#!/usr/bin/env bash
# .claude/hooks/permission-denied.sh
#
# PermissionDenied fires after a tool call has already been denied.
# Observability-only — the deny already happened. Logs for handover/debug.
#
# Both Claude Code and Grok emit it, and the payloads agree on the two fields
# this hook reads: Claude sends {tool_name, tool_input, tool_use_id, reason}
# (verified against the hooks reference 2026-09-17), Grok sends the camelCase
# equivalents which .grok/hooks/run.sh normalises. Claude Code additionally
# uses PermissionRequest as the PRE-decision event — that is a separate hook,
# auto-approve-permissions.sh.
#
# Claude Code's PermissionDenied accepts hookSpecificOutput.retry:true to tell
# the model it may retry the denied call. Deliberately not used: a context
# preservation kit has no basis for second-guessing a permission decision, and
# the retry prompt would fire on every denial in auto mode.

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

# state_append() honours the containment guard; a bare `mkdir -p` + `>>` here
# did not, and recreated the directory resolve_state_dir.sh had just rm -rf'd
# for being $HOME or Claude Code's own config dir. Running the appenders
# back-to-back hid it — the next hook's containment cleanup deleted this one's
# leak — so it only showed up when this hook ran alone.
state_append "$FAILURE_LOG" "$(jq -nc \
  --arg ts "$TIMESTAMP" \
  --arg tool "$TOOL" \
  --arg error "permission_denied: $REASON" \
  --arg path "" \
  '{"ts":$ts,"tool":$tool,"error":$error,"path":$path,"event":"PermissionDenied"}' \
  2>/dev/null)" || true

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
