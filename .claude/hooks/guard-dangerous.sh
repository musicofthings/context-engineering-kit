#!/usr/bin/env bash
# .claude/hooks/guard-dangerous.sh
# PreToolUse hook on Bash — blocks known-dangerous patterns.
# Exit 2 = block the tool call and tell Claude why.

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

DANGEROUS_PATTERNS=(
  "rm -rf /"
  "rm -rf ~"
  "dd if=/dev/zero"
  "mkfs"
  ":(){:|:&};:"
  "chmod -R 777 /"
  "> /dev/sda"
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if [[ "$CMD" == *"$pattern"* ]]; then
    echo "BLOCKED: Command matches dangerous pattern: '$pattern'" >&2
    echo "Command was: $CMD" >&2
    exit 2
  fi
done

# Block writes to production config
if [[ "$CMD" == *"production"* && ("$CMD" == *"write"* || "$CMD" == *">"*) ]]; then
  echo "BLOCKED: Attempted write to production config" >&2
  exit 2
fi

exit 0
