#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "$0")")
source "${SRC}/utils.sh"

LIBATF="${ROOT}/libatf"

function get_libatf_customer {
    local customer_config=$(config_value "$1" customer_config)
    local board="$2"
    local libatf_customer=""

    if [ -n "${customer_config}" ]; then
        local libatf="${ROOT}/${customer_config}/libatf/${board}"
        if [ -d "${libatf}" ]; then
            libatf_customer="${libatf}";
        fi
    fi

    echo "${libatf_customer}"
}

function clean_libatf {
    local mtk_build="$1"
    if [ -d "${mtk_build}" ]; then
        rm -r "${mtk_build}"
    fi
}

function get_libatf {
    local board=$(board_name "$1")
    local clean="$2"
    local mode="$3"
    local -n libatf_a_ref="$4"
    local libatf_board=$(config_value "$1" libatf.board)
    local libatf_plat=$(config_value "$1" libatf.plat)
    local libatf_a=""

    if [ ! -z "${libatf_board}" ]; then
        board=${libatf_board}
    fi

    if [ -d "${LIBATF}" ]; then
        libatf_a="${LIBATF}/build-${board}/src/${libatf_plat}/libatf.a"
        if [[ "${clean}" == true ]]; then
            build_libatf "$1" true "${mode}"
        else
            # check if libatf has been compiled
            ! [ -a "${libatf_a}" ] && build_libatf "$1" false "${mode}"
        fi
    else
        libatf_a="${ROOT}/libatf-prebuilt/${board}/libatf.a"
    fi

    libatf_a_ref="${libatf_a}"
}

function build_libatf {
    local board=$(board_name "$1")
    local mtk_build="build-${board}"
    local clean="${2:-false}"
    local mode="${3:-release}"
    local libatf_customer=$(get_libatf_customer "$1" "${board}")
    local build="libatf"
    local extra_flags=""

    display_current_build "$1" "${build}" "${mode}"

    pushd "${LIBATF}"

    [[ "${clean}" == true ]] && clean_libatf "${mtk_build}"

    if [ -n "${libatf_customer}" ]; then
        if [[ "${clean}" == true ]] && [ -d "boards/${board}" ]; then
            rm -r "boards/${board}"
        fi
        ln -snf "${libatf_customer}" "boards/${board}"
    fi

    aarch64_env

    meson "${mtk_build}" -Dboard="${board}" -Datf_root="${ROOT}/arm-trusted-firmware" \
          ${extra_flags} --cross-file "${SRC}/config/meson.cross"
    ninja -C "${mtk_build}"

    clear_vars
    popd
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
