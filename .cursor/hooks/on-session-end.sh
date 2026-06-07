#!/usr/bin/env bash
# .cursor/hooks/on-session-end.sh
# Cursor `sessionEnd` -> kit session-end.sh (commit session state to git).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

INPUT=$(cat 2>/dev/null || true)
printf '%s' "$INPUT" | bash "$CEK_HOOKS_DIR/session-end.sh" 1>&2 || true
exit 0
