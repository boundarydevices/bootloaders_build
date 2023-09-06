#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "$0")")
source "${SRC}/utils.sh"

SECURE_TOOLS="${ROOT}/mtk-secure-boot-tools"
KEYS="${BUILD}/.keys"

# Secure: BL1 to U-Boot SPL
EFUSE_KEY="efuse.key"
DA_KEY="da.key"
MTK_DA_SIGNED="MTK_AllInOne_DA_signed.bin"
AUTH_KEY="auth_sv5.auth"

# Secure: U-Boot SPL to bootloaders image
BOOTLOADERS_KEY="bootloaders.key"
BOOTLOADERS_CRT="bootloaders.crt"

# Trusted Applications
TA_KEY="ta.key"
TA_PUB_KEY="ta_pub.key"

# Android Verified Boot (AVB)
AVB_KEY="avb.key"
AVB_PUB_KEY="avb_pub.key"

function get_secure_config {
    local board=$(board_name "$1")
    local secure_config=""

    if [ -d "${SECURE_TOOLS}/configs/${board}" ]; then
        secure_config="${SECURE_TOOLS}/configs/${board}";
    else
        local customer_config=$(config_value "$1" customer_config)
        if [ -n "${customer_config}" ]; then
            local customer_secure="${ROOT}/${customer_config}/secure/${board}"
            if [ -d "${customer_secure}" ]; then
                secure_config="${customer_secure}";
            fi
        fi
    fi

    echo "${secure_config}"
}

function generate_bootloaders_key {
    ! [ -d "${KEYS}" ] && mkdir -p "${KEYS}"

    openssl genpkey -algorithm RSA -out "${KEYS}/${BOOTLOADERS_KEY}" \
            -pkeyopt rsa_keygen_bits:2048 -pkeyopt rsa_keygen_pubexp:65537
}

function get_bootloaders_key_dir {
    local bootloaders_key_dir_config=$(config_value "$1" secure.bootloaders_key_dir)
    local -n bootloaders_key_dir_ref="$2"

    if [ -n "${bootloaders_key_dir_config}" ]; then
        if [ -a "${bootloaders_key_dir_config}/${BOOTLOADERS_KEY}" ]; then
            bootloaders_key_dir_ref="${bootloaders_key_dir_config}"
        else
            error_exit "Bootloaders key not found: ${bootloaders_key_dir_config}/${BOOTLOADERS_KEY}"
        fi
    else
        if ! [ -a "${KEYS}/${BOOTLOADERS_KEY}" ]; then
            echo "No bootloaders key found, generate new one ..."
            generate_bootloaders_key
        fi
        bootloaders_key_dir_ref="${KEYS}"
    fi

    if ! [ -a "${bootloaders_key_dir_ref}/${BOOTLOADERS_CRT}" ]; then
        openssl req -batch -new -x509 \
                -key "${bootloaders_key_dir_ref}/${BOOTLOADERS_KEY}" \
                -out "${bootloaders_key_dir_ref}/${BOOTLOADERS_CRT}"
    fi
}

function get_ta_keys {
    local ta_key_config=$(config_value "$1" secure.ta_key)
    local -n ta_key_ref="$2"
    local ta_pub_key_config=$(config_value "$1" secure.ta_pub_key)
    local -n ta_pub_key_ref="$3"

    # check private/public keys in config
    if [ -n "${ta_key_config}" ]; then
        if [ -a "${ta_key_config}" ]; then
            ta_key_ref="${ta_key_config}"
        else
            error_exit "TA key not found: ${ta_key_config}"
        fi
    fi

    if [ -n "${ta_pub_key_config}" ]; then
        if [ -a "${ta_pub_key_config}" ]; then
            ta_pub_key_ref="${ta_pub_key_config}"
        else
            error_exit "TA public key not found: ${ta_pub_key_config}"
        fi
    fi

    [ -n "${ta_key_ref}" ] && [ -n "${ta_pub_key_ref}" ] && return

    # check private/public keys under ${KEYS}
    if [ -a "${KEYS}/${TA_KEY}" ] && [ -a "${KEYS}/${TA_PUB_KEY}" ]; then
        ta_key_ref="${KEYS}/${TA_KEY}"
        ta_pub_key_ref="${KEYS}/${TA_PUB_KEY}"
    fi
}

function generate_ta_keys {
    local ta_key="${KEYS}/${TA_KEY}"
    local ta_pub_key="${KEYS}/${TA_PUB_KEY}"

    ! [ -d "${KEYS}" ] && mkdir -p "${KEYS}"

    openssl genrsa -out "${ta_key}" 4096
    openssl rsa -in "${ta_key}" -out "${ta_pub_key}" --pubout

    printf "TA keys generated here:\n%s\n%s\n" "${ta_key}" "${ta_pub_key}"
}

function get_avb_key {
    local avb_key_config=$(config_value "$1" secure.avb_key)
    local -n avb_key_ref="$2"

    if [ -n "${avb_key_config}" ]; then
        if [ -a "${avb_key_config}" ]; then
            avb_key_ref="${avb_key_config}"
        else
            error_exit "AVB key not found: ${avb_key_config}"
        fi
    else
        if [ -a "${KEYS}/${AVB_KEY}" ]; then
            avb_key_ref="${KEYS}/${AVB_KEY}"
        fi
    fi
}

function get_avb_pub_key {
    local avb_pub_key_config=$(config_value "$1" secure.avb_pub_key)
    local -n avb_pub_key_ref="$2"

    if [ -n "${avb_pub_key_config}" ]; then
        if [ -a "${avb_pub_key_config}" ]; then
            avb_pub_key_ref="${avb_pub_key_config}"
        else
            error_exit "AVB public key not found: ${avb_pub_key_config}"
        fi
    else
        if [ -a "${KEYS}/${AVB_PUB_KEY}" ]; then
            avb_pub_key_ref="${KEYS}/${AVB_PUB_KEY}"
        fi
    fi
}

function generate_avb_keys {
    local avb_key="${KEYS}/${AVB_KEY}"
    local avb_pub_key="${KEYS}/${AVB_PUB_KEY}"

    ! [ -d "${KEYS}" ] && mkdir -p "${KEYS}"

    openssl genrsa -out "${avb_key}" 4096
    avbtool extract_public_key --key "${avb_key}" --output "${avb_pub_key}"

    printf "AVB keys generated here:\n%s\n%s\n" "${avb_key}" "${avb_pub_key}"
}

function generate_efuse_key {
    ! [ -d "${KEYS}" ] && mkdir -p "${KEYS}"
    openssl genrsa -out "${KEYS}/${EFUSE_KEY}" 2048
}

function check_efuse_key {
    if [ -a "${KEYS}/${EFUSE_KEY}" ]; then
        echo "EFUSE key found: ${KEYS}/${EFUSE_KEY}"
    else
        echo "EFUSE key not found, generate new one ..."
        generate_efuse_key
    fi
}

function generate_da_key {
    ! [ -d "${KEYS}" ] && mkdir -p "${KEYS}"
    openssl genrsa -out "${KEYS}/${DA_KEY}" 2048
}

function check_da_key {
    if [ -a "${KEYS}/${DA_KEY}" ]; then
        echo "Download Agent key found: ${KEYS}/${DA_KEY}"
    else
        echo "Download Agent key not found, generate new one ..."
        generate_da_key
    fi
}

function daa_supported {
    local secure_config="$1"
    local toolauth_gfh_config_pss="${secure_config}/toolauth_gfh_config_pss.ini"
    local bbchips_pss="${secure_config}/bbchips_pss.ini"

    [ -a "${toolauth_gfh_config_pss}" ] && [ -a "${bbchips_pss}" ]
}

function sign_mmcboot {
    local secure_config="$1"
    local input="$2"
    local output="$3"
    local output_dir=$(dirname "${output}")
    local pbp_py="${SECURE_TOOLS}/sign-image_v2/pbp.py"
    local hdr_tool_py="${SECURE_TOOLS}/secure_chip_tools/dev-info-hdr-tool.py"
    local key_ini="${SECURE_TOOLS}/configs/key.ini"
    local pl_gfh="${secure_config}/pl_gfh_config_pss.ini"

    pushd "${KEYS}"

    check_efuse_key

    # update key.ini with efuse key
    cp "${key_ini}" key.ini
    sed -i 's|EFUSE_KEY|'${KEYS}/${EFUSE_KEY}'|g' key.ini

    python "${pbp_py}" -i key.ini -g "${pl_gfh}" -func sign -o "${output}" "${input}"
    python "${hdr_tool_py}" emmc "${output}" "${output}"
    rm key.ini "${output_dir}/sig_size.txt"

    popd
}

function sign_da {
    local input="$1"
    local output="$2"
    local input_digest="da_digest"

    check_da_key

    cat "${input}" | openssl dgst -binary -sha256 > "${input_digest}"
    openssl pkeyutl -sign -inkey "${KEYS}/${DA_KEY}" -in "${input_digest}" -out "${output}" -pkeyopt digest:sha256 -pkeyopt rsa_padding_mode:pss -pkeyopt rsa_pss_saltlen:32

    rm "${input_digest}"
}

function resign_da {
    local secure_config="$1"
    local mtk_plat="$2"
    local resign_da_py="${SECURE_TOOLS}/secure_chip_tools/resign_da.py"
    local bbchips_pss="${secure_config}/bbchips_pss.ini"
    local mtk_all_da="${SECURE_TOOLS}/configs/MTK_AllInOne_DA_Win.bin"

    # update bbchips_pss.ini with download agent key
    cp "${bbchips_pss}" bbchips_pss.ini
    sed -i 's|DA_KEY|'${KEYS}/${DA_KEY}'|g' bbchips_pss.ini

    python "${resign_da_py}" "${mtk_all_da}" "${mtk_plat^^}" bbchips_pss.ini all "${MTK_DA_SIGNED}"
    rm bbchips_pss.ini
}

function generate_auth_file {
    local secure_config="$1"
    local toolauth_py="${SECURE_TOOLS}/secure_chip_tools/toolauth.py"
    local toolauth_gfh_config_pss="${secure_config}/toolauth_gfh_config_pss.ini"
    local key_ini="${SECURE_TOOLS}/configs/key.ini"

    # update key.ini with efuse key
    cp "${key_ini}" key.ini
    sed -i 's|EFUSE_KEY|'${KEYS}/${EFUSE_KEY}'|g' key.ini

    # update toolauth_gfh_config_pss.ini with download agent key
    cp "${toolauth_gfh_config_pss}" toolauth_gfh_config_pss.ini
    sed -i 's|DA_KEY|'${KEYS}/${DA_KEY}'|g' toolauth_gfh_config_pss.ini

    python "${toolauth_py}" -i key.ini -g toolauth_gfh_config_pss.ini "${AUTH_KEY}"
    rm key.ini toolauth_gfh_config_pss.ini
}

function get_efuse_pub_key {
    local -n ref_efuse_pub_key="$1"
    local der_extractor="${SECURE_TOOLS}/sign-image_v2/der_extractor/der_extractor"
    local efuse_pub_key="${EFUSE_KEY}_pub.der"
    local efuse_key_h="efuse_key.h"

    # public efuse key
    openssl rsa -in "${KEYS}/${EFUSE_KEY}" -out "${efuse_pub_key}" -outform DER --pubout

    # header file
    chmod +x "${der_extractor}"
    "${der_extractor}" "${efuse_pub_key}" "${efuse_key_h}" ANDROID_SBC

    # extract public key
    ref_efuse_pub_key=$(cat "${efuse_key_h}" | perl -0777 -ne '$_=$1 if /(?:PUBK\s+)(.*(\\)?\n)+#endif/s; s/([\\\n, ]|0x)//g; print')

    rm "${efuse_pub_key}" "${efuse_key_h}"
}

function update_efuse_xml {
    local secure_config="$1"
    local pub_key_n=""

    cp "${secure_config}/efuse.xml" efuse.xml

    # fill public key
    get_efuse_pub_key pub_key_n
    sed -i 's/EFUSE_PUB_KEY/'${pub_key_n}'/' efuse.xml
}

function add_secure_boot_files {
    local package="$1"
    local secure_config="$2"
    local board="$3"
    local mtk_plat="$4"

    # add efuse configuration
    update_efuse_xml "${secure_config}"
    zip -ju "${package}" efuse.xml
    rm efuse.xml

    # add efuse private key
    zip -ju "${package}" "${KEYS}/${EFUSE_KEY}"

    # add secure board files
    zip -ju "${package}" "${secure_config}/${board}_android_scatter.txt"
    zip -ju "${package}" "${secure_config}/${board}_preloader.bin"

    # Download Agent Authentification
    if daa_supported "${secure_config}"; then
        # Download Agent key
        check_da_key
        zip -ju "${package}" "${DA_KEY}"

        # MTK_AllInOne_DA signed
        resign_da "${secure_config}" "${mtk_plat}"
        zip -ju "${package}" "${MTK_DA_SIGNED}"
        rm "${MTK_DA_SIGNED}"

        # authentication file
        generate_auth_file "${secure_config}"
        zip -ju "${package}" "${AUTH_KEY}"
    else
        warning "DAA not supported for ${board}"
    fi
}

function generate_secure_package {
    local board=$(board_name "$1")
    local mtk_plat=$(config_value "$1" plat)
    local secure_config=$(get_secure_config "$1")
    local out_dir="$2"
    local package="secure_${board}.zip"

    pushd "${KEYS}"
    [ -a "${package}" ] && rm "${package}"

    # add bootloaders key and crt
    local bootloaders_key_dir=""
    get_bootloaders_key_dir "$1" bootloaders_key_dir
    zip -ju "${package}" "${bootloaders_key_dir}/bootloaders.key" \
                         "${bootloaders_key_dir}/bootloaders.crt"

    # add Trusted Applications keys
    local ta_key=""
    local ta_pub_key=""
    get_ta_keys "$1" ta_key ta_pub_key
    if [ -n "${ta_key}" ]; then
        zip -ju "${package}" "${ta_key}"
    fi
    if [ -n "${ta_pub_key}" ]; then
        zip -ju "${package}" "${ta_pub_key}"
    fi

    # add Android Verified Boot keys
    local avb_key=""
    local avb_pub_key=""
    get_avb_key "$1" avb_key
    if [ -n "${avb_key}" ]; then
        zip -ju "${package}" "${avb_key}"
    fi
    get_avb_pub_key "$1" avb_pub_key
    if [ -n "${avb_pub_key}" ]; then
        zip -ju "${package}" "${avb_pub_key}"
    fi

    # add Secure Boot files
    if [ -n "${secure_config}" ]; then
        add_secure_boot_files "${package}" "${secure_config}" "${board}" "${mtk_plat}"
    else
        warning "Secure boot not supported for ${board}"
    fi

    mv "${package}" "${AUTH_KEY}" "${out_dir}/"

    popd
}

# main
function usage {
    cat <<DELIM__
usage: $(basename "$0") function

Functions supported can be found in "$0"
DELIM__
}

function main {
    if ! [ $# -eq 1 ]; then
        usage
    else
        local command="$1"
        "${command}"
    fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
