#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "$0")")
source "${SRC}/build_bootloaders.sh"
source "${SRC}/build_da.sh"
source "${SRC}/build_mtk_boot.sh"
source "${SRC}/utils.sh"

function build_all {
    local clean="${2:-false}"
    local mode="${3:-release}"
    local out_dir=$(out_dir "$1" "${mode}")

    if [[ "${clean}" == true ]] && [ -d "${out_dir}" ]; then
        rm -rf "${out_dir}"
    fi

    # Download Agent (DA)
    build_da "$@"

    # MMC BOOT
    build_mtk_boot "$@"

    # Bootloaders: BL31, OP-TEE, U-Boot
    build_bootloaders "$@"

    # secure package
    if [[ "${mode}" == "factory" ]]; then
        generate_secure_package "$1" "${out_dir}"
    fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
