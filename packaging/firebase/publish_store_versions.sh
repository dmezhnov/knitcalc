#!/usr/bin/env bash
# Writes the self-update channel entries (android/windows/macos/linux) into the
# public store-versions document the app reads to decide whether to show the
# update banner (see lib/update/impl/remote/store_versions.dart).
#
# Run by the release CI after the GitHub release is created. The download URLs
# point at the freshly published release assets on the GitHub CDN; only the
# version *check* lives in Firestore, the binaries still download from GitHub.
#
# It PATCHes ONLY the four self-update fields with an updateMask, so the
# manually-bumped store fields (samsung/amazon/huawei/fdroid/accrescent) — which
# are updated by hand once each store has actually published — are left intact.
#
# Required environment:
#   ACCESS_TOKEN   OAuth access token for a service account that can write the
#                  document (produced by google-github-actions/auth).
#   VERSION        Marketing+build version, e.g. 1.8.35+58.
#   ARTIFACT_DIR   Directory containing the release artifacts (searched
#                  recursively for each asset to read its byte size).
#   REPO           owner/name, e.g. dmezhnov/knitcalc (defaults to
#                  GITHUB_REPOSITORY).
#
# Usage: ACCESS_TOKEN=... VERSION=1.8.35+58 ARTIFACT_DIR=release-download \
#          packaging/firebase/publish_store_versions.sh
set -euo pipefail

: "${ACCESS_TOKEN:?ACCESS_TOKEN is required}"
: "${VERSION:?VERSION is required}"
: "${ARTIFACT_DIR:?ARTIFACT_DIR is required}"
REPO="${REPO:-${GITHUB_REPOSITORY:?REPO or GITHUB_REPOSITORY is required}}"
PROJECT_ID="${PROJECT_ID:-knitcalc-sync}"

base_url="https://github.com/${REPO}/releases/download/v${VERSION}"

# Byte size of the first artifact matching the given basename, or empty.
asset_size() {
    local name="$1" path
    path="$(find "$ARTIFACT_DIR" -name "$name" -type f -print -quit 2>/dev/null || true)"
    [ -n "$path" ] && stat -c '%s' "$path" || true
}

# Emits a Firestore mapValue field for one self-update channel, or nothing when
# the asset is absent from the artifact dir (so a partial build never publishes
# a dangling URL).
channel_field() {
    local key="$1" asset="$2" size
    size="$(asset_size "$asset")"
    if [ -z "$size" ]; then
        echo "::warning::store-versions: asset $asset not found; skipping $key" >&2
        return 0
    fi
    cat <<JSON
"$key":{"mapValue":{"fields":{"version":{"stringValue":"$VERSION"},"url":{"stringValue":"$base_url/$asset"},"size":{"integerValue":"$size"}}}},
JSON
}

# Emits a per-ABI APK as a Firestore mapValue field, or nothing when absent.
abi_asset() {
    local abi="$1" file="knitcalc-${VERSION}-$1.apk" size
    size="$(asset_size "$file")"
    [ -z "$size" ] && return 0
    cat <<JSON
"$abi":{"mapValue":{"fields":{"url":{"stringValue":"$base_url/$file"},"size":{"integerValue":"$size"}}}},
JSON
}

# The android field: the universal APK (url/size) plus an `abis` sub-map of the
# per-ABI APKs, so the app downloads the ~3x smaller APK matching the device and
# falls back to the universal one when its ABI is unknown/absent.
android_field() {
    local universal="knitcalc-${VERSION}.apk" size abis abis_field=""
    size="$(asset_size "$universal")"
    if [ -z "$size" ]; then
        echo "::warning::store-versions: asset $universal not found; skipping android" >&2
        return 0
    fi
    abis="$(
        abi_asset arm64-v8a
        abi_asset armeabi-v7a
        abi_asset x86_64
    )"
    abis="${abis%,}"
    [ -n "$abis" ] && abis_field=",\"abis\":{\"mapValue\":{\"fields\":{$abis}}}"
    cat <<JSON
"android":{"mapValue":{"fields":{"version":{"stringValue":"$VERSION"},"url":{"stringValue":"$base_url/$universal"},"size":{"integerValue":"$size"}$abis_field}}},
JSON
}

fields="$(
    android_field
    # Windows self-update downloads and runs the inno installer, not the zip.
    channel_field windows "knitcalc-setup-x64-${VERSION}.exe"
    channel_field macos "knitcalc-macos-${VERSION}.zip"
    channel_field linux "knitcalc-linux-x64-${VERSION}.tar.gz"
)"

# Strip the trailing comma left by the last field.
fields="${fields%,}"

if [ -z "$fields" ]; then
    echo "::warning::store-versions: no assets found; nothing to publish" >&2
    exit 0
fi

body="{\"fields\":{$fields}}"

url="https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/config/storeVersions"
# updateMask keeps the hand-bumped store fields intact; PATCH creates the
# document if it does not exist yet.
url="${url}?updateMask.fieldPaths=android&updateMask.fieldPaths=windows&updateMask.fieldPaths=macos&updateMask.fieldPaths=linux"

status="$(
    curl -sS -X PATCH "$url" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H 'Content-Type: application/json' \
        -d "$body" \
        -o /tmp/store_versions_response.json \
        -w '%{http_code}'
)"

if [ "$status" != "200" ]; then
    echo "::error::store-versions: Firestore PATCH failed (HTTP $status)" >&2
    cat /tmp/store_versions_response.json >&2 || true
    exit 1
fi

echo "store-versions: published self-update entries for $VERSION"
