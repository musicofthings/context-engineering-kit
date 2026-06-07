#!/usr/bin/env bash
# .cursor/hooks/_common.sh
#
# Shared bootstrap for the Cursor hook adapters. Cursor uses a different hook
# event model and a different stdin JSON schema than Claude Code, so these
# adapters translate Cursor's payloads into the shape the kit's existing
# .claude/hooks/*.sh scripts expect, then exec them. This keeps ONE set of
# logic (state_write, locking, handover, git snapshot) working under both
# Claude Code and Cursor.
#
# Resolution: the kit scripts key off CLAUDE_PROJECT_DIR / CLAUDE_PLUGIN_ROOT.
# Cursor does not set those, so we derive the repo root from THIS file's
# location (.cursor/hooks/_common.sh -> ../.. == repo root) and export both.

# Absolute repo root, independent of the process cwd.
CEK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export CEK_ROOT
export CLAUDE_PROJECT_DIR="$CEK_ROOT"
export CLAUDE_PLUGIN_ROOT="$CEK_ROOT"

# Mark that we're running under Cursor so the kit scripts (and dedup guard)
# can distinguish the runtime if they ever need to.
export CEK_RUNTIME="cursor"

CEK_HOOKS_DIR="$CEK_ROOT/.claude/hooks"
CEK_SCRIPTS_DIR="$CEK_ROOT/scripts"
export CEK_HOOKS_DIR CEK_SCRIPTS_DIR
