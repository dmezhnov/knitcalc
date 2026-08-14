-- Generated from packaging/metadata/metadata.yaml by tool/packaging_metadata.dart.
-- Edit that file and run `mise metadata`; changes here are overwritten.
local M = {}

M.repo = "dmezhnov/knitcalc"
M.package = "knitcalc"
-- User-visible name, used by the hooks that add the app to the
-- Windows Start menu and to ~/Applications on macOS.
M.displayName = "KnitCalc"
M.apiHeaders = {
    Accept = "application/vnd.github+json",
    ["User-Agent"] = "mise-knitcalc-plugin",
    ["X-GitHub-Api-Version"] = "2022-11-28",
}

-- Release tags are the pubspec version with a "v" prefix ("v1.2.3+45").
function M.versionFromTag(tag)
    return (string.gsub(tag, "^v", ""))
end

-- Desktop bundles published per platform. Linux and Windows ship x64
-- only; the macOS zip is a universal .app bundle, so both arches take it.
function M.assetName(version)
    local os_type = RUNTIME.osType
    local arch = RUNTIME.archType

    if os_type == "linux" and arch == "amd64" then
        return "knitcalc-linux-x64-" .. version .. ".tar.gz"
    elseif os_type == "windows" and arch == "amd64" then
        return "knitcalc-windows-x64-" .. version .. ".zip"
    elseif os_type == "darwin" then
        return "knitcalc-macos-" .. version .. ".zip"
    end

    error("knitcalc: no release build for " .. tostring(os_type) .. "-" .. tostring(arch))
end

return M
