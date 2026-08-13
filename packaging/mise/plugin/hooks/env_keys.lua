-- The Flutter bundle keeps its executable next to its `data/` and `lib/`
-- directories, so the install directory itself is the bin directory. On macOS
-- post_install.lua puts a symlink there pointing into the .app bundle.
function PLUGIN:EnvKeys(ctx)
    return {
        {
            key = "PATH",
            value = ctx.path,
        },
    }
end
