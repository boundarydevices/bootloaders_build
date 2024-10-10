#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "$0")")
source "${SRC}/build_ddr_loader.sh"
source "${SRC}/build_uboot_spl.sh"
source "${SRC}/secure.sh"
source "${SRC}/utils.sh"

function da_create_binary {
    local mode="$2"
    local out_dir="$3"
    local spl_size_max=$(config_value "$1" mtk_boot.spl_size_max)
    local ddr_loader_bin="${out_dir}/ddr-loader.bin"
    local uboot_spl_out_bin="${UBOOT}/spl/u-boot-spl.bin"

    if ! [ -a "${ddr_loader_bin}" ]; then
        error_exit "DDR loader not found"
    fi

    if ! [ -a "${uboot_spl_out_bin}" ]; then
        error_exit "U-Boot SPL not found"
    fi

    # Factory Mode: U-Boot SPL must be truncated to maximum size
    if [[ "${mode}" == "factory" ]]; then
        truncate --size="${spl_size_max}" "${uboot_spl_out_bin}"
    fi

    cat "${ddr_loader_bin}" "${uboot_spl_out_bin}" > "${out_dir}/da-${mode}.bin"
    rm "${ddr_loader_bin}"
}

function build_da {
    local mode="$3"
    local out_dir=$(out_dir "$1" "${mode}")

    display_current_build "$1" "da" "${mode}"

    ! [ -d "${out_dir}" ] && mkdir -p "${out_dir}"

    build_ddr_loader "$1" "$2" "$3"

    build_uboot_spl "$1" "$2" "$3" "true"

    da_create_binary "$1" "${mode}" "${out_dir}"
    if [[ "${mode}" == "factory" ]]; then
        sign_da "${out_dir}/da-${mode}.bin" "${out_dir}/da-${mode}.sign"
    fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
