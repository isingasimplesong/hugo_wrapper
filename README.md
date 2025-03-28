# hugo_wrapper

Simple bash wrapper for managing my [hugo](https://gohugo.io/) websites

## Usage

```bash
Usage: hugo_wrapper.sh <command> [subcommand/arguments] [OPTIONS]
```

**Note:**

- `PROJECT_PATH`, `DEPLOY_HOST` & `DEPLOY_PATH` variables must be set, either in the configuration file or via command line arguments.
- Configuration is read from `~/.config/hugo_wrapper.conf`, and command line arguments override the configuration.

---

### Commands

#### New Post

```bash
hugo_wrapper.sh new post "Post Title" [OPTIONS]
```

- **Description:** Creates a new post.
- **File Creation:** The post file will be created as:

  ```
  content/posts/<YYYY-MM-DD>-<slugified-title>.md
  ```

#### New Page

```bash
hugo_wrapper.sh new page "Page Title" [OPTIONS]
```

- **Description:** Creates a new page.
- **File Creation:** The page file will be created as:

  ```
  content/pages/<slugified-title>.md
  ```

#### Deploy

```bash
hugo_wrapper.sh deploy [OPTIONS]
```

- **Description:** Builds the site with Hugo and deploys it using rsync.

---

### Common Options

- `-p, --project-path PATH`
  Override the project directory.
- `-d, --deploy-path PATH`
  Override the remote deploy path.
- `-H, --deploy-host HOST`
  Override the remote deploy host.
- `-h, --help`
  Display this help and exit.

---

### Examples

```bash
hugo_wrapper.sh new post "My New Post"
hugo_wrapper.sh new page "About Me" --project-path /path/to/project
hugo_wrapper.sh deploy -p /path/to/project -d /remote/path -H myserver
```
