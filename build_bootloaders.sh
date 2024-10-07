#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "$0")")
source "${SRC}/build_bl31.sh"
source "${SRC}/build_mtk_boot.sh"
source "${SRC}/build_optee.sh"
source "${SRC}/build_uboot.sh"
source "${SRC}/secure.sh"
source "${SRC}/utils.sh"

function bootloaders_factory_image {
    local config="$1"
    local mode="$2"
    local out_dir=$(out_dir "$1" "${mode}")
    local its="${BUILD}/config/u-boot/bootloaders-factory.its"
    local uboot_spl_dtb_out_bin="${out_dir}/u-boot-spl.dtb"
    local bootloaders_key_dir=""

    if ! [ -a "${uboot_spl_dtb_out_bin}" ]; then
        error_exit "U-Boot SPL DTB not found"
    fi

    get_bootloaders_key_dir "$1" bootloaders_key_dir

    cp "${BUILD}/config/u-boot/bootloaders-factory.its" "${out_dir}/bootloaders.its"

    "${UBOOT}/tools/mkimage" -r \
                             -f "${out_dir}/bootloaders.its" \
                             -K "${uboot_spl_dtb_out_bin}" \
                             -k "${bootloaders_key_dir}" \
                             "${out_dir}/bootloaders-factory.img"

    mtk_boot_create_factory_binary "${config}" "${mode}"
}

function build_bootloaders {
    local mtk_plat=$(config_value "$1" plat)
    local mode="$3"
    local out_dir=$(out_dir "$1" "${mode}")

    display_current_build "$1" "bootloaders" "${mode}"

    ! [ -d "${out_dir}" ] && mkdir -p "${out_dir}"

    # Booloaders components
    build_bl31 "$1" "$2" "$3"
    build_optee "$1" "$2" "$3"
    build_uboot "$1" "$2" "$3"

    # Generate bootloaders image
    if [[ "${mode}" == "factory" ]]; then
        bootloaders_factory_image "$1" "${mode}"
    else
        cp "${BUILD}/config/u-boot/bootloaders.its" "${out_dir}/bootloaders.its"
        "${UBOOT}/tools/mkimage" -f "${out_dir}/bootloaders.its" \
                                 "${out_dir}/bootloaders-${mode}.img"
    fi

    # remove inputs from out dir
    rm "${out_dir}/bootloaders.its"
    rm "${out_dir}/bl31.bin" "${out_dir}/tee.bin" "${out_dir}/u-boot.bin"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
