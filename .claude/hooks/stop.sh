#!/usr/bin/env bash
# .claude/hooks/stop.sh
# Fires on Stop — when Claude finishes each response turn.
# Lightweight: only updates state.json. Heavy work is done in session-end.sh.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_FILE="$PROJECT_DIR/.claude/session/state.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$PROJECT_DIR/.claude/session"

# Read stop event input
INPUT=$(cat)
STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // "end_turn"' 2>/dev/null || echo "end_turn")

# Only update timestamp and stop reason — don't overwrite task state set by skills
if [ -f "$STATE_FILE" ]; then
  CURRENT=$(cat "$STATE_FILE")
  STATE_TMP=$(mktemp "${STATE_FILE}.XXXXXX")
  echo "$CURRENT" | jq \
    --arg ts "$TIMESTAMP" \
    --arg reason "$STOP_REASON" \
    '.last_stop = $ts | .last_stop_reason = $reason' \
    > "$STATE_TMP" && mv "$STATE_TMP" "$STATE_FILE" 2>/dev/null || rm -f "$STATE_TMP"
else
  cat > "$STATE_FILE" <<EOF
{
  "last_stop": "$TIMESTAMP",
  "last_stop_reason": "$STOP_REASON",
  "active_task": "unknown",
  "phase": "unknown",
  "next_action": "check session_handover.md",
  "compact_count": 0
}
EOF
fi

exit 0
