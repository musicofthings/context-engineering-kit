# Runtime capability matrix (Phase C)

context-engineering-kit keeps **one logic core** under `.claude/hooks/*.sh`.
Thin adapters set `CLAUDE_PROJECT_DIR` / `CEK_RUNTIME` and dispatch into that core.

| Runtime | Config entrypoint | Adapter | Notes |
|---------|-------------------|---------|--------|
| **Claude Code** | `hooks/hooks.json` (plugin) + `.claude/settings.json` (project) | direct | Full event set; injects SessionStart / UserPromptSubmit stdout into context |
| **Cursor** | `.cursor/hooks.json` | `.cursor/hooks/*.sh` → `cek_runtime.sh` | camelCase events; inject text → stderr |
| **Codex** | `.codex/hooks.json` (project) + `.codex-plugin/plugin.json` → `hooks/codex-hooks.json` (plugin) | `.codex/hooks/run.sh` | Portable relative commands only. The plugin manifest **must** name its hooks file — Codex otherwise defaults to `hooks/hooks.json`, the Claude manifest |
| **Grok Build** | `.grok/hooks/cek-hooks.json` **and** may also load `.claude/settings.json` | `.grok/hooks/run.sh` | Skips unknown event names; PermissionDenied ≠ PermissionRequest |

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

Codex sources verified 2026-09-13. **Grok remains unverified** — no authoritative
public hook spec was found; its column mirrors the Claude schema in practice and
additions to it are provisional.

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
| PreCompact | ✅ | ✅ | ✅ | ✅ | `pre-compact.sh` |
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
| SessionEnd | ✅ | ✅ | ✅ | ✅ | `session-end.sh` → detaches `scripts/session_finalize.sh` |

`cek_runtime_supports <Event>` in `scripts/cek_runtime.sh` encodes the same table
for runtime no-ops. It answers "does this runtime emit this event", **not** "does
the kit wire it" — `WorktreeCreate` is supported by Claude Code and still absent
from `hooks/hooks.json` on purpose.

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

**Cursor** — open the project; `.cursor/hooks.json` is picked up automatically.

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

**Grok** — open the project and run `/hooks-trust` once. Confirm Hooks tab shows
`cek-hooks.json` entries. Prefer Grok  + Claude settings together (deduped) or
disable Claude compat hooks if you want a single source.
