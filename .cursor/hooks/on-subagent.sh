#!/usr/bin/env bash
# .cursor/hooks/on-subagent.sh <SubagentStart|SubagentStop>
# Cursor `subagentStart` / `subagentStop` -> kit subagent-lifecycle.sh.
# The lifecycle script branches on $CLAUDE_HOOK_EVENT, passed here as $1.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

EVENT="${1:-SubagentStart}"
INPUT=$(cat 2>/dev/null || true)
printf '%s' "$INPUT" \
  | CLAUDE_HOOK_EVENT="$EVENT" bash "$CEK_HOOKS_DIR/subagent-lifecycle.sh" 1>&2 2>&1 || true
exit 0
