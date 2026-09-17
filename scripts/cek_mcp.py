#!/usr/bin/env python3
"""
cek_mcp.py — the universal floor.

A stdio MCP server exposing context-engineering-kit's state to any agent that
speaks Model Context Protocol. Hooks give guaranteed execution on the five
runtimes that have them; this gives *reachable* state everywhere else — Warp,
Cline, Continue, Goose, Zed, and Antigravity CLI, which has no compaction hook
and therefore no other way to write a handover at all.

It is strictly weaker than hooks. The model has to CHOOSE to call these tools,
so there is no guaranteed save at 85%. That is the honest trade, and the README
says so rather than listing MCP runtimes beside Claude Code.

Stdlib only, on purpose. The kit's core is dependency-free (see
requirements.txt) and a floor that needs `pip install mcp` is not a floor. The
protocol surface used here is small: newline-delimited JSON-RPC 2.0 over
stdin/stdout, initialize / tools/list / tools/call / ping.

Spec: modelcontextprotocol.io/specification/2025-06-18 — transports, lifecycle
and server/tools, read 2026-09-18.

── Security model ───────────────────────────────────────────────────────────

This server hands write access to whatever model is driving the client, so the
boundaries are drawn deliberately:

1. The project directory is taken from the ENVIRONMENT at launch and never from
   a tool argument. No tool accepts a path. A model that has been prompt-injected
   cannot redirect a write somewhere else, because there is nowhere else to name.
2. Every state access goes through cek_paths, so the containment guard (refuses
   $HOME, ~/.claude, non-git directories) and the cross-process locks apply
   unchanged. This server adds no new way to touch state.
3. Writes can be disabled wholesale with CEK_MCP_READONLY=1.
4. session_sync is STATUS-ONLY by default. Its --save mode commits *and pushes*,
   and --load runs `git pull --rebase --autostash` over the working tree. Those
   are outward-facing and hard to reverse, so they require an explicit
   CEK_MCP_ALLOW_GIT=1 opt-in rather than being one model decision away.

Usage:
  python3 scripts/cek_mcp.py       # speaks MCP on stdin/stdout
  python3 scripts/eval_mcp.py      # drives it as a client and checks the protocol
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cek_paths import (  # noqa: E402
    load_json,
    resolve_state_file,
    state_rejection_reason,
    state_update,
    state_writes_allowed,
)

KIT_ROOT = Path(__file__).resolve().parent.parent
SERVER_NAME = "context-engineering-kit"
SERVER_VERSION = "3.4.0"

# Versions this server implements. The newest is offered when a client asks for
# something unknown, per the lifecycle spec's negotiation rule.
SUPPORTED_PROTOCOL_VERSIONS = ["2025-06-18", "2025-03-26", "2024-11-05"]
LATEST_PROTOCOL_VERSION = SUPPORTED_PROTOCOL_VERSIONS[0]

JSONRPC_PARSE_ERROR = -32700
JSONRPC_INVALID_REQUEST = -32600
JSONRPC_METHOD_NOT_FOUND = -32601
JSONRPC_INVALID_PARAMS = -32602
JSONRPC_INTERNAL_ERROR = -32603


def log(msg: str) -> None:
    """stderr only. stdout carries protocol messages and nothing else."""
    print(f"[cek-mcp] {msg}", file=sys.stderr, flush=True)


def project_dir() -> Path:
    """Where this server operates. Environment at launch, never a tool argument."""
    for var in ("CEK_MCP_PROJECT_DIR", "CLAUDE_PROJECT_DIR"):
        val = os.environ.get(var)
        if val:
            return Path(val)
    return Path.cwd()


def readonly() -> bool:
    return os.environ.get("CEK_MCP_READONLY", "").strip() in ("1", "true", "yes")


def git_allowed() -> bool:
    return os.environ.get("CEK_MCP_ALLOW_GIT", "").strip() in ("1", "true", "yes")


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def handover_path() -> Path:
    return project_dir() / "session_handover.md"


def run_script(args: list[str], timeout: int = 60) -> tuple[int, str, str]:
    """Run a kit script with the server's own project context."""
    env = dict(os.environ)
    env["CLAUDE_PROJECT_DIR"] = str(project_dir())
    env["CLAUDE_PLUGIN_ROOT"] = str(KIT_ROOT)
    env["CEK_RUNTIME"] = env.get("CEK_RUNTIME", "mcp")
    try:
        r = subprocess.run(
            args, capture_output=True, text=True, timeout=timeout,
            cwd=str(project_dir()), env=env,
        )
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return 124, "", f"timed out after {timeout}s"
    except Exception as exc:  # noqa: BLE001 — a broken tool must not kill the server
        return 1, "", str(exc)


# ── Tools ────────────────────────────────────────────────────────────────────

def _guard_write() -> str | None:
    """Shared refusal reasons for every mutating tool."""
    if readonly():
        return "Refused: this server is running with CEK_MCP_READONLY=1."
    reason = state_rejection_reason(project_dir())
    if reason:
        return (
            f"Refused: {project_dir()} is not somewhere kit state may be written "
            f"({reason}). This is the same containment guard the hooks use."
        )
    return None


def tool_handover_read(_args: dict) -> dict:
    path = handover_path()
    if not path.exists():
        return text_result(
            f"No session_handover.md in {project_dir()}.\n"
            "Nothing has been handed over yet — call handover_write to create one.",
        )
    try:
        return text_result(path.read_text(encoding="utf-8", errors="replace"))
    except Exception as exc:  # noqa: BLE001
        return text_result(f"Could not read {path}: {exc}", is_error=True)


def tool_handover_write(args: dict) -> dict:
    refusal = _guard_write()
    if refusal:
        return text_result(refusal, is_error=True)

    fields = {k: args.get(k) for k in ("active_task", "phase", "next_action") if args.get(k)}
    if fields:
        state_file = resolve_state_file(project_dir())

        def mutate(st: dict) -> dict:
            st.update(fields)
            st["last_updated"] = utc_now()
            st["last_mcp_write"] = utc_now()
            return st

        if not state_update(state_file, mutate):
            return text_result(
                "Refused: the containment guard rejected this location, so state was not written.",
                is_error=True,
            )

    rc, _out, err = run_script(
        [sys.executable, str(KIT_ROOT / "scripts" / "generate_session_handover.py"),
         "--trigger", "mcp", "--output", str(handover_path())],
    )
    if rc != 0:
        return text_result(f"Handover generation failed (rc={rc}): {err.strip()}", is_error=True)

    updated = ", ".join(f"{k}={v!r}" for k, v in fields.items()) or "no state fields changed"
    return text_result(
        f"Wrote {handover_path()}\n{updated}\n\n"
        "Note: this is an on-request save. Unlike the hook-driven runtimes there is no "
        "automatic save at the 85%/92% usage thresholds here.",
    )


def tool_state_get(_args: dict) -> dict:
    state_file = resolve_state_file(project_dir())
    if not state_file.exists():
        return text_result(f"No session state at {state_file} yet.")
    st = load_json(state_file)
    # Deliberately a whitelist. state.json accumulates fields over time and this
    # server should not become a way to read whatever ends up in it.
    keys = [
        "active_task", "phase", "next_action", "last_updated", "compact_count",
        "session_start_time", "session_id", "last_stop", "changed_files",
        "subagents_running", "api_failures", "usage_pct", "rl_5h_pct",
    ]
    view = {k: st[k] for k in keys if k in st}
    return structured_result(view, json.dumps(view, indent=2))


def tool_usage_status(_args: dict) -> dict:
    rc, out, err = run_script(
        [sys.executable, str(KIT_ROOT / "scripts" / "usage-tracker.py"), "--report"],
    )
    if rc != 0:
        return text_result(f"usage-tracker failed (rc={rc}): {err.strip()}", is_error=True)
    return text_result(out.strip() or "No usage data recorded yet.")


def tool_context_health(_args: dict) -> dict:
    """Facts about whether the kit is actually working here, not advice."""
    pd = project_dir()
    state_file = resolve_state_file(pd)
    rejection = state_rejection_reason(pd)
    hp = handover_path()

    def age_hours(p: Path) -> float | None:
        try:
            return round((datetime.now(timezone.utc).timestamp() - p.stat().st_mtime) / 3600, 1)
        except Exception:  # noqa: BLE001
            return None

    health = {
        "project_dir": str(pd),
        "is_git_repo": subprocess.run(
            ["git", "-C", str(pd), "rev-parse", "--git-dir"],
            capture_output=True, text=True,
        ).returncode == 0,
        "state_writes_allowed": state_writes_allowed(pd),
        "containment_rejection": rejection or None,
        "state_file": str(state_file),
        "state_file_exists": state_file.exists(),
        "handover_exists": hp.exists(),
        "handover_age_hours": age_hours(hp) if hp.exists() else None,
        "claude_md_exists": (pd / "CLAUDE.md").exists(),
        "server_readonly": readonly(),
        "git_tools_enabled": git_allowed(),
        "mode": "mcp — on-request only, no automatic threshold saves",
    }
    lines = [f"{k}: {v}" for k, v in health.items()]
    return structured_result(health, "\n".join(lines))


def tool_session_sync(args: dict) -> dict:
    mode = str(args.get("mode", "status")).strip().lower()
    if mode not in ("status", "save", "load"):
        return text_result(f"Unknown mode {mode!r}. Use status, save or load.", is_error=True)

    if mode in ("save", "load"):
        if readonly():
            return text_result("Refused: CEK_MCP_READONLY=1.", is_error=True)
        if not git_allowed():
            return text_result(
                f"Refused: session_sync mode={mode!r} is disabled by default.\n\n"
                "`save` commits AND PUSHES to the remote; `load` runs "
                "`git pull --rebase --autostash` over the working tree. Both are "
                "outward-facing and hard to reverse, which is not something a model "
                "should be one tool call away from.\n\n"
                "Set CEK_MCP_ALLOW_GIT=1 in the server's environment to enable them, "
                "or run `bash scripts/session_sync.sh --" + mode + "` yourself.",
                is_error=True,
            )

    flag = {"status": "--status", "save": "--save", "load": "--load"}[mode]
    rc, out, err = run_script(
        ["bash", str(KIT_ROOT / "scripts" / "session_sync.sh"), flag], timeout=120,
    )
    body = (out + "\n" + err).strip() or f"session_sync {flag} finished with rc={rc}"
    return text_result(body, is_error=(rc != 0))


TOOLS: list[dict] = [
    {
        "name": "handover_read",
        "title": "Read session handover",
        "description": (
            "Read this project's session_handover.md — the active task, the exact next "
            "action, remaining work and architecture decisions carried from previous "
            "sessions. Call this at the start of a session to pick up where the last one "
            "stopped."
        ),
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "annotations": {"readOnlyHint": True, "openWorldHint": False},
        "handler": tool_handover_read,
    },
    {
        "name": "handover_write",
        "title": "Write session handover",
        "description": (
            "Record the current task state and regenerate session_handover.md so the next "
            "session can resume from it. Call this before the context window fills, before "
            "switching machines, and at the end of a work session. On runtimes without "
            "hooks this is the ONLY way state gets saved."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "active_task": {"type": "string", "description": "What is being built or fixed, in one line."},
                "phase": {"type": "string", "description": "Which stage of that task the work is at."},
                "next_action": {"type": "string", "description": "The exact next step, specific enough to act on cold."},
            },
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": False, "destructiveHint": False, "idempotentHint": True, "openWorldHint": False},
        "handler": tool_handover_write,
    },
    {
        "name": "state_get",
        "title": "Get session state",
        "description": (
            "Read the kit's structured session state: active task, phase, next action, "
            "compaction count, changed files and usage percentages."
        ),
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "annotations": {"readOnlyHint": True, "openWorldHint": False},
        "handler": tool_state_get,
    },
    {
        "name": "usage_status",
        "title": "Usage and burn rate",
        "description": (
            "Report token usage, cost, burn rate and predicted time to the subscription "
            "limit, so a long session can be wound down before it is cut off."
        ),
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "annotations": {"readOnlyHint": True, "openWorldHint": False},
        "handler": tool_usage_status,
    },
    {
        "name": "context_health",
        "title": "Context kit health check",
        "description": (
            "Check whether context preservation is actually working in this project: "
            "whether state writes are permitted here, whether a handover exists and how "
            "stale it is, and whether this server is read-only."
        ),
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "annotations": {"readOnlyHint": True, "openWorldHint": False},
        "handler": tool_context_health,
    },
    {
        "name": "session_sync",
        "title": "Cross-device session sync",
        "description": (
            "Report cross-device sync status (branch, commits ahead, uncommitted context "
            "files). Modes 'save' and 'load' also move git state and are disabled unless "
            "the server was started with CEK_MCP_ALLOW_GIT=1."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "mode": {
                    "type": "string",
                    "enum": ["status", "save", "load"],
                    "description": "status (default, read-only); save commits and pushes; load pulls with rebase.",
                },
            },
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": False, "destructiveHint": True, "openWorldHint": True},
        "handler": tool_session_sync,
    },
]


def public_tools() -> list[dict]:
    """Tool descriptors as the wire wants them — no handler, no readonly writers."""
    out = []
    for t in TOOLS:
        if readonly() and not t["annotations"].get("readOnlyHint"):
            continue
        out.append({k: v for k, v in t.items() if k != "handler"})
    return out


def text_result(text: str, *, is_error: bool = False) -> dict:
    return {"content": [{"type": "text", "text": text}], "isError": is_error}


def structured_result(data: dict, text: str, *, is_error: bool = False) -> dict:
    # The spec asks tools returning structuredContent to also return the
    # serialised form as text, for clients that do not read structured results.
    return {
        "content": [{"type": "text", "text": text}],
        "structuredContent": data,
        "isError": is_error,
    }


# ── JSON-RPC plumbing ────────────────────────────────────────────────────────

INSTRUCTIONS = (
    "context-engineering-kit keeps task state across sessions, devices and context "
    "compaction.\n\n"
    "Call handover_read at the start of a session to recover what the last session was "
    "doing. Call handover_write before the context window fills, before switching "
    "machines, and when finishing a session.\n\n"
    "This server is the on-request path. On Claude Code, Cursor, Codex, Grok and "
    "opencode the kit also runs as hooks, which save automatically; over MCP nothing is "
    "saved unless a tool is called."
)


def handle(method: str, params: dict, state: dict) -> tuple[dict | None, dict | None]:
    """Return (result, error). Exactly one is not None; both None means notification."""
    if method == "initialize":
        requested = str(params.get("protocolVersion") or "")
        negotiated = requested if requested in SUPPORTED_PROTOCOL_VERSIONS else LATEST_PROTOCOL_VERSION
        state["initialized"] = True
        client = params.get("clientInfo") or {}
        log(f"initialize from {client.get('name', 'unknown')} "
            f"(requested {requested or 'none'}, using {negotiated})")
        return {
            "protocolVersion": negotiated,
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": SERVER_NAME, "title": "Context Engineering Kit", "version": SERVER_VERSION},
            "instructions": INSTRUCTIONS,
        }, None

    if method == "notifications/initialized":
        return None, None

    if method == "ping":
        return {}, None

    if method == "tools/list":
        return {"tools": public_tools()}, None

    if method == "tools/call":
        name = params.get("name")
        args = params.get("arguments") or {}
        if not isinstance(args, dict):
            return None, {"code": JSONRPC_INVALID_PARAMS, "message": "arguments must be an object"}
        tool = next((t for t in TOOLS if t["name"] == name), None)
        if tool is None:
            return None, {"code": JSONRPC_INVALID_PARAMS, "message": f"Unknown tool: {name}"}
        if readonly() and not tool["annotations"].get("readOnlyHint"):
            return text_result(
                f"Refused: {name} mutates state and this server is running with "
                "CEK_MCP_READONLY=1.", is_error=True,
            ), None
        try:
            return tool["handler"](args), None
        except Exception as exc:  # noqa: BLE001
            # A failing tool is a tool result, not a dead server. The spec draws
            # this line too: protocol errors for protocol problems, isError for
            # everything the tool itself ran into.
            log(f"tool {name} raised: {exc!r}")
            return text_result(f"{name} failed: {exc}", is_error=True), None

    return None, {"code": JSONRPC_METHOD_NOT_FOUND, "message": f"Method not found: {method}"}


def serve(stdin=None, stdout=None) -> int:
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    state: dict = {"initialized": False}
    log(f"serving {project_dir()} "
        f"(readonly={readonly()}, git_tools={git_allowed()})")

    for line in stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError as exc:
            send(stdout, {"jsonrpc": "2.0", "id": None,
                          "error": {"code": JSONRPC_PARSE_ERROR, "message": f"Parse error: {exc}"}})
            continue

        if not isinstance(msg, dict) or msg.get("jsonrpc") != "2.0":
            send(stdout, {"jsonrpc": "2.0", "id": None,
                          "error": {"code": JSONRPC_INVALID_REQUEST, "message": "Not a JSON-RPC 2.0 message"}})
            continue

        msg_id = msg.get("id")
        method = msg.get("method")
        params = msg.get("params") or {}

        if method is None:
            continue  # a response to something we never sent; ignore

        try:
            result, error = handle(str(method), params, state)
        except Exception as exc:  # noqa: BLE001
            result, error = None, {"code": JSONRPC_INTERNAL_ERROR, "message": str(exc)}

        # Notifications carry no id and get no reply, per JSON-RPC.
        if msg_id is None:
            continue
        if error is not None:
            send(stdout, {"jsonrpc": "2.0", "id": msg_id, "error": error})
        else:
            send(stdout, {"jsonrpc": "2.0", "id": msg_id, "result": result})

    log("stdin closed — exiting")
    return 0


def send(stdout, payload: dict) -> None:
    # One message per line, no embedded newlines: the stdio transport requires it.
    stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    stdout.flush()


def main() -> int:
    if "--selftest" in sys.argv:
        print("Self-test lives in scripts/eval_mcp.py — run:\n"
              "  python3 scripts/eval_mcp.py", file=sys.stderr)
        return 0
    return serve()


if __name__ == "__main__":
    sys.exit(main())
