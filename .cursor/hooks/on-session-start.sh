#!/usr/bin/env bash
# .cursor/hooks/on-session-start.sh
# Cursor `sessionStart` -> kit session-start.sh (+ morning brief).
#
# The kit script prints its banner / context block to stdout, which Claude Code
# injects into the model context. Cursor's sessionStart does not inject hook
# stdout, so we route that text to stderr (visible in the Hooks output channel)
# and keep stdout clean. The important side effects — state.json init, sentinel
# reset, session metadata capture — still run.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

INPUT=$(cat 2>/dev/null || true)
printf '%s' "$INPUT" | bash "$CEK_HOOKS_DIR/session-start.sh" 1>&2 || true
bash "$CEK_HOOKS_DIR/morning-brief-auto.sh" 1>&2 2>&1 || true
exit 0
