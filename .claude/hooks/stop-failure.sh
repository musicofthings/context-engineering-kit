#!/usr/bin/env bash
# .claude/hooks/stop-failure.sh
# StopFailure hook — fires when a turn ends due to an API error.
# Logs the error type to session state and injects a note for the next turn.
# Common error types: rate_limit, overloaded, billing_error, model_not_found,
# max_output_tokens, authentication_failed, server_error.
#
# Useful for:
# - Tracking rate limit frequency (signals you should slow down or use Haiku)
# - Detecting overload events (consider /compact-smart if context is heavy)
# - Diagnosing billing/auth failures quickly

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# shellcheck source=../../scripts/resolve_state_dir.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"

INPUT=$(cat 2>/dev/null || true)

# Extract failure type (rate_limit, overloaded, billing_error, model_not_found,
# max_output_tokens, authentication_failed, server_error, unknown)
FAILURE_TYPE=$(printf '%s' "$INPUT" | jq -r '.failure_type // .error_type // "unknown"' 2>/dev/null || echo "unknown")

# Increment failure counter and record last failure in state
state_write \
  '.api_failures = ((.api_failures // 0) + 1)
   | .last_api_failure = {"ts": $ts, "type": $ftype}' \
  --arg ts "$TIMESTAMP" \
  --arg ftype "$FAILURE_TYPE" \
  >/dev/null 2>&1 || true

# Log to failures file alongside tool failures
FAILURE_LOG="$STATE_DIR/tool-failures.jsonl"
jq -n \
  --arg ts "$TIMESTAMP" \
  --arg ftype "$FAILURE_TYPE" \
  '{"ts":$ts,"event":"StopFailure","failure_type":$ftype}' \
  >> "$FAILURE_LOG" 2>/dev/null || true

# For StopFailure, exit code and stderr are ignored by Claude Code.
# No stdout injection is possible here — this hook is logging-only.
exit 0
