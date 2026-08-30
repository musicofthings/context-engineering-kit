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

export CEK_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/cek_runtime.sh
source "$(cd "$CEK_ADAPTER_DIR/../.." && pwd)/scripts/cek_runtime.sh"
export CEK_RUNTIME="codex"

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
