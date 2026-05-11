#!/usr/bin/env bash
# .claude/hooks/session-start.sh
# SessionStart hook — fires on fresh and resumed sessions.
# Records session start time, clears sentinel files, injects context.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Worktree detection — always read/write state on main checkout ─────────────
# Worktrees are ephemeral; session state must persist on main, not on the
# short-lived worktree branch that will be deleted after the task is done.
GIT_DIR=$(git -C "$PROJECT_DIR" rev-parse --git-dir 2>/dev/null || echo "")
if echo "$GIT_DIR" | grep -q '/worktrees/'; then
  MAIN_ROOT=$(git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null \
    | awk 'NR==1{sub(/^worktree /,""); print}')
  [ -z "$MAIN_ROOT" ] && MAIN_ROOT="$PROJECT_DIR"
  IN_WORKTREE=true
else
  MAIN_ROOT="$PROJECT_DIR"
  IN_WORKTREE=false
fi

STATE_FILE="$MAIN_ROOT/.claude/session/state.json"
SENTINEL_DIR="$MAIN_ROOT/.claude/session"
BUDGET_FILE="$MAIN_ROOT/config/usage_budget.json"

mkdir -p "$SENTINEL_DIR"

TODAY=$(date -u +"%A %B %d %Y, %H:%M UTC")
GIT_BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
GIT_COMMIT=$(git -C "$PROJECT_DIR" log --oneline -1 2>/dev/null || echo "none")
GIT_DIRTY=$(git -C "$PROJECT_DIR" status --short 2>/dev/null | wc -l | tr -d ' ')

# ── Clear usage sentinel files on new session ─────────────────────────────────
# These gate injection of warnings — reset them each session so warnings
# fire fresh even if you left off at a high-usage state last time.
rm -f "$SENTINEL_DIR/.sentinel_warn" \
      "$SENTINEL_DIR/.sentinel_save" \
      "$SENTINEL_DIR/.sentinel_critical" 2>/dev/null || true

# ── Reset subagent counter ───────────────────────────────────────────────────
# subagents_running drifts upward across crashes — reset to 0 on session start
# so the count reflects this session only.
if [ -f "$STATE_FILE" ]; then
  STATE_TMP=$(mktemp "${STATE_FILE}.XXXXXX")
  jq '.subagents_running = 0' "$STATE_FILE" > "$STATE_TMP" 2>/dev/null \
    && mv "$STATE_TMP" "$STATE_FILE" \
    || rm -f "$STATE_TMP"
fi

# ── Record session start time in state.json ──────────────────────────────────
# usage-sentinel.sh reads this to compute elapsed time against the budget window.
# Always overwrite — SessionStart fires on new sessions only, not compact resumes.
if [ -f "$STATE_FILE" ]; then
  STATE_TMP=$(mktemp "${STATE_FILE}.XXXXXX")
  jq --arg ts "$TIMESTAMP" '.session_start_time = $ts' "$STATE_FILE" > "$STATE_TMP" \
    && mv "$STATE_TMP" "$STATE_FILE" 2>/dev/null || rm -f "$STATE_TMP"
else
  cat > "$STATE_FILE" << STATEOF
{
  "session_start_time": "$TIMESTAMP",
  "last_updated": "$TIMESTAMP",
  "active_task": "unknown",
  "phase": "unknown",
  "next_action": "read session_handover.md",
  "compact_count": 0,
  "session_cost_usd": "0",
  "changed_files": []
}
STATEOF
fi

# ── Load state for display ────────────────────────────────────────────────────
ACTIVE_TASK=$(jq -r '.active_task // "none"' "$STATE_FILE" 2>/dev/null || echo "none")
PHASE=$(jq -r '.phase // "none"' "$STATE_FILE" 2>/dev/null || echo "none")
NEXT_ACTION=$(jq -r '.next_action // "none"' "$STATE_FILE" 2>/dev/null || echo "none")
LAST_UPDATED=$(jq -r '.last_updated // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
COMPACT_COUNT=$(jq -r '.compact_count // 0' "$STATE_FILE" 2>/dev/null || echo "0")

# Load budget config for display
SUB_TYPE="pro"
WINDOW_MINUTES=300
if [ -f "$BUDGET_FILE" ]; then
  SUB_TYPE=$(jq -r '.subscription_type // "pro"' "$BUDGET_FILE" 2>/dev/null || echo "pro")
  WINDOW_MINUTES=$(jq -r ".subscriptions.${SUB_TYPE}.window_minutes // 300" "$BUDGET_FILE" 2>/dev/null || echo "300")
fi

cat << INJECT

╔══════════════════════════════════════════════════════════╗
║  context-engineering-kit v2.4.1 — Session Started         ║
╚══════════════════════════════════════════════════════════╝

📅 Date/Time    : $TODAY
🌿 Branch       : $GIT_BRANCH$([ "$IN_WORKTREE" = true ] && echo " (worktree — state on main)")
📝 Commit       : $GIT_COMMIT
🔄 Dirty files  : $GIT_DIRTY
📦 Compactions  : $COMPACT_COUNT this project
⏱  Session start: $TIMESTAMP
📊 Plan         : $SUB_TYPE (${WINDOW_MINUTES}min window)

── Last session ─────────────────────────────────────────────
Task   : $ACTIVE_TASK
Phase  : $PHASE
Next   : $NEXT_ACTION
Saved  : $LAST_UPDATED

── Usage thresholds (auto-save fires automatically) ─────────
70% → warning injected into context
80% → save reminder injected
85% → auto-save directive (Claude saves before responding)
92% → critical directive (Claude saves immediately)

── Quick commands ────────────────────────────────────────────
/handover        Full task state + manual state.json update
/token-status    Context usage + daily usage report
/compact-smart   Relevance-scored compaction
/model-switch    Auto-select Haiku/Sonnet/Opus by task
/session-sync    Save state to git for other devices
/context-health  Full health check

Read session_handover.md before starting work.
╚══════════════════════════════════════════════════════════╝
INJECT

exit 0
