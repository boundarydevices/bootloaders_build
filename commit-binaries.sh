#!/bin/bash

set -e
set -u
set -o pipefail

SRC=$(dirname "$(readlink -e "$0")")
source "${SRC}/utils.sh"

function usage {
    cat <<DELIM__
usage: $(basename "$0") [options]

$ $(basename "$0") --from-repo=<repo root directory> --to-repo=<repo root directory> --to-project=<project sub-path>

Options:
  --from-repo               Absolute path to the source repo
  --from-projects           (OPTIONAL) space-separated list of relative source projects. Defaults to all
  --to-repo                 Absolute path to the destination repo
  --to-project              Relative path in the destination repo where git commit is ran
  --title-prefix            (OPTIONAL) commit message title prefix. Defaults to "generic"
  --dry-run                 (OPTIONAL) don't commit, pass --dry-run to git instead
  --no-fail-on-empty-commit (OPTIONAL) return success if nothing to commit
  --help                    (OPTIONAL) display usage

Examples:
  $ $(basename "$0") --from-repo=/home/user/src/android-common-kernel --from-projects='common hikey-modules' \\
                       --to-repo=/home/user/src/aosp --to-project=device/amlogic/yukawa-kernel
DELIM__
}

function all_projects_for_repo {
    local repo_path=$1
    local projects=$(repo --color=never list --path-only)

    echo $projects
}

function display_center_msg {
    local line_length="$1"
    local msg="$2"
    local length=${#msg}
    local pad=$(((line_length - length) / 2))

    printf "%0.s " $(seq 1 ${pad})
    printf "${msg}"

    # if line_length is an odd number, add 1 to pad
    if [ $(((pad * 2) + length)) != "${line_length}" ]; then
        pad=$((pad + 1))
    fi

    printf "%0.s " $(seq 1 ${pad})
}

function display_commit_msg_header {
    local path="$1"

    printf "%0.s#" {1..90}
    printf "\n##"
    display_center_msg 86 "COMMIT MESSAGE IN:"
    printf "##\n##"
    display_center_msg 86 "${path}"
    printf "##\n"
    printf "%0.s#" {1..90}
    printf "\n\n"
}

function commit_msg_body {
    local remote_name=$1 && shift
    local from_repo=$1 && shift
    local projects=("$@")

    local remote_url=""
    local head=""
    local branch=""

    for project in "${projects[@]}"; do
        pushd "${from_repo}/${project}"
        body+="- Project: ${project}:\n"

        remote_url=$(git remote get-url "${remote_name}")
        body+="URL: ${remote_url}\n"

        branch=$(repo --color=never info . 2>&1 | perl -ne 'print "$1" if /^Manifest revision: (.*)/')
        body+="Branch: ${branch}\n"

        head=$(git log --oneline --no-decorate -1)
        body+="HEAD: ${head}\n\n"
        popd
    done

    echo "${body}"
}

function commit_binaries {
    local from_repo=""
    local from_projects=""
    local to_repo=""
    local to_project=""
    local title_prefix="generic"
    local dry_run=false
    local no_fail_on_empty_commit=false

    local opts_args="from-repo:,from-projects:,to-repo:,to-project:,title-prefix:,dry-run,no-fail-on-empty-commit,help"
    local opts=$(getopt -o '' -l "${opts_args}" -- "$@")
    eval set -- "${opts}"

    while true; do
        case "$1" in
            --from-repo) from_repo=$(find_path "$2"); shift 2 ;;
            --from-projects) from_projects="$2"; shift 2;;
            --to-repo) to_repo=$(find_path "$2"); shift 2 ;;
            --to-project) to_project="$2"; shift 2;;
            --title-prefix) title_prefix="$2"; shift 2;;
            --dry-run) dry_run=true; shift ;;
            --no-fail-on-empty-commit) no_fail_on_empty_commit=true; shift ;;
            --help) usage; exit 0 ;;
            --) shift; break ;;
        esac
    done

    # check arguments
    ! [ -d "${from_repo}" ] && error_usage_exit "invalid --from-repo: $from_repo"
    ! [ -d "${to_repo}" ] && error_usage_exit "invalid --to-repo: $to_repo"
    ! [ -d "${to_repo}/${to_project}" ] && error_usage_exit "invalid --to-project: ${to_repo}/${to_project}"

    # if no projects are specified, use all of them.
    if [ -z "$from_projects" ]; then
        from_projects="$(all_projects_for_repo ${from_repo})"
    fi

    check_local_changes "${from_repo}" $from_projects

    # commits message
    local commit_body=$(commit_msg_body "aiot" $from_repo $from_projects)

    local commit_title=""
    local commit_msg=""

    pushd "${to_repo}/${to_project}"
    # display commit
    display_commit_msg_header "${to_repo}/${to_project}"
    commit_title="${title_prefix}: update binaries\n\n"
    commit_msg=$(echo -e "${commit_title}${commit_body}")
    echo "${commit_msg}"

    if [[ "${no_fail_on_empty_commit}" == true ]] && [ -z "$(git status --porcelain)" ]; then
        warning_exit "nothing to commit"
    fi
    git add --all

    if [[ "${dry_run}" == true ]]; then
        git commit --dry-run -s -m "${commit_msg}"
        git restore --staged .
    else
        git commit --quiet -s -m "${commit_msg}"
    fi
    popd
}

if [ "$0" = "$BASH_SOURCE" ]; then
    commit_binaries "$@"
fi
