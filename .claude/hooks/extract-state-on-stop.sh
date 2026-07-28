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

# ── Redaction + normalisation helpers ────────────────────────────────────────
# Extracted strings come straight from model output and get persisted into
# state.json (and, via generate_session_handover.py, into git-committed
# session_handover.md). Strip credential- and PHI-shaped substrings first, per
# .claude/rules/security.md. Defense-in-depth only — not a guarantee.
#
# Portability notes (the source of a past "sed: unknown command: ','" failure
# that left next_action truncated to garbage like "should be gitig"):
#   - Never use GNU-only sed flags (e.g. s///i) — BSD sed mis-parses them.
#   - Avoid nested POSIX classes like [:#[:space:]] which some seds choke on.
#   - Empty input short-circuits so sed never runs on a zero-length stream
#     under set -euo pipefail in a way that can abort the hook mid-write.
#   - stderr from sed is discarded; on any failure we return the original text.
redact() {
  local input="${1-}"
  if [ -z "$input" ]; then
    printf '%s' ""
    return 0
  fi
  # shellcheck disable=SC2001
  printf '%s' "$input" | sed -E \
    -e 's/sk-ant-[A-Za-z0-9_-]+/[REDACTED-KEY]/g' \
    -e 's/ghp_[A-Za-z0-9]+/[REDACTED-KEY]/g' \
    -e 's/gh[opsu]_[A-Za-z0-9]+/[REDACTED-KEY]/g' \
    -e 's/AKIA[A-Z0-9]{12,}/[REDACTED-KEY]/g' \
    -e 's/[Bb]earer[[:space:]]+[A-Za-z0-9._-]+/[REDACTED-TOKEN]/g' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}/[REDACTED-EMAIL]/g' \
    -e 's/[Mm][Rr][Nn][:# \t]*[0-9]{4,}/[REDACTED-MRN]/g' \
    -e 's/[0-9]{3}-[0-9]{2}-[0-9]{4}/[REDACTED-SSN]/g' \
    2>/dev/null || printf '%s' "$input"
}

# Collapse to a single line, trim, and bound length. If we hit the max length,
# drop a trailing partial word so state.json never stores fragments like
# "should be gitig".
normalize_hint() {
  local s max="${2:-120}"
  s=$(printf '%s' "${1-}" | tr '\n\r\t' '   ' | tr -s ' ')
  s=$(printf '%s' "$s" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' 2>/dev/null || printf '%s' "$s")
  [ -z "$s" ] && { printf '%s' ""; return 0; }
  s=$(printf '%s' "$s" | cut -c1-"$max" 2>/dev/null || printf '%s' "$s")
  # If truncation landed mid-token, trim back to the last space.
  if [ "${#s}" -ge "$max" ]; then
    case "$s" in
      *' '*) s="${s% *}" ;;
    esac
  fi
  printf '%s' "$s"
}

# Reject weak/passive/too-short hints so we don't clobber a good next_action
# with prose fragments ("should be gitignored…") from the response body.
is_usable_next_action() {
  local s="${1-}"
  local len=${#s}
  [ "$len" -lt 12 ] && return 1
  case "$s" in
    *' '*) ;;
    *) return 1 ;;
  esac
  # Passive description, not an actionable next step
  echo "$s" | grep -qiE '^should[[:space:]]+be[[:space:]]' && return 1
  # Obvious mid-word cutoffs from older cut -c bugs / partial greps
  echo "$s" | grep -qiE '(gitig|ignor[^e]|committ|withou|befor[^e]|aft)$' && return 1
  return 0
}

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
  RESPONSE=$(grep -E '"type"\s*:\s*"assistant"' "$TRANSCRIPT_PATH" 2>/dev/null \
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
# Look for phrases that signal the next intended action. Prefer explicit
# "next/I'll/let me" phrasing; only fall back to TODO/need-to/should+verb.
NEXT_ACTION=""
RESPONSE_ONE_LINE=$(printf '%s' "$RESPONSE" | tr '\n\r' '  ' | tr -s ' ')

# Priority 1: explicit "next" statements
# Use [^!?] (not [^.!?]) so filenames like find_python.sh are not cut at the dot.
if echo "$RESPONSE_ONE_LINE" | grep -qiE "(next[: ](i'll|i will|step|we'll|we will|is|are|up)|now (i'll|i will|let's|i'm going to)|after this|going to |i'm going to |will now |let me )"; then
  NEXT_ACTION=$(echo "$RESPONSE_ONE_LINE" \
    | grep -iEo "(next[: ](i'll|i will|step|we'll|we will|is|are|up)[^!?]{5,80}|now (i'll|i will|let's|i'm going to)[^!?]{5,80}|after this[^!?]{5,60}|going to [^!?]{5,60}|i'm going to [^!?]{5,60}|will now [^!?]{5,60}|let me [^!?]{5,60})" \
    | head -1 \
    | sed 's/[.[:space:]]*$//' \
    || true)
fi

# Priority 2: TODO / need to / should+action-verb (not bare "should be …")
# Portable TODO strip: never use sed s///i (GNU-only; BSD sed errors or mangles).
if [ -z "$NEXT_ACTION" ]; then
  NEXT_ACTION=$(echo "$RESPONSE_ONE_LINE" \
    | grep -iEo "(TODO:[^!?]{5,80}|need to [^!?]{5,60}|should (run|fix|add|update|check|create|write|implement|test|merge|commit|review|investigate|route|replace|remove|migrate|verify|pull|push|sync)[^!?]{0,60})" \
    | head -1 \
    | sed -E 's/[Tt][Oo][Dd][Oo]://; s/[.[:space:]]*$//' \
    || true)
fi

# Priority 3: last sentence if it contains action words
if [ -z "$NEXT_ACTION" ]; then
  LAST_SENTENCE=$(echo "$RESPONSE_ONE_LINE" | grep -oE '[^.!?]+[.!?]$' | tail -1 || true)
  if echo "$LAST_SENTENCE" | grep -qiE "(let me|i'll|i will|run|write|create|update|fix|check|add)"; then
    NEXT_ACTION="$LAST_SENTENCE"
  fi
fi

NEXT_ACTION=$(normalize_hint "$NEXT_ACTION" 120)
if ! is_usable_next_action "$NEXT_ACTION"; then
  NEXT_ACTION=""
fi

# ── Pattern: detect active task from content ─────────────────────────────────
ACTIVE_TASK_HINT=""
if echo "$RESPONSE_ONE_LINE" | grep -qiE "(working on|building|implementing|fixing|creating|writing)[^!?]{5,60}"; then
  ACTIVE_TASK_HINT=$(echo "$RESPONSE_ONE_LINE" \
    | grep -iEo "(working on|building|implementing|fixing|creating|writing)[^!?]{5,60}" \
    | head -1 \
    | sed 's/[.[:space:]]*$//' \
    || true)
fi
ACTIVE_TASK_HINT=$(normalize_hint "$ACTIVE_TASK_HINT" 80)

# ── Pattern: detect phase ────────────────────────────────────────────────────
PHASE_HINT=""
if echo "$RESPONSE_ONE_LINE" | grep -qiE "phase [0-9]|phase [a-z]+|step [0-9]"; then
  PHASE_HINT=$(echo "$RESPONSE_ONE_LINE" \
    | grep -iEo "phase [0-9a-z][^!?]{0,40}" \
    | head -1 \
    | sed 's/[.[:space:]]*$//' \
    || true)
fi
PHASE_HINT=$(normalize_hint "$PHASE_HINT" 60)

# ── Pattern: detect completions ──────────────────────────────────────────────
COMPLETED=""
if echo "$RESPONSE" | grep -qE "(✅|done|complete|finished|created|written|updated)"; then
  COMPLETED=$(echo "$RESPONSE" \
    | grep -E "(✅|✓|DONE|done|complete|finished)" \
    | grep -v "^#" \
    | head -5 \
    | tr '\n' '|' \
    | sed 's/|$//' \
    2>/dev/null \
    || true)
fi

# ── Redact extracted strings before they persist ─────────────────────────────
NEXT_ACTION=$(redact "$NEXT_ACTION")
ACTIVE_TASK_HINT=$(redact "$ACTIVE_TASK_HINT")
PHASE_HINT=$(redact "$PHASE_HINT")
COMPLETED=$(redact "$COMPLETED")
# Re-validate after redact (redaction can shorten/empty a string)
if ! is_usable_next_action "$NEXT_ACTION"; then
  NEXT_ACTION=""
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
