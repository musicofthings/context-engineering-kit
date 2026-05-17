#!/usr/bin/env bash
# .claude/hooks/stop.sh
# Fires on Stop — when Claude finishes each response turn.
# Lightweight: only updates state.json. Heavy work is done in session-end.sh.

set -euo pipefail
umask 0077

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Resolve state location (shared worktree-aware helper) ─────────────────────
# shellcheck source=../../scripts/resolve_state_dir.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"

# Read stop event input
INPUT=$(cat)
STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // "end_turn"' 2>/dev/null || echo "end_turn")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")

# Only update timestamp and stop reason — don't overwrite task state set by
# skills. state_write treats a missing file as {}, so defaults are seeded here.
# Keep session_id/transcript_path fresh for the handover's resume section.
state_write \
  '.last_stop = $ts
   | .last_stop_reason = $reason
   | (if $sid != "" then .session_id = $sid else . end)
   | (if $tx  != "" then .transcript_path = $tx else . end)
   | .active_task = (.active_task // "unknown")
   | .phase = (.phase // "unknown")
   | .next_action = (.next_action // "check session_handover.md")
   | .compact_count = (.compact_count // 0)' \
  --arg ts "$TIMESTAMP" --arg reason "$STOP_REASON" \
  --arg sid "$SESSION_ID" --arg tx "$TRANSCRIPT_PATH" || true

exit 0
