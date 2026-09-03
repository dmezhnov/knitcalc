#!/usr/bin/env bash
# Bumps ONE store-listing field (samsung/amazon/huawei/fdroid/accrescent/rustore)
# of the public store-versions document to the version that store has actually
# published, so its users see the update banner (see packaging/firebase/README.md
# and lib/update/impl/store/android_store_links.dart).
#
# These fields cannot be written by release CI: a store publishes on its own
# schedule, days after the release, and a field bumped early would send users to
# a listing that still carries the old build. So this runs afterwards — for
# RuStore from the "Sync store versions" workflow, which polls the store's API
# until the version is live, and otherwise by hand through the "Bump a store
# version" workflow. Both hold the service-account key.
#
# Only the named field is touched (updateMask), so the self-update entries
# written by publish_store_versions.sh and the other stores are left intact.
#
# Required environment:
#   ACCESS_TOKEN   OAuth access token for a service account that can write the
#                  document.
#   STORE          Store field key, e.g. rustore.
#   VERSION        Marketing+build version the store published, e.g. 1.8.80+103.
#
# Usage: ACCESS_TOKEN=... STORE=rustore VERSION=1.8.80+103 \
#          packaging/firebase/bump_store_version.sh
set -euo pipefail

: "${ACCESS_TOKEN:?ACCESS_TOKEN is required}"
: "${STORE:?STORE is required}"
: "${VERSION:?VERSION is required}"
PROJECT_ID="${PROJECT_ID:-knitcalc-sync}"

# The client ignores a field it cannot parse, so a typo would fail silently
# (no banner, no error) — check both the key and the version here instead.
case "$STORE" in
    samsung | amazon | huawei | fdroid | accrescent | rustore) ;;
    *)
        echo "::error::unknown store field '$STORE'; expected one of samsung amazon huawei fdroid accrescent rustore" >&2
        exit 1
        ;;
esac

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
    echo "::error::VERSION must look like 1.8.80+103, got '$VERSION'" >&2
    exit 1
fi

url="https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/config/storeVersions"
url="${url}?updateMask.fieldPaths=${STORE}"

status="$(
    curl -sS -X PATCH "$url" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H 'Content-Type: application/json' \
        -d "{\"fields\":{\"$STORE\":{\"stringValue\":\"$VERSION\"}}}" \
        -o /tmp/bump_store_version_response.json \
        -w '%{http_code}'
)"

if [ "$status" != "200" ]; then
    echo "::error::store-versions: Firestore PATCH failed (HTTP $status)" >&2
    cat /tmp/bump_store_version_response.json >&2 || true
    exit 1
fi

echo "store-versions: $STORE is now $VERSION"
