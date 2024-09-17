#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "$0")")
source "${SRC}/utils.sh"

function usage {
    cat <<DELIM__
usage: $(basename "$0") [options]

$ $(basename "$0") --aosp=/home/julien/Documents/mediatek/android --branch=jmasson/update-binaries

Options:
  --aosp     Android Root path
  --branch   Branch name
  --clean    (OPTIONAL) clean up AOSP projects
  --help     (OPTIONAL) display usage
DELIM__
}

function projects_path {
    local -n projects_ref="$1"
    local aosp="$2"
    local mtk_binaries_path=""
    local toplevel=""

    pushd "${SRC}"
    for mtk_config in config/boards/*.yaml; do
        mtk_binaries_path=$(config_value "${mtk_config}" android.binaries_path)
        pushd "${aosp}/${mtk_binaries_path}"
        toplevel=$(git rev-parse --sq --show-toplevel)
        if [[ ! ${projects_ref[*]} =~ ${toplevel} ]]; then
            projects_ref+=("${toplevel}")
        fi
        popd
    done
}

function main {
    local aosp=""
    local branch=""
    local clean=false

    local opts_args="aosp:,branch:,clean,help"
    local opts=$(getopt -o '' -l "${opts_args}" -- "$@")
    eval set -- "${opts}"

    while true; do
        case "$1" in
            --aosp) aosp=$(find_path "$2"); shift 2 ;;
            --branch) branch="$2"; shift 2 ;;
            --clean) clean=true; shift ;;
            --help) usage; exit 0 ;;
            --) shift; break ;;
        esac
    done

    # check arguments
    [ -z "${aosp}" ] && error_usage_exit "Cannot find Android Root Path"
    [ -z "${branch}" ] && error_usage_exit "Please provide branch name"

    declare -a projects
    projects_path projects "${aosp}"
    for project in "${projects[@]}"; do
        pushd "${project}"
        echo "Setup: ${project}"

        # clean up project
        if [[ "${clean}" == true ]]; then
            git clean --quiet -xdf
            git reset --quiet --hard
        fi

        # check local changes
        if ! git diff-index --quiet HEAD; then
            error_exit "error: Local changes detected"
        fi

        # check if branch exist
        if git show-ref --quiet "${branch}"; then
            git checkout --quiet --detach
            git branch --quiet -D "${branch}"
        fi

        # detect remote: [aiot|baylibre]
        local remote="rita"
        local output=$(git remote | grep baylibre)
        [ -n "${output}" ] && remote="baylibre"

        # create branch
        local repo_branch=$(repo --color=never info . 2>&1 | perl -ne 'print "$1" if /^Manifest revision: (.*)/')
        git fetch --quiet "${remote}" "${repo_branch}"
        git checkout --quiet "${remote}/${repo_branch}" -b "${branch}"
        popd
    done
}

main "$@"
