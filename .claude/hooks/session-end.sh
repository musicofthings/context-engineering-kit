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

# ── Worktree detection — always commit session state on main checkout ─────────
# Worktrees are ephemeral; committing to a worktree branch loses state when
# the worktree is deleted. Redirect all writes to the main checkout instead.
GIT_DIR=$(git -C "$PROJECT_DIR" rev-parse --git-dir 2>/dev/null || echo "")
if echo "$GIT_DIR" | grep -q '/worktrees/'; then
  MAIN_ROOT=$(git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null \
    | awk 'NR==1{sub(/^worktree /,""); print; exit}')
  if [ -n "$MAIN_ROOT" ]; then
    log "In linked worktree — redirecting session state to main checkout: $MAIN_ROOT"
    # Sync session files from worktree into main repo before committing
    mkdir -p "$MAIN_ROOT/.claude/session"
    cp -r "$PROJECT_DIR/.claude/session/." "$MAIN_ROOT/.claude/session/" 2>/dev/null || true
    [ -f "$PROJECT_DIR/session_handover.md" ] \
      && cp "$PROJECT_DIR/session_handover.md" "$MAIN_ROOT/session_handover.md" 2>/dev/null || true
    COMMIT_DIR="$MAIN_ROOT"
  else
    log "Could not find main worktree root — skipping session-end commit"
    exit 0
  fi
else
  COMMIT_DIR="$PROJECT_DIR"
fi

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
