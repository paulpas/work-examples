#!/usr/bin/env bash
# ---------------------------------------------------------------
# Script to interactively view merge commits with actual diffs
# Dependencies: git, fzf, gum, delta, awk
# Usage Example: ./view_merges.sh -d 14
# ---------------------------------------------------------------
set -eo pipefail

#DAYS_AGO=7

# Used to filter repositories.  Change to "*" for all
REPO_FILTER="adc*"

usage() {
    echo "Usage: $0 [-d days]"
    echo "  -d days   Query merge commits from the past specified days (default: 7)"
    exit 1
}
if (( $# == "0" )); then
    usage
fi
while getopts ":d:h" opt; do
    case ${opt} in
        d ) DAYS_AGO=$OPTARG ;;
        h ) usage ;;
        * ) usage ;;
    esac
done

find_git_repositories() {
    find . -maxdepth 1 -type d -name "${REPO_FILTER}" -exec test -d '{}/.git' ';' -print \
    | sed 's|^\./||'
}

get_valid_merge_commits() {
    local repo=$1
    cd "$repo" || return 1

    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    [ -z "$current_branch" ] && return 1

    local stashed=0
    if ! git diff-index --quiet HEAD -- &>/dev/null; then
        git stash &>/dev/null
        stashed=1
    fi

    git checkout main &>/dev/null || git checkout master &>/dev/null
    git pull &>/dev/null

    local commit_lines
    commit_lines=$(git log --since="${DAYS_AGO} days ago" --merges \
        --pretty=format:"%h|%ad|%s" --date=iso-strict 2>/dev/null || echo "")

    local commit_hash commit_date commit_msg
    while IFS="|" read -r commit_hash commit_date commit_msg; do
        [[ -z "$commit_hash" || -z "$commit_date" || -z "$commit_msg" ]] && continue
        git diff --quiet "${commit_hash}"^.."${commit_hash}" &>/dev/null && continue
        echo "${repo}|${commit_hash}|${commit_date}|${commit_msg}"
    done <<< "$commit_lines"

    git checkout "$current_branch" &>/dev/null
    [ "$stashed" -eq 1 ] && git stash pop &>/dev/null
}

select_valid_repositories() {
    local repos valid_repos repo
    repos=($(find_git_repositories))

    for repo in "${repos[@]}"; do
        [[ -n $(get_valid_merge_commits "$repo") ]] && valid_repos+=("$repo")
    done

    if [ ${#valid_repos[@]} -eq 0 ]; then
        echo "No repositories have valid merge commits with diffs in the past ${DAYS_AGO} days."
        exit 0
    fi

    gum choose --no-limit "${valid_repos[@]}" --height=24
}

choose_commit_with_fzf() {
    local commits=("$@")
    if [ ${#commits[@]} -eq 0 ]; then
        echo "NO COMMITS IN THE PAST ${DAYS_AGO} DAYS" | fzf --prompt="No commits" --exit-0 --height=10
        return 1
    fi
    printf '%s\n' "${commits[@]}" | column -s'|' -t | fzf --prompt="Select a commit / Type a string to search / CRTL-c to exit: " --height=95%
}

show_diff_for_commit() {
    local repo=$1
    local commit_hash=$2

    # explicitly disable 'pipefail' around delta command only, avoiding script exit on q
    set +o pipefail

    # ensure 'less' passing results in clean status
    LESS='--quit-if-one-screen --RAW-CONTROL-CHARS' git -C "$repo" diff "${commit_hash}"^.."${commit_hash}" \
        | delta --dark --side-by-side --line-numbers

    set -o pipefail
}

main() {
    echo "Updating and checking repositories for valid merge commits (this may take a moment)..."

    local selected_repos commit_array selected_commit repo hash
    selected_repos=($(select_valid_repositories))

    echo "Scanning selected repositories (be patient)..."
    commit_array=()
    for repo in "${selected_repos[@]}"; do
        while IFS= read -r commit_line; do
            commit_array+=("$commit_line")
        done < <(get_valid_merge_commits "$repo")
    done

    while true; do
        selected_commit=$(choose_commit_with_fzf "${commit_array[@]}") || break
        if [ -z "$selected_commit" ]; then
            echo "No commit selected. Exiting."
            break
        elif [[ "$selected_commit" == "NO COMMITS IN THE PAST"* ]]; then
            echo "$selected_commit"
            break
        fi

        # Carefully parse selection
        repo=$(awk '{print $1}' <<< "$selected_commit")
        hash=$(awk '{print $2}' <<< "$selected_commit")

        clear
        echo "Repository: $repo | Commit: $hash"
        #printf '%s\n' "-------------------------------------------------------------"
        show_diff_for_commit "$repo" "$hash"
        #printf '%s\n' "-------------------------------------------------------------"

        # safely prompt return to menu
        #echo "Press ENTER to return to commit selection, or CTRL+C to quit."
        #read -r _
    done
}

main "$@"

