#!/usr/bin/env bash
# .cursor/hooks/_common.sh
#
# Cursor adapter bootstrap (Phase C). Delegates to shared scripts/cek_runtime.sh
# so Cursor / Codex / Grok all set CLAUDE_PROJECT_DIR the same way.

# Assign then export (SC2155): `export VAR="$(...)"` masks the command
# substitution's exit status behind export's own.
CEK_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CEK_ADAPTER_DIR

# ── Grok also loads this file. Bail out when it does. ────────────────────────
# docs.x.ai/build/features/hooks, verified 2026-09-17, verbatim: "Claude Code
# (.claude/settings.json) and Cursor (.cursor/hooks.json) hook files are read as
# well, INCLUDING CURSOR'S CAMELCASE EVENT NAMES."
#
# Earlier versions of this repo asserted the opposite — that the Cursor file
# "uses Cursor-only event names" and therefore could not fire on Grok. It is
# exactly backwards. Grok reads sessionStart, stop, preCompact and the rest, so
# a Grok session in a repo carrying this kit ran BOTH .grok/hooks/cek-hooks.json
# and all twelve handlers in .cursor/hooks.json: two session-start chains, two
# stop chains (usage-tracker.py twice per turn), two pre-compact snapshot
# commits. Same double-fire class v3.0.0 removed from .claude/settings.json.
#
# Grok exports GROK_HOOK_EVENT / GROK_HOOK_NAME / GROK_SESSION_ID /
# GROK_WORKSPACE_ROOT into every hook process, so the runtime is unambiguous
# here. Cursor never sets them. `.grok/hooks/cek-hooks.json` stays the single
# Grok source; this is the one place the two can collide.
#
# This bootstrap is sourced as the first line of all eleven adapters, so
# `exit` here stops each of them before any side effect. `return` would only
# end the source call and let the adapter carry on, which is the opposite of
# what is wanted. Exiting from a sourced file is the footgun that got
# cek_skip_if_unsupported() deleted from cek_runtime.sh — the difference is
# that this is the bootstrap itself, at the top, where ending the caller IS
# the contract, not a helper invoked mid-script.
if [ -n "${GROK_SESSION_ID:-}${GROK_HOOK_EVENT:-}${GROK_WORKSPACE_ROOT:-}" ]; then
  echo "[cek/cursor] Grok session detected — deferring to .grok/hooks/cek-hooks.json" >&2
  exit 0
fi

# shellcheck source=../../scripts/cek_runtime.sh
source "$(cd "$CEK_ADAPTER_DIR/../.." && pwd)/scripts/cek_runtime.sh"
export CEK_RUNTIME="cursor"
