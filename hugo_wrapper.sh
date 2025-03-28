#!/usr/bin/env bash

# hugo_wrapper.sh - help manage hugo websites
# Copyright (c) 2025, Mathieu Rousseau
# Provided "as is" under the MIT License

set -euo pipefail

# Trap interrupts for clean termination
trap 'echo "Script interrupted"; exit 1' INT TERM

# Check for hugo early
if ! command -v hugo >/dev/null; then
    echo "Error: Hugo is not installed." >&2
    exit 1
fi

CONFIG_FILE="$HOME/.config/hugo_wrapper.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    while IFS='=' read -r key value; do
        if [[ ! $key =~ ^[[:space:]]*# && -n $key ]]; then
            # Remove leading/trailing whitespace
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            declare "$key=$value"
        fi
    done <"$CONFIG_FILE"
fi

# Default dry run to false
DRY_RUN=false

# Loop over required variables and check if they're set.
for var in PROJECT_PATH DEPLOY_PATH DEPLOY_HOST; do
    if [ -z "${!var:-}" ]; then
        echo "Error: $var is not set. Please set $var on the CLI or in your config file." >&2
        exit 1
    fi
done

# Usage message
usage() {
    local progname
    progname=$(basename "$0")
    cat <<EOF
Usage: ${progname} <command> [subcommand/arguments] [OPTIONS]

    PROJECT_PATH, DEPLOY_HOST & DEPLOY_PATH variables must be set, in conf or
    via command line arguments

    Config is read from ~/.config/hugo_wrapper.conf, and command line arguments
    override it

Commands:
  new post "Post Title" [OPTIONS]
      Creates a new post
      The post file will be created as:
         content/posts/<YYYY-MM-DD>-<slugified-title>.md

  new page "Page Title" [OPTIONS]
      Creates a new page
      The page file will be created as:
         content/pages/<slugified-title>.md

  deploy [OPTIONS]
      Build the site with Hugo and deploy it using rsync

Common Options:
  -p, --project-path PATH       Override the project directory
  -d, --deploy-path PATH        Override the remote deploy path
  -H, --deploy-host HOST        Override the remote deploy host
  --dry-run                     Perform a dry run (no actual changes, use with deploy only)
  -h, --help                    Display this help and exit

Examples:
  ${progname} new post "My New Post"
  ${progname} new page "About Me" --project-path /path/to/project
  ${progname} deploy -p /path/to/project -d /remote/path -H myserver
  ${progname} deploy --dry-run
EOF
}

# Helper: Parse common options
# This function will iterate over remaining CLI args and override the conf variables
parse_common_options() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        -p | --project-path)
            PROJECT_PATH="$2"
            shift 2
            ;;
        -d | --deploy-path)
            DEPLOY_PATH="$2"
            shift 2
            ;;
        -H | --deploy-host)
            DEPLOY_HOST="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        esac
    done
}

# Helper: Validate project path exists
validate_project_path() {
    if [ ! -d "$PROJECT_PATH" ]; then
        echo "Error: Project path doesn't exist: $PROJECT_PATH"
        exit 1
    fi
}

# Helper: Slugify title
slugify() {
    local title="$1"
    # Convert to ASCII, convert to lower case, replace non-alphanumerics with dashes,
    # then remove leading/trailing dashes.
    echo "$title" | iconv -t ascii//TRANSLIT | tr '[:upper:]' '[:lower:]' |
        tr -d '[:punct:]' | tr '[:space:]' '-' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//'
}

# Command: new post
new_post() {
    local title="$1"
    shift
    parse_common_options "$@"
    validate_project_path

    local slug
    slug=$(slugify "$title")
    local date_str
    date_str=$(date +%Y-%m-%d)
    local file_rel_path="content/posts/${date_str}-${slug}.md"

    # Save original directory
    local original_dir
    original_dir=$(pwd)

    cd "$PROJECT_PATH" || {
        echo "Invalid project path: $PROJECT_PATH"
        exit 1
    }

    # Convert PROJECT_PATH to its absolute value
    PROJECT_PATH="$(pwd)"

    local file_path="${PROJECT_PATH}/${file_rel_path}"

    echo "Creating new post: $file_path"
    if ! hugo new "$file_rel_path"; then
        echo "Error creating the post."
        cd "$original_dir" || true
        exit 1
    fi
    echo "Post created successfully."

    if [ -n "${EDITOR:-}" ]; then
        echo "Opening post in \$EDITOR ($EDITOR)..."
        "$EDITOR" "$file_path"
    fi

    # Return to original directory
    cd "$original_dir" || true
}

# Command: new page
new_page() {
    local title="$1"
    shift
    parse_common_options "$@"
    validate_project_path

    local slug
    slug=$(slugify "$title")
    local file_rel_path="content/pages/${slug}.md"

    # Save original directory
    local original_dir
    original_dir=$(pwd)

    cd "$PROJECT_PATH" || {
        echo "Invalid project path: $PROJECT_PATH"
        exit 1
    }

    # Convert PROJECT_PATH to its absolute value
    PROJECT_PATH="$(pwd)"

    local file_path="${PROJECT_PATH}/${file_rel_path}"

    echo "Creating new page: $file_path"
    if ! hugo new "$file_rel_path"; then
        echo "Error creating the page."
        cd "$original_dir" || true
        exit 1
    fi
    echo "Page created successfully."

    if [ -n "${EDITOR:-}" ]; then
        echo "Opening page in \$EDITOR ($EDITOR)..."
        "$EDITOR" "$file_path"
    fi

    # Return to original directory
    cd "$original_dir" || true
}

# Command: deploy
deploy_site() {
    parse_common_options "$@"
    validate_project_path

    # Check for hugo
    if ! command -v hugo >/dev/null; then
        echo "Hugo is not installed."
        exit 1
    fi

    # Save original directory
    local original_dir
    original_dir=$(pwd)

    cd "$PROJECT_PATH" || {
        echo "Invalid project path: $PROJECT_PATH"
        exit 1
    }

    echo "Generating the site with Hugo..."
    if ! hugo --minify --gc --environment production; then
        echo "Error during site generation."
        cd "$original_dir" || true
        exit 1
    fi

    # Setup rsync options
    local RSYNC_OPTS="-avz --delete --checksum --human-readable --progress"
    if [ "$DRY_RUN" = true ]; then
        RSYNC_OPTS="$RSYNC_OPTS --dry-run"
        echo "Running in dry-run mode (no actual changes will be made)..."
    fi

    echo "Deploying the site to ${DEPLOY_HOST}:${DEPLOY_PATH}..."
    if ! rsync $RSYNC_OPTS public/ "${DEPLOY_HOST}:${DEPLOY_PATH}"; then
        echo "Error during rsync deployment."
        cd "$original_dir" || true
        exit 1
    fi

    echo "Deployment succeeded!"
    cd "$original_dir" || true
}

# Main command dispatcher
if [[ "$#" -lt 1 ]]; then
    usage
    exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
new)
    if [[ "$#" -lt 2 ]]; then
        usage
        exit 1
    fi
    NEW_TYPE="$1"
    shift
    TITLE="$1"
    shift
    case "$NEW_TYPE" in
    post)
        new_post "$TITLE" "$@"
        ;;
    page)
        new_page "$TITLE" "$@"
        ;;
    *)
        echo "Unknown new type: $NEW_TYPE"
        usage
        exit 1
        ;;
    esac
    ;;
deploy)
    deploy_site "$@"
    ;;
-h | --help)
    usage
    exit 0
    ;;
*)
    echo "Unknown command: $COMMAND"
    usage
    exit 1
    ;;
esac
