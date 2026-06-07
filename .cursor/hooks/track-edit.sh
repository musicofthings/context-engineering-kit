#!/usr/bin/env bash
# .cursor/hooks/track-edit.sh
# Cursor `afterFileEdit` -> kit track-changes.sh.
#
# Cursor delivers the edited path at top-level `.file_path`; the kit script
# reads the Claude Code shape `.tool_input.file_path`. Reshape, then exec.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || true)
printf '%s' "$INPUT" \
  | jq '{tool_input: {file_path: (.file_path // .tool_input.file_path // "")}}' 2>/dev/null \
  | bash "$CEK_HOOKS_DIR/track-changes.sh" 1>&2 || true
exit 0
