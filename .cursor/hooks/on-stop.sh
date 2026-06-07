#!/usr/bin/env bash
# .cursor/hooks/on-stop.sh
# Cursor `stop` -> the kit's three Stop-stage steps, run in sequence (same
# order and serialization as the Claude Code Stop chain in settings.json):
#   1. extract-state-on-stop.sh  (heuristic next_action/task from transcript)
#   2. usage-tracker.py          (daily usage + forecast)
#   3. stop.sh                   (timestamp + stop reason heartbeat)
#
# extract-state-on-stop reads `.transcript_path`; if Cursor's stop payload
# doesn't carry one in the Claude JSONL format, the script gracefully falls
# back to a heartbeat-only state write. All three are best-effort.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

INPUT=$(cat 2>/dev/null || true)

printf '%s' "$INPUT" | bash "$CEK_HOOKS_DIR/extract-state-on-stop.sh" 1>&2 2>&1 || true

if [ -f "$CEK_SCRIPTS_DIR/find_python.sh" ]; then
  # shellcheck source=../../scripts/find_python.sh
  source "$CEK_SCRIPTS_DIR/find_python.sh"
  "$PYTHON" "$CEK_SCRIPTS_DIR/usage-tracker.py" </dev/null 1>&2 2>&1 || true
fi

printf '%s' "$INPUT" | bash "$CEK_HOOKS_DIR/stop.sh" 1>&2 || true
exit 0
