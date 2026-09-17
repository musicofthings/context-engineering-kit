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

# ── Capability lookup ────────────────────────────────────────────────────────
# Reads config/runtime_events.json, the single registry that also drives
# scripts/generate_runtime_hooks.py and the table in
# docs/runtime-capability-matrix.md.
#
# This function used to carry its own copy of that table as four nested `case`
# statements. Three copies of the same facts existed — here, in the generator,
# and in the matrix doc — and only the generator's copy validated anything, so
# Cursor (absent from it) could never be checked at all. Whichever copy someone
# updated, the other two silently disagreed.
#
# Answers "does this runtime EMIT this event", not "does the kit wire it".
# WorktreeCreate is supported by Claude Code and deliberately unwired.
#
# Lazy: most hooks never ask, so the registry is parsed on first call only.

CEK_SUPPORTED_EVENTS=""
_CEK_EVENTS_LOADED_FOR=""

_cek_load_supported_events() {
  # The cache is keyed on the runtime, not a bare "loaded" flag. The `case`
  # statement this replaced re-read $CEK_RUNTIME on every call, so a caller that
  # flips it — the Phase C evals do exactly that, and so would anything probing
  # more than one runtime — kept getting correct answers. A runtime-blind memo
  # silently answered every later query from the first runtime's event list.
  #
  # Replays the cached OUTCOME, not an unconditional success: returning 0 after
  # a failed load would leave CEK_SUPPORTED_EVENTS empty while telling the
  # caller the registry was read, flipping the fail-open guard below into
  # fail-closed for every call after the first.
  if [ "$_CEK_EVENTS_LOADED_FOR" = "${CEK_RUNTIME:-}" ] && [ -n "$_CEK_EVENTS_LOADED_FOR" ]; then
    [ -n "$CEK_SUPPORTED_EVENTS" ]
    return $?
  fi
  _CEK_EVENTS_LOADED_FOR="${CEK_RUNTIME:-}"
  CEK_SUPPORTED_EVENTS=""

  local reg=""
  for candidate in \
    "${CLAUDE_PLUGIN_ROOT:-}/config/runtime_events.json" \
    "${CEK_ROOT:-}/config/runtime_events.json" \
    "${CLAUDE_PROJECT_DIR:-}/config/runtime_events.json"; do
    case "$candidate" in /config/*) continue ;; esac
    if [ -f "$candidate" ]; then reg="$candidate"; break; fi
  done
  [ -n "$reg" ] || return 1

  if command -v jq >/dev/null 2>&1; then
    CEK_SUPPORTED_EVENTS=$(jq -r --arg rt "$CEK_RUNTIME" \
      '.runtimes[$rt].events // {} | keys | join(" ")' "$reg" 2>/dev/null || echo "")
  fi
  if [ -z "$CEK_SUPPORTED_EVENTS" ]; then
    local py=""
    for c in python3 python py; do
      command -v "$c" >/dev/null 2>&1 && { py="$c"; break; }
    done
    if [ -n "$py" ]; then
      CEK_SUPPORTED_EVENTS=$("$py" -c "
import json,sys
try:
    r=json.load(open(sys.argv[1]))['runtimes'].get(sys.argv[2],{})
    print(' '.join(r.get('events',{}).keys()))
except Exception:
    print('')
" "$reg" "$CEK_RUNTIME" 2>/dev/null || echo "")
    fi
  fi
  [ -n "$CEK_SUPPORTED_EVENTS" ]
}

# Return 0 if the event is supported on CEK_RUNTIME.
cek_runtime_supports() {
  local evt="$1"

  # Unknown runtime, or a registry we could not read (no jq AND no python, or
  # the file is missing because only the adapters were copied somewhere).
  # Fail OPEN in both cases: this is a capability hint used to skip work, and
  # wrongly answering "no" silently disables real handlers. Wrongly answering
  # "yes" costs one no-op hook run.
  case "$CEK_RUNTIME" in
    claude|cursor|codex|grok) ;;
    *) return 0 ;;
  esac
  _cek_load_supported_events || return 0

  case " $CEK_SUPPORTED_EVENTS " in
    *" $evt "*) return 0 ;;
    *) return 1 ;;
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
