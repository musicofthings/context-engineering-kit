#!/usr/bin/env bash
# .cursor/hooks/guard-shell.sh
# Cursor `beforeShellExecution` -> kit guard-dangerous.sh.
#
# Cursor delivers the command at top-level `.command`; the kit guard reads the
# Claude Code shape `.tool_input.command`. We reshape, then exec the guard.
# guard-dangerous.sh exits 2 to block a dangerous command — Cursor treats a
# hook exit code of 2 as "deny", so the block propagates with no JSON needed.
#
# Fails OPEN: if jq is missing or the reshape breaks, we allow rather than
# wedge every shell command. This guard is defense-in-depth, not the only line.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

if ! command -v jq >/dev/null 2>&1; then
  exit 0   # no jq -> cannot evaluate -> fail open
fi

INPUT=$(cat 2>/dev/null || true)
printf '%s' "$INPUT" \
  | jq '{tool_input: {command: (.command // .tool_input.command // "")}}' 2>/dev/null \
  | bash "$CEK_HOOKS_DIR/guard-dangerous.sh"
rc="${PIPESTATUS[2]:-0}"
exit "$rc"
