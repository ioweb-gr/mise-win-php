--- Installs a specific version of a tool
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendinstall
function PLUGIN:BackendInstall(ctx)
    local cmd = require("cmd")
    local file = require("file")

    if RUNTIME.osType ~= "windows" then
        error("This plugin only supports installation on Windows. PHP binaries from windows.php.net are Windows-specific.")
    end

    local ps1_path = file.join_path(RUNTIME.pluginDirPath, "scripts", "install.ps1")

    -- Call the existing PowerShell install script
    local install_cmd = string.format("powershell -NoProfile -ExecutionPolicy Bypass -Command \"$env:MISE_INSTALL_VERSION='%s'; $env:MISE_INSTALL_PATH='%s'; & '%s'\"", ctx.version, ctx.install_path, ps1_path)
    local result = cmd.exec(install_cmd)

    -- Print the output so the user sees progress
    if result then
        print(result)
    end

    -- Check for failure in PowerShell output
    if result:find("Error") or result:find("Exception") or result:find("failed") then
        error("PowerShell installation script failed:\n" .. result)
    end

    return {}
end
