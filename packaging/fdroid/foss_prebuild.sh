#!/bin/sh
# F-Droid `foss` prebuild: strips the proprietary Google Play Services
# dependency so F-Droid can build KnitCalc from source and its scanner accepts
# the result.
#
# F-Droid builds from source and rejects bundled proprietary blobs. The native
# Google account picker pulls in `play-services-auth` via `google_sign_in`, so
# this script, run from the fdroiddata build recipe's `prebuild` (see
# packaging/fdroid/io.github.dmezhnov.knitcalc.yml), does two things before
# `flutter pub get`:
#
#   1. removes the `google_sign_in` dependency from pubspec.yaml;
#   2. swaps the Play-Services-free fetcher stub over the production fetcher
#      (the only file importing `package:google_sign_in`).
#
# The app then has no native picker and signs in through the loopback browser
# OAuth flow — the same path Play-Services-less devices already take. Run from
# the repository root. Idempotent and fails loudly if the inputs drift.
set -eu

pubspec="pubspec.yaml"
real="lib/firebase/native_id_token_fetcher.dart"
stub="lib/firebase/native_id_token_fetcher_foss.dart"

[ -f "$pubspec" ] || { echo "foss_prebuild: $pubspec not found (run from repo root)" >&2; exit 1; }
[ -f "$stub" ]    || { echo "foss_prebuild: $stub not found" >&2; exit 1; }

# 1. Drop the google_sign_in dependency. Guard that the line existed, so a
#    pubspec rename can't let a Play-Services build slip through unnoticed.
if ! grep -qE '^[[:space:]]+google_sign_in:' "$pubspec"; then
  echo "foss_prebuild: no google_sign_in dependency in $pubspec — refusing to continue (did the key change?)" >&2
  exit 1
fi
sed -i -E '/^[[:space:]]+google_sign_in:/d' "$pubspec"

# 2. Replace the production fetcher with the stub.
cp "$stub" "$real"

echo "foss_prebuild: removed google_sign_in and applied the FOSS sign-in stub."
