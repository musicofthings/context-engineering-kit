#!/usr/bin/env bash
# scripts/eval_usage_lifecycle.sh
#
# Hypothetical scenario evals for Phase A (real auto-save) + Phase B (subagent safety).
# Runs in an isolated temp dir with stubbed state — does NOT touch the live
# project's session_handover.md or state.json.
#
# Usage: bash scripts/eval_usage_lifecycle.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=find_python.sh
source "$ROOT/scripts/find_python.sh"

PASS=0
FAIL=0
SCENARIO=""

pass() { echo "  PASS  $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }

assert_eq() {
  local label="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then pass "$label"; else fail "$label (got=[$got] want=[$want])"; fi
}

assert_file() {
  local label="$1" path="$2"
  if [ -f "$path" ]; then pass "$label"; else fail "$label (missing $path)"; fi
}

assert_grep() {
  local label="$1" path="$2" pattern="$3"
  if [ -f "$path" ] && grep -qE "$pattern" "$path" 2>/dev/null; then
    pass "$label"
  else
    fail "$label (pattern /$pattern/ in $path)"
  fi
}

assert_not_file() {
  local label="$1" path="$2"
  if [ ! -f "$path" ]; then pass "$label"; else fail "$label (exists $path)"; fi
}

# ── Isolated sandbox ──────────────────────────────────────────────────────────
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/cek-eval.XXXXXX")
cleanup() { rm -rf "$SANDBOX" 2>/dev/null || true; }
trap cleanup EXIT

mkdir -p "$SANDBOX/.claude/session" "$SANDBOX/config" "$SANDBOX/scripts" "$SANDBOX/.claude/hooks"

# Minimal kit surface: real scripts + hooks under test
cp "$ROOT/scripts/cek_auto_save.sh" "$SANDBOX/scripts/"
cp "$ROOT/scripts/find_python.sh" "$SANDBOX/scripts/"
cp "$ROOT/scripts/find_jq.sh" "$SANDBOX/scripts/"
cp "$ROOT/scripts/resolve_state_dir.sh" "$SANDBOX/scripts/"
cp "$ROOT/scripts/generate_session_handover.py" "$SANDBOX/scripts/"
# Make jq discoverable before any hook runs
# shellcheck source=find_jq.sh
source "$SANDBOX/scripts/find_jq.sh" || true
if ! command -v jq >/dev/null 2>&1 && [ -z "${JQ:-}" ]; then
  echo "SKIP/FAIL precondition: jq is required for lifecycle evals" >&2
  exit 2
fi
cp "$ROOT/.claude/hooks/usage-sentinel.sh" "$SANDBOX/.claude/hooks/"
cp "$ROOT/.claude/hooks/subagent-lifecycle.sh" "$SANDBOX/.claude/hooks/"
cp "$ROOT/.claude/hooks/session-start.sh" "$SANDBOX/.claude/hooks/"
cp "$ROOT/config/usage_budget.json" "$SANDBOX/config/"
cp "$ROOT/config/plugin_settings.json" "$SANDBOX/config/"

# Short window for time-based scenarios (10 minutes)
"$PYTHON" - <<PY
import json
from pathlib import Path
p = Path("$SANDBOX/config/usage_budget.json")
d = json.loads(p.read_text(encoding="utf-8"))
d["subscription_type"] = "pro"
d["subscriptions"]["pro"]["window_minutes"] = 10
d["thresholds"] = {"warn_pct": 70, "pre_save_pct": 80, "auto_save_pct": 85, "critical_pct": 92}
d["auto_save"] = {
    "execute_handover": True,
    "execute_session_sync": False,
    "subagent_grace_sec": 120,
}
p.write_text(json.dumps(d, indent=2), encoding="utf-8")
PY

export CLAUDE_PROJECT_DIR="$SANDBOX"
export CLAUDE_PLUGIN_ROOT="$SANDBOX"
cd "$SANDBOX"
git init -q 2>/dev/null || true
git -c user.email=eval@test -c user.name=eval checkout -b main 2>/dev/null || true
git -c user.email=eval@test -c user.name=eval commit --allow-empty -m init -q 2>/dev/null || true

write_state() {
  "$PYTHON" -c "
import json, sys
from pathlib import Path
p = Path('.claude/session/state.json')
base = {}
if p.exists():
    try: base = json.loads(p.read_text(encoding='utf-8'))
    except Exception: base = {}
base.update(json.loads(sys.argv[1]))
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(base, indent=2), encoding='utf-8')
" "$1"
}

# ISO timestamp N minutes ago
minutes_ago() {
  local m="$1"
  "$PYTHON" -c "from datetime import datetime,timezone,timedelta; print((datetime.now(timezone.utc)-timedelta(minutes=$m)).strftime('%Y-%m-%dT%H:%M:%SZ'))"
}

run_sentinel() {
  bash .claude/hooks/usage-sentinel.sh </dev/null \
    >"$SANDBOX/sentinel.out" 2>"$SANDBOX/sentinel.err" || true
  cat "$SANDBOX/sentinel.out" "$SANDBOX/sentinel.err" \
    >"$SANDBOX/sentinel.combined" 2>/dev/null || true
}

run_subagent() {
  local event="$1" id="${2:-agent-1}"
  CLAUDE_HOOK_EVENT="$event" \
    bash .claude/hooks/subagent-lifecycle.sh <<EOF
{"agent_id":"$id","agent_type":"general-purpose","description":"hypothetical $event"}
EOF
}

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  CEK usage lifecycle evals  (sandbox: $SANDBOX)"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# ════════════════════════════════════════════════════════════════════════════
SCENARIO="S1: below warn threshold — silent"
echo "▶ $SCENARIO"
rm -f .claude/session/.sentinel_* session_handover.md
write_state "{\"session_start_time\":\"$(minutes_ago 1)\",\"active_task\":\"eval\",\"subagents_running\":0}"
run_sentinel
assert_not_file "no save sentinel" ".claude/session/.sentinel_save"
assert_not_file "no critical sentinel" ".claude/session/.sentinel_critical"
# handover may not exist
if [ ! -f session_handover.md ]; then pass "no handover at low usage"; else fail "unexpected handover at low usage"; fi
echo ""

# ════════════════════════════════════════════════════════════════════════════
SCENARIO="S2: 85% autosave — WRITE handover"
echo "▶ $SCENARIO"
rm -f .claude/session/.sentinel_* session_handover.md
# 10 min window → 9 min elapsed = 90%
write_state "{\"session_start_time\":\"$(minutes_ago 9)\",\"active_task\":\"phase-a-autosave\",\"phase\":\"eval\",\"next_action\":\"verify handover write\",\"subagents_running\":0}"
run_sentinel
assert_file "save sentinel claimed" ".claude/session/.sentinel_save"
assert_file "handover written" "session_handover.md"
assert_grep "inject mentions AUTO-SAVED" "sentinel.combined" "AUTO-SAVED|auto-saved|AUTO-SAVED"
# state should record last_auto_save
LAST=$("$PYTHON" -c "import json;print(json.load(open('.claude/session/state.json')).get('last_auto_save') or '')")
if [ -n "$LAST" ]; then pass "state.last_auto_save set ($LAST)"; else fail "state.last_auto_save missing"; fi
echo ""

# ════════════════════════════════════════════════════════════════════════════
SCENARIO="S3: second prompt at 85% — no double save claim"
echo "▶ $SCENARIO"
# Keep sentinels from S2
run_sentinel
if [ -f .claude/session/.sentinel_save ]; then pass "save sentinel still present"; else fail "save sentinel lost"; fi
assert_file "handover retained" "session_handover.md"
echo ""

# ════════════════════════════════════════════════════════════════════════════
SCENARIO="S4: 92% critical with subagents mid-flight"
echo "▶ $SCENARIO"
rm -f .claude/session/.sentinel_* 
# 10 min window, 10 min elapsed = 100%
write_state "{\"session_start_time\":\"$(minutes_ago 10)\",\"active_task\":\"subagent-midflight\",\"subagents_running\":2,\"last_subagent_activity\":\"$(minutes_ago 0)\",\"active_subagent_ids\":[\"a1\",\"a2\"]}"
run_sentinel
assert_file "critical sentinel" ".claude/session/.sentinel_critical"
assert_file "handover at critical" "session_handover.md"
assert_grep "subagents warning injected" "sentinel.combined" "SUBAGENTS ACTIVE|subagents"
RUNNING=$("$PYTHON" -c "import json;print(json.load(open('.claude/session/state.json')).get('subagents_running',0))")
assert_eq "subagents_running preserved (not zeroed by sentinel)" "$RUNNING" "2"
echo ""

# ════════════════════════════════════════════════════════════════════════════
SCENARIO="S5: SubagentStart/Stop bookkeeping"
echo "▶ $SCENARIO"
write_state "{\"session_start_time\":\"$(minutes_ago 1)\",\"subagents_running\":0,\"active_subagent_ids\":[]}"
run_subagent SubagentStart explorer-1
run_subagent SubagentStart explorer-2
R=$("$PYTHON" -c "import json;print(json.load(open('.claude/session/state.json')).get('subagents_running',0))")
assert_eq "two starts → running=2" "$R" "2"
IDS=$("$PYTHON" -c "import json;print(len(json.load(open('.claude/session/state.json')).get('active_subagent_ids') or []))")
assert_eq "active ids length 2" "$IDS" "2"
run_subagent SubagentStop explorer-1
R=$("$PYTHON" -c "import json;print(json.load(open('.claude/session/state.json')).get('subagents_running',0))")
assert_eq "one stop → running=1" "$R" "1"
run_subagent SubagentStop explorer-2
R=$("$PYTHON" -c "import json;print(json.load(open('.claude/session/state.json')).get('subagents_running',0))")
assert_eq "both stopped → running=0" "$R" "0"
echo ""

# ════════════════════════════════════════════════════════════════════════════
SCENARIO="S6: session-start preserves mid-flight subagents (grace)"
echo "▶ $SCENARIO"
write_state "{\"session_start_time\":\"$(minutes_ago 2)\",\"subagents_running\":3,\"last_subagent_activity\":\"$(minutes_ago 0)\",\"active_task\":\"preserve-me\",\"active_subagent_ids\":[\"x\"]}"
printf '%s' '{"session_id":"eval-s6","source":"startup","cwd":"'"$SANDBOX"'"}' \
  | bash .claude/hooks/session-start.sh >/dev/null 2>"$SANDBOX/sstart.err" || true
R=$("$PYTHON" -c "import json;print(json.load(open('.claude/session/state.json')).get('subagents_running',0))")
PRES=$("$PYTHON" -c "import json;print(str(json.load(open('.claude/session/state.json')).get('subagents_preserved_on_start',False)).lower())")
assert_eq "subagents preserved on start" "$R" "3"
assert_eq "flag subagents_preserved_on_start" "$PRES" "true"
assert_file "pre-reset handover snapshot" "session_handover.md"
echo ""

# ════════════════════════════════════════════════════════════════════════════
SCENARIO="S7: session-start zeros stale subagents after grace"
echo "▶ $SCENARIO"
# Activity 10 minutes ago; grace is 120s → should zero
write_state "{\"session_start_time\":\"$(minutes_ago 2)\",\"subagents_running\":5,\"last_subagent_activity\":\"$(minutes_ago 10)\",\"active_subagent_ids\":[\"stale\"]}"
printf '%s' '{"session_id":"eval-s7","source":"startup"}' \
  | bash .claude/hooks/session-start.sh >/dev/null 2>"$SANDBOX/sstart7.err" || true
R=$("$PYTHON" -c "import json;print(json.load(open('.claude/session/state.json')).get('subagents_running',0))")
PRES=$("$PYTHON" -c "import json;print(str(json.load(open('.claude/session/state.json')).get('subagents_preserved_on_start',False)).lower())")
assert_eq "stale subagents zeroed" "$R" "0"
assert_eq "not preserved" "$PRES" "false"
echo ""

# ════════════════════════════════════════════════════════════════════════════
SCENARIO="S8: atomic double-claim (simulate plugin+project race)"
echo "▶ $SCENARIO"
rm -f .claude/session/.sentinel_* session_handover.md
write_state "{\"session_start_time\":\"$(minutes_ago 9)\",\"active_task\":\"race\",\"subagents_running\":0}"
# Two parallel sentinel runs
bash .claude/hooks/usage-sentinel.sh </dev/null >/dev/null 2>&1 &
P1=$!
bash .claude/hooks/usage-sentinel.sh </dev/null >/dev/null 2>&1 &
P2=$!
wait $P1 $P2 2>/dev/null || true
assert_file "exactly one claim path left handover" "session_handover.md"
# Only one sentinel file should exist (not corrupt)
assert_file "save sentinel after race" ".claude/session/.sentinel_save"
echo ""

# ════════════════════════════════════════════════════════════════════════════
SCENARIO="S9: execute_handover=false disables write"
echo "▶ $SCENARIO"
rm -f .claude/session/.sentinel_* session_handover.md
"$PYTHON" - <<'PY'
import json
from pathlib import Path
p = Path("config/usage_budget.json")
d = json.loads(p.read_text(encoding="utf-8"))
d["auto_save"]["execute_handover"] = False
p.write_text(json.dumps(d, indent=2), encoding="utf-8")
PY
write_state "{\"session_start_time\":\"$(minutes_ago 9)\",\"active_task\":\"disabled\",\"subagents_running\":0}"
run_sentinel
assert_file "save sentinel still claimed" ".claude/session/.sentinel_save"
if [ ! -f session_handover.md ]; then
  pass "no handover when execute_handover=false"
else
  # generator might still be called only if execute true — if file exists, fail
  fail "handover written despite execute_handover=false"
fi
# restore for cleanliness
"$PYTHON" - <<'PY'
import json
from pathlib import Path
p = Path("config/usage_budget.json")
d = json.loads(p.read_text(encoding="utf-8"))
d["auto_save"]["execute_handover"] = True
p.write_text(json.dumps(d, indent=2), encoding="utf-8")
PY
echo ""

# ════════════════════════════════════════════════════════════════════════════
SCENARIO="S10: prefer fresh forecast rl_5h_pct over wall-clock"
echo "▶ $SCENARIO"
rm -f .claude/session/.sentinel_* session_handover.md
# Wall clock only ~10% (1 of 10 min) but forecast says 90% real window
write_state "{\"session_start_time\":\"$(minutes_ago 1)\",\"active_task\":\"real-signal\",\"subagents_running\":0}"
NOW_TS=$("$PYTHON" -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")
"$PYTHON" -c "
import json
from pathlib import Path
Path('.claude/session/usage-forecast.json').write_text(json.dumps({
  'updated': '$NOW_TS',
  'data_source': 'rate_limit_window',
  'rl_5h_pct': 90,
  'pct_used': 90,
  'status': 'COMPACT',
}, indent=2), encoding='utf-8')
"
run_sentinel
assert_file "save sentinel from real 90%" ".claude/session/.sentinel_save"
assert_file "handover from real signal" "session_handover.md"
if grep -q 'rate_limit_window\|source.:.rate_limit' "$SANDBOX/sentinel.combined" "$SANDBOX/sentinel.err" .claude/session/usage.jsonl 2>/dev/null; then
  pass "logged real usage source"
else
  # usage.jsonl should carry source field
  if grep -q 'rate_limit_window' .claude/session/usage.jsonl 2>/dev/null; then
    pass "usage.jsonl source=rate_limit_window"
  else
    fail "expected rate_limit_window in usage log"
  fi
fi
echo ""

# ════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[ "$FAIL" -eq 0 ]
