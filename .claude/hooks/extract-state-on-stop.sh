#!/usr/bin/env bash
# .claude/hooks/extract-state-on-stop.sh
#
# Stop hook — runs after every assistant response turn.
# Does lightweight heuristic extraction of next_action from the response text.
# NO API call — pure bash + jq pattern matching. Fast, free, always runs.
#
# This is the continuous update layer that keeps state.json fresh between
# manual /handover invocations. It doesn't replace /handover — it ensures
# that even if you never ran /handover, PreCompact has *something* current.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_FILE="$PROJECT_DIR/.claude/session/state.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$PROJECT_DIR/.claude/session"

# ── Read Stop event input ────────────────────────────────────────────────────
INPUT=$(cat)

# Extract the assistant's response text from the Stop event
# Stop input contains: session_id, stop_reason, turn_count, response text
RESPONSE=$(echo "$INPUT" | jq -r '.response // ""' 2>/dev/null || echo "")
TURN_COUNT=$(echo "$INPUT" | jq -r '.turn_count // 0' 2>/dev/null || echo "0")

# If response is empty, nothing to extract
[ -z "$RESPONSE" ] && exit 0

# ── Pattern: extract next_action ─────────────────────────────────────────────
# Look for phrases that signal the next intended action
NEXT_ACTION=""

# Priority 1: explicit "next" statements at end of response
if echo "$RESPONSE" | grep -qiE "(next (i'll|i will|step|we'll|we will)|now (i'll|i will|let's)|after this)"; then
  NEXT_ACTION=$(echo "$RESPONSE" \
    | grep -iEo "(next (i'll|i will|step|we'll|we will|is|are|up)[^.!?\n]{5,80}|now (i'll|i will|let's)[^.!?\n]{5,80}|after this[^.!?\n]{5,60})" \
    | head -1 \
    | sed 's/^[[:space:]]*//' \
    | cut -c1-120 \
    || echo "")
fi

# Priority 2: TODO or action items at end
if [ -z "$NEXT_ACTION" ]; then
  NEXT_ACTION=$(echo "$RESPONSE" \
    | grep -iEo "(TODO:[^.!?\n]{5,80}|need to [^.!?\n]{5,60}|should [^.!?\n]{5,60})" \
    | head -1 \
    | sed 's/TODO://i' \
    | sed 's/^[[:space:]]*//' \
    | cut -c1-120 \
    || echo "")
fi

# Priority 3: last sentence if it ends with action words
if [ -z "$NEXT_ACTION" ]; then
  LAST_SENTENCE=$(echo "$RESPONSE" | tr '\n' ' ' | grep -oE '[^.!?]+[.!?]$' | tail -1 | sed 's/^[[:space:]]*//' || echo "")
  if echo "$LAST_SENTENCE" | grep -qiE "(let me|i'll|i will|run|write|create|update|fix|check|add)"; then
    NEXT_ACTION=$(echo "$LAST_SENTENCE" | cut -c1-120)
  fi
fi

# ── Pattern: detect active task from content ─────────────────────────────────
ACTIVE_TASK_HINT=""

# Look for "working on", "building", "implementing", "fixing"
if echo "$RESPONSE" | grep -qiE "(working on|building|implementing|fixing|creating|writing)[^.!?\n]{5,60}"; then
  ACTIVE_TASK_HINT=$(echo "$RESPONSE" \
    | grep -iEo "(working on|building|implementing|fixing|creating|writing)[^.!?\n]{5,60}" \
    | head -1 \
    | sed 's/^[[:space:]]*//' \
    | cut -c1-80 \
    || echo "")
fi

# ── Pattern: detect phase ────────────────────────────────────────────────────
PHASE_HINT=""
if echo "$RESPONSE" | grep -qiE "phase [0-9]|phase [a-z]+|step [0-9]"; then
  PHASE_HINT=$(echo "$RESPONSE" \
    | grep -iEo "phase [0-9a-z][^.!?\n]{0,40}" \
    | head -1 \
    | sed 's/^[[:space:]]*//' \
    || echo "")
fi

# ── Pattern: detect completions ──────────────────────────────────────────────
# Lines ending with ✅ or "done" or "complete"
COMPLETED=""
if echo "$RESPONSE" | grep -qE "(✅|done|complete|finished|created|written|updated)"; then
  COMPLETED=$(echo "$RESPONSE" \
    | grep -E "(✅|✓|DONE|done|complete|finished)" \
    | grep -v "^#" \
    | head -5 \
    | tr '\n' '|' \
    | sed 's/|$//' \
    || echo "")
fi

# ── Update state.json ─────────────────────────────────────────────────────────
# Only write fields we actually extracted — don't clobber existing good data
if [ -f "$STATE_FILE" ]; then
  CURRENT=$(cat "$STATE_FILE")

  # Build jq update expression based on what we found
  JQ_ARGS=""
  JQ_EXPR="."

  JQ_EXPR="$JQ_EXPR | .last_stop_turn = $TURN_COUNT"
  JQ_EXPR="$JQ_EXPR | .last_activity = \"$TIMESTAMP\""

  if [ -n "$NEXT_ACTION" ]; then
    # Escape for jq
    NEXT_ACTION_ESCAPED=$(echo "$NEXT_ACTION" | sed 's/"/\\"/g' | tr -d '\n')
    JQ_EXPR="$JQ_EXPR | .next_action = \"$NEXT_ACTION_ESCAPED\""
  fi

  if [ -n "$ACTIVE_TASK_HINT" ]; then
    CURRENT_TASK=$(echo "$CURRENT" | jq -r '.active_task // ""' 2>/dev/null || echo "")
    # Only update if current task is generic/unknown
    if [ "$CURRENT_TASK" = "unknown" ] || [ "$CURRENT_TASK" = "" ] || [ "$CURRENT_TASK" = "initial setup" ]; then
      HINT_ESCAPED=$(echo "$ACTIVE_TASK_HINT" | sed 's/"/\\"/g' | tr -d '\n')
      JQ_EXPR="$JQ_EXPR | .active_task = \"$HINT_ESCAPED\""
    fi
  fi

  if [ -n "$PHASE_HINT" ]; then
    CURRENT_PHASE=$(echo "$CURRENT" | jq -r '.phase // ""' 2>/dev/null || echo "")
    if [ "$CURRENT_PHASE" = "unknown" ] || [ "$CURRENT_PHASE" = "" ]; then
      PHASE_ESCAPED=$(echo "$PHASE_HINT" | sed 's/"/\\"/g' | tr -d '\n')
      JQ_EXPR="$JQ_EXPR | .phase = \"$PHASE_ESCAPED\""
    fi
  fi

  # Apply update
  echo "$CURRENT" | jq "$JQ_EXPR" > "$STATE_FILE.tmp" \
    && mv "$STATE_FILE.tmp" "$STATE_FILE" \
    || true

else
  # No state file yet — create minimal one
  cat > "$STATE_FILE" <<EOF
{
  "last_activity": "$TIMESTAMP",
  "last_stop_turn": $TURN_COUNT,
  "next_action": "${NEXT_ACTION:-"check session_handover.md"}",
  "active_task": "${ACTIVE_TASK_HINT:-"unknown"}",
  "phase": "${PHASE_HINT:-"unknown"}",
  "compact_count": 0,
  "state_source": "stop-hook-heuristic"
}
EOF
fi

# ── Append to session ledger (lightweight turn log) ──────────────────────────
LEDGER="$PROJECT_DIR/.claude/session/turn-ledger.jsonl"
if [ -n "$NEXT_ACTION" ] || [ -n "$ACTIVE_TASK_HINT" ]; then
  echo "{\"ts\":\"$TIMESTAMP\",\"turn\":$TURN_COUNT,\"next_action\":\"$(echo "$NEXT_ACTION" | sed 's/"/\\"/g' | tr -d '\n')\",\"task_hint\":\"$(echo "$ACTIVE_TASK_HINT" | sed 's/"/\\"/g' | tr -d '\n')\"}" \
    >> "$LEDGER" 2>/dev/null || true
fi

exit 0
