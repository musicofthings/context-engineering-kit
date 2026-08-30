#!/usr/bin/env bash
# .claude/hooks/session-start.sh
# SessionStart hook — fires on fresh and resumed sessions.
# Records session start time, clears sentinel files, injects context.

set -euo pipefail
umask 0077

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Capture the SDK/CLI session identity from hook stdin ─────────────────────
# Claude Code passes {session_id, transcript_path, cwd, source} as JSON on
# stdin. Recording it lets the handover hand the user the exact `--resume <id>`
# and the transcript path. Only read when stdin is a pipe (hook context) so a
# manual terminal run doesn't block on cat.
HOOK_INPUT=""
if [ ! -t 0 ]; then HOOK_INPUT=$(cat 2>/dev/null || true); fi
SESSION_ID=$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")
TRANSCRIPT_PATH=$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
SESSION_CWD=$(printf '%s' "$HOOK_INPUT" | jq -r '.cwd // ""' 2>/dev/null || echo "")
SESSION_SOURCE=$(printf '%s' "$HOOK_INPUT" | jq -r '.source // "startup"' 2>/dev/null || echo "startup")

# ── Resolve state location (shared worktree-aware helper) ─────────────────────
# shellcheck source=../../scripts/resolve_state_dir.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"

# ── Python 3 resolver (python3 → python → py) ────────────────────────────────
# Used by _parse_epoch (Windows often has only `python`/`py`, not `python3`)
# and by the docs-refresh background job below. Source once here so both paths
# share the same interpreter.
# shellcheck source=../../scripts/find_python.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/find_python.sh" 2>/dev/null || PYTHON=""
# shellcheck source=../../scripts/cek_auto_save.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/cek_auto_save.sh" 2>/dev/null || true
if declare -f cek_auto_save_init >/dev/null 2>&1; then
  cek_auto_save_init "$MAIN_ROOT/config/usage_budget.json" \
    "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/config/plugin_settings.json"
fi

# Collapse a double fire when the kit is active as both plugin and opened repo.
hook_once session-start || exit 0

SENTINEL_DIR="$STATE_DIR"
BUDGET_FILE="$MAIN_ROOT/config/usage_budget.json"

mkdir -p "$SENTINEL_DIR"

TODAY=$(date -u +"%A %B %d %Y, %H:%M UTC")
GIT_BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
GIT_COMMIT=$(git -C "$PROJECT_DIR" log --oneline -1 2>/dev/null || echo "none")
GIT_DIRTY=$(git -C "$PROJECT_DIR" status --short 2>/dev/null | wc -l | tr -d ' ')

# ── Load budget/window config (also reused by the display block below) ────────
SUB_TYPE="pro"
WINDOW_MINUTES=300
if [ -f "$BUDGET_FILE" ]; then
  SUB_TYPE=$(jq -r '.subscription_type // "pro"' "$BUDGET_FILE" 2>/dev/null || echo "pro")
  WINDOW_MINUTES=$(jq -r ".subscriptions.${SUB_TYPE}.window_minutes // 300" "$BUDGET_FILE" 2>/dev/null || echo "300")
fi

# ── Decide session_start_time — keep the usage clock honest ──────────────────
# Resetting this on every SessionStart (fresh AND resumed) made usage-sentinel
# measure wall-clock since the last start, not the real rolling Pro/Max window —
# producing false "100% / CRITICAL" banners once elapsed exceeded the window.
#   • resume / compact  → never restart the clock (same window continues).
#   • startup / clear   → keep the existing window unless it has fully elapsed;
#                         only then start a fresh window from now.
# A brand-new project (no prior start time) always starts now.
_parse_epoch() {
  local ts="$1"
  if date -d "$ts" +%s >/dev/null 2>&1; then
    date -d "$ts" +%s
  elif TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s >/dev/null 2>&1; then
    TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s
  elif [ -n "${PYTHON:-}" ] && command -v "$PYTHON" >/dev/null 2>&1; then
    "$PYTHON" -c "from datetime import datetime; print(int(datetime.fromisoformat('${ts}'.replace('Z','+00:00')).timestamp()))" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

PREV_START=$(jq -r '.session_start_time // ""' "$STATE_FILE" 2>/dev/null || echo "")
NEW_START="$TIMESTAMP"
WINDOW_RESETTING=false
if [ -n "$PREV_START" ]; then
  case "$SESSION_SOURCE" in
    resume|compact)
      NEW_START="$PREV_START" ;;
    *)
      PREV_EPOCH=$(_parse_epoch "$PREV_START")
      NOW_EPOCH=$(date +%s)
      WINDOW_SEC=$(( WINDOW_MINUTES * 60 ))
      case "$PREV_EPOCH" in ''|*[!0-9]*) PREV_EPOCH=0 ;; esac
      if [ "$PREV_EPOCH" -gt 0 ] && [ "$(( NOW_EPOCH - PREV_EPOCH ))" -lt "$WINDOW_SEC" ]; then
        NEW_START="$PREV_START"   # window still active — keep its start
      else
        # Clock will reset — Phase B: snapshot before wiping usage window context
        WINDOW_RESETTING=true
      fi ;;
  esac
else
  # Brand-new project — treat as a fresh window for sentinel arming
  WINDOW_RESETTING=true
fi

# ── Clear usage sentinels only when the usage window actually resets ──────────
# Clearing on every SessionStart re-armed 85%/92% and re-ran auto-save on every
# resume/compact. Keep sentinels for the active window; re-arm only on reset.
if [ "$WINDOW_RESETTING" = true ]; then
  rm -f "$SENTINEL_DIR/.sentinel_warn" \
        "$SENTINEL_DIR/.sentinel_presave" \
        "$SENTINEL_DIR/.sentinel_save" \
        "$SENTINEL_DIR/.sentinel_critical" \
        "$SENTINEL_DIR/.sentinel_warn.claim" \
        "$SENTINEL_DIR/.sentinel_presave.claim" \
        "$SENTINEL_DIR/.sentinel_save.claim" \
        "$SENTINEL_DIR/.sentinel_critical.claim" 2>/dev/null || true
fi

# ── Phase B: never zero mid-flight subagents without a snapshot ──────────────
# subagents_running can lag if SubagentStop was lost; grace period preserves
# the count when last_subagent_activity is recent. On window reset always try
# an auto-save first so handover exists before the new clock starts.
PRESERVE_SUBS=false
if declare -f cek_subagents_still_active >/dev/null 2>&1; then
  if cek_subagents_still_active; then
    PRESERVE_SUBS=true
  fi
fi
if declare -f cek_pre_reset_snapshot_if_needed >/dev/null 2>&1; then
  if [ "$WINDOW_RESETTING" = true ] || [ "$PRESERVE_SUBS" = true ]; then
    cek_pre_reset_snapshot_if_needed "session-start-${SESSION_SOURCE}" || true
  fi
fi

# state_write treats a missing file as {}, so the // defaults below double as
# the bootstrap path for a brand-new project.
# Only force subagents_running=0 when not preserving mid-flight children.
if [ "$PRESERVE_SUBS" = true ]; then
  state_write \
    '.session_start_time = $start
     | .last_updated = $ts
     | (if $sid  != "" then .session_id = $sid else . end)
     | (if $tx   != "" then .transcript_path = $tx else . end)
     | (if $scwd != "" then .session_cwd = $scwd else . end)
     | .session_source = $ssrc
     | .active_task = (.active_task // "unknown")
     | .phase = (.phase // "unknown")
     | .next_action = (.next_action // "read session_handover.md")
     | .compact_count = (.compact_count // 0)
     | .session_cost_usd = (.session_cost_usd // "0")
     | .changed_files = (.changed_files // [])
     | .subagents_preserved_on_start = true' \
    --arg ts "$TIMESTAMP" \
    --arg start "$NEW_START" \
    --arg sid "$SESSION_ID" \
    --arg tx "$TRANSCRIPT_PATH" \
    --arg scwd "$SESSION_CWD" \
    --arg ssrc "$SESSION_SOURCE" || true
else
  state_write \
    '.subagents_running = 0
     | .active_subagent_ids = []
     | .subagents_preserved_on_start = false
     | .session_start_time = $start
     | .last_updated = $ts
     | (if $sid  != "" then .session_id = $sid else . end)
     | (if $tx   != "" then .transcript_path = $tx else . end)
     | (if $scwd != "" then .session_cwd = $scwd else . end)
     | .session_source = $ssrc
     | .active_task = (.active_task // "unknown")
     | .phase = (.phase // "unknown")
     | .next_action = (.next_action // "read session_handover.md")
     | .compact_count = (.compact_count // 0)
     | .session_cost_usd = (.session_cost_usd // "0")
     | .changed_files = (.changed_files // [])' \
    --arg ts "$TIMESTAMP" \
    --arg start "$NEW_START" \
    --arg sid "$SESSION_ID" \
    --arg tx "$TRANSCRIPT_PATH" \
    --arg scwd "$SESSION_CWD" \
    --arg ssrc "$SESSION_SOURCE" || true
fi

# ── Docs freshness sentinel ───────────────────────────────────────────────────
# Keep api_docs.md current so the model never codes against outdated API
# syntax. Missing or older than refresh_ttl_hours → re-fetch in the background.
# Never blocks session start; a failed fetch leaves the previous file in place
# (fetch_api_docs.py refuses to write HTML or all-failed output).
DOCS_STATUS="not configured (no config/api_sources.json)"
DOCS_CFG="$PROJECT_DIR/config/api_sources.json"
[ -f "$DOCS_CFG" ] || DOCS_CFG="${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/config/api_sources.json"
DOCS_FETCHER="${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/fetch_api_docs.py"
if [ -f "$DOCS_CFG" ] && [ -f "$DOCS_FETCHER" ]; then
  DOCS_TTL=$(jq -r '.refresh_ttl_hours // 24' "$DOCS_CFG" 2>/dev/null || echo 24)
  case "$DOCS_TTL" in ''|*[!0-9]*) DOCS_TTL=24 ;; esac
  DOCS_FILE="$PROJECT_DIR/api_docs.md"
  if [ ! -f "$DOCS_FILE" ] || [ -n "$(find "$DOCS_FILE" -mmin +"$(( DOCS_TTL * 60 ))" 2>/dev/null)" ]; then
    # $PYTHON resolved once at top of this script via find_python.sh
    if [ -n "${PYTHON:-}" ] && command -v "$PYTHON" >/dev/null 2>&1; then
      ( CLAUDE_PROJECT_DIR="$PROJECT_DIR" \
        CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}" \
        nohup "$PYTHON" "$DOCS_FETCHER" >> "$STATE_DIR/docs-refresh.log" 2>&1 & ) 2>/dev/null
      DOCS_STATUS="stale (>${DOCS_TTL}h) — background refresh started"
    else
      DOCS_STATUS="stale — no Python 3 on PATH, refresh skipped"
    fi
  else
    DOCS_STATUS="current (refreshed <${DOCS_TTL}h ago)"
  fi
fi

# ── Load state for display ────────────────────────────────────────────────────
ACTIVE_TASK=$(jq -r '.active_task // "none"' "$STATE_FILE" 2>/dev/null || echo "none")
PHASE=$(jq -r '.phase // "none"' "$STATE_FILE" 2>/dev/null || echo "none")
NEXT_ACTION=$(jq -r '.next_action // "none"' "$STATE_FILE" 2>/dev/null || echo "none")
LAST_UPDATED=$(jq -r '.last_updated // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
COMPACT_COUNT=$(jq -r '.compact_count // 0' "$STATE_FILE" 2>/dev/null || echo "0")
# SUB_TYPE / WINDOW_MINUTES were already loaded above for the window calc.

# Nearly every hook in this kit parses JSON with jq — without it the kit
# silently no-ops (state never updates, usage warnings never fire) and the
# dangerous-command guard runs blind. Say so loudly instead of degrading
# in silence.
JQ_WARNING=""
if ! command -v jq >/dev/null 2>&1; then
  JQ_WARNING="
⚠️  jq NOT FOUND — most context-kit hooks are inactive.
   Install it:  winget install jqlang.jq   (or choco/scoop/apt/brew)
"
fi

cat << INJECT

╔══════════════════════════════════════════════════════════╗
║  context-engineering-kit v2.7.0 — Session Started         ║
────────────────────────────────────────────────────────────
$JQ_WARNING
📅 Date/Time    : $TODAY
🌿 Branch       : $GIT_BRANCH$([ "$IN_WORKTREE" = true ] && echo " (worktree — state on main)")
📝 Commit       : $GIT_COMMIT
🔄 Dirty files  : $GIT_DIRTY
📦 Compactions  : $COMPACT_COUNT this project
⏱  Session start: $TIMESTAMP
📊 Plan         : $SUB_TYPE (${WINDOW_MINUTES}min window)
📚 API docs     : $DOCS_STATUS
🔑 Session      : ${SESSION_ID:-unknown} (${SESSION_SOURCE})$([ "$IN_WORKTREE" = true ] && echo " ⚠ worktree cwd — resume only from this dir")

── Last session ─────────────────────────────────────────────
Task   : $ACTIVE_TASK
Phase  : $PHASE
Next   : $NEXT_ACTION
Saved  : $LAST_UPDATED

── Usage thresholds (auto-save executes, not model-only) ────
70% → warning injected
80% → save reminder injected
85% → WRITE session_handover.md (+ optional session-sync)
92% → critical WRITE + urgent notice
Subagents mid-flight → count preserved (grace); snapshot before window reset

── Quick commands ────────────────────────────────────────────
/handover        Full task state + manual state.json update
/token-status    Context usage + daily usage report
/compact-smart   Relevance-scored compaction
/model-switch    Auto-select Haiku/Sonnet/Opus by task
/session-sync    Save state to git for other devices
/context-health  Full health check

Read session_handover.md before starting work.
────────────────────────────────────────────────────────────
INJECT

exit 0
