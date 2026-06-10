# Packaging for desktop package managers

Templates for publishing the desktop builds to winget, Scoop, Chocolatey
(Windows) and Homebrew (macOS). `{{VERSION}}`, `{{URL}}` and `{{SHA256}}`
placeholders are filled in by `.github/workflows/publish.yml` after each release
— the `publish` job renders the Scoop bucket and Homebrew cask on `main`, the
`windows-package-managers` job submits to winget and Chocolatey. winget and
Chocolatey get the bare semver (`1.8.23` — both reject `+build` metadata); Scoop
and Homebrew get the full version (`1.8.23+46`).

The job is a no-op (with a workflow warning) until the corresponding secret is
configured, so releases keep working before the one-time onboarding below.

## One-time onboarding

### winget (`packaging/winget/`)

1. Create a classic GitHub PAT with the `public_repo` scope and save it as the
   `PACKAGING_GITHUB_TOKEN` repository secret.
2. The first version must be submitted to
   [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) manually:
   render the three manifests (fill the placeholders for a released version),
   place them under `manifests/d/Dmezhnov/KnitCalc/<version>/` in a fork and
   open a PR. After it is merged, the workflow submits every following version
   automatically via `wingetcreate update --submit`.

### Scoop (`packaging/scoop/`)

No onboarding: this repository doubles as the bucket. The release job renders
`bucket/knitcalc.json` on `main` with each release (a Scoop bucket is just a
git repo with a `bucket/` directory), so no separate repo, token or review is
involved. Users install with:

    scoop bucket add knitcalc https://github.com/dmezhnov/knitcalc
    scoop install knitcalc

### Homebrew (`packaging/homebrew/`)

No onboarding: this repository doubles as a Homebrew tap. The release job renders
`Casks/knitcalc.rb` on `main` from the macOS zip's URL and hash (a tap is just a
git repo with a `Casks/` directory), so no separate repo, token or review is
involved. The macOS build is unsigned and unnotarized, so install with
`--no-quarantine`:

    brew tap dmezhnov/knitcalc https://github.com/dmezhnov/knitcalc
    brew install --cask --no-quarantine knitcalc

### Chocolatey (`packaging/chocolatey/`)

1. Register an account on <https://community.chocolatey.org>, take the API key
   from the account page and save it as the `CHOCO_API_KEY` repository secret.
2. The workflow packs and pushes on each release. The very first push goes
   through human moderation (typically days); later versions are mostly
   automated moderation.

### apt (`packaging/apt/`)

The `linux-android-web` job builds a `.deb` from the Flutter Linux bundle and a
signed apt repository into `build/web/apt`, which ships inside the same GitHub
Pages deploy (served at `https://dmezhnov.github.io/knitcalc/apt`). The site is
redeployed whole each release, so the repo always carries just the latest
version — enough for apt to offer an upgrade. The step is skipped (with a
warning) until the signing key is configured.

One-time onboarding — generate a signing key (no passphrase keeps CI signing
simple), then save its base64-encoded secret key as the `APT_GPG_PRIVATE_KEY`
repository secret (set `APT_GPG_PASSPHRASE` too only if the key has one):

    gpg --batch --quick-generate-key "KnitCalc apt <dmezhnov@users.noreply.github.com>" rsa4096 sign never
    gpg --armor --export-secret-keys "KnitCalc apt" | base64 -w0

Users install with (the public key is published at `apt/knitcalc.gpg`):

    curl -fsSL https://dmezhnov.github.io/knitcalc/apt/knitcalc.gpg \
      | sudo tee /usr/share/keyrings/knitcalc.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/knitcalc.gpg] https://dmezhnov.github.io/knitcalc/apt stable main" \
      | sudo tee /etc/apt/sources.list.d/knitcalc.list
    sudo apt-get update && sudo apt-get install knitcalc
