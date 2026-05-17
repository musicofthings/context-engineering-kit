#!/usr/bin/env bash
# .claude/hooks/post-tool-failure.sh
# PostToolUseFailure hook — fires when any tool call fails.
# Logs the failure to session state for debugging and handover context.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# shellcheck source=../../scripts/resolve_state_dir.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"
FAILURE_LOG="$STATE_DIR/tool-failures.jsonl"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

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

# Update last_tool_failure (lock-guarded, concurrency-safe)
state_write \
  '.last_tool_failure = {"ts": $ts, "tool": $tool, "error": $error}' \
  --arg ts "$TIMESTAMP" --arg tool "$TOOL_NAME" --arg error "$ERROR_MSG" || true

exit 0
