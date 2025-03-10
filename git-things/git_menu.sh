#!/usr/bin/env bash
#
# Script Name: git_changes.sh
#
# Description: 
#   This script queries merge commits from multiple git repositories over the past specified number of days.
#   It allows filtering repositories based on a specified pattern. The user can interactively select repositories
#   and commits using the command-line tools 'gum' and 'fzf', after which the git diff of selected commits are 
#   displayed with enhanced readability (using 'delta').
#   
# Data Flow Overview:
#   - User provides optional filters (days and repo filter).
#   - Repositories matching the filter are located.
#   - For each selected repository, merge commits from specified past days are retrieved.
#   - User selects repositories and commits interactively.
#   - The diff for the selected merge commit is displayed.
#   - Temporary backups are created/restored for untracked files to maintain repository integrity.
#
# Usage Examples:
#   ./git_changes.sh -d 7 -r 'abc*'
#
# Dependencies:
#   - git, fzf, gum, delta
#

set -eo pipefail

# Default configuration values
DAYS_AGO=7          # Default search range: query commits from the past 7 days
REPO_FILTER="*"     # Default repository filter: searches all repos

# Display script usage instructions
usage() {
    cat << EOF
Usage: $0 [-d days] [-r repository_filter]
  -d days              Query merge commits from the past specified days (default: 7)
  -r repository_filter Set a filter for the repositories to be queried (default: *)

Example:
     $(basename $0) -d 7 -r 'adc*'
     $(basename $0) -r 'adc*'
     $(basename $0) -d 7
EOF
    exit 1
}

# Check if at least one input argument is given, otherwise show usage
if (( $# == 0 )); then
    usage
fi

# Process user options for days, repository filter, and help flag
while getopts ":d:r:h" opt; do
    case ${opt} in
        d ) DAYS_AGO=$OPTARG ;;          # Set the number of days ago
        r ) REPO_FILTER=$OPTARG ;;       # Set repo filter pattern
        h ) usage ;;                     # Display usage
        * ) usage ;;                     # Unknown option
    esac
done

##########################
# FUNCTION DEFINITIONS
##########################

# Find git repositories matching the repo filter within the current directory
find_git_repositories() {
    find . -maxdepth 1 -type d -name "${REPO_FILTER}" -exec test -d '{}/.git' ';' -print | sed 's|^\./||'
}

# Backup untracked files safely to a temporary location; returns backup directory path
backup_untracked_files() {
    local repo=$1 backup_dir
    # Create a temporary directory in /tmp named after the repository with timestamp
    backup_dir=$(mktemp -d "/tmp/${repo//\//_}_untracked_$(date +%s).XXXXXX")
    # Move untracked files into temporary backup directory
    git -C "$repo" ls-files --others --exclude-standard | while read -r file; do
        mkdir -p "$(dirname "$backup_dir/$file")"
        mv "$repo/$file" "$backup_dir/$file"
    done
    echo "$backup_dir"
}

# Restore untracked files from the provided backup directory back to repository
restore_untracked_files() {
    local repo=$1 backup_dir=$2
    [ -d "$backup_dir" ] || return 0  # Return if backup doesn't exist
    cp -r "$backup_dir/." "$repo/"    # Copy backup files to original repo location
    rm -rf "$backup_dir"              # Clean up backup directory
}

# Retrieve valid merge commits from the specified repository for given DAYS_AGO
get_valid_merge_commits() {
    local repo=$1 current_branch commit_lines commit_hash commit_date commit_msg stashed=0 backup_dir

    # Capture current branch name
    current_branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    [ -z "$current_branch" ] && return 1  # If no branch found, exit function

    # Stash any changes if present
    if ! git -C "$repo" diff-index --quiet HEAD -- &>/dev/null; then
        git -C "$repo" stash &>/dev/null
        stashed=1
    fi

    # Backup untracked files
    backup_dir=$(backup_untracked_files "$repo")

    # Checkout main or master branch and pull latest updates silently
    git -C "$repo" checkout main &>/dev/null || git -C "$repo" checkout master &>/dev/null
    git -C "$repo" pull --quiet >/dev/null

    # Get merge commits from specified past days; output format: hash|date|message
    commit_lines=$(git -C "$repo" log --since="${DAYS_AGO} days ago" --merges \
        --pretty=format:"%h|%ad|%s" --date=iso-strict 2>/dev/null || echo "")

    # Iterate through merge commits for detailed validity checks
    while IFS="|" read -r commit_hash commit_date commit_msg; do
        [[ -z "$commit_hash" || -z "$commit_date" || -z "$commit_msg" ]] && continue
        # Skip commit if no diff present (empty merge)
        git -C "$repo" diff --quiet "${commit_hash}"^.."${commit_hash}" &>/dev/null && continue
        # Output format for valid commit: repo|commit_hash|commit_date|commit_msg
        echo "${repo}|${commit_hash}|${commit_date}|${commit_msg}"
    done <<< "$commit_lines"

    # Restore repository to original branch and unstash changes if they were stashed
    git -C "$repo" checkout "$current_branch" &>/dev/null
    [ "$stashed" -eq 1 ] && git -C "$repo" stash pop &>/dev/null

    # Restore untracked files
    restore_untracked_files "$repo" "$backup_dir"
}

# Select repositories interactively using 'gum'
select_repositories_with_gum() {
    local repos
    repos=($(find_git_repositories))
    [ ${#repos[@]} -eq 0 ] && {
        echo "No git repositories match filter '${REPO_FILTER}'."
        exit 0
    }
    gum choose --no-limit "${repos[@]}" --height=24
}

# Interactively select commit using 'fzf'
choose_commit_with_fzf() {
    local commits=("$@")
    if [ ${#commits[@]} -eq 0 ]; then
        echo "NO COMMITS IN THE PAST ${DAYS_AGO} DAYS" | fzf --prompt="No commits" --exit-0 --height=10
        return 1
    fi
    printf '%s\n' "${commits[@]}" | column -s'|' -t | fzf --prompt="Select a commit / Type to search / CTRL-c to exit: " --height=100%
}

# Show diff for selected commit using delta (for better readability)
show_diff_for_commit() {
    local repo=$1 commit_hash=$2
    set +o pipefail
    git -C "$repo" diff "${commit_hash}"^.."${commit_hash}" \
        | delta --dark --side-by-side --line-numbers
    echo "Press any key to continue..."
    read -n 1 -s -r -p ""
    echo ""
    set -o pipefail
}

# Main execution function orchestrating all actions
main() {
    local selected_repos repo commit_array selected_commit hash

    # Select git repositories via user interaction
    echo "Finding git repositories matching ${REPO_FILTER}..."
    selected_repos=($(select_repositories_with_gum))
    [ ${#selected_repos[@]} -eq 0 ] && {
        echo "No repositories selected. Exiting."
        exit 0
    }

    declare -A backups  # Associative array to track backups per repo

    # Define cleanup function to restore backups upon exit
    cleanup() {
        for repo_key in "${!backups[@]}"; do
            restore_untracked_files "$repo_key" "${backups[$repo_key]}"
        done
    }
    trap cleanup EXIT

    echo "Scanning selected repositories..."
    commit_array=()
    for repo in "${selected_repos[@]}"; do
        echo "Updating repository ${repo}..."
        backups["$repo"]="$(backup_untracked_files "$repo")"
        mapfile -t repo_commits < <(get_valid_merge_commits "$repo")
        commit_array+=("${repo_commits[@]}")
    done

    while true; do
        selected_commit=$(choose_commit_with_fzf "${commit_array[@]}") || break
        [ -z "$selected_commit" ] && { echo "Canceled selection. Exiting."; break; }
        repo=$(awk '{print $1}' <<< "$selected_commit")
        hash=$(awk '{print $2}' <<< "$selected_commit")

        clear
        echo "Repository: $repo | Commit: $hash"
        show_diff_for_commit "$repo" "$hash"
    done

    echo "Restoring untracked files..."
}

main "$@"
