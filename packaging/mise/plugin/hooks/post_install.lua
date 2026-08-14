-- macOS ships the app as a `knitcalc.app` bundle, so the executable is not at
-- the root of the install directory the way it is on Linux and Windows. A
-- symlink next to it keeps one PATH entry for every platform (see env_keys.lua)
-- and still resolves into the mise install tree, which is what the app's own
-- update-channel detection looks for.
local function linkMacosBundle(path, name)
    -- The bundle keeps its directory unless mise flattened a single-directory
    -- archive on extraction, so both layouts are handled.
    os.execute(
        'p="'
            .. path
            .. '"; '
            .. 'for c in "'
            .. name
            .. '.app/Contents/MacOS/'
            .. name
            .. '" "Contents/MacOS/'
            .. name
            .. '"; do '
            .. 'if [ -x "$p/$c" ]; then ln -sf "$c" "$p/'
            .. name
            .. '"; break; fi; done'
    )
end

-- The Linux tarball is the one channel that brings no runtime of its own: the
-- bundle carries only our own `.so`s and links the system GTK 3 stack (the
-- `.deb` declares it as a dependency, AppImage/Snap/Flatpak carry a runtime).
-- Bundling GTK was considered and rejected — half of it loads through `dlopen`
-- (pixbuf loaders, GIO modules, GSettings schemas) and `libGL` has to match the
-- host, so a copied stack breaks on the machines it is supposed to save.
--
-- Without this hook a user of a bare distro gets the dynamic loader's
-- `error while loading shared libraries: libgtk-3.so.0` on first run, long
-- after `mise install` reported success. Asking the loader at install time
-- turns that into an answer. It is a warning, never an error: the check is
-- best effort and must not fail an install that is otherwise fine.
--
-- `LD_TRACE_LOADED_OBJECTS=1 "$bin"` rather than `ldd "$bin"`, because it runs
-- the *binary's own* interpreter: on a NixOS box with nix-ld that is nix-ld,
-- which resolves the stack the app really uses, while `ldd` traces with its own
-- glibc loader and reports every GTK library as missing on a machine where the
-- app starts fine. The loader prints the list and exits without running main,
-- so nothing can open a window or hang the install.
local function warnAboutMissingLibraries(path, name)
    os.execute([==[
bin="]==] .. path .. "/" .. name .. [==["
[ -x "$bin" ] || exit 0

missing=$(LD_TRACE_LOADED_OBJECTS=1 "$bin" 2>/dev/null |
    sed -n 's/^[[:space:]]*\([^[:space:]][^[:space:]]*\) => not found.*$/\1/p' |
    sort -u | xargs)
[ -n "$missing" ] || exit 0

{
    echo "knitcalc: installed, but these shared libraries are missing on this system:"
    echo "  $missing"
    echo "The Linux build links the system GTK 3 stack; install it and knitcalc runs."
    echo "  Debian/Ubuntu  sudo apt install libgtk-3-0 liblzma5"
    echo "  Fedora/RHEL    sudo dnf install gtk3 xz-libs"
    echo "  Arch           sudo pacman -S gtk3 xz"
    echo "  openSUSE       sudo zypper install gtk3 liblzma5"
    echo "  NixOS          programs.nix-ld.enable = true; and in programs.nix-ld.libraries:"
    echo "                 gtk3 pango cairo gdk-pixbuf glib harfbuzz at-spi2-atk libepoxy fontconfig"
} >&2
]==])
end

-- mise only puts the binary on PATH, so a `mise install` alone leaves the app
-- out of the application menu and gives its window no icon (on Wayland the icon
-- is matched app_id -> .desktop -> icon theme, so without the entry there is
-- only a placeholder). The Linux tarball already ships the per-user integration
-- the manual install uses — `install.sh`, the hicolor PNGs and the `.desktop` —
-- so the hook just runs it. It is best effort like the library check above: a
-- missing menu entry must not fail an install.
--
-- The one thing that cannot be reused is install.sh's `Exec=`. It points at the
-- extracted binary, which is right for a tarball unpacked by hand but wrong
-- here: the path carries a version, `mise use knitcalc@<newer>` leaves the old
-- install directory in place, and the menu would go on launching the old build
-- forever. mise's shim is the stable entry point — a copy of the mise binary
-- that resolves the active version at launch, and one that still executes out
-- of `…/mise/installs/…`, so the app keeps detecting `Channel.mise`. It sits at
-- `<data>/shims/<name>`, three levels above `<data>/installs/<name>/<version>`;
-- if it is not there (shims disabled), install.sh's own `Exec=` is left alone.
--
-- `pre_uninstall.lua` takes the entry back out.
local function installDesktopEntry(path, name)
    os.execute([==[
p="]==] .. path .. [==["
[ -x "$p/install.sh" ] || exit 0

# Tarballs up to 1.8.77+100 ship an install.sh that copies into
# `$data/icons/hicolor` without creating it, so it fails on an account that has
# no icon theme of its own yet — which is every account that has installed
# nothing but mise tools. Creating the directory here fixes those releases too.
data=${XDG_DATA_HOME:-$HOME/.local/share}
mkdir -p "$data/icons/hicolor"
sh "$p/install.sh" >/dev/null 2>&1 || exit 0

entry="$data/applications/$(basename "$p"/desktop/*.desktop)"
mise_data=$(cd "$p/../../.." 2>/dev/null && pwd)
[ -f "$entry" ] && [ -n "$mise_data" ] || exit 0

# The shim itself is written after this hook returns — mise reshims once the
# install is complete — so the path is used, not tested for. `mise-install-check`
# asserts it exists by the end of an install.
sed -i "s|^Exec=.*|Exec=$mise_data/shims/]==] .. name .. [==[|" "$entry"
]==])
end

-- The same gap on macOS: the `.app` bundle sits in the versioned install
-- directory, where neither Launchpad nor Spotlight looks. `~/Applications` is
-- the per-user directory both of them do scan, and a symlink into the install
-- tree is what Homebrew casks put there too — the app still runs out of
-- `…/mise/installs/…`, so `Channel.mise` detection is unaffected. Relinked on
-- every install, so an upgrade moves the alias to the new version.
--
-- A bundle installed some other way (dragged into `/Applications`, a `.dmg`)
-- keeps its own copy; only a `~/Applications` entry that is a symlink into this
-- mise's install tree is ours to replace.
local function linkMacosApplications(path, name, displayName)
    os.execute([==[
p="]==] .. path .. [==["

# Same two layouts linkMacosBundle above handles: the bundle keeps its own
# directory unless mise flattened a single-directory archive on extraction, in
# which case the install directory *is* the bundle. Release 1.8.78+101 shipped
# only the first case and the macOS runner reported "no application entry":
# mise does flatten our zip, so `$p/knitcalc.app` never existed.
bundle=""
for c in "$p/]==] .. name .. [==[.app" "$p"; do
    if [ -d "$c/Contents" ]; then bundle="$c"; break; fi
done
[ -n "$bundle" ] || exit 0

apps="$HOME/Applications"
link="$apps/]==] .. displayName .. [==[.app"
installs=$(cd "$p/.." 2>/dev/null && pwd)
[ -n "$installs" ] || exit 0
if [ -e "$link" ] && [ ! -L "$link" ]; then exit 0; fi
if [ -L "$link" ]; then
    case "$(readlink "$link")" in "$installs"/*) ;; *) exit 0 ;; esac
fi

mkdir -p "$apps"
ln -sfn "$bundle" "$link"
]==])
end

-- Windows ships the plain runner directory, so mise puts `knitcalc.exe` on PATH
-- and nothing appears in the Start menu. `[Environment]::GetFolderPath('Programs')`
-- is the per-user Start-menu folder — the same place the Scoop shortcut and the
-- Inno installer's entry land, which is why an existing shortcut is only
-- overwritten when it already points into this mise's install tree.
--
-- The shortcut targets the versioned `knitcalc.exe`, not the shim: mise's shims
-- are console executables, so a Start-menu entry pointing at one flashes a
-- console window on every launch. An upgrade re-points the shortcut here, and
-- pre_uninstall.lua removes it with the last version. The icon needs no file —
-- Windows reads it from the executable's own resources.
local function installStartMenuShortcut(path, name, displayName)
    os.execute(
        'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "'
            .. "$ErrorActionPreference='SilentlyContinue';"
            .. "$p='"
            .. path
            .. "';"
            .. "$exe=Join-Path $p '"
            .. name
            .. ".exe';"
            .. 'if (-not (Test-Path $exe)) { exit 0 };'
            .. "$lnk=Join-Path ([Environment]::GetFolderPath('Programs')) '"
            .. displayName
            .. ".lnk';"
            .. '$ws=New-Object -ComObject WScript.Shell;'
            -- Through GetFullPath on both sides: the path mise hands the hook
            -- and the one WScript.Shell stored in an existing shortcut need not
            -- spell their separators the same way.
            .. '$installs=[IO.Path]::GetFullPath((Split-Path $p));'
            .. 'if (Test-Path $lnk) {'
            .. '  $target=$ws.CreateShortcut($lnk).TargetPath;'
            .. '  if ($target) { $target=[IO.Path]::GetFullPath($target) };'
            .. '  if (-not $target -or -not $target.StartsWith($installs, '
            .. "'OrdinalIgnoreCase')) { exit 0 }"
            .. '};'
            .. '$s=$ws.CreateShortcut($lnk);'
            .. '$s.TargetPath=$exe;'
            .. '$s.WorkingDirectory=$p;'
            .. '$s.Save()"'
    )
end

function PLUGIN:PostInstall(ctx)
    local knitcalc = require("knitcalc")
    local path = ctx.sdkInfo[knitcalc.package].path

    if RUNTIME.osType == "darwin" then
        linkMacosBundle(path, knitcalc.package)
        linkMacosApplications(path, knitcalc.package, knitcalc.displayName)
    elseif RUNTIME.osType == "linux" then
        warnAboutMissingLibraries(path, knitcalc.package)
        installDesktopEntry(path, knitcalc.package)
    elseif RUNTIME.osType == "windows" then
        installStartMenuShortcut(path, knitcalc.package, knitcalc.displayName)
    end
end
