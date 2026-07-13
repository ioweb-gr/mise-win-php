--- Installs a specific version of a tool
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendinstall
function PLUGIN:BackendInstall(ctx)
    local http = require("http")
    local file = require("file")
    local tool = ctx.tool or "php"

    if RUNTIME.osType ~= "windows" then
        error("This plugin only supports installation on Windows. PHP binaries from windows.php.net are Windows-specific.")
    end

    local version = ctx.version
    local install_path = ctx.install_path
    local download_path = ctx.download_path

    local function install_composer()
        local composer_version = version

        local function composer_channel(version_spec)
            if version_spec == "latest" then
                return "stable"
            elseif version_spec == "1" or version_spec == "1.x" or version_spec == "1@latest" then
                return "1"
            elseif version_spec == "2" or version_spec == "2.x" or version_spec == "2@latest" then
                return "2"
            end

            return nil
        end

        local channel = composer_channel(composer_version)
        if channel then
            local requested_version = composer_version
            local resp, err = http.get({ url = "https://getcomposer.org/versions" })
            if err or resp.status_code ~= 200 then
                error("Could not resolve Composer " .. requested_version .. " from getcomposer.org")
            end

            local escaped_channel = channel:gsub("%.", "%%.")
            composer_version = resp.body:match('"' .. escaped_channel .. '"%s*:%s*%[%s*{.-"version"%s*:%s*"([^"]+)"')
            if not composer_version then
                error("Could not parse Composer " .. requested_version .. " from getcomposer.org")
            end
        end

        local composer_path = file.join_path(install_path, "composer.phar")
        local download_url = "https://getcomposer.org/download/" .. composer_version .. "/composer.phar"
        local _, dl_err = http.download_file({ url = download_url }, composer_path)
        if dl_err then
            error("Failed to download Composer " .. composer_version .. ": " .. tostring(dl_err))
        end

        local cmd_path = file.join_path(install_path, "composer.cmd")
        local f_cmd = io.open(cmd_path, "w")
        if not f_cmd then
            error("Could not write " .. cmd_path)
        end

        f_cmd:write("@echo off\r\n")
        f_cmd:write("setlocal\r\n")
        f_cmd:write("php \"%~dp0composer.phar\" %*\r\n")
        f_cmd:write("exit /b %ERRORLEVEL%\r\n")
        f_cmd:close()

        return {}
    end

    if tool == "composer" then
        return install_composer()
    elseif tool ~= "php" then
        error("Unsupported tool: " .. tool .. ". Supported tools are php and composer.")
    end

    local archiver = require("archiver")
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
    -- Use the PECL Windows build server (same source as pcov) so all PHP
    -- versions including 7.4 are covered without scraping xdebug.org.
    local xdebug_dll_path = nil
    do
        local semver = require("semver")
        local xdebug_base = "https://windows.php.net/downloads/pecl/releases/xdebug/"

        local resp, err = http.get({ url = xdebug_base })
        if err or resp.status_code ~= 200 then
            print("Warning: xdebug not installed: could not reach PECL xdebug releases")
        else
            local versions, seen = {}, {}
            for ver in resp.body:gmatch('href="([%d]+%.[%d]+%.[%d]+)/"') do
                if not seen[ver] then
                    table.insert(versions, ver)
                    seen[ver] = true
                end
            end

            if #versions == 0 then
                print("Warning: xdebug not installed: no versions found in PECL listing")
            else
                local sorted = semver.sort(versions)
                local latest = sorted[#sorted]
                local ver_url = xdebug_base .. latest .. "/"

                local resp2, err2 = http.get({ url = ver_url })
                if err2 or resp2.status_code ~= 200 then
                    print("Warning: xdebug not installed: could not fetch version directory for " .. latest)
                else
                    -- Pattern: php_xdebug-3.4.4-8.1-ts-vs16-x64.zip
                    local zip_pat = "php_xdebug%-[%d%.]+%-" .. escaped_minor .. "%-ts%-" .. vc_ver .. "%-x64%.zip"
                    local zip_name = resp2.body:match(zip_pat)
                    if not zip_name then
                        print("Warning: xdebug not installed: no build for PHP " .. php_minor .. " / " .. vc_ver)
                    else
                        local zip_dest = file.join_path(download_path, zip_name)
                        local _, xdl_err = http.download_file({ url = ver_url .. zip_name }, zip_dest)
                        if xdl_err then
                            print("Warning: xdebug not installed: download failed: " .. tostring(xdl_err))
                        else
                            archiver.decompress(zip_dest, ext_dir)
                            xdebug_dll_path = file.join_path(ext_dir, "php_xdebug.dll")
                        end
                    end
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

    -- Extensions required/recommended for Magento 2.
    -- gd2 = PHP 7.x name; gd = PHP 8.x name. Both listed; the pattern
    -- silently skips whichever name is absent from the template.
    local extensions = {
        "bcmath", "curl", "exif", "fileinfo",
        "gd", "gd2", "gettext", "iconv", "intl",
        "mbstring", "mysqli", "openssl", "pdo_mysql",
        "soap", "sockets", "sodium", "xsl", "zip",
    }

    local ini_source = file.exists(ini) and ini or ini_dev
    local f_in = io.open(ini_source, "r")
    if not f_in then
        print("Warning: could not open " .. ini_source)
    else
        local content = f_in:read("*a")
        f_in:close()

        -- Prepend \n so the very first line is reachable with the \n anchor.
        local text = "\n" .. content

        -- ;extension=name -> extension=name. The non-word suffix keeps gd from
        -- matching gd2, socket from matching sockets, etc.
        for _, ext in ipairs(extensions) do
            text = text:gsub("\n%s*;%s*(extension%s*=%s*" .. ext .. "[^%a%d_][^\n]*)", "\n%1")
        end

        -- ;zend_extension=opcache and ;zend_extension=php_opcache
        text = text:gsub("\n%s*;%s*(zend_extension%s*=%s*opcache[^\n]*)", "\n%1")
        text = text:gsub("\n%s*;%s*(zend_extension%s*=%s*php_opcache[^\n]*)", "\n%1")

        -- ;extension_dir = "..." (both the "./" and "ext" variants)
        text = text:gsub("\n%s*;%s*(extension_dir[^\n]*)", "\n%1")

        text = text:sub(2)

        -- Full path used for zend_extension so PHP finds the DLL regardless of
        -- how extension_dir is resolved at runtime.
        if xdebug_dll_path and not text:match("zend_extension%s*=%s*[^%r\n]*php_xdebug%.dll") then
            text = text .. "\n[xdebug]\n"
            text = text .. "zend_extension=" .. xdebug_dll_path .. "\n"
            text = text .. "xdebug.mode=debug,coverage\n"
            text = text .. "xdebug.start_with_request=trigger\n"
            text = text .. "xdebug.client_host=127.0.0.1\n"
            text = text .. "xdebug.client_port=9003\n"
        end

        if pcov_installed and not text:match("extension%s*=%s*php_pcov%.dll") then
            text = text .. "\n[pcov]\n"
            text = text .. "extension=php_pcov.dll\n"
        end

        local f_out = io.open(ini, "w")
        if not f_out then
            print("Warning: could not write " .. ini)
        else
            f_out:write(text)
            f_out:close()
            print("Ensured php.ini with Magento extensions enabled")
        end
    end

    return {}
end
