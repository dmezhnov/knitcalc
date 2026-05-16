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

- Nix with flakes enabled for Linux, Android, and Web builds.
- Flutter for local app development.
- Trunk for linting.
- mise for project tasks.

The project pins tool versions in `.tool-versions`.

## Setup

Install project tools and hooks:

```bash
mise install
```

Enter the Nix development shell when working directly with Flutter on Linux:

```bash
nix develop path:$PWD
```

Run the app:

```bash
flutter run
```

## Quality Checks

Run linters:

```bash
mise run lint
```

Format files supported by Trunk:

```bash
mise run format
```

Run Flutter analysis and tests:

```bash
mise run test
```

The release workflow runs `mise run lint` before `mise run test`. If linting
fails, the workflow stops before tests and builds.

## Builds

Build one target with:

```bash
mise run build <target>
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
mise run build apk
mise run build web
mise run build linux
```

The Web build uses `--base-href /knitcalc/` for GitHub Pages.

## Release Flow

Publishing is driven by the `test` branch:

```bash
mise run publish
```

`mise run publish` requires a clean git working tree and pushes the current
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

```yaml
version: 1.0.3+4
```

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
```

The iOS artifact is unsigned because signed iOS releases require an Apple
Developer Program account, certificates, and provisioning profiles.

The GitHub Pages site is published at:

```text
https://dmezhnov.github.io/knitcalc/
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
