#!/usr/bin/env python3
"""
eval_mcp.py — drives scripts/cek_mcp.py exactly as an MCP client would.

Launches the server as a subprocess, speaks newline-delimited JSON-RPC 2.0 over
its stdin/stdout, and checks both the protocol surface and the security
boundaries. Every assertion here is about behaviour a client would actually
observe, not about internals.

Run: python3 scripts/eval_mcp.py
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

KIT = Path(__file__).resolve().parent.parent
SERVER = KIT / "scripts" / "cek_mcp.py"

PASS = 0
FAIL = 0


def ok(msg: str) -> None:
    global PASS
    print(f"  PASS  {msg}")
    PASS += 1


def bad(msg: str, detail: str = "") -> None:
    global FAIL
    print(f"  FAIL  {msg} — {detail}")
    FAIL += 1


class Client:
    """A minimal MCP client over stdio."""

    def __init__(self, project: Path, **env_extra: str):
        env = dict(os.environ)
        env["CEK_MCP_PROJECT_DIR"] = str(project)
        env.pop("CEK_MCP_READONLY", None)
        env.pop("CEK_MCP_ALLOW_GIT", None)
        env.update(env_extra)
        self.proc = subprocess.Popen(
            [sys.executable, str(SERVER)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, env=env, cwd=str(project), bufsize=1,
        )
        self._id = 0

    def request(self, method: str, params: dict | None = None) -> dict:
        self._id += 1
        msg = {"jsonrpc": "2.0", "id": self._id, "method": method}
        if params is not None:
            msg["params"] = params
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line:
            raise RuntimeError(f"server closed stdout during {method}")
        return json.loads(line)

    def notify(self, method: str, params: dict | None = None) -> None:
        msg = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            msg["params"] = params
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()

    def call(self, name: str, args: dict | None = None) -> dict:
        return self.request("tools/call", {"name": name, "arguments": args or {}})

    def close(self) -> str:
        self.proc.stdin.close()
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        return self.proc.stderr.read()


def sandbox() -> Path:
    d = Path(tempfile.mkdtemp(prefix="cek-mcp-"))
    subprocess.run(["git", "-C", str(d), "init", "-q"], check=False)
    subprocess.run(["git", "-C", str(d), "config", "user.email", "e@t"], check=False)
    subprocess.run(["git", "-C", str(d), "config", "user.name", "e"], check=False)
    (d / "CLAUDE.md").write_text("# sandbox\n")
    subprocess.run(["git", "-C", str(d), "add", "-A"], check=False,
                   capture_output=True)
    subprocess.run(["git", "-C", str(d), "commit", "-qm", "init"], check=False,
                   capture_output=True)
    return d


def text_of(resp: dict) -> str:
    return "".join(c.get("text", "") for c in resp.get("result", {}).get("content", []))


print("╔════════════════════════════════════════╗")
print("║  cek-mcp protocol + boundary evals     ║")
print("╚════════════════════════════════════════╝")

SB = sandbox()
c = Client(SB)

# ── Lifecycle ────────────────────────────────────────────────────────────────
r = c.request("initialize", {
    "protocolVersion": "2025-06-18",
    "capabilities": {},
    "clientInfo": {"name": "eval_mcp", "version": "1.0"},
})
res = r.get("result", {})
if res.get("protocolVersion") == "2025-06-18":
    ok("initialize echoes a supported protocol version")
else:
    bad("initialize protocolVersion", json.dumps(r)[:200])
if res.get("capabilities", {}).get("tools") is not None:
    ok("server declares the tools capability")
else:
    bad("tools capability", json.dumps(res)[:200])
if res.get("serverInfo", {}).get("name"):
    ok("server declares serverInfo")
else:
    bad("serverInfo", json.dumps(res)[:200])

c.notify("notifications/initialized")

# Version negotiation: an unknown version must come back as one we DO support,
# not echoed blindly.
c2 = Client(SB)
r2 = c2.request("initialize", {"protocolVersion": "1.0.0", "capabilities": {},
                               "clientInfo": {"name": "old", "version": "0"}})
if r2.get("result", {}).get("protocolVersion") in ("2025-06-18", "2025-03-26", "2024-11-05"):
    ok("unknown protocol version negotiated down to a supported one")
else:
    bad("version negotiation", json.dumps(r2)[:200])
c2.close()

# A notification must produce no response. If the server replies to one, the
# next request's reply is off by one and every later call reads a stale result.
c.notify("notifications/initialized")
r = c.request("ping")
if r.get("id") == c._id and r.get("result") == {}:
    ok("notifications get no reply; ping works")
else:
    bad("notification/ping handling", json.dumps(r)[:200])

# ── Tools ────────────────────────────────────────────────────────────────────
r = c.request("tools/list")
tools = {t["name"]: t for t in r.get("result", {}).get("tools", [])}
expected = {"handover_read", "handover_write", "state_get", "usage_status",
            "context_health", "session_sync"}
if expected <= set(tools):
    ok("tools/list exposes all six tools")
else:
    bad("tools/list", f"missing {expected - set(tools)}")

if all("inputSchema" in t and t["inputSchema"].get("type") == "object" for t in tools.values()):
    ok("every tool declares an object inputSchema")
else:
    bad("inputSchema", "a tool is missing one")

# No tool may accept a path — that is the whole containment story.
path_props = [
    (n, p) for n, t in tools.items()
    for p in t.get("inputSchema", {}).get("properties", {})
    if any(k in p.lower() for k in ("path", "dir", "file", "cwd"))
]
if not path_props:
    ok("no tool accepts a path/dir argument")
else:
    bad("path argument exposed", str(path_props))

r = c.request("tools/call", {"name": "no_such_tool", "arguments": {}})
if r.get("error", {}).get("code") == -32602:
    ok("unknown tool is a JSON-RPC error, not a crash")
else:
    bad("unknown tool", json.dumps(r)[:200])

r = c.request("nonexistent/method")
if r.get("error", {}).get("code") == -32601:
    ok("unknown method returns METHOD_NOT_FOUND")
else:
    bad("unknown method", json.dumps(r)[:200])

# ── Behaviour ────────────────────────────────────────────────────────────────
r = c.call("handover_read")
if "No session_handover.md" in text_of(r):
    ok("handover_read reports absence rather than erroring")
else:
    bad("handover_read on empty project", text_of(r)[:120])

r = c.call("handover_write", {
    "active_task": "wire the MCP floor",
    "phase": "Phase 4",
    "next_action": "run the protocol evals",
})
if not r.get("result", {}).get("isError") and (SB / "session_handover.md").exists():
    ok("handover_write creates session_handover.md")
else:
    bad("handover_write", text_of(r)[:200])

if "on-request save" in text_of(r):
    ok("handover_write states that MCP has no automatic threshold save")
else:
    bad("honesty note missing", text_of(r)[:160])

r = c.call("handover_read")
if "wire the MCP floor" in text_of(r):
    ok("handover_read returns what handover_write recorded")
else:
    bad("round trip", text_of(r)[:200])

r = c.call("state_get")
sc = r.get("result", {}).get("structuredContent", {})
if sc.get("active_task") == "wire the MCP floor":
    ok("state_get returns structuredContent")
else:
    bad("state_get", json.dumps(r)[:200])
if "session_id" in sc or "active_task" in sc:
    leaked = set(sc) - {
        "active_task", "phase", "next_action", "last_updated", "compact_count",
        "session_start_time", "session_id", "last_stop", "changed_files",
        "subagents_running", "api_failures", "usage_pct", "rl_5h_pct",
    }
    if not leaked:
        ok("state_get returns only whitelisted keys")
    else:
        bad("state_get whitelist", f"leaked {leaked}")

r = c.call("context_health")
h = r.get("result", {}).get("structuredContent", {})
if h.get("state_writes_allowed") is True and h.get("handover_exists") is True:
    ok("context_health reports the real state of the project")
else:
    bad("context_health", json.dumps(h)[:200])

# ── Security boundaries ──────────────────────────────────────────────────────
r = c.call("session_sync", {"mode": "status"})
if not r.get("result", {}).get("isError"):
    ok("session_sync status works without any opt-in")
else:
    bad("session_sync status", text_of(r)[:160])

for mode in ("save", "load"):
    r = c.call("session_sync", {"mode": mode})
    body = text_of(r)
    if r.get("result", {}).get("isError") and "CEK_MCP_ALLOW_GIT" in body:
        ok(f"session_sync {mode} refused without CEK_MCP_ALLOW_GIT")
    else:
        bad(f"session_sync {mode} not gated", body[:200])

stderr = c.close()
if "[cek-mcp]" in stderr:
    ok("server logs to stderr (stdout stays protocol-only)")
else:
    bad("stderr logging", stderr[:160])

# Read-only mode must hide AND refuse the writers.
c3 = Client(SB, CEK_MCP_READONLY="1")
c3.request("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                          "clientInfo": {"name": "ro", "version": "1"}})
r = c3.request("tools/list")
names = {t["name"] for t in r.get("result", {}).get("tools", [])}
if "handover_write" not in names and "handover_read" in names:
    ok("readonly mode hides the mutating tools from tools/list")
else:
    bad("readonly tools/list", str(names))
r = c3.call("handover_write", {"active_task": "should not happen"})
if r.get("result", {}).get("isError") and "READONLY" in text_of(r):
    ok("readonly mode refuses handover_write even when called directly")
else:
    bad("readonly enforcement", text_of(r)[:200])
c3.close()

# Containment: a project outside a git repo must be refused, by the same guard
# the hooks use — not by a second implementation living in this server.
NONGIT = Path(tempfile.mkdtemp(prefix="cek-mcp-nongit-"))
c4 = Client(NONGIT)
c4.request("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                          "clientInfo": {"name": "ng", "version": "1"}})
r = c4.call("handover_write", {"active_task": "should be refused"})
if r.get("result", {}).get("isError") and "Refused" in text_of(r):
    ok("handover_write refused outside a git repo (containment guard)")
else:
    bad("containment", text_of(r)[:200])

# The no-argument call is the one that needs _guard_write specifically. With
# fields to write, state_update refuses independently inside cek_paths — so an
# assertion that only ever passes arguments still passes with _guard_write
# deleted, and proves nothing about it. With NO arguments state_update is never
# reached, and the only thing standing between the model and a handover written
# outside a project is that guard.
r = c4.call("handover_write", {})
if r.get("result", {}).get("isError") and "Refused" in text_of(r):
    ok("handover_write with no args also refused (guard, not state_update)")
else:
    bad("no-arg containment", text_of(r)[:200])
if not (NONGIT / "session_handover.md").exists() and not (NONGIT / ".claude").exists():
    ok("nothing written to the refused location")
else:
    bad("containment leak", f"created files in {NONGIT}")
c4.close()

subprocess.run(["rm", "-rf", str(SB), str(NONGIT)], check=False)

print()
print("━" * 40)
print(f"Results: {PASS} passed, {FAIL} failed")
print("━" * 40)
sys.exit(0 if FAIL == 0 else 1)
