#!/usr/bin/env bash
# .claude/hooks/session-end.sh
# Fires on SessionEnd — when the Claude Code session closes.
# Commits session state to git so it's available on other devices/subscriptions.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_FILE="$PROJECT_DIR/.claude/session/state.json"
HISTORY_FILE="$PROJECT_DIR/.claude/session/history.jsonl"
HANDOVER_FILE="$PROJECT_DIR/session_handover.md"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

log() { echo "[session-end] $*" >&2; }

log "Session ending at $TIMESTAMP"

# ── Append to history ────────────────────────────────────────────────────────
if [ -f "$STATE_FILE" ]; then
  cat "$STATE_FILE" | jq -c ". + {\"session_ended\": \"$TIMESTAMP\"}" \
    >> "$HISTORY_FILE" 2>/dev/null || true
fi

# ── Git commit session files ─────────────────────────────────────────────────
cd "$PROJECT_DIR"

# Only commit if there are changes to session files
CHANGED=$(git diff --name-only .claude/session/ session_handover.md CLAUDE.md 2>/dev/null || echo "")

if [ -n "$CHANGED" ]; then
  git add .claude/session/state.json .claude/session/history.jsonl \
         session_handover.md CLAUDE.md 2>/dev/null || true

  ACTIVE_TASK="unknown"
  if [ -f "$STATE_FILE" ]; then
    ACTIVE_TASK=$(jq -r '.active_task // "session state"' "$STATE_FILE" 2>/dev/null || echo "session state")
  fi

  git commit -m "chore(context): save session state — $ACTIVE_TASK [$TIMESTAMP]" \
    --no-verify 2>/dev/null || log "git commit skipped (nothing to commit or not a git repo)"
else
  log "No session file changes — skipping git commit"
fi

log "Session end complete"
exit 0
