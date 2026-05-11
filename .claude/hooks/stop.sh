#!/usr/bin/env bash
# .claude/hooks/stop.sh
# Fires on Stop — when Claude finishes each response turn.
# Lightweight: only updates state.json. Heavy work is done in session-end.sh.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Worktree detection — always write state to main checkout ──────────────────
GIT_DIR=$(git -C "$PROJECT_DIR" rev-parse --git-dir 2>/dev/null || echo "")
if echo "$GIT_DIR" | grep -q '/worktrees/'; then
  MAIN_ROOT=$(git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null \
    | awk 'NR==1{sub(/^worktree /,""); print}')
  [ -n "$MAIN_ROOT" ] && STATE_DIR="$MAIN_ROOT/.claude/session" || STATE_DIR="$PROJECT_DIR/.claude/session"
else
  STATE_DIR="$PROJECT_DIR/.claude/session"
fi
STATE_FILE="$STATE_DIR/state.json"

mkdir -p "$STATE_DIR"

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
