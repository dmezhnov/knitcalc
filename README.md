# KnitCalc

KnitCalc is a Flutter calculator for knitting. It converts a sample swatch into
target stitch, row, and yarn-length estimates. The interface is available in
Russian and English.

[![Packaging status](https://repology.org/badge/vertical-allrepos/knitcalc.svg)](https://repology.org/project/knitcalc/versions)

## Installation

The web app runs at <https://dmezhnov.github.io/knitcalc/>. Native builds for
every platform are attached to [GitHub Releases](https://github.com/dmezhnov/knitcalc/releases);
package managers are served from this repository directly:

```bash
# Windows (Scoop; this repo doubles as the bucket)
scoop bucket add knitcalc https://github.com/dmezhnov/knitcalc
scoop install knitcalc

# macOS (Homebrew; this repo doubles as the tap — the build is unsigned)
brew tap dmezhnov/knitcalc https://github.com/dmezhnov/knitcalc
brew install --cask --no-quarantine knitcalc

# Linux
sudo snap install knitcalc      # Snap Store
yay -S knitcalc-bin             # AUR
```

Linux users can also take the AppImage (with zsync delta updates) from the
release assets, or add the apt repository hosted on the GitHub Pages site —
setup commands for it and the remaining channels (winget, Chocolatey,
IzzyOnDroid, openSUSE Build Service, nixpkgs) are collected in
[packaging/README.md](packaging/README.md). Android APKs (universal and
per-ABI) ship with every release.

## Features

- Multiple product types, selected from a dropdown. Each type provides its own
  inputs and calculations.
- Numeric inputs for the sample swatch (size, stitch and row counts) plus
  per-type target parameters.
- Live calculations from the swatch gauge — starting with stitches and rows per
  centimeter — refreshed on every input change.
- Photo attachments on saved projects, stored inline with the project data.
- Optional account (email/password or Google sign-in) that syncs projects
  between devices via Firebase; the app is fully functional without it
  (see the [privacy policy](https://dmezhnov.github.io/knitcalc/privacy.html)).
- Built-in update checks matched to the install channel: self-update for
  manual installs, the package manager or store otherwise.
- Runtime language switch between Russian and English.
- Release builds for Android, Linux, Web, Windows, macOS, and unsigned iOS.

## Requirements

- mise for project tasks and depends.

The project pins tool versions in `mise.toml`.

## Setup

Install project tools and hooks:

```bash
mise install
```

Run the app:

```bash
mise dev
```

## Quality Checks

Run linters:

```bash
mise lint
```

Format files supported by Trunk:

```bash
mise format
```

Run Flutter tests:

```bash
mise test
```

The release workflow runs `mise lint` before `mise test`. If linting
fails, the workflow stops before tests and builds.

## Builds

Build one target with:

```bash
mise build <target>
```

Supported targets:

```text
apk
apk-split
appbundle
web
linux
windows
macos
ios
```

On NixOS, the Linux build and `mise dev` wrap themselves in an ad-hoc
`nix-shell` that provides the GTK toolchain; other distros and CI use the
system toolchain directly. Windows, macOS, and iOS builds must be run on their
native GitHub Actions runners or on matching local machines.

Examples:

```bash
mise build apk
mise build web
mise build linux
```

The Web build uses `--base-href /knitcalc/` for GitHub Pages.

## Release Flow

Publishing is driven by the `test` branch:

```bash
mise publish "1.1.1+3" "Release commit message"
```

`mise publish` writes the given version into `pubspec.yaml`, commits all
working-tree changes, pushes to `origin/test`, and streams the release run
until it finishes. The part of the version before `+` is the public app
version; the number after `+` is the platform build number and should
increase for every release.

On push to `test`, GitHub Actions:

1. Runs Trunk linting, then Flutter analysis and tests.
2. Builds all supported targets — including per-ABI APKs, the AppImage with
   its `.zsync`, and a `.deb` plus a signed apt repository.
3. Merges into `main`, renders the package-manager manifests that live on
   `main` (Scoop bucket, Homebrew cask, flatpak metainfo), and recreates the
   `release/` folder with the current version's artifacts.
4. Creates a version tag and GitHub Release.
5. Publishes to the external channels: winget, Chocolatey, the Snap Store,
   and the AUR.
6. Deploys the web build (which carries the apt repository) to GitHub Pages.

A pre-commit hook blocks commits that reuse an already-published git tag.

## Outputs

The iOS artifact is unsigned because signed iOS releases require an Apple
Developer Program account, certificates, and provisioning profiles.

The GitHub Pages site is published at:

```text
https://dmezhnov.github.io/knitcalc/
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
