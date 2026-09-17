# context-engineering-kit v3.1.2

**Date:** 2026-09-17
**Tag:** `v3.1.2`
**Artifact:** `context-engineering-kit-3.1.2.zip` (build with `python scripts/package_plugin.py`)

A re-verification release. Codex and Grok were last checked on 2026-09-13; the
Gemini CLI mistake in the v4 plan — citing a product Google had shut off three
months earlier — made it worth re-checking the other runtimes the same way,
starting with "does this still exist" rather than "what are its hooks".

**Neither event set has drifted.** Codex's 12 events and Grok's 14 still match
`RUNTIME_EVENTS` exactly. The re-check found one live bug and two documented
behaviours the kit had missed.

---

## Fixed

### Grok ran the Cursor hooks as well — a double-fire

`docs.x.ai/build/features/hooks`, verbatim:

> Claude Code (`.claude/settings.json`) and Cursor (`.cursor/hooks.json`) hook
> files are read as well, **including Cursor's camelCase event names**.

This repo claimed the opposite. From the README, before this release: *"the
second uses Cursor-only event names — so `cek-hooks.json` is the only set that
runs."* Exactly backwards. `.cursor/hooks.json` declares `sessionStart`,
`sessionEnd`, `beforeSubmitPrompt`, `beforeShellExecution`, `afterFileEdit`,
`beforeReadFile`, `afterAgentResponse`, `stop`, `postToolUseFailure`,
`subagentStart`, `subagentStop` and `preCompact` — every one a name Grok reads.

So a Grok session in any repo carrying this kit ran `cek-hooks.json` **and** all
eleven Cursor adapters:

- two `session-start` chains
- two `stop` chains, so `usage-tracker.py` twice per turn
- two `pre-compact` snapshot commits

This is the same double-fire class v3.0.0 removed from `.claude/settings.json`,
re-entering through a different door. The atomic sentinel claims meant the 85%
and 92% saves still ran once, which is why it was survivable rather than
obvious.

**Fixed** in `.cursor/hooks/_common.sh`, the bootstrap all eleven adapters
source as their first line. Grok exports `GROK_HOOK_EVENT`, `GROK_HOOK_NAME`,
`GROK_SESSION_ID` and `GROK_WORKSPACE_ROOT` into every hook process and Cursor
never sets them, so the runtime is unambiguous; the bootstrap exits before any
side effect when it sees them. `.grok/hooks/cek-hooks.json` is again the only
Grok source.

`eval_phase_c.sh` (31 → 33) asserts both halves, and both were negative-
controlled against the guard's removal:

- every Cursor adapter defers under `GROK_*`
- every Cursor adapter still runs without it, so the guard is not too broad

---

## Documented

Two Codex/Grok behaviours the kit had not accounted for. Neither is a bug today;
both constrain what an adapter may do.

### Codex spills large hook output

Model-visible hook output over roughly **2,500 tokens** is written to
`<temp_dir>/hook_outputs/<session_id>/<uuid>.txt` and replaced with a
head-and-tail preview plus the file path. The per-handler
`additionalContextLimit` field tunes the threshold. The SessionStart banner is
the kit's handler nearest that line — noted in the README's Codex section so
anyone extending it knows the ceiling exists.

### Grok's default hook timeout is 5 seconds, not 30

Only the `SessionEnd` entry sets an explicit timeout, so every other Grok hook —
including the `session-start` chain — runs against a 5s budget. `session-end.sh`
already detaches its work, so the documented risk is the session-start chain,
which has not been profiled against that ceiling. Recorded in the capability
matrix rather than fixed speculatively.

---

## Added

### README: Antigravity CLI compatibility and limitations

A new **Option G** section, marked **not yet supported**, covering what an
adapter can and cannot deliver so the wait is a judgement call rather than a
guess. Gemini CLI was sunset on **2026-06-18** with no grace period; this kit
never shipped a Gemini adapter, and Antigravity support is Phase 3 of the v4
plan.

The section is explicit about the gap that matters: Antigravity has **five**
lifecycle events and **none of them are session events**. No `SessionStart`, no
`SessionEnd`, no compaction event, no subagent events. Writing
`session_handover.md` before compaction — the single most valuable thing this
kit does — cannot be triggered by a hook there at all. The planned MCP server is
the fallback, and because the model must choose to call it, there is no
*guaranteed* save.

Also documented: the payload needs more translation than any adapter shipped so
far (camelCase, nested `toolCall.name`/`.args`, PascalCase argument keys,
Antigravity-specific tool names), decisions are JSON rather than exit 2, `Stop`
inverts the usual sense, the event name is absent from the payload, and the
binary is closed source where Gemini CLI was not.

---

## Unchanged

Everything in v3.1.1. Evals 135 → 137. No config format changes; drop-in
upgrade.
