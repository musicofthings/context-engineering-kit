#!/usr/bin/env bash
# .opencode/hooks/run.sh — opencode adapter
#
# Portable entrypoint. Sets CEK_RUNTIME=opencode and dispatches into the single
# logic core under .claude/hooks/, exactly like the Codex and Grok adapters.
#
# opencode is the one runtime whose config is not a JSON hook file: plugins are
# JavaScript/TypeScript modules. .opencode/plugins/cek.ts is a thin translator
# that serialises each opencode event into the Claude-shaped snake_case JSON the
# core reads and invokes this script. All logic stays here and below; the TS
# file holds no policy.
#
# Usage (from cek.ts):
#   bash .opencode/hooks/run.sh session-start
#   bash .opencode/hooks/run.sh stop
#   bash .opencode/hooks/run.sh hook guard-dangerous.sh
set -uo pipefail

CEK_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CEK_ADAPTER_DIR
# shellcheck source=../../scripts/cek_runtime.sh
source "$(cd "$CEK_ADAPTER_DIR/../.." && pwd)/scripts/cek_runtime.sh"
export CEK_RUNTIME="opencode"

ACTION="${1:-}"
shift || true

INPUT=$(cat 2>/dev/null || true)

# stdin is consumed once into $INPUT, so replay it for each hook in a chain.
pipe_hook() {
  printf '%s' "$INPUT" | cek_run_hook "$@"
}

# opencode's tool.execute.before blocks by THROWING in JavaScript, not by an
# exit code. cek.ts turns exit 2 into a thrown Error, so the core's existing
# `exit 2 == deny` contract is preserved end to end. Propagate 2 verbatim and
# end the chain; any other non-zero status is a broken hook rather than a
# decision, so log it and fail open.
preserve_decision() {
  local label="${2:-${1:-hook}}" rc=0
  "$@" || rc=$?
  if [ "$rc" -eq 2 ]; then
    exit 2
  fi
  if [ "$rc" -ne 0 ]; then
    echo "[opencode-run] $label exited $rc (not a decision — failing open)" >&2
  fi
  return 0
}

case "$ACTION" in
  session-start)
    preserve_decision pipe_hook session-start.sh
    preserve_decision cek_run_hook morning-brief-auto.sh </dev/null
    ;;
  stop)
    # opencode has no UserPromptSubmit equivalent — its documented events cover
    # messages, tools and session lifecycle, but nothing fires between the user
    # submitting a prompt and the model seeing it. The usage sentinel therefore
    # runs at TURN END here rather than turn start, so the 85%/92% thresholds
    # are evaluated once per turn. The atomic sentinel claims make that safe to
    # run from a different point in the loop.
    preserve_decision pipe_hook extract-state-on-stop.sh
    if [ -f "$CEK_SCRIPTS_DIR/find_python.sh" ]; then
      # shellcheck source=../../scripts/find_python.sh
      source "$CEK_SCRIPTS_DIR/find_python.sh"
      printf '%s' "$INPUT" | "$PYTHON" "$CEK_SCRIPTS_DIR/usage-tracker.py" || true
    fi
    preserve_decision pipe_hook stop.sh
    preserve_decision pipe_hook usage-sentinel.sh
    ;;
  hook)
    script="${1:-}"
    if [ -z "$script" ]; then
      echo "[opencode-run] missing hook script name" >&2
      exit 0
    fi
    preserve_decision pipe_hook "$script"
    ;;
  *)
    echo "[opencode-run] unknown action: $ACTION" >&2
    exit 0
    ;;
esac
exit 0
