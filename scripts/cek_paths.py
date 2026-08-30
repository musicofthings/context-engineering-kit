#!/usr/bin/env python3
"""
cek_paths.py — Python counterpart to scripts/resolve_state_dir.sh.

Single source of truth for the Python side of WHERE session state lives and HOW
it is written. Previously each Python script carried its own copy of this logic
(or, worse, hardcoded PROJECT_DIR/.claude/session), which drifted from the shell
version — the shell handled Windows backslash worktree paths and took a lock,
the Python copies did neither.

Anything in Python that touches state.json must go through state_update() here,
for the same reason the shell side must go through state_write(): several hooks
fire on the same event and a bare read-modify-write loses the other's fields.

Lock compatibility: the shell helper takes flock(1) on <state>.lock when
available and otherwise an atomic-mkdir lock on <state>.lockd. Which one it
picks is platform-dependent (macOS has no flock(1)), so we take BOTH here —
that is the only way a Python writer actually excludes a concurrent shell
writer on either platform.
"""

from __future__ import annotations

import json
import os
import subprocess
import time
from contextlib import contextmanager
from pathlib import Path

LOCK_TIMEOUT_SEC = 5.0
_LOCK_POLL_SEC = 0.05


def _run(cmd: list[str]) -> str:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return r.stdout.strip()
    except Exception:
        return ""


def _scope(project_dir: Path, plugin_root: Path) -> str:
    settings = plugin_root / "config" / "plugin_settings.json"
    if not settings.exists():
        settings = project_dir / "config" / "plugin_settings.json"
    scope = "auto"
    if settings.exists():
        try:
            scope = (json.loads(settings.read_text(encoding="utf-8", errors="replace"))
                     .get("state", {}).get("scope", "auto"))
        except Exception:
            scope = "auto"
    scope = {"repo": "main", "shared": "main", "worktree": "local"}.get(scope, scope)
    return scope if scope in ("auto", "main", "local") else "auto"


def resolve_state_dir(project_dir: Path | None = None) -> Path:
    """Mirror resolve_state_dir.sh. Returns the directory holding state.json."""
    project_dir = Path(project_dir or os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
    plugin_root = Path(os.environ.get("CLAUDE_PLUGIN_ROOT", str(project_dir)))
    pd = str(project_dir)
    scope = _scope(project_dir, plugin_root)

    repo_root = _run(["git", "-C", pd, "rev-parse", "--show-toplevel"]) or pd
    git_dir = _run(["git", "-C", pd, "rev-parse", "--git-dir"])
    # Match forward AND backslash separators — Git-Bash/MSYS emit the former,
    # some Windows-native git configurations the latter. The shell version
    # already did this; the Python copies only checked "/worktrees/".
    in_worktree = "/worktrees/" in git_dir or "\\worktrees\\" in git_dir

    main_root = repo_root
    if in_worktree:
        wl = _run(["git", "-C", pd, "worktree", "list", "--porcelain"])
        first = wl.splitlines()[0] if wl else ""
        if first.startswith("worktree "):
            main_root = first[len("worktree "):].strip() or repo_root

    if scope == "local":
        base = repo_root
    elif scope == "main":
        base = main_root
    else:
        base = main_root if in_worktree else repo_root
    return Path(base) / ".claude" / "session"


def resolve_state_file(project_dir: Path | None = None) -> Path:
    return resolve_state_dir(project_dir) / "state.json"


@contextmanager
def state_lock(state_file: Path):
    """Best-effort cross-process lock compatible with resolve_state_dir.sh.

    Yields True if the lock was taken, False if it timed out. A timeout is not
    fatal — the caller should still write (losing a field beats losing the
    turn), but it means a concurrent writer may clobber.
    """
    lock_file = Path(str(state_file) + ".lock")
    lock_dir = Path(str(state_file) + ".lockd")
    fh = None
    have_flock = False
    have_mkdir = False
    deadline = time.monotonic() + LOCK_TIMEOUT_SEC
    try:
        try:
            import fcntl
            state_file.parent.mkdir(parents=True, exist_ok=True)
            fh = open(lock_file, "w")
            while True:
                try:
                    fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                    have_flock = True
                    break
                except OSError:
                    if time.monotonic() >= deadline:
                        break
                    time.sleep(_LOCK_POLL_SEC)
        except Exception:
            have_flock = False

        while True:
            try:
                lock_dir.mkdir()
                have_mkdir = True
                break
            except FileExistsError:
                if time.monotonic() >= deadline:
                    break
                time.sleep(_LOCK_POLL_SEC)
            except Exception:
                break

        yield have_flock or have_mkdir
    finally:
        if have_mkdir:
            try:
                lock_dir.rmdir()
            except Exception:
                pass
        if fh is not None:
            try:
                fh.close()
            except Exception:
                pass


def atomic_write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2), encoding="utf-8")
    os.replace(tmp, path)


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    except Exception:
        return {}


def state_update(state_file: Path, mutate) -> bool:
    """Lock-guarded read-modify-write. `mutate` takes and returns the dict.

    The Python equivalent of state_write() in resolve_state_dir.sh — a corrupt
    or missing file is treated as {} so the mutation always has a base object.
    """
    with state_lock(state_file) as locked:
        st = load_json(state_file)
        try:
            st = mutate(st) or st
        except Exception:
            return False
        atomic_write_json(state_file, st)
        return bool(locked)
