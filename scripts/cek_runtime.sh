#!/usr/bin/env bash
# scripts/cek_runtime.sh
#
# Shared multi-runtime bootstrap for context-engineering-kit.
# Sourced by Cursor / Codex / Grok thin adapters (and optionally by hooks).
#
# Exports:
#   CEK_ROOT            — absolute repo root for this kit install / project
#   CEK_RUNTIME         — claude | cursor | codex | grok | unknown
#   CLAUDE_PROJECT_DIR  — always set (hooks expect this)
#   CLAUDE_PLUGIN_ROOT  — always set (same as CEK_ROOT for standalone)
#   CEK_HOOKS_DIR       — $CEK_ROOT/.claude/hooks
#   CEK_SCRIPTS_DIR     — $CEK_ROOT/scripts
#
# Helpers:
#   cek_runtime_detect          — set CEK_RUNTIME from env/hints
#   cek_runtime_supports <evt>  — 0 if this runtime has the event
#   cek_run_hook <script> [args]— run a .claude/hooks script with stdin preserved
#   cek_run_hook_stderr <script>— same, stdout→stderr (Cursor/Grok non-inject)

# Resolve kit root: caller may set CEK_ROOT; else walk from BASH_SOURCE of the
# *caller* if they set CEK_ADAPTER_DIR; else from this file (scripts/ → ..).
if [ -z "${CEK_ROOT:-}" ]; then
  if [ -n "${CEK_ADAPTER_DIR:-}" ]; then
    # Adapter lives at <root>/.cursor/hooks or <root>/.codex/hooks or <root>/.grok/hooks
    CEK_ROOT="$(cd "${CEK_ADAPTER_DIR}/../.." && pwd)"
  else
    CEK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi
fi
export CEK_ROOT

export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$CEK_ROOT}"
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$CEK_ROOT}"
export CEK_HOOKS_DIR="${CEK_HOOKS_DIR:-$CEK_ROOT/.claude/hooks}"
export CEK_SCRIPTS_DIR="${CEK_SCRIPTS_DIR:-$CEK_ROOT/scripts}"

# ── Runtime detection ─────────────────────────────────────────────────────────
cek_runtime_detect() {
  if [ -n "${CEK_RUNTIME:-}" ] && [ "$CEK_RUNTIME" != "unknown" ]; then
    export CEK_RUNTIME
    return 0
  fi
  if [ -n "${CURSOR_TRACE_ID:-}" ] || [ -n "${CURSOR_SESSION_ID:-}" ]; then
    CEK_RUNTIME="cursor"
  elif [ -n "${CODEX_HOME:-}" ] || [ -n "${CODEX_THREAD_ID:-}" ]; then
    CEK_RUNTIME="codex"
  elif [ -n "${GROK_HOME:-}" ] || [ -n "${GROK_SESSION_ID:-}" ] || [ -n "${XAI_SESSION_ID:-}" ]; then
    CEK_RUNTIME="grok"
  elif [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ] || [ -n "${CLAUDECODE:-}" ]; then
    CEK_RUNTIME="claude"
  else
    CEK_RUNTIME="unknown"
  fi
  export CEK_RUNTIME
}

cek_runtime_detect

# ── Capability matrix (mirrors docs/runtime-capability-matrix.md) ─────────────
# Return 0 if the event is supported on CEK_RUNTIME.
cek_runtime_supports() {
  local evt="$1"
  case "$CEK_RUNTIME" in
    claude)
      case "$evt" in
        SessionStart|SessionEnd|UserPromptSubmit|PreToolUse|PostToolUse|PostToolUseFailure|\
        PermissionRequest|Stop|StopFailure|Notification|SubagentStart|SubagentStop|\
        PreCompact|PostCompact|InstructionsLoaded|FileChanged) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    cursor)
      case "$evt" in
        SessionStart|SessionEnd|UserPromptSubmit|PreToolUse|PostToolUse|PostToolUseFailure|\
        Stop|SubagentStart|SubagentStop|PreCompact) return 0 ;;
        # Cursor has no PermissionRequest / Session inject parity for all events
        PermissionRequest|StopFailure|Notification|PostCompact|InstructionsLoaded|FileChanged) return 1 ;;
        *) return 1 ;;
      esac
      ;;
    grok)
      case "$evt" in
        SessionStart|SessionEnd|UserPromptSubmit|PreToolUse|PostToolUse|PostToolUseFailure|\
        Stop|StopFailure|Notification|SubagentStart|SubagentStop|PreCompact|PostCompact|\
        PermissionDenied) return 0 ;;
        # Grok uses PermissionDenied, not PermissionRequest; no InstructionsLoaded/FileChanged
        PermissionRequest|InstructionsLoaded|FileChanged) return 1 ;;
        *) return 1 ;;
      esac
      ;;
    codex)
      case "$evt" in
        SessionStart|SessionEnd|UserPromptSubmit|PreToolUse|PostToolUse|PostToolUseFailure|\
        PermissionRequest|Stop|StopFailure|SubagentStart|SubagentStop|PreCompact|PostCompact|\
        Notification) return 0 ;;
        InstructionsLoaded|FileChanged) return 1 ;;
        *) return 1 ;;
      esac
      ;;
    *)
      # unknown — allow all (best-effort)
      return 0
      ;;
  esac
}

# NOTE: a cek_skip_if_unsupported() helper used to live here. It called `exit`
# from this *sourced* library, so it would terminate the caller's shell rather
# than just the check. It had zero callers and was not in the documented helper
# list above. Use `cek_runtime_supports <evt> || exit 0` at the call site.

# Run a kit hook script. Preserves stdin via a temp copy when needed.
cek_run_hook() {
  local script="$1"; shift
  local path="$CEK_HOOKS_DIR/$script"
  if [ ! -f "$path" ]; then
    echo "[cek_runtime] missing hook: $path" >&2
    return 1
  fi
  # Ensure jq/python resolution available to child
  export CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT CEK_ROOT CEK_RUNTIME
  bash "$path" "$@"
}

# Cursor / some Grok paths: side effects only; route inject text to stderr.
cek_run_hook_stderr() {
  local script="$1"; shift
  local path="$CEK_HOOKS_DIR/$script"
  if [ ! -f "$path" ]; then
    echo "[cek_runtime] missing hook: $path" >&2
    return 1
  fi
  export CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT CEK_ROOT CEK_RUNTIME
  bash "$path" "$@" 1>&2
}
