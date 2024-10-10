#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "$0")")
source "${SRC}/secure.sh"
source "${SRC}/utils.sh"

OPTEE="${ROOT}/optee-os"

function clean_optee {
    if [ -d "out" ]; then
        rm -rf out
    fi
}

function build_ta {
    local clean="$1"
    local optee_flags="$2"
    local ta_dir=$(dirname "$3")

    pushd "${ta_dir}"
    echo "-> Build Trusted Application: ${ta_dir}"
    [[ "${clean}" == true ]] && make clean
    make -j"$(nproc)" ${optee_flags}
    popd
}

function get_optee_flags {
    local optee_plat=$(config_value "$1" optee.plat)
    local flags=$(config_value "$1" optee.flags)
    local rpmb=$(config_value "$1" optee.rpmb)
    local mode="$2"
    local -n optee_flags_ref="$3"

    # additional flags
    case "${mode}" in
        "release") flags+=" DEBUG=0 CFG_TEE_CORE_LOG_LEVEL=0 CFG_UART_ENABLE=n" ;;
        "debug") flags+=" DEBUG=1" ;;
        "factory")
            flags+=" DEBUG=0 CFG_TEE_CORE_LOG_LEVEL=0 CFG_UART_ENABLE=n"

            # sign TA
            local ta_key=""
            local ta_pub_key=""
            get_ta_keys "$1" ta_key ta_pub_key
            if [ -n "${ta_key}" ] && [ -n "${ta_pub_key}" ]; then
                flags+=" TA_SIGN_KEY=${ta_key} TA_PUBLIC_KEY=${ta_pub_key}"
            fi

            # RPMB
            if [ "${rpmb}" != "False" ]; then
                flags+=" CFG_RPMB_FS=y CFG_RPMB_WRITE_KEY=y"
            fi

            # AVB TA
            flags+=" CFG_IN_TREE_EARLY_TAS=avb/023f8f1a-292a-432b-8fc4-de8471358067"
    esac

    flags+=" CFG_TZDRAM_START=0x43200000 CFG_TZDRAM_SIZE=0x00a00000"
    flags+=" CFG_HMAC_64_1024_RANGE=y"
    flags+=" CFG_DT=y"
    flags+=" PLATFORM=mediatek-${optee_plat}"

    optee_flags_ref="${flags}"
}

function build_android_ta {
    local clean="$2"
    local mode="$3"
    local out_dir=$(out_dir "$1" "${mode}")
    local optee_out_dir="${OPTEE}/out/arm-plat-mediatek"
    local kmgk="optee-ta/kmgk"
    local xtest="optee-ta/optee_test/ta"
    local optee_flags=""
    local ta_paths=($(config_value "$1" optee.ta_paths))
    declare -a android_ta_paths

    display_current_build "$1" "android Trusted Applications" "${mode}"

    get_optee_flags "$1" "${mode}" optee_flags

    # ta from config
    if [ "${#ta_paths[@]}" -gt 0 ]; then
        android_ta_paths+=("${ta_paths[@]}")
    fi

    # gatekeeper
    android_ta_paths+=("${kmgk}/gatekeeper/ta/4d573443-6a56-4272-ac6f-2425af9ef9bb.ta")

    # keymaster
    android_ta_paths+=("${kmgk}/keymaster/ta/dba51a17-0563-11e7-93b1-6fa7b0071a51.ta")

    # xtest
    android_ta_paths+=("${xtest}/bti_test/3616069b-504d-4044-9497-feb84a073a14.ta")
    android_ta_paths+=("${xtest}/concurrent/e13010e0-2ae1-11e5-896a-0002a5d5c51b.ta")
    android_ta_paths+=("${xtest}/concurrent_large/5ce0c432-0ab0-40e5-a056-782ca0e6aba2.ta")
    android_ta_paths+=("${xtest}/create_fail_test/c3f6e2c0-3548-11e1-b86c-0800200c9a66.ta")
    android_ta_paths+=("${xtest}/crypt/cb3e5ba0-adf1-11e0-998b-0002a5d5c51b.ta")
    android_ta_paths+=("${xtest}/crypto_perf/02a42f43-d8b7-4a57-aa4d-87bd9b5587cb.ta")
    android_ta_paths+=("${xtest}/large/25497083-a58a-4fc5-8a72-1ad7b69b8562.ta")
    android_ta_paths+=("${xtest}/miss/528938ce-fc59-11e8-8eb2-f2801f1b9fd1.ta")
    android_ta_paths+=("${xtest}/os_test_lib/ffd2bded-ab7d-4988-95ee-e4962fff7154.ta")
    android_ta_paths+=("${xtest}/os_test_lib_dl/b3091a65-9751-4784-abf7-0298a7cc35ba.ta")
    android_ta_paths+=("${xtest}/os_test/5b9e0e40-2636-11e1-ad9e-0002a5d5c51b.ta")
    android_ta_paths+=("${xtest}/rpc_test/d17f73a0-36ef-11e1-984a-0002a5d5c51b.ta")
    android_ta_paths+=("${xtest}/sdp_basic/12345678-5b69-11e4-9dbb-101f74f00099.ta")
    android_ta_paths+=("${xtest}/sims/e6a33ed4-562b-463a-bb7e-ff5e15a493c8.ta")
    android_ta_paths+=("${xtest}/sims_keepalive/a4c04d50-f180-11e8-8eb2-f2801f1b9fd1.ta")
    android_ta_paths+=("${xtest}/socket/873bcd08-c2c3-11e6-a937-d0bf9c45c61c.ta")
    android_ta_paths+=("${xtest}/storage/b689f2a7-8adf-477a-9f99-32e90c0ad0a2.ta")
    android_ta_paths+=("${xtest}/storage2/731e279e-aafb-4575-a771-38caa6f0cca6.ta")
    android_ta_paths+=("${xtest}/storage_benchmark/f157cda0-550c-11e5-a6fa-0002a5d5c51b.ta")
    android_ta_paths+=("${xtest}/subkey1/5c206987-16a3-59cc-ab0f-64b9cfc9e758.ta")
    android_ta_paths+=("${xtest}/subkey2/a720ccbb-51da-417d-b82e-e5445d474a7a.ta")
    android_ta_paths+=("${xtest}/supp_plugin/380231ac-fb99-47ad-a689-9e017eb6e78a.ta")
    android_ta_paths+=("${xtest}/tpm_log_test/ee90d523-90ad-46a0-859d-8eea0b150086.ta")

    # build TA
    aarch64_env
    export TA_DEV_KIT_DIR="${optee_out_dir}/export-ta_arm64"

    ! [ -d "${out_dir}/optee-ta" ] && mkdir -p "${out_dir}/optee-ta"

    android_ta_paths=("${android_ta_paths[@]/#/${ROOT}/}")
    for android_ta in "${android_ta_paths[@]}"; do
        build_ta "${clean}" "${optee_flags}" "${android_ta}"
        cp "${android_ta}" "${out_dir}/optee-ta/"
    done

    clear_vars
}

function build_optee {
    local clean="${2:-false}"
    local mode="${3:-release}"
    local out_dir=$(out_dir "$1" "${mode}")
    local optee_flags=""
    local optee_out_dir="${OPTEE}/out/arm-plat-mediatek"
    local early_ta_paths=($(config_value "$1" optee.early_ta_paths))

    display_current_build "$1" "optee" "${mode}"

    get_optee_flags "$1" "${mode}" optee_flags

    # OTP TA
    if [[ "${mode}" == "factory" ]]; then
        early_ta_paths+=("optee-ta/optee-otp/ta/3712bdda-569f-4940-b749-fb3b06a5fd86.elf")
    fi

    # setup env
    ! [ -d "${out_dir}" ] && mkdir -p "${out_dir}"

    pushd "${OPTEE}"
    [[ "${clean}" == true ]] && clean_optee

    aarch64_env

    # build early TA
    if [ "${#early_ta_paths[@]}" -gt 0 ]; then
        make -j"$(nproc)" ${optee_flags} ta_dev_kit
        export TA_DEV_KIT_DIR="${optee_out_dir}/export-ta_arm64"

        early_ta_paths=("${early_ta_paths[@]/#/${ROOT}/}")
        for early_ta in "${early_ta_paths[@]}"; do
            build_ta "${clean}" "${optee_flags}" "${early_ta}"
            optee_flags+=" EARLY_TA_PATHS+=${early_ta}"
        done
    fi

    # build tee binary
    make -j"$(nproc)" ${optee_flags} all

    cp out/arm-plat-mediatek/core/tee.bin "${out_dir}/tee.bin"

    clear_vars
    popd
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
