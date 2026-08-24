#!/usr/bin/env bash
# Mints a RuStore Public API authorization token (JWE) and prints it.
#
# The API authenticates each session with a signature rather than a bearer
# secret: sign "<keyId><timestamp>" with the RSA private key issued by the
# console (SHA512withRSA), post it, get a JWE valid for 900 seconds. The
# signature itself is only valid for a minute, so the token is minted at the
# point of use, never stored.
#
# Required environment:
#   RUSTORE_KEY_ID        Numeric key id from the console's "API RuStore" page.
#   RUSTORE_PRIVATE_KEY   The private key that page shows exactly once, as the
#                         bare Base64 PKCS#8 body (no PEM header) or a full PEM.
#
# Usage: RUSTORE_KEY_ID=... RUSTORE_PRIVATE_KEY="$(cat key.txt)" \
#          packaging/rustore/auth_token.sh
set -euo pipefail

: "${RUSTORE_KEY_ID:?RUSTORE_KEY_ID is required}"
: "${RUSTORE_PRIVATE_KEY:?RUSTORE_PRIVATE_KEY is required}"

API="${RUSTORE_API:-https://public-api.rustore.ru}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"

# The console hands out the naked Base64 body; openssl wants PEM. Both the
# 64-column wrapping and the newline before the END line matter: without the
# latter openssl reads the footer as part of the body and reports the key as an
# undecodable "EncryptedPrivateKeyInfo" (measured), which reads like a wrong key.
pem="$work/key.pem"
if [[ "$RUSTORE_PRIVATE_KEY" == *"-----BEGIN"* ]]; then
    printf '%s\n' "$RUSTORE_PRIVATE_KEY" > "$pem"
else
    {
        echo '-----BEGIN PRIVATE KEY-----'
        printf '%s\n' "$(printf '%s' "$RUSTORE_PRIVATE_KEY" | tr -d ' \n\r' | fold -w 64)"
        echo '-----END PRIVATE KEY-----'
    } > "$pem"
fi

# Milliseconds and a colon in the offset are both required by the API
# (2026-08-24T19:28:00.123+03:00); %:z gives the colon, %3N the milliseconds.
timestamp="$(date +%Y-%m-%dT%H:%M:%S.%3N%:z)"

signature="$(
    printf '%s' "${RUSTORE_KEY_ID}${timestamp}" |
        openssl dgst -sha512 -sign "$pem" -binary |
        openssl base64 -A
)"

response="$work/auth.json"
status="$(
    curl -sS -X POST "${API}/public/auth/" \
        -H 'Content-Type: application/json' \
        -d "{\"keyId\":\"${RUSTORE_KEY_ID}\",\"timestamp\":\"${timestamp}\",\"signature\":\"${signature}\"}" \
        -o "$response" \
        -w '%{http_code}'
)"

# The API answers 200 with a body-level error code as well, so the body decides.
token="$(python3 -c 'import json,sys; print((json.load(open(sys.argv[1])).get("body") or {}).get("jwe",""))' "$response" 2>/dev/null || true)"

if [ "$status" != "200" ] || [ -z "$token" ]; then
    echo "::error::rustore: auth failed (HTTP $status)" >&2
    # The response carries no secret — only a code and a message.
    cat "$response" >&2 || true
    exit 1
fi

printf '%s\n' "$token"
