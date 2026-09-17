# `cek-mcp` — setup for any MCP client

`scripts/cek_mcp.py` is a stdio MCP server exposing the kit's state to any agent
that speaks Model Context Protocol. It is the **universal floor**: hooks give
guaranteed execution on the five runtimes that have them, this gives *reachable*
state everywhere else.

**Read this first.** MCP is strictly weaker than hooks. The model has to *choose*
to call these tools, so there is **no guaranteed save at 85% and no automatic
save before compaction**. If your runtime supports hooks (Claude Code, Cursor,
Codex, Grok, opencode), install those — the MCP server is a supplement there,
not a replacement.

Where it is the *only* option:

| Runtime | Why |
|---|---|
| **Warp** | No hook mechanism at all (`warpdotdev/warp#6857`, open since Jul 2025) |
| **Antigravity CLI** | Five events, none of them session or compaction events — the pre-compaction handover cannot be triggered by a hook there |
| **Cline, Continue, Goose, Zed, …** | No adapter in this kit; MCP is the shared surface |

---

## Requirements

Python 3 on `PATH`. Nothing else — the server is stdlib-only, deliberately. A
floor that needs `pip install mcp` is not a floor.

## Environment

| Variable | Effect |
|---|---|
| `CEK_MCP_PROJECT_DIR` | The project the server operates on. Falls back to `CLAUDE_PROJECT_DIR`, then the launch cwd. **Set this explicitly** — clients vary in what cwd they hand a server. |
| `CEK_MCP_READONLY=1` | Hides and refuses every mutating tool. |
| `CEK_MCP_ALLOW_GIT=1` | Enables `session_sync` modes `save` and `load`. Off by default — see below. |

### Why `session_sync` is gated

`save` commits **and pushes** to the remote. `load` runs
`git pull --rebase --autostash` over your working tree. Both are outward-facing
and hard to reverse, and neither is something a model should be one tool call
away from on its own initiative. `mode: "status"` is read-only and always
available.

---

## Tools

| Tool | Reads | Writes | Notes |
|---|:---:|:---:|---|
| `handover_read` | ✅ | | The session handover — active task, next action, decisions |
| `handover_write` | | ✅ | Records task state and regenerates `session_handover.md` |
| `state_get` | ✅ | | Structured state; returns a **whitelist** of keys, not whatever `state.json` happens to hold |
| `usage_status` | ✅ | | Burn rate and predicted time to the subscription limit |
| `context_health` | ✅ | | Whether preservation is actually working here |
| `session_sync` | ✅ | ⚠️ | `status` free; `save`/`load` need `CEK_MCP_ALLOW_GIT=1` |

No tool accepts a path. The project directory comes from the environment at
launch and cannot be redirected by a tool argument — a prompt-injected model has
nowhere else to name. Every state access goes through `cek_paths`, so the same
containment guard and cross-process locks the hooks use apply unchanged.

---

## Client configuration

Replace `/path/to/context-engineering-kit` and `/path/to/your-project`
throughout.

### Warp

Settings → AI → Manage MCP servers → `+ Add`:

```json
{
  "context-engineering-kit": {
    "command": "python3",
    "args": ["/path/to/context-engineering-kit/scripts/cek_mcp.py"],
    "env": { "CEK_MCP_PROJECT_DIR": "/path/to/your-project" },
    "start_on_launch": true
  }
}
```

Pair it with an `AGENTS.md` in the project root telling the agent to call
`handover_read` at the start of a session — Warp reads `AGENTS.md` (all caps)
automatically from the repo root and the current subdirectory.

### Claude Code

```bash
claude mcp add context-engineering-kit \
  --env CEK_MCP_PROJECT_DIR=/path/to/your-project \
  -- python3 /path/to/context-engineering-kit/scripts/cek_mcp.py
```

Claude Code already runs the kit as hooks. Adding the server too is only useful
if you want the model to be able to read and write the handover on request
mid-session.

### Cursor — `.cursor/mcp.json`

```json
{
  "mcpServers": {
    "context-engineering-kit": {
      "command": "python3",
      "args": ["/path/to/context-engineering-kit/scripts/cek_mcp.py"],
      "env": { "CEK_MCP_PROJECT_DIR": "/path/to/your-project" }
    }
  }
}
```

### Codex — `~/.codex/config.toml`

```toml
[mcp_servers.context-engineering-kit]
command = "python3"
args = ["/path/to/context-engineering-kit/scripts/cek_mcp.py"]
env = { CEK_MCP_PROJECT_DIR = "/path/to/your-project" }
```

### Antigravity CLI

Use `/mcp` in the CLI, or add an `mcp_config.json` to a plugin bundle:

```json
{
  "mcpServers": {
    "context-engineering-kit": {
      "command": "python3",
      "args": ["/path/to/context-engineering-kit/scripts/cek_mcp.py"],
      "env": { "CEK_MCP_PROJECT_DIR": "/path/to/your-project" }
    }
  }
}
```

On Antigravity this is **load-bearing, not a convenience**: there is no
compaction hook, so `handover_write` called before a long task is the only way
state survives.

### opencode — `opencode.json`

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "context-engineering-kit": {
      "type": "local",
      "command": ["python3", "/path/to/context-engineering-kit/scripts/cek_mcp.py"],
      "enabled": true,
      "environment": { "CEK_MCP_PROJECT_DIR": "/path/to/your-project" }
    }
  }
}
```

opencode also has a full plugin adapter (README Option G) which saves
automatically — prefer that.

### Cline / Continue / Goose / Zed and others

All take the same three things. Whatever the file is called, it reduces to:

```json
{
  "command": "python3",
  "args": ["/path/to/context-engineering-kit/scripts/cek_mcp.py"],
  "env": { "CEK_MCP_PROJECT_DIR": "/path/to/your-project" }
}
```

These four are listed because they speak MCP, **not because the kit has been
tested in them.** The protocol surface is verified (see below); the individual
clients are not.

---

## Verifying it works

The repo's own client:

```bash
python3 scripts/eval_mcp.py
```

Or the official inspector, which is a genuinely independent check:

```bash
npx -y @modelcontextprotocol/inspector --cli python3 scripts/cek_mcp.py --method tools/list
npx -y @modelcontextprotocol/inspector --cli python3 scripts/cek_mcp.py \
  --method tools/call --tool-name context_health
```

`context_health` is the tool to call when something seems wrong — it reports
whether state writes are permitted in this directory, whether a handover exists
and how stale it is, and whether the server is read-only.

## Protocol version

The server implements `2025-06-18` and also accepts `2025-03-26` and
`2024-11-05`. A client asking for anything else is negotiated down to
`2025-06-18`, per the lifecycle spec — verified against the official inspector,
which requests `2025-11-25` and connects fine.
