#!/usr/bin/env python3
"""
generate_runtime_hooks.py
Single source of truth for multi-runtime hook wiring (Phase C).

Generates:
  .codex/hooks.json          project adapter  — commands relative to the repo root
  .grok/hooks/cek-hooks.json project adapter  — commands relative to the repo root
  hooks/codex-hooks.json     Codex plugin     — commands under ${CLAUDE_PLUGIN_ROOT}

Commands are always portable — repo-relative or plugin-root-relative, never
absolute machine paths.

The plugin file must exist and must be named in .codex-plugin/plugin.json:
Codex falls back to `hooks/hooks.json` when a manifest declares no `hooks`
entry, and that file is the *Claude* manifest, full of events Codex has never
had. The explicit `hooks` entry is what keeps the two apart.

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
        # Codex caps SessionEnd at 3s (1s default) and always runs it
        # synchronously; session-end.sh detaches its work, so 3 is ample.
        "timeout": {"codex": 3, "grok": 30},
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
        "runtimes": ["grok"],  # Codex has no PostToolUseFailure event
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
        "runtimes": ["grok"],  # Codex has no StopFailure event
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
        # Codex-only. An interrupted turn is squarely a handover concern: the
        # next session should know the last turn was cut off rather than
        # completed. Passive — output cannot stop the interruption — and capped
        # at 3s (1s default), which RUNTIME_TIMEOUT_MAX enforces.
        "event": "Interrupt",
        "hook": "native-event-log.sh",
        "runtimes": ["codex"],
        "timeout": {"codex": 3},
    },
    {
        "event": "Notification",
        "hook": "notify.sh",
        "runtimes": ["grok"],  # Codex has no Notification event
    },
]


# Authoritative per-runtime event allow-list.
#
# `--check` only proves the generated files match this generator, so a wrong
# EVENTS entry used to stay green forever: .codex/hooks.json shipped
# PostToolUseFailure, StopFailure and Notification, none of which Codex has.
# Generation now fails if EVENTS names an event a runtime does not implement.
#
# codex: learn.chatgpt.com/docs/hooks, verified 2026-09-13.
# grok:  docs.x.ai/build/features/hooks, verified 2026-09-13. The set below is
#        exactly the documented one. Note PreToolUse is the ONLY blocking event
#        on Grok (exit 2 denies); every other event is passive and fails open.
RUNTIME_EVENTS: dict[str, set[str]] = {
    "codex": {
        "SessionStart", "SessionEnd", "UserPromptSubmit",
        "PreToolUse", "PermissionRequest", "PostToolUse",
        "PreCompact", "PostCompact",
        "SubagentStart", "SubagentStop", "Stop", "Interrupt",
    },
    "grok": {
        "SessionStart", "SessionEnd", "UserPromptSubmit",
        "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionDenied",
        "PreCompact", "PostCompact",
        "SubagentStart", "SubagentStop", "Stop", "StopFailure", "Notification",
    },
}

# Per-runtime hard timeout ceilings, in seconds. Codex: "SessionEnd and
# Interrupt use 1 second by default and support up to 3 seconds."
RUNTIME_TIMEOUT_MAX: dict[str, dict[str, int]] = {
    "codex": {"SessionEnd": 3, "Interrupt": 3},
    "grok": {},
}

# Codex documents background hooks (`"async": true`, 8 concurrent per session).
# Grok's documented schema is matcher / type / command / url / timeout only —
# no async — so emitting the key there is guesswork, not configuration.
RUNTIME_SUPPORTS_ASYNC: dict[str, bool] = {"codex": True, "grok": False}


def _cmd_codex(entry: dict) -> str:
    if "chain" in entry:
        return f'bash .codex/hooks/run.sh {entry["chain"]}'
    return f'bash .codex/hooks/run.sh hook {entry["hook"]}'


def _cmd_codex_plugin(entry: dict) -> str:
    root = '"${CLAUDE_PLUGIN_ROOT}/.codex/hooks/run.sh"'
    if "chain" in entry:
        return f'bash {root} {entry["chain"]}'
    return f'bash {root} hook {entry["hook"]}'


def _cmd_grok(entry: dict) -> str:
    if "chain" in entry:
        return f'bash .grok/hooks/run.sh {entry["chain"]}'
    return f'bash .grok/hooks/run.sh hook {entry["hook"]}'


def _timeout_for(entry: dict, runtime: str, evt: str) -> int | None:
    """Resolve an entry's timeout for one runtime, clamped to that runtime's max."""
    raw = entry.get("timeout")
    if isinstance(raw, dict):
        raw = raw.get(runtime)
    if not raw:
        return None
    ceiling = RUNTIME_TIMEOUT_MAX.get(runtime, {}).get(evt)
    if ceiling is not None and raw > ceiling:
        raise ValueError(
            f"{runtime}: {evt} timeout {raw}s exceeds the runtime maximum of {ceiling}s"
        )
    return raw


def build_hooks(runtime: str, *, plugin: bool = False) -> dict:
    if runtime == "codex":
        cmd_fn = _cmd_codex_plugin if plugin else _cmd_codex
    else:
        cmd_fn = _cmd_grok
    supported = RUNTIME_EVENTS[runtime]
    hooks: dict[str, list] = {}
    for entry in EVENTS:
        if runtime not in entry["runtimes"]:
            continue
        evt = entry["event"]
        if evt not in supported:
            raise ValueError(
                f"{runtime}: EVENTS declares {evt}, which this runtime does not "
                f"implement. Fix the entry's `runtimes`, or add {evt} to "
                f"RUNTIME_EVENTS[{runtime!r}] with a doc reference."
            )
        block: dict = {"hooks": [{"type": "command", "command": cmd_fn(entry)}]}
        if entry.get("matcher") is not None and entry.get("matcher") != "":
            block["matcher"] = entry["matcher"]
        elif "matcher" in entry:
            block["matcher"] = entry["matcher"]
        if entry.get("async") and RUNTIME_SUPPORTS_ASYNC.get(runtime, False):
            block["hooks"][0]["async"] = True
        timeout = _timeout_for(entry, runtime, evt)
        if timeout:
            block["hooks"][0]["timeout"] = timeout
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
        ROOT / "hooks" / "codex-hooks.json": build_hooks("codex", plugin=True),
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
