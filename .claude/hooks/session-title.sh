#!/usr/bin/env bash
# .claude/hooks/session-title.sh
# SessionStart hook — auto-names the session from git branch + active task.
#
# Emits JSON with hookSpecificOutput.sessionTitle so Claude Code labels the
# session in /sessions and the IDE sidebar without you having to /rename manually.
# Applies only on "startup" and "resume" — ignored on "clear" and "compact".
#
# Title format: <branch>/<task-slug>
# Examples:
#   feat/vcf-parser / fix-malformed-header
#   main / unknown
#   worktree-feat-sarek / run-nf-core-sarek

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# shellcheck source=../../scripts/resolve_state_dir.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"

INPUT=$(cat 2>/dev/null || true)
SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // "startup"' 2>/dev/null || echo "startup")

# Only set title on fresh or resumed sessions
case "$SOURCE" in
  startup|resume) ;;
  *) exit 0 ;;
esac

# Resolve active task via worktree-aware STATE_FILE (set by resolve_state_dir.sh)
ACTIVE_TASK=""
if [ -f "$STATE_FILE" ]; then
  ACTIVE_TASK=$(jq -r '.active_task // ""' "$STATE_FILE" 2>/dev/null || echo "")
fi

GIT_BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Slugify the active task: lowercase, replace spaces/special chars with hyphens, cap at 40 chars
if [ -n "$ACTIVE_TASK" ] && [ "$ACTIVE_TASK" != "unknown" ] && [ "$ACTIVE_TASK" != "none" ]; then
  TASK_SLUG=$(printf '%s' "$ACTIVE_TASK" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/--*/-/g' \
    | sed 's/^-//;s/-$//' \
    | cut -c1-40)
else
  TASK_SLUG=""
fi

# Build title: branch only, or branch/task if we have one
if [ -n "$TASK_SLUG" ]; then
  TITLE="${GIT_BRANCH}/${TASK_SLUG}"
else
  TITLE="${GIT_BRANCH}"
fi

# Return JSON — Claude Code reads sessionTitle and renames the session
jq -nc --arg title "$TITLE" --arg ev "SessionStart" '{
  hookSpecificOutput: {
    hookEventName: $ev,
    sessionTitle: $title
  }
}'

exit 0
