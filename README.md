# KnitCalc

KnitCalc is a Flutter calculator for rectangular scarf knitting. It converts a
sample swatch into target stitch, row, and yarn-length estimates.

## Features

- Rectangular scarf preset.
- Numeric inputs for swatch size, stitch count, row count, target dimensions,
  and yarn length.
- Live calculations for:
    - stitches per centimeter
    - rows per centimeter
    - target stitch count
    - target row count
    - target yarn length
- Release builds for Android, Linux, Web, Windows, macOS, and unsigned iOS.
- GitHub Pages deployment for the web build.

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

Run Flutter analysis and tests:

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
appbundle
web
linux
windows
macos
ios
```

Linux, Android, and Web builds run through the Nix development shell. Windows,
macOS, and iOS builds must be run on their native GitHub Actions runners or on
matching local machines.

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
mise publish
```

`mise publish` requires a clean git working tree and pushes the current
commit to `origin/test`.

On push to `test`, GitHub Actions:

1. Runs Trunk linting.
2. Runs Flutter analysis and tests.
3. Builds all supported targets.
4. Recreates the `release/` folder with the current version's artifacts.
5. Pushes the release commit to `main`.
6. Creates a version tag and GitHub Release.
7. Deploys the web build to GitHub Pages.

Before publishing a new release, bump `version` in `pubspec.yaml`. For example:

````yaml
version: 1.0.1+2```

The part before `+` is the public app version. The number after `+` is the
platform build number and should increase for every release.

## Outputs

Release artifacts are written under `release/`:

```text
release/android/
release/linux/
release/web/
release/windows/
release/macos/
release/ios/
````

The iOS artifact is unsigned because signed iOS releases require an Apple
Developer Program account, certificates, and provisioning profiles.

The GitHub Pages site is published at:

```text
https://dmezhnov.github.io/knitcalc/
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
