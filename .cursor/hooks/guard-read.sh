#!/usr/bin/env bash
# .cursor/hooks/guard-read.sh
# Cursor `beforeReadFile` -> deny reads of credential files.
#
# .claude/rules/security.md says "Never read, display, or transmit `.env` files
# or any file containing API keys". On Claude Code that is enforced by the
# `deny: Read(./.env)` rules in .claude/settings.json. Cursor has no equivalent
# permission config, so the rule was documentation only there. This hook is the
# enforcement.
#
# Wired with `failClosed: true`: if this script crashes or times out, the read
# is blocked rather than allowed. That is the right default for a deny rule —
# a broken guard must not silently open the door.
#
# Note the hook also receives the file's full `content` on stdin. It is never
# read, logged, or echoed here; only the path is inspected.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

INPUT=$(cat 2>/dev/null || true)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.file_path // ""' 2>/dev/null || echo "")
BASENAME="${FILE_PATH##*/}"

deny() {
  jq -nc --arg msg "$1" '{permission: "deny", user_message: $msg}'
  exit 0
}

case "$BASENAME" in
  .env|.env.*|*.env)
    deny "Blocked by context-engineering-kit: $BASENAME is an environment file (.claude/rules/security.md)."
    ;;
esac

case "$FILE_PATH" in
  */.aws/credentials|*/.ssh/id_*|*/.netrc|*/.npmrc|*/.pypirc)
    deny "Blocked by context-engineering-kit: $BASENAME holds credentials (.claude/rules/security.md)."
    ;;
esac

# Anything else: stay silent and let Cursor's normal flow continue. Returning
# no JSON is an allow.
exit 0
