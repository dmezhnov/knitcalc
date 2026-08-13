-- Lists the installable versions: every published GitHub release of the app.
-- Newest first, which is the order the GitHub API returns them in.
function PLUGIN:Available(ctx)
    local http = require("http")
    local json = require("json")
    local knitcalc = require("knitcalc")

    local resp, err = http.get({
        url = "https://api.github.com/repos/" .. knitcalc.repo .. "/releases?per_page=100",
        headers = knitcalc.apiHeaders,
    })

    if err ~= nil then
        error("knitcalc: cannot list releases: " .. tostring(err))
    end

    if resp.status_code ~= 200 then
        error("knitcalc: cannot list releases: GitHub returned " .. tostring(resp.status_code))
    end

    local releases = json.decode(resp.body)
    local result = {}

    for _, release in ipairs(releases) do
        -- Drafts are invisible to anonymous callers anyway; prereleases are
        -- skipped so `@latest` never resolves to one.
        if release.draft ~= true and release.prerelease ~= true and type(release.tag_name) == "string" then
            table.insert(result, {
                version = knitcalc.versionFromTag(release.tag_name),
                note = (#result == 0) and "Latest" or nil,
            })
        end
    end

    return result
end
