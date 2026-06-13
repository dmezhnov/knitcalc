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
APK/AAB works everywhere. Listing copy, screenshots and the icon are reused from
`fastlane/metadata/android/{en-US,ru-RU}/` — that directory is the single source
of truth for all catalogs; don't re-type the texts per store.

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
