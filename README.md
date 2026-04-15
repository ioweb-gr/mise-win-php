# mise-win-php

A [Mise](https://mise.jdx.dev/) (asdf-compatible) plugin for installing PHP on Windows using prebuilt binaries from [windows.php.net](https://windows.php.net/downloads/releases/).

This plugin is designed as a reliable, Windows-native PHP installer that avoids building from source, making it a faster and simpler alternative to `vfox-php`.

## Requirements

* **Windows OS**: Works in Git Bash, MSYS2, and other common Windows shell environments.
* **curl**: Used for downloading binaries and fetching version lists.
* **tar**: Used for extraction (with a PowerShell fallback if `tar` is unavailable or fails).

## Installation

Add the plugin to Mise by providing the repository URL:

```bash
mise plugin add win-php https://github.com/your-username/mise-win-php.git
```

## Usage

### Install a Specific Version
Find the version you need from `windows.php.net` (Thread Safe x64 builds) and install it:

```bash
# List all available versions
mise ls-remote win-php

# Install a specific version
mise install win-php@8.2.27
```

### Set Global Version
To use a specific PHP version across your entire system:

```bash
mise global win-php@8.2.27
```

## How It Works

1.  **Version Listing (`bin/list-all`)**: 
    Dynamically scrapes `https://downloads.php.net/~windows/releases/` and its `archives/` directory. It identifies and lists only **Thread Safe (TS)** and **x64** versions, ensuring compatibility with most common Windows PHP setups.
2.  **Installation (`bin/install`)**:
    *   Finds the exact ZIP filename for the requested version (e.g., `php-8.2.27-Win32-vs16-x64.zip`).
    *   Downloads the ZIP to a temporary location within the install path.
    *   Extracts the content using `tar -xf`. If `tar` fails, it falls back to PowerShell's `Expand-Archive`.
    *   Automatically creates a default `php.ini` from `php.ini-development` if one doesn't exist.
    *   Cleans up the downloaded archive after a successful extraction.
3.  **Execution Environment (`bin/exec-env`)**:
    Adds the PHP installation directory to your `PATH`, ensuring that `php` and other binaries are available in your shell.

## Development & Releases

This project uses a `master` branch for the primary codebase.

### Auto-Release on Tag

A GitHub Actions workflow is included to automate releases. When you push a semantic version tag (e.g., `1.0.0`), a new GitHub Release is automatically created.

**To release a new version:**

1.  Ensure all changes are on the `master` branch.
2.  Tag the version (without a `v` prefix):
    ```bash
    git checkout master
    git pull
    git tag 1.0.0
    git push origin 1.0.0
    ```
3.  GitHub Actions will handle the rest, generating release notes and marking the release as latest.

## Troubleshooting

*   **Version Not Found**: If a specific version isn't listed, ensure it exists as a Thread Safe x64 ZIP on `windows.php.net/downloads/releases/`.
*   **Extraction Errors**: Ensure your terminal has permission to write to the Mise install directory. The plugin will attempt to use PowerShell if standard extraction tools fail.
