#!/usr/bin/env bash
# .cursor/hooks/on-tool-failure.sh
# Cursor `postToolUseFailure` -> kit post-tool-failure.sh (log the failure).
# Field names may differ from Claude Code; the kit script defaults missing
# fields to "unknown"/"" so it degrades gracefully.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

INPUT=$(cat 2>/dev/null || true)
printf '%s' "$INPUT" | bash "$CEK_HOOKS_DIR/post-tool-failure.sh" 1>&2 2>&1 || true
exit 0
