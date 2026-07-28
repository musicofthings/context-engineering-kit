#!/usr/bin/env bash
# .claude/hooks/usage-sentinel.sh
#
# UserPromptSubmit hook — fires before every user prompt is processed.
# Tracks time elapsed against the Pro/Max 5-hour window (or cost against API budget).
# At 85%/92%: EXECUTES handover (and optional session-sync) then injects a short notice.
# At 70%/80%: inject soft reminders only.
#
# Phase A: real save, not model-dependent /handover directives alone.
# Phase B: if subagents_running > 0, still save; inject a drain warning.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}"
# shellcheck source=../../scripts/find_python.sh
source "$PLUGIN_ROOT/scripts/find_python.sh"
PLUGIN_SETTINGS="$PLUGIN_ROOT/config/plugin_settings.json"

# Feature gate
if [ -f "$PLUGIN_SETTINGS" ]; then
  FEATURE_ON=$(jq -r '.features.usage_sentinel // true' "$PLUGIN_SETTINGS" 2>/dev/null || echo "true")
  [ "$FEATURE_ON" = "false" ] && exit 0
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
NOW=$(date +%s)

# shellcheck source=../../scripts/resolve_state_dir.sh
source "$PLUGIN_ROOT/scripts/resolve_state_dir.sh"
# shellcheck source=../../scripts/cek_auto_save.sh
source "$PLUGIN_ROOT/scripts/cek_auto_save.sh"

BUDGET_FILE="$MAIN_ROOT/config/usage_budget.json"
USAGE_LOG="$STATE_DIR/usage.jsonl"
SENTINEL_DIR="$STATE_DIR"

cek_auto_save_init "$BUDGET_FILE" "$PLUGIN_SETTINGS"

# ── Load budget config ────────────────────────────────────────────────────────
SUB_TYPE="pro"
WINDOW_MINUTES=300
DAILY_BUDGET_USD=10.0
WARN_PCT=70
PRE_SAVE_PCT=80
AUTO_SAVE_PCT=85
CRITICAL_PCT=92

# Strip CR/whitespace from jq.exe (Windows) output — otherwise $(( )) breaks.
_num() {
  local v
  v=$(printf '%s' "${1-}" | tr -d '\r\n' | tr -d '[:space:]')
  case "$v" in ''|*[!0-9.-]*) printf '%s' "${2:-0}" ;; *) printf '%s' "$v" ;; esac
}
_str() {
  printf '%s' "${1-}" | tr -d '\r'
}

if [ -f "$BUDGET_FILE" ]; then
  SUB_TYPE=$(_str "$(jq -r '.subscription_type // "pro"' "$BUDGET_FILE" 2>/dev/null || echo "pro")")
  WARN_PCT=$(_num "$(jq -r '.thresholds.warn_pct // 70' "$BUDGET_FILE" 2>/dev/null || echo 70)" 70)
  PRE_SAVE_PCT=$(_num "$(jq -r '.thresholds.pre_save_pct // 80' "$BUDGET_FILE" 2>/dev/null || echo 80)" 80)
  AUTO_SAVE_PCT=$(_num "$(jq -r '.thresholds.auto_save_pct // 85' "$BUDGET_FILE" 2>/dev/null || echo 85)" 85)
  CRITICAL_PCT=$(_num "$(jq -r '.thresholds.critical_pct // 92' "$BUDGET_FILE" 2>/dev/null || echo 92)" 92)

  if [ "$SUB_TYPE" = "api" ]; then
    DAILY_BUDGET_USD=$(_str "$(jq -r ".subscriptions.api.daily_budget_usd // 10.0" "$BUDGET_FILE" 2>/dev/null || echo "10.0")")
  else
    WINDOW_MINUTES=$(_num "$(jq -r ".subscriptions.${SUB_TYPE}.window_minutes // 300" "$BUDGET_FILE" 2>/dev/null || echo 300)" 300)
  fi
fi

# ── Load session start time ───────────────────────────────────────────────────
SESSION_START=""
SESSION_COST_USD="0"

if [ -f "$STATE_FILE" ]; then
  SESSION_START=$(_str "$(jq -r '.session_start_time // ""' "$STATE_FILE" 2>/dev/null || echo "")")
  SESSION_COST_USD=$(_str "$(jq -r '.session_cost_usd // "0"' "$STATE_FILE" 2>/dev/null || echo "0")")
fi

[ -z "$SESSION_START" ] && exit 0

# ── Calculate elapsed time (cross-platform) ───────────────────────────────────
parse_epoch() {
  local ts="$1"
  ts=$(printf '%s' "$ts" | tr -d '\r')
  if date -d "$ts" +%s &>/dev/null 2>&1; then
    date -d "$ts" +%s
  elif TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s &>/dev/null 2>&1; then
    TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s
  else
    "$PYTHON" -c "from datetime import datetime,timezone; print(int(datetime.fromisoformat('${ts}'.replace('Z','+00:00')).timestamp()))" 2>/dev/null || echo "0"
  fi
}

START_EPOCH=$(_num "$(parse_epoch "$SESSION_START")" 0)

if [ "$START_EPOCH" = "0" ] || [ -z "$START_EPOCH" ]; then
  echo "[usage-sentinel] Warning: could not parse session start time '$SESSION_START', skipping usage check." >&2
  exit 0
fi

ELAPSED_SEC=$(( NOW - START_EPOCH ))
# Guard negative clock skew
if [ "$ELAPSED_SEC" -lt 0 ]; then ELAPSED_SEC=0; fi
ELAPSED_MIN=$(( ELAPSED_SEC / 60 ))

# ── Compute usage percentage ──────────────────────────────────────────────────
# Prefer real rate-limit / forecast metrics (written by usage-tracker on Stop)
# when fresh; fall back to wall-clock session age (historical CEK behaviour).
USAGE_SOURCE="wall_clock"
FORECAST_FILE="$STATE_DIR/usage-forecast.json"
REAL_PCT=""
REAL_SRC=""

_forecast_age_ok() {
  # Accept forecast if updated within last 2 hours (7200s)
  local updated epoch_u age
  updated=$(_str "$(jq -r '.updated // empty' "$FORECAST_FILE" 2>/dev/null || true)")
  [ -z "$updated" ] && return 1
  epoch_u=$(_num "$(parse_epoch "$updated")" 0)
  [ "$epoch_u" = "0" ] && return 1
  age=$(( NOW - epoch_u ))
  [ "$age" -lt 0 ] && age=0
  [ "$age" -le 7200 ]
}

if [ -f "$FORECAST_FILE" ] && _forecast_age_ok; then
  # Prefer explicit 5h window %; else tracker composite pct_used
  REAL_PCT=$(_str "$(jq -r 'if .rl_5h_pct != null then .rl_5h_pct else .pct_used end' "$FORECAST_FILE" 2>/dev/null || true)")
  REAL_SRC=$(_str "$(jq -r '.data_source // "forecast"' "$FORECAST_FILE" 2>/dev/null || echo forecast)")
fi
# Also accept state.json mirror from usage-tracker
if [ -z "$REAL_PCT" ] || [ "$REAL_PCT" = "null" ]; then
  if [ -f "$STATE_FILE" ]; then
    REAL_PCT=$(_str "$(jq -r '.rl_5h_pct // .usage_pct // empty' "$STATE_FILE" 2>/dev/null || true)")
    REAL_SRC=$(_str "$(jq -r '.usage_source // "state"' "$STATE_FILE" 2>/dev/null || echo state)")
  fi
fi

# Coerce real pct (may be float like 34.2)
if [ -n "$REAL_PCT" ] && [ "$REAL_PCT" != "null" ]; then
  REAL_PCT=$("$PYTHON" -c "print(int(float('${REAL_PCT}')))" 2>/dev/null || echo "")
fi

if [ "$SUB_TYPE" = "api" ]; then
  WALL_PCT=$(_num "$("$PYTHON" -c "print(int(float('${SESSION_COST_USD}') / float('${DAILY_BUDGET_USD}') * 100))" 2>/dev/null || echo 0)" 0)
  WALL_LABEL="USD $(printf '%.2f' "$SESSION_COST_USD") / \$${DAILY_BUDGET_USD}"
  WALL_LIMIT="daily budget"
else
  WINDOW_MINUTES=$(_num "$WINDOW_MINUTES" 300)
  WINDOW_SEC=$(( WINDOW_MINUTES * 60 ))
  if [ "$WINDOW_SEC" -le 0 ]; then WINDOW_SEC=1; fi
  WALL_PCT=$(( ELAPSED_SEC * 100 / WINDOW_SEC ))
  REMAINING_MIN=$(( WINDOW_MINUTES - ELAPSED_MIN ))
  WALL_LABEL="${ELAPSED_MIN}/${WINDOW_MINUTES} min"
  WALL_LIMIT="${REMAINING_MIN} min remaining"
fi

if [ -n "$REAL_PCT" ] && [ "$REAL_PCT" != "null" ]; then
  USAGE_PCT=$(_num "$REAL_PCT" 0)
  USAGE_SOURCE="${REAL_SRC:-rate_limit_window}"
  USAGE_LABEL="${USAGE_PCT}% (${USAGE_SOURCE})"
  LIMIT_LABEL="subscription window"
else
  USAGE_PCT=$(_num "$WALL_PCT" 0)
  USAGE_SOURCE="wall_clock"
  USAGE_LABEL="${WALL_LABEL}"
  LIMIT_LABEL="${WALL_LIMIT}"
fi

USAGE_PCT=$(_num "$USAGE_PCT" 0)
if [ "$USAGE_PCT" -gt 100 ]; then USAGE_PCT=100; fi

# ── Log usage snapshot ────────────────────────────────────────────────────────
echo "{\"ts\":\"$TIMESTAMP\",\"pct\":$USAGE_PCT,\"source\":\"$USAGE_SOURCE\",\"elapsed_min\":$ELAPSED_MIN,\"sub\":\"$SUB_TYPE\",\"cost_usd\":\"$SESSION_COST_USD\"}" \
  >> "$USAGE_LOG" 2>/dev/null || true

SUBS_RUNNING=$(_num "$(cek_subagents_running)" 0)
SUBS_NOTE=""
if [ "$SUBS_RUNNING" -gt 0 ]; then
  SUBS_NOTE="
⚠ SUBAGENTS ACTIVE: ${SUBS_RUNNING} still running. State was auto-saved.
  Prefer finishing or cancelling subagents before heavy new work; do not assume
  children see this usage notice."
fi

HANDOVER_PATH=$(cek_handover_path)

# ── Threshold actions (highest first) ─────────────────────────────────────────
# Atomic claim prevents plugin+project double-fire from double-saving.

if [ "$USAGE_PCT" -ge "$CRITICAL_PCT" ]; then
  if cek_claim_sentinel critical; then
    cek_claim_sentinel save >/dev/null 2>&1 || true   # mark lower tiers claimed too
    cek_claim_sentinel presave >/dev/null 2>&1 || true
    cek_claim_sentinel warn >/dev/null 2>&1 || true
    cek_execute_save_pipeline "usage-critical-${USAGE_PCT}pct" "$USAGE_PCT"
    if [ "$CEK_EXECUTE_HANDOVER" = "true" ]; then
      SAVE_LINE="Context-engineering-kit AUTO-SAVED session_handover.md (${HANDOVER_PATH})."
    else
      SAVE_LINE="Auto-execute handover is OFF — run /handover then /session-sync save immediately."
    fi
    cat << INJECT

════════════════════════════════════════════════════════════════
 ⚠️  USAGE CRITICAL — ${USAGE_PCT}% of ${SUB_TYPE} limit (${USAGE_LABEL})
════════════════════════════════════════════════════════════════
${SAVE_LINE}
execute_handover=${CEK_EXECUTE_HANDOVER}  session_sync=${CEK_EXECUTE_SESSION_SYNC}
Usage: ${USAGE_PCT}% of the ${SUB_TYPE} window (${USAGE_LABEL}, ~${LIMIT_LABEL}).
Tell the user in one line about the usage state. If context is also full, prefer /compact-smart.
${SUBS_NOTE}
════════════════════════════════════════════════════════════════
INJECT
  fi

elif [ "$USAGE_PCT" -ge "$AUTO_SAVE_PCT" ]; then
  if cek_claim_sentinel save; then
    cek_claim_sentinel presave >/dev/null 2>&1 || true
    cek_claim_sentinel warn >/dev/null 2>&1 || true
    cek_execute_save_pipeline "usage-autosave-${USAGE_PCT}pct" "$USAGE_PCT"
    if [ "$CEK_EXECUTE_HANDOVER" = "true" ]; then
      SAVE_LINE="Context-engineering-kit wrote session_handover.md (${HANDOVER_PATH}). Mention \"State auto-saved.\" once."
    else
      SAVE_LINE="Auto-execute handover is OFF — please run /handover soon."
    fi
    cat << INJECT

╔══════════════════════════════════════════════════════════╗
 🟠 USAGE ${USAGE_PCT}% — ${USAGE_LABEL} (${SUB_TYPE})
╚══════════════════════════════════════════════════════════╝
${SAVE_LINE}
${SUBS_NOTE}
INJECT
  fi

elif [ "$USAGE_PCT" -ge "$PRE_SAVE_PCT" ]; then
  if cek_claim_sentinel presave; then
    # Soft reminder only — no full save yet (save at 85%)
    cat << INJECT

🟡 [usage-sentinel] ${USAGE_PCT}% of the ${SUB_TYPE} window is used (${USAGE_LABEL}).
   Auto-save of session_handover.md will run at ${AUTO_SAVE_PCT}%.
   If context is filling, /compact-smart is preferable to blind auto-compaction.
${SUBS_NOTE}
INJECT
  fi

elif [ "$USAGE_PCT" -ge "$WARN_PCT" ]; then
  if cek_claim_sentinel warn; then
    echo "🟡 [usage-sentinel] ${USAGE_PCT}% usage (${USAGE_LABEL}). Auto-save at ${AUTO_SAVE_PCT}%."
  fi
fi

exit 0
