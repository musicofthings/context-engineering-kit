#!/usr/bin/env bash
# .grok/hooks/run.sh — Grok Build adapter (Phase C)
# Portable entrypoint. Sets CEK_RUNTIME=grok and dispatches to .claude/hooks/.
#
# Grok also auto-loads .claude/settings.json when present — since v3.0.0 that
# file declares no hooks, so this adapter is the only Grok hook source.
set -uo pipefail

# Assign then export (SC2155): `export VAR="$(...)"` masks the command
# substitution's exit status behind export's own.
CEK_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CEK_ADAPTER_DIR
# shellcheck source=../../scripts/cek_runtime.sh
source "$(cd "$CEK_ADAPTER_DIR/../.." && pwd)/scripts/cek_runtime.sh"
export CEK_RUNTIME="grok"

ACTION="${1:-}"
shift || true

INPUT=$(cat 2>/dev/null || true)

# ── Payload normalisation (camelCase -> snake_case) ──────────────────────────
# Verified against docs.x.ai/build/features/hooks on 2026-09-13: Grok sends
# camelCase — hookEventName, sessionId, cwd, workspaceRoot, toolName, toolInput.
# The shared core under .claude/hooks/ reads the Claude snake_case names
# (.tool_input 7x, .transcript_path 6x, .file_path 6x, .session_id 5x, ...), so
# on Grok every one of those reads resolved to empty. guard-dangerous.sh in
# particular could not see the command it is supposed to inspect, which made it
# inert on Grok regardless of exit codes.
#
# Additive: the camelCase keys are left in place, snake_case aliases are added
# only where absent, so a future Grok that sends both keeps working.
normalize_payload() {
  command -v jq >/dev/null 2>&1 || { printf '%s' "$INPUT"; return 0; }
  printf '%s' "$INPUT" | jq -c '
    . as $in
    | .hook_event_name //= $in.hookEventName
    | .session_id      //= $in.sessionId
    | .tool_name       //= $in.toolName
    | .tool_input      //= $in.toolInput
    | .transcript_path //= $in.transcriptPath
    | .file_path       //= ($in.filePath // $in.toolInput.file_path // $in.toolInput.filePath)
    | .cwd             //= ($in.cwd // $in.workspaceRoot)
    | .last_assistant_message //= $in.lastAssistantMessage
    | .stop_reason     //= $in.stopReason
    | .reason          //= $in.reason
    | with_entries(select(.value != null))
  ' 2>/dev/null || printf '%s' "$INPUT"
}
INPUT=$(normalize_payload)

# PreToolUse is the ONLY blocking event on Grok, and it denies on exit 2. Every
# other event is passive and fails open. `|| true` on the whole dispatch turned
# that 2 into a 0, so guard-dangerous.sh could not deny anything here either.
run_pipe() {
  local script="$1" rc=0
  printf '%s' "$INPUT" | cek_run_hook "$script" || rc=$?
  if [ "$rc" -eq 2 ]; then
    exit 2
  fi
  if [ "$rc" -ne 0 ]; then
    echo "[grok-run] $script exited $rc (not a decision — failing open)" >&2
  fi
  return 0
}

case "$ACTION" in
  session-start)
    printf '%s' "$INPUT" | cek_run_hook session-start.sh || true
    cek_run_hook morning-brief-auto.sh </dev/null || true
    ;;
  stop)
    # Grok Stop can block agent exit — keep this fail-open and fast.
    printf '%s' "$INPUT" | cek_run_hook extract-state-on-stop.sh || true
    if [ -f "$CEK_SCRIPTS_DIR/find_python.sh" ]; then
      # shellcheck source=../../scripts/find_python.sh
      source "$CEK_SCRIPTS_DIR/find_python.sh"
      # usage-tracker reads the Stop event JSON from stdin and exits
      # immediately when it is empty — </dev/null made this a silent no-op.
      printf '%s' "$INPUT" | "$PYTHON" "$CEK_SCRIPTS_DIR/usage-tracker.py" || true
    fi
    printf '%s' "$INPUT" | cek_run_hook stop.sh || true
    ;;
  subagent-start)
    printf '%s' "$INPUT" | CLAUDE_HOOK_EVENT=SubagentStart cek_run_hook subagent-lifecycle.sh || true
    ;;
  subagent-stop)
    printf '%s' "$INPUT" | CLAUDE_HOOK_EVENT=SubagentStop cek_run_hook subagent-lifecycle.sh || true
    ;;
  hook)
    script="${1:-}"
    [ -n "$script" ] || exit 0
    # Skip events that Grok does not implement (defensive)
    case "$script" in
      auto-approve-permissions.sh)
        # Grok uses PermissionDenied, not PermissionRequest
        if ! cek_runtime_supports PermissionRequest; then
          echo "[grok-run] skip PermissionRequest hook on Grok" >&2
          exit 0
        fi
        ;;
      instructions-loaded.sh)
        if ! cek_runtime_supports InstructionsLoaded; then
          exit 0
        fi
        ;;
    esac
    run_pipe "$script"
    ;;
  *)
    echo "[grok-run] unknown action: $ACTION" >&2
    exit 0
    ;;
esac
exit 0
