#!/usr/bin/env bash
# Publishes one release to RuStore through the Public API: create a draft
# version, upload the no-sideload APK into it, send it for moderation.
#
# RuStore moderates every version (up to three days), so this only *submits* —
# the listing goes live later, on its own. That is also why the `rustore` field
# of the store-versions document is bumped separately, once the store has
# actually published: the "Sync store versions" workflow polls for that with
# packaging/rustore/published_version.sh.
#
# The upload is the **no-sideload** APK on purpose: the normal one carries
# REQUEST_INSTALL_PACKAGES, which RuStore's information-security review rejects
# (it turned 1.8.79+102 down over exactly that). See "The no-sideload APK" in
# packaging/README.md.
#
# Idempotent, because RuStore allows exactly ONE draft per application and a
# draft cannot be edited, only deleted: a re-run first checks whether this
# versionCode is already submitted (then it does nothing) and otherwise deletes
# whatever draft is lying around before creating its own. So a failed run is
# fixed by re-running it, never by cleaning up in the console.
#
# Required environment:
#   RUSTORE_KEY_ID, RUSTORE_PRIVATE_KEY   API key from the console (see
#                                         packaging/rustore/auth_token.sh).
#   VERSION                               Marketing+build version, 1.9.1+105.
#   APK                                   Path to knitcalc-<version>-nosideload.apk.
# Optional:
#   WHATS_NEW    "What's new" text for this version (max 5000 chars). Defaults
#                to fastlane/metadata/android/ru-RU/changelogs/<versionCode>.txt
#                when that file exists, and to a one-line fallback otherwise.
#   MODER_INFO   Comment for the moderator (max 180 characters).
#   PACKAGE_NAME Application id (defaults to the published one).
#
# Usage: RUSTORE_KEY_ID=... RUSTORE_PRIVATE_KEY="$(cat key.txt)" \
#          VERSION=1.9.1+105 APK=release-download/knitcalc-1.9.1+105-nosideload.apk \
#          packaging/rustore/publish_version.sh
set -euo pipefail

: "${VERSION:?VERSION is required}"
: "${APK:?APK is required}"

PACKAGE_NAME="${PACKAGE_NAME:-io.github.dmezhnov.knitcalc}"
API="${RUSTORE_API:-https://public-api.rustore.ru}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"

[ -f "$APK" ] || { echo "::error::rustore: no APK at $APK" >&2; exit 1; }

# 1.9.1+105 -> 105. RuStore identifies a version by its code, not its name.
version_code="${VERSION##*+}"
if ! [[ "$version_code" =~ ^[0-9]+$ ]]; then
    echo "::error::rustore: cannot read a versionCode out of '$VERSION'" >&2
    exit 1
fi

changelog="$repo/fastlane/metadata/android/ru-RU/changelogs/${version_code}.txt"
if [ -z "${WHATS_NEW:-}" ] && [ -f "$changelog" ]; then
    WHATS_NEW="$(cat "$changelog")"
fi
WHATS_NEW="${WHATS_NEW:-Обновление до версии ${VERSION%%+*}.}"
MODER_INFO="${MODER_INFO:-Автоматическая публикация из CI. Тестовый аккаунт не нужен — приложение работает без регистрации.}"

# Echoed because the store shows this text to users and nothing else in the run
# reveals which of the three sources won.
echo "rustore: what's new — ${WHATS_NEW}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

token="$(RUSTORE_KEY_ID="${RUSTORE_KEY_ID:?}" RUSTORE_PRIVATE_KEY="${RUSTORE_PRIVATE_KEY:?}" "$here/auth_token.sh")"

# Every endpoint answers 200 with a body-level `code`, so both are checked.
# Prints the response body on success; dies with it on failure.
api() {
    local method="$1" path="$2"
    shift 2
    local body="$work/response.json" status
    status="$(
        curl -sS -X "$method" "${API}${path}" \
            -H "Public-Token: $token" \
            "$@" \
            -o "$body" \
            -w '%{http_code}'
    )"
    if [ "$status" != "200" ] || [ "$(json "$body" 'd.get("code")')" != "OK" ]; then
        echo "::error::rustore: $method $path failed (HTTP $status)" >&2
        cat "$body" >&2 || true
        exit 1
    fi
    cat "$body"
}

# Evaluates a Python expression against the parsed response, where `d` is the
# document; prints nothing when the path is absent.
json() {
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); v=eval(sys.argv[2]); print("" if v is None else v)' "$1" "$2"
}

versions="$work/versions.json"
api GET "/public/v1/application/${PACKAGE_NAME}/version?page=0&size=50" > "$versions"

# A re-run after a green submission must not submit again — RuStore would
# reject the duplicate versionCode anyway, but with a failure rather than a
# no-op, and a moderation queue is not something to poke twice.
existing="$(json "$versions" "next((v['versionStatus'] for v in d['body']['content'] if v['versionCode']==${version_code} and v['versionStatus'] not in ('REJECTED_BY_MODERATOR','REJECTED_BY_SECURITY','DELETED_DRAFT')), None)")"
if [ -n "$existing" ]; then
    echo "rustore: versionCode ${version_code} is already there as ${existing}; nothing to do."
    exit 0
fi

# One draft per application, and a draft cannot be edited — so a leftover draft
# (an earlier failed run, or something started in the console) has to go before
# this one can be created.
draft="$(json "$versions" "next((v['versionId'] for v in d['body']['content'] if v['versionStatus']=='DRAFT'), None)")"
if [ -n "$draft" ]; then
    echo "rustore: deleting the existing draft ${draft}."
    api DELETE "/public/v1/application/${PACKAGE_NAME}/version/${draft}" > /dev/null
fi

# Fields left out of the request are inherited from the active version, which is
# where the name, categories, descriptions, price and contacts come from — this
# sends only what changes per release.
python3 - "$work/draft.json" "$WHATS_NEW" "$MODER_INFO" <<'PY'
import json, sys
path, whats_new, moder_info = sys.argv[1], sys.argv[2], sys.argv[3]
json.dump(
    {
        "whatsNew": whats_new[:5000],
        "moderInfo": moder_info[:180],
        "publishType": "INSTANTLY",
    },
    open(path, "w"),
    ensure_ascii=False,
)
PY

created="$work/created.json"
api POST "/public/v1/application/${PACKAGE_NAME}/version" \
    -H 'Content-Type: application/json' \
    --data-binary "@$work/draft.json" > "$created"
# The docs describe the answer as `body.versionId`, but the API returns the id
# as a bare `body` number (measured against the live app); accept both.
version_id="$(json "$created" "d['body'] if isinstance(d['body'], int) else d['body']['versionId']")"
echo "rustore: draft ${version_id} created for ${VERSION}."

# isMainApk=true marks it as the binary users get; servicesType stays Unknown
# (HMS is a separate, Huawei-only slot we do not fill).
#
# A 400 here naming "new sensitive permissions" is not a bug in this script: the
# API refuses any permission the previous version did not declare, and such a
# release has to be uploaded through the console once, with the permission
# declaration filled in. Nothing else about the flow changes.
api POST "/public/v1/application/${PACKAGE_NAME}/version/${version_id}/apk?isMainApk=true&servicesType=Unknown" \
    -F "file=@${APK}" > /dev/null
echo "rustore: uploaded $(basename "$APK")."

api POST "/public/v1/application/${PACKAGE_NAME}/version/${version_id}/commit?priorityUpdate=0" > /dev/null
echo "rustore: version ${VERSION} (code ${version_code}) sent for moderation."
