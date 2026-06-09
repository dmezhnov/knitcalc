# Packaging for Windows package managers

Templates for publishing the Windows build to winget, Scoop and Chocolatey.
`{{VERSION}}`, `{{URL}}` and `{{SHA256}}` placeholders are filled in by the
`windows-package-managers` job of `.github/workflows/publish.yml` after each
release. winget and Chocolatey get the bare semver (`1.8.23` — both reject
`+build` metadata); Scoop gets the full version (`1.8.23+46`).

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

### Chocolatey (`packaging/chocolatey/`)

1. Register an account on <https://community.chocolatey.org>, take the API key
   from the account page and save it as the `CHOCO_API_KEY` repository secret.
2. The workflow packs and pushes on each release. The very first push goes
   through human moderation (typically days); later versions are mostly
   automated moderation.
