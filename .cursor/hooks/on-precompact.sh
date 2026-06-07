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
printf '%s' "$INPUT" | bash "$CEK_HOOKS_DIR/pre-compact.sh" 1>&2 || true
exit 0
