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
    -- pcall cannot wrap async functions (yields across C boundary), so errors are
    -- handled via return-value checks instead.
    local xdebug_dll_path = nil
    do
        local semver = require("semver")
        -- Scrape the download page (not /files/ which is a 404 directory listing).
        -- TS builds are named: php_xdebug-{ver}-{phpver}-ts-{vc}-x86_64.dll
        local resp, err = http.get({ url = "https://xdebug.org/download" })
        if err or resp.status_code ~= 200 then
            local reason = err and tostring(err) or ("HTTP " .. tostring(resp.status_code))
            print("Warning: xdebug not installed: could not reach xdebug.org/download: " .. reason)
        else
            local pat = "php_xdebug%-([%d%.]+)%-" .. escaped_minor .. "%-ts%-" .. vc_ver .. "%-x86_64%.dll"
            local versions, seen = {}, {}
            for ver in resp.body:gmatch(pat) do
                if not seen[ver] then
                    table.insert(versions, ver)
                    seen[ver] = true
                end
            end

            if #versions == 0 then
                print("Warning: xdebug not installed: no TS build found for PHP " .. php_minor .. " / " .. vc_ver)
            else
                local sorted = semver.sort(versions)
                local latest = sorted[#sorted]
                local dll_name = string.format("php_xdebug-%s-%s-ts-%s-x86_64.dll", latest, php_minor, vc_ver)
                local dll_dest = file.join_path(ext_dir, dll_name)
                local _, xdl_err = http.download_file({ url = "https://xdebug.org/files/" .. dll_name }, dll_dest)
                if xdl_err then
                    print("Warning: xdebug not installed: download failed: " .. tostring(xdl_err))
                else
                    xdebug_dll_path = dll_dest
                end
            end
        end
    end

    -- ── pcov ─────────────────────────────────────────────────────────────────
    -- Find the latest pcov release on the PECL Windows build server, download
    -- the TS zip for this PHP version, and extract the DLL into ext/.
    local pcov_installed = false
    do
        local semver = require("semver")
        local pcov_base = "https://windows.php.net/downloads/pecl/releases/pcov/"

        local resp, err = http.get({ url = pcov_base })
        if err or resp.status_code ~= 200 then
            print("Warning: pcov not installed: could not reach PECL pcov releases")
        else
            -- Directory listing has links like href="1.0.12/"
            local versions, seen = {}, {}
            for ver in resp.body:gmatch('href="([%d]+%.[%d]+%.[%d]+)/"') do
                if not seen[ver] then
                    table.insert(versions, ver)
                    seen[ver] = true
                end
            end

            if #versions == 0 then
                print("Warning: pcov not installed: no versions found in PECL listing")
            else
                local sorted = semver.sort(versions)
                local latest = sorted[#sorted]
                local ver_url = pcov_base .. latest .. "/"

                local resp2, err2 = http.get({ url = ver_url })
                if err2 or resp2.status_code ~= 200 then
                    print("Warning: pcov not installed: could not fetch version directory for " .. latest)
                else
                    -- Pattern: php_pcov-1.0.12-8.3-ts-vs16-x64.zip
                    local zip_pat = "php_pcov%-[%d%.]+%-" .. escaped_minor .. "%-ts%-" .. vc_ver .. "%-x64%.zip"
                    local zip_name = resp2.body:match(zip_pat)
                    if not zip_name then
                        print("Warning: pcov not installed: no build for PHP " .. php_minor .. " / " .. vc_ver)
                    else
                        local zip_dest = file.join_path(download_path, zip_name)
                        local _, pdl_err = http.download_file({ url = ver_url .. zip_name }, zip_dest)
                        if pdl_err then
                            print("Warning: pcov not installed: download failed: " .. tostring(pdl_err))
                        else
                            -- PECL zips place the DLL at the root; extract directly into ext/
                            archiver.decompress(zip_dest, ext_dir)
                            pcov_installed = true
                        end
                    end
                end
            end
        end
    end

    -- ── php.ini ──────────────────────────────────────────────────────────────
    -- Patch php.ini-development → php.ini entirely in Lua (standard io library).
    -- Avoids the PowerShell → cmd.exe path, which mangles regex metacharacters
    -- like ^ ( ) when they pass through CMD.EXE's command-line parser.
    local ini_dev = file.join_path(install_path, "php.ini-development")
    local ini = file.join_path(install_path, "php.ini")

    if file.exists(ini_dev) and not file.exists(ini) then
        -- Extensions required/recommended for Magento 2.
        -- gd2 = PHP 7.x name; gd = PHP 8.x name.  Both listed; the
        -- pattern silently skips whichever name is absent from the template.
        local extensions = {
            "bcmath", "curl", "exif", "fileinfo",
            "gd", "gd2", "gettext", "iconv", "intl",
            "mbstring", "mysqli", "openssl", "pdo_mysql",
            "soap", "sockets", "sodium", "xsl", "zip",
        }

        local f_in = io.open(ini_dev, "r")
        if not f_in then
            print("Warning: could not open " .. ini_dev)
        else
            local content = f_in:read("*a")
            f_in:close()

            -- Uncomment matching lines.
            -- Prepend \n so the very first line is reachable with the \n; anchor.
            local text = "\n" .. content

            -- ;extension=name  →  extension=name
            -- [^%a%d_] after the name ensures "gd" never matches "gd2",
            -- "socket" never matches "sockets", etc.  It also matches the
            -- trailing \n, so end-of-line lines are handled in one pass.
            for _, ext in ipairs(extensions) do
                text = text:gsub("\n;(extension=" .. ext .. "[^%a%d_][^\n]*)", "\n%1")
            end

            -- ;zend_extension=opcache  and  ;zend_extension=php_opcache
            text = text:gsub("\n;(zend_extension=opcache[^\n]*)", "\n%1")
            text = text:gsub("\n;(zend_extension=php_opcache[^\n]*)", "\n%1")

            -- ;extension_dir = "..."  (both the "./" and "ext" variants)
            text = text:gsub("\n;(extension_dir[^\n]*)", "\n%1")

            -- Remove the prepended \n
            text = text:sub(2)

            local f_out = io.open(ini, "w")
            if not f_out then
                print("Warning: could not write " .. ini)
            else
                f_out:write(text)
                f_out:close()
                print("Created php.ini with extensions enabled")

                -- Append xdebug section.
                -- Full path used for zend_extension so PHP finds the DLL
                -- regardless of how extension_dir is resolved at runtime.
                if xdebug_dll_path then
                    local f_xd = io.open(ini, "a")
                    if f_xd then
                        f_xd:write("\n[xdebug]\n")
                        f_xd:write("zend_extension=" .. xdebug_dll_path .. "\n")
                        f_xd:write("xdebug.mode=debug,coverage\n")
                        f_xd:write("xdebug.start_with_request=trigger\n")
                        f_xd:write("xdebug.client_host=127.0.0.1\n")
                        f_xd:write("xdebug.client_port=9003\n")
                        f_xd:close()
                    end
                end

                -- Append pcov section.
                if pcov_installed then
                    local f_pcov = io.open(ini, "a")
                    if f_pcov then
                        f_pcov:write("\n[pcov]\n")
                        f_pcov:write("extension=php_pcov.dll\n")
                        f_pcov:close()
                    end
                end
            end
        end
    end

    return {}
end
