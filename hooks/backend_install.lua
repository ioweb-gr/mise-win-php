--- Installs a specific version of a tool
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendinstall
function PLUGIN:BackendInstall(ctx)
    local http = require("http")
    local file = require("file")
    local archiver = require("archiver")

    if RUNTIME.osType ~= "windows" then
        error("This plugin only supports installation on Windows. PHP binaries from windows.php.net are Windows-specific.")
    end

    local version = ctx.version
    local install_path = ctx.install_path
    local download_path = ctx.download_path
    local base_url = "https://downloads.php.net/~windows/releases/"

    -- Escape dots in the version string for use as a Lua pattern
    local escaped_version = version:gsub("%.", "%%.")

    -- Find the zip filename for the requested version on a given URL
    local function find_zip(url)
        local resp, err = http.get({ url = url })
        if err or resp.status_code ~= 200 then
            return nil
        end
        for filename in resp.body:gmatch("php%-" .. escaped_version .. "%-Win32%-[^\"]*%-x64%.zip") do
            if not filename:find("%-nts%-") then
                return filename
            end
        end
        return nil
    end

    -- Try the releases page first, then archives
    local filename = find_zip(base_url)
    local download_url

    if filename then
        download_url = base_url .. filename
    else
        filename = find_zip(base_url .. "archives/")
        if filename then
            download_url = base_url .. "archives/" .. filename
        end
    end

    if not filename then
        error("Could not find PHP version " .. version .. " (Thread Safe, x64) on windows.php.net")
    end

    -- Download to the mise-provided download directory
    local zip_path = file.join_path(download_path, filename)
    local _, dl_err = http.download_file({ url = download_url }, zip_path)
    if dl_err then
        error("Failed to download PHP " .. version .. ": " .. tostring(dl_err))
    end

    -- Extract the zip into the install directory
    archiver.decompress(zip_path, install_path)

    -- Set up php.ini with extensions enabled for Magento 2.
    -- file.read is available but file.write is not in the mise Lua API, so we use
    -- PowerShell to read, patch, and write the ini file entirely on the Windows side.
    -- This avoids passing file content through command-line arguments.
    local ini_dev = file.join_path(install_path, "php.ini-development")
    local ini = file.join_path(install_path, "php.ini")
    if file.exists(ini_dev) and not file.exists(ini) then
        local cmd = require("cmd")

        -- Extensions to enable for Magento 2 (covers PHP 7.x and 8.x naming).
        -- gd2 = PHP 7.x name; gd = PHP 8.x name. Both are listed; only the
        -- matching line in the ini file will be uncommented.
        local extensions = {
            "bcmath", "curl", "exif", "fileinfo",
            "gd", "gd2", "gettext", "iconv", "intl",
            "mbstring", "mysqli", "openssl", "pdo_mysql",
            "soap", "sockets", "sodium", "xsl", "zip",
        }

        -- Build a .NET regex alternation group, e.g. "bcmath|curl|..."
        local ext_pattern = table.concat(extensions, "|")

        -- PowerShell reads ini-development, uncomments matching extension= lines,
        -- and writes the result as php.ini.  Single-quoted PS strings are used
        -- throughout so there is no conflict with the outer double-quote wrapping
        -- required by -Command "...".
        --
        -- Regex explanation:
        --   ^;(extension=(?:bcmath|curl|...))  — leading semicolon then capture group
        --   Replacement: $1                     — drop the semicolon, keep the rest
        --
        -- opcache is a zend_extension, handled with a separate replace.
        local ps_cmd = string.format(
            "$c=Get-Content -LiteralPath '%s';" ..
            "$c=$c -replace '^;(extension=(?:%s))','$1';" ..
            "$c=$c -replace '^;(zend_extension=opcache)','$1';" ..
            "$c=$c -replace '^;(zend_extension=php_opcache)','$1';" ..
            "$c|Set-Content -LiteralPath '%s'",
            ini_dev, ext_pattern, ini
        )

        local ok, err = pcall(function()
            cmd.exec("powershell -NoProfile -ExecutionPolicy Bypass -Command \"" .. ps_cmd .. "\"")
        end)

        if not ok then
            -- Non-fatal: PHP works with compiled-in defaults.
            -- php.ini-development is in the install dir for manual setup.
            print("Warning: could not create php.ini automatically: " .. tostring(err))
        end
    end

    return {}
end
