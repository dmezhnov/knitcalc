-- `mise uninstall knitcalc` deletes the install directory, but the desktop
-- entry and icon theme that post_install.lua put into the user's data dir live
-- outside it: without this hook the application menu keeps an entry launching a
-- shim that mise removed with the last version. The tarball ships the exact
-- counterpart of what was installed — `uninstall.sh`, which drops the entry,
-- the hicolor PNGs and refreshes both caches — so the hook only has to run it.
-- Best effort, like the install side: a failure here must not block an
-- uninstall.
--
-- Two guards, because the same paths can belong to somebody else:
--
--  * mise keeps versions side by side and the entry points at the
--    version-independent shim, so it must survive the removal of one version
--    while another is still installed. The hook runs before the directory is
--    deleted, so the version being removed is still in the listing — anything
--    else next to it means this is not the last one.
--  * a `.deb`, an AppImage or a hand-unpacked tarball writes the very same
--    `~/.local/share` paths. The entry is only ours when its `Exec=` is this
--    mise's shim, which is what post_install.lua wrote.
local function removeDesktopEntry(path, name)
    os.execute([==[
p="]==] .. path .. [==["
[ -x "$p/uninstall.sh" ] || exit 0

here=$(basename "$p")
for d in "$p"/../*/; do
    d=${d%/}
    [ -d "$d" ] || continue
    # mise puts its version aliases next to the real directories
    # (`installs/knitcalc/{1,1.8,latest}` -> `./1.8.77+100`); measured — without
    # this the check took `1` for a second installed version and never cleaned up.
    if [ -L "$d" ]; then continue; fi
    [ "$(basename "$d")" = "$here" ] || exit 0
done

data=${XDG_DATA_HOME:-$HOME/.local/share}
entry="$data/applications/$(basename "$p"/desktop/*.desktop)"
mise_data=$(cd "$p/../../.." 2>/dev/null && pwd)
[ -f "$entry" ] && [ -n "$mise_data" ] || exit 0
grep -q "^Exec=$mise_data/shims/]==] .. name .. [==[$" "$entry" || exit 0

sh "$p/uninstall.sh" >/dev/null 2>&1 || exit 0
]==])
end

-- macOS counterpart: drop the `~/Applications` alias, but only while it still
-- points at the bundle inside the version being removed. If an upgrade already
-- re-pointed it at a newer version, or the user has a real copy there, it stays.
local function removeMacosApplicationsLink(path, displayName)
    os.execute([==[
link="$HOME/Applications/]==] .. displayName .. [==[.app"
[ -L "$link" ] || exit 0

# Both layouts post_install.lua can link: the bundle inside the install
# directory, or — when mise flattened the archive — the install directory itself,
# in which case the link target is the path with nothing after it.
case "$(readlink "$link")" in
    "]==] .. path .. [==[" | "]==] .. path .. [==["/*) rm -f "$link" ;;
esac
]==])
end

-- Windows counterpart, with the same rule: the Start-menu shortcut goes only if
-- it still targets the executable in the version being removed, so an upgrade's
-- shortcut and a Scoop/Inno one of the same name survive.
local function removeStartMenuShortcut(path, displayName)
    os.execute(
        'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "'
            .. "$ErrorActionPreference='SilentlyContinue';"
            .. "$lnk=Join-Path ([Environment]::GetFolderPath('Programs')) '"
            .. displayName
            .. ".lnk';"
            .. 'if (-not (Test-Path $lnk)) { exit 0 };'
            .. '$ws=New-Object -ComObject WScript.Shell;'
            .. '$target=$ws.CreateShortcut($lnk).TargetPath;'
            .. 'if (-not $target) { exit 0 };'
            -- Both sides through GetFullPath: mise hands the hook a path whose
            -- separators need not match the ones WScript.Shell stored in the
            -- shortcut, and a raw StartsWith on those missed — release
            -- 1.8.78+101 left the Start-menu entry behind on the runner.
            .. "$here=[IO.Path]::GetFullPath('"
            .. path
            .. "');"
            .. '$target=[IO.Path]::GetFullPath($target);'
            .. "if ($target.StartsWith($here, 'OrdinalIgnoreCase')) "
            .. '{ Remove-Item -Force $lnk }"'
    )
end

function PLUGIN:PreUninstall(ctx)
    local knitcalc = require("knitcalc")
    local path = ctx.sdkInfo[knitcalc.package].path

    if RUNTIME.osType == "linux" then
        removeDesktopEntry(path, knitcalc.package)
    elseif RUNTIME.osType == "darwin" then
        removeMacosApplicationsLink(path, knitcalc.displayName)
    elseif RUNTIME.osType == "windows" then
        removeStartMenuShortcut(path, knitcalc.displayName)
    end
end
