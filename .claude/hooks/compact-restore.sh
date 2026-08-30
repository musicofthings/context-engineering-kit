#!/usr/bin/env bash
# .claude/hooks/compact-restore.sh
# SessionStart hook with matcher "compact" — fires right after auto or manual
# compaction. Per the hooks docs, SessionStart is one of only three events
# whose stdout is injected into the model's context (UserPromptSubmit and
# UserPromptExpansion are the others). PostCompact stdout goes to the debug
# log only — which is why re-injection lives HERE, not in post-compact.sh.
#
# session-start.sh also fires on this event (it has no matcher) and handles
# the window clock + banner. This script injects only what compaction loses:
# the task state digest and the working notes from session_handover.md.
#
# Phrasing is deliberately factual ("The active task is X"), not imperative:
# the docs warn that injected text framed as out-of-band system commands can
# trigger the model's prompt-injection defenses.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# shellcheck source=../../scripts/resolve_state_dir.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"

HANDOVER_FILE="$MAIN_ROOT/session_handover.md"

ACTIVE_TASK="unknown"; PHASE="unknown"; NEXT_ACTION="read session_handover.md"
COMPACT_COUNT="?"; CHANGED_FILES=""
if [ -f "$STATE_FILE" ]; then
  ACTIVE_TASK=$(jq -r '.active_task // "unknown"'  "$STATE_FILE" 2>/dev/null || echo "unknown")
  PHASE=$(jq -r '.phase // "unknown"'              "$STATE_FILE" 2>/dev/null || echo "unknown")
  NEXT_ACTION=$(jq -r '.next_action // "unknown"'  "$STATE_FILE" 2>/dev/null || echo "unknown")
  COMPACT_COUNT=$(jq -r '.compact_count // "?"'    "$STATE_FILE" 2>/dev/null || echo "?")
  CHANGED_FILES=$(jq -r '(.changed_files // [])[:15][]' "$STATE_FILE" 2>/dev/null | sed 's/^/  - /' || true)
fi

cat <<INJECT
Context note: this conversation was just compacted (compaction #$COMPACT_COUNT
in this project). The summary above may have dropped working detail. The
state below was captured by hooks immediately before compaction and is
current.

The active task is: $ACTIVE_TASK
The current phase is: $PHASE
The next action is: $NEXT_ACTION
INJECT

if [ -n "$CHANGED_FILES" ]; then
  echo ""
  echo "Files changed this session:"
  echo "$CHANGED_FILES"
fi

# Inject the handover body — the highest-fidelity record of in-flight work.
# Capped so a long handover can't flood the freshly compacted window.
if [ -f "$HANDOVER_FILE" ]; then
  echo ""
  echo "── session_handover.md (saved pre-compaction) ──"
  head -c 6000 "$HANDOVER_FILE"
  if [ "$(wc -c < "$HANDOVER_FILE")" -gt 6000 ]; then
    echo ""
    echo "...(truncated — the full file is at session_handover.md)"
  fi
fi

exit 0
