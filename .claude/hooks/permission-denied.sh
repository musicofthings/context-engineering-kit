#!/usr/bin/env bash
# .claude/hooks/permission-denied.sh
#
# Grok fires PermissionDenied when the permission system blocks a tool call.
# Observability-only — the deny already happened. Logs for handover/debug.
# Claude Code uses PermissionRequest (pre-decision) via auto-approve-permissions.sh.

set -euo pipefail

# Capture stdin before sourcing helpers
INPUT=$(cat 2>/dev/null || true)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# shellcheck source=../../scripts/resolve_state_dir.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"
# shellcheck source=../../scripts/find_python.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/find_python.sh" 2>/dev/null || PYTHON=""

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
FAILURE_LOG="$STATE_DIR/tool-failures.jsonl"
TOOL="unknown"
REASON=""

if [ -n "${PYTHON:-}" ] && command -v "$PYTHON" >/dev/null 2>&1 && [ -n "$INPUT" ]; then
  _PD_FIELDS=$(
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
   return str(v).replace(chr(9),' ').replace(chr(10),' ').replace(chr(13),' ')[:200]
 return ''
print(g('tool_name','tool','name')+chr(9)+g('reason','error','message','permission'))
" 2>/dev/null || true
  )
  TOOL=$(printf '%s' "$_PD_FIELDS" | cut -f1 | tr -d '\r')
  REASON=$(printf '%s' "$_PD_FIELDS" | cut -f2- | tr -d '\r')
  [ -z "$TOOL" ] && TOOL="unknown"
  unset _PD_FIELDS
fi

mkdir -p "$STATE_DIR" 2>/dev/null || true
jq -n \
  --arg ts "$TIMESTAMP" \
  --arg tool "$TOOL" \
  --arg error "permission_denied: $REASON" \
  --arg path "" \
  '{"ts":$ts,"tool":$tool,"error":$error,"path":$path,"event":"PermissionDenied"}' \
  >> "$FAILURE_LOG" 2>/dev/null || true

if declare -f state_write >/dev/null 2>&1; then
  state_write \
    '.last_tool_failure = {"ts": $ts, "tool": $tool, "error": $err}
     | .permission_denials = ((.permission_denials // 0) + 1)' \
    --arg ts "$TIMESTAMP" \
    --arg tool "$TOOL" \
    --arg err "permission_denied: $REASON" \
    || true
fi

echo "[permission-denied] tool=$TOOL reason=${REASON:-n/a}" >&2
exit 0
