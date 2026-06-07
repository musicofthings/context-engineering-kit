#!/usr/bin/env bash
# .cursor/hooks/on-prompt.sh
# Cursor `beforeSubmitPrompt` -> kit usage-sentinel.sh.
#
# usage-sentinel reads state.json (not stdin) and logs a usage snapshot to
# usage.jsonl, arming the threshold sentinels. Under Claude Code its stdout
# warning is injected into context; Cursor's beforeSubmitPrompt does not inject
# arbitrary stdout, so we send it to stderr (Hooks output) and never block the
# prompt. The usage tracking / logging — the load-bearing part — still runs.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

INPUT=$(cat 2>/dev/null || true)
printf '%s' "$INPUT" | bash "$CEK_HOOKS_DIR/usage-sentinel.sh" 1>&2 || true
exit 0
