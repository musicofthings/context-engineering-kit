#!/usr/bin/env bash
# .claude/hooks/post-compact.sh
# Fires AFTER compaction AND when SessionStart detects a compact resume.
# Re-injects critical context so Claude doesn't lose project awareness.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_FILE="$PROJECT_DIR/.claude/session/state.json"
HANDOVER_FILE="$PROJECT_DIR/session_handover.md"

log() { echo "[post-compact] $*" >&2; }

# ── Load state ───────────────────────────────────────────────────────────────
if [ -f "$STATE_FILE" ]; then
  ACTIVE_TASK=$(jq -r '.active_task // "not set"' "$STATE_FILE" 2>/dev/null || echo "not set")
  PHASE=$(jq -r '.phase // "not set"' "$STATE_FILE" 2>/dev/null || echo "not set")
  NEXT_ACTION=$(jq -r '.next_action // "not set"' "$STATE_FILE" 2>/dev/null || echo "not set")
  GIT_BRANCH=$(jq -r '.git_branch // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
  GIT_COMMIT=$(jq -r '.git_last_commit // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
  COMPACT_COUNT=$(jq -r '.compact_count // 1' "$STATE_FILE" 2>/dev/null || echo "1")
else
  ACTIVE_TASK="unknown — read session_handover.md"
  PHASE="unknown"
  NEXT_ACTION="read session_handover.md"
  GIT_BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  GIT_COMMIT="unknown"
  COMPACT_COUNT="1"
fi

# ── Emit re-injection content (stdout → Claude's context) ───────────────────
cat <<INJECT

════════════════════════════════════════════════════════
 CONTEXT RESTORED AFTER COMPACTION #$COMPACT_COUNT
════════════════════════════════════════════════════════

Project : context-engineering-kit
Branch  : $GIT_BRANCH
Commit  : $GIT_COMMIT
Task    : $ACTIVE_TASK
Phase   : $PHASE
Next    : $NEXT_ACTION

⚡ Critical rules still apply:
  - Never commit directly to main
  - Never modify .env files
  - Use claude.cmd on Windows no-admin machines

📋 Full task state is in session_handover.md
   Read it before continuing work.

Commands available:
  /token-status   → context usage
  /handover       → full task state
  /compact-smart  → relevance-scored compaction
  /session-sync   → sync state to git

════════════════════════════════════════════════════════
INJECT

log "Post-compact context injection complete"
exit 0
