#!/usr/bin/env bash
# .claude/hooks/subagent-lifecycle.sh
# SubagentStart and SubagentStop — track running children for Phase B safety.
# usage-sentinel and session-start consult subagents_running + last activity
# so a usage/window reset does not silently zero mid-flight work without a snapshot.

set -euo pipefail

# Capture stdin BEFORE sourcing anything — git/jq/find helpers can accidentally
# consume the hook payload under some environments (WSL + Windows binaries).
INPUT=$(cat 2>/dev/null || true)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# shellcheck source=../../scripts/resolve_state_dir.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"
SUBAGENT_LOG="$STATE_DIR/subagents.jsonl"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOOK_EVENT="${CLAUDE_HOOK_EVENT:-SubagentStart}"

# Accept event from argv (Cursor adapter: on-subagent.sh SubagentStart)
if [ "${1:-}" = "SubagentStart" ] || [ "${1:-}" = "SubagentStop" ]; then
  HOOK_EVENT="$1"
fi
# Parse hook payload with Python when available. jq.exe (WinGet under WSL) cannot
# open Linux paths like /tmp/... and often ignores piped stdin, so file+jq is
# unreliable on mixed Windows/WSL setups.
# shellcheck source=../../scripts/find_python.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/find_python.sh" 2>/dev/null || PYTHON=""
AGENT_ID=""
AGENT_TYPE=""
DESCRIPTION=""
if [ -n "${PYTHON:-}" ] && command -v "$PYTHON" >/dev/null 2>&1; then
  # Tab-separated fields (no eval). Env carries JSON so jq.exe WSL path/stdin
  # issues never block subagent id tracking.
  _SA_FIELDS=$(
    CEK_HOOK_JSON="$INPUT" "$PYTHON" -c "import json,os
raw=os.environ.get('CEK_HOOK_JSON') or ''
try:
 d=json.loads(raw) if raw else {}
except Exception:
 d={}
if not isinstance(d,dict):
 d={}
def g(*keys):
 for k in keys:
  v=d.get(k)
  if v is not None and str(v).strip()!='':
   return str(v).replace(chr(9),' ').replace(chr(10),' ').replace(chr(13),' ')
 return ''
print(g('agent_id','subagent_id','id')+chr(9)+g('agent_type','subagent_type','type')+chr(9)+g('description','prompt')[:200])
" 2>/dev/null || true
  )
  AGENT_ID=$(printf '%s' "$_SA_FIELDS" | cut -f1 | tr -d '\r')
  AGENT_TYPE=$(printf '%s' "$_SA_FIELDS" | cut -f2 | tr -d '\r')
  DESCRIPTION=$(printf '%s' "$_SA_FIELDS" | cut -f3- | tr -d '\r')
  unset _SA_FIELDS
fi

jq -n \
  --arg ts "$TIMESTAMP" \
  --arg event "$HOOK_EVENT" \
  --arg id "$AGENT_ID" \
  --arg type "$AGENT_TYPE" \
  --arg desc "$DESCRIPTION" \
  '{"ts":$ts,"event":$event,"agent_id":$id,"agent_type":$type,"description":$desc}' \
  >> "$SUBAGENT_LOG" 2>/dev/null || true

# Collapse the plugin+repo double fire. Unlike the once-per-session hooks this
# must be keyed by event AND agent id — several subagents legitimately start
# within the same second, and a bare per-event guard would drop real starts.
# Without any guard, subagents_started and subagents_running both counted twice.
if declare -f hook_once >/dev/null 2>&1; then
  hook_once "subagent-${HOOK_EVENT}-${AGENT_ID:-noid}" 3 || exit 0
fi

if [ "$HOOK_EVENT" = "SubagentStart" ]; then
  # Avoid jq `unique` (behaviour differs across builds); append + de-dupe with index.
  state_write \
    '.subagents_started = ((.subagents_started // 0) + 1)
     | .subagents_running = ((.subagents_running // 0) + 1)
     | .last_subagent_activity = $ts
     | .last_subagent_start = $ts
     | .last_subagent_id = $id
     | .last_subagent_type = $type
     | .active_subagent_ids = (
         (.active_subagent_ids // []) as $cur
         | if ($id == "" or ($cur | index($id) != null)) then $cur
           else ($cur + [$id]) end
       )' \
    --arg ts "$TIMESTAMP" \
    --arg id "$AGENT_ID" \
    --arg type "$AGENT_TYPE" \
    || true

elif [ "$HOOK_EVENT" = "SubagentStop" ] || [ "$HOOK_EVENT" = "SubagentEnd" ]; then
  state_write \
    '.subagents_running = ([((.subagents_running // 1) - 1), 0] | max)
     | .last_subagent_activity = $ts
     | .last_subagent_stop = $ts
     | .active_subagent_ids = (
         if $id == "" then (.active_subagent_ids // [])
         else ((.active_subagent_ids // []) | map(select(. != $id))) end
       )
     | (if ((.subagents_running // 0) == 0) then .active_subagent_ids = [] else . end)' \
    --arg ts "$TIMESTAMP" \
    --arg id "$AGENT_ID" \
    || true
fi

exit 0
