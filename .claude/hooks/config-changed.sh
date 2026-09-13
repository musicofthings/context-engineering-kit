#!/usr/bin/env bash
# .claude/hooks/config-changed.sh
#
# FileChanged handler for the kit's own config files.
#
# Two things about this event are easy to get wrong, and the previous inline
# `bash -c 'echo ... $CLAUDE_FILE_PATH'` got both:
#
#   1. The `matcher` is NOT a path glob. Claude Code splits it on `|` and
#      registers each segment as a literal filename in the working directory,
#      then filters matching hooks against the changed file's *basename*. A
#      segment containing `/` (e.g. "config/usage_budget.json") therefore
#      watches a file that does not exist and can never match. The matcher in
#      hooks/hooks.json is bare basenames for that reason.
#   2. There is no CLAUDE_FILE_PATH environment variable. The changed file's
#      absolute path arrives as `file_path` on stdin.
#
# This is an observation-only handler: it records the change and tells the
# session which file moved, so stale thresholds are visible rather than silent.
# It deliberately does not reload anything — every consumer reads its config
# fresh on each invocation.

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# `source` is a POSIX special builtin: under `set -e` a missing file aborts the
# shell outright, and the trailing `|| true` does NOT catch it. Test first.
_rsd="${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"
if [ -f "$_rsd" ]; then
  # shellcheck source=../../scripts/resolve_state_dir.sh
  source "$_rsd" 2>/dev/null || true
fi
unset _rsd

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.file_path // ""' 2>/dev/null || echo "")
[ -n "$FILE_PATH" ] || FILE_PATH="(unknown)"
BASENAME="${FILE_PATH##*/}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [ -n "${STATE_DIR:-}" ] && [ -d "$STATE_DIR" ]; then
  AUDIT="$(dirname "$STATE_DIR")/config-audit.log"
  state_append "$AUDIT" "$(jq -nc --arg ts "$TIMESTAMP" --arg file "$FILE_PATH" \
    --arg event "FileChanged" '{"ts":$ts,"file":$file,"event":$event}' 2>/dev/null)" || true
fi

echo "[cek] config changed: $BASENAME — thresholds re-read on next hook run" >&2
exit 0
