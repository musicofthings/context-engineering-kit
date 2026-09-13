# context-engineering-kit v3.1.0

**Release date:** 2026-09-13  
**Tag:** `v3.1.0`  
**Artifact:** `context-engineering-kit-3.1.0.zip` (build with `python scripts/package_plugin.py`)

Every gap the v3.0.0 notes listed as *known* is now closed. No breaking changes.

The headline is that Grok finally got verified against a published spec instead
of inferred from Claude's — and the inference had been wrong in a way that made
Grok's only security control inert.

---

## Grok: verified, and two inferences corrected

v3.0.0 shipped with Grok's column in the capability matrix marked
**unverified** — "mirrors the Claude schema in practice; treat additions as
provisional" — because no public hook spec had been found. One exists:
`docs.x.ai/build/features/hooks`.

**The event set was right.** All fourteen documented events match what the kit
already declared, exactly. That part of the inference held.

**The payload shape was not.** Grok sends camelCase:

```json
{ "hookEventName": "PreToolUse", "sessionId": "...", "cwd": "...",
  "workspaceRoot": "...", "toolName": "Bash", "toolInput": { ... } }
```

The shared core under `.claude/hooks/` reads the Claude snake_case names —
`.tool_input` in seven places, `.transcript_path` in six, `.file_path` in six,
`.session_id` in five. On Grok every one of those resolved to empty.
`guard-dangerous.sh` could not see the command it exists to inspect.

Combined with the second issue, that made Grok's guard doubly inert:
**`PreToolUse` is the only blocking event on Grok** (exit 2 denies, reason on
stderr; everything else is passive and fails open) — and the adapter's blanket
`|| true` turned that 2 into a 0. This is the same defect as CEK-CODEX-002, left
open in v3.0.0 only because the exit-code contract could not be confirmed. It
now can, and it is fixed the same way.

`.grok/hooks/run.sh` normalises the payload before dispatch, additively: the
camelCase keys stay, snake_case aliases are added only where absent, so a Grok
that later sends both keeps working.

Two smaller corrections from the same spec:

- **`async` is not in Grok's schema** (`matcher`, `type`, `command`, `url`,
  `timeout`). The generator had been emitting it on four entries; it no longer
  does, and the generator now tracks async support per runtime.
- **Grok reads `.claude/settings.json` and `.cursor/hooks.json`**, both of which
  this repo ships. Neither fires — the first declares no hooks since v3.0.0, the
  second uses Cursor-only event names — but that is now stated rather than
  assumed.

Removed while here: `/hooks-trust`, a Grok command the README, the capability
matrix and `AGENTS.md` all asserted. It does not appear in the documentation.
The install notes now describe trusting the project without naming a command
that may not exist.

## `SessionEnd` no longer commits on `/clear` and `/resume`

`SessionEnd` fires on `clear`, `resume`, `logout`, `prompt_input_exit` and
`other`. The kit treated all five as the session ending, so clearing context
mid-task produced a `chore(context): save session state` commit.

State is still written on every reason — `/clear` is precisely when losing it
hurts. Only the commit is gated now.

## `AGENTS.md` is runtime-neutral, and `init-cek` respects yours

v3.0.0 made Codex able to *find* `AGENTS.md`; its contents still assumed Claude
Code. The agent roles and communication protocol are now harness-neutral, with
runtime specifics confined to a *Runtime mechanics* table and the invocation
section.

`init-cek` now creates `AGENTS.md`, and **never overwrites one that has
substantive content — not even with `--force`**. It also detects a lowercase
`agents.md` and renames it through a temporary name, rather than writing a
second file that only appears on case-sensitive systems.

## CI packages the plugin and actually installs it

Manifest validation proved the JSON parsed. It could not prove what a user does.

`scripts/eval_codex_install.sh` packages the plugin, unpacks it to a separate
plugin root, and drives its hooks against an unrelated git project — from the
project root *and* from a nested subdirectory, since Codex may start below it.
20 checks: packaging completeness, the manifest never inheriting
`hooks/hooks.json`, only Codex-implemented events declared, commands resolving
under `${CLAUDE_PLUGIN_ROOT}`, state landing in the project rather than the
plugin root, the guard still denying with exit 2 through the installed copy, and
the 3-second `SessionEnd` ceiling.

It runs on Ubuntu and macOS.

## Codex `Interrupt`

Wired to the event logger. An interrupted turn is a handover concern: the next
session should know the last turn was cut off rather than completed. Passive,
and capped at Codex's 3-second ceiling.

---

## Test coverage

| Suite | v3.0.1 | v3.1.0 |
|---|---:|---:|
| `eval_phase_c` | 28 | **31** |
| `eval_usage_lifecycle` | 29 | 29 |
| `eval_hooks_smoke` | 67 | **70** |
| `eval_codex_install` | — | **20** |
| **Total** | 124 | **150** |

All green on Ubuntu, macOS (stock `/bin/bash` 3.2 under a UTF-8 locale), and
Windows.

## Upgrade

No steps. Reinstall the plugin or pull `main`.

If you use Grok, this is the release that makes the dangerous-command guard
actually work there. Before it, the guard ran and allowed everything.

## Install

**Plugin zip (Cowork / Desktop):** download `context-engineering-kit-3.1.0.zip`
from this release.

**CLI / Cursor / Grok / Codex:**
```bash
git clone https://github.com/musicofthings/context-engineering-kit.git
cd context-engineering-kit
bash setup.sh   # Claude CLI
```

## Verify
```bash
bash scripts/eval_phase_c.sh          # 31
bash scripts/eval_usage_lifecycle.sh  # 29
bash scripts/eval_hooks_smoke.sh      # 70
bash scripts/eval_codex_install.sh    # 20
```

## Docs
- Compatibility review, R-027..R-030: `docs/sota-compatibility-review-2026-09.md`
- Capability matrix (now with verified sources per runtime): `docs/runtime-capability-matrix.md`
- Previous releases: `docs/RELEASE_NOTES_3.0.1.md`, `docs/RELEASE_NOTES_3.0.0.md`

## What is deliberately not wired

Recorded so it is not mistaken for an oversight. On Cursor: `preToolUse` /
`postToolUse` duplicate coverage the kit already gets from
`beforeShellExecution` and `afterFileEdit`; `beforeMCPExecution` and
`afterShellExecution` are governance surfaces this kit has no policy for;
`workspaceOpen` fires outside any session, where there is no session state; the
Tab hooks cover inline completions, which never touch context. On Claude Code:
`MessageDisplay`, `Elicitation` / `ElicitationResult`, and `WorktreeCreate` —
the last for the reason in the capability matrix. Each would add per-event cost
for no handover benefit.
