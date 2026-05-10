#!/usr/bin/env bash
# .claude/hooks/guard-dangerous.sh
# PreToolUse hook on Bash — blocks known-dangerous patterns.
# Exit 2 = block the tool call and tell Claude why.

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

# Regex patterns — match whitespace variants, quoting, and long-form flags
DANGEROUS_REGEXES=(
  'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f[[:space:]]+[/~]'
  'rm[[:space:]]+--recursive[[:space:]]+--force[[:space:]]+[/~]'
  'rm[[:space:]]+--force[[:space:]]+--recursive[[:space:]]+[/~]'
  'dd[[:space:]]+if=/dev/zero'
  'dd[[:space:]]+if=[^[:space:]]*[[:space:]]+of=/dev/'
  'mkfs(\.[a-z]+)?[[:space:]]'
  ':\(\)\{:\|:&\};:'
  'chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/'
  '>[[:space:]]*/dev/sd[a-z]'
)

for regex in "${DANGEROUS_REGEXES[@]}"; do
  if [[ "$CMD" =~ $regex ]]; then
    echo "BLOCKED: Command matches dangerous pattern: '$regex'" >&2
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
