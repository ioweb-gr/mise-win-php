--- Lists available versions for a tool in this backend
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendlistversions
function PLUGIN:BackendListVersions(ctx)
    local http = require("http")
    local versions = {}
    local seen = {}

    local function get_versions(url)
        local resp, err = http.get({ url = url })
        if err or resp.status_code ~= 200 then
            return
        end

        -- Match: php-8.3.11-Win32-vs16-x64.zip
        -- Pattern notes:
        -- %- matches literal '-'
        -- [0-9%.]+ matches one or more digits or dots (for version)
        -- [^%\"]* matches any char except '"' (to keep within the href attribute)
        for filename in resp.body:gmatch("php%-[0-9%.]+%-Win32%-[^%\"]*%-x64%.zip") do
            -- Filter out NTS (Non-Thread-Safe)
            if not filename:find("%-nts%-") then
                local version = filename:match("php%-([0-9%.]+)%-Win32")
                if version and not seen[version] then
                    table.insert(versions, version)
                    seen[version] = true
                end
            end
        end
    end

    get_versions("https://downloads.php.net/~windows/releases/")
    get_versions("https://downloads.php.net/~windows/releases/archives/")

    -- Semantic version sort
    table.sort(versions, function(a, b)
        local function split(v)
            local t = {}
            for s in v:gmatch("%d+") do
                table.insert(t, tonumber(s))
            end
            return t
        end
        local ta = split(a)
        local tb = split(b)
        for i = 1, math.max(#ta, #tb) do
            local va = ta[i] or 0
            local vb = tb[i] or 0
            if va ~= vb then
                return va < vb
            end
        end
        return false
    end)

    return { versions = versions }
end
