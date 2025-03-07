#!/usr/bin/env bash

# List of repository names separated by space
REPOS=("repo1" "repo2")

# Default number of days ago to look for commits
DAYS_AGO=7

# Function to display usage information
usage() {
    echo "Usage: $0 [-d <days_ago>]"
    echo "  -d <days_ago>   Number of days ago to look for commits (default is 7)"
}

# Parse command-line arguments
while getopts ":d:" opt; do
    case ${opt} in
        d )
            DAYS_AGO=$OPTARG
            ;;
        \? )
            usage
            exit 1
            ;;
        * )
            echo "Invalid option: -$OPTARG requires an argument."
            usage
            exit 1
            ;;
    esac
done

# Function to get commits from a specific repository
get_commits_from_repo() {
    local REPO_DIR=$1
    cd "${REPO_DIR}" || return 1
    git log --since="${DAYS_AGO} days ago" --pretty=format:"%h %ad %s" --date=iso-strict | awk -v repo="${REPO_DIR}" '{print repo " " $0}'
}

# Function to find Git repositories in the current directory
find_git_repositories() {
    local REPOS=$1
    for REPO in ${REPOS}; do
        if [ -d "${REPO}/.git" ]; then
            echo "${REPO}"
        fi
    done
}

# Function to display an interactive list of commits using fzf
select_commit_with_fzf() {
    local COMMIT_INFO_LIST=$1
    echo -e "${COMMIT_INFO_LIST}" | fzf --prompt="Select a commit / Type a string to search / CTRL-C to exit: " --style full --height 90% --border
}

# Function to extract commit details from selected commit info
extract_commit_details() {
    local SELECTED_COMMIT=$1
    local REPO_NAME=$(echo ${SELECTED_COMMIT} | awk '{print $1}')
    local COMMIT_ID=$(echo ${SELECTED_COMMIT} | awk '{print $2}')
    local TIMESTAMP=$(echo ${SELECTED_COMMIT} | awk '{$1=$2=""; print substr($0, index($0,$3))}' | awk '{print $1, $2, $3}')
    local MESSAGE=$(echo ${SELECTED_COMMIT} | awk '{$1=$2=$3=$4=""; print substr($0, index($0,$5))}')
    echo "${REPO_NAME} ${COMMIT_ID} ${TIMESTAMP} ${MESSAGE}"
}

# Function to print commit details
print_commit_details() {
    local REPO_NAME=$1
    local COMMIT_ID=$2
    local TIMESTAMP=$3
    local MESSAGE=$4
    echo "------------------------------------------------------------------"
    echo "Repository: ${REPO_NAME}"
    echo "Commit ID: ${COMMIT_ID}"
    echo "Timestamp: ${TIMESTAMP}"
    echo "Message: ${MESSAGE}"
    if git -C "${REPO_NAME}" log -1 --merges --pretty=format:"%s" "${COMMIT_ID}" > /dev/null; then
        echo "Merge Message: $(git -C "${REPO_NAME}" log -1 --merges --pretty=format:"%b" "${COMMIT_ID}")"
    fi
    echo "------------------------------------------------------------------"
    echo "Diff:"
    git -C "${REPO_NAME}" show ${COMMIT_ID} | delta -s
}

# Main function to orchestrate the script
main() {
    # Convert array to space-separated string
    local REPO_STRING=$(printf "%s\n" "${REPOS[@]}")
    # Find repositories with .git directories
    local GIT_REPOS=($(find_git_repositories "$REPO_STRING"))
    if [ ${#GIT_REPOS[@]} -eq 0 ]; then
        echo "No Git repositories found in the specified list."
        exit 1
    fi
    while true; do
        # Collect commits from all repositories
        local COMMIT_INFO_LIST=""
        for REPO in "${GIT_REPOS[@]}"; do
            COMMIT_INFO_LIST+=$(get_commits_from_repo "$REPO")
            COMMIT_INFO_LIST+="\n"
        done
        # Select a commit using fzf
        local SELECTED_COMMIT=$(select_commit_with_fzf "$COMMIT_INFO_LIST")
        if [ -z "$SELECTED_COMMIT" ]; then
            echo "No commit selected. Exiting."
            break #exit 1
        fi
        # Extract and print commit details
        local COMMIT_DETAILS=($(extract_commit_details "$SELECTED_COMMIT"))
        print_commit_details "${COMMIT_DETAILS[@]}"
        # Ask if the user wants to continue
        read -p "Press any key to return to the menu or (n) to exit: (*/n) " CONTINUE
        if [[ $CONTINUE =~ ^[Nn]$ ]]; then
            break
        fi
    done
}

# Run the main function
main

