#!/usr/bin/env bash
# .claude/hooks/post-tool-failure.sh
# PostToolUseFailure hook — fires when any tool call fails.
# Logs the failure to session state for debugging and handover context.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_FILE="$PROJECT_DIR/.claude/session/state.json"
FAILURE_LOG="$PROJECT_DIR/.claude/session/tool-failures.jsonl"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$PROJECT_DIR/.claude/session"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")
ERROR_MSG=$(echo "$INPUT" | jq -r '.error // ""' 2>/dev/null || echo "")
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.command // ""' 2>/dev/null || echo "")

# Append to failures log
jq -n \
  --arg ts "$TIMESTAMP" \
  --arg tool "$TOOL_NAME" \
  --arg error "$ERROR_MSG" \
  --arg path "$FILE_PATH" \
  '{"ts":$ts,"tool":$tool,"error":$error,"path":$path}' \
  >> "$FAILURE_LOG" 2>/dev/null || true

# Update last_tool_failure in state.json for handover visibility
if [ -f "$STATE_FILE" ]; then
  jq --arg ts "$TIMESTAMP" \
     --arg tool "$TOOL_NAME" \
     --arg error "$ERROR_MSG" \
    '.last_tool_failure = {"ts": $ts, "tool": $tool, "error": $error}' \
    "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE" 2>/dev/null || true
fi

exit 0
