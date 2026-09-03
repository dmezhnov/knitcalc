#!/usr/bin/env bash
# Prints the version RuStore actually serves right now, e.g. "1.9.1+105", or
# nothing at all when the app has no live version there yet.
#
# This answers the one question a release run cannot: RuStore moderates every
# submission (up to three days) and publishes on its own schedule, which is why
# the `rustore` field of the store-versions document must never be bumped at
# release time. It used to be bumped by hand once the listing went live; the
# "Sync store versions" workflow now polls this script instead and bumps the
# field itself. See .github/workflows/sync-store-versions.yml and
# packaging/firebase/bump_store_version.sh.
#
# Only ACTIVE counts as published. PARTIAL_ACTIVE is a staged rollout that most
# users do not have yet, so a field bumped to it would put a banner in front of
# people whose listing still offers the old build — such a version is reported
# and ignored, and it becomes ACTIVE once the rollout reaches 100%.
#
# Required environment:
#   RUSTORE_KEY_ID, RUSTORE_PRIVATE_KEY   API key from the console (see
#                                         packaging/rustore/auth_token.sh).
# Optional:
#   PACKAGE_NAME  Application id (defaults to the published one).
#
# Usage: RUSTORE_KEY_ID=... RUSTORE_PRIVATE_KEY="$(cat key.txt)" \
#          packaging/rustore/published_version.sh
set -euo pipefail

PACKAGE_NAME="${PACKAGE_NAME:-io.github.dmezhnov.knitcalc}"
API="${RUSTORE_API:-https://public-api.rustore.ru}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

token="$(RUSTORE_KEY_ID="${RUSTORE_KEY_ID:?}" RUSTORE_PRIVATE_KEY="${RUSTORE_PRIVATE_KEY:?}" "$here/auth_token.sh")"

# Same page as publish_version.sh reads: the list is newest first and one app
# never has fifty versions in flight, so the live one is always on it.
versions="$work/versions.json"
status="$(
    curl -sS -X GET "${API}/public/v1/application/${PACKAGE_NAME}/version?page=0&size=50" \
        -H "Public-Token: $token" \
        -o "$versions" \
        -w '%{http_code}'
)"

# The API answers 200 with a body-level error code as well, so both are checked.
code="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("code",""))' "$versions" 2>/dev/null || true)"
if [ "$status" != "200" ] || [ "$code" != "OK" ]; then
    echo "::error::rustore: version list failed (HTTP $status)" >&2
    cat "$versions" >&2 || true
    exit 1
fi

# Notices go to stderr so that stdout carries the version and nothing else —
# the caller reads it straight into a variable.
published="$(
    python3 - "$versions" <<'PY'
import json, sys

versions = json.load(open(sys.argv[1]))["body"]["content"]
live = [v for v in versions if v["versionStatus"] == "ACTIVE"]
staged = [v for v in versions if v["versionStatus"] == "PARTIAL_ACTIVE"]

for v in staged:
    print(
        f"rustore: {v['versionName']}+{v['versionCode']} is a staged rollout at "
        f"{v.get('partialValue')}% — not counted as published.",
        file=sys.stderr,
    )

if not live:
    # The statuses are listed rather than swallowed: "no ACTIVE version" is also
    # what a renamed status would look like, and this is the only place the
    # difference shows.
    seen = ", ".join(
        f"{v['versionName']}+{v['versionCode']} {v['versionStatus']}" for v in versions[:5]
    )
    print(f"rustore: no ACTIVE version among [{seen or 'nothing'}].", file=sys.stderr)
    sys.exit(0)

# More than one ACTIVE version is not a thing RuStore does, but taking the
# newest keeps this honest if it ever happens.
newest = max(live, key=lambda v: v["versionCode"])
print(f"{newest['versionName']}+{newest['versionCode']}")
PY
)"

if [ -z "$published" ]; then
    exit 0
fi

# The store echoes back whatever versionName was uploaded, and the field feeds a
# version comparison in the app — so it is checked here rather than trusted.
if ! [[ "$published" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
    echo "::error::rustore: unusable published version '$published'" >&2
    exit 1
fi

printf '%s\n' "$published"
