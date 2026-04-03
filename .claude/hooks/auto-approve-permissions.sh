#!/usr/bin/env bash
# .claude/hooks/auto-approve-permissions.sh
#
# PermissionRequest hook — fires before any permission dialog appears.
# Auto-approves writes to context engineering files so the user is NEVER
# asked for permission when /handover, the agent PreCompact hook, or
# any other skill/hook writes to session state files.
#
# Returns JSON with permissionDecision: "allow" for matching paths.
# Returns nothing (exit 0) for everything else — lets normal permission
# flow handle it.
#
# Exit codes:
#   0 = approved (with JSON output) or pass-through (no output)
#   2 = deny (never used here)

set -euo pipefail

INPUT=$(cat)

# Extract tool name and file path from PermissionRequest input
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || echo "")

# ── Auto-approved tool+path combinations ────────────────────────────────────
# These are all the files that context-engineering-kit hooks and skills write to.
# Anything in this list gets silently approved without prompting the user.

auto_approve() {
  # Return JSON decision to stdout — Claude Code reads this
  cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "permissionDecision": "allow",
    "permissionDecisionReason": "context-kit: auto-approved context file write"
  }
}
JSON
  exit 0
}

# Write/Edit tool: check if target is a context file
if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "MultiEdit" ]]; then

  # Normalise path — strip leading ./ and project dir prefix
  NORM_PATH="${FILE_PATH#./}"
  NORM_PATH="${NORM_PATH#$CLAUDE_PROJECT_DIR/}"
  NORM_PATH="${NORM_PATH#$CLAUDE_PROJECT_DIR\\}"  # Windows backslash

  # Auto-approve list — exact matches and prefix patterns
  APPROVED_PATHS=(
    "session_handover.md"
    "CLAUDE.md"
    "agents.md"
    "api_docs.md"
    "README.md"
    ".claude/session/state.json"
    ".claude/session/history.jsonl"
    ".claude/session/turn-ledger.jsonl"
    ".claude/session/daily-usage.json"
    ".claude/session/usage-forecast.json"
    ".claude/compact-audit.log"
    ".claude/config-audit.log"
  )

  # Auto-approve any path under .claude/session/
  if [[ "$NORM_PATH" == .claude/session/* ]]; then
    auto_approve
  fi

  # Auto-approve any path under docs/ (context kit docs)
  if [[ "$NORM_PATH" == docs/* ]]; then
    auto_approve
  fi

  # Check exact matches
  for approved in "${APPROVED_PATHS[@]}"; do
    if [[ "$NORM_PATH" == "$approved" ]]; then
      auto_approve
    fi
  done

fi

# Bash tool: auto-approve context kit scripts
if [[ "$TOOL_NAME" == "Bash" ]]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

  # Auto-approve session sync, handover generation, and context update scripts
  if [[ "$CMD" == *"session_sync.sh"* ]] || \
     [[ "$CMD" == *"generate_session_handover.py"* ]] || \
     [[ "$CMD" == *"update_context_files.py"* ]] || \
     [[ "$CMD" == "bash .claude/hooks/"* ]] || \
     [[ "$CMD" == *"python3 scripts/"* ]]; then
    auto_approve
  fi
fi

# Everything else: no output, normal permission flow applies
exit 0
