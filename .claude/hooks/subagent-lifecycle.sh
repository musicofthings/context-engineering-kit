#!/usr/bin/env bash
# .claude/hooks/subagent-lifecycle.sh
# SubagentStart and SubagentStop hook — logs subagent invocations to session state.
# Helps track what parallel work was delegated during a session.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# shellcheck source=../../scripts/resolve_state_dir.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"
SUBAGENT_LOG="$STATE_DIR/subagents.jsonl"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOOK_EVENT="${CLAUDE_HOOK_EVENT:-SubagentStart}"

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

# Track cumulative starts and current running count (lock-guarded)
if [ "$HOOK_EVENT" = "SubagentStart" ]; then
  state_write '.subagents_started = ((.subagents_started // 0) + 1)
    | .subagents_running = ((.subagents_running // 0) + 1)' || true
elif [ "$HOOK_EVENT" = "SubagentStop" ]; then
  state_write '.subagents_running = ([((.subagents_running // 1) - 1), 0] | max)' || true
fi

exit 0
