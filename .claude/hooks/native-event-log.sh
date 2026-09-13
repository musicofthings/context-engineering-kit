#!/usr/bin/env bash
# .claude/hooks/native-event-log.sh
#
# Logs the native Claude Code lifecycle hooks this kit now surfaces for
# observability and later handover/reporting. This is intentionally a no-op
# logger: it records the event to state-native JSONL and updates state.json,
# without altering the model’s behavior or injecting text into the turn.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# `source` is a POSIX special builtin: under `set -e` a missing file aborts the
# shell outright, and the trailing `|| true` does NOT catch it. Test first.
_rsd="${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"
if [ -f "$_rsd" ]; then
  # shellcheck source=../../scripts/resolve_state_dir.sh
  source "$_rsd" 2>/dev/null || true
fi
unset _rsd

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EVENT_NAME=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // .event // "NativeEvent"' 2>/dev/null || echo "NativeEvent")
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '(.tool_name // .tool // .name // "") // ""' 2>/dev/null || echo "")
PATH_VALUE=$(printf '%s' "$INPUT" | jq -r '(.file_path // .path // .cwd // "") // ""' 2>/dev/null || echo "")
MESSAGE_VALUE=$(printf '%s' "$INPUT" | jq -r '(.message // .reason // .error // .summary // "") // ""' 2>/dev/null || echo "")

# Two reasons to stop before writing anything:
#   - `set -u` + an unset STATE_DIR is a fatal expansion error that `|| true`
#     cannot catch, so the script would exit non-zero whenever
#     resolve_state_dir.sh failed to source.
#   - Containment: this hook appends to native-events.jsonl directly, which used
#     to bypass CEK_STATE_OK entirely and deposit state in $HOME/.claude.
STATE_DIR="${STATE_DIR:-}"
if [ -z "$STATE_DIR" ]; then
  exit 0
fi
if declare -f cek_state_ok >/dev/null 2>&1 && ! cek_state_ok; then
  exit 0
fi

mkdir -p "$STATE_DIR" 2>/dev/null || true
jq -nc \
  --arg ts "$TIMESTAMP" \
  --arg event "$EVENT_NAME" \
  --arg tool "$TOOL_NAME" \
  --arg path "$PATH_VALUE" \
  --arg msg "$MESSAGE_VALUE" \
  '{"ts":$ts,"event":$event,"tool":$tool,"path":$path,"message":$msg}' \
  >> "$STATE_DIR/native-events.jsonl" 2>/dev/null || true

if declare -f state_write >/dev/null 2>&1; then
  state_write \
    '.last_native_event = {"ts": $ts, "event": $event, "tool": $tool, "path": $path, "message": $msg}
     | .native_event_count = ((.native_event_count // 0) + 1)' \
    --arg ts "$TIMESTAMP" \
    --arg event "$EVENT_NAME" \
    --arg tool "$TOOL_NAME" \
    --arg path "$PATH_VALUE" \
    --arg msg "$MESSAGE_VALUE" \
    || true
fi

exit 0
