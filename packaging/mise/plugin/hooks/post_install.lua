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

function PLUGIN:PostInstall(ctx)
    local knitcalc = require("knitcalc")
    local path = ctx.sdkInfo[knitcalc.package].path

    if RUNTIME.osType == "darwin" then
        linkMacosBundle(path, knitcalc.package)
    elseif RUNTIME.osType == "linux" then
        warnAboutMissingLibraries(path, knitcalc.package)
    end
end
