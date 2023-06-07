#!/bin/bash

BUILD=$(dirname "$(readlink -e "$0")")
ROOT=$(readlink -e "${BUILD}/../")
OUT="${ROOT}/out"
TOOLCHAINS="${SYSTEM_WIDE_TOOLCHAINS:-${ROOT}/toolchains}"
MODES=("release" "debug" "factory")

INIT_PATH=$PATH

function pushd {
    command pushd "$@" > /dev/null
}

function popd {
    command popd > /dev/null
}

function find_path {
    local path="$1"
    local real_path=""
    if [ -e "${path}" ]; then
        real_path=$(readlink -e "${path}")
    fi
    echo "${real_path}"
}

function check_local_changes {
    local repo_path="$1" && shift
    local projects=("$@")

    for project in "${projects[@]}"; do
        pushd "${repo_path}/${project}"
        # always run status before to trigger an index rebuild
        # This is important when many files have a different mtime
        # see: https://github.com/MestreLion/git-tools/issues/38#issuecomment-894182421
        git status
        if ! git diff --quiet HEAD; then
            error_exit "Local changes detected in: ${project}"
        fi
        popd
    done
}

function aarch64_env {
    export PATH="${TOOLCHAINS}/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/bin:$PATH"
    export CROSS_COMPILE=aarch64-none-linux-gnu-
    export CROSS_COMPILE64=aarch64-none-linux-gnu-
}

function check_aarch64 {
    if ! [ -d "${TOOLCHAINS}/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu" ]; then
        pushd "${TOOLCHAINS}"
        wget https://developer.arm.com/-/media/Files/downloads/gnu-a/10.3-2021.07/binrel/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu.tar.xz
        tar -xvf gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu.tar.xz
        popd
    fi
}

function arm-none_env {
    export PATH="${TOOLCHAINS}/gcc-arm-10.3-2021.07-x86_64-aarch64-none-elf/bin:$PATH"
    export CROSS_COMPILE=aarch64-none-elf-
}

function check_arm-none {
    if ! [ -d "${TOOLCHAINS}/gcc-arm-10.3-2021.07-x86_64-aarch64-none-elf" ]; then
        pushd "${TOOLCHAINS}"
        wget https://developer.arm.com/-/media/Files/downloads/gnu-a/10.3-2021.07/binrel/gcc-arm-10.3-2021.07-x86_64-aarch64-none-elf.tar.xz
        tar -xvf gcc-arm-10.3-2021.07-x86_64-aarch64-none-elf.tar.xz
        popd
    fi
}

function clear_vars {
    export PATH=$INIT_PATH
    unset ARCH
    unset CROSS_COMPILE
}

function check_env {
    # out directory
    ! [ -d "${OUT}" ] && mkdir "${OUT}"

    # toolchains
    ! [ -d "${TOOLCHAINS}" ] && mkdir "${TOOLCHAINS}"
    check_aarch64
    check_arm-none
}

function config_value {
    local value=$(cat "$1" | shyaml --quiet get-value "$2")
    echo "${value}"
}

function board_name {
    local yaml_config=$(basename "$1")
    echo "${yaml_config%.yaml}"
}

function config_root {
    local config_root="$(dirname "${1}")/.."
    echo "$(readlink -e "${config_root}")"
}

function out_dir {
    local board=$(board_name "$1")
    local mode="${2:-release}"

    echo "${OUT}/${board}/${mode}"
}

function display_current_build {
    local board=$(board_name "$1")
    local build="$2"
    local mode="$3"

    printf "\n"
    printf "%0.s-" {1..20}
    printf "> Build %s: %s - %s <" "${build}" "${board}" "${mode}"
    printf "%0.s-" {1..20}
    printf "\n"
}

function usage {
    cat <<DELIM__
usage: $(basename "$0") [options]

$ $(basename "$0") --config=i350-pumpkin.yaml

Options:
  --config   Mediatek board config file
  --clean    (OPTIONAL) clean before build
  --mode     (OPTIONAL) [release|debug|factory] mode (default: release)
  --help     (OPTIONAL) display usage
DELIM__
}

function warning {
    local warning="$1"
    printf "\033[0;33mWARNING:\033[0m ${warning}\n\n"
}

function warning_exit {
    warning "$1"
    exit 0
}

function error {
    local error="$1"
    printf "\033[0;31mERROR:\033[0m ${error}\n\n"
}

function error_exit {
    error "$1"
    exit 1
}

function error_usage_exit {
    error "$1"
    usage
    exit 1
}

function main {
    local script=$(basename "$0")
    local build="${script%.*}"
    local clean=false
    local config=""
    local mode="release"

    local opts_args="clean,config:,help,mode:"
    local opts=$(getopt -o '' -l "${opts_args}" -- "$@")
    eval set -- "${opts}"

    while true; do
        case "$1" in
            --config) config=$(find_path "$2"); shift 2 ;;
            --clean) clean=true; shift ;;
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
    ${build} "${config}" "${clean}" "${mode}"
}
