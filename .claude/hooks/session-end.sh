#!/usr/bin/env bash
# .claude/hooks/session-end.sh
# Fires on SessionEnd — when the session closes, is cleared, or is switched away
# from via /resume.
#
# This hook does almost nothing on purpose. SessionEnd hooks share a 1.5-second
# budget, and the hooks reference is explicit that "Timeouts set on
# plugin-provided hooks don't raise the budget" — so the `timeout: 30` that used
# to sit in hooks/hooks.json was ignored for every plugin install, and the real
# end-of-session work (handover regeneration, worktree sync, git commit) was
# killed partway through. It only ever completed when the repo itself was open
# in Claude Code, because project-scope settings *do* raise the budget. Codex is
# stricter still: 1s default, 3s maximum, always synchronous.
#
# So the work is detached into scripts/session_finalize.sh, which outlives this
# hook, and the hook returns immediately.
#
# Escape hatches:
#   CEK_SESSION_END_SYNC=1                     run the finalizer inline (tests, CI)
#   CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS=…  raise Claude Code's own budget

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
KIT_ROOT="${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}"
FINALIZE="$KIT_ROOT/scripts/session_finalize.sh"

log() { echo "[session-end] $*" >&2; }

if [ ! -f "$FINALIZE" ]; then
  log "finalizer missing at $FINALIZE — nothing to do"
  exit 0
fi

export CLAUDE_PROJECT_DIR="$PROJECT_DIR"
export CLAUDE_PLUGIN_ROOT="$KIT_ROOT"

if [ "${CEK_SESSION_END_SYNC:-0}" = "1" ]; then
  bash "$FINALIZE" || log "finalizer failed (non-fatal)"
  exit 0
fi

# Detach so the finalizer survives the 1.5s budget. setsid where available
# (Linux), otherwise a plain background child with nohup (macOS/BSD).
if command -v setsid >/dev/null 2>&1; then
  setsid bash "$FINALIZE" >/dev/null 2>&1 </dev/null &
else
  nohup bash "$FINALIZE" >/dev/null 2>&1 </dev/null &
fi
disown 2>/dev/null || true

log "session finalize detached (pid $!)"
exit 0
