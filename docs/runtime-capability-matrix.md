# Runtime capability matrix (Phase C)

context-engineering-kit keeps **one logic core** under `.claude/hooks/*.sh`.
Thin adapters set `CLAUDE_PROJECT_DIR` / `CEK_RUNTIME` and dispatch into that core.

| Runtime | Config entrypoint | Adapter | Notes |
|---------|-------------------|---------|--------|
| **Claude Code** | `hooks/hooks.json` (plugin) + `.claude/settings.json` (project) | direct | Full event set; injects SessionStart / UserPromptSubmit stdout into context |
| **Cursor** | `.cursor/hooks.json` | `.cursor/hooks/*.sh` → `cek_runtime.sh` | camelCase events; inject text → stderr |
| **Codex** | `.codex/hooks.json` | `.codex/hooks/run.sh` | Portable relative commands only (no absolute machine paths) |
| **Grok Build** | `.grok/hooks/cek-hooks.json` **and** may also load `.claude/settings.json` | `.grok/hooks/run.sh` | Skips unknown event names; PermissionDenied ≠ PermissionRequest |

Regenerate Codex/Grok JSON after editing the event table:

```bash
python scripts/generate_runtime_hooks.py
python scripts/generate_runtime_hooks.py --check   # CI / pre-commit
```

---

## Event support

| Event | Claude | Cursor | Codex | Grok | Kit hook / chain |
|-------|:------:|:------:|:-----:|:----:|------------------|
| SessionStart | ✅ | ✅ | ✅ | ✅ | `session-start` chain (+ morning-brief) |
| SessionStart `compact` | ✅ | — | ✅ | ✅ | `compact-restore.sh` |
| SessionStart `startup\|resume` | ✅ | — | ✅ | ✅ | `session-title.sh` |
| SessionEnd | ✅ | ✅ | ✅ | ✅ | `session-end.sh` |
| UserPromptSubmit | ✅ | ✅ (`beforeSubmitPrompt`) | ✅ | ✅ | `usage-sentinel.sh` (Phase A auto-save) |
| PreToolUse (Bash) | ✅ | ✅ | ✅ | ✅ | `guard-dangerous.sh` |
| PostToolUse (Edit/Write) | ✅ | ✅ | ✅ | ✅ | `track-changes.sh` |
| PostToolUseFailure | ✅ | ✅ | ✅ | ✅ | `post-tool-failure.sh` |
| PermissionRequest | ✅ | ❌ | ✅ | ❌ | `auto-approve-permissions.sh` |
| PermissionDenied | ❌ | ❌ | ❌ | ✅ | *(no CEK script yet — Grok-only)* |
| PreCompact | ✅ | ✅ | ✅ | ✅ | `pre-compact.sh` |
| PostCompact | ✅ | ❌* | ✅ | ✅ | `post-compact.sh` (*Cursor re-injects via SessionStart compact) |
| Stop | ✅ | ✅ | ✅ | ✅ | `stop` chain: extract-state → usage-tracker → stop |
| StopFailure | ✅ | ❌ | ✅ | ✅ | `stop-failure.sh` |
| SubagentStart | ✅ | ✅ | ✅ | ✅ | `subagent-lifecycle.sh` |
| SubagentStop | ✅ | ✅ | ✅ | ✅ | `subagent-lifecycle.sh` |
| Notification | ✅ | ❌ | ✅ | ✅ | `notify.sh` |
| InstructionsLoaded | ✅ | ❌ | ❌ | ❌ | `instructions-loaded.sh` (Claude only) |
| FileChanged | ✅ | ❌ | ❌ | ❌ | config audit echo (Claude only) |

`cek_runtime_supports <Event>` in `scripts/cek_runtime.sh` encodes the same table for runtime no-ops.

---

## Double-fire risk (Grok + Claude settings)

Grok **merges** project `.claude/settings.json` and `.grok/hooks/*.json` when the
folder is trusted. That can run the same logic twice.

Mitigations already in the kit:

- `hook_once` on session-start / pre-compact / post-compact / session-end
- Atomic usage sentinels (Phase A) so 85%/92% save runs once per window

Optional (user config, not required):

```toml
# ~/.grok/config.toml — use only .grok/hooks for this machine
[compat.claude]
hooks = false
```

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

**Codex** — ensure project root is the cwd; `.codex/hooks.json` is portable.
Do **not** commit machine-local absolute paths.

**Grok** — open the project and run `/hooks-trust` once. Confirm Hooks tab shows
`cek-hooks.json` entries. Prefer Grok  + Claude settings together (deduped) or
disable Claude compat hooks if you want a single source.
