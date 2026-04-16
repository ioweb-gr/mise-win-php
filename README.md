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

### Use PHP directly

Once a version is installed, `php` is available as a normal command — no `mise exec` wrapper needed.

`mise install` / `mise use` automatically update the `php` shim. Add the shims directory to your PATH once and `php` resolves correctly from any project:

```
# Windows — add to your system/user PATH:
%LOCALAPPDATA%\mise\shims

# or use shell activation in your PowerShell profile:
# Invoke-Expression (&mise activate pwsh | Out-String)
```

Then just run `php` as usual:

```bash
php -v
php artisan ...
composer install
```

### Per-project PHP versions

Put a `mise.toml` in each project root. The `php` shim picks the right version automatically based on which directory you are in.

```
project-a/
  mise.toml    →  "win-php:php" = "8.1"

project-b/
  mise.toml    →  "win-php:php" = "8.3"

legacy-app/
  mise.toml    →  "win-php:php" = "7.4"
```

```bash
cd project-a && php -v    # PHP 8.1.x
cd project-b && php -v    # PHP 8.3.x
cd legacy-app && php -v   # PHP 7.4.x
```

Install all versions at once from the repo root or globally:

```bash
mise install win-php:php@8.1 win-php:php@8.3 win-php:php@7.4
```

### Update the plugin

Pull the latest plugin code (bug fixes, new PHP version support):

```bash
mise plugins update win-php
```

To pick up the changes for an already-installed PHP version, reinstall it:

```bash
mise install --force win-php:php@8.3
```

## What gets installed

For each PHP version the plugin:

1. Downloads the **Thread Safe x64** ZIP from `windows.php.net` (checks the releases page first, then archives).
2. Extracts it into Mise's install directory.
3. Downloads the latest **xdebug** ZIP for the matching PHP minor version and VC runtime from the [PECL Windows build server](https://windows.php.net/downloads/pecl/releases/xdebug/) and extracts the DLL into `ext/`.
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
| `hooks/backend_install.lua` | Downloads + extracts PHP, xdebug, pcov; writes `php.ini` via Lua `io` |
| `hooks/backend_exec_env.lua` | Returns `PATH = install_path` in `env_vars`; mise uses this to scan for executables and create shims (e.g. `php.cmd`), then strips it before applying env vars to the shell |

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
