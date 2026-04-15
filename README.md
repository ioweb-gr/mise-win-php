# win-php (Mise Backend Plugin)

A [Mise](https://mise.jdx.dev/) backend plugin for installing PHP on Windows using pre-built binaries from [windows.php.net](https://windows.php.net/downloads/releases/).

## Requirements

* **Windows OS** — installation and execution is only supported on Windows.
* **Mise** — installed and configured on your system.
* **Experimental features** — required for backend plugins:
  ```bash
  mise settings set experimental true
  ```

## Installation

```bash
mise plugin install win-php https://github.com/ioweb-gr/mise-win-php.git
```

## Usage

The tool name is `php`; the backend prefix is `win-php`. All commands use the `win-php:php@version` format.

### List available versions

```bash
mise ls-remote win-php:php
```

### Install a version

```bash
mise use win-php:php@8.3
```

### Set a global default

```bash
mise use -g win-php:php@8.3
```

### Run a single command with `mise exec`

```bash
# Check the installed version
mise exec win-php:php@8.3 -- php -v

# Run a script
mise exec win-php:php@8.3 -- php my-script.php

# Open the interactive REPL
mise exec win-php:php@8.3 -- php -a
```

If you have a `mise.toml` in your project that already pins the version, you can omit the tool argument:

```bash
# mise.toml already contains: win-php:php = "8.3"
mise exec -- php -v
```

## What gets installed

For each PHP version the plugin:

1. Downloads the **Thread Safe x64** ZIP from `windows.php.net` (checks the releases page first, then archives).
2. Extracts it into Mise's install directory.
3. Downloads the latest **xdebug** DLL for the matching PHP minor version and VC runtime from [xdebug.org](https://xdebug.org/files/) and places it in `ext/`.
4. Downloads the latest **pcov** DLL from the [PECL Windows build server](https://windows.php.net/downloads/pecl/releases/pcov/) and extracts it into `ext/`.
5. Creates **`php.ini`** from `php.ini-development` with the following pre-configured:

   **Extensions enabled** (uncommented from the template):
   `bcmath`, `curl`, `exif`, `fileinfo`, `gd`/`gd2`, `gettext`, `iconv`, `intl`, `mbstring`, `mysqli`, `openssl`, `pdo_mysql`, `soap`, `sockets`, `sodium`, `xsl`, `zip`, `opcache`

   **xdebug section appended:**
   ```ini
   [xdebug]
   zend_extension=<full path to xdebug DLL>
   xdebug.mode=debug,coverage
   xdebug.start_with_request=trigger
   xdebug.client_host=127.0.0.1
   xdebug.client_port=9003
   ```

   **pcov section appended:**
   ```ini
   [pcov]
   extension=php_pcov.dll
   ```

> xdebug and pcov downloads are non-fatal. If either fails (e.g. no build available for a given PHP version), the PHP installation still completes and a warning is printed.

## How it works

| File | Purpose |
|------|---------|
| `metadata.lua` | Declares the plugin as `win-php` |
| `hooks/backend_list_versions.lua` | Scrapes `windows.php.net` for TS x64 ZIPs using Mise's built-in `http` module; returns a semver-sorted list |
| `hooks/backend_install.lua` | Downloads + extracts PHP, xdebug, pcov; writes `php.ini` via PowerShell (Lua has `file.read` but no `file.write`) |
| `hooks/backend_exec_env.lua` | Adds the PHP install directory to `PATH` and `bin_paths` so Mise can find `php.exe` |

## Troubleshooting

* **Version not found** — verify the version exists as a TS x64 ZIP on `windows.php.net/downloads/releases/`. Use `mise ls-remote win-php:php` to see what is available.
* **Install fails on Linux/macOS** — listing remote versions works on any OS, but `mise install` will error because the PHP binaries are Windows-only.
* **xdebug/pcov not installed** — run with `mise --debug install win-php:php@X.Y` to see which step failed. You can install them manually by downloading the DLL into the `ext/` subdirectory of the PHP install path and adding the appropriate `php.ini` lines.
* **php.ini not created** — `php.ini-development` is always present in the install directory; copy it to `php.ini` manually and edit as needed.

## Development

### Tagging a release

Push a semantic version tag to trigger the automated GitHub Release workflow:

```bash
git tag 1.2.0
git push origin 1.2.0
```
