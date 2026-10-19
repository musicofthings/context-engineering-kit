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
| `scripts/fetch_api_docs.py` | the six `source` URLs, appended to the weekly doc refresh |
| `scripts/check_runtime_doc_drift.py` | compares each runtime's event set against the page its `source` cites |
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

## What `--check` still cannot tell you, and what does

Everything above is internally consistent by construction. `--check` proves the
generated configs match the registry; `check_sync.sh` proves the wiring is
single-sourced. Neither reads a vendor page, so a registry entry that has
drifted away from the doc in its own `source` field stays green indefinitely —
which is exactly what happened. Antigravity shipped a native `SessionStart`,
the registry did not mention it, the kit went on synthesizing the event on
`PreInvocation` for a month, and every check in this repo passed throughout.
v4.0.1 found it by hand.

`scripts/check_runtime_doc_drift.py` is the check that would have found it:

```bash
python scripts/check_runtime_doc_drift.py              # fetch all six, compare
python scripts/check_runtime_doc_drift.py --offline     # no network, bookkeeping only
python scripts/check_runtime_doc_drift.py --runtime cursor
python scripts/eval_doc_drift.py                        # offline fixtures, incl. the v4.0.1 case
```

For each runtime it extracts the event names the vendor page documents and
compares that set against `events` + `native_extra` + `declined`. Because those
three lists must account for **every** event on the page, anything the page
lists and the registry does not mention is, by construction, an event nobody
has looked at.

| Finding | Meaning | Exit |
|---|---|---|
| `DEFECT` | the registry claims an event its own cited doc no longer lists, or its bookkeeping is self-inconsistent | 1 |
| `ADVISORY` | the doc lists an event the registry does not mention, a `declined` event has vanished, or `verified` is over 30 days old | 2 |
| `UNKNOWN` | a page could not be fetched or could not be parsed — **nothing was verified**, which is not the same as nothing being wrong | 3 |

The codes are distinct on purpose. A false claim in a committed file is this
repo's defect and fails CI. A vendor shipping an event is not, and a weekly job
that goes red every time one does is a job that gets muted — which is how
v4.0.1 happened in the first place. So 2 and 3 are loud and non-fatal:
annotations plus a step summary in the weekly workflow, and the drift report is
pasted into the body of the doc-refresh PR so it arrives where someone reviews
it. `--strict` collapses 2 and 3 into 1 for callers that want a hard gate.

Where a page is too irregular to parse, every extractor raises rather than
returning a partial set: a wrong answer here is indistinguishable from "no
drift", and a false clean bill of health is the failure being fixed.

The extractors live in `scripts/runtime_doc_events.py` — one declarative entry
per runtime naming the anchor heading and the shape of the list under it
(`headings`, `table`, `bullets`), because no two vendors present their events
the same way. `scripts/fixtures/runtime-docs/*.page.md` holds a trimmed excerpt
of each live page so the suite never needs the network. Those files are named
`<runtime>.page.md` and not `<runtime>.md` deliberately: a fixture called
`claude.md` is picked up by Claude Code's own `CLAUDE.md` discovery on a
case-insensitive filesystem, which would load a page of untrusted fetched vendor
text as project instructions.

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

**Antigravity CLI (`agy`) support:** Google shut off Gemini CLI on **2026-06-18**
with no grace period, replaced by Antigravity CLI (`agy`). Antigravity support
is implemented in `.agents/hooks/run.sh` with `.agents/hooks.json` generated.
Antigravity emits **six** events: `SessionStart`, `PreToolUse`, `PostToolUse`,
`PreInvocation`, `PostInvocation`, `Stop`. There are no compaction events, so
compaction context preservation is handled on-demand via `cek-mcp`.

**Corrected 2026-10-19 — `SessionStart` is native.** v3.5.0 through v4.0.0 read
this doc as a five-event surface and synthesized SessionStart on `PreInvocation`
when `invocationNum == 0`. The event exists, fires once before the first model
invocation, and returns `injectSteps` like `PreInvocation` does, so the
`session-start` chain now binds to it directly. `PreInvocation` keeps the usage
sentinel alone — Antigravity has no `UserPromptSubmit`, so that is the only
pre-model point where the thresholds can be evaluated. The synthesis also hid a
latent bug: the adapter's normaliser wrote a JSON `null` into `invocation_num`
whenever the payload lacked `invocationNum`, which reached the shell as the
string `"None"` and failed the numeric comparison, silently taking the
non-session branch. The normaliser now omits absent keys instead.


---

## Event support

<!-- BEGIN GENERATED: event-support -->
<!-- regenerate: python scripts/generate_runtime_hooks.py -->

| Event | Claude Code | Cursor | Codex | Grok Build | opencode | Antigravity CLI | Kit hook / chain |
|-------|:------:|:------:|:------:|:------:|:------:|:------:|------------------|
| Setup | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| SessionStart | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `session-start` chain + `compact-restore.sh` + `session-title.sh` |
| SessionEnd | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | `session-end.sh` |
| UserPromptSubmit | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | `usage-sentinel.sh` |
| UserPromptExpansion | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| PreToolUse | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `guard-dangerous.sh` |
| PostToolUse | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `track-changes.sh` |
| PostToolUseFailure | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | `post-tool-failure.sh` |
| PostToolBatch | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| PermissionRequest | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | `auto-approve-permissions.sh` |
| PermissionDenied | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | `permission-denied.sh` |
| Stop | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `stop` chain |
| StopFailure | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ | `stop-failure.sh` |
| Notification | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | `notify.sh` |
| MessageDisplay | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | _not wired_ |
| TaskCreated | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| TaskCompleted | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| TeammateIdle | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| SubagentStart | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | `subagent-start` chain |
| SubagentStop | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | `subagent-stop` chain |
| PreCompact | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | `pre-compact.sh` |
| PostCompact | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | `post-compact.sh` |
| PreModelSwitch | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| PostModelSwitch | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| Elicitation | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | _not wired_ |
| ElicitationResult | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | _not wired_ |
| InstructionsLoaded | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | `instructions-loaded.sh` (Claude only) |
| ConfigChange | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| CwdChanged | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| DirectoryAdded | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| WorktreeCreate | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | **deliberately not wired** — see below |
| WorktreeRemove | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | `native-event-log.sh` (Claude only) |
| FileChanged | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | `config-changed.sh` (Claude only) |
| Interrupt | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | `native-event-log.sh` |

Cursor-native events with no canonical equivalent, wired anyway:

| Cursor event | Adapter |
|---|---|
| `afterAgentResponse` | `on-agent-response.sh` |
| `beforeReadFile` | `guard-read.sh` |

Antigravity-native events with no canonical equivalent, wired anyway:

| Antigravity event | Action |
|---|---|
| `PreInvocation` | `pre-invocation` |

| Runtime | Source | Verified |
|---|---|---|
| Claude Code | https://code.claude.com/docs/en/hooks | 2026-10-19 |
| Cursor | https://cursor.com/docs/hooks | 2026-10-19 |
| Codex | https://learn.chatgpt.com/docs/hooks | 2026-10-19 |
| Grok Build | https://docs.x.ai/build/features/hooks | 2026-10-19 |
| opencode | https://opencode.ai/docs/plugins/ | 2026-10-19 |
| Antigravity CLI | https://antigravity.google/docs/hooks/ | 2026-10-19 |

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

**Cursor caps stop-hook reinvocation.** The per-script `loop_limit` field
defaults to **5** for Cursor hooks (and `null`, meaning no limit, for Claude Code
hooks), and applies to `stop` and `subagentStop`. The kit's `stop` chain writes
state and returns; it does not ask Cursor to continue, so the cap is never
reached. It would bind on any future handler that returns a continue decision.

Cursor's `sessionStart` also accepts a JSON response with `additional_context`,
which is added to the conversation's initial system context. The adapter returns
the kit banner that way, so Cursor sessions start with the same handover state
Claude Code sessions get. Raw stdout is *not* injected — the JSON shape is
required.

**Deliberately unused, not overlooked** — and since v4.1.0 recorded as such in
the registry, as `declined` on each runtime. "Not overlooked" used to be a claim
in this paragraph and nowhere else; the drift detector now reports any
documented event that is in neither `events`, `native_extra` nor `declined`, so
the distinction between a decision and an oversight is checked rather than
asserted. On Cursor: `preToolUse` / `postToolUse`
duplicate coverage the kit already gets from `beforeShellExecution` and
`afterFileEdit`; `beforeMCPExecution` and `afterShellExecution` are governance
surfaces this kit has no policy for; `workspaceOpen` fires outside any session,
where there is no session state to maintain; `afterAgentThought` fires per
reasoning step, far below the granularity any handover needs; the Tab hooks
cover inline completions, which never touch context state. On Claude Code: `MessageDisplay`
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

Repo commands used by CI and by hand:

```bash
bash scripts/check_sync.sh                          # wiring + registry bookkeeping
python scripts/generate_runtime_hooks.py --check    # generated configs match the registry
python scripts/check_runtime_doc_drift.py           # registry matches the live vendor docs
bash scripts/eval_all_runtimes.sh                   # all nine suites
```

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
