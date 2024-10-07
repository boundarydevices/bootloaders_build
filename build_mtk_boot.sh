#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "$0")")
source "${SRC}/build_ddr_loader.sh"
source "${SRC}/build_uboot_spl.sh"
source "${SRC}/secure.sh"
source "${SRC}/utils.sh"

function mtk_boot_create_factory_binary {
    local mtk_plat=$(config_value "$1" plat)
    local secure_config=$(get_secure_config "$1")
    local mode="$2"
    local out_dir=$(out_dir "$1" "${mode}")
    local spl_size_max=$(config_value "$1" mtk_boot.spl_size_max)
    local mtk_boot_bin="${out_dir}/mtk-boot-${mode}.bin"
    local ddr_loader_bin="${out_dir}/ddr-loader.bin"
    local uboot_spl_nodtb_out_bin="${out_dir}/u-boot-spl-nodtb.bin"
    local uboot_spl_dtb_out_bin="${out_dir}/u-boot-spl.dtb"
    local uboot_spl_out_bin="${out_dir}/u-boot-spl.bin"

    if ! [ -a "${ddr_loader_bin}" ]; then
        error_exit "DDR loader not found"
    fi

    if ! [ -a "${uboot_spl_nodtb_out_bin}" ]; then
        error_exit "U-Boot SPL (nodtb) not found"
    fi

    if ! [ -a "${uboot_spl_dtb_out_bin}" ]; then
        error_exit "U-Boot SPL DTB not found"
    fi

    # create U-Boot SPL
    cat "${uboot_spl_nodtb_out_bin}" "${uboot_spl_dtb_out_bin}" > "${uboot_spl_out_bin}"
    truncate --size="${spl_size_max}" "${uboot_spl_out_bin}"
    rm "${uboot_spl_nodtb_out_bin}" "${uboot_spl_dtb_out_bin}"

    # create mtk-boot
    cat "${ddr_loader_bin}" "${uboot_spl_out_bin}" > "${out_dir}/mtk-boot-input.bin"
    rm "${ddr_loader_bin}" "${uboot_spl_out_bin}"

    # sign mtk-boot
    sign_mtk_boot "${secure_config}" "${out_dir}/mtk-boot-input.bin" "${mtk_boot_bin}"
    rm "${out_dir}/mtk-boot-input.bin"
}

function mtk_boot_create_binary {
    local mtk_plat=$(config_value "$1" plat)
    local out_dir="$2"
    local ddr_loader_bin="${out_dir}/ddr-loader.bin"
    local uboot_spl_out_bin="${UBOOT}/spl/u-boot-spl.bin"

    if ! [ -a "${ddr_loader_bin}" ]; then
        error_exit "DDR loader not found"
    fi

    if ! [ -a "${uboot_spl_out_bin}" ]; then
        error_exit "U-Boot SPL not found"
    fi

    cat "${ddr_loader_bin}" "${uboot_spl_out_bin}" > "${out_dir}/mtk-boot-input.bin"
    rm "${ddr_loader_bin}"
}

function build_mtk_boot {
    local mode="$3"
    local out_dir=$(out_dir "$1" "${mode}")
    local mtk_boot_bin="${out_dir}/mtk-boot-${mode}.bin"
    local secure_config=$(get_secure_config "$1")

    display_current_build "$1" "mtk-boot" "${mode}"

    ! [ -d "${out_dir}" ] && mkdir -p "${out_dir}"

    build_ddr_loader "$1" "$2" "$3"

    build_uboot_spl "$1" "$2" "$3" "false"

    # Factory mode:
    # The device tree of SPL binary will contain the signature to verify each
    # components inside the bootloader image.
    # This device tree can be updated ONLY when we generate the bootloader image.
    # Thus in factory mode we cannot create yet mtk-boot.bin, build_bootloader
    # will create and sign mtk-boot.
    if [[ "${mode}" == "factory" ]] && [ -n "${secure_config}" ]; then
        uboot_spl_copy_binaries_out "${out_dir}"
        warning "Factory mode: please run build_bootloaders to generate mtk-boot binary"
    else
        mtk_boot_create_binary "$1" "${out_dir}"
        "${SRC}/mkimage" -T mtk_image -a 0x201000 -e 0x201000 -n "media=emmc;aarch64=1" \
                         -d "${out_dir}/mtk-boot-input.bin" "${mtk_boot_bin}"
        rm "${out_dir}/mtk-boot-input.bin"
    fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
