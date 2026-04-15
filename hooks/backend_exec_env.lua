--- Sets up environment variables for a tool
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendexecenv
function PLUGIN:BackendExecEnv(ctx)
    -- PHP binaries on Windows are located in the root installation folder
    return {
        bin_paths = { ctx.install_path },
        env_vars = {
            { key = "PATH", value = ctx.install_path }
        }
    }
end
