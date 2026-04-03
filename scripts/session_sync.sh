#!/usr/bin/env bash
# scripts/session_sync.sh
# Save or load session state to/from git.
# Enables cross-device and cross-subscription continuity.
#
# Usage:
#   bash scripts/session_sync.sh --save    # commit state before switching device
#   bash scripts/session_sync.sh --load    # restore state after git pull
#   bash scripts/session_sync.sh --status  # show sync status

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_FILE="$PROJECT_DIR/.claude/session/state.json"
HISTORY_FILE="$PROJECT_DIR/.claude/session/history.jsonl"
HANDOVER_FILE="$PROJECT_DIR/session_handover.md"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOSTNAME_ID=$(hostname 2>/dev/null || echo "unknown-host")

log()  { echo "[session-sync] $*"; }
warn() { echo "[session-sync] ⚠️  $*" >&2; }

# ── Detect platform ──────────────────────────────────────────────────────────
PLATFORM="unknown"
case "$OSTYPE" in
  darwin*) PLATFORM="mac" ;;
  linux*)  PLATFORM="linux" ;;
  msys*|cygwin*|win*) PLATFORM="windows" ;;
esac

# ── SAVE ────────────────────────────────────────────────────────────────────
do_save() {
  log "Saving session state from $HOSTNAME_ID ($PLATFORM)..."

  mkdir -p "$PROJECT_DIR/.claude/session"

  # Update state with device info
  if [ -f "$STATE_FILE" ]; then
    jq --arg host "$HOSTNAME_ID" \
       --arg platform "$PLATFORM" \
       --arg ts "$TIMESTAMP" \
       '.saved_by = $host | .saved_platform = $platform | .last_save = $ts' \
       "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
  else
    cat > "$STATE_FILE" <<EOF
{
  "saved_by": "$HOSTNAME_ID",
  "saved_platform": "$PLATFORM",
  "last_save": "$TIMESTAMP",
  "active_task": "unknown",
  "phase": "unknown",
  "next_action": "read session_handover.md",
  "compact_count": 0
}
EOF
  fi

  cd "$PROJECT_DIR"

  # Stage session files
  git add .claude/session/state.json 2>/dev/null || true
  git add .claude/session/history.jsonl 2>/dev/null || true
  git add session_handover.md 2>/dev/null || true
  git add CLAUDE.md 2>/dev/null || true

  # Only commit if there are staged changes
  if git diff --cached --quiet 2>/dev/null; then
    log "Nothing changed — no commit needed"
  else
    ACTIVE_TASK=$(jq -r '.active_task // "session state"' "$STATE_FILE" 2>/dev/null || echo "session state")
    git commit -m "chore(context): sync from $HOSTNAME_ID — $ACTIVE_TASK [$TIMESTAMP]" --no-verify
    git push 2>/dev/null && log "Pushed to remote" || warn "Push failed — run 'git push' manually"
  fi

  log ""
  log "✅ Session saved from $HOSTNAME_ID"
  log ""
  log "On your other device:"
  log "  git pull"
  log "  bash scripts/session_sync.sh --load"
  log "  (then in Claude Code: /context-health)"
}

# ── LOAD ─────────────────────────────────────────────────────────────────────
do_load() {
  log "Loading session state on $HOSTNAME_ID ($PLATFORM)..."

  # Pull latest
  cd "$PROJECT_DIR"
  git pull 2>/dev/null && log "Git pull complete" || warn "Git pull failed — using local state"

  # Report what we found
  if [ -f "$STATE_FILE" ]; then
    SAVED_BY=$(jq -r '.saved_by // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
    SAVED_TS=$(jq -r '.last_save // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
    ACTIVE_TASK=$(jq -r '.active_task // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
    PHASE=$(jq -r '.phase // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
    NEXT_ACTION=$(jq -r '.next_action // "read session_handover.md"' "$STATE_FILE" 2>/dev/null || echo "read session_handover.md")
    COMPACT_COUNT=$(jq -r '.compact_count // 0' "$STATE_FILE" 2>/dev/null || echo "0")

    log ""
    log "╔══════════════════════════════════════╗"
    log "║  Session Restored                     ║"
    log "╚══════════════════════════════════════╝"
    log "Last saved by : $SAVED_BY"
    log "Saved at      : $SAVED_TS"
    log "Active task   : $ACTIVE_TASK"
    log "Phase         : $PHASE"
    log "Next action   : $NEXT_ACTION"
    log "Compact count : $COMPACT_COUNT"
    log ""
    log "✅ Run: claude (then /context-health to verify)"
  else
    warn "No state file found — starting fresh"
    log "Run: claude /context-health"
  fi
}

# ── STATUS ───────────────────────────────────────────────────────────────────
do_status() {
  log "Session sync status for $HOSTNAME_ID ($PLATFORM)"
  log ""

  if [ -f "$STATE_FILE" ]; then
    SAVED_BY=$(jq -r '.saved_by // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
    SAVED_TS=$(jq -r '.last_save // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
    ACTIVE_TASK=$(jq -r '.active_task // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
    log "State file    : ✅ exists"
    log "Last saved by : $SAVED_BY at $SAVED_TS"
    log "Active task   : $ACTIVE_TASK"
  else
    log "State file    : ❌ not found"
  fi

  cd "$PROJECT_DIR"
  GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "not a git repo")
  GIT_AHEAD=$(git rev-list --count origin/HEAD..HEAD 2>/dev/null || echo "?")
  log ""
  log "Git branch    : $GIT_BRANCH"
  log "Commits ahead : $GIT_AHEAD"

  UNCOMMITTED=$(git diff --name-only .claude/session/ session_handover.md CLAUDE.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "$UNCOMMITTED" -gt 0 ]; then
    log "Uncommitted   : ⚠️  $UNCOMMITTED context files have local changes"
    log "  → Run: bash scripts/session_sync.sh --save"
  else
    log "Uncommitted   : ✅ none"
  fi
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
MODE="${1:-}"
case "$MODE" in
  --save|-s)   do_save ;;
  --load|-l)   do_load ;;
  --status)    do_status ;;
  *)
    echo "Usage: bash scripts/session_sync.sh --save | --load | --status"
    exit 1
    ;;
esac
