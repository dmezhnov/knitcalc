# KnitCalc

## Commands (run via mise)

Use these mise tasks instead of calling the toolchain directly — they wrap
project-specific setup and flags:

- `mise publish` — publish a release
- `mise test` — run tests
- `mise format` — format code
- `mise lint` — lint

Publishing also requires bumping `version:` in `pubspec.yaml` first; a pre-commit
hook blocks commits that reuse an already-published git tag.

## Commit messages

- Write commit messages in English.
- Do not mention Claude or AI assistance anywhere in the message — no
  `Co-Authored-By: Claude ...` trailers, no "Generated with" lines.
