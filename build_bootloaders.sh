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
    local bootloaders_its="$3"
    local out_dir=$(out_dir "$1" "${mode}")
    local uboot_spl_dtb_out_bin="${out_dir}/u-boot-spl.dtb"
    local bootloaders_key_dir=""

    if ! [ -a "${uboot_spl_dtb_out_bin}" ]; then
        error_exit "U-Boot SPL DTB not found"
    fi

    get_bootloaders_key_dir "$1" bootloaders_key_dir

    cp "${bootloaders_its}" "${out_dir}/bootloaders.its"

    "${UBOOT}/tools/mkimage" -r \
                             -f "${out_dir}/bootloaders.its" \
                             -K "${uboot_spl_dtb_out_bin}" \
                             -k "${bootloaders_key_dir}" \
                             "${out_dir}/bootloaders-factory.img"

    mtk_boot_create_factory_binary "${config}" "${mode}"
}

function build_bootloaders {
    local mode="$3"
    local uboot_plat=$(config_value "$1" uboot.plat)
    local out_dir=$(out_dir "$1" "${mode}")
    local bootloaders_its=""

    display_current_build "$1" "bootloaders" "${mode}"

    ! [ -d "${out_dir}" ] && mkdir -p "${out_dir}"

    # Booloaders components
    build_bl31 "$1" "$2" "$3"
    build_optee "$1" "$2" "$3"
    build_uboot "$1" "$2" "$3"

    # Generate bootloaders image
    if [[ "${mode}" == "factory" ]]; then
        bootloaders_its="${BUILD}/config/u-boot/${uboot_plat}/bootloaders-factory.its"
        bootloaders_factory_image "$1" "${mode}" "${bootloaders_its}"
    else
        bootloaders_its="${BUILD}/config/u-boot/${uboot_plat}/bootloaders.its"
        cp "${bootloaders_its}" "${out_dir}/bootloaders.its"
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
