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
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Resolve state location (shared worktree-aware helper) ─────────────────────
# shellcheck source=../../scripts/resolve_state_dir.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"

# ── Read Stop event input ────────────────────────────────────────────────────
INPUT=$(cat)

# Stop hook payload schema (Claude Code):
#   { session_id, transcript_path, hook_event_name, stop_hook_active }
# It does NOT include the assistant response text — that lives in the
# transcript JSONL at transcript_path. Read the last assistant message there.
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
TURN_COUNT=$(printf '%s' "$INPUT" | jq -r '.turn_count // 0' 2>/dev/null || echo "0")
# Coerce TURN_COUNT to a numeric value — argjson aborts on non-integer.
case "$TURN_COUNT" in ''|*[!0-9]*) TURN_COUNT=0 ;; esac

RESPONSE=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  # Grep-prefilter so jq doesn't slurp a multi-MB transcript when only the
  # last assistant turn matters. Each line is one JSON object.
  RESPONSE=$(grep '"type":"assistant"' "$TRANSCRIPT_PATH" 2>/dev/null \
    | tail -1 \
    | jq -r '.message.content[]? | select(.type == "text") | .text' 2>/dev/null \
    | tr '\n' ' ' \
    || echo "")
fi

# Even when we can't extract response text, keep state.json heartbeat fresh.
if [ -z "$RESPONSE" ]; then
  state_write \
    '.last_stop_turn = $turn | .last_activity = $ts' \
    --argjson turn "$TURN_COUNT" \
    --arg ts "$TIMESTAMP" \
    >/dev/null 2>&1 || true
  exit 0
fi

# ── Pattern: extract next_action ─────────────────────────────────────────────
# Look for phrases that signal the next intended action
NEXT_ACTION=""

# Priority 1: explicit "next" statements at end of response
# Collapse newlines first so [^.!?] doesn't behave differently across grep implementations
if echo "$RESPONSE" | grep -qiE "(next[: ](i'll|i will|step|we'll|we will|is|are|up)|now (i'll|i will|let's|i'm going to)|after this|going to |i'm going to |will now |let me )"; then
  NEXT_ACTION=$(echo "$RESPONSE" \
    | tr '\n' ' ' \
    | grep -iEo "(next[: ](i'll|i will|step|we'll|we will|is|are|up)[^.!?]{5,80}|now (i'll|i will|let's|i'm going to)[^.!?]{5,80}|after this[^.!?]{5,60}|going to [^.!?]{5,60}|i'm going to [^.!?]{5,60}|will now [^.!?]{5,60}|let me [^.!?]{5,60})" \
    | head -1 \
    | sed 's/^[[:space:]]*//' \
    | cut -c1-120 \
    || echo "")
fi

# Priority 2: TODO or action items at end
if [ -z "$NEXT_ACTION" ]; then
  NEXT_ACTION=$(echo "$RESPONSE" \
    | tr '\n' ' ' \
    | grep -iEo "(TODO:[^.!?]{5,80}|need to [^.!?]{5,60}|should [^.!?]{5,60})" \
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
if echo "$RESPONSE" | grep -qiE "(working on|building|implementing|fixing|creating|writing)[^.!?]{5,60}"; then
  ACTIVE_TASK_HINT=$(echo "$RESPONSE" \
    | grep -iEo "(working on|building|implementing|fixing|creating|writing)[^.!?]{5,60}" \
    | head -1 \
    | sed 's/^[[:space:]]*//' \
    | cut -c1-80 \
    || echo "")
fi

# ── Pattern: detect phase ────────────────────────────────────────────────────
PHASE_HINT=""
if echo "$RESPONSE" | grep -qiE "phase [0-9]|phase [a-z]+|step [0-9]"; then
  PHASE_HINT=$(echo "$RESPONSE" \
    | grep -iEo "phase [0-9a-z][^.!?]{0,40}" \
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

# ── Update state.json (lock-guarded, concurrency-safe) ───────────────────────
# Only write fields we actually extracted — don't clobber existing good data.
# next_action guard: this is a weak heuristic. Only fill it when the stored
# value is empty or a generic placeholder, so a precise next_action set by
# /handover is never clobbered by a noisy last-sentence match every turn.
# state_write treats a missing/corrupt file as {}, so the // defaults below
# also serve as the "no state file yet" bootstrap path.
state_write \
  '.last_stop_turn = $turn
   | .last_activity = $ts
   | .state_source = (.state_source // "stop-hook-heuristic")
   | .compact_count = (.compact_count // 0)
   | (if ($next_action != "" and ((.next_action // "") == "" or (.next_action // "") == "unknown" or (.next_action // "") == "none" or (.next_action // "") == "read session_handover.md" or (.next_action // "") == "check session_handover.md")) then .next_action = $next_action else . end)
   | (if ($active_task_hint != "" and ((.active_task // "") == "" or (.active_task // "") == "unknown" or (.active_task // "") == "initial setup")) then .active_task = $active_task_hint else . end)
   | (if ($phase_hint != "" and ((.phase // "") == "" or (.phase // "") == "unknown")) then .phase = $phase_hint else . end)
   | .next_action = (.next_action // "check session_handover.md")
   | .active_task = (.active_task // "unknown")
   | .phase = (.phase // "unknown")' \
  --argjson turn "$TURN_COUNT" \
  --arg ts "$TIMESTAMP" \
  --arg next_action "$NEXT_ACTION" \
  --arg active_task_hint "$ACTIVE_TASK_HINT" \
  --arg phase_hint "$PHASE_HINT" || true

# ── Append to session ledger (lightweight turn log) ──────────────────────────
LEDGER="$STATE_DIR/turn-ledger.jsonl"
if [ -n "$NEXT_ACTION" ] || [ -n "$ACTIVE_TASK_HINT" ]; then
  jq -n \
    --arg ts "$TIMESTAMP" \
    --argjson turn "$TURN_COUNT" \
    --arg next_action "$NEXT_ACTION" \
    --arg task_hint "$ACTIVE_TASK_HINT" \
    '{"ts":$ts,"turn":$turn,"next_action":$next_action,"task_hint":$task_hint}' \
    >> "$LEDGER" 2>/dev/null || true
fi

exit 0
