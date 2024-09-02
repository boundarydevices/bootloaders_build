#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "$0")")
source "${SRC}/utils.sh"

UBOOT="${ROOT}/u-boot"

function clean_uboot_spl {
    make mrproper
}

function uboot_spl_copy_binaries_out {
    local out_dir="$1"
    local uboot_spl_nodtb_out_bin="${UBOOT}/spl/u-boot-spl-nodtb.bin"
    local uboot_spl_dtb_out_bin="${UBOOT}/spl/u-boot-spl.dtb"

    if ! [ -a "${uboot_spl_nodtb_out_bin}" ]; then
        error_exit "U-Boot SPL (nodtb) not found"
    fi
    cp "${uboot_spl_nodtb_out_bin}" "${out_dir}/u-boot-spl-nodtb.bin"

    if ! [ -a "${uboot_spl_dtb_out_bin}" ]; then
        error_exit "U-Boot SPL DTB not found"
    fi
    cp "${uboot_spl_dtb_out_bin}" "${out_dir}/u-boot-spl.dtb"
}

function merge_uboot_spl_config {
    local config_root="$1"
    local board="$2"
    local mode="$3"
    local da="$4"
    local mode_fragment="${BUILD}/config/u-boot/spl-${mode}.config"
    local board_fragment="${config_root}/u-boot/${board}.config"
    declare -a configs

    if [[ "${da}" == true ]]; then
        configs+=("${BUILD}/config/u-boot/spl-da.config")
    else
        if [ -a "${mode_fragment}" ]; then
            configs+=("${mode_fragment}")
        fi
    fi

    if [ -a "${board_fragment}" ]; then
        configs+=("${board_fragment}")
    fi

    scripts/kconfig/merge_config.sh .config "${configs[*]}"
}

function build_uboot_spl {
    local config_root=$(config_root "$1")
    local board=$(board_name "$1")
    local clean="$2"
    local mode="$3"
    local da="$4"
    local spl_size_max=$(config_value "$1" mmcboot.spl_size_max)
    local mtk_spl_defconfig=$(config_value "$1" uboot.spl_defconfig)
    local uboot_spl_out_bin="${UBOOT}/spl/u-boot-spl.bin"
    local uboot_spl_size=0
    local build="uboot SPL"

    if [[ "${da}" == true ]]; then
        build="uboot SPL DA"
    fi

    display_current_build "$1" "${build}" "${mode}"

    pushd "${UBOOT}"
    [[ "${clean}" == true ]] && clean_uboot_spl

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
    make "${mtk_spl_defconfig}"
    merge_uboot_spl_config "${config_root}" "${board}" "${mode}" "${da}"

    make -j"$(nproc)" spl/u-boot-spl

    # check and truncate uboot spl size
    uboot_spl_size=$(stat --printf="%s" "${uboot_spl_out_bin}")
    if (( uboot_spl_size > spl_size_max)); then
        error_exit "U-Boot SPL size exceed the limit: ${uboot_spl_size} > ${spl_size_max}"
    fi

    unset ARCH
    clear_vars
    popd
}

function usage {
    cat <<DELIM__
usage: $(basename "$0") [options]

$ $(basename "$0") --config=i350-evk.yaml

Options:
  --config   Mediatek board config file
  --clean    (OPTIONAL) clean before build
  --da       (OPTIONAL) Download Agent build type
  --mode     (OPTIONAL) [release|debug|factory] mode (default: release)
  --help     (OPTIONAL) display usage
DELIM__
}

function main {
    local config=""
    local clean=false
    local da=false
    local mode="release"

    local opts_args="clean,config:,da,help,mode:"
    local opts=$(getopt -o '' -l "${opts_args}" -- "$@")
    eval set -- "${opts}"

    while true; do
        case "$1" in
            --config) config=$(find_path "$2"); shift 2 ;;
            --clean) clean=true; shift ;;
            --da) da=true; shift ;;
            --mode) mode="$2"; shift 2 ;;
            --help) usage; exit 0 ;;
            --) shift; break ;;
        esac
    done

    # check arguments
    [ -z "${config}" ] &&  error_usage_exit "Cannot find board config file"
    ! [[ " ${MODES[*]} " =~ " ${mode} " ]] && error_usage_exit "${mode} mode not supported"

    # build
    check_env
    build_uboot_spl "${config}" "${clean}" "${mode}" "${da}"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
