#!/usr/bin/env python3
"""
generate_runtime_hooks.py
Single source of truth for multi-runtime hook wiring (Phase C).

Generates:
  .codex/hooks.json
  .grok/hooks/cek-hooks.json

Commands are always portable (relative to project cwd), never absolute machine paths.

Usage:
  python scripts/generate_runtime_hooks.py
  python scripts/generate_runtime_hooks.py --check   # exit 1 if drift
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Canonical event → dispatch targets.
# kind: "hook" runs .claude/hooks/<name>.sh via the runtime adapter
#       "chain" runs a named chain in the adapter (e.g. stop chain)
# runtimes: which generated configs include this entry

EVENTS: list[dict] = [
    {
        "event": "SessionStart",
        "matcher": "",
        "chain": "session-start",
        "runtimes": ["codex", "grok"],
        "async": False,
    },
    {
        "event": "SessionStart",
        "matcher": "compact",
        "hook": "compact-restore.sh",
        "runtimes": ["codex", "grok"],
    },
    {
        "event": "SessionStart",
        "matcher": "startup|resume",
        "hook": "session-title.sh",
        "runtimes": ["codex", "grok"],
    },
    {
        "event": "SessionEnd",
        "hook": "session-end.sh",
        "runtimes": ["codex", "grok"],
        "timeout": 30,
    },
    {
        "event": "UserPromptSubmit",
        "hook": "usage-sentinel.sh",
        "runtimes": ["codex", "grok"],
    },
    {
        "event": "PreToolUse",
        "matcher": "Bash",
        "hook": "guard-dangerous.sh",
        "runtimes": ["codex", "grok"],
    },
    {
        "event": "PostToolUse",
        "matcher": "Edit|Write",
        "hook": "track-changes.sh",
        "runtimes": ["codex", "grok"],
    },
    {
        "event": "PostToolUseFailure",
        "hook": "post-tool-failure.sh",
        "runtimes": ["codex", "grok"],
        "async": True,
    },
    {
        "event": "PermissionRequest",
        "matcher": "Write|Edit|MultiEdit|Bash",
        "hook": "auto-approve-permissions.sh",
        "runtimes": ["codex"],  # Grok: PermissionDenied only — skip
    },
    {
        "event": "PermissionDenied",
        "hook": "permission-denied.sh",
        "runtimes": ["grok"],  # Grok-only event name
        "async": True,
    },
    {
        "event": "PreCompact",
        "hook": "pre-compact.sh",
        "runtimes": ["codex", "grok"],
    },
    {
        "event": "PostCompact",
        "hook": "post-compact.sh",
        "runtimes": ["codex", "grok"],
    },
    {
        "event": "Stop",
        "chain": "stop",
        "runtimes": ["codex", "grok"],
    },
    {
        "event": "StopFailure",
        "hook": "stop-failure.sh",
        "runtimes": ["codex", "grok"],
    },
    {
        "event": "SubagentStart",
        "chain": "subagent-start",
        "runtimes": ["codex", "grok"],
        "async": True,
    },
    {
        "event": "SubagentStop",
        "chain": "subagent-stop",
        "runtimes": ["codex", "grok"],
        "async": True,
    },
    {
        "event": "Notification",
        "hook": "notify.sh",
        "runtimes": ["codex", "grok"],
    },
]


def _cmd_codex(entry: dict) -> str:
    if "chain" in entry:
        return f'bash .codex/hooks/run.sh {entry["chain"]}'
    return f'bash .codex/hooks/run.sh hook {entry["hook"]}'


def _cmd_grok(entry: dict) -> str:
    if "chain" in entry:
        return f'bash .grok/hooks/run.sh {entry["chain"]}'
    return f'bash .grok/hooks/run.sh hook {entry["hook"]}'


def build_hooks(runtime: str) -> dict:
    cmd_fn = _cmd_codex if runtime == "codex" else _cmd_grok
    hooks: dict[str, list] = {}
    for entry in EVENTS:
        if runtime not in entry["runtimes"]:
            continue
        evt = entry["event"]
        block: dict = {"hooks": [{"type": "command", "command": cmd_fn(entry)}]}
        if entry.get("matcher") is not None and entry.get("matcher") != "":
            block["matcher"] = entry["matcher"]
        elif "matcher" in entry:
            block["matcher"] = entry["matcher"]
        if entry.get("async"):
            block["hooks"][0]["async"] = True
        if entry.get("timeout"):
            block["hooks"][0]["timeout"] = entry["timeout"]
        hooks.setdefault(evt, []).append(block)
    return {"hooks": hooks}


def write_json(path: Path, data: dict) -> str:
    text = json.dumps(data, indent=2) + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    old = path.read_text(encoding="utf-8") if path.exists() else None
    if old == text:
        return "unchanged"
    path.write_text(text, encoding="utf-8", newline="\n")
    return "written"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="fail if generated files would change")
    args = ap.parse_args()

    targets = {
        ROOT / ".codex" / "hooks.json": build_hooks("codex"),
        ROOT / ".grok" / "hooks" / "cek-hooks.json": build_hooks("grok"),
    }

    status = 0
    for path, data in targets.items():
        text = json.dumps(data, indent=2) + "\n"
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                print(f"DRIFT: {path.relative_to(ROOT)}")
                status = 1
            else:
                print(f"OK: {path.relative_to(ROOT)}")
        else:
            result = write_json(path, data)
            print(f"{result}: {path.relative_to(ROOT)}")

    # Validate no absolute Windows/Unix home paths slipped in
    for path in targets:
        if not path.exists():
            continue
        body = path.read_text(encoding="utf-8")
        for bad in ("C:\\\\Users", "C:/Users", "/Users/", "C:\\Users"):
            if bad in body:
                print(f"ERROR: absolute path marker {bad!r} in {path}")
                status = 1

    return status


if __name__ == "__main__":
    sys.exit(main())
