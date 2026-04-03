#!/usr/bin/env bash
# .claude/hooks/track-changes.sh
# PostToolUse on Edit|Write — logs file changes to session state.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_FILE="$PROJECT_DIR/.claude/session/state.json"
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")

[ -z "$FILE_PATH" ] && exit 0

mkdir -p "$PROJECT_DIR/.claude/session"

# Append to changed_files list in state.json
if [ -f "$STATE_FILE" ]; then
  jq --arg f "$FILE_PATH" \
    'if (.changed_files | index($f)) then . else .changed_files += [$f] end' \
    "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE" 2>/dev/null || true
fi

exit 0
