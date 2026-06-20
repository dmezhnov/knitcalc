# Store-versions document (update availability)

The app decides whether to show the "update available" banner by reading a
single public Firestore document instead of polling the GitHub API. This avoids
GitHub's unauthenticated rate limit (60 requests/hour **per IP** — easily shared
away under carrier-grade NAT on mobile) and, for the app stores, lets the
version be bumped only once the store has actually published, so the banner
never runs ahead of the store.

- Client: `lib/update/impl/remote/store_versions.dart` (decode + evaluate),
  `remote_versions_source.dart` (fetch).
- CI writer: `packaging/firebase/publish_store_versions.sh`, called from the
  `publish` job in `.github/workflows/publish.yml`.

## Document

Path: `config/storeVersions` in the `knitcalc-sync` project (default database).

Each field is keyed by channel. Two shapes:

- **Self-update channels** (`android`, `windows`, `macos`, `linux`) — a map with
  the download `url` (a GitHub release asset on the CDN), `version` and `size`.
  These are written automatically by release CI. The `android` entry also
  carries an `abis` sub-map of per-ABI APKs (`arm64-v8a`, `armeabi-v7a`,
  `x86_64`, each `{url,size}`); the app downloads the ~3x smaller per-ABI APK
  matching the device and falls back to the universal `url` when its ABI is
  unknown or absent. All APKs share one versionCode (see
  `android/app/build.gradle.kts`), so the variants are interchangeable.
- **Store-listing channels** (`samsung`, `amazon`, `huawei`, `fdroid`,
  `accrescent`) — a bare version string. The app opens the store listing to
  update; it downloads nothing. **Bumped by hand** (see below).

Example (Firestore console / REST shape):

```json
{
    "fields": {
        "android": {
            "mapValue": {
                "fields": {
                    "version": { "stringValue": "1.8.35+58" },
                    "url": {
                        "stringValue": "https://github.com/dmezhnov/knitcalc/releases/download/v1.8.35+58/knitcalc-1.8.35+58.apk"
                    },
                    "size": { "integerValue": "12582912" }
                }
            }
        },
        "windows": { "mapValue": { "fields": { "...": "..." } } },
        "macos": { "mapValue": { "fields": { "...": "..." } } },
        "linux": { "mapValue": { "fields": { "...": "..." } } },
        "fdroid": { "stringValue": "1.8.34+57" },
        "samsung": { "stringValue": "1.8.33+56" }
    }
}
```

A field whose version cannot be parsed is ignored by the client, so a malformed
or in-progress entry for one channel never breaks the others.

## Public read rule

The document must be world-readable (it is non-secret version metadata, and the
read happens before/without sign-in). Add to the project's Firestore rules:

```text
match /databases/{database}/documents {
  // ... existing user-scoped rules ...

  // Public, read-only update-availability metadata. Writes are restricted to
  // the release service account (which bypasses rules), so no write rule here.
  match /config/{document} {
    allow read: if true;
    allow write: if false;
  }
}
```

## CI write (self-update channels)

The `publish` job mints a token from the `FIREBASE_SA_KEY` service-account key
with `gcloud auth activate-service-account` + `print-access-token` (a self-signed
JWT — deliberately avoids `iamcredentials.googleapis.com`, which is not enabled
on the project) and runs `publish_store_versions.sh`, which PATCHes only the four
self-update fields (`updateMask`), leaving the hand-bumped store fields intact.
The step is `continue-on-error`, so a Firestore problem never fails the release
or the package-manager jobs that depend on it; it is skipped with a warning when
`FIREBASE_SA_KEY` is unset (like the Chocolatey push).

One-time setup: a service account `release-publisher@knitcalc-sync.iam` with role
`roles/datastore.user` and its key in the `FIREBASE_SA_KEY` secret. This was
created headless (the maintainer's IP can't reach the Firebase/Cloud console or
most googleapis.com hosts) via the throwaway `firebase-bootstrap` branch
workflow; see the commit history if it must be recreated.

## Manual store-version bump (store-listing channels)

When a store (Samsung, Amazon, Huawei, F-Droid, Accrescent) has **actually
published** a new version, set that store's field to the published version so
its users see the banner. Either edit the document in the Firestore console, or
PATCH a single field, e.g. for F-Droid:

```bash
ACCESS_TOKEN="$(gcloud auth print-access-token)"   # or the SA token
curl -X PATCH \
  "https://firestore.googleapis.com/v1/projects/knitcalc-sync/databases/(default)/documents/config/storeVersions?updateMask.fieldPaths=fdroid" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"fields":{"fdroid":{"stringValue":"1.8.35+58"}}}'
```

Do **not** bump a store's field until that store's listing is live, or the
banner will send users to a store that still has the old version.
