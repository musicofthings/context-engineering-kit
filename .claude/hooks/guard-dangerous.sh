#!/usr/bin/env bash
# .claude/hooks/guard-dangerous.sh
# PreToolUse hook on Bash — blocks known-dangerous patterns.
# Exit 2 = block the tool call and tell Claude why.
#
# LIMITATION — defense-in-depth, NOT a security boundary. This matches the
# literal command text against a fixed regex list. It cannot see through
# indirection: `X=/; rm -rf "$X"`, variables, subshells, eval, or a target
# hidden inside an invoked script all slip past. It reduces accidental
# footguns; it does not sandbox. Real isolation is an OS/container concern.

set -euo pipefail

INPUT=$(cat)

# Parse the command with jq when available, else fall back to Python.
# Without a fallback, a missing jq makes CMD empty and the guard FAILS OPEN —
# every dangerous command sails through because there is nothing to match.
if command -v jq >/dev/null 2>&1; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
else
  # shellcheck source=../../scripts/find_python.sh
  source "${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR:-.}}/scripts/find_python.sh"
  CMD=$(echo "$INPUT" | "$PYTHON" -c \
    "import sys,json;print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" \
    2>/dev/null || echo "")
fi

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
  # separate -r -f flags (any order) against / ~ $HOME *
  'rm[[:space:]]+-[rf][[:space:]]+-[rf][[:space:]]+([/~]|\$HOME|\*)'
  # separate -r -f flags with QUOTED destructive target — e.g. rm -r -f "$HOME"
  'rm[[:space:]]+-[rf][[:space:]]+-[rf][[:space:]]+["'"'"']?(/|~|\$HOME)["'"'"']?([[:space:]]|$|[;&|])'
  # quoted destructive targets: rm -rf "/", '~', "$HOME"
  'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f[[:space:]]+["'"'"']?(/|~|\$HOME)["'"'"']?([[:space:]]|$|[;&|])'
  # bare current-directory wipe: rm -rf . | ./ (target alone, not a path prefix)
  'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f[[:space:]]+\./?([[:space:]]|$|[;&|])'
  # find -delete on root-ish paths
  'find[[:space:]]+/[[:space:]].*-delete'
  # destructive git operations on remote/main
  'git[[:space:]]+push[[:space:]]+(--force|-f)[[:space:]]+.*[[:space:]](main|master)'
  'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f[a-zA-Z]*d'
  # disk wipers
  'dd[[:space:]]+if=/dev/zero'
  'dd[[:space:]]+if=[^[:space:]]*[[:space:]]+of=/dev/'
  'mkfs(\.[a-z0-9]+)?[[:space:]]'
  # shell history clearing (forbidden by .claude/rules/security.md)
  'history[[:space:]]+-c'
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
