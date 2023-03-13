#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "$0")")
source "${SRC}/build_libatf.sh"
source "${SRC}/secure.sh"
source "${SRC}/utils.sh"

MBEDTLS="${ROOT}/mbedtls"

function clean_bl2 {
    local mtk_plat="$1"
    if [ -d "build/${mtk_plat}" ]; then
        rm -r "build/${mtk_plat}"
    fi
}

function bl2_create_image {
    local bl2_tmp="bl2.img.tmp"

    cp bl2.bin "${bl2_tmp}"
    truncate -s%4 "${bl2_tmp}"
    "${SRC}/mkimage" -T mtk_image -a 0x201000 -e 0x201000 -n "media=emmc;aarch64=1" \
                     -d "${bl2_tmp}" bl2.img

    rm "${bl2_tmp}"
}

function build_bl2 {
    local board=$(board_name "$1")
    local mtk_plat=$(config_value "$1" plat)
    local atf_project=$(config_value "$1" bl2.project)
    local mtk_cflags=$(config_value "$1" bl2.cflags)
    local libatf_a="${LIBATF}/build-${board}/src/${mtk_plat}/libatf.a"
    local libbase_a="${ROOT}/libbase-prebuilts/${mtk_plat}/libbase.a"
    local clean="${2:-false}"
    local mode="${3:-release}"
    local out_dir=$(out_dir "$1" "${mode}")
    local secure_config=$(get_secure_config "$1")
    local bl2_out_dir=""
    local extra_flags=""

    display_current_build "$1" "bl2" "${mode}"

    if [[ "${mode}" == "debug" ]]; then
        extra_flags="DEBUG=1"
        bl2_out_dir="build/${mtk_plat}/debug"
    else
        extra_flags="DEBUG=0"
        bl2_out_dir="build/${mtk_plat}/release"
    fi

    if [[ "${mode}" == "factory" ]]; then
        local rot_key=""
        get_rot_key "$1" rot_key
        extra_flags+=" MBEDTLS_DIR=${MBEDTLS} TRUSTED_BOARD_BOOT=1 GENERATE_COT=1"
        extra_flags+=" ROT_KEY=${rot_key}"
    fi

    ! [ -d "${out_dir}" ] && mkdir -p "${out_dir}"

    if [[ "${clean}" == true ]]; then
        build_libatf "$1" true false "${mode}"
    else
        # check if libatf has been compiled
        ! [ -a "${libatf_a}" ] && build_libatf "$1" false false "${mode}"
    fi

    pushd "${ROOT}/${atf_project}"
    [[ "${clean}" == true ]] && clean_bl2 "${mtk_plat}"

    aarch64_env

    make E=0 CFLAGS="${mtk_cflags}" PLAT="${mtk_plat}" \
         BL2_LDFLAGS="--whole-archive" \
         BL2_LIBS="${libatf_a} ${libbase_a}" \
         ${extra_flags} bl2

    pushd "${bl2_out_dir}"
    if [[ "${mode}" == "factory" ]] && [ -n "${secure_config}" ]; then
        sign_bl2_image "${secure_config}" "${PWD}/bl2.bin" "${PWD}/bl2.img"
    else
        bl2_create_image
    fi
    cp bl2.img "${out_dir}/bl2-${mode}.img"
    popd

    clear_vars
    popd
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
