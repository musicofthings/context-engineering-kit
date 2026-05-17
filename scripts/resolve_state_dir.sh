#!/usr/bin/env bash
# scripts/resolve_state_dir.sh
#
# Single source of truth for WHERE session state lives and HOW it is written.
# Sourced by every hook that touches state.json.
#
# ── Two logic flows ──────────────────────────────────────────────────────────
#
#   BRANCH flow (no worktree, the common case)
#     One working directory. State lives at <repo>/.claude/session/. State is
#     per-PROJECT, not per-branch — switching branches keeps continuity.
#
#   WORKTREE flow (linked worktrees)
#     Worktrees are ephemeral; their branch is deleted when the task ends.
#     By default state is redirected to the MAIN checkout so it survives.
#
# ── Scope is configurable ────────────────────────────────────────────────────
# config/plugin_settings.json → "state": { "scope": "<value>" }
#
#   auto   (default) — branch flow uses repo root; worktree flow → main checkout
#   main   (aka repo / shared) — always the main checkout, even from a worktree
#   local  (aka worktree)      — never redirect; state stays in THIS working dir
#                                (isolated per worktree — opt in if you run many
#                                 worktrees in parallel and want them separate)
#
# ── Concurrency ──────────────────────────────────────────────────────────────
# Multiple sessions/worktrees can converge on the same state.json. Use the
# state_write() function below for all read-modify-write updates: it takes a
# portable lock (flock if present, mkdir-spinlock otherwise) and writes
# atomically, so concurrent writers field-merge instead of clobbering.
#
# ── Exports ──────────────────────────────────────────────────────────────────
#   PROJECT_DIR    — the working dir the hook ran in
#   REPO_ROOT      — git toplevel of PROJECT_DIR (worktree root if in one)
#   MAIN_ROOT      — main checkout root (== PROJECT_DIR when not a worktree)
#   IN_WORKTREE    — "true" / "false"
#   STATE_SCOPE    — resolved scope ("auto"|"main"|"local")
#   STATE_DIR      — directory that holds state.json (always created)
#   STATE_FILE     — $STATE_DIR/state.json
# Functions: state_write '<jq filter>' [jq args...]
#
# Usage:
#   PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
#   source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"
#   state_write '.foo = $v' --arg v "bar"

: "${PROJECT_DIR:=${CLAUDE_PROJECT_DIR:-$(pwd)}}"
_RSD_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}"

# ── Resolve scope from plugin settings (default: auto) ───────────────────────
STATE_SCOPE="auto"
_rsd_settings="$_RSD_PLUGIN_ROOT/config/plugin_settings.json"
if [ -f "$_rsd_settings" ]; then
  STATE_SCOPE=$(jq -r '.state.scope // "auto"' "$_rsd_settings" 2>/dev/null || echo "auto")
fi
case "$STATE_SCOPE" in
  repo|shared) STATE_SCOPE="main" ;;
  worktree)    STATE_SCOPE="local" ;;
  auto|main|local) ;;
  *) STATE_SCOPE="auto" ;;
esac

# ── Git topology ─────────────────────────────────────────────────────────────
REPO_ROOT=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$PROJECT_DIR")
_rsd_git_dir=$(git -C "$PROJECT_DIR" rev-parse --git-dir 2>/dev/null || echo "")
if echo "$_rsd_git_dir" | grep -q '/worktrees/'; then
  IN_WORKTREE=true
  MAIN_ROOT=$(git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null \
    | awk 'NR==1{sub(/^worktree /,""); print; exit}')
  [ -z "$MAIN_ROOT" ] && MAIN_ROOT="$REPO_ROOT"
else
  IN_WORKTREE=false
  MAIN_ROOT="$REPO_ROOT"
fi
unset _rsd_git_dir _rsd_settings

# ── Pick the state directory per scope ───────────────────────────────────────
case "$STATE_SCOPE" in
  local)  _rsd_base="$REPO_ROOT" ;;                                   # this working dir
  main)   _rsd_base="$MAIN_ROOT" ;;                                    # always main checkout
  auto|*) if [ "$IN_WORKTREE" = true ]; then _rsd_base="$MAIN_ROOT"; else _rsd_base="$REPO_ROOT"; fi ;;
esac

STATE_DIR="$_rsd_base/.claude/session"
STATE_FILE="$STATE_DIR/state.json"
unset _rsd_base
mkdir -p "$STATE_DIR" 2>/dev/null || true

# ── Portable lock around STATE_FILE ──────────────────────────────────────────
# flock when available (Linux / Git-Bash). macOS has no flock(1): fall back to
# an atomic mkdir spinlock with a bounded wait so a crashed writer can't wedge
# every future hook.
_state_lock_dir="${STATE_FILE}.lockd"
_state_lock_file="${STATE_FILE}.lock"

_state_acquire() {
  if command -v flock &>/dev/null; then
    exec 9>"$_state_lock_file" 2>/dev/null || return 0
    flock -w 5 9 2>/dev/null || true
    return 0
  fi
  local tries=0
  while ! mkdir "$_state_lock_dir" 2>/dev/null; do
    tries=$((tries + 1))
    if [ "$tries" -ge 50 ]; then            # ~5s: assume stale, steal the lock
      rm -rf "$_state_lock_dir" 2>/dev/null || true
      mkdir "$_state_lock_dir" 2>/dev/null || true
      break
    fi
    sleep 0.1
  done
}

_state_release() {
  if command -v flock &>/dev/null; then
    exec 9>&- 2>/dev/null || true
  else
    rmdir "$_state_lock_dir" 2>/dev/null || true
  fi
}

# state_write '<jq filter>' [jq args...]
# Lock-guarded, atomic read-modify-write of STATE_FILE. Missing/corrupt file is
# treated as {} so the filter always has a base object to merge into.
state_write() {
  local filter="$1"; shift
  local tmp base
  _state_acquire
  if [ -s "$STATE_FILE" ] && jq -e . "$STATE_FILE" >/dev/null 2>&1; then
    base=$(cat "$STATE_FILE")
  else
    base='{}'
  fi
  tmp=$(mktemp "${STATE_FILE}.XXXXXX" 2>/dev/null) || { _state_release; return 1; }
  if printf '%s' "$base" | jq "$@" "$filter" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv "$tmp" "$STATE_FILE"
  else
    rm -f "$tmp"
    _state_release
    return 1
  fi
  _state_release
}
