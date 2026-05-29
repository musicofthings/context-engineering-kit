#!/usr/bin/env bash
# .claude/hooks/track-changes.sh
# PostToolUse on Edit|Write — logs file changes to session state.
#
# Hardening notes:
# - Path normalised to PROJECT_DIR-relative form so the same file edited
#   from C:\Users\... and /c/Users/... (Git Bash) doesn't dedupe as two
#   entries. Cross-machine paths (D:\..., /Users/other/...) are stored
#   verbatim — they're already pollution by the time they reach us.
# - Capped at 50 entries (FIFO trim from the front). Without this, the
#   list grew to 30+ entries spanning three machines and deleted worktrees
#   in past sessions and bloated session_handover.md.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# shellcheck source=../../scripts/resolve_state_dir.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")

[ -z "$FILE_PATH" ] && exit 0

# Normalise: strip PROJECT_DIR prefix in both forward-slash and backslash
# form so the entry is repo-relative. Falls through to absolute path if the
# file is outside the project (e.g. transcript files, system configs).
NORM_PATH="${FILE_PATH#"$PROJECT_DIR/"}"
NORM_PATH="${NORM_PATH#"$PROJECT_DIR"\\}"
NORM_PATH="${NORM_PATH//\\//}"

# Cap at 50 entries. Append, dedup, trim from the front (oldest first).
state_write \
  '.changed_files = ((.changed_files // []) - [$f] + [$f])
   | .changed_files = (.changed_files | if length > 50 then .[length-50:] else . end)' \
  --arg f "$NORM_PATH" || true

exit 0
