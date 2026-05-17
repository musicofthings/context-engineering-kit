#!/usr/bin/env bash
# .claude/hooks/track-changes.sh
# PostToolUse on Edit|Write — logs file changes to session state.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# shellcheck source=../../scripts/resolve_state_dir.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")

[ -z "$FILE_PATH" ] && exit 0

# Append to changed_files list (lock-guarded, concurrency-safe)
state_write \
  'if ((.changed_files // []) | index($f)) then . else .changed_files = ((.changed_files // []) + [$f]) end' \
  --arg f "$FILE_PATH" || true

exit 0
