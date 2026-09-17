# Runtime capability matrix (Phase C)

context-engineering-kit keeps **one logic core** under `.claude/hooks/*.sh`.
Thin adapters set `CLAUDE_PROJECT_DIR` / `CEK_RUNTIME` and dispatch into that core.

| Runtime | Config entrypoint | Adapter | Notes |
|---------|-------------------|---------|--------|
| **Claude Code** | `hooks/hooks.json` (plugin) + `.claude/settings.json` (project) | direct | Full event set; injects SessionStart / UserPromptSubmit stdout into context |
| **Cursor** | `.cursor/hooks.json` | `.cursor/hooks/*.sh` → `cek_runtime.sh` | camelCase events; `sessionStart` injects via JSON `additional_context`, everything else → stderr |
| **Codex** | `.codex/hooks.json` (project) + `.codex-plugin/plugin.json` → `hooks/codex-hooks.json` (plugin) | `.codex/hooks/run.sh` | Portable relative commands only. The plugin manifest **must** name its hooks file — Codex otherwise defaults to `hooks/hooks.json`, the Claude manifest |
| **Grok Build** | `.grok/hooks/cek-hooks.json`; Grok also reads `.claude/settings.json` and `.cursor/hooks.json` | `.grok/hooks/run.sh` | **camelCase payload** — the adapter normalises it to the core's snake_case. `PreToolUse` is the only blocking event (exit 2 denies); everything else fails open. No `async` in its schema |

## One registry, generated everywhere

Since v3.2.0 there is exactly one copy of the runtime facts:
**`config/runtime_events.json`**. It records, per runtime, the events emitted
and what that runtime calls them, plus payload casing, async support, timeout
defaults and ceilings, the config file to generate — and a `source` URL with a
`verified` date.

Three things read it, and nothing else carries a second copy:

| Consumer | Uses it for |
|---|---|
| `scripts/generate_runtime_hooks.py` | emits `.codex/hooks.json`, `hooks/codex-hooks.json`, `.grok/hooks/cek-hooks.json`, `.cursor/hooks.json`, and the table below |
| `cek_runtime_supports()` in `scripts/cek_runtime.sh` | runtime no-ops at hook time |
| this document | the generated block below |

```bash
python scripts/generate_runtime_hooks.py
python scripts/generate_runtime_hooks.py --check   # CI / pre-commit
```

Generation **fails** if the wiring table names an event a runtime does not
emit. `--check` alone never caught that: it only proves the generated files
match the generator, so `.codex/hooks.json` shipped `PostToolUseFailure`,
`StopFailure` and `Notification` — none of which Codex has — while staying
green. Timeout ceilings are enforced the same way (Codex caps `SessionEnd` and
`Interrupt` at 3s).

**Cursor is now inside that boundary.** `.cursor/hooks.json` was hand-written
until v3.2.0 and Cursor appeared in no allow-list, so the guard that caught the
Codex mistake could never fire for it. One caveat the generator encodes: Cursor's
`matcher` is not a tool-name filter — on `beforeShellExecution` it matches the
command *text* — so canonical matchers are never emitted for Cursor.

`hooks/hooks.json`, the Claude manifest, is deliberately **not** generated:
Claude Code is the reference runtime, its manifest carries events no other
runtime has, and its per-event `async` choices are policy rather than
capability. It is validated against the registry instead, so an event that
Claude Code does not emit cannot sit in it unnoticed.

**Re-verified 2026-09-17** — Codex against `learn.chatgpt.com/docs/hooks`, Grok
against `docs.x.ai/build/features/hooks` (page dated 2026-07-02). Both event sets
match the columns below **exactly**; no drift since the 2026-09-13 check. Grok's
payload is **camelCase** (`hookEventName`, `toolName`, `toolInput`), not the
Claude snake_case the shared core reads, and `async` is not in its schema.

The re-verification did surface three things this document had wrong or missing:

1. **Grok runs `.cursor/hooks.json` too** — a live double-fire. See the
   correction under the install checklist below.
2. **Codex spills large hook output.** Model-visible hook output over roughly
   2,500 tokens is written to `<temp_dir>/hook_outputs/<session_id>/<uuid>.txt`
   and replaced with a head-and-tail preview. The per-handler
   `additionalContextLimit` field tunes that threshold. The kit's SessionStart
   banner is the handler that gets near the line.
3. **Grok's default hook timeout is 5 seconds**, not 30. Only the `SessionEnd`
   entry sets an explicit timeout, so every other Grok hook — including the
   `session-start` chain — runs against a 5s budget. `session-end.sh` already
   detaches its work; the session-start chain has not been profiled against
   that ceiling.

Why Gemini CLI is not in this table: Google shut it off on **2026-06-18** with no
grace period, replaced by Antigravity CLI (`agy`). This kit never shipped a
Gemini adapter, and Antigravity support is planned, not built — see
`PLAN_v4_universal_runtime.md` Phase 3 for its five-event surface and the
session/compaction gaps that follow from it.

---

## Event support

<!-- BEGIN GENERATED: event-support -->
<!-- regenerate: python scripts/generate_runtime_hooks.py -->

| Event | Claude Code | Cursor | Codex | Grok Build | opencode | Kit hook / chain |
|-------|:------:|:------:|:------:|:------:|:------:|------------------|
| Setup | ✅ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| SessionStart | ✅ | ✅ | ✅ | ✅ | ✅ | `session-start` chain + `compact-restore.sh` + `session-title.sh` |
| SessionEnd | ✅ | ✅ | ✅ | ✅ | ✅ | `session-end.sh` |
| UserPromptSubmit | ✅ | ✅ | ✅ | ✅ | ❌ | `usage-sentinel.sh` |
| UserPromptExpansion | ✅ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| PreToolUse | ✅ | ✅ | ✅ | ✅ | ✅ | `guard-dangerous.sh` |
| PostToolUse | ✅ | ✅ | ✅ | ✅ | ✅ | `track-changes.sh` |
| PostToolUseFailure | ✅ | ✅ | ❌ | ✅ | ❌ | `post-tool-failure.sh` |
| PostToolBatch | ✅ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| PermissionRequest | ✅ | ❌ | ✅ | ❌ | ❌ | `auto-approve-permissions.sh` |
| PermissionDenied | ✅ | ❌ | ❌ | ✅ | ❌ | `permission-denied.sh` |
| Stop | ✅ | ✅ | ✅ | ✅ | ✅ | `stop` chain |
| StopFailure | ✅ | ❌ | ❌ | ✅ | ✅ | `stop-failure.sh` |
| Notification | ✅ | ❌ | ❌ | ✅ | ❌ | `notify.sh` |
| TaskCreated | ✅ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| TaskCompleted | ✅ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| TeammateIdle | ✅ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| SubagentStart | ✅ | ✅ | ✅ | ✅ | ❌ | `subagent-start` chain |
| SubagentStop | ✅ | ✅ | ✅ | ✅ | ❌ | `subagent-stop` chain |
| PreCompact | ✅ | ✅ | ✅ | ✅ | ✅ | `pre-compact.sh` |
| PostCompact | ✅ | ❌ | ✅ | ✅ | ✅ | `post-compact.sh` |
| PreModelSwitch | ✅ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| PostModelSwitch | ✅ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| InstructionsLoaded | ✅ | ❌ | ❌ | ❌ | ❌ | `instructions-loaded.sh` (Claude only) |
| ConfigChange | ✅ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| CwdChanged | ✅ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| DirectoryAdded | ✅ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| WorktreeCreate | ✅ | ❌ | ❌ | ❌ | ❌ | **deliberately not wired** — see below |
| WorktreeRemove | ✅ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| FileChanged | ✅ | ❌ | ❌ | ❌ | ❌ | `config-changed.sh` (Claude only) |
| Interrupt | ❌ | ❌ | ✅ | ❌ | ❌ | `native-event-log.sh` |

Cursor-native events with no canonical equivalent, wired anyway:

| Cursor event | Adapter |
|---|---|
| `afterAgentResponse` | `on-agent-response.sh` |
| `beforeReadFile` | `guard-read.sh` |

| Runtime | Source | Verified |
|---|---|---|
| Claude Code | https://code.claude.com/docs/en/hooks | 2026-09-17 |
| Cursor | https://cursor.com/docs/hooks | 2026-09-17 |
| Codex | https://learn.chatgpt.com/docs/hooks | 2026-09-17 |
| Grok Build | https://docs.x.ai/build/features/hooks | 2026-09-17 |
| opencode | https://opencode.ai/docs/plugins/ | 2026-09-17 |

<!-- END GENERATED: event-support -->


`cek_runtime_supports <Event>` in `scripts/cek_runtime.sh` answers from the same
registry — it used to carry its own copy as four nested `case` statements. It
answers "does this runtime emit this event", **not** "does the kit wire it":
`WorktreeCreate` is supported by Claude Code and still absent from
`hooks/hooks.json` on purpose. It reads the registry with `jq`, falls back to
Python, and **fails open** if neither is available — a capability hint that
wrongly answers "no" silently disables real handlers, while a wrong "yes" costs
one no-op hook run.

### Grok speaks camelCase

Grok's hook payload is `hookEventName` / `sessionId` / `cwd` / `workspaceRoot` /
`toolName` / `toolInput`. The shared core under `.claude/hooks/` reads the Claude
snake_case names — `.tool_input` in seven places, `.transcript_path` in six,
`.file_path` in six, `.session_id` in five. Every one of those resolved to empty
on Grok, which meant `guard-dangerous.sh` could not see the command it exists to
inspect: the only blocking event Grok has was inert regardless of exit codes.

`.grok/hooks/run.sh` now normalises the payload before dispatch, additively — the
camelCase keys stay, snake_case aliases are added only where absent, so a future
Grok that sends both keeps working. Environment detection already matched
(`GROK_SESSION_ID` is one of the documented variables).

### Cursor-native hooks the kit uses

Three Cursor hooks have no Claude Code counterpart, so they are not rows in the
table above:

| Cursor hook | Adapter | Why |
|---|---|---|
| `afterAgentResponse` | `on-agent-response.sh` | Carries `text`, the final assistant message. Cursor's `stop` payload is only `{status, loop_count}` and its transcript is not in the Claude JSONL shape, so `next_action` extraction was effectively dead on Cursor without this |
| `beforeReadFile` | `guard-read.sh` (`failClosed: true`) | Enforces the `.env` rule in `.claude/rules/security.md`. Claude Code gets this from `deny: Read(./.env)` in settings.json; Cursor has no equivalent config, so the rule was documentation only |
| `preCompact` | `on-precompact.sh` | Supplies `context_usage_percent`, `context_tokens` and `context_window_size`. `pre-compact.sh` prefers that over its own estimate — snapshots used to be stamped `ctx=unknown%` on every runtime. The adapter returns the kit banner as `{"user_message": …}`, which Cursor shows when compaction fires; it used to go to stderr, where only the Hooks output channel saw it |

Cursor's `sessionStart` also accepts a JSON response with `additional_context`,
which is added to the conversation's initial system context. The adapter returns
the kit banner that way, so Cursor sessions start with the same handover state
Claude Code sessions get. Raw stdout is *not* injected — the JSON shape is
required.

**Deliberately unused, not overlooked.** On Cursor: `preToolUse` / `postToolUse`
duplicate coverage the kit already gets from `beforeShellExecution` and
`afterFileEdit`; `beforeMCPExecution` and `afterShellExecution` are governance
surfaces this kit has no policy for; `workspaceOpen` fires outside any session,
where there is no session state to maintain; the Tab hooks cover inline
completions, which never touch context state. On Claude Code: `MessageDisplay`
(10s budget on a per-message event), `Elicitation` / `ElicitationResult` (MCP
input, not context), and `WorktreeCreate` (see below). Wiring any of these would
add per-event cost for no handover benefit.

### Why `WorktreeCreate` is not wired

Configuring a `WorktreeCreate` hook **replaces** Claude Code's default
`git worktree` behaviour: the hook itself has to create the working copy and
print its path as the last non-empty line of stdout, and `.worktreeinclude` stops
being processed. A logging-only handler prints no path, which breaks
`claude --worktree`, subagents with `isolation: "worktree"`, and background
sessions for every project the plugin is installed in.

The kit has no reason to replace git here, so the event stays unwired. Do not
add it back for observability — `WorktreeRemove` is the safe half of the pair
(Claude Code discards its output) and is already wired.

---

## Double-fire risk (Grok + Claude settings)

Grok **merges** project `.claude/settings.json` and `.grok/hooks/*.json` when the
folder is trusted. Since v3.0.0 `.claude/settings.json` declares **no hooks**
(the plugin manifest `hooks/hooks.json` is the single Claude source), so nothing
double-fires. Atomic usage sentinels (Phase A) additionally guarantee the
85%/92% save runs once per window.

---

## Commands this kit names, and where each is documented

Every command referenced in the README, `AGENTS.md`, this file or a `SKILL.md`,
with its source. A previous sweep deleted a real command (`/hooks-trust`)
because one incomplete read had not surfaced it, while leaving an invented one
in place — so the evidence lives here rather than in anyone's memory.

| Command | Runtime | Documented at |
|---|---|---|
| `/clear` `/compact` `/rewind` `/fast` `/model` `/resume` `/hooks` `/config` `/permissions` | Claude Code | `code.claude.com/docs/en/commands` |
| `/handover` `/token-status` `/compact-smart` `/context-health` `/model-switch` `/session-sync` `/usage-forecast` `/morning-brief` `/init-cek` | Claude Code | **this repo** — `skills/<name>/SKILL.md` defines each |
| `/context-engineering-kit:<skill>` | Claude Code | plugin-scoped form for the same skills |
| `/skills`, `$<skill>` | Codex | `learn.chatgpt.com/docs/build-skills` |
| `/hooks` | Codex | `learn.chatgpt.com/docs/hooks` |
| `/hooks-trust`, `--trust` | Grok | `docs.x.ai/build/features/hooks` |
| `/hooks` tab (extensions modal) | Grok | same |

**Asserted before and now removed as undocumented:**

| Claim | Why it went |
|---|---|
| `[compat.claude] hooks = false` in `~/.grok/config.toml` | No such setting appears in Grok's hooks documentation. Grok reads `.claude/settings.json` and `.cursor/hooks.json`; nothing documents turning that off |
| `$context-engineering-kit:<skill>` on Codex | Codex documents `/skills` and typing `$` to mention a skill. Whether a plugin namespaces its bundled skills is unstated — use the bare name |

Cursor has no slash-command surface for skills; state the task in prose.

---

## Environment contract

Adapters must export before calling `.claude/hooks/*`:

| Variable | Purpose |
|----------|---------|
| `CEK_ROOT` | Absolute project/kit root |
| `CEK_RUNTIME` | `claude` \| `cursor` \| `codex` \| `grok` |
| `CLAUDE_PROJECT_DIR` | Same as CEK_ROOT for standalone |
| `CLAUDE_PLUGIN_ROOT` | Plugin root or CEK_ROOT |
| `CLAUDE_HOOK_EVENT` | `SubagentStart` / `SubagentStop` when needed |

---

## Install checklist

**Claude Code** — open the project (settings auto-load) or install the plugin.

**Cursor** — open the project in a **trusted** workspace; `.cursor/hooks.json` is
picked up automatically and reloads on save. Cloud agents run these project
hooks too, except `sessionStart` / `sessionEnd` / the MCP hooks, which Cursor
defers there.

**Codex** — two supported modes:

- *Plugin* — install from a marketplace entry; `.codex-plugin/plugin.json` names
  `./hooks/codex-hooks.json`, whose commands resolve under `${CLAUDE_PLUGIN_ROOT}`.
  Codex also reads the repo's existing `.claude-plugin/marketplace.json` as a
  legacy-compatible marketplace.
- *Project adapter* — ensure the repo root is the cwd; `.codex/hooks.json` is
  portable. Do **not** commit machine-local absolute paths.

Either way, run `/hooks` once to review and trust the hooks: installing or
enabling a plugin does not trust its hooks, and Codex records trust against each
hook's hash, so a changed hook needs re-approval.

**Grok** — project hooks require trust before they run: grant it with
`/hooks-trust` the first time you open the repo, or launch with `--trust`. The
decision is stored in `~/.grok/trusted_folders.toml`. Inspect what loaded in the
`/hooks` tab of the extensions modal. Note Grok also reads
`.claude/settings.json` **and** `.cursor/hooks.json`, so this repo ships three
files it may load. `.claude/settings.json` declares no hooks since v3.0.0. The
Cursor file **does** fire — see the correction below. There is **no documented
setting** to disable that compatibility scan — earlier versions of this README
suggested one, which was invented.

### Correction (2026-09-17): the Cursor file fires on Grok

This document previously claimed `.cursor/hooks.json` "uses Cursor-only event
names, so `cek-hooks.json` is the only set that fires." That is backwards.
`docs.x.ai/build/features/hooks`, verbatim:

> Claude Code (`.claude/settings.json`) and Cursor (`.cursor/hooks.json`) hook
> files are read as well, **including Cursor's camelCase event names**.

`.cursor/hooks.json` declares `sessionStart`, `sessionEnd`, `beforeSubmitPrompt`,
`beforeShellExecution`, `afterFileEdit`, `beforeReadFile`, `afterAgentResponse`,
`stop`, `postToolUseFailure`, `subagentStart`, `subagentStop` and `preCompact` —
all names Grok reads. So a Grok session in a repo carrying this kit was running
`cek-hooks.json` **and** all eleven Cursor adapters: two session-start chains,
two stop chains (`usage-tracker.py` twice per turn), two pre-compact snapshot
commits. The same double-fire class v3.0.0 removed from `.claude/settings.json`,
re-entering through a different door.

Fixed in `.cursor/hooks/_common.sh`: Grok exports `GROK_HOOK_EVENT` /
`GROK_HOOK_NAME` / `GROK_SESSION_ID` / `GROK_WORKSPACE_ROOT` into every hook
process and Cursor never sets them, so the bootstrap every adapter sources
exits early when it sees them. `eval_phase_c.sh` asserts both halves: all
adapters defer under `GROK_*`, and all still run without it.
