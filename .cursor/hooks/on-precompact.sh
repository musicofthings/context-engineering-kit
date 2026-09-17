#!/usr/bin/env bash
# .cursor/hooks/on-precompact.sh
# Cursor `preCompact` -> kit pre-compact.sh.
#
# pre-compact.sh increments compact_count, regenerates session_handover.md +
# CLAUDE.md, and commits a snapshot to git. Its stdout ("CONTEXT PRESERVED")
# is a Claude Code context injection; Cursor preCompact is observe-only, so we
# route that text to stderr and keep the load-bearing side effects.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

INPUT=$(cat 2>/dev/null || true)

# pre-compact.sh's stdout is a Claude Code context injection. Cursor's
# preCompact cannot inject into the conversation, but it DOES accept
# {"user_message": "..."} and shows it to the user when compaction fires.
# That is strictly better than the stderr-only routing this used to do, where
# the text reached the Hooks output channel and nowhere the user would look.
OUT=$(printf '%s' "$INPUT" | bash "$CEK_HOOKS_DIR/pre-compact.sh" 2>/dev/null || true)

if [ -n "$OUT" ] && command -v jq >/dev/null 2>&1; then
  jq -nc --arg m "$OUT" '{"user_message": $m}'
fi
exit 0
