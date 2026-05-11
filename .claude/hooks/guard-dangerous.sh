#!/usr/bin/env bash
# .claude/hooks/guard-dangerous.sh
# PreToolUse hook on Bash — blocks known-dangerous patterns.
# Exit 2 = block the tool call and tell Claude why.

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

# Regex patterns — match whitespace variants, quoting, and long-form flags.
# Targets are intentionally narrow: only the truly destructive patterns,
# with enough variation to catch flag reordering and argument expansion.
DANGEROUS_REGEXES=(
  # rm with -rf / -fr / --recursive --force against / ~ $HOME *
  'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f[[:space:]]+[/~]'
  'rm[[:space:]]+-[a-zA-Z]*f[a-zA-Z]*r[[:space:]]+[/~]'
  'rm[[:space:]]+--recursive[[:space:]]+--force[[:space:]]+[/~]'
  'rm[[:space:]]+--force[[:space:]]+--recursive[[:space:]]+[/~]'
  'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f[[:space:]]+\$HOME'
  'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f[[:space:]]+\*'
  # find -delete on root-ish paths
  'find[[:space:]]+/[[:space:]].*-delete'
  # destructive git operations on remote/main
  'git[[:space:]]+push[[:space:]]+(--force|-f)[[:space:]]+.*[[:space:]](main|master)'
  'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f[a-zA-Z]*d'
  # disk wipers
  'dd[[:space:]]+if=/dev/zero'
  'dd[[:space:]]+if=[^[:space:]]*[[:space:]]+of=/dev/'
  'mkfs(\.[a-z]+)?[[:space:]]'
  # fork bomb
  ':\(\)\{:\|:&\};:'
  # broad permission drops
  'chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/'
  # raw block-device redirects
  '>[[:space:]]*/dev/sd[a-z]'
)

for regex in "${DANGEROUS_REGEXES[@]}"; do
  if [[ "$CMD" =~ $regex ]]; then
    echo "BLOCKED: Command matches dangerous pattern: '$regex'" >&2
    echo "Command was: $CMD" >&2
    exit 2
  fi
done

# Block writes to production.* config files.
#
# Two patterns because the destination is positioned differently per command:
#   - "> production.env"          — direct: file follows the operator
#   - "tee production.env"        — direct: file is the next token
#   - "cp src.env production.env" — last arg: cp/mv take SOURCE [...] DEST
#   - "mv tmp production.env"     — last arg
# Source-reads of production files (e.g. `cp production.env backup`) are
# allowed — they don't write to production.
PROD_RE_DIRECT='(^|[[:space:]])(>+|tee)[[:space:]]+([^[:space:]]+/)?production\.[a-zA-Z0-9_]+'
PROD_RE_DEST='(^|[[:space:]])(cp|mv)[[:space:]]+[^;&|]*[[:space:]]([^[:space:]]+/)?production\.[a-zA-Z0-9_]+([[:space:]]*$|[[:space:]]*[;&|])'
if [[ "$CMD" =~ $PROD_RE_DIRECT ]] || [[ "$CMD" =~ $PROD_RE_DEST ]]; then
  echo "BLOCKED: Attempted write to production.* config file" >&2
  exit 2
fi

exit 0
