#!/usr/bin/env bash
# .cursor/hooks/on-session-start.sh
# Cursor `sessionStart` -> kit session-start.sh (+ morning brief).
#
# The kit script prints its banner / context block to stdout, which Claude Code
# injects into the model context. Cursor does not inject raw stdout — but it
# does support a JSON response, and `additional_context` is "added to the
# conversation's initial system context". This adapter used to send the whole
# banner to stderr and inject nothing, so Cursor sessions started blind to the
# handover state that Claude Code sessions get for free.
#
# So: capture the banner, hand it back as additional_context, and mirror it to
# stderr for the Hooks output channel. Side effects (state.json init, sentinel
# reset, session metadata capture) are unchanged.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

INPUT=$(cat 2>/dev/null || true)

# stdout = the banner, stderr = the script's own log lines (passed through).
BANNER=$(printf '%s' "$INPUT" | bash "$CEK_HOOKS_DIR/session-start.sh" 2>/dev/null || true)
bash "$CEK_HOOKS_DIR/morning-brief-auto.sh" 1>&2 </dev/null || true

if [ -n "$BANNER" ]; then
  printf '%s\n' "$BANNER" >&2
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg ctx "$BANNER" '{additional_context: $ctx}'
  fi
fi

exit 0
