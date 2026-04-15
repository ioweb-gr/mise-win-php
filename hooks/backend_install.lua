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

    -- Set up default php.ini from the development template if not already present
    local ini_dev = file.join_path(install_path, "php.ini-development")
    local ini = file.join_path(install_path, "php.ini")
    if file.exists(ini_dev) and not file.exists(ini) then
        local cmd = require("cmd")
        cmd.exec("cmd /c copy \"" .. ini_dev .. "\" \"" .. ini .. "\"")
    end

    return {}
end
