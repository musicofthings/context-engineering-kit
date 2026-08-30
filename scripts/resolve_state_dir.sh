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

# Ensure jq is available (including jq.exe under WSL via WinGet).
# shellcheck source=find_jq.sh
if [ -f "$_RSD_PLUGIN_ROOT/scripts/find_jq.sh" ]; then
  # shellcheck disable=SC1091
  source "$_RSD_PLUGIN_ROOT/scripts/find_jq.sh" 2>/dev/null || true
elif [ -f "${PROJECT_DIR}/scripts/find_jq.sh" ]; then
  # shellcheck disable=SC1091
  source "${PROJECT_DIR}/scripts/find_jq.sh" 2>/dev/null || true
fi

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
# Match both forward-slash (Git-Bash/MSYS, normal Linux/macOS) and backslash
# (some Windows-native git configurations) worktree paths.
if echo "$_rsd_git_dir" | grep -qE '[/\\]worktrees[/\\]'; then
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

# ── Containment: never create kit state outside a real project ───────────────
# When CLAUDE_PROJECT_DIR is unset these helpers fall back to $(pwd), and if
# that is not a git repo `git rev-parse --show-toplevel` fails and _rsd_base
# silently becomes the cwd — so a hook firing from $HOME used to create
# $HOME/.claude/session/, i.e. kit state inside Claude Code's OWN config
# directory. auto_init_project.sh already refused non-git dirs; this helper
# did not, and it is the one every hook goes through.
#
# CEK_STATE_OK=false makes state_write() no-op instead of writing.
CEK_STATE_OK=true
_rsd_reject=""
if ! git -C "$_rsd_base" rev-parse --git-dir >/dev/null 2>&1; then
  _rsd_reject="not a git repository"
elif [ "$_rsd_base" = "$HOME" ]; then
  _rsd_reject="\$HOME itself"
else
  case "$_rsd_base" in
    "$HOME"/.claude|"$HOME"/.claude/*) _rsd_reject="inside Claude Code's config dir" ;;
  esac
fi

if [ -n "$_rsd_reject" ]; then
  CEK_STATE_OK=false
  if [ -z "${CEK_STATE_WARNED:-}" ]; then
    echo "[resolve_state_dir] skipping state for $_rsd_base ($_rsd_reject)" >&2
    export CEK_STATE_WARNED=1
  fi
elif ! mkdir -p "$STATE_DIR" 2>/dev/null; then
  CEK_STATE_OK=false
  echo "[resolve_state_dir] WARNING: could not create $STATE_DIR — state writes will fail" >&2
else
  # Self-contained ignore for the directory we just created in SOMEONE ELSE'S
  # repo. Without it the kit's per-turn churn gets swept into the host
  # project's own `git add -A` commits — kit state is currently tracked in 8
  # unrelated repos this way. Scoped to this directory only: it never touches
  # the host project's root .gitignore, and it cannot untrack anything that is
  # already committed.
  if [ ! -e "$STATE_DIR/.gitignore" ]; then
    cat > "$STATE_DIR/.gitignore" 2>/dev/null <<'CEKIGNORE' || true
# Written by context-engineering-kit.
# Session state is machine-local: it rotates every turn and means nothing on
# another machine. The portable cross-device artifact is session_handover.md
# at the repo root, which IS meant to be committed.
#
# `*` with no negation deliberately ignores this file too: git still honours an
# ignored .gitignore, and excepting it would leave the host repo showing an
# untracked .claude/ forever. The kit recreates this file when it needs to.
*
CEKIGNORE
  fi
fi
unset _rsd_base _rsd_reject

# ── Portable lock around STATE_FILE ──────────────────────────────────────────
# flock when available (Linux / Git-Bash). macOS has no flock(1): fall back to
# an atomic mkdir spinlock with a bounded wait so a crashed writer can't wedge
# every future hook.
#
# NOTE: flock (file lock) and mkdir (directory lock) are NOT cross-process
# compatible. A Linux writer and a macOS writer sharing one state.json via
# NFS / iCloud / Dropbox lock on different paths and won't see each other.
# Do not share a single state.json across OSes via cloud-sync filesystems.
_state_lock_file="${STATE_FILE}.lock"
_state_lock_dir="${STATE_FILE}.lockd"
_state_lock_held=""

_state_acquire() {
  _state_lock_held=""
  if command -v flock &>/dev/null; then
    if ! exec 9>"$_state_lock_file" 2>/dev/null; then
      echo "[resolve_state_dir] WARNING: cannot open lock file $_state_lock_file" >&2
      return 1
    fi
    if ! flock -w 5 9 2>/dev/null; then
      exec 9>&- 2>/dev/null || true
      echo "[resolve_state_dir] WARNING: flock timeout on $_state_lock_file — aborting write" >&2
      return 1
    fi
    _state_lock_held="flock"
    return 0
  fi
  local tries=0
  while ! mkdir "$_state_lock_dir" 2>/dev/null; do
    tries=$((tries + 1))
    if [ "$tries" -ge 50 ]; then
      # Looks stale (>5s). Steal via an ATOMIC rename, not rm -rf + mkdir:
      # with rm -rf, two waiters that both time out can each delete the other's
      # freshly-won lock and both then "hold" it. Renaming the stale dir aside
      # can only succeed for one process, so exactly one waiter proceeds.
      if mv "$_state_lock_dir" "${_state_lock_dir}.stale.$$" 2>/dev/null; then
        rmdir "${_state_lock_dir}.stale.$$" 2>/dev/null || true
        if mkdir "$_state_lock_dir" 2>/dev/null; then
          _state_lock_held="mkdir"
          return 0
        fi
      fi
      echo "[resolve_state_dir] WARNING: mkdir-spinlock contention on $_state_lock_dir — aborting write" >&2
      return 1
    fi
    sleep 0.1
  done
  _state_lock_held="mkdir"
  return 0
}

_state_release() {
  case "$_state_lock_held" in
    flock) exec 9>&- 2>/dev/null || true ;;
    mkdir) rmdir "$_state_lock_dir" 2>/dev/null || true ;;
  esac
  _state_lock_held=""
}

# NOTE: a hook_once() de-dupe guard used to live here. It papered over the same
# hooks being registered twice — once by the plugin manifest (hooks/hooks.json)
# and once by the repo's .claude/settings.json. v3.0.0 removed the settings.json
# hooks block, making the plugin manifest the single hook source, so the guard
# (and its .hookfire_* marker files) is retired.

# state_write '<jq filter>' [jq args...]
# Lock-guarded, atomic read-modify-write of STATE_FILE. Missing/corrupt file is
# treated as {} so the filter always has a base object to merge into.
# Returns 0 on success, 1 on any failure (lock not acquired, mktemp failed,
# jq filter empty). Callers should propagate the return value — do NOT mask
# with `|| true` if you care whether the write landed.
state_write() {
  local filter="$1"; shift
  local tmp base
  # Containment guard (see CEK_STATE_OK above): refuse rather than create kit
  # state outside a real project.
  [ "${CEK_STATE_OK:-true}" = "true" ] || return 1
  if ! _state_acquire; then
    return 1
  fi
  if [ -s "$STATE_FILE" ] && jq -e . "$STATE_FILE" >/dev/null 2>&1; then
    base=$(cat "$STATE_FILE")
  else
    base='{}'
  fi
  tmp=$(mktemp "${STATE_FILE}.XXXXXX" 2>/dev/null) || {
    echo "[resolve_state_dir] WARNING: mktemp failed under $STATE_DIR" >&2
    _state_release
    return 1
  }
  if printf '%s' "$base" | jq "$@" "$filter" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    # mktemp creates 0600. Carry the existing file's mode across the replace so
    # state.json does not silently flip between 0600 and 0644 depending on
    # whether a shell hook or usage-tracker.py wrote it last; 0600 for a new
    # file, since state.json can hold extracted task text.
    if [ -f "$STATE_FILE" ]; then
      chmod --reference="$STATE_FILE" "$tmp" 2>/dev/null \
        || chmod "$(stat -f '%Lp' "$STATE_FILE" 2>/dev/null || echo 600)" "$tmp" 2>/dev/null \
        || true
    else
      chmod 600 "$tmp" 2>/dev/null || true
    fi
    mv "$tmp" "$STATE_FILE"
    _state_release
    return 0
  fi
  rm -f "$tmp"
  _state_release
  return 1
}
