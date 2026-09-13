# Runtime capability matrix (Phase C)

context-engineering-kit keeps **one logic core** under `.claude/hooks/*.sh`.
Thin adapters set `CLAUDE_PROJECT_DIR` / `CEK_RUNTIME` and dispatch into that core.

| Runtime | Config entrypoint | Adapter | Notes |
|---------|-------------------|---------|--------|
| **Claude Code** | `hooks/hooks.json` (plugin) + `.claude/settings.json` (project) | direct | Full event set; injects SessionStart / UserPromptSubmit stdout into context |
| **Cursor** | `.cursor/hooks.json` | `.cursor/hooks/*.sh` → `cek_runtime.sh` | camelCase events; `sessionStart` injects via JSON `additional_context`, everything else → stderr |
| **Codex** | `.codex/hooks.json` (project) + `.codex-plugin/plugin.json` → `hooks/codex-hooks.json` (plugin) | `.codex/hooks/run.sh` | Portable relative commands only. The plugin manifest **must** name its hooks file — Codex otherwise defaults to `hooks/hooks.json`, the Claude manifest |
| **Grok Build** | `.grok/hooks/cek-hooks.json`; Grok also reads `.claude/settings.json` and `.cursor/hooks.json` | `.grok/hooks/run.sh` | **camelCase payload** — the adapter normalises it to the core's snake_case. `PreToolUse` is the only blocking event (exit 2 denies); everything else fails open. No `async` in its schema |

Regenerate Codex/Grok JSON after editing the event table:

```bash
python scripts/generate_runtime_hooks.py
python scripts/generate_runtime_hooks.py --check   # CI / pre-commit
```

`RUNTIME_EVENTS` in that script is the authoritative per-runtime allow-list, and
generation now **fails** if the event table names an event a runtime does not
implement. `--check` alone never caught that: it only proves the generated files
match the generator, so `.codex/hooks.json` shipped `PostToolUseFailure`,
`StopFailure` and `Notification` — none of which Codex has — while staying green.
`RUNTIME_TIMEOUT_MAX` does the same for per-runtime timeout ceilings (Codex caps
`SessionEnd` and `Interrupt` at 3s).

Both verified 2026-09-13 — Codex against `learn.chatgpt.com/docs/hooks`, Grok
against `docs.x.ai/build/features/hooks`. Grok's documented event set matches the
column below exactly. Two things the spec settled that inference had got wrong:
its payload is **camelCase** (`hookEventName`, `toolName`, `toolInput`), not the
Claude snake_case the shared core reads, and `async` is not in its schema.

---

## Event support

| Event | Claude | Cursor | Codex | Grok | Kit hook / chain |
|-------|:------:|:------:|:-----:|:----:|------------------|
| Setup | ✅ | ❌ | ❌ | ❌ | `native-event-log.sh` |
| SessionStart | ✅ | ✅ | ✅ | ✅ | `session-start` chain (+ morning-brief) |
| SessionStart `compact` | ✅ | — | ✅ | ✅ | `compact-restore.sh` |
| SessionStart `startup\|resume` | ✅ | — | ✅ | ✅ | `session-title.sh` |
| UserPromptSubmit | ✅ | ✅ (`beforeSubmitPrompt`) | ✅ | ✅ | `usage-sentinel.sh` (Phase A auto-save) |
| UserPromptExpansion | ✅ | ❌ | ❌ | ❌ | `native-event-log.sh` |
| PreToolUse (Bash) | ✅ | ✅ | ✅ | ✅ | `guard-dangerous.sh` |
| PermissionRequest | ✅ | ❌ | ✅ | ❌ | `auto-approve-permissions.sh` |
| PermissionDenied | ✅ | ❌ | ❌ | ✅ | `permission-denied.sh` + `native-event-log.sh` |
| PostToolUse (Edit/Write) | ✅ | ✅ | ✅ | ✅ | `track-changes.sh` |
| PostToolUseFailure | ✅ | ✅ | ❌ | ✅ | `post-tool-failure.sh` |
| PostToolBatch | ✅ | ❌ | ❌ | ❌ | `native-event-log.sh` |
| TaskCreated | ✅ | ❌ | ❌ | ❌ | `native-event-log.sh` |
| TaskCompleted | ✅ | ❌ | ❌ | ❌ | `native-event-log.sh` |
| TeammateIdle | ✅ | ❌ | ❌ | ❌ | `native-event-log.sh` |
| Stop | ✅ | ✅ | ✅ | ✅ | `stop` chain: extract-state → usage-tracker → stop |
| StopFailure | ✅ | ❌ | ❌ | ✅ | `stop-failure.sh` |
| SubagentStart | ✅ | ✅ | ✅ | ✅ | `subagent-lifecycle.sh` |
| SubagentStop | ✅ | ✅ | ✅ | ✅ | `subagent-lifecycle.sh` |
| PreCompact | ✅ | ✅ | ✅ | ✅ | `pre-compact.sh` (Cursor also supplies the real context %) |
| PostCompact | ✅ | ❌* | ✅ | ✅ | `post-compact.sh` (*Cursor re-injects via SessionStart compact) |
| Notification | ✅ | ❌ | ❌ | ✅ | `notify.sh` |
| PreModelSwitch | ✅ | ❌ | ❌ | ❌ | `native-event-log.sh` |
| PostModelSwitch | ✅ | ❌ | ❌ | ❌ | `native-event-log.sh` |
| CwdChanged | ✅ | ❌ | ❌ | ❌ | `native-event-log.sh` |
| DirectoryAdded | ✅ | ❌ | ❌ | ❌ | `native-event-log.sh` |
| WorktreeCreate | ✅ | ❌ | ❌ | ❌ | **deliberately not wired** — see below |
| WorktreeRemove | ✅ | ❌ | ❌ | ❌ | `native-event-log.sh` |
| ConfigChange | ✅ | ❌ | ❌ | ❌ | `native-event-log.sh` |
| InstructionsLoaded | ✅ | ❌ | ❌ | ❌ | `instructions-loaded.sh` (Claude only) |
| FileChanged | ✅ | ❌ | ❌ | ❌ | `config-changed.sh` (Claude only) |
| SessionEnd | ✅ | ✅ | ✅ | ✅ | `session-end.sh` → detaches `scripts/session_finalize.sh`; commits only on a real exit, not `clear`/`resume` |
| Interrupt | ❌ | ❌ | ✅ | ❌ | `native-event-log.sh` (Codex-only; 3s ceiling) |

`cek_runtime_supports <Event>` in `scripts/cek_runtime.sh` encodes the same table
for runtime no-ops. It answers "does this runtime emit this event", **not** "does
the kit wire it" — `WorktreeCreate` is supported by Claude Code and still absent
from `hooks/hooks.json` on purpose.

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
| `preCompact` | `on-precompact.sh` | Supplies `context_usage_percent`, `context_tokens` and `context_window_size`. `pre-compact.sh` prefers that over its own estimate — snapshots used to be stamped `ctx=unknown%` on every runtime |

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
`.claude/settings.json` **and** `.cursor/hooks.json` (both documented), so this
repo ships three files it may load; `.claude/settings.json` declares no hooks
since v3.0.0 and the Cursor file uses Cursor-only event names, so
`cek-hooks.json` is the only set that fires. There is **no documented setting**
to disable that compatibility scan — earlier versions of this README suggested
one, which was invented.
