# win-php (Mise Backend Plugin)

A [Mise](https://mise.jdx.dev/) backend plugin for installing PHP on Windows using pre-built binaries from [windows.php.net](https://windows.php.net/downloads/releases/).

This plugin uses the enhanced [Mise Backend Architecture](https://mise.jdx.dev/backend-plugin-development.html) (based on vfox) to provide a robust, cross-platform version listing and Windows-native installation.

## Requirements

* **Windows OS**: Installation and execution is only supported on Windows.
* **Mise**: Installed and configured on your system.
* **Experimental Features**: Since this is a backend plugin, you must enable experimental features in Mise:
  ```bash
  mise settings set experimental true
  ```
* **PowerShell**: Used for installation and extraction logic.

## Installation

Add the plugin to Mise by providing the repository URL:

```bash
mise plugin install win-php https://github.com/ioweb-repos/mise-win-php.git
```

## Usage

As a backend plugin, it uses the `backend:tool@version` format. The tool name is currently `php` (Thread Safe, x64).

### List Available Versions

```bash
# List all available versions for PHP on Windows
mise ls-remote win-php:php
```

### Install a Specific Version

```bash
# Install a specific version
mise use win-php:php@8.3.11
```

### Global Configuration

```bash
# Set global version in mise.toml
mise use -g win-php:php@8.3.11
```

## How It Works

This plugin transitions from standard asdf-style scripts to the modern backend architecture:

1.  **Metadata (`metadata.lua`)**: Defines the backend as `win-php`.
2.  **Version Listing (`hooks/backend_list_versions.lua`)**: 
    Implemented in Lua for cross-platform performance. It dynamically scrapes `https://downloads.php.net/~windows/releases/` and its `archives/` directory using Mise's built-in `http` module. It identifies only **Thread Safe (TS)** and **x64** versions.
3.  **Installation (`hooks/backend_install.lua`)**:
    Validates that the target OS is Windows and then delegates the heavy lifting to a PowerShell script (`scripts/install.ps1`).
    *   Finds the exact ZIP filename for the requested version.
    *   Downloads and extracts the ZIP using native PowerShell commands (`Invoke-WebRequest`, `Expand-Archive`).
    *   Automatically creates a default `php.ini` from `php.ini-development` if one doesn't exist.
4.  **Execution Environment (`hooks/backend_exec_env.lua`)**:
    Correctly sets up the `PATH` variable to include the PHP installation directory.

## Development

This project uses the `master` branch for the primary codebase.

### Tagging & Releases

Push a semantic version tag (e.g., `1.1.0`) to trigger the automated GitHub Release workflow.

```bash
git tag 1.1.0
git push origin 1.1.0
```

## Troubleshooting

*   **Version Not Found**: Ensure the requested version exists as a Thread Safe x64 ZIP on `windows.php.net/downloads/releases/`.
*   **Unsupported OS**: If you try to list versions on Linux/macOS, it will work (listing the remote Windows versions), but attempting to **install** will result in an error message explaining that it is only for Windows.
