#!/usr/bin/env bash
# .claude/hooks/session-end.sh
# Fires on SessionEnd — when the Claude Code session closes.
# Commits session state to git so it's available on other devices/subscriptions.

set -euo pipefail
umask 0077

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

log() { echo "[session-end] $*" >&2; }

log "Session ending at $TIMESTAMP"

# ── Resolve state location (shared worktree-aware helper) ─────────────────────
# Worktrees are ephemeral; committing to a worktree branch loses state when
# the worktree is deleted. Redirect all writes to the main checkout instead.
# shellcheck source=../../scripts/resolve_state_dir.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"

if [ "$IN_WORKTREE" = true ]; then
  log "In linked worktree — redirecting session state to main checkout: $MAIN_ROOT"
  # Sync session files from worktree into main repo before committing.
  # CLAUDE.md must be copied too — worktree edits to it are otherwise lost.
  mkdir -p "$MAIN_ROOT/.claude/session"
  cp -r "$PROJECT_DIR/.claude/session/." "$MAIN_ROOT/.claude/session/" 2>/dev/null || true
  [ -f "$PROJECT_DIR/session_handover.md" ] \
    && cp "$PROJECT_DIR/session_handover.md" "$MAIN_ROOT/session_handover.md" 2>/dev/null || true
  [ -f "$PROJECT_DIR/CLAUDE.md" ] \
    && cp "$PROJECT_DIR/CLAUDE.md" "$MAIN_ROOT/CLAUDE.md" 2>/dev/null || true
fi
COMMIT_DIR="$MAIN_ROOT"

STATE_FILE="$COMMIT_DIR/.claude/session/state.json"
HISTORY_FILE="$COMMIT_DIR/.claude/session/history.jsonl"
HANDOVER_FILE="$COMMIT_DIR/session_handover.md"

# ── Append to history (atomic where flock available, best-effort otherwise) ──
if [ -f "$STATE_FILE" ]; then
  ENTRY=$(jq -c --arg ts "$TIMESTAMP" '. + {session_ended: $ts}' "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$ENTRY" ]; then
    if command -v flock &>/dev/null; then
      (flock -x 9; printf '%s\n' "$ENTRY" >> "$HISTORY_FILE") 9>"${HISTORY_FILE}.lock"
    else
      printf '%s\n' "$ENTRY" >> "$HISTORY_FILE"
    fi 2>/dev/null || true
  fi
fi

# ── Git commit session files ─────────────────────────────────────────────────
cd "$COMMIT_DIR"

# Check both staged and unstaged changes for session files before adding
CHANGED=$(git status --porcelain .claude/session/state.json session_handover.md CLAUDE.md 2>/dev/null || echo "")

if [ -n "$CHANGED" ]; then
  git add .claude/session/state.json \
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
