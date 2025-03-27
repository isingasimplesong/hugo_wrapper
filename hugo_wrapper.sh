#!/usr/bin/env bash
set -euo pipefail

#############################
# Load configuration file
#############################
CONFIG_FILE="$HOME/.config/hugo_wrapper.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Set defaults if not provided in conf.
PROJECT_PATH="${PROJECT_PATH:-$(pwd)}"                  # absolute path on the machine that run this wrapper
DEPLOY_PATH="${DEPLOY_PATH:-/path/to/deploy/directory}" # absolute path on the server
DEPLOY_HOST="${DEPLOY_HOST:-deploy.host.tld}"

#############################
# Usage message
#############################
usage() {
    cat <<EOF
Usage: $0 <command> [subcommand/arguments] [OPTIONS]

Commands:
  new post "Post Title" [OPTIONS]
      Creates a new post.
      The post file will be created as:
         content/posts/<YYYY-MM-DD>-<slugified-title>.md

  new page "Page Title" [OPTIONS]
      Creates a new page.
      The page file will be created as:
         content/pages/<slugified-title>.md

  deploy [OPTIONS]
      Build the site with Hugo and deploy it using rsync.

Common Options:
  -p, --project-path PATH       Override the project directory (default: \$PROJECT_PATH).
  -d, --deploy-path PATH        Override the remote deploy path (default: \$DEPLOY_PATH).
  -H, --deploy-host HOST        Override the remote deploy host (default: \$DEPLOY_HOST).
  -h, --help                    Display this help and exit.

Examples:
  $0 new post "My New Post"
  $0 new page "About Me" --project-path /path/to/project
  $0 deploy -p /path/to/project -d /remote/path -H myserver
EOF
}

#############################
# Helper: Parse common options
#############################
# This function will iterate over remaining CLI args and override the common variables.
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

#############################
# Helper: Slugify title
#############################
slugify() {
    local title="$1"
    # Convert to lower case, replace non-alphanumerics with dashes,
    # then remove leading/trailing dashes.
    echo "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed 's/^-//;s/-$//'
}

#############################
# Command: new post
#############################
new_post() {
    local title="$1"
    shift
    parse_common_options "$@"

    local slug
    slug=$(slugify "$title")
    local date_str
    date_str=$(date +%Y-%m-%d)
    local file_rel_path="content/posts/${date_str}-${slug}.md"

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
        exit 1
    fi
    echo "Post created successfully."

    if [ -n "${EDITOR:-}" ]; then
        echo "Opening post in \$EDITOR ($EDITOR)..."
        "$EDITOR" "$file_path"
    fi
}

#############################
# Command: new page
#############################
new_page() {
    local title="$1"
    shift
    parse_common_options "$@"

    local slug
    slug=$(slugify "$title")
    local file_rel_path="content/pages/${slug}.md"

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
        exit 1
    fi
    echo "Page created successfully."

    if [ -n "${EDITOR:-}" ]; then
        echo "Opening page in \$EDITOR ($EDITOR)..."
        "$EDITOR" "$file_path"
    fi
}

#############################
# Command: deploy
#############################
deploy_site() {
    parse_common_options "$@"

    # Check for hugo
    if ! command -v hugo >/dev/null; then
        echo "Hugo is not installed."
        exit 1
    fi

    cd "$PROJECT_PATH" || {
        echo "Invalid project path: $PROJECT_PATH"
        exit 1
    }

    echo "Generating the site with Hugo..."
    if ! hugo --minify --gc --environment production; then
        echo "Error during site generation."
        exit 1
    fi

    echo "Deploying the site to ${DEPLOY_HOST}:${DEPLOY_PATH}..."
    if ! rsync -az --delete public/ "${DEPLOY_HOST}:${DEPLOY_PATH}"; then
        echo "Error during rsync deployment."
        exit 1
    fi

    echo "Deployment succeeded!"
}

#############################
# Main command dispatcher
#############################
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
