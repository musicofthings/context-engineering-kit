#!/usr/bin/env bash
# .agents/hooks/run.sh — Antigravity CLI / IDE adapter (Phase 3)
# Portable entrypoint: no machine-absolute paths. Sets CEK_RUNTIME=antigravity
# and dispatches to the single logic core under .claude/hooks/.
#
# Antigravity emits 5 events only: PreToolUse, PostToolUse, PreInvocation,
# PostInvocation, Stop. It omits session/compaction events and passes camelCase
# payloads with nested PascalCase tool arguments.
#
# Handlers return JSON contracts on stdout:
# - PreToolUse: {"decision": "allow" | "deny", "reason": "..."}
# - PostToolUse: {}
# - PreInvocation: {"injectSteps": [{"ephemeralMessage": "..."}]}
# - Stop: {}
set -uo pipefail

CEK_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CEK_ADAPTER_DIR
# shellcheck source=../../scripts/cek_runtime.sh
source "$(cd "$CEK_ADAPTER_DIR/../.." && pwd)/scripts/cek_runtime.sh"
# shellcheck source=../../scripts/find_python.sh
source "$CEK_SCRIPTS_DIR/find_python.sh"
export CEK_RUNTIME="antigravity"

ACTION="${1:-}"
shift || true

RAW_INPUT=$(cat 2>/dev/null || true)

# ── Payload normalisation (Antigravity camelCase + toolCall -> snake_case) ───
normalize_payload() {
  if [ -z "$RAW_INPUT" ]; then
    printf '{}'
    return 0
  fi
  "$PYTHON" -c '
import json, sys

try:
    data = json.load(sys.stdin)
except Exception:
    data = {}

if not isinstance(data, dict):
    data = {}

tool_call = data.get("toolCall", {}) if isinstance(data.get("toolCall"), dict) else {}
raw_name = tool_call.get("name", "")
args = tool_call.get("args", {}) if isinstance(tool_call.get("args"), dict) else {}

name_map = {
    "run_command": "Bash",
    "write_to_file": "Write",
    "replace_file_content": "Edit",
    "view_file": "Read",
}
tool_name = name_map.get(raw_name, raw_name or data.get("tool_name", ""))

tool_input = dict(data.get("tool_input", {})) if isinstance(data.get("tool_input"), dict) else {}
if "CommandLine" in args:
    tool_input["command"] = args["CommandLine"]
if "TargetFile" in args:
    tool_input["file_path"] = args["TargetFile"]
if "AbsolutePath" in args:
    tool_input["file_path"] = args["AbsolutePath"]
if "DirectoryPath" in args:
    tool_input["directory_path"] = args["DirectoryPath"]
for k, v in args.items():
    if k not in ("CommandLine", "TargetFile", "AbsolutePath", "DirectoryPath"):
        tool_input[k] = v

norm = dict(data)
norm["session_id"] = data.get("conversationId") or data.get("session_id")
norm["conversation_id"] = norm["session_id"]
ws = data.get("workspacePaths", [])
if ws and isinstance(ws, list) and len(ws) > 0:
    norm["cwd"] = ws[0]
    norm["workspace_root"] = ws[0]
norm["transcript_path"] = data.get("transcriptPath") or data.get("transcript_path")
norm["artifact_dir"] = data.get("artifactDirectoryPath") or data.get("artifact_dir")
norm["tool_name"] = tool_name
norm["tool_input"] = tool_input
norm["file_path"] = tool_input.get("file_path") or data.get("filePath")
norm["invocation_num"] = data.get("invocationNum", data.get("invocation_num"))
norm["step_idx"] = data.get("stepIdx", data.get("step_idx"))
norm["fully_idle"] = data.get("fullyIdle", data.get("fully_idle"))
norm["stop_reason"] = data.get("terminationReason", data.get("stop_reason"))

print(json.dumps(norm))
' <<< "$RAW_INPUT" 2>/dev/null || printf '%s' "$RAW_INPUT"
}

NORM_INPUT=$(normalize_payload)

# If workspacePaths is present in payload, resolve CLAUDE_PROJECT_DIR to the target project
PAYLOAD_WS=$("$PYTHON" -c "import json,sys; print(json.loads(sys.argv[1]).get('workspace_root', ''))" "$NORM_INPUT" 2>/dev/null || true)
if [ -n "$PAYLOAD_WS" ] && [ -d "$PAYLOAD_WS" ]; then
  export CLAUDE_PROJECT_DIR="$PAYLOAD_WS"
fi

# ── Handlers ─────────────────────────────────────────────────────────────────

# PreInvocation: synthesize SessionStart when invocationNum == 0,
# or run usage-sentinel on subsequent turns. Inject output via injectSteps.
handle_pre_invocation() {
  local inv_num banner=""
  inv_num=$("$PYTHON" -c "import json,sys; print(json.loads(sys.argv[1]).get('invocation_num', 0))" "$NORM_INPUT" 2>/dev/null || echo "0")
  if [ "$inv_num" -eq 0 ]; then
    banner=$(printf '%s' "$NORM_INPUT" | cek_run_hook session-start.sh 2>&1 || true)
    cek_run_hook morning-brief-auto.sh </dev/null >/dev/null 2>&1 || true
  else
    banner=$(printf '%s' "$NORM_INPUT" | cek_run_hook usage-sentinel.sh 2>&1 || true)
  fi

  "$PYTHON" -c '
import json, sys
msg = sys.argv[1].strip()
if msg:
    print(json.dumps({"injectSteps": [{"ephemeralMessage": msg}]}))
else:
    print(json.dumps({"injectSteps": []}))
' "$banner"
}

# Stop: extract state, record tokens, run stop chain. Allow stop.
handle_stop() {
  printf '%s' "$NORM_INPUT" | cek_run_hook extract-state-on-stop.sh >/dev/null 2>&1 || true
  if [ -f "$CEK_SCRIPTS_DIR/find_python.sh" ]; then
    # shellcheck source=../../scripts/find_python.sh
    source "$CEK_SCRIPTS_DIR/find_python.sh"
    printf '%s' "$NORM_INPUT" | "$PYTHON" "$CEK_SCRIPTS_DIR/usage-tracker.py" >/dev/null 2>&1 || true
  fi
  printf '%s' "$NORM_INPUT" | cek_run_hook stop.sh >/dev/null 2>&1 || true
  echo "{}"
}

# PreToolUse: guard-dangerous. Exit 2 -> {"decision": "deny", "reason": ...}
# Exit 0 -> {"decision": "allow"}.
handle_pre_tool_use() {
  local script="$1" rc=0 err_out=""
  err_out=$(printf '%s' "$NORM_INPUT" | cek_run_hook "$script" 2>&1) || rc=$?
  if [ "$rc" -eq 2 ]; then
    "$PYTHON" -c '
import json, sys
reason = sys.argv[1].strip() or "Command blocked by security guard"
print(json.dumps({"decision": "deny", "reason": reason}))
' "$err_out"
    return 0
  fi
  if [ "$rc" -ne 0 ]; then
    echo "[antigravity-run] $script exited $rc (failing open)" >&2
  fi
  echo '{"decision": "allow"}'
  return 0
}

# PostToolUse: track-changes or failure log. Expects empty JSON {}.
handle_post_tool_use() {
  local script="$1"
  printf '%s' "$NORM_INPUT" | cek_run_hook "$script" >/dev/null 2>&1 || true
  echo "{}"
  return 0
}

case "$ACTION" in
  pre-invocation)
    handle_pre_invocation
    ;;
  stop)
    handle_stop
    ;;
  hook)
    script="${1:-}"
    if [ -z "$script" ]; then
      echo "[antigravity-run] missing hook script name" >&2
      echo "{}"
      exit 0
    fi
    case "$script" in
      guard-dangerous.sh)
        handle_pre_tool_use "$script"
        ;;
      track-changes.sh|post-tool-failure.sh)
        handle_post_tool_use "$script"
        ;;
      *)
        printf '%s' "$NORM_INPUT" | cek_run_hook "$script" >/dev/null 2>&1 || true
        echo "{}"
        ;;
    esac
    ;;
  *)
    echo "[antigravity-run] unknown action: $ACTION" >&2
    echo "{}"
    ;;
esac
exit 0
