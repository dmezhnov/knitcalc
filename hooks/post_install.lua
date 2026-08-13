-- macOS ships the app as a `knitcalc.app` bundle, so the executable is not at
-- the root of the install directory the way it is on Linux and Windows. A
-- symlink next to it keeps one PATH entry for every platform (see env_keys.lua)
-- and still resolves into the mise install tree, which is what the app's own
-- update-channel detection looks for.
function PLUGIN:PostInstall(ctx)
    if RUNTIME.osType ~= "darwin" then
        return
    end

    local knitcalc = require("knitcalc")
    local path = ctx.sdkInfo[knitcalc.package].path

    -- The bundle keeps its directory unless mise flattened a single-directory
    -- archive on extraction, so both layouts are handled.
    os.execute(
        'p="'
            .. path
            .. '"; '
            .. 'for c in "'
            .. knitcalc.package
            .. '.app/Contents/MacOS/'
            .. knitcalc.package
            .. '" "Contents/MacOS/'
            .. knitcalc.package
            .. '"; do '
            .. 'if [ -x "$p/$c" ]; then ln -sf "$c" "$p/'
            .. knitcalc.package
            .. '"; break; fi; done'
    )
end
