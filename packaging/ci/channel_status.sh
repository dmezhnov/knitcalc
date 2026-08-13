#!/usr/bin/env bash
# Records the outcome of one release channel for the end-of-run report.
#
#   usage: bash packaging/ci/channel_status.sh <channel> <ok|skipped|failed> [detail]
#
# Every publishing step writes exactly one of these files; the job uploads the
# directory as a channel-status-* artifact and packaging/ci/channel_report.sh
# merges them into a single table. A channel that leaves no file behind is
# reported as `unknown`, so a step that dies before recording anything cannot
# pass for silence.
set -euo pipefail

channel="$1"
state="$2"
detail="${3:-}"

dir="${CHANNEL_STATUS_DIR:-channel-status}"
mkdir -p "$dir"
printf '%s\t%s\t%s\n' "$channel" "$state" "$detail" > "$dir/$channel.tsv"
