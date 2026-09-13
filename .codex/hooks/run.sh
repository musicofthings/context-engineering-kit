#!/usr/bin/env bash
# .codex/hooks/run.sh — Codex adapter (Phase C)
# Portable entrypoint: no machine-absolute paths. Sets CEK_RUNTIME=codex and
# dispatches to the single logic core under .claude/hooks/.
#
# Usage (from hooks.json):
#   bash .codex/hooks/run.sh session-start
#   bash .codex/hooks/run.sh stop
#   bash .codex/hooks/run.sh hook usage-sentinel.sh
#   bash .codex/hooks/run.sh subagent-start
set -uo pipefail

# Assign then export (SC2155): `export VAR="$(...)"` masks the command
# substitution's exit status behind export's own.
CEK_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CEK_ADAPTER_DIR
# shellcheck source=../../scripts/cek_runtime.sh
source "$(cd "$CEK_ADAPTER_DIR/../.." && pwd)/scripts/cek_runtime.sh"
export CEK_RUNTIME="codex"

ACTION="${1:-}"
shift || true

INPUT=$(cat 2>/dev/null || true)

# stdin is consumed once into $INPUT, so replay it for each hook in a chain.
pipe_hook() {
  printf '%s' "$INPUT" | cek_run_hook "$@"
}

# Run a hook while preserving its decision status.
#
# Codex reads exit code 2 as a decision — block on PreToolUse/PermissionRequest,
# feedback on PostToolUse, continue on Stop/SubagentStop — with the reason on
# stderr. The blanket `|| true` this replaces turned that 2 into a 0, which
# silently disarmed guard-dangerous.sh on Codex. Exit 2 is now propagated
# verbatim and ends the chain. Any other non-zero status is a broken hook, not
# a decision: log it and fail open so a bug in the kit cannot wedge a session.
preserve_decision() {
  local label="${2:-${1:-hook}}" rc=0
  "$@" || rc=$?
  if [ "$rc" -eq 2 ]; then
    exit 2
  fi
  if [ "$rc" -ne 0 ]; then
    echo "[codex-run] $label exited $rc (not a decision — failing open)" >&2
  fi
  return 0
}

run_pipe() {
  preserve_decision pipe_hook "$1"
}

case "$ACTION" in
  session-start)
    preserve_decision pipe_hook session-start.sh
    preserve_decision cek_run_hook morning-brief-auto.sh </dev/null
    ;;
  stop)
    preserve_decision pipe_hook extract-state-on-stop.sh
    if [ -f "$CEK_SCRIPTS_DIR/find_python.sh" ]; then
      # shellcheck source=../../scripts/find_python.sh
      source "$CEK_SCRIPTS_DIR/find_python.sh"
      # usage-tracker reads the Stop event JSON from stdin and exits
      # immediately when it is empty — </dev/null made this a silent no-op.
      printf '%s' "$INPUT" | "$PYTHON" "$CEK_SCRIPTS_DIR/usage-tracker.py" || true
    fi
    preserve_decision pipe_hook stop.sh
    ;;
  subagent-start)
    export CLAUDE_HOOK_EVENT=SubagentStart
    preserve_decision pipe_hook subagent-lifecycle.sh
    ;;
  subagent-stop)
    export CLAUDE_HOOK_EVENT=SubagentStop
    preserve_decision pipe_hook subagent-lifecycle.sh
    ;;
  hook)
    # bash .codex/hooks/run.sh hook guard-dangerous.sh
    script="${1:-}"
    if [ -z "$script" ]; then
      echo "[codex-run] missing hook script name" >&2
      exit 0
    fi
    run_pipe "$script"
    ;;
  *)
    echo "[codex-run] unknown action: $ACTION" >&2
    exit 0
    ;;
esac
exit 0
