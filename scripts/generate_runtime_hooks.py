#!/usr/bin/env python3
"""
generate_runtime_hooks.py
Single source of truth for multi-runtime hook wiring.

Two inputs, cleanly separated:

  config/runtime_events.json   RUNTIME FACTS — which events each runtime emits,
                               what it calls them, timeouts, async support,
                               plus a `source` URL and `verified` date each.
  EVENTS (this file)           KIT POLICY — which hook or chain handles which
                               canonical event, and on which runtimes.

Generates:
  .codex/hooks.json          Codex project adapter  — repo-relative commands
  hooks/codex-hooks.json     Codex plugin           — ${CLAUDE_PLUGIN_ROOT}
  .grok/hooks/cek-hooks.json Grok project adapter   — repo-relative commands
  .cursor/hooks.json         Cursor project hooks   — repo-relative commands
  docs/runtime-capability-matrix.md — the event-support table, between markers

Commands are always portable — repo-relative or plugin-root-relative, never
absolute machine paths.

hooks/hooks.json (the Claude manifest) is deliberately NOT generated. Claude
Code is the reference runtime; its manifest carries events no other runtime has
and per-event async choices that are policy, not capability. It is validated
against the registry, not written from it.

The Codex plugin file must exist and must be named in .codex-plugin/plugin.json:
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
REGISTRY_PATH = ROOT / "config" / "runtime_events.json"
MATRIX_PATH = ROOT / "docs" / "runtime-capability-matrix.md"
MATRIX_BEGIN = "<!-- BEGIN GENERATED: event-support -->"
MATRIX_END = "<!-- END GENERATED: event-support -->"


def load_registry() -> dict:
    with REGISTRY_PATH.open(encoding="utf-8") as fh:
        return json.load(fh)["runtimes"]


RUNTIMES = load_registry()


# ── Kit policy: canonical event → what runs ──────────────────────────────────
#
# "chain" runs a named chain in the adapter (session-start, stop, subagent-*).
# "hook"  runs a single .claude/hooks/<name>.sh through the adapter.
# "runtimes" lists which generated configs include the entry. A runtime that
#   does not emit the event is a hard error, not a silent skip — see build().
#
# Cursor dispatches to its own adapter scripts rather than a run.sh action, so
# entries that apply there carry a "cursor" block naming the adapter. Cursor's
# `matcher` is also NOT a tool-name filter the way Claude's is — on
# beforeShellExecution it matches the command TEXT — so the canonical matcher is
# never emitted for Cursor.

EVENTS: list[dict] = [
    {
        "event": "SessionStart",
        "matcher": "",
        "chain": "session-start",
        "runtimes": ["codex", "grok", "cursor", "opencode"],
        "async": False,
        "cursor": {"adapter": "on-session-start.sh"},
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
        "runtimes": ["codex", "grok", "cursor", "opencode"],
        # Codex caps SessionEnd at 3s (1s default) and always runs it
        # synchronously; session-end.sh detaches its work, so 3 is ample.
        # Grok's default is 5s, so 30 here is an explicit widening.
        "timeout": {"codex": 3, "grok": 30},
        "cursor": {"adapter": "on-session-end.sh"},
    },
    {
        "event": "UserPromptSubmit",
        "hook": "usage-sentinel.sh",
        "runtimes": ["codex", "grok", "cursor"],
        "cursor": {"adapter": "on-prompt.sh"},
    },
    {
        "event": "PreToolUse",
        "matcher": "Bash",
        "hook": "guard-dangerous.sh",
        "runtimes": ["codex", "grok", "cursor", "opencode"],
        # failClosed stays false: this guard is defence-in-depth, and a crash in
        # it must not wedge every shell command Cursor wants to run.
        "cursor": {"adapter": "guard-shell.sh", "failClosed": False},
    },
    {
        "event": "PostToolUse",
        "matcher": "Edit|Write",
        "hook": "track-changes.sh",
        "runtimes": ["codex", "grok", "cursor", "opencode"],
        "cursor": {"adapter": "track-edit.sh"},
    },
    {
        "event": "PostToolUseFailure",
        "hook": "post-tool-failure.sh",
        "runtimes": ["grok", "cursor"],  # Codex has no PostToolUseFailure event
        "async": True,
        "cursor": {"adapter": "on-tool-failure.sh"},
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
        "runtimes": ["codex", "grok", "cursor", "opencode"],
        "cursor": {"adapter": "on-precompact.sh"},
    },
    {
        "event": "PostCompact",
        "hook": "post-compact.sh",
        "runtimes": ["codex", "grok", "opencode"],
    },
    {
        "event": "Stop",
        "chain": "stop",
        "runtimes": ["codex", "grok", "cursor", "opencode"],
        "cursor": {"adapter": "on-stop.sh"},
    },
    {
        "event": "StopFailure",
        "hook": "stop-failure.sh",
        "runtimes": ["grok", "opencode"],  # Codex has no StopFailure event
    },
    {
        "event": "SubagentStart",
        "chain": "subagent-start",
        "runtimes": ["codex", "grok", "cursor"],
        "async": True,
        "cursor": {"adapter": "on-subagent.sh", "args": "SubagentStart"},
    },
    {
        "event": "SubagentStop",
        "chain": "subagent-stop",
        "runtimes": ["codex", "grok", "cursor"],
        "async": True,
        "cursor": {"adapter": "on-subagent.sh", "args": "SubagentStop"},
    },
    {
        # Codex-only. An interrupted turn is squarely a handover concern: the
        # next session should know the last turn was cut off rather than
        # completed. Passive — output cannot stop the interruption — and capped
        # at 3s (1s default), which the registry's timeout_max_sec enforces.
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


# Cursor hooks with no canonical counterpart. They are not rows in the event
# table because no other runtime has anything to put in the other columns, but
# they are real wiring and belong in the generated config.
CURSOR_NATIVE: list[dict] = [
    {
        # Carries `text`, the final assistant message. Cursor's `stop` payload is
        # only {status, loop_count} and its transcript is not in the Claude JSONL
        # shape, so next_action extraction was dead on Cursor without this.
        "native_event": "afterAgentResponse",
        "adapter": "on-agent-response.sh",
    },
    {
        # Enforces the .env rule in .claude/rules/security.md. Claude Code gets
        # that from `deny: Read(./.env)`; Cursor has no equivalent config, so the
        # rule was documentation only. failClosed because a security guard that
        # fails open is not a guard.
        "native_event": "beforeReadFile",
        "adapter": "guard-read.sh",
        "failClosed": True,
    },
]


def native_event(runtime: str, canonical: str) -> str:
    """What `runtime` calls `canonical`. Raises if it does not emit it at all."""
    events = RUNTIMES[runtime]["events"]
    if canonical not in events:
        raise ValueError(
            f"{runtime}: EVENTS declares {canonical}, which this runtime does not "
            f"emit. Fix the entry's `runtimes`, or add {canonical} to "
            f"config/runtime_events.json under runtimes.{runtime}.events with a "
            f"doc reference — {RUNTIMES[runtime]['source']}"
        )
    return events[canonical]


def _timeout_for(entry: dict, runtime: str, evt: str) -> int | None:
    """Resolve an entry's timeout for one runtime, clamped to that runtime's max."""
    raw = entry.get("timeout")
    if isinstance(raw, dict):
        raw = raw.get(runtime)
    if not raw:
        return None
    ceiling = RUNTIMES[runtime].get("timeout_max_sec", {}).get(evt)
    if ceiling is not None and raw > ceiling:
        raise ValueError(
            f"{runtime}: {evt} timeout {raw}s exceeds the runtime maximum of {ceiling}s"
        )
    return raw


def _command(runtime: str, entry: dict, *, plugin: bool = False) -> str:
    rt = RUNTIMES[runtime]
    prefix = rt["plugin_command_prefix"] if plugin else rt["command_prefix"]
    if "chain" in entry:
        return f"{prefix}{entry['chain']}"
    return f"{prefix}hook {entry['hook']}"


def build_claude_style(runtime: str, *, plugin: bool = False) -> dict:
    """Codex and Grok both take Claude's {event: [{matcher, hooks: [...]}]}."""
    hooks: dict[str, list] = {}
    for entry in EVENTS:
        if runtime not in entry["runtimes"]:
            continue
        evt = entry["event"]
        emitted = native_event(runtime, evt)
        block: dict = {"hooks": [{"type": "command", "command": _command(runtime, entry, plugin=plugin)}]}
        if entry.get("matcher"):
            block["matcher"] = entry["matcher"]
        elif "matcher" in entry:
            block["matcher"] = entry["matcher"]
        if entry.get("async") and RUNTIMES[runtime].get("supports_async", False):
            block["hooks"][0]["async"] = True
        timeout = _timeout_for(entry, runtime, evt)
        if timeout:
            block["hooks"][0]["timeout"] = timeout
        hooks.setdefault(emitted, []).append(block)
    return {"hooks": hooks}


def build_cursor() -> dict:
    """Cursor's shape is {event: [{command, failClosed?}]} — flat, no matcher.

    Cursor's `matcher` is not a tool-name filter: on beforeShellExecution it is
    tested against the command TEXT. Emitting the canonical "Bash" matcher there
    would silently narrow the dangerous-command guard to commands containing the
    literal word "bash". So canonical matchers are dropped for Cursor entirely.
    """
    prefix = RUNTIMES["cursor"]["command_prefix"]
    hooks: dict[str, list] = {}

    for entry in EVENTS:
        if "cursor" not in entry["runtimes"]:
            continue
        cfg = entry.get("cursor")
        if not cfg:
            raise ValueError(
                f"EVENTS entry for {entry['event']} lists cursor in `runtimes` but "
                f"has no `cursor` block naming its adapter."
            )
        emitted = native_event("cursor", entry["event"])
        command = f"{prefix}{cfg['adapter']}"
        if cfg.get("args"):
            command = f"{command} {cfg['args']}"
        block: dict = {"command": command}
        if "failClosed" in cfg:
            block["failClosed"] = cfg["failClosed"]
        hooks.setdefault(emitted, []).append(block)

    for entry in CURSOR_NATIVE:
        if entry["native_event"] not in RUNTIMES["cursor"]["native_extra"]:
            raise ValueError(
                f"cursor: CURSOR_NATIVE declares {entry['native_event']}, which is "
                f"not listed in config/runtime_events.json under "
                f"runtimes.cursor.native_extra"
            )
        block = {"command": f"{prefix}{entry['adapter']}"}
        if "failClosed" in entry:
            block["failClosed"] = entry["failClosed"]
        hooks.setdefault(entry["native_event"], []).append(block)

    return {"version": 1, "hooks": hooks}


# ── Capability matrix table ──────────────────────────────────────────────────

def _handler_label(entry: dict) -> str:
    if "chain" in entry:
        return f"`{entry['chain']}` chain"
    return f"`{entry['hook']}`"


# Events the kit chooses not to wire, where the absence is a decision rather
# than an oversight and the reader needs to know which.
NOT_WIRED_NOTES: dict[str, str] = {
    "WorktreeCreate": "**deliberately not wired** — see below",
}


def claude_manifest_wiring() -> dict[str, list[str]]:
    """event -> handler script names, read from the hand-maintained manifest.

    Eleven events are wired on Claude Code only and never appear in EVENTS,
    which covers the generated runtimes. Without this the table reported them
    as unwired, which is worse than the hand-written table it replaced.
    """
    path = ROOT / "hooks" / "hooks.json"
    if not path.exists():
        return {}
    manifest = json.loads(path.read_text(encoding="utf-8"))
    out: dict[str, list[str]] = {}
    for evt, blocks in manifest.get("hooks", {}).items():
        names: list[str] = []
        for block in blocks:
            for handler in block.get("hooks", []):
                cmd = handler.get("command", "")
                for token in cmd.replace('"', " ").replace("'", " ").split():
                    if token.endswith(".sh") or token.endswith(".py"):
                        names.append(token.rsplit("/", 1)[-1])
        # dict.fromkeys preserves order while de-duplicating
        out[evt] = list(dict.fromkeys(names))
    return out


def build_matrix_table() -> str:
    """Render the event-support table from the registry plus the wiring table."""
    order = ["claude", "cursor", "codex", "grok", "opencode"]
    # Union of every canonical event any runtime emits, in registry order so the
    # table is stable and reviewable.
    seen: list[str] = []
    for rt in order:
        for evt in RUNTIMES[rt]["events"]:
            if evt not in seen:
                seen.append(evt)

    wired: dict[str, list[dict]] = {}
    for entry in EVENTS:
        wired.setdefault(entry["event"], []).append(entry)
    claude_only = claude_manifest_wiring()

    lines = [
        "| Event | " + " | ".join(RUNTIMES[r]["display_name"] for r in order) + " | Kit hook / chain |",
        "|-------|" + "|".join([":------:"] * len(order)) + "|------------------|",
    ]
    for evt in seen:
        cells = []
        for rt in order:
            cells.append("✅" if evt in RUNTIMES[rt]["events"] else "❌")
        entries = wired.get(evt, [])
        if entries:
            handler = " + ".join(dict.fromkeys(_handler_label(e) for e in entries))
        elif evt in NOT_WIRED_NOTES:
            handler = NOT_WIRED_NOTES[evt]
        elif claude_only.get(evt):
            handler = " + ".join(f"`{n}`" for n in claude_only[evt]) + " (Claude only)"
        else:
            handler = "_not wired_"
        lines.append(f"| {evt} | " + " | ".join(cells) + f" | {handler} |")

    lines.append("")
    lines.append("Cursor-native events with no canonical equivalent, wired anyway:")
    lines.append("")
    lines.append("| Cursor event | Adapter |")
    lines.append("|---|---|")
    for entry in CURSOR_NATIVE:
        lines.append(f"| `{entry['native_event']}` | `{entry['adapter']}` |")

    lines.append("")
    lines.append("| Runtime | Source | Verified |")
    lines.append("|---|---|---|")
    for rt in order:
        r = RUNTIMES[rt]
        lines.append(f"| {r['display_name']} | {r['source']} | {r['verified']} |")

    return "\n".join(lines)


def render_matrix(existing: str) -> str:
    """Replace the generated block, leaving every hand-written word alone."""
    if MATRIX_BEGIN not in existing or MATRIX_END not in existing:
        raise ValueError(
            f"{MATRIX_PATH.relative_to(ROOT)} is missing the generated-block markers "
            f"{MATRIX_BEGIN!r} / {MATRIX_END!r}"
        )
    head = existing.split(MATRIX_BEGIN)[0]
    tail = existing.split(MATRIX_END)[1]
    body = build_matrix_table()
    return f"{head}{MATRIX_BEGIN}\n<!-- regenerate: python scripts/generate_runtime_hooks.py -->\n\n{body}\n\n{MATRIX_END}{tail}"


# ── Validation that does not produce a file ──────────────────────────────────

def validate_claude_manifest() -> list[str]:
    """hooks/hooks.json is hand-maintained; check it against the registry anyway.

    It is the one config the generator does not write, which makes it the one
    that can drift silently. Every event it wires must be an event Claude Code
    actually emits.
    """
    problems: list[str] = []
    path = ROOT / "hooks" / "hooks.json"
    if not path.exists():
        return [f"missing {path.relative_to(ROOT)}"]
    manifest = json.loads(path.read_text(encoding="utf-8"))
    claude_events = RUNTIMES["claude"]["events"]
    for evt in manifest.get("hooks", {}):
        if evt not in claude_events:
            problems.append(
                f"hooks/hooks.json wires {evt}, which is not in the registry's "
                f"claude event set ({RUNTIMES['claude']['source']})"
            )
    return problems


def write_text(path: Path, text: str) -> str:
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

    def as_json(data: dict) -> str:
        return json.dumps(data, indent=2) + "\n"

    targets: dict[Path, str] = {
        ROOT / ".codex" / "hooks.json": as_json(build_claude_style("codex")),
        ROOT / "hooks" / "codex-hooks.json": as_json(build_claude_style("codex", plugin=True)),
        ROOT / ".grok" / "hooks" / "cek-hooks.json": as_json(build_claude_style("grok")),
        ROOT / ".cursor" / "hooks.json": as_json(build_cursor()),
    }
    if MATRIX_PATH.exists():
        targets[MATRIX_PATH] = render_matrix(MATRIX_PATH.read_text(encoding="utf-8"))

    status = 0
    for path, text in targets.items():
        rel = path.relative_to(ROOT)
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                print(f"DRIFT: {rel}")
                status = 1
            else:
                print(f"OK: {rel}")
        else:
            print(f"{write_text(path, text)}: {rel}")

    for problem in validate_claude_manifest():
        print(f"ERROR: {problem}")
        status = 1

    # No absolute machine paths may ever reach a committed config.
    for path in targets:
        if not path.exists() or path.suffix != ".json":
            continue
        body = path.read_text(encoding="utf-8")
        for bad in ("C:\\\\Users", "C:/Users", "/Users/", "C:\\Users"):
            if bad in body:
                print(f"ERROR: absolute path marker {bad!r} in {path.relative_to(ROOT)}")
                status = 1

    return status


if __name__ == "__main__":
    sys.exit(main())
