# KnitCalc

## Commands (run via mise)

Use these mise tasks instead of calling the toolchain directly — they wrap
project-specific setup and flags:

- `mise publish` — publish a release
- `mise test` — run tests
- `mise format` — format code
- `mise lint` — lint
- `mise metadata` — re-render every store/package-manager listing

## Store listings

Names, descriptions, URLs, tags and screenshots for every channel (winget,
Scoop, Chocolatey, Homebrew, apt, AUR, rpm, Snap, Flathub, F-Droid/fastlane,
the Inno installer, the GitHub repo page) are generated from the single source
`packaging/metadata/metadata.yaml` — edit that file and run `mise metadata`,
never the generated files. `mise lint` fails if they drift. The icon has the
same treatment: it comes from `assets/icon/icon.png`. See
`packaging/README.md`.

Publishing also requires bumping `version:` in `pubspec.yaml` first; a pre-commit
hook blocks commits that reuse an already-published git tag.

## Commit messages

- Write commit messages in English.
- Do not mention Claude or AI assistance anywhere in the message — no
  `Co-Authored-By: Claude ...` trailers, no "Generated with" lines.
