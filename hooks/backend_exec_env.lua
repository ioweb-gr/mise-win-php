--- Sets up environment variables for a tool
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendexecenv
function PLUGIN:BackendExecEnv(ctx)
    -- PHP binaries are in the root install directory, not a bin/ subdirectory.
    -- mise reads PATH from env_vars to determine where to scan for executables when
    -- creating shims (e.g. php.cmd on Windows). It then filters PATH out before
    -- applying env_vars to the shell, so this does not replace the user's PATH.
    -- Result: `php` works directly once mise shims are on PATH — no `mise exec` needed.
    return {
        env_vars = {
            { key = "PATH", value = ctx.install_path }
        }
    }
end
