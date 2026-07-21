#!/usr/bin/env bash
# scripts/check_sync.sh
#
# The repo ships two copies of the skills and agent definitions:
#   skills/            + agents/             ← plugin layout (referenced by hooks/hooks.json)
#   .claude/skills/    + .claude/subagents/  ← local project layout (referenced by .claude/settings.json)
# They must stay byte-identical. Run this before committing changes to either
# tree; CI can run it too. Exits 1 (with a diff summary) on any drift.
#
# Usage: bash scripts/check_sync.sh

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$PROJECT_DIR"

status=0

check_pair() {
  local a="$1" b="$2"
  if [ ! -d "$a" ] || [ ! -d "$b" ]; then
    echo "SKIP: $a or $b missing"
    return 0
  fi
  if ! diff -rq "$a" "$b"; then
    echo "DRIFT: $a and $b differ (see above). Copy the newer tree over the older one."
    status=1
  fi
}

check_pair "skills" ".claude/skills"
check_pair "agents" ".claude/subagents"

if [ "$status" -eq 0 ]; then
  echo "OK: duplicated trees are in sync"
fi
exit "$status"
