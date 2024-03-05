#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "$0")")
source "${SRC}/secure.sh"
source "${SRC}/utils.sh"

UBOOT="${ROOT}/u-boot"

function clean_uboot {
    make mrproper
}

function merge_config {
    local mode="${1}"
    local board="${2}"
    local config_root="${3}"
    local mode_fragment="${BUILD}/config/u-boot/${mode}.config"
    local board_fragment="${config_root}/u-boot/${board}.config"
    declare -a configs

    if [ -a "${mode_fragment}" ]; then
        configs+=("${mode_fragment}")
    fi

    if [ -a "${board_fragment}" ]; then
        configs+=("${board_fragment}")
    fi

    if [[ "${configs[*]}" ]]; then
        scripts/kconfig/merge_config.sh .config "${configs[*]}"
    fi
}

function build_uboot {
    local config_root=$(config_root "$1")
    local uboot_board=$(config_value "$1" uboot.board)
    local board="${uboot_board:-$(board_name "$1")}"
    local clean="${2:-false}"
    local mode="${3:-release}"
    local out_dir=$(out_dir "$1" "${mode}")
    local mtk_defconfig=$(config_value "$1" uboot.defconfig)

    display_current_build "${board}" "uboot" "${mode}"

    if [ -z "${mtk_defconfig}" ]; then
        echo "uboot: skip build, defconfig not provided"
        return
    fi

    ! [ -d "${out_dir}" ] && mkdir -p "${out_dir}"

    pushd "${UBOOT}"
    [[ "${clean}" == true ]] && clean_uboot

    aarch64_env
    export ARCH=arm64

    # create symlink to config board
    if [ -d "${config_root}/u-boot/${board}/board" ]; then
        ln -snf "${config_root}/u-boot/${board}/board" "${UBOOT}/board/mediatek/${board}"
    fi

    # create symlink to config dts
    if [ -d "${config_root}/u-boot/${board}/dts" ]; then
        pushd "${config_root}/u-boot/${board}/dts/"
        for dts in *; do
            ln -sf "${config_root}/u-boot/${board}/dts/${dts}" "${UBOOT}/arch/arm/dts/"
        done
        popd
    fi

    # generate defconfig
    make "${mtk_defconfig}"
    merge_config "${mode}" "${board}" "${config_root}"

    # avb key only on release/factory
    if ! [[ "${mode}" == "debug" ]]; then
        local avb_pub_key=""
        get_avb_pub_key "$1" avb_pub_key
        if [ -n "${avb_pub_key}" ]; then
            cp "${avb_pub_key}" "${mtk_defconfig}.avbpubkey"
            avb_pub_key="${mtk_defconfig}.avbpubkey"
            sed -i 's/^\(CONFIG_AVB_PUBKEY_FILE=\).*/\1\"'${avb_pub_key}'\"/' .config
        fi
    fi

    make -j"$(nproc)"

    ./scripts/get_default_envs.sh > "${out_dir}/u-boot-initial-${mode}-env"
    cp u-boot.bin "${out_dir}"

    unset ARCH
    clear_vars
    popd
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
