#!/usr/bin/env bash
# .grok/hooks/run.sh — Grok Build adapter (Phase C)
# Portable entrypoint. Sets CEK_RUNTIME=grok and dispatches to .claude/hooks/.
#
# Grok also auto-loads .claude/settings.json when present — since v3.0.0 that
# file declares no hooks, so this adapter is the only Grok hook source.
set -uo pipefail

export CEK_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/cek_runtime.sh
source "$(cd "$CEK_ADAPTER_DIR/../.." && pwd)/scripts/cek_runtime.sh"
export CEK_RUNTIME="grok"

ACTION="${1:-}"
shift || true

INPUT=$(cat 2>/dev/null || true)

run_pipe() {
  local script="$1"
  printf '%s' "$INPUT" | cek_run_hook "$script" || true
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
