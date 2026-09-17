# context-engineering-kit v3.3.0

**Date:** 2026-09-17
**Tag:** `v3.3.0`
**Artifact:** `context-engineering-kit-3.3.0.zip` (build with `python scripts/package_plugin.py`)

Phase 2 of the [v4.0 universal-runtime plan](PLAN_v4_universal_runtime.md):
**opencode**. The fifth runtime, and the first whose extension surface is not a
JSON hook file.

Existing runtimes are untouched — Codex, Grok and Cursor configs regenerate
byte-identical. Drop-in upgrade.

---

## Why opencode was moved ahead of Antigravity

The plan originally had Antigravity CLI as Phase 2, on the strength of a
"cheapest new runtime, highest parity" claim that turned out to be about a
product Google had already shut down. Re-derived from the real docs, Antigravity
has five events and none of them are session events. opencode has the full
session lifecycle, is open source, and can do something no other supported
runtime can.

## The compaction hook

Everywhere else, the kit writes `session_handover.md` before compaction and
hopes the summariser keeps what matters. opencode's
`experimental.session.compacting` lets a plugin write into the **compaction
prompt itself**:

```
session_handover.md ──► output.context.push(...) ──► compaction prompt
```

The handover becomes part of what the continuation is built from, rather than a
file sitting next to a conversation that has already been summarised.

`output.prompt` is deliberately **not** set. Assigning it replaces opencode's
entire compaction prompt and causes `output.context` to be ignored; replacing a
runtime's summarisation strategy wholesale is not this kit's business. An eval
asserts it stays untouched.

## One core, still

`.opencode/plugins/cek.ts` is a translator with no policy in it. Each opencode
event becomes the Claude-shaped snake_case JSON the shared core already reads,
and `.opencode/hooks/run.sh` dispatches it exactly as the Codex and Grok
adapters do. Writing a second logic core in TypeScript was the alternative, and
duplicating the core is how this repo ended up with two copies of `skills/`
before v3.0.0.

Adding the runtime took what Phase 1 promised: a registry entry, an adapter, and
`"opencode"` added to the `runtimes` list on the applicable wiring entries. The
capability matrix grew its opencode column automatically.

## Differences from Claude Code, and why

| | |
|---|---|
| **No `UserPromptSubmit`** | Nothing documented fires between prompt submission and the model seeing it. The usage sentinel runs at **turn end** (`session.idle`), so 85%/92% thresholds are evaluated once per turn. Atomic sentinel claims make running it from a different point in the loop safe. |
| **No subagent events** | Subagent tracking and the mid-flight grace period are inactive. |
| **Permission events unwired** | opencode emits `permission.asked` / `permission.replied`, but their payloads are not documented field-by-field. Guessing at a payload is how the Grok adapter was inert for months. Left unwired deliberately. |
| **Blocking is a thrown Error** | `tool.execute.before` blocks by throwing, not by exit code. `cek.ts` converts the core's `exit 2` into that throw, so `guard-dangerous.sh` behaves identically without knowing anything about opencode. |

## npm

`.opencode/package.json` declares `opencode-context-engineering-kit`, but the
**supported install today is the local plugin directory**. `cek.ts` shells out
to the kit's core under `.claude/hooks/` and `scripts/`, so an npm install has
to vendor those or point `CEK_ROOT` at a checkout. The plugin logs loudly on
stderr and deactivates rather than pretending to work when it cannot find the
core — a context-preservation tool that silently does nothing is worse than one
that is absent, because the user believes their state is being saved.

---

## Evals

144 → 155. A new harness, `scripts/eval_opencode.mjs`, implements the exact
Bun-shell subset `cek.ts` uses (tagged template, `< ${Response}` stdin
redirection, `.env` / `.cwd` / `.nothrow` / `.quiet`) and spawns a **real
bash** — so it covers the whole path from opencode event through the TS mapping
and `run.sh` to state on disk. It is skipped, not failed, when no Node is
present; nothing else in this kit needs one.

**What it does not cover is Bun itself.** A green run means "the mapping is
right", not "verified on Bun".

### Two bugs the harness caught precisely because it is not Bun

Both were Bun-only APIs used where a standard one exists, and both failed
silently off Bun:

1. **`import.meta.dir`** — undefined outside Bun, so kit-root resolution
   returned null and the plugin registered no hooks at all. Now
   `import.meta.url` + `fileURLToPath`, which works in Bun too.
2. **`Bun.file()`** — threw under Node *inside a `try/catch` that swallowed it*,
   so the compaction injection silently never happened. That is the worse of
   the two: the handover was still written, the hook still ran, and everything
   looked fine. Now `readFileSync` from `node:fs`, and the catch logs instead of
   swallowing.

An eval now fails if `cek.ts` reaches for a Bun-only API outside a comment.

Every new assertion was negative-controlled against a reintroduced break:

| Control | Eval that caught it |
|---|---|
| `run.sh` stops propagating exit 2 | `opencode run.sh swallowed the deny: rc=0` |
| Compaction stops injecting the handover | `opencode plugin evals` |
| Plugin overwrites `output.prompt` | `opencode plugin evals` |
| `cek.ts` reintroduces a Bun-only API | `cek.ts uses a Bun-only API outside a comment` |
