#!/usr/bin/env bash
# .claude/hooks/usage-sentinel.sh
#
# UserPromptSubmit hook — fires before every user prompt is processed.
# Tracks time elapsed against the Pro/Max 5-hour window (or cost against API budget).
# Injects warnings and auto-save directives when thresholds are crossed.
# Writes usage metrics to .claude/session/usage.jsonl for trend tracking.
#
# How it works:
#   - Reads session start time from state.json (written by session-start.sh)
#   - Reads budget config from config/usage_budget.json
#   - Injects text into Claude's context via stdout (not a prompt block)
#   - At 80%: injects "run /handover soon" reminder
#   - At 85%: injects directive — Claude will execute save sequence before responding
#   - At 92%: injects urgent directive — Claude saves immediately then says it's near limit
#   - Uses sentinel files to avoid injecting the same message on every prompt

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_FILE="$PROJECT_DIR/.claude/session/state.json"
BUDGET_FILE="$PROJECT_DIR/config/usage_budget.json"
USAGE_LOG="$PROJECT_DIR/.claude/session/usage.jsonl"
SENTINEL_DIR="$PROJECT_DIR/.claude/session"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
NOW=$(date +%s)

mkdir -p "$SENTINEL_DIR"

# ── Load budget config ────────────────────────────────────────────────────────
SUB_TYPE="pro"
WINDOW_MINUTES=300
DAILY_BUDGET_USD=10.0
WARN_PCT=70
PRE_SAVE_PCT=80
AUTO_SAVE_PCT=85
CRITICAL_PCT=92

if [ -f "$BUDGET_FILE" ]; then
  SUB_TYPE=$(jq -r '.subscription_type // "pro"' "$BUDGET_FILE" 2>/dev/null || echo "pro")
  WARN_PCT=$(jq -r '.thresholds.warn_pct // 70' "$BUDGET_FILE" 2>/dev/null || echo "70")
  PRE_SAVE_PCT=$(jq -r '.thresholds.pre_save_pct // 80' "$BUDGET_FILE" 2>/dev/null || echo "80")
  AUTO_SAVE_PCT=$(jq -r '.thresholds.auto_save_pct // 85' "$BUDGET_FILE" 2>/dev/null || echo "85")
  CRITICAL_PCT=$(jq -r '.thresholds.critical_pct // 92' "$BUDGET_FILE" 2>/dev/null || echo "92")

  if [ "$SUB_TYPE" = "api" ]; then
    DAILY_BUDGET_USD=$(jq -r ".subscriptions.api.daily_budget_usd // 10.0" "$BUDGET_FILE" 2>/dev/null || echo "10.0")
  else
    WINDOW_MINUTES=$(jq -r ".subscriptions.${SUB_TYPE}.window_minutes // 300" "$BUDGET_FILE" 2>/dev/null || echo "300")
  fi
fi

# ── Load session start time ───────────────────────────────────────────────────
SESSION_START=""
SESSION_COST_USD="0"

if [ -f "$STATE_FILE" ]; then
  SESSION_START=$(jq -r '.session_start_time // ""' "$STATE_FILE" 2>/dev/null || echo "")
  SESSION_COST_USD=$(jq -r '.session_cost_usd // "0"' "$STATE_FILE" 2>/dev/null || echo "0")
fi

[ -z "$SESSION_START" ] && exit 0   # No start time recorded yet — skip

# ── Calculate elapsed time (cross-platform) ───────────────────────────────────
# macOS: date -j -f format; Linux: date -d; Windows Git Bash: use python3
parse_epoch() {
  local ts="$1"
  if date -d "$ts" +%s &>/dev/null 2>&1; then
    date -d "$ts" +%s          # GNU/Linux
  elif date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s &>/dev/null 2>&1; then
    date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s   # macOS
  else
    python3 -c "from datetime import datetime,timezone; print(int(datetime.fromisoformat('${ts}'.replace('Z','+00:00')).timestamp()))" 2>/dev/null || echo "0"
  fi
}

START_EPOCH=$(parse_epoch "$SESSION_START")

# If all parse methods failed, epoch is "0" which would make elapsed = NOW (~1.7B sec)
# and immediately trigger a false critical alert — exit cleanly instead
if [ "$START_EPOCH" = "0" ] || [ -z "$START_EPOCH" ]; then
  echo "[usage-sentinel] Warning: could not parse session start time '$SESSION_START', skipping usage check." >&2
  exit 0
fi

ELAPSED_SEC=$(( NOW - START_EPOCH ))
ELAPSED_MIN=$(( ELAPSED_SEC / 60 ))

# ── Compute usage percentage ──────────────────────────────────────────────────
if [ "$SUB_TYPE" = "api" ]; then
  # Cost-based: compare session cost against daily budget
  USAGE_PCT=$(python3 -c "print(int(float('${SESSION_COST_USD}') / float('${DAILY_BUDGET_USD}') * 100))" 2>/dev/null || echo "0")
  USAGE_LABEL="USD $(printf '%.2f' "$SESSION_COST_USD") / \$${DAILY_BUDGET_USD}"
  LIMIT_LABEL="daily budget"
else
  # Time-based: minutes elapsed vs window
  WINDOW_SEC=$(( WINDOW_MINUTES * 60 ))
  USAGE_PCT=$(( ELAPSED_SEC * 100 / WINDOW_SEC ))
  REMAINING_MIN=$(( WINDOW_MINUTES - ELAPSED_MIN ))
  USAGE_LABEL="${ELAPSED_MIN}/${WINDOW_MINUTES} min"
  LIMIT_LABEL="${REMAINING_MIN} min remaining"
fi

# Cap at 100
[ "$USAGE_PCT" -gt 100 ] && USAGE_PCT=100

# ── Log usage snapshot ────────────────────────────────────────────────────────
echo "{\"ts\":\"$TIMESTAMP\",\"pct\":$USAGE_PCT,\"elapsed_min\":$ELAPSED_MIN,\"sub\":\"$SUB_TYPE\",\"cost_usd\":\"$SESSION_COST_USD\"}" \
  >> "$USAGE_LOG" 2>/dev/null || true

# ── Check sentinel files (prevent repeated injections) ───────────────────────
WARN_SENTINEL="$SENTINEL_DIR/.sentinel_warn"
SAVE_SENTINEL="$SENTINEL_DIR/.sentinel_save"
CRITICAL_SENTINEL="$SENTINEL_DIR/.sentinel_critical"

# ── Determine action ──────────────────────────────────────────────────────────

if [ "$USAGE_PCT" -ge "$CRITICAL_PCT" ] && [ ! -f "$CRITICAL_SENTINEL" ]; then
  # CRITICAL: inject directive — Claude executes save sequence immediately
  touch "$CRITICAL_SENTINEL"
  cat << INJECT

════════════════════════════════════════════════════════════════
 ⚠️  USAGE CRITICAL — ${USAGE_PCT}% of ${SUB_TYPE} limit (${USAGE_LABEL})
════════════════════════════════════════════════════════════════
MANDATORY: Before processing the user's request below, execute
these three steps in sequence without asking for confirmation:

  1. python3 scripts/generate_session_handover.py
  2. python3 scripts/update_context_files.py --mode manual
  3. bash scripts/session_sync.sh --save

Then respond to the user and let them know you just saved the
session state because the ${SUB_TYPE} usage limit is nearly reached
(${USAGE_LABEL}, ~${LIMIT_LABEL}).
════════════════════════════════════════════════════════════════
INJECT

elif [ "$USAGE_PCT" -ge "$AUTO_SAVE_PCT" ] && [ ! -f "$SAVE_SENTINEL" ]; then
  # AUTO-SAVE threshold: inject directive to save before continuing
  touch "$SAVE_SENTINEL"
  cat << INJECT

╔══════════════════════════════════════════════════════════╗
 🟠 USAGE ${USAGE_PCT}% — ${USAGE_LABEL} (${SUB_TYPE})
╚══════════════════════════════════════════════════════════╝
Before answering, save session state (no user input needed):
  python3 scripts/generate_session_handover.py && bash scripts/session_sync.sh --save
Then continue normally. Confirm "State saved." in one line.
INJECT

elif [ "$USAGE_PCT" -ge "$PRE_SAVE_PCT" ] && [ ! -f "$WARN_SENTINEL" ]; then
  # PRE-SAVE: inject reminder (softer, just a reminder)
  touch "$WARN_SENTINEL"
  cat << INJECT

🟡 [usage-sentinel] ${USAGE_PCT}% of ${SUB_TYPE} limit used (${USAGE_LABEL}).
   Run /handover + /session-sync save soon to preserve state before the window resets.
INJECT

elif [ "$USAGE_PCT" -ge "$WARN_PCT" ] && [ ! -f "$WARN_SENTINEL" ]; then
  # WARN: note only, no directive
  touch "$WARN_SENTINEL"
  echo "🟡 [usage-sentinel] ${USAGE_PCT}% usage (${USAGE_LABEL}). Consider /handover + /session-sync save."
fi

exit 0
