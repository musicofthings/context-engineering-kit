#!/usr/bin/env bash
# scripts/cek_auto_save.sh
#
# Shared auto-save helpers for usage-sentinel, session-start, and session-end.
# Source AFTER find_python.sh and resolve_state_dir.sh so $PYTHON, $STATE_*,
# $MAIN_ROOT, $PROJECT_DIR, and $PLUGIN_ROOT / CLAUDE_PLUGIN_ROOT are set.
#
# Public functions:
#   cek_auto_save_init          — load config defaults from usage_budget.json
#   cek_claim_sentinel <name>   — atomic once-per-window claim (0=ours, 1=skip)
#   cek_subagents_running       — integer count from state.json
#   cek_run_handover <trigger> [context_pct]
#   cek_maybe_session_sync      — optional git save if configured
#   cek_auto_save_at_threshold <level> <usage_pct> <usage_label>
#       level: warn | presave | autosave | critical
#
# Design (Phase A+B):
#   - 85%/92% EXECUTE handover (do not only inject text for the model)
#   - subagents_running > 0 still gets a real save + an inject warning
#   - session-start must not zero subagent counters without a prior snapshot
#     when children may still be mid-flight

# shellcheck disable=SC2034
: "${PROJECT_DIR:=${CLAUDE_PROJECT_DIR:-$(pwd)}}"
: "${PLUGIN_ROOT:=${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}}"
: "${MAIN_ROOT:=$PROJECT_DIR}"
: "${STATE_DIR:=$PROJECT_DIR/.claude/session}"
: "${STATE_FILE:=$STATE_DIR/state.json}"
: "${PYTHON:=python3}"

CEK_EXECUTE_HANDOVER=true
CEK_EXECUTE_SESSION_SYNC=false
CEK_SUBAGENT_GRACE_SEC=120

cek_auto_save_init() {
  local budget="${1:-$MAIN_ROOT/config/usage_budget.json}"
  local settings="${2:-$PLUGIN_ROOT/config/plugin_settings.json}"

  CEK_EXECUTE_HANDOVER=true
  CEK_EXECUTE_SESSION_SYNC=false
  CEK_SUBAGENT_GRACE_SEC=120

  # Normalize jq.exe output (CRLF) before case/arith comparisons
  _cek_norm() { printf '%s' "${1-}" | tr -d '\r\n' | tr -d '[:space:]'; }

  # 1) plugin_settings feature flag = default
  # 2) usage_budget.auto_save.* overrides (per-project tuning wins)
  # NOTE: jq's `//` treats `false` as missing — never use `// default` for booleans.
  if [ -f "$settings" ]; then
    local eh2
    eh2=$(_cek_norm "$(jq -r 'if (.features | has("auto_execute_handover")) then .features.auto_execute_handover else "null" end' "$settings" 2>/dev/null || echo null)")
    case "$eh2" in true|false) CEK_EXECUTE_HANDOVER=$eh2 ;; esac
  fi

  if [ -f "$budget" ]; then
    local eh es gr
    eh=$(_cek_norm "$(jq -r 'if (.auto_save | type == "object") and (.auto_save | has("execute_handover")) then .auto_save.execute_handover else "null" end' "$budget" 2>/dev/null || echo null)")
    es=$(_cek_norm "$(jq -r 'if (.auto_save | type == "object") and (.auto_save | has("execute_session_sync")) then .auto_save.execute_session_sync else "null" end' "$budget" 2>/dev/null || echo null)")
    gr=$(_cek_norm "$(jq -r 'if (.auto_save | type == "object") and (.auto_save | has("subagent_grace_sec")) then .auto_save.subagent_grace_sec else "null" end' "$budget" 2>/dev/null || echo null)")
    case "$eh" in true|false) CEK_EXECUTE_HANDOVER=$eh ;; esac
    case "$es" in true|false) CEK_EXECUTE_SESSION_SYNC=$es ;; esac
    case "$gr" in ''|null|*[!0-9]*) ;; *) CEK_SUBAGENT_GRACE_SEC=$gr ;; esac
  fi
}

# Atomic claim so plugin+project double-fire only runs save once.
# Returns 0 if THIS caller owns the threshold action; 1 if already claimed.
cek_claim_sentinel() {
  local name="$1"
  local f="${SENTINEL_DIR:-$STATE_DIR}/.sentinel_${name}"
  local d="${SENTINEL_DIR:-$STATE_DIR}/.sentinel_${name}.claim"
  mkdir -p "${SENTINEL_DIR:-$STATE_DIR}" 2>/dev/null || true

  if [ -f "$f" ]; then
    return 1
  fi

  # Prefer the shared state lock when available (sourced resolve_state_dir).
  if declare -f _state_acquire >/dev/null 2>&1; then
    if _state_acquire 2>/dev/null; then
      if [ -f "$f" ]; then
        _state_release 2>/dev/null || true
        return 1
      fi
      touch "$f" 2>/dev/null || true
      _state_release 2>/dev/null || true
      return 0
    fi
  fi

  # Fallback: mkdir spinlock
  if mkdir "$d" 2>/dev/null; then
    if [ -f "$f" ]; then
      rmdir "$d" 2>/dev/null || true
      return 1
    fi
    touch "$f" 2>/dev/null || true
    rmdir "$d" 2>/dev/null || true
    return 0
  fi
  return 1
}

cek_subagents_running() {
  if [ ! -f "$STATE_FILE" ]; then
    echo 0
    return
  fi
  local n
  n=$(jq -r '.subagents_running // 0' "$STATE_FILE" 2>/dev/null || echo 0)
  case "$n" in ''|*[!0-9]*) echo 0 ;; *) echo "$n" ;; esac
}

# True (0) if we should NOT zero subagents_running yet (grace / still active).
cek_subagents_still_active() {
  local running last now age
  running=$(cek_subagents_running)
  [ "$running" -gt 0 ] || return 1
  if [ ! -f "$STATE_FILE" ]; then
    return 0
  fi
  last=$(jq -r '.last_subagent_activity // .last_subagent_start // ""' "$STATE_FILE" 2>/dev/null || echo "")
  if [ -z "$last" ]; then
    return 0   # unknown age but count > 0 — preserve
  fi
  now=$(date +%s)
  if date -d "$last" +%s >/dev/null 2>&1; then
    age=$(( now - $(date -d "$last" +%s) ))
  elif [ -n "${PYTHON:-}" ] && command -v "$PYTHON" >/dev/null 2>&1; then
    age=$("$PYTHON" -c "from datetime import datetime; print(int(${now})-int(datetime.fromisoformat('${last}'.replace('Z','+00:00')).timestamp()))" 2>/dev/null || echo 0)
  else
    age=0
  fi
  case "$age" in ''|*[!0-9-]*) age=0 ;; esac
  # Negative clock skew → treat as active
  if [ "$age" -lt 0 ]; then age=0; fi
  if [ "$age" -lt "$CEK_SUBAGENT_GRACE_SEC" ]; then
    return 0
  fi
  return 1
}

cek_handover_path() {
  case "${STATE_SCOPE:-auto}" in
    local) echo "${REPO_ROOT:-$PROJECT_DIR}/session_handover.md" ;;
    *)     echo "$MAIN_ROOT/session_handover.md" ;;
  esac
}

# Write session_handover.md from current state. Always best-effort.
# Records last_auto_save_* fields on success.
cek_run_handover() {
  local trigger="${1:-usage-threshold}"
  local context_pct="${2:-unknown}"
  local out script rc=1
  out=$(cek_handover_path)
  script="${PLUGIN_ROOT}/scripts/generate_session_handover.py"
  [ -f "$script" ] || script="${PROJECT_DIR}/scripts/generate_session_handover.py"

  if [ ! -f "$script" ]; then
    echo "[cek_auto_save] WARNING: generate_session_handover.py not found" >&2
    return 1
  fi

  if [ -z "${PYTHON:-}" ] || ! command -v "$PYTHON" >/dev/null 2>&1; then
    echo "[cek_auto_save] WARNING: no Python 3 — cannot generate handover" >&2
    return 1
  fi

  mkdir -p "$(dirname "$out")" 2>/dev/null || true
  if CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PROJECT_DIR}" \
     CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}" \
     "$PYTHON" "$script" \
       --trigger "$trigger" \
       --context-pct "$context_pct" \
       --output "$out" \
       >/dev/null 2>&1; then
    rc=0
  else
    # Minimal fallback so something durable exists even if the generator fails
    cat > "$out" <<EOF
# Session Handover
_Auto-generated fallback by cek_auto_save at $(date -u +"%Y-%m-%dT%H:%M:%SZ")_
_Trigger: ${trigger} | Context: ${context_pct}_

## Active Task
See \`.claude/session/state.json\` — full generator failed; state.json is authoritative.

## Next action
Read session_handover.md and state.json; run /handover to regenerate fully.
EOF
    rc=0
    echo "[cek_auto_save] WARNING: generator failed — wrote minimal fallback handover" >&2
  fi

  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if declare -f state_write >/dev/null 2>&1; then
    state_write \
      '.last_auto_save = $ts
       | .last_auto_save_trigger = $tr
       | .last_auto_save_handover = $path
       | .next_action = (if (.next_action // "" | test("^(unknown|none|read session_handover|check session_handover)"))
           then "read session_handover.md (auto-saved)"
           else .next_action end)' \
      --arg ts "$ts" \
      --arg tr "$trigger" \
      --arg path "$out" \
      || true
  fi
  echo "[cek_auto_save] handover written → $out (trigger=$trigger)" >&2
  return $rc
}

cek_maybe_session_sync() {
  if [ "$CEK_EXECUTE_SESSION_SYNC" != "true" ]; then
    return 0
  fi
  local sync="${PLUGIN_ROOT}/scripts/session_sync.sh"
  [ -f "$sync" ] || sync="${PROJECT_DIR}/scripts/session_sync.sh"
  if [ ! -f "$sync" ]; then
    echo "[cek_auto_save] session_sync.sh missing — skip git save" >&2
    return 0
  fi
  # --save can take a few seconds; never fail the hook
  CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PROJECT_DIR}" \
  CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}" \
    bash "$sync" --save >/dev/null 2>&1 \
    || echo "[cek_auto_save] session_sync --save failed (non-fatal)" >&2
}

# Run the save side-effects for autosave/critical thresholds.
# Prints nothing to stdout (caller owns inject text).
cek_execute_save_pipeline() {
  local trigger="$1"
  local context_pct="${2:-unknown}"
  if [ "$CEK_EXECUTE_HANDOVER" = "true" ]; then
    cek_run_handover "$trigger" "$context_pct" || true
  fi
  cek_maybe_session_sync
}

# Snapshot before a window/session reset when subagents may still be running.
cek_pre_reset_snapshot_if_needed() {
  local reason="${1:-session-reset}"
  local running
  running=$(cek_subagents_running)
  if [ "$running" -gt 0 ] || cek_subagents_still_active; then
    echo "[cek_auto_save] pre-reset snapshot (subagents_running=$running, reason=$reason)" >&2
    cek_execute_save_pipeline "$reason" "unknown"
    return 0
  fi
  # Also snapshot if window is fully elapsed and we have never auto-saved
  if [ -f "$STATE_FILE" ]; then
    local last
    last=$(jq -r '.last_auto_save // ""' "$STATE_FILE" 2>/dev/null || echo "")
    if [ -z "$last" ]; then
      cek_execute_save_pipeline "$reason" "unknown" || true
    fi
  fi
  return 0
}
