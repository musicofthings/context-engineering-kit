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

# Collapse a double fire (plugin + opened repo) so we don't commit twice.
hook_once session-end || exit 0

# ── Phase A+B: force handover before exit if children active or never saved ─
# shellcheck source=../../scripts/find_python.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/find_python.sh" 2>/dev/null || PYTHON=""
# shellcheck source=../../scripts/cek_auto_save.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/cek_auto_save.sh" 2>/dev/null || true
if declare -f cek_auto_save_init >/dev/null 2>&1; then
  cek_auto_save_init "$MAIN_ROOT/config/usage_budget.json" \
    "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/config/plugin_settings.json"
  RUNNING=0
  if declare -f cek_subagents_running >/dev/null 2>&1; then
    RUNNING=$(cek_subagents_running)
  fi
  NEED_SAVE=false
  if [ "$RUNNING" -gt 0 ]; then
    NEED_SAVE=true
    log "subagents_running=$RUNNING at SessionEnd — forcing handover"
  elif [ -f "$STATE_FILE" ]; then
    LAST_SAVE=$(jq -r '.last_auto_save // ""' "$STATE_FILE" 2>/dev/null || echo "")
    # Always refresh handover on session end when execute_handover is on
    if [ "${CEK_EXECUTE_HANDOVER:-true}" = "true" ]; then
      NEED_SAVE=true
    fi
    [ -z "$LAST_SAVE" ] && NEED_SAVE=true
  else
    NEED_SAVE=true
  fi
  if [ "$NEED_SAVE" = true ] && declare -f cek_execute_save_pipeline >/dev/null 2>&1; then
    cek_execute_save_pipeline "session-end" "unknown" || log "auto-save at session-end failed (non-fatal)"
  fi
fi

if [ "$IN_WORKTREE" = true ]; then
  log "In linked worktree — sync mode depends on STATE_SCOPE=$STATE_SCOPE"
  mkdir -p "$MAIN_ROOT/.claude/session"
  if [ "$STATE_SCOPE" = "local" ]; then
    # Worktree was the authoritative source — push everything up to main so it
    # survives worktree deletion. This is the only scope where blanket cp -r
    # is correct: the worktree's session dir is the live one.
    log "scope=local — copying worktree session dir up to main"
    cp -r "$PROJECT_DIR/.claude/session/." "$MAIN_ROOT/.claude/session/" 2>/dev/null || true
    [ -f "$PROJECT_DIR/session_handover.md" ] \
      && cp "$PROJECT_DIR/session_handover.md" "$MAIN_ROOT/session_handover.md" 2>/dev/null || true
    [ -f "$PROJECT_DIR/CLAUDE.md" ] \
      && cp "$PROJECT_DIR/CLAUDE.md" "$MAIN_ROOT/CLAUDE.md" 2>/dev/null || true
  else
    # auto/main scope — state.json already lives at MAIN_ROOT (hooks wrote it
    # there). Blanket cp -r from PROJECT_DIR/.claude/session would clobber
    # fresh main state with whatever stray/stale files happen to be in the
    # worktree's dir. Only sync the loose top-level files that legitimately
    # may have been edited in the worktree, and only if they're newer.
    if [ -f "$PROJECT_DIR/session_handover.md" ] \
         && { [ ! -f "$MAIN_ROOT/session_handover.md" ] \
              || [ "$PROJECT_DIR/session_handover.md" -nt "$MAIN_ROOT/session_handover.md" ]; }; then
      cp "$PROJECT_DIR/session_handover.md" "$MAIN_ROOT/session_handover.md" 2>/dev/null || true
    fi
    if [ -f "$PROJECT_DIR/CLAUDE.md" ] \
         && { [ ! -f "$MAIN_ROOT/CLAUDE.md" ] \
              || [ "$PROJECT_DIR/CLAUDE.md" -nt "$MAIN_ROOT/CLAUDE.md" ]; }; then
      cp "$PROJECT_DIR/CLAUDE.md" "$MAIN_ROOT/CLAUDE.md" 2>/dev/null || true
    fi
  fi
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
      # -w 5: bounded wait so a crashed peer holding the lock can't hang
      # session-end forever (resolve_state_dir.sh uses the same timeout).
      (flock -w 5 -x 9 || exit 1; printf '%s\n' "$ENTRY" >> "$HISTORY_FILE") 9>"${HISTORY_FILE}.lock"
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
  SESSION_PATHS=()
  for p in .claude/session/state.json session_handover.md CLAUDE.md; do
    [ -f "$p" ] && SESSION_PATHS+=("$p")
  done

  ACTIVE_TASK="unknown"
  if [ -f "$STATE_FILE" ]; then
    ACTIVE_TASK=$(jq -r '.active_task // "session state"' "$STATE_FILE" 2>/dev/null || echo "session state")
  fi

  # --only: commit JUST these paths. A plain `git add` + `git commit` would
  # also sweep in whatever the user happened to have staged mid-task when the
  # session closed.
  [ "${#SESSION_PATHS[@]}" -gt 0 ] && git commit --only "${SESSION_PATHS[@]}" \
    -m "chore(context): save session state — $ACTIVE_TASK [$TIMESTAMP]" \
    --no-verify 2>/dev/null || log "git commit skipped (nothing to commit or not a git repo)"
else
  log "No session file changes — skipping git commit"
fi

log "Session end complete"
exit 0
