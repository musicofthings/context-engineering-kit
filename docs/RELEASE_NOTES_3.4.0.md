# context-engineering-kit v3.4.0

**Date:** 2026-09-18
**Tag:** `v3.4.0`
**Artifact:** `context-engineering-kit-3.4.0.zip` (build with `python scripts/package_plugin.py`)

Phase 4 of the [v4.0 universal-runtime plan](PLAN_v4_universal_runtime.md):
**`cek-mcp`**, a stdio MCP server that makes the kit's state reachable from any
agent speaking Model Context Protocol.

Phase 3 (Antigravity CLI) is deliberately skipped for now — this reaches
Antigravity too, and reaches Warp, Cline, Continue, Goose and Zed at the same
cost. The plan's version numbering shifts accordingly.

Nothing existing changes. Adapters, hooks and configs are untouched.

---

## What this is, and what it is not

Hooks give **guaranteed execution** on the five runtimes that have them. MCP
gives **reachable state** everywhere else. Those are not the same thing, and the
difference is stated everywhere it could mislead — in the README, in
`docs/mcp-setup.md`, in the server's own `instructions` string, and in the text
`handover_write` returns after a successful save:

> Note: this is an on-request save. Unlike the hook-driven runtimes there is no
> automatic save at the 85%/92% usage thresholds here.

The model has to *choose* to call a tool. There is no save at 85% and none
before compaction. Where an adapter exists, install the adapter.

Where this is the only option:

| Runtime | Why |
|---|---|
| **Warp** | No hook mechanism at all (`warpdotdev/warp#6857`, open since Jul 2025) |
| **Antigravity CLI** | Five events, none of them session or compaction events |
| **Cline, Continue, Goose, Zed** | No adapter here; MCP is the shared surface |

Those four are listed because they speak MCP, **not because the kit has been
tested in each.** The protocol surface is verified; the individual clients are
not, and saying otherwise would be the same mistake as the Gemini CLI row.

## Stdlib only, on purpose

The kit's core is dependency-free — `requirements.txt` carries one optional
package for a feature that is off by default. A universal floor that requires
`pip install mcp` is not a floor, so the JSON-RPC loop is hand-written against
the spec (`modelcontextprotocol.io/specification/2025-06-18`, read 2026-09-18).
An eval fails if `cek_mcp.py` ever grows a third-party import.

The protocol surface used is small: newline-delimited JSON-RPC 2.0 over
stdin/stdout, `initialize` / `tools/list` / `tools/call` / `ping`.

## Tools

| Tool | Reads | Writes |
|---|:---:|:---:|
| `handover_read` | ✅ | |
| `handover_write` | | ✅ |
| `state_get` | ✅ | |
| `usage_status` | ✅ | |
| `context_health` | ✅ | |
| `session_sync` | ✅ | ⚠️ gated |

`handover_write` takes `active_task`, `phase` and `next_action`, records them
through `cek_paths`, and regenerates `session_handover.md`. On a runtime without
hooks that is the entire save path.

## Security model

This server hands write access to whatever model is driving the client, so the
boundaries are explicit:

1. **No tool accepts a path.** The project directory is read from the
   environment at launch (`CEK_MCP_PROJECT_DIR` → `CLAUDE_PROJECT_DIR` → cwd)
   and cannot be redirected by a tool argument. A prompt-injected model has
   nowhere else to name. An eval fails if any tool schema grows a
   path/dir/file/cwd property.
2. **All state access goes through `cek_paths`**, so the containment guard and
   the cross-process locks apply unchanged. This server adds no new way to reach
   state.
3. **`state_get` returns a whitelist**, not whatever `state.json` has
   accumulated.
4. **`CEK_MCP_READONLY=1`** hides *and* refuses every mutating tool.
5. **`session_sync` is status-only by default.** Its `save` mode commits **and
   pushes**; `load` runs `git pull --rebase --autostash` over the working tree.
   Both are outward-facing and hard to reverse, so they require an explicit
   `CEK_MCP_ALLOW_GIT=1` rather than sitting one model decision away. The
   refusal message says exactly what each mode would do and how to run it
   yourself.

---

## Evals

155 → 183. `scripts/eval_mcp.py` launches the server as a subprocess and drives
it as a real client: lifecycle, version negotiation, notification handling,
tool schemas, every security boundary.

**Independently verified.** The official `@modelcontextprotocol/inspector`
connects, lists all six tools, calls them, and receives the gated refusal for
`session_sync save`. It requests protocol version `2025-11-25` — newer than the
spec page this was written against — and the server negotiates down to
`2025-06-18` exactly as the lifecycle spec requires. That is a third-party
client agreeing with the implementation, not the implementation agreeing with
its own test client.

```bash
python3 scripts/eval_mcp.py
npx -y @modelcontextprotocol/inspector --cli python3 scripts/cek_mcp.py --method tools/list
```

### The control that did not fire

Five security boundaries were negative-controlled. Four failed immediately when
broken. The fifth — removing the containment guard from the write path — **kept
passing**, because `state_update` inside `cek_paths` refuses independently, so
the assertion was satisfied by the second layer and proved nothing about the
first.

Defence in depth is good; an eval that cannot tell which layer held is not. The
gap behind it was real: `handover_write` with **no arguments** never reaches
`state_update` at all, so the guard is the only thing between the model and a
handover written outside a project. An assertion for that case was added, and
with the guard removed it now fails with a handover written into a non-git temp
directory — which is exactly what it should catch.

This is the second time in this line of work that an eval passed for the wrong
reason (Phase 1 had the same shape). Both were found by controlling the
guarantee rather than trusting a green run.
