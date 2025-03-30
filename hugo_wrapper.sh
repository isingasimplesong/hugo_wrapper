#!/usr/bin/env bash

# hugo_wrapper.sh - help manage hugo websites
# Copyright (c) 2025, Mathieu Rousseau
# Provided "as is" under the MIT License

set -euo pipefail

# Trap interrupts for clean termination
trap 'echo "Script interrupted"; exit 1' INT TERM

# Check for required commands early
if ! command -v hugo >/dev/null; then
    echo "Error: Hugo is not installed." >&2
    exit 1
fi
if ! command -v rsync >/dev/null; then
    echo "Error: rsync is not installed." >&2
    exit 1
fi
# We need fzf for interactive edit
FZF_INSTALLED=false
command -v fzf >/dev/null && FZF_INSTALLED=true
EDITOR="${EDITOR:-vi}" # Default to vi if EDITOR is not set

# --- Configuration Loading ---
CONFIG_FILE="$HOME/.config/hugo_wrapper.conf"
# Initialize potentially configurable variables to empty strings
PROJECT_PATH=""
DEPLOY_PATH=""
DEPLOY_HOST=""

if [[ -f "$CONFIG_FILE" ]]; then
    # Use process substitution to avoid subshell issues with the while loop
    while IFS='=' read -r key value || [[ -n "$key" ]]; do # Process last line even if no newline
        # Remove leading/trailing whitespace from key and value robustly
        key=$(echo "$key" | awk '{$1=$1};1')
        value=$(echo "$value" | awk '{$1=$1};1')

        # Skip comments and empty keys
        if [[ "$key" =~ ^# || -z "$key" ]]; then
            continue
        fi

        # Remove potential surrounding quotes from value
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"

        # Ensure variable names are valid bash identifiers
        if [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            # Use declare -g to ensure global scope assignment
            declare -g "$key=$value"
        fi
    done < <(cat "$CONFIG_FILE" 2>/dev/null || true) # Read config, ignore read errors if file vanishes mid-script
fi
# --- End Configuration Loading ---

# Default dry run to false
DRY_RUN=false

# --- Global Variable Validation ---
# This validation runs *after* config load but *before* options are parsed.
# Options can override these, and command-specific validation happens later if needed.

# Check required variables that MUST be set either by config or later by options
# Deployment vars are only strictly required for the deploy command itself.
# PROJECT_PATH is required for almost all commands.
if [ -z "${PROJECT_PATH:-}" ]; then
    echo "Warning: PROJECT_PATH is not set in config. It must be provided via -p option for most commands." >&2
fi
# We won't exit here anymore; validation will happen within command handlers after options are parsed.
# --- End Global Variable Validation ---

# --- Helper Functions ---

# Usage message (Updated)
usage() {
    local progname
    progname=$(basename "$0")
    cat <<EOF
Usage: ${progname} <command> [arguments] [OPTIONS]

Manage Hugo websites efficiently.

Requires 'hugo' and 'rsync'. 'fzf' is optional but needed for interactive edit.

Configuration is read from ${CONFIG_FILE} (if it exists).
Command-line options override configuration variables.

Required variables (can be set in config or via options):
  PROJECT_PATH      Path to the Hugo project root directory (required for most commands).
  DEPLOY_HOST       Remote host for deployment (required for 'deploy').
  DEPLOY_PATH       Remote directory path for deployment (required for 'deploy').

Commands:
  new post "<Title>"        Create a new post in content/posts/. Defaults to draft.
                            Opens in \$EDITOR if set.
  new page "<Title>"        Create a new page in content/pages/. Defaults to draft.
                            Opens in \$EDITOR if set.

  list [posts|pages] [draft|public]
                            List content with IDs. Filters are optional and can be
                            combined (e.g., list posts draft).
                            Examples:
                              list             # List all posts and pages
                              list posts       # List only posts
                              list draft       # List only drafts (posts and pages)
                              list pages public # List only published pages

  edit [ID...]             Open content file(s) with matching IDs in \$EDITOR.
  edit [posts|pages]       Interactively select content to edit using fzf.
                            (Requires fzf installed). Example: edit posts

  status <ID> [draft|public]
                            Show or set the draft status of content by ID.
                            Example:
                              status 1          # Show status of item with ID 1
                              status 1 draft    # Set item 1 to draft (draft: true)
                              status 1 public   # Set item 1 to public (draft: false)

  deploy                    Build the site (using 'production' environment) and deploy using rsync.

Common Options:
  -p, --project-path PATH   Override/set PROJECT_PATH for this run.
  -d, --deploy-path PATH    Override/set DEPLOY_PATH for this run.
  -H, --deploy-host HOST    Override/set DEPLOY_HOST for this run.
  --dry-run                 Perform a dry run (deploy command only).
  -h, --help                Display this help message and exit.

Examples:
  ${progname} new post "My Awesome Journey"
  ${progname} list posts draft
  ${progname} status 3 public
  ${progname} edit 1 5
  ${progname} edit pages # Requires fzf
  ${progname} deploy --dry-run -p /alt/project -H server2
EOF
}

# Helper: Parse common options
parse_common_options() {
    # Use getopt for robust option parsing
    local parsed_options OptsInd
    parsed_options=$(getopt -o p:d:H:h --long project-path:,deploy-path:,deploy-host:,dry-run,help -n "$(basename "$0")" -- "$@")

    if [[ $? -ne 0 ]]; then
        # getopt reports errors
        exit 1
    fi

    eval set -- "$parsed_options"

    while true; do
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
        --)
            shift
            break
            ;; # End of options marker
        *)
            echo "Internal error parsing options!" >&2
            exit 1
            ;;
        esac
    done
    # Remaining arguments ($@) are returned to the caller
}

# Helper: Validate project path exists and is absolute
validate_project_path() {
    if [ -z "${PROJECT_PATH:-}" ]; then
        echo "Error: PROJECT_PATH is required but not set (by config or -p option)." >&2
        usage >&2
        exit 1
    fi
    if [ ! -d "$PROJECT_PATH" ] || [ ! -d "$PROJECT_PATH/content" ]; then
        echo "Error: Project path '$PROJECT_PATH' doesn't exist or is not a valid Hugo project (missing content directory)." >&2
        exit 1
    fi
    # Convert to absolute path for consistency
    PROJECT_PATH=$(cd "$PROJECT_PATH" && pwd)
}

# Helper: Validate deploy parameters are set
validate_deploy_params() {
    local missing_vars=()
    if [ -z "${DEPLOY_HOST:-}" ]; then missing_vars+=("DEPLOY_HOST (-H)"); fi
    if [ -z "${DEPLOY_PATH:-}" ]; then missing_vars+=("DEPLOY_PATH (-d)"); fi

    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "Error: Required variable(s) for deployment not set (by config or options):" >&2
        printf " - %s\n" "${missing_vars[@]}" >&2
        usage >&2
        exit 1
    fi
}

# Helper: Slugify title
slugify() {
    local title="$1"
    echo "$title" | iconv -f utf-8 -t ascii//TRANSLIT | tr '[:upper:]' '[:lower:]' |
        tr -cs '[:alnum:]' '-' | sed 's/-\+/-/g; s/^-//; s/-$//'
}

# Helper: Get content files with IDs and details (for list, edit, status)
_get_content_files() {
    local type_filter="${1:-all}"   # posts, pages, all
    local status_filter="${2:-all}" # draft, public, all
    local id=0
    # PROJECT_PATH should be validated and absolute before calling this
    local content_dir="$PROJECT_PATH/content"
    local search_paths=()

    case "$type_filter" in
    posts) [[ -d "$content_dir/posts" ]] && search_paths+=("$content_dir/posts") ;;
    pages) [[ -d "$content_dir/pages" ]] && search_paths+=("$content_dir/pages") ;;
    all | *) # Default to both if they exist
        [[ -d "$content_dir/posts" ]] && search_paths+=("$content_dir/posts")
        [[ -d "$content_dir/pages" ]] && search_paths+=("$content_dir/pages")
        ;;
    esac

    if [[ ${#search_paths[@]} -eq 0 ]]; then
        return # Output nothing if no paths to search
    fi

    # Use find -print0 and read -d $'\0' for safer handling of filenames with spaces/special chars
    find "${search_paths[@]}" -maxdepth 1 -name '*.md' -type f -print0 | while IFS= read -r -d $'\0' file_path; do
        local rel_path="${file_path#"$content_dir/"}"
        local file_type="unknown"
        if [[ "$rel_path" == posts/* ]]; then
            file_type="post"
        elif [[ "$rel_path" == pages/* ]]; then
            file_type="page"
        fi

        # Determine status (draft: true/false)
        local is_draft="false" # Default public
        if grep -q -E '^[[:space:]]*draft:[[:space:]]*true' "$file_path"; then
            is_draft="true"
        fi
        local current_status="public"
        [ "$is_draft" = "true" ] && current_status="draft"

        # Apply filters
        local match_type=false
        local match_status=false
        [[ "$type_filter" == "all" || "$type_filter" == "${file_type}s" ]] && match_type=true
        [[ "$status_filter" == "all" || "$status_filter" == "$current_status" ]] && match_status=true

        if $match_type && $match_status; then
            id=$((id + 1))
            # Output tab-separated values
            printf "%d\t%s\t%s\t%s\n" "$id" "$current_status" "$file_type" "$rel_path"
        fi
    done | sort -t $'\t' -k4 # Sort by relative path for consistency
}

# Helper: Find file path by ID (for edit, status)
_find_file_by_id() {
    local target_id="$1"
    local found_path=""
    # PROJECT_PATH must be valid here
    # Search all files to find the ID, using the same listing logic
    # Use process substitution and capture output
    local file_list
    file_list=$(_get_content_files "all" "all")
    if [[ -n "$file_list" ]]; then
        while IFS=$'\t' read -r id _ _ rel_path; do
            if [[ "$id" == "$target_id" ]]; then
                found_path="$PROJECT_PATH/content/$rel_path"
                break
            fi
        done <<<"$file_list"
    fi
    echo "$found_path"
}

# --- Command Handlers ---

# Command: new post/page (Adapted from original, combined)
handle_new() {
    local type="$1" # post or page
    local title="$2"
    shift 2 # Consume type and title
    # Pass remaining args (options) to parser
    parse_common_options "$@"
    validate_project_path # Validate after options override config

    if [ -z "$title" ]; then
        echo "Error: Title is required for 'new $type'." >&2
        usage >&2
        exit 1
    fi

    local slug content_subdir date_prefix=""
    slug=$(slugify "$title")

    if [[ "$type" == "post" ]]; then
        date_prefix=$(date +%Y-%m-%d)-
        content_subdir="posts"
    elif [[ "$type" == "page" ]]; then
        content_subdir="pages"
    else
        echo "Internal Error: Invalid type '$type' passed to handle_new." >&2
        exit 1
    fi

    # Ensure the target directory exists within the project
    mkdir -p "${PROJECT_PATH}/content/${content_subdir}"

    local file_rel_path="content/${content_subdir}/${date_prefix}${slug}.md"
    local file_abs_path="${PROJECT_PATH}/${file_rel_path}"

    # Check if file already exists
    if [[ -e "$file_abs_path" ]]; then
        echo "Error: File already exists: $file_abs_path" >&2
        exit 1
    fi

    echo "Creating new $type: $file_rel_path"
    # Run hugo new from the project path context
    if ! hugo new "$file_rel_path" --cwd "$PROJECT_PATH"; then
        echo "Error: Hugo failed to create the $type." >&2
        exit 1
    fi
    echo "$type created successfully: $file_abs_path"

    # Ensure draft status is explicitly set to true
    if ! grep -q -E '^[[:space:]]*draft:[[:space:]]*' "$file_abs_path"; then
        if grep -q '^---$' "$file_abs_path"; then
            sed -i.bak '/^---$/a draft: true' "$file_abs_path"
        else
            sed -i.bak '1i draft: true' "$file_abs_path"
        fi
        rm -f "${file_abs_path}.bak" # Remove backup on success
    elif ! grep -q -E '^[[:space:]]*draft:[[:space:]]*true' "$file_abs_path"; then
        sed -i.bak 's/^[[:space:]]*draft:[[:space:]]*false/draft: true/' "$file_abs_path"
        rm -f "${file_abs_path}.bak"
    fi

    if [ -n "$EDITOR" ]; then
        echo "Opening in \$EDITOR ($EDITOR)..."
        eval "$EDITOR \"$file_abs_path\"" # Use eval for complex EDITOR vars
    fi
}

# Command: list (New)
handle_list() {
    local type_filter="all"
    local status_filter="all"
    local options_args=() # Arguments to pass to parse_common_options

    # Separate filters from options
    while [[ $# -gt 0 ]]; do
        case "$1" in
        posts | pages)
            if [[ "$type_filter" != "all" ]]; then
                echo "Error: Cannot specify more than one type filter." >&2
                usage >&2
                exit 1
            fi
            type_filter="$1"
            shift
            ;;
        draft | public)
            if [[ "$status_filter" != "all" ]]; then
                echo "Error: Cannot specify more than one status filter." >&2
                usage >&2
                exit 1
            fi
            status_filter="$1"
            shift
            ;;
        -*) # Option detected, pass it and subsequent args to option parser
            options_args+=("$@")
            break
            ;;
        *)
            echo "Error: Unknown list filter '$1'." >&2
            usage >&2
            exit 1
            ;;
        esac
    done

    parse_common_options "${options_args[@]}"
    validate_project_path # Requires PROJECT_PATH

    echo "Listing content in: $PROJECT_PATH/content"
    echo "Filters: Type=${type_filter}, Status=${status_filter}"
    echo "--------------------------------------------------"
    printf "%-5s %-8s %-6s %s\n" "ID" "Status" "Type" "Path"
    echo "--------------------------------------------------"

    local content_list
    content_list=$(_get_content_files "$type_filter" "$status_filter")

    if [ -z "$content_list" ]; then
        echo "No content found matching the criteria."
    else
        echo "$content_list" | column -t -s $'\t'
    fi
    echo "--------------------------------------------------"
}

# Command: edit (New)
handle_edit() {
    local ids=()
    local type_filter="all" # For fzf mode
    local non_option_args=()
    local options_args=()

    # Separate non-options (IDs, type) from options
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--" ]]; then
            shift
            options_args+=("$@")
            break # Handle '--' separator
        elif [[ "$1" == -* ]]; then
            options_args+=("$1")
            shift # Collect option flag
            # Check if option needs an argument (simple check)
            case "${options_args[-1]}" in -p | -d | -H | --project-path | --deploy-path | --deploy-host)
                if [[ -n "$1" && "$1" != -* ]]; then
                    options_args+=("$1")
                    shift
                fi
                ;;
            esac
        else
            non_option_args+=("$1")
            shift
        fi # Collect non-option arg
    done

    # Process collected non-option arguments
    for arg in "${non_option_args[@]}"; do
        case "$arg" in
        posts | pages)
            if [[ ${#ids[@]} -gt 0 ]]; then
                echo "Error: Cannot mix IDs and type filter (posts/pages) for edit." >&2
                usage >&2
                exit 1
            fi
            if [[ "$type_filter" != "all" ]]; then
                echo "Error: Cannot specify more than one type filter for interactive edit." >&2
                usage >&2
                exit 1
            fi
            type_filter="$arg"
            ;;
        [1-9] | [1-9][0-9]*) # Positive integer check for ID
            if [[ "$type_filter" != "all" ]]; then
                echo "Error: Cannot mix IDs and type filter (posts/pages) for edit." >&2
                usage >&2
                exit 1
            fi
            ids+=("$arg")
            ;;
        *)
            echo "Error: Unknown argument for edit: $arg" >&2
            usage >&2
            exit 1
            ;;
        esac
    done

    parse_common_options "${options_args[@]}"
    validate_project_path # Requires PROJECT_PATH

    local files_to_edit=()

    if [[ ${#ids[@]} -gt 0 ]]; then
        # --- Edit by ID ---
        echo "Attempting to edit by ID(s): ${ids[*]}"
        for id in "${ids[@]}"; do
            local file_path
            file_path=$(_find_file_by_id "$id") # Requires PROJECT_PATH to be set
            if [[ -z "$file_path" ]]; then
                echo "Warning: No content found with ID $id. Skipping." >&2
            elif [[ ! -f "$file_path" ]]; then
                echo "Warning: File for ID $id not found at '$file_path'. Skipping." >&2
            else
                files_to_edit+=("$file_path")
            fi
        done
    else
        # --- Interactive Edit using fzf ---
        if ! $FZF_INSTALLED; then
            echo "Error: 'fzf' is required for interactive editing. Please install fzf." >&2
            exit 1
        fi

        echo "Entering interactive edit mode (Type filter: ${type_filter})..."
        local content_list preview_cmd
        content_list=$(_get_content_files "$type_filter" "all") # Requires PROJECT_PATH

        if [ -z "$content_list" ]; then
            echo "No content found matching filter '$type_filter' to select from."
            exit 0
        fi

        # Preview command using absolute path
        preview_cmd="[[ -f \"${PROJECT_PATH}/content/{4}\" ]] && (bat --color=always --plain --line-range :15 \"${PROJECT_PATH}/content/{4}\" || head -n 15 \"${PROJECT_PATH}/content/{4}\") || echo 'File not found'"

        local selected_lines
        selected_lines=$(
            echo "$content_list" | fzf --multi --height 40% --border \
                --header $'[ID]\t[Status]\t[Type]\t[Path] (CTRL+Space to multi-select, Enter to confirm)' \
                \
                --bind='ctrl-space:toggle+up' --prompt="Select content (Type: $type_filter)> " # --preview="$preview_cmd" --preview-window='right:60%:wrap' \
        )

        if [[ -z "$selected_lines" ]]; then
            echo "No content selected."
            exit 0
        fi

        while IFS= read -r line; do
            local rel_path abs_path
            rel_path=$(echo "$line" | awk -F'\t' '{print $4}')
            if [[ -n "$rel_path" ]]; then
                abs_path="${PROJECT_PATH}/content/${rel_path}"
                if [[ -f "$abs_path" ]]; then
                    files_to_edit+=("$abs_path")
                else echo "Warning: Selected file path seems invalid: $abs_path" >&2; fi
            fi
        done <<<"$selected_lines"
    fi

    if [[ ${#files_to_edit[@]} -eq 0 ]]; then
        echo "No valid files selected or found to edit."
        exit 0
    fi

    echo "Opening selected file(s) in \$EDITOR ($EDITOR):"
    printf " - %s\n" "${files_to_edit[@]}"
    eval "$EDITOR \"${files_to_edit[@]}\"" # Use eval for complex EDITOR vars / multiple files
    echo "Finished editing."
}

# Command: status (New)
handle_status() {
    local id target_status=""
    local non_option_args=()
    local options_args=()

    # Separate non-options (ID, status) from options
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--" ]]; then
            shift
            options_args+=("$@")
            break
        elif [[ "$1" == -* ]]; then
            options_args+=("$1")
            shift
            case "${options_args[-1]}" in -p | -d | -H | --project-path | --deploy-path | --deploy-host)
                if [[ -n "$1" && "$1" != -* ]]; then
                    options_args+=("$1")
                    shift
                fi
                ;;
            esac
        else
            non_option_args+=("$1")
            shift
        fi
    done

    # Process non-option args for status command
    if [[ ${#non_option_args[@]} -lt 1 || ! "${non_option_args[0]}" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: Missing or invalid required ID argument for status command." >&2
        usage >&2
        exit 1
    fi
    id="${non_option_args[0]}"

    if [[ ${#non_option_args[@]} -gt 1 ]]; then
        if [[ "${non_option_args[1]}" == "draft" || "${non_option_args[1]}" == "public" ]]; then
            target_status="${non_option_args[1]}"
        else
            echo "Error: Invalid status '${non_option_args[1]}'. Must be 'draft' or 'public'." >&2
            usage >&2
            exit 1
        fi
    fi
    if [[ ${#non_option_args[@]} -gt 2 ]]; then
        echo "Error: Too many arguments provided for status command." >&2
        usage >&2
        exit 1
    fi

    parse_common_options "${options_args[@]}"
    validate_project_path # Requires PROJECT_PATH

    local file_path
    file_path=$(_find_file_by_id "$id") # Requires PROJECT_PATH

    if [[ -z "$file_path" ]]; then
        echo "Error: No content found with ID $id." >&2
        exit 1
    fi
    if [[ ! -f "$file_path" ]]; then
        echo "Error: File for ID $id not found at '$file_path' (internal error)." >&2
        exit 1
    fi

    local rel_path="${file_path#"$PROJECT_PATH/"}" # Get relative path for display

    # --- Display current status ---
    if [[ -z "$target_status" ]]; then
        local current_status="public" # Default assumption
        local draft_line
        draft_line=$(grep -E '^[[:space:]]*draft:[[:space:]]*(true|false)' "$file_path" 2>/dev/null || true)
        if [[ "$draft_line" =~ :[[:space:]]*true ]]; then current_status="draft"; fi
        echo "Status for ID $id ($rel_path): $current_status"
        exit 0
    fi

    # --- Set new status ---
    local new_draft_value="false"
    [[ "$target_status" == "draft" ]] && new_draft_value="true"
    local new_status_line="draft: ${new_draft_value}"

    echo "Setting status for ID $id ($rel_path) to: $target_status (${new_status_line})"

    # Use sed to replace the line or add it if missing (simple approach)
    local sed_script backup_needed=true
    if grep -q -E '^[[:space:]]*draft:[[:space:]]*' "$file_path"; then
        # Line exists, replace it
        sed_script="s|^[[:space:]]*draft:[[:space:]]*.*|${new_status_line}|"
    else
        # Line doesn't exist, add it after potential front matter marker or at top
        if grep -q '^---$' "$file_path"; then
            # Insert after first '---'
            sed_script="/^---$/a ${new_status_line}"
        else
            # Insert at the beginning
            sed_script="1i ${new_status_line}"
        fi
    fi

    # Check if status is already correct to avoid unnecessary modification
    local current_draft_value="false"
    if grep -q -E '^[[:space:]]*draft:[[:space:]]*true' "$file_path"; then current_draft_value="true"; fi
    if [[ "$current_draft_value" == "$new_draft_value" ]]; then
        echo "Status already set to '$target_status'. No changes made."
        backup_needed=false # No need to run sed or handle backup
    fi

    if $backup_needed; then
        # Execute sed with backup
        if sed -i.bak "$sed_script" "$file_path"; then
            echo "Status updated successfully."
            rm -f "${file_path}.bak" # Remove backup on success
        else
            echo "Error: Failed to update status in file '$file_path'." >&2
            # Attempt to restore backup if it exists
            [[ -f "${file_path}.bak" ]] && mv "${file_path}.bak" "$file_path" && echo "Restored backup." >&2
            exit 1
        fi
    fi
}

# Command: deploy (Adapted from original)
handle_deploy() {
    parse_common_options "$@" # Parse options like --dry-run
    validate_project_path     # Validate PROJECT_PATH
    validate_deploy_params    # Validate DEPLOY_HOST and DEPLOY_PATH

    local original_dir
    original_dir=$(pwd)
    cd "$PROJECT_PATH" || {
        echo "Error: Failed to cd into project path: $PROJECT_PATH" >&2
        exit 1
    }
    trap 'cd "$original_dir"' EXIT INT TERM # Ensure cd back

    echo "Generating the site with Hugo (environment: production)..."
    if ! hugo --minify --gc --environment production; then
        echo "Error: Failed during site generation." >&2
        exit 1
    fi

    if [[ ! -d "public" ]]; then
        echo "Error: Hugo build completed but 'public/' directory not found." >&2
        exit 1
    fi

    local RSYNC_OPTS=(-avz --delete --checksum --human-readable --progress)
    if [ "$DRY_RUN" = true ]; then
        RSYNC_OPTS+=(--dry-run)
        echo "--- DRY RUN MODE ---"
    fi

    echo "Deploying 'public/' contents to ${DEPLOY_HOST}:${DEPLOY_PATH}..."
    if ! rsync "${RSYNC_OPTS[@]}" public/ "${DEPLOY_HOST}:${DEPLOY_PATH}"; then
        echo "Error: Failed during rsync deployment." >&2
        exit 1
    fi

    if [ "$DRY_RUN" = true ]; then echo "--- DRY RUN COMPLETE ---"; else echo "--- DEPLOYMENT SUCCESSFUL ---"; fi

    trap - EXIT INT TERM # Disable trap on success
    cd "$original_dir" || true
}

# --- Main Command Dispatcher ---
if [[ "$#" -lt 1 ]]; then
    usage
    exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
new)
    if [[ "$#" -lt 2 ]]; then
        echo "Error: 'new' requires type (post/page) and title." >&2
        usage >&2
        exit 1
    fi
    handle_new "$@" # Pass type, title, options
    ;;
list)
    handle_list "$@" # Pass filters, options
    ;;
edit)
    handle_edit "$@" # Pass IDs or type filter, options
    ;;
status)
    if [[ "$#" -lt 1 ]]; then
        echo "Error: 'status' requires at least an ID." >&2
        usage >&2
        exit 1
    fi
    handle_status "$@" # Pass ID, [status], options
    ;;
deploy)
    handle_deploy "$@" # Pass options only
    ;;
-h | --help)
    usage
    exit 0
    ;;
*)
    echo "Error: Unknown command: $COMMAND" >&2
    usage
    exit 1
    ;;
esac
# --- End Command Dispatcher ---

exit 0 # Explicit success exit
