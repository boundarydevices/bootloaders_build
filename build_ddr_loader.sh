#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "$0")")
source "${SRC}/build_libatf.sh"
source "${SRC}/utils.sh"

DDR_LOADER="${ROOT}/ddr-loader"
DDR_SIZE_MAX=$((120 * 1024)) # 120 Ko

function clean_ddr {
    local mtk_plat="$1"
    if [ -d "build/${mtk_plat}" ]; then
        rm -r "build/${mtk_plat}"
    fi
}

function build_ddr_loader {
    local board=$(board_name "$1")
    local mtk_plat=$(config_value "$1" plat)
    local libatf_a="${LIBATF}/build-${board}/src/${mtk_plat}/libatf.a"
    local clean="${2:-false}"
    local mode="${3:-release}"
    local out_dir=$(out_dir "$1" "${mode}")
    local ddr_out_dir="build/${mtk_plat}/release"
    local ddr_size=0

    display_current_build "$1" "ddr-loader" "${mode}"

    if [[ "${clean}" == true ]]; then
        build_libatf "$1" true "${mode}"
    else
        # check if libatf has been compiled
        ! [ -a "${libatf_a}" ] && build_libatf "$1" false "${mode}"
    fi

    pushd "${DDR_LOADER}"
    [[ "${clean}" == true ]] && clean_ddr "${mtk_plat}"

    aarch64_env

    make E=0 PLAT="${mtk_plat}" \
         DEBUG=0 LOG_LEVEL=10 \
         BL2_LDFLAGS="--whole-archive" \
         BL2_LIBS="${libatf_a}" \
         bl2

    pushd "${ddr_out_dir}"

    # check ddr size
    ddr_size=$(stat --printf="%s" bl2.bin)
    if (( ddr_size > DDR_SIZE_MAX)); then
        error_exit "DDR size exceed the limit: ${DDR_SIZE_MAX}"
    fi

    cp bl2.bin "${out_dir}/ddr-loader.bin"
    truncate "--size=${DDR_SIZE_MAX}" "${out_dir}/ddr-loader.bin"

    popd

    clear_vars
    popd
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
