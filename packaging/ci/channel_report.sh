#!/usr/bin/env bash
# Merges the per-channel status files written by packaging/ci/channel_status.sh
# into one table on the job summary, one annotation per channel, and a non-zero
# exit if the release did not reach every channel.
#
# The publishing steps themselves stay warn-and-continue on purpose (a store
# outage must not abort a release that is already tagged and uploaded), so this
# job is the only thing that turns "one channel silently did not update" into a
# red run — and into a non-zero `mise publish`.
set -uo pipefail

dir="${CHANNEL_STATUS_DIR:-channel-status}"
summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

# Every channel a release is expected to reach, in reporting order.
channels=(
    "github-release|GitHub release"
    "github-repo|GitHub repository listing"
    "pages|GitHub Pages (web + apt repo)"
    "apt|apt repository"
    "scoop|Scoop bucket"
    "homebrew|Homebrew cask"
    "firestore|Firestore update banner"
    "winget|winget"
    "chocolatey|Chocolatey"
    "snap|Snap Store"
    "aur|AUR"
    "rustore|RuStore"
    "mise-linux|mise (Linux install check)"
    "mise-windows|mise (Windows install check)"
    "mise-macos|mise (macOS install check)"
)

{
    echo "## Release channels"
    echo
    echo "| Channel | Status | Detail |"
    echo "| --- | --- | --- |"
} >> "$summary"

failed=0
published=()
for entry in "${channels[@]}"; do
    id="${entry%%|*}"
    name="${entry#*|}"
    file="$dir/$id.tsv"

    if [ -f "$file" ]; then
        state="$(head -1 "$file" | cut -f2)"
        detail="$(head -1 "$file" | cut -f3-)"
    else
        state="unknown"
        detail="the job that publishes this channel did not run to completion"
    fi

    case "$state" in
        ok) icon="✅" ;;
        skipped) icon="⚠️" ;;
        *) icon="❌" ;;
    esac

    # A detail carrying a pipe would split the markdown row; a stray CR (the
    # Windows steps capture tool output) would break the annotation.
    cell="$(printf '%s' "$detail" | tr -d '\r' | sed 's/|/\\|/g')"
    printf '| %s | %s %s | %s |\n' "$name" "$icon" "$state" "$cell" >> "$summary"

    if [ "$state" = ok ]; then
        # One annotation per channel would lose the tail of the list: GitHub
        # renders at most 10 notices per step and there are more channels than
        # that (AUR and the mise checks used to fall off the end), so the green
        # ones are collected and announced together. Failures stay one apiece —
        # they are errors, which are not capped, and each needs its own detail.
        published+=("${name}: ${detail:-published}")
    else
        failed=1
        echo "::error::${name}: ${state}${detail:+ — $detail}"
    fi
done

if [ "${#published[@]}" -ne 0 ]; then
    printf -v joined '%s; ' "${published[@]}"
    echo "::notice::Published — ${joined%; }"
fi

if [ "$failed" -ne 0 ]; then
    {
        echo
        echo "The release itself is published — only the marked channels are behind."
        echo "Fix the cause and re-run the owning job; nothing needs a new version."
    } >> "$summary"
fi

exit "$failed"
