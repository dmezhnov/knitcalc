# Packaging for desktop package managers

## Listing metadata: one file, every channel

`packaging/metadata/metadata.yaml` is the **single source of truth** for
everything a store shows: application name, tagline, one-line summary, long
description and feature list (per locale), publisher, license, URLs, tags,
categories and screenshots. `mise metadata`
(`tool/packaging_metadata.dart`) renders it into every channel:

| Rendered file                                  | Channel                                                                             |
| ---------------------------------------------- | ----------------------------------------------------------------------------------- |
| `fastlane/metadata/android/<locale>/*`         | Play, IzzyOnDroid, RuStore, Samsung, Amazon, Huawei, Accrescent, NashStore/RuMarket |
| `packaging/winget/*.locale.en-US.yaml`         | winget                                                                              |
| `packaging/scoop/knitcalc.json`                | Scoop                                                                               |
| `packaging/chocolatey/knitcalc.nuspec`         | Chocolatey                                                                          |
| `packaging/homebrew/knitcalc.rb`               | Homebrew                                                                            |
| `packaging/mise/knitcalc.toml`                 | mise (registry entry for jdx/mise)                                                  |
| `packaging/mise/plugin/*.lua`                  | mise plugin (copied to the root of `main`)                                          |
| `packaging/apt/{control,knitcalc.desktop}`     | apt / `.deb`                                                                        |
| `packaging/obs/knitcalc.spec`                  | openSUSE Build Service (rpm)                                                        |
| `packaging/aur/{PKGBUILD,SRCINFO}`             | AUR                                                                                 |
| `snap/{snapcraft.yaml,gui/knitcalc.desktop}`   | Snap Store                                                                          |
| `packaging/flatpak/*.{metainfo.xml,desktop}`   | Flathub, GNOME Software, KDE Discover, AppImage                                     |
| `packaging/fdroid/*.yml`                       | F-Droid main repo                                                                   |
| `packaging/desktop/*.desktop`                  | the Linux tarball / dev install (`tool/linux_desktop_install.dart`)                 |
| `packaging/inno/knitcalc.iss` (`[Setup]` keys) | Windows installer, Add/Remove Programs                                              |
| `packaging/metadata/github.json`               | this repository's own description, website and topics                               |
| `pubspec.yaml` (description and URLs)          | pub metadata                                                                        |

Never edit those files' metadata by hand: `mise lint` runs
`packaging_metadata.dart --check` and fails when any of them drifts, and
`mise build` regenerates them. Files that also carry build logic (PKGBUILD, the
rpm spec, `snapcraft.yaml`, the F-Droid recipe, the Inno script, `pubspec.yaml`)
keep it — only their metadata fields are rewritten.

Screenshots live at `packaging/metadata/screenshots/<locale>/<form-factor>/<id>.png`
and are listed by id in `metadata.yaml`; the phone set is copied into the
fastlane tree, and AppStream links the desktop set from `main` by raw URL. The
**icon** has its own single source, `assets/icon/icon.png`: `mise build` runs
`icons_launcher` plus `tool/packaging_icons.dart`, which regenerate every
platform icon, the fastlane catalogue icon and the Flatpak icon from it.

The GitHub repository listing is pushed on each release by
`packaging/ci/publish_repo_metadata.sh` (the `Sync GitHub repository listing`
step). It runs on `PACKAGING_GITHUB_TOKEN` — editing repository settings is not
a scope a workflow `permissions:` block can grant to the built-in token — and,
like every other channel, records its verdict for the release channel report.

## Channels

Templates for publishing the desktop builds to winget, Scoop, Chocolatey
(Windows) and Homebrew (macOS). `{{VERSION}}`, `{{URL}}` and `{{SHA256}}`
placeholders are filled in by `.github/workflows/publish.yml` after each release
— the `publish` job renders the Scoop bucket and Homebrew cask on `main`, the
`windows-package-managers` job submits to winget and Chocolatey. winget and
Chocolatey get the bare semver (`1.8.23` — both reject `+build` metadata); Scoop
and Homebrew get the full version (`1.8.23+46`).

On Windows the release ships two assets: the **Inno Setup installer**
(`knitcalc-setup-x64-<full>.exe`, built from `packaging/inno/knitcalc.iss`) and
the loose bundle zip (`knitcalc-windows-x64-<full>.zip`). winget installs the
installer (per-user, `InstallerType: inno`). The installer adds `{app}` to the
user PATH (so `knitcalc` runs from a terminal), drops a single Start-menu
shortcut, and stamps an `install_source` marker (`winget` vs `manual`) so the
app picks the right update path: a winget install updates with `winget upgrade`,
a direct install self-updates by downloading and running the new installer. The
installer's Add/Remove Programs `DisplayVersion` is the **bare** semver
(`AppVersion={#AppNumeric}`), matching the winget manifest's `PackageVersion`;
if it carried the full `+build` version winget would never see the install as
current and `winget upgrade` (and the in-app winget-channel banner) would loop,
reinstalling the same version on every launch. On uninstall the app always signs
out (deletes the standalone `auth_session.json`) and, on an interactive uninstall,
offers to also delete saved projects; a silent `winget uninstall` keeps projects.
Scoop and Chocolatey install the zip — their shims launch `knitcalc.exe` by full
path, so the adjacent DLLs resolve (unlike a winget portable alias). The
installer is the recommended direct download for end users.

The job is a no-op (with a workflow warning) until the corresponding secret is
configured, so releases keep working before the one-time onboarding below.

## Release channel report

Because every publishing step is warn-and-continue (an outage at a store must
not abort a release that is already tagged and uploaded), a channel can fail to
update without reddening anything. The **Release channel report** job closes
that gap:

- each publishing step records its verdict with
  `packaging/ci/channel_status.sh <channel> ok|skipped|failed [detail]`
  (`channel_status.ps1` on the Windows runner), and its job uploads the
  directory as a `channel-status-*` artifact;
- `packaging/ci/channel_report.sh` merges them into a table on the run summary,
  emits one annotation per channel, and **exits non-zero if any channel is not
  `ok`** — including channels with no status file at all (`unknown`: the owning
  job never got that far), so a dead job cannot pass for silence;
- `mise publish` prints those annotations after `gh run watch` and exits with
  the run's status, so the terminal shows which channels published.

A red report does not mean a bad release: the tag, the assets and every channel
marked `ok` are live. Fix the cause and re-run the owning job — no version bump
is needed.

For the two Windows channels there is a dedicated retry:
`.github/workflows/republish-windows.yml` (**Republish Windows package
managers**, `workflow_dispatch`) re-submits an existing release to winget and/or
Chocolatey, recomputing the zip hash from the published asset. Both it and the
release job call the same composite action,
`.github/actions/windows-package-managers`, so the submission logic has one
home. Note that a `workflow_dispatch` workflow is only offered once it exists on
the default branch, i.e. after the release that first carries it.

Known causes behind the two Windows channels going quiet:

- **winget** — `The forked repository could not be synced with the upstream
commits`: `dmezhnov/winget-pkgs` drifted from upstream and wingetcreate
  refuses to branch off it. Fix with
  `gh api repos/dmezhnov/winget-pkgs/merge-upstream -f branch=master`, then
  retry the channel.
- **Chocolatey** — `403` means the key was rejected or a previous version is
  still in first-time moderation; `400` means the request itself was malformed,
  and in practice that is a `CHOCO_API_KEY` secret carrying a stray newline or
  space (the key goes out as the `X-NuGet-ApiKey` header). The action trims the
  value and refuses characters that cannot go into a header, but a wrong or
  truncated key still needs re-copying from
  <https://community.chocolatey.org/account>.

## One-time onboarding

### winget (`packaging/winget/`)

1. Create a classic GitHub PAT with the `public_repo` scope and save it as the
   `PACKAGING_GITHUB_TOKEN` repository secret.
2. The first version (and any switch of `InstallerType`) must be submitted to
   [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) manually:
   render the three manifests (fill the placeholders for a released version),
   place them under `manifests/d/Dmezhnov/KnitCalc/<version>/` in a fork and
   open a PR. After it is merged, the workflow submits every following version
   automatically via `wingetcreate update --submit`. Note: `wingetcreate update`
   only bumps the url/version/hash — it can't change `InstallerType`, so the
   move from the old `zip`/portable manifest to the current `inno` manifest
   needs one such manual PR before the automated updates resume.

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

### mise (`packaging/mise/`)

The [mise](https://mise.jdx.dev) version manager installs the release assets
straight from GitHub Releases on Linux, Windows and macOS. Nothing is published
per release; what the release job does instead is **verify the install** — the
`mise-install` matrix job runs both paths below on all three runners and reports
`mise-linux`/`mise-windows`/`mise-macos` in the channel report, so an asset
rename or a broken bundle layout cannot break the channel silently.

#### The plugin: this repository as its own tool registry

mise's shorthand names (`mise use -g knitcalc`) come from the registry compiled
into mise itself — there is no setting pointing it at a third-party registry.
A **tool plugin** is the way around that: mise clones a git repository and reads
`metadata.lua` plus `hooks/` from its root, which makes this repository its own
one-tool registry, exactly as it doubles as the Scoop bucket and the Homebrew
tap:

    mise plugin install knitcalc https://github.com/dmezhnov/knitcalc
    mise use -g knitcalc@latest

The plugin is generated into `packaging/mise/plugin/` — `metadata.lua` and
`knitcalc.lua` (repository, package name, per-platform asset names) come from
`metadata.yaml`, the four hooks next to them are hand-written code:
`available.lua` lists the GitHub releases, `pre_install.lua` resolves the
platform's asset through the API (that gives both the percent-encoded download
URL for the `+build` tag and the asset's sha256 digest, which mise verifies),
`env_keys.lua` puts the install directory on PATH and `post_install.lua`
symlinks the macOS `.app` binary next to it so that one PATH entry fits all
three platforms. The shared module sits at the plugin root instead of the
documented `lib/` because `lib/` at the root of this repository is the Flutter
source tree; `require` resolves from the plugin root just as well.

The `Render mise plugin` step of the publish job copies that tree to the root of
`main` (mise clones the default branch), and it commits only when the plugin
itself changed — unlike the bucket and the cask it carries no version, since the
plugin asks the GitHub API. Note that mise deliberately keeps plugins out of its
registry: their code runs on the user's machine. That is a reason for _mise_ not
to bless third-party plugins, not a reason for us not to publish our own.

#### Without a plugin: the `github` backend

The same builds install through mise's `github` backend (its `ubi` backend is
deprecated and disappears in 2027.1), at the cost of spelling the platform
details out. The per-platform `asset_pattern` globs are not optional: a release
also carries the AppImage, the Android APKs, the web tarball, the iOS zip and
the Inno `setup.exe`, and mise's asset autodetection is free to pick any of
them. The macOS asset is an `.app` bundle, hence its `bin_path`. The
`[tool_alias]` line is what makes the tool answer to the plain name `knitcalc`,
so that its install directory and `mise upgrade knitcalc` match the plugin
install:

    [tool_alias]
    knitcalc = "github:dmezhnov/knitcalc"

    [tools.knitcalc]
    version = "latest"

    [tools.knitcalc.platforms]
    linux-x64 = { asset_pattern = "knitcalc-linux-x64-*.tar.gz" }
    windows-x64 = { asset_pattern = "knitcalc-windows-x64-*.zip" }
    macos-arm64 = { asset_pattern = "knitcalc-macos-*.zip", bin_path = "knitcalc.app/Contents/MacOS" }
    macos-x64 = { asset_pattern = "knitcalc-macos-*.zip", bin_path = "knitcalc.app/Contents/MacOS" }

mise puts `knitcalc` on PATH and installs no desktop entry or icon. An app
installed this way detects `Channel.mise` (the executable resolves inside
`…/mise/installs/…`) and never self-updates: the banner comes from
`mise outdated --json` and its button runs `mise upgrade knitcalc` in a
terminal — see `lib/update/impl/pm/specs/mise_spec.dart`.

#### Optional onboarding: the upstream registry

Neither path above needs anything from upstream. A registry entry only removes
the one-off `mise plugin install`, so that `mise use -g knitcalc` works on a
bare mise — worth a PR, not worth blocking on:

1. Fork [jdx/mise](https://github.com/jdx/mise) and copy the generated
   `packaging/mise/knitcalc.toml` to `registry/knitcalc.toml`.
2. Check it with `mise test-tool knitcalc`, then open a PR titled
   `registry: add knitcalc (github:dmezhnov/knitcalc)`.
3. The registry's `validate-new-tools` job requires the `test` field, which runs
   `knitcalc --version` on their runners. That is why the native runners answer
   `--version` before any window opens (`linux/runner/main.cc`,
   `windows/runner/main.cpp`, `macos/Runner/main.swift`) — so the PR can only go
   out after a release that carries them. `mise run mise-install-check` runs the
   same check locally against the published release.
4. One thing that check cannot control upstream: the Linux bundle links GTK, so
   the loader needs `libgtk-3-0` (and `liblzma5`) present even for `--version`.
   Our own `mise-install` job installs them; if mise's Linux runner turns out
   not to have them, the entry may have to declare `os = ["macos", "windows"]`
   or the test be discussed in the PR.

### Chocolatey (`packaging/chocolatey/`)

1. Register an account on <https://community.chocolatey.org>, take the API key
   from the account page and save it as the `CHOCO_API_KEY` repository secret.
2. The workflow packs and pushes on each release. The very first push goes
   through human moderation (typically days); later versions are mostly
   automated moderation.

### Snap Store (`snap/`)

The `snap-store` job packs the release Linux bundle into a snap
(`snap/snapcraft.yaml`, `plugin: dump` — no rebuild) and uploads it to the
stable channel of the Snap Store. The step is skipped (with a warning) until
the credentials secret is configured.

One-time onboarding — register the `knitcalc` name under your Snap Store
account at <https://snapcraft.io/register-snap>, then export store credentials
restricted to this snap and the upload/release ACLs. Without snapd, the
snapcraft CLI can run from its OCI image:

    docker run -it --rm ghcr.io/canonical/snapcraft:8_core24 \
      export-login --snaps=knitcalc \
      --acls=package_access,package_push,package_update,package_release -

Save the printed blob as the `SNAPCRAFT_STORE_CREDENTIALS` repository secret.
Users install with:

    sudo snap install knitcalc

### Flathub (`packaging/flatpak/`)

Unlike the other channels, Flathub builds the app from source on its own
infrastructure, with no network access during the build. The
`flatpak-flutter.yml` manifest here is the _input_ for
[flatpak-flutter](https://github.com/TheAppgineer/flatpak-flutter), which
pins the Flutter SDK and every pub dependency (from `pubspec.lock`) as offline
sources and emits the final manifest plus a `generated/` directory:

    docker run --rm --network host -v "$PWD":/usr/src/flatpak \
      -u `id -u`:`id -g` theappgineer/flatpak-flutter:latest flatpak-flutter.yml

Those generated files live in the Flathub packaging repo
(`flathub/io.github.dmezhnov.knitcalc`), not here. To ship a new version:
bump `tag`/`commit` of the knitcalc source in the manifest (and the flutter
tag if `mise.toml` changed), rerun the generation, and open a PR to the
Flathub repo. The metainfo, desktop file and icon are installed from this
directory at build time, so they version together with the app.

One-time onboarding: PR to [flathub/flathub](https://github.com/flathub/flathub)
(branch off `new-pr`) containing the generated manifest set; their CI
test-builds it and a reviewer approves. Users install with:

    flatpak install flathub io.github.dmezhnov.knitcalc

### AUR (`packaging/aur/`)

The `aur` job renders the `PKGBUILD`/`SRCINFO` templates (a `-bin` repackage
of the release Linux tarball, same layout as the `.deb`) and pushes them to
the `knitcalc-bin` AUR repo. The step is skipped (with a warning) until the
SSH key secret is configured.

One-time onboarding — register an account on <https://aur.archlinux.org>, add
an SSH public key to it, and save the matching private key as the
`AUR_SSH_PRIVATE_KEY` repository secret:

    ssh-keygen -t ed25519 -N '' -C knitcalc-aur -f knitcalc-aur
    # public part -> AUR account settings, private part -> the secret
    gh secret set AUR_SSH_PRIVATE_KEY < knitcalc-aur && rm knitcalc-aur

The first CI push creates the package base owned by that account. Users
install with an AUR helper, e.g. `yay -S knitcalc-bin`.

### AppImage

The `linux-android-web` job repacks the Linux bundle into
`knitcalc-<version>-x86_64.AppImage` (plus a `.zsync` file for delta updates
via AppImageUpdate) and ships both as release assets. No store or secret
involved. After the first release carrying an AppImage, the app can be listed
in the [AppImageHub catalog](https://github.com/AppImage/appimage.github.io)
with a one-file PR (`data/KnitCalc`).

### openSUSE Build Service (`packaging/obs/`)

`knitcalc.spec` repackages the release Linux tarball as an rpm (same layout
as the `.deb`); OBS serves repos for openSUSE Tumbleweed/Leap and Fedora from
package [`home:dmezhnov/knitcalc`](https://build.opensuse.org/package/show/home:dmezhnov/knitcalc).
`knitcalc-rpmlintrc` filters the prebuilt-bundle complaints (missing `.hash`
sections etc.) that openSUSE's post-build rpmlint would otherwise fail on.
Users install with the repo from
`https://download.opensuse.org/repositories/home:/dmezhnov/<distro>/`.

Per release (not wired into CI yet — worth an `osc` + OBS-token job):

1. Replace `{{VERSION}}` in `knitcalc.spec` and `_service`.
2. In an `osc co home:dmezhnov/knitcalc` checkout: drop in the rendered
   `knitcalc.spec`/`_service`/`knitcalc-rpmlintrc`, download the release
   tarball and `LICENSE` next to them (the URLs from the spec; `osc service
runall` would do it, but `obs-service-download_url` is not packaged in
   nixpkgs), remove the previous version's tarball (`osc rm`), `osc add` the
   new one, `osc commit`.

### IzzyOnDroid (`fastlane/`)

The IzzyOnDroid F-Droid-compatible repo takes the **per-ABI release APKs**
(the universal APK is over their ~30 MB per-file limit) straight from GitHub
releases and the app description/screenshots from `fastlane/metadata/android/`
in this repo. One-time onboarding: request addition at
<https://codeberg.org/IzzyOnDroid/repo/issues> pointing at the repo and the
`knitcalc-<version>-arm64-v8a.apk` asset naming. Updates are picked up from
releases automatically. The APKs must stay signed with the same release key.

### F-Droid main repo (`packaging/fdroid/`)

F-Droid builds from source on its own infrastructure and its scanner rejects
bundled proprietary blobs. KnitCalc's only such blob is Google Play Services,
pulled in by `google_sign_in` (the native Credential Manager account picker).
The whole `package:google_sign_in` import is isolated in one leaf file
(`lib/firebase/native_id_token_fetcher.dart`); everything else talks to it
through the injected `NativeIdTokenFetcher` seam.

`packaging/fdroid/foss_prebuild.sh` makes the source F-Droid-buildable: it
removes the `google_sign_in` dependency from `pubspec.yaml` and copies the
Play-Services-free stub (`native_id_token_fetcher_foss.dart`) over that leaf, so
the built APK carries no Google proprietary code. Sign-in then always uses the
loopback browser OAuth flow — the same fallback Play-Services-less devices
already take. The normal Play/sideload/other-store builds are unchanged and keep
the native picker.

The self-updater needs no special handling: an app installed by the F-Droid
client reports installer `org.fdroid.fdroid`, which `androidChannelForInstaller`
maps to `Channel.androidManagedStore` → `NoopUpdateService`, so it never
downloads an APK — F-Droid handles updates.

`packaging/fdroid/io.github.dmezhnov.knitcalc.yml` is a template for the
fdroiddata metadata entry; its `Builds` recipe runs `foss_prebuild.sh` before
`flutter pub get`. One-time onboarding (needs a GitLab account): fork
[fdroiddata](https://gitlab.com/fdroid/fdroiddata), drop the rendered metadata
in as `metadata/io.github.dmezhnov.knitcalc.yml` (set the Flutter srclib version
to match `mise.toml`), validate with `fdroid lint`/`fdroid build`, and open an
MR. Expect reviewer iteration — Flutter recipes usually need it. Until it lands,
IzzyOnDroid (above) covers F-Droid clients.

### RuStore — manual

Free developer account at <https://console.rustore.ru> (needs identity
verification), then upload the release `.aab` or APK by hand; texts and
screenshots can be reused from `fastlane/metadata/android/ru-RU/`. No
publishing API is wired up.

### Other Android stores (Samsung, Amazon, Huawei, Accrescent, NashStore, RuMarket)

All of these take the **standard release artifact** built by CI — no separate
build is needed. Bundling Google Play Services is fine for every one of them
(unlike F-Droid above): native Google sign-in falls back to the browser
loopback OAuth flow on devices without Play Services (e.g. Huawei), so the same
APK/AAB works everywhere. Listing copy, screenshots and the icon are uploaded
from `fastlane/metadata/android/{en-US,ru-RU}/`, which `mise metadata` renders
from `packaging/metadata/metadata.yaml` (see the top of this file) — don't
re-type the texts per store, and don't edit the fastlane files either.

These stores ship and update the app themselves, so the in-app updater stays
silent for them: `androidChannelForInstaller` maps their installer package names
to `Channel.androidManagedStore` → `NoopUpdateService` (no GitHub self-update
fighting the store). The mapping lives in `lib/update/channel.dart`.

Each is a **manual first upload** (account creation and identity verification
can't be automated). Onboarding is documented here; per-release CI upload can be
wired later once the account exists and its API credentials are saved as
secrets — every store below has a publishing API, but the first submission and
the store-review setup are done by hand. Confirm current fees/requirements on
each console, as they change.

#### Samsung Galaxy Store

Register at the [Seller Portal](https://seller.samsungapps.com) (free; accept
the commercial seller agreement, provide payout/business info even for a free
app). Create the app, upload the release **`.aab`** (APK also accepted), fill the
listing from the fastlane metadata, pick a category and the content rating, then
submit for review. Automation later: the Galaxy Store **Seller API** (a service
account + a JWT signed with its key) can create a binary upload session and
submit — wire it as a gated CI job (skip until the key secret is set).

#### Amazon Appstore

Register at the [Amazon Developer console](https://developer.amazon.com) (free).
Add a new Android app and upload the release **APK** (Amazon historically prefers
APK over AAB and re-signs/tests the binary itself). Fill the listing from the
fastlane metadata, set the content rating, submit. Automation later: the **App
Submission API** uses a Security Profile (`client_id`/`client_secret` → OAuth
token → create edit → upload APK → commit); wire it as a gated CI job.

#### Huawei AppGallery

Register at [AppGallery Connect](https://developer.huawei.com/consumer/en/appgallery)
(free; needs identity verification — individual or enterprise — which can take a
few days). Create the app, upload the release **APK**, fill the listing from the
fastlane metadata, set the rating, submit. No HMS rework is required: the app
authenticates against Google via the browser loopback flow, which works on
HMS-only devices, and the native Credential Manager call simply falls back.
Automation later: the **AppGallery Connect Publishing API**
(`client_id`/`client_secret` → token → upload → submit); wire it as a gated CI
job.

#### Accrescent

A FOSS-leaning store with its own format. Onboard via the developer console at
<https://accrescent.app> (registration details — and any one-time anti-spam fee —
are on their site; verify the current process, it is still evolving). Accrescent
distributes an **APK Set (`.apks`)** generated from the AAB with `bundletool`,
signed with the release key. Listing copy/screenshots from the fastlane
metadata. The Accrescent client handles updates.

#### NashStore / RuMarket (Russian catalogs)

Smaller Russian catalogs besides RuStore. Both are **fully manual**: register on
each console (NashStore <https://nashstore.ru>, RuMarket via its developer
portal), upload the release `.aab`/APK by hand, and reuse the Russian listing
from `fastlane/metadata/android/ru-RU/`. No publishing API is wired up; treat
them like RuStore above.

### nixpkgs

Built from source with `flutter.buildFlutterApplication` (no binary repack);
the expression lives in the NixOS/nixpkgs tree under
`pkgs/by-name/kn/knitcalc/`, not here. Updates are PRs to nixpkgs bumping
`version`/`hash` and refreshing `pubspec.lock.json` (convert `pubspec.lock`
to JSON). Users install with `nix-env -iA nixpkgs.knitcalc` or
`environment.systemPackages = [ pkgs.knitcalc ];`.

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
