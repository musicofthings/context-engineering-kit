#!/usr/bin/env bash
# .cursor/hooks/on-agent-response.sh
# Cursor `afterAgentResponse` -> kit extract-state-on-stop.sh.
#
# Cursor's `stop` payload carries only { status, loop_count } — no response
# text — and its transcript is not in the Claude JSONL shape the kit's
# transcript fallback expects, so next_action extraction was effectively dead
# on Cursor. `afterAgentResponse` hands over `{ "text": "<final assistant
# text>" }`, which extract-state-on-stop.sh now reads directly.
#
# Observational hook: no output fields are supported, so everything goes to
# stderr and the exit status is always 0.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

INPUT=$(cat 2>/dev/null || true)
printf '%s' "$INPUT" | bash "$CEK_HOOKS_DIR/extract-state-on-stop.sh" 1>&2 || true
exit 0
