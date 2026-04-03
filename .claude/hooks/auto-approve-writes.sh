#!/usr/bin/env bash
# .claude/hooks/auto-approve-writes.sh
#
# PermissionRequest hook — fires whenever Claude Code would show a permission dialog.
# Silently approves writes/edits to known context files so /handover and agent hooks
# never prompt the user. All other requests pass through to normal approval flow.
#
# Output: JSON to stdout → {"permissionDecision": "allow"} or {} (defer)
# Exit 0 always — this hook never blocks.

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""'     2>/dev/null || echo "")
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || echo "")
COMMAND=$(echo "$INPUT"   | jq -r '.tool_input.command // ""'   2>/dev/null || echo "")

# ── Auto-approve: known context file writes ──────────────────────────────────

CONTEXT_FILE_PATTERNS=(
  "session_handover.md"
  "CLAUDE.md"
  "agents.md"
  ".claude/session/state.json"
  ".claude/session/history.jsonl"
  ".claude/session/turn-ledger.jsonl"
  ".claude/session/usage.jsonl"
  ".claude/compact-audit.log"
  ".claude/config-audit.log"
)

if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" ]]; then
  for pattern in "${CONTEXT_FILE_PATTERNS[@]}"; do
    if [[ "$FILE_PATH" == *"$pattern"* ]]; then
      echo '{"permissionDecision":"allow"}'
      exit 0
    fi
  done
fi

# ── Auto-approve: our own scripts and hooks ──────────────────────────────────

SAFE_BASH_PATTERNS=(
  "python3 scripts/generate_session_handover.py"
  "python3 scripts/update_context_files.py"
  "python3 scripts/usage_report.py"
  "bash scripts/session_sync.sh"
  "bash .claude/hooks/"
  "git add .claude/session"
  "git add session_handover.md"
  "git add CLAUDE.md"
  "git commit -m \"chore(context)"
  "git commit -m 'chore(context)"
)

if [[ "$TOOL_NAME" == "Bash" ]]; then
  for pattern in "${SAFE_BASH_PATTERNS[@]}"; do
    if [[ "$COMMAND" == *"$pattern"* ]]; then
      echo '{"permissionDecision":"allow"}'
      exit 0
    fi
  done
fi

# ── Defer everything else to normal approval flow ────────────────────────────
echo '{}'
exit 0
