#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "$0")")
source "${SRC}/secure.sh"
source "${SRC}/build_libatf.sh"
source "${SRC}/utils.sh"

ATF="${ROOT}/arm-trusted-firmware"

function clean_bl31 {
    local mtk_plat="$1"
    if [ -d "build/${mtk_plat}" ]; then
        rm -r "build/${mtk_plat}"
    fi
}

function build_bl31 {
    local board=$(board_name "$1")
    local mtk_plat=$(config_value "$1" plat)
    local out_dir=$(out_dir "$1" "${mode}")
    local clean="$2"
    local mode="$3"
    local libatf_a="${LIBATF}/build-${board}/src/${mtk_plat}/libatf.a"
    local libbase_a="${ROOT}/libbase-prebuilts/${mtk_plat}/libbase.a"
    local bl31_flags=""
    local bl31_out_dir=""

    display_current_build "$1" "BL31" "${mode}"

    ! [ -d "${out_dir}" ] && mkdir -p "${out_dir}"

    bl31_flags+=" E=0"
    bl31_flags+=" PLAT=${mtk_plat}"
    bl31_flags+=" NEED_BL32=yes SPD=opteed"
    bl31_flags+=" ENABLE_LTO=1"

    if [[ "${mode}" == "debug" ]]; then
        bl31_flags+=" DEBUG=1 log_level=20"
    else
        bl31_flags+=" DEBUG=0 log_level=0"
    fi

    if [[ "${mode}" == "debug" ]]; then
        bl31_out_dir="${ATF}/build/${mtk_plat}/debug"
    else
        bl31_out_dir="${ATF}/build/${mtk_plat}/release"
    fi

    if [[ "${clean}" == true ]]; then
        build_libatf "$1" true "${mode}"
    else
        # check if libatf has been compiled
        ! [ -a "${libatf_a}" ] && build_libatf "$1" false "${mode}"
    fi

    pushd "${ATF}"
    [[ "${clean}" == true ]] && clean_bl31 "${mtk_plat}"

    arm-none_env

    make BL31_LIBS="${libatf_a} ${libbase_a}" ${bl31_flags} bl31
    cp "${bl31_out_dir}/bl31.bin" "${out_dir}"

    clear_vars
    popd
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
