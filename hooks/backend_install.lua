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
        if err or resp.status_code ~= 200 then return nil end
        for fname in resp.body:gmatch("php%-" .. escaped_version .. "%-Win32%-[^\"]*%-x64%.zip") do
            if not fname:find("%-nts%-") then return fname end
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

    -- Download and extract PHP
    local zip_path = file.join_path(download_path, filename)
    local _, dl_err = http.download_file({ url = download_url }, zip_path)
    if dl_err then
        error("Failed to download PHP " .. version .. ": " .. tostring(dl_err))
    end
    archiver.decompress(zip_path, install_path)

    -- Derive PHP minor version ("8.3", "7.4") and VC runtime ("vs16", "vc15", "vs17")
    -- from the downloaded zip filename, e.g. "php-8.3.30-Win32-vs16-x64.zip"
    local php_minor = version:match("^(%d+%.%d+)")
    local vc_ver = filename:match("Win32%-([^%-]+)%-x64")
    local escaped_minor = php_minor:gsub("%.", "%%.")

    local ext_dir = file.join_path(install_path, "ext")

    -- ── xdebug ───────────────────────────────────────────────────────────────
    -- Fetch the xdebug.org file listing and download the latest DLL that matches
    -- this PHP minor version and VC runtime.  xdebug ships a single .dll (no zip).
    local xdebug_dll_path = nil
    pcall(function()
        local semver = require("semver")
        local xdebug_base = "https://xdebug.org/files/"

        local resp, err = http.get({ url = xdebug_base })
        if err or resp.status_code ~= 200 then
            error("Could not reach xdebug.org/files/")
        end

        -- Pattern: php_xdebug-3.4.4-8.3-vs16-x86_64.dll
        local pat = "php_xdebug%-([%d%.]+)%-" .. escaped_minor .. "%-" .. vc_ver .. "%-x86_64%.dll"

        local versions, seen = {}, {}
        for ver in resp.body:gmatch(pat) do
            if not seen[ver] then
                table.insert(versions, ver)
                seen[ver] = true
            end
        end
        if #versions == 0 then
            error("No xdebug build found for PHP " .. php_minor .. " / " .. vc_ver)
        end

        local sorted = semver.sort(versions)
        local latest = sorted[#sorted]
        local dll_name = string.format("php_xdebug-%s-%s-%s-x86_64.dll", latest, php_minor, vc_ver)

        local dll_dest = file.join_path(ext_dir, dll_name)
        local _, xdl_err = http.download_file({ url = xdebug_base .. dll_name }, dll_dest)
        if xdl_err then
            error("Failed to download xdebug: " .. tostring(xdl_err))
        end

        xdebug_dll_path = dll_dest
    end)

    -- ── pcov ─────────────────────────────────────────────────────────────────
    -- Find the latest pcov release on the PECL Windows build server, download
    -- the TS zip for this PHP version, and extract the DLL into ext/.
    local pcov_installed = false
    pcall(function()
        local semver = require("semver")
        local pcov_base = "https://windows.php.net/downloads/pecl/releases/pcov/"

        local resp, err = http.get({ url = pcov_base })
        if err or resp.status_code ~= 200 then
            error("Could not reach PECL pcov releases")
        end

        -- Directory listing has links like href="1.0.12/"
        local versions, seen = {}, {}
        for ver in resp.body:gmatch('href="([%d]+%.[%d]+%.[%d]+)/"') do
            if not seen[ver] then
                table.insert(versions, ver)
                seen[ver] = true
            end
        end
        if #versions == 0 then
            error("No pcov versions found in PECL listing")
        end

        local sorted = semver.sort(versions)
        local latest = sorted[#sorted]
        local ver_url = pcov_base .. latest .. "/"

        resp, err = http.get({ url = ver_url })
        if err or resp.status_code ~= 200 then
            error("Could not fetch pcov version directory for " .. latest)
        end

        -- Pattern: php_pcov-1.0.12-8.3-ts-vs16-x64.zip
        local zip_pat = "php_pcov%-[%d%.]+%-" .. escaped_minor .. "%-ts%-" .. vc_ver .. "%-x64%.zip"
        local zip_name = resp.body:match(zip_pat)
        if not zip_name then
            error("No pcov build for PHP " .. php_minor .. " / " .. vc_ver)
        end

        local zip_dest = file.join_path(download_path, zip_name)
        local _, pdl_err = http.download_file({ url = ver_url .. zip_name }, zip_dest)
        if pdl_err then
            error("Failed to download pcov: " .. tostring(pdl_err))
        end

        -- PECL zips place the DLL at the root; extract directly into ext/
        archiver.decompress(zip_dest, ext_dir)
        pcov_installed = true
    end)

    -- ── php.ini ──────────────────────────────────────────────────────────────
    -- Use PowerShell to create php.ini from php.ini-development with:
    --   • Magento 2 extensions uncommented
    --   • opcache (zend_extension) enabled
    --   • extension_dir uncommented
    --   • xdebug and pcov sections appended (if downloaded above)
    --
    -- file.read exists but file.write does not in the mise Lua API, so all
    -- read-patch-write operations happen entirely inside PowerShell — no file
    -- content passes through command-line arguments.
    local ini_dev = file.join_path(install_path, "php.ini-development")
    local ini = file.join_path(install_path, "php.ini")

    if file.exists(ini_dev) and not file.exists(ini) then
        local cmd = require("cmd")

        -- Extensions required/recommended for Magento 2.
        -- gd2 = PHP 7.x name; gd = PHP 8.x name.  Both listed; the regex
        -- silently skips whichever name is absent from the ini template.
        local extensions = {
            "bcmath", "curl", "exif", "fileinfo",
            "gd", "gd2", "gettext", "iconv", "intl",
            "mbstring", "mysqli", "openssl", "pdo_mysql",
            "soap", "sockets", "sodium", "xsl", "zip",
        }
        local ext_pattern = table.concat(extensions, "|")

        -- Uncomment extensions, opcache, and extension_dir in one pass
        local ps_setup = string.format(
            "$c=Get-Content -LiteralPath '%s';" ..
            "$c=$c -replace '^;(extension=(?:%s))','$1';" ..
            "$c=$c -replace '^;(zend_extension=opcache)','$1';" ..
            "$c=$c -replace '^;(zend_extension=php_opcache)','$1';" ..
            "$c=$c -replace '^;(extension_dir)','$1';" ..
            "$c|Set-Content -LiteralPath '%s'",
            ini_dev, ext_pattern, ini
        )

        local ini_ok, ini_err = pcall(function()
            cmd.exec("powershell -NoProfile -ExecutionPolicy Bypass -Command \"" .. ps_setup .. "\"")
        end)

        if not ini_ok then
            print("Warning: could not create php.ini: " .. tostring(ini_err))
        else
            -- Append xdebug section if the DLL was downloaded successfully.
            -- Full path is used for zend_extension so it works regardless of
            -- whether extension_dir resolves correctly at runtime.
            if xdebug_dll_path then
                local xdebug_ps = string.format(
                    "Add-Content -LiteralPath '%s' -Value " ..
                    "'','[xdebug]'," ..
                    "'zend_extension=%s'," ..
                    "'xdebug.mode=debug,coverage'," ..
                    "'xdebug.start_with_request=trigger'," ..
                    "'xdebug.client_host=127.0.0.1'," ..
                    "'xdebug.client_port=9003'",
                    ini, xdebug_dll_path
                )
                pcall(function()
                    cmd.exec("powershell -NoProfile -ExecutionPolicy Bypass -Command \"" .. xdebug_ps .. "\"")
                end)
            end

            -- Append pcov section if the DLL was extracted successfully.
            if pcov_installed then
                local pcov_ps = string.format(
                    "Add-Content -LiteralPath '%s' -Value '','[pcov]','extension=php_pcov.dll'",
                    ini
                )
                pcall(function()
                    cmd.exec("powershell -NoProfile -ExecutionPolicy Bypass -Command \"" .. pcov_ps .. "\"")
                end)
            end
        end
    end

    return {}
end
