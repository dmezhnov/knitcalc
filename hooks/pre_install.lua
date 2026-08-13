-- Resolves the release asset for the running platform and hands mise its URL
-- and checksum; mise downloads and extracts it into the install directory.
--
-- The asset is looked up through the GitHub API rather than composed into a
-- URL by hand: the API returns the percent-encoded download URL (release tags
-- carry a `+build` suffix) and the asset's sha256 digest.
function PLUGIN:PreInstall(ctx)
    local http = require("http")
    local json = require("json")
    local knitcalc = require("knitcalc")

    local version = ctx.version
    local asset = knitcalc.assetName(version)

    local resp, err = http.get({
        url = "https://api.github.com/repos/" .. knitcalc.repo .. "/releases/tags/v" .. version,
        headers = knitcalc.apiHeaders,
    })

    if err ~= nil then
        error("knitcalc: cannot read release v" .. version .. ": " .. tostring(err))
    end

    if resp.status_code ~= 200 then
        error("knitcalc: cannot read release v" .. version .. ": GitHub returned " .. tostring(resp.status_code))
    end

    local release = json.decode(resp.body)

    for _, candidate in ipairs(release.assets or {}) do
        if candidate.name == asset then
            local sha256 = nil

            if type(candidate.digest) == "string" then
                sha256 = string.match(candidate.digest, "^sha256:(%x+)$")
            end

            return {
                version = version,
                url = candidate.browser_download_url,
                sha256 = sha256,
                note = "Installing " .. asset,
            }
        end
    end

    error("knitcalc: release v" .. version .. " carries no asset named " .. asset)
end
