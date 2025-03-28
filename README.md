# hugo_wrapper

Simple bash wrapper for managing [hugo](https://gohugo.io/) websites

## Usage

```bash
hugo_wrapper.sh <command> [subcommand/arguments] [OPTIONS]
```

- `PROJECT_PATH`, `DEPLOY_HOST` & `DEPLOY_PATH` variables must be set, either in the configuration file or via command line arguments.
- Configuration is read from `~/.config/hugo_wrapper.conf`, and command line arguments override the configuration.

### Commands

#### New Post

```bash
hugo_wrapper.sh new post "Post Title" [OPTIONS]
```

- Creates a new post.
- The post file will be created as `content/posts/<YYYY-MM-DD>-<slugified-title>.md`

#### New Page

```bash
hugo_wrapper.sh new page "Page Title" [OPTIONS]
```

- Creates a new page.
- The page file will be created as `content/pages/<slugified-title>.md`

#### Deploy

```bash
hugo_wrapper.sh deploy [OPTIONS]
```

- Builds the site with Hugo and deploys it using rsync
- Uses enhanced rsync options for robust transfers (--checksum, --human-readable, --progress)

### Common Options

- `-p, --project-path PATH` : Override the project directory
- `-d, --deploy-path PATH` : Override the remote deploy path
- `-H, --deploy-host HOST` : Override the remote deploy host
- `--dry-run` : Perform a deployment dry run (no actual changes)
- `-h, --help` : Display this help and exit

### Examples

```bash
hugo_wrapper.sh new post "My New Post"
hugo_wrapper.sh new page "About Me" --project-path /path/to/project
hugo_wrapper.sh deploy -p /path/to/project -d /remote/path -H myserver
hugo_wrapper.sh deploy --dry-run
```

## Example Configuration File

Create `~/.config/hugo_wrapper.conf` with content like:

```bash
# Hugo Wrapper Configuration
# Path to your Hugo project
PROJECT_PATH=/home/username/myhugosite

# Deployment settings
DEPLOY_HOST=user@example.com
DEPLOY_PATH=/var/www/mysite
```
