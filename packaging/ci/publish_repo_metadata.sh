#!/usr/bin/env bash
# Pushes the repository's own listing — description, website and topics — from
# packaging/metadata/github.json, which tool/packaging_metadata.dart renders
# from packaging/metadata/metadata.yaml along with every store listing. Run by
# the `publish` job of .github/workflows/publish.yml so the GitHub page never
# says something different from winget, Flathub or Google Play.
#
# Editing a repository's settings is not among the scopes a workflow
# `permissions:` block can grant, so the built-in GITHUB_TOKEN cannot do this:
# the step runs on PACKAGING_GITHUB_TOKEN, the same classic PAT (scope
# `public_repo`) the winget submission uses. Like every other publishing step it
# is warn-and-continue — it records its verdict for
# packaging/ci/channel_report.sh instead of aborting an already-tagged release.
#
#   usage: GH_TOKEN=<PAT> bash packaging/ci/publish_repo_metadata.sh
set -uo pipefail

repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
file="packaging/metadata/github.json"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${GH_TOKEN:-}" ]; then
    echo "::warning::PACKAGING_GITHUB_TOKEN is not set; skipping the repository listing."
    bash "$here/channel_status.sh" github-repo skipped \
        "PACKAGING_GITHUB_TOKEN is not set"
    exit 0
fi

if [ ! -f "$file" ]; then
    echo "::warning::$file is missing; skipping the repository listing."
    bash "$here/channel_status.sh" github-repo skipped "$file is missing"
    exit 0
fi

status=ok
detail="$(jq -r '.description' "$file")"

# `jq` drops the "##" comment key: the API rejects unknown fields.
if ! out="$(jq '{description, homepage}' "$file" \
    | gh api -X PATCH "repos/$repo" --input - 2>&1 >/dev/null)"; then
    status=failed
    detail="description/homepage: ${out}"
    echo "::warning::Could not update the repository description: ${out}"
fi

if [ "$status" = ok ]; then
    if ! out="$(jq '{names: .topics}' "$file" \
        | gh api -X PUT "repos/$repo/topics" --input - 2>&1 >/dev/null)"; then
        status=failed
        detail="topics: ${out}"
        echo "::warning::Could not update the repository topics: ${out}"
    fi
fi

# A 403 here almost always means the PAT lacks `public_repo` (or expired).
if [ "$status" = failed ]; then
    detail="$(printf '%s' "$detail" | tr '\n\t' '  ')"
fi

bash "$here/channel_status.sh" github-repo "$status" "$detail"
