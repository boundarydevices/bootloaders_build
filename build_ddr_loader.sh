#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "$0")")
source "${SRC}/build_libatf.sh"
source "${SRC}/utils.sh"

DDR_LOADER="${ROOT}/ddr-loader"

function clean_ddr {
    local ddr_loader_plat="$1"
    if [ -d "build/${ddr_loader_plat}" ]; then
        rm -r "build/${ddr_loader_plat}"
    fi
}

function build_ddr_loader {
    local ddr_loader_plat=$(config_value "$1" ddr_loader.plat)
    local libatf=""
    local clean="${2:-false}"
    local mode="${3:-release}"
    local out_dir=$(out_dir "$1" "${mode}")
    local ddr_out_dir="build/${ddr_loader_plat}/release"
    local ddr_size_max=$(config_value "$1" mtk_boot.ddr_size_max)
    local spl_size_max=$(config_value "$1" mtk_boot.spl_size_max)
    local ddr_size=0

    [ -z "${ddr_size_max}" ] && error_usage_exit "DDR size max not set in $1"
    [ -z "${spl_size_max}" ] && error_usage_exit "SPL size max not set in $1"

    display_current_build "$1" "ddr-loader" "${mode}"

    ! [ -d "${out_dir}" ] && mkdir -p "${out_dir}"

    get_libatf "$1" "${clean}" "${mode}" libatf

    pushd "${DDR_LOADER}"
    [[ "${clean}" == true ]] && clean_ddr "${ddr_loader_plat}"

    aarch64_env

    make E=0 PLAT="${ddr_loader_plat}" \
         DEBUG=0 LOG_LEVEL=10 \
         BL2_CFLAGS="-DSPL_OFFSET=\"${ddr_size_max}\" -DSPL_SIZE=\"${spl_size_max}\"" \
         BL2_LDFLAGS="--whole-archive" \
         BL2_LIBS="${libatf}" \
         bl2

    pushd "${ddr_out_dir}"

    # check ddr size
    ddr_size=$(stat --printf="%s" bl2.bin)
    if (( ddr_size > ddr_size_max)); then
        error_exit "DDR size exceed the limit: ${ddr_size} > ${ddr_size_max}"
    fi

    cp bl2.bin "${out_dir}/ddr-loader.bin"
    truncate "--size=${ddr_size_max}" "${out_dir}/ddr-loader.bin"

    popd

    clear_vars
    popd
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
