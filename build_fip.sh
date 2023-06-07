#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "$0")")
source "${SRC}/secure.sh"
source "${SRC}/build_libatf.sh"
source "${SRC}/utils.sh"

ATF="${ROOT}/arm-trusted-firmware"
MBEDTLS="${ROOT}/mbedtls"

function clean_fip {
    local mtk_plat="$1"
    if [ -d "build/${mtk_plat}" ]; then
        rm -r "build/${mtk_plat}"
    fi
}

function build_fip {
    local board=$(board_name "$1")
    local mtk_plat=$(config_value "$1" plat)
    local atf_project=$(config_value "$1" bl2.project)
    local mtk_cflags=$(config_value "$1" fip.cflags)
    local log_level=$(config_value "$1" fip.log_level)
    local libatf_a="${LIBATF}/build-${board}/src/${mtk_plat}/libatf.a"
    local libbase_a="${ROOT}/libbase-prebuilts/${mtk_plat}/libbase.a"
    local bl32_bin="$2"
    local bl33_bin="$3"
    local fip_bin="$4"
    local clean="${5:-false}"
    local extra_flags=""
    local mode="${6:-release}"
    local out_dir=$(out_dir "$1" "${mode}")
    local fip_out_dir=""

    display_current_build "$1" "fip" "${mode}"

    if [[ "${mode}" == "debug" ]]; then
        extra_flags="DEBUG=1 log_level=${log_level} ENABLE_LTO=1"
        fip_out_dir="build/${mtk_plat}/debug"
    else
        extra_flags="DEBUG=0 log_level=0"
        fip_out_dir="build/${mtk_plat}/release"
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
    [[ "${clean}" == true ]] && clean_fip "${mtk_plat}"

    arm-none_env

    make E=0 CFLAGS="${mtk_cflags}" PLAT="${mtk_plat}" BL32="${bl32_bin}" BL33="${bl33_bin}" \
         BL31_LIBS="${libatf_a} ${libbase_a}" ${extra_flags} SPD=opteed \
         NEED_BL32=yes NEED_BL33=yes bl31 fip

    cp "${fip_out_dir}/fip.bin" "${out_dir}/${fip_bin}"

    clear_vars
    popd
}

# main
function usage {
    cat <<DELIM__
usage: $(basename "$0") [options]

$ $(basename "$0") --config=i350-pumpkin.yaml --bl32=tee.bin --bl33=u-boot.bin --output=fip-test.bin

Options:
  --config   Mediatek board config file
  --bl32     Path to bl32 binary
  --bl33     Path to bl33 binary
  --output   (OPTIONAL) Output name of fip binary
  --clean    (OPTIONAL) clean before build
  --mode     (OPTIONAL) [release|debug|factory] mode (default: release)
  --help     (OPTIONAL) display usage
DELIM__
}

function main {
    local bl32=""
    local bl33=""
    local config=""
    local clean=false
    local output=""
    local mode="release"

    local opts_args="bl32:,bl33:,clean,config:,output:,help,mode:"
    local opts=$(getopt -o '' -l "${opts_args}" -- "$@")
    eval set -- "${opts}"

    while true; do
        case "$1" in
            --bl32) bl32=$(find_path "$2"); shift 2 ;;
            --bl33) bl33=$(find_path "$2"); shift 2 ;;
            --clean) clean=true; shift ;;
            --config) config=$(find_path "$2"); shift 2 ;;
            --output) output=$2; shift 2 ;;
            --mode) mode="$2"; shift 2 ;;
            --help) usage; exit 0 ;;
            --) shift; break ;;
        esac
    done

    # check arguments
    [ -z "${config}" ] && error_usage_exit "Cannot find board config file"
    [ -z "${bl32}" ] && error_usage_exit "Cannot find bl32"
    [ -z "${bl33}" ] && error_usage_exit "Cannot find bl33"
    ! [[ " ${MODES[*]} " =~ " ${mode} " ]] && error_usage_exit "${mode} mode not supported"
    if [ -z "${output}" ]; then
        output="fip-${mode}.bin"
    fi

    # build fip
    check_env
    build_fip "${config}" "${bl32}" "${bl33}" "${output}" "${clean}" "${mode}"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
