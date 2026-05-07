#!/usr/bin/env bash
# .claude/hooks/subagent-lifecycle.sh
# SubagentStart and SubagentStop hook — logs subagent invocations to session state.
# Helps track what parallel work was delegated during a session.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_FILE="$PROJECT_DIR/.claude/session/state.json"
SUBAGENT_LOG="$PROJECT_DIR/.claude/session/subagents.jsonl"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOOK_EVENT="${CLAUDE_HOOK_EVENT:-SubagentStart}"

mkdir -p "$PROJECT_DIR/.claude/session"

INPUT=$(cat)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // ""' 2>/dev/null || echo "")
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null || echo "")
DESCRIPTION=$(echo "$INPUT" | jq -r '.description // ""' 2>/dev/null || echo "")

jq -n \
  --arg ts "$TIMESTAMP" \
  --arg event "$HOOK_EVENT" \
  --arg id "$AGENT_ID" \
  --arg type "$AGENT_TYPE" \
  --arg desc "$DESCRIPTION" \
  '{"ts":$ts,"event":$event,"agent_id":$id,"agent_type":$type,"description":$desc}' \
  >> "$SUBAGENT_LOG" 2>/dev/null || true

# Track cumulative starts and current running count in state.json
if [ -f "$STATE_FILE" ]; then
  STATE_TMP=$(mktemp "${STATE_FILE}.XXXXXX")
  if [ "$HOOK_EVENT" = "SubagentStart" ]; then
    jq '.subagents_started = ((.subagents_started // 0) + 1)
      | .subagents_running = ((.subagents_running // 0) + 1)' \
      "$STATE_FILE" > "$STATE_TMP" && mv "$STATE_TMP" "$STATE_FILE" 2>/dev/null || rm -f "$STATE_TMP"
  elif [ "$HOOK_EVENT" = "SubagentStop" ]; then
    jq '.subagents_running = ([(.subagents_running // 1) - 1, 0] | max)' \
      "$STATE_FILE" > "$STATE_TMP" && mv "$STATE_TMP" "$STATE_FILE" 2>/dev/null || rm -f "$STATE_TMP"
  fi
fi

exit 0
