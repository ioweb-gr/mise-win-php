--- Lists available versions for a tool in this backend
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendlistversions
function PLUGIN:BackendListVersions(ctx)
    local http = require("http")
    local tool = ctx.tool or "php"
    local versions = {}
    local seen = {}

    local function sort_versions(items)
        table.sort(items, function(a, b)
            local function parse(v)
                local major, minor, patch, suffix = v:match("^(%d+)%.(%d+)%.(%d+)(.*)$")
                return {
                    tonumber(major) or 0,
                    tonumber(minor) or 0,
                    tonumber(patch) or 0,
                    suffix or "",
                }
            end

            local function suffix_rank(suffix)
                if suffix == "" then
                    return 100, 0, ""
                end

                local normalized = suffix:lower()
                local num = tonumber(normalized:match("(%d+)$")) or 0
                if normalized:find("alpha", 1, true) then
                    return 10, num, normalized
                elseif normalized:find("beta", 1, true) then
                    return 20, num, normalized
                elseif normalized:find("rc", 1, true) then
                    return 30, num, normalized
                end

                return 40, num, normalized
            end

            local ta = parse(a)
            local tb = parse(b)
            for i = 1, 3 do
                if ta[i] ~= tb[i] then
                    return ta[i] < tb[i]
                end
            end

            local rank_a, num_a, suffix_a = suffix_rank(ta[4])
            local rank_b, num_b, suffix_b = suffix_rank(tb[4])
            if rank_a ~= rank_b then
                return rank_a < rank_b
            elseif num_a ~= num_b then
                return num_a < num_b
            end

            return suffix_a < suffix_b
        end)
    end

    if tool == "composer" then
        local function add_version(version)
            if version and version:match("^%d+%.%d+%.%d+[%w%-]*$") and not seen[version] then
                table.insert(versions, version)
                seen[version] = true
            end
        end

        local resp, err = http.get({ url = "https://getcomposer.org/download/" })
        if not err and resp.status_code == 200 then
            for version in resp.body:gmatch("/download/([%d]+%.[%d]+%.[%d]+[^/]*)/composer%.phar") do
                add_version(version)
            end
        end

        -- The download page is the full history, but /versions is tiny and gives
        -- the currently advertised stable/LTS releases if the page layout changes.
        local resp_versions, err_versions = http.get({ url = "https://getcomposer.org/versions" })
        if not err_versions and resp_versions.status_code == 200 then
            for version in resp_versions.body:gmatch('"version"%s*:%s*"([^"]+)"') do
                add_version(version)
            end
        end

        sort_versions(versions)
        return { versions = versions }
    elseif tool ~= "php" then
        error("Unsupported tool: " .. tool .. ". Supported tools are php and composer.")
    end

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
    sort_versions(versions)

    return { versions = versions }
end
