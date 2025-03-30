# hugo_wrapper

A Bash script to help manage Hugo websites, simplifying common tasks like creating content, managing draft status, editing, and deployment.

## Features

* Create new posts and pages with automatic naming conventions.
* List content (posts/pages) with filters for status (draft/public) and type.
* Assign temporary IDs to listed content for easy reference in subsequent commands.
* Edit content by ID or interactively using `fzf`.
* Check or update the draft status (`draft: true/false`) of content by ID.
* Build the Hugo site (using the `production` environment) and deploy via `rsync`.
* Load configuration from a central file.
* Override configuration via command-line options.

## Requirements

* Bash
* [Hugo](https://gohugo.io/)
* `rsync`
* Standard Unix tools (`find`, `grep`, `sed`, `awk`, `sort`, `column`, `mktemp`, `iconv`, `tr`, `cat`, `date`, `getopt`, `mkdir`)
* [`fzf`](https://github.com/junegunn/fzf) (Optional, but required for the interactive `edit` command without IDs)
* [`bat`](https://github.com/sharkdp/bat) (Optional, for syntax highlighting in `fzf` preview)

## Installation

1. Clone the repository or download the `hugo_wrapper.sh` script.
2. Make the script executable: `chmod +x hugo_wrapper.sh`
3. (Optional) Place it somewhere in your `$PATH` (e.g., `~/.local/bin/`)

## Configuration

The script reads configuration from `~/.config/hugo_wrapper.conf` if it exists. Command-line options will override settings from the config file.

Create the file `~/.config/hugo_wrapper.conf` with the following variables:

```bash
# Path to your Hugo project root directory
PROJECT_PATH=/path/to/your/hugo/site

# Deployment settings (only required for the 'deploy' command)
DEPLOY_HOST=[email address removed]
DEPLOY_PATH=/path/to/remote/webroot
```

* `PROJECT_PATH` is required for most commands.
* `DEPLOY_HOST` and `DEPLOY_PATH` are required only for the `deploy` command.

## Usage

```bash
hugo_wrapper.sh <command> [arguments] [OPTIONS]
```

## Commands

### `new`

Create new content. Defaults to `draft: true`. Opens in `$EDITOR` if set.

* `new post "<Title>"`
    Creates `content/posts/YYYY-MM-DD-slugified-title.md`.
* `new page "<Title>"`
    Creates `content/pages/slugified-title.md`.

### `list`

List content with temporary IDs. IDs are sequential and may change if files are added/removed.

* `list`
    Lists all posts and pages (draft and public).
* `list [posts|pages]`
    Filters by type.
* `list [draft|public]`
    Filters by status.
* `list [posts|pages] [draft|public]`
    Combines filters (order doesn't matter).

    Example: `list posts draft` lists only draft posts.

### `edit`

Open content in `$EDITOR`.

* `edit [ID...]`
    Opens the content file(s) corresponding to the temporary ID(s) obtained from `list`.
    Example: `edit 1 5`
* `edit [posts|pages]` (Requires `fzf`)
    Interactively select content to edit using `fzf`, optionally filtered by type.
    Example: `edit posts`

### `status`

Check or set the draft status (`draft: true/false` front matter).

* `status <ID>`
    Displays the current status (draft or public) for the content with the given temporary ID.
* `status <ID> [draft|public]`
    Sets the status for the content with the given ID. `draft` sets `draft: true`, `public` sets `draft: false`.
    Example: `status 3 public`

### `deploy`

Build the site using `hugo --environment production` and deploy the `public/` directory via `rsync` using common options (`-avz --delete --checksum`). Requires `DEPLOY_HOST` and `DEPLOY_PATH` to be set.

* `deploy`

## Common Options

These options override values set in the configuration file for the current run.

* `-p, --project-path PATH` : Set/Override the Hugo project directory path.
* `-d, --deploy-path PATH` : Set/Override the remote deployment path.
* `-H, --deploy-host HOST` : Set/Override the remote deployment host (e.g., `user@server`).
* `--dry-run` : Perform a dry run (for `deploy` command only, shows what `rsync` would do without making changes).
* `-h, --help` : Display the help message.

## Examples

```bash
# Create a new draft post
hugo_wrapper.sh new post "My First Draft"

# List all draft posts and get their IDs
hugo_wrapper.sh list posts draft

# Set post with ID 1 (from the list above) to public
hugo_wrapper.sh status 1 public

# Edit page with ID 3 (from a 'list' command) using the configured editor
hugo_wrapper.sh edit 3

# Interactively select a page to edit (requires fzf)
hugo_wrapper.sh edit pages

# Deploy the site using configuration from the file
hugo_wrapper.sh deploy

# Deploy the site, overriding the project path and doing a dry run
hugo_wrapper.sh deploy --dry-run -p /path/to/another/project
```
