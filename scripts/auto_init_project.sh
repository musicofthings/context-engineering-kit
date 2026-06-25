#!/usr/bin/env bash
# scripts/auto_init_project.sh
#
# Called by the plugin's SessionStart hook when auto_activate_new_repos is true.
# Bootstraps context-kit in any project that doesn't already have it.
# Safe to run repeatedly — skips projects that are already initialised.
#
# Detection: a project is considered "uninitialised" if it has no
# .claude/session/state.json AND no session_handover.md at PROJECT_DIR root.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SETTINGS_FILE="$PLUGIN_ROOT/config/plugin_settings.json"
# shellcheck source=find_python.sh
source "$PLUGIN_ROOT/scripts/find_python.sh"

log() { echo "[auto-init] $*" >&2; }

# ── Read plugin settings ──────────────────────────────────────────────────────
AUTO_ACTIVATE="true"
if [ -f "$SETTINGS_FILE" ]; then
  AUTO_ACTIVATE=$(jq -r '.auto_activate_new_repos // true' "$SETTINGS_FILE" 2>/dev/null || echo "true")
fi

[ "$AUTO_ACTIVATE" = "true" ] || exit 0

# ── Check skip list ───────────────────────────────────────────────────────────
if [ -f "$SETTINGS_FILE" ]; then
  SKIP=$(jq -r --arg p "$PROJECT_DIR" '.skip_repos // [] | map(. == $p) | any' "$SETTINGS_FILE" 2>/dev/null || echo "false")
  [ "$SKIP" = "true" ] && exit 0
fi

# ── Check if already initialised ─────────────────────────────────────────────
STATE_FILE="$PROJECT_DIR/.claude/session/state.json"
HANDOVER_FILE="$PROJECT_DIR/session_handover.md"

if [ -f "$STATE_FILE" ] || [ -f "$HANDOVER_FILE" ]; then
  exit 0   # already initialised — nothing to do
fi

# ── Skip non-git directories (optional safety guard) ─────────────────────────
if ! git -C "$PROJECT_DIR" rev-parse --git-dir &>/dev/null 2>&1; then
  log "Not a git repo — skipping auto-init for $PROJECT_DIR"
  exit 0
fi

log "New project detected: $PROJECT_DIR"
log "Bootstrapping context-kit..."

# ── Create session directory ──────────────────────────────────────────────────
mkdir -p "$PROJECT_DIR/.claude/session"

# ── Write initial state.json ──────────────────────────────────────────────────
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
REPO_NAME=$(basename "$PROJECT_DIR")
HOSTNAME_VAL=$(hostname 2>/dev/null || echo "unknown")

jq -n \
  --arg ts "$TIMESTAMP" \
  --arg branch "$GIT_BRANCH" \
  --arg repo "$REPO_NAME" \
  --arg host "$HOSTNAME_VAL" \
  '{
    last_updated: $ts,
    initialized_by: "auto-init",
    active_task: "project start",
    phase: "Phase 0 — Init",
    next_action: "run /context-health to verify setup",
    compact_count: 0,
    session_start_time: $ts,
    git_branch: $branch,
    repo: $repo,
    saved_by: $host
  }' > "$STATE_FILE"

# ── Generate initial session_handover.md ─────────────────────────────────────
if "$PYTHON" "$PLUGIN_ROOT/scripts/generate_session_handover.py" --trigger init --output "$HANDOVER_FILE" 2>/dev/null; then
  log "session_handover.md created"
else
  # Minimal fallback if Python unavailable
  cat > "$HANDOVER_FILE" <<HANDOVER
# Session Handover — $REPO_NAME
_Auto-initialised by context-engineering-kit plugin at $TIMESTAMP_

## 🎯 Active Task
Project start — context-kit just bootstrapped this project.

## ✅ Completed This Session
- context-kit plugin auto-initialised

## 📋 Remaining
- Run \`/context-health\` to verify full setup
- Add project-specific context to CLAUDE.md if needed

## 🔧 Environment
- Branch: $GIT_BRANCH
- Init time: $TIMESTAMP
HANDOVER
  log "Minimal session_handover.md written (Python unavailable)"
fi

# ── Emit context injection notice ─────────────────────────────────────────────
echo ""
echo "🔧 [context-kit] Auto-initialised for: $REPO_NAME"
echo "   session_handover.md and state.json created. Run /context-health to verify."
echo ""

log "Auto-init complete for $PROJECT_DIR"
exit 0
