# Session Handover
_Generated: 2026-09-17T15:24:33Z_
_Branch: main_
_Trigger: stability | Context at compact: unknown%_
_Compact count this project: 0_

---

## 🎯 Active Task
**What we're building/fixing:**
v4.0 universal runtime support — Phase 0 (core fixes) shipped as v3.1.1

**Phase:** Phase 0 complete; Phase 1 (single generated runtime registry) not started
**Next action:** Decide scope in docs/PLAN_v4_universal_runtime.md (4 open questions), then start Phase 1: move the event table into config/runtime_events.json and generate Cursor's config from it

---

## ✅ Completed This Session
- [x] Git sync — pushed `8d58226..b9104c0` to origin/main
- [x] Full-repo code review — 6 findings, 3 reproduced (see docs/PLAN_v4_universal_runtime.md Part 1)
- [x] Verified runtime surfaces against vendor docs: Warp has NO hooks (warpdotdev/warp#6857 still open), opencode needs a JS shim
- [x] **Corrected**: Gemini CLI was sunset 2026-06-18; the live runtime is Antigravity CLI (`agy`), re-derived from antigravity.google/docs/hooks. Plan Phase 2/3 reordered — opencode first, Antigravity after.
- [x] Wrote docs/PLAN_v4_universal_runtime.md (committed b6d2eb4)
- [x] Phase 0 shipped as v3.1.1 — handover accretion, lock placement, containment on 4 shell writers + state_lock(), StopFailure fields, PermissionDenied wiring, imperative inject text, Cursor preCompact user_message
- [x] Evals 130 → 135; every new assertion negative-controlled

---

## 🔄 In Progress (Exact Resume Point)
**Branch:** `main`
**Last commit:** `6ef0d89 fix: Phase 0 — close the core bugs before new runtimes inherit them (v3.1.1)`
**Next immediate action:** Decide scope in docs/PLAN_v4_universal_runtime.md (4 open questions), then start Phase 1: move the event table into config/runtime_events.json and generate Cursor's config from it

---

## 📋 Remaining Work
**Phase 0 is done and shipped as v3.1.1.** Full plan:
[`docs/PLAN_v4_universal_runtime.md`](docs/PLAN_v4_universal_runtime.md).

1. **Four open decisions blocking Phase 1** (in the plan's "Decisions to make" section):
   - Scope: all six phases, or the recommended subset — Phases 1, 2, 4 (registry, opencode, MCP floor)?
   - opencode: JS shim over the bash core (recommended), or a native TS path?
   - Warp: is "read-only, no auto-save" acceptable to advertise, or drop it until it has hooks?
   - Rename `.claude/` (the shared core's home) to `core/`? Breaking; decide at v4.0.0 or not at all.

2. **Phase 1 — one generated runtime registry** (the enabling refactor)
   - Move the event table to `config/runtime_events.json`: per runtime, supported events,
     event-name aliases, timeout ceilings, async support, payload casing, injection mechanism
   - `generate_runtime_hooks.py` emits ALL adapter configs from it, **including Cursor**
   - `cek_runtime_supports()` reads it instead of carrying a second copy
   - `docs/runtime-capability-matrix.md` becomes generated output
   - Today the same table lives in three hand-synced places:
     `generate_runtime_hooks.py:162`, `cek_runtime.sh:62`, the matrix doc

3. **Phase 2 — opencode** (JS/TS plugin; `experimental.session.compacting` can inject the handover into the compaction prompt — the one place the kit beats Claude Code)
4. **Phase 3 — Antigravity CLI** (`agy`) — NOT Gemini CLI, which Google shut off 2026-06-18 with no grace period. Only 5 events (PreToolUse/PostToolUse/PreInvocation/PostInvocation/Stop): no session, compaction or subagent events. camelCase payload with nested `toolCall.name`/`.args` and PascalCase arg keys, Antigravity-specific tool names, JSON decisions instead of exit 2, and the event name is not in the payload. Closed source. Partial parity, not the cheap win the first draft claimed.
5. **Phase 4 — `cek-mcp`** (universal floor; unlocks Warp, Cline, Continue, Goose, Zed)
6. **Phase 5 — Warp** (AGENTS.md generator + MCP, with honest capability disclosure)
7. **Phase 6 — v4.0.0** (per-runtime evals, generated matrix, per-runtime bundles)

**Carried over, not Phase 0 scope:**
- `PreCompact` stamps `ctx=unknown%` into snapshot commits on Claude Code (`context_percent` is not a field on that event; Cursor supplies the real number)
- Your installed plugin copy is v3.0.0 at `~/.claude/plugins/marketplaces/local-desktop-app-uploads/` — re-upload the zip

---

## 🏗 Architecture Decisions Made
| Decision | Rationale | Date |
|----------|-----------|------|
| `state.json` stays untracked/machine-local | Confirmed deliberate via `90545c6 "chore: ignore Claude session state"`; `session_handover.md` is the portable cross-device anchor | 2026-08-30 |
| Kit drops a self-ignoring `.claude/session/.gitignore` in host repos | Stops per-turn churn being swept into unrelated projects' commits; scoped to that dir, cannot untrack existing history | 2026-08-30 |
| `resolve_state_dir.sh` refuses non-git / `$HOME` / `~/.claude` | The helper every hook goes through had no containment guard, so kit state landed inside Claude Code's own config dir | 2026-08-30 |
| Python state logic centralised in `scripts/cek_paths.py` | Two divergent copies had drifted from the shell version (Windows backslash worktree paths, no locking) | 2026-08-30 |
| ruff pinned + explicit rule set in `ruff.toml` | An unpinned lint gate let a newer ruff turn CI red on untouched code; BLE001/S110 conflict with the deliberate fail-open `except Exception` in hooks | 2026-08-30 |
| **REVERSE** the `.claude/subagents` → `.claude/agents` rename | The rename was wrong. `.claude/subagents/` was inert; renaming it made it ACTIVE and it now shadows the plugin's own `agents/`. Delete it instead. | 2026-08-30 |
| `hooks/hooks.json` is the single hook source; drop settings.json hooks | Both declare all 16 events at the same scripts and Claude Code does not dedupe across plugin/project scope | 2026-08-30 (planned) |
| SessionEnd work moves to `Stop` `async: true` | A plugin cannot raise its own 1.5s SessionEnd budget; this is not fixable with a bigger timeout | 2026-08-30 (planned) |
| No `agent`-type hooks | Documented experimental; inappropriate for a distributed plugin | 2026-08-30 (planned) |

---

## 🔧 Commands to Resume

**This exact conversation** (SDK/CLI transcript resume):
```bash
# Same machine AND same directory it started in:
claude --resume 88b4e1b5-a3ff-4af2-8117-cfe59f96e6c7
```
- Session ID    : `88b4e1b5-a3ff-4af2-8117-cfe59f96e6c7`
- Transcript    : `/Users/theranosis_dx/.claude/projects/-Users-theranosis-dx-projects-context-engineering-kit/88b4e1b5-a3ff-4af2-8117-cfe59f96e6c7.jsonl`
- Bound to cwd  : `/Users/theranosis_dx/projects/context-engineering-kit`
- Stored at     : `~/.claude/projects/-Users-theranosis-dx-projects-context-engineering-kit/88b4e1b5-a3ff-4af2-8117-cfe59f96e6c7.jsonl`

> ⚠️ Transcript resume is **cwd-bound**. It only works from the same directory
> on the same machine. If this session started in a git **worktree**, that
> worktree's path is the cwd — resuming from `main` (or after the worktree is
> deleted) will silently start a *fresh* session. Per the Agent SDK docs, the
> robust cross-host / cross-worktree path is **not** transcript resume — it's
> this handover file: read it into a new session's prompt as application state.

**Project state** (any machine — the robust path):
```bash
git pull origin main
bash scripts/session_sync.sh --load

# In Claude Code:
# /context-health     — verify hooks are wired
# /handover           — review this file
# /token-status       — check context usage
```

---

## 📁 Files Modified This Session
| File | Status |
|------|--------|
| `.claude/hooks/auto-approve-permissions.sh` | modified |
| `.claude/hooks/config-changed.sh` | modified |
| `.claude/hooks/extract-state-on-stop.sh` | modified |
| `.claude/hooks/native-event-log.sh` | modified |
| `.claude/hooks/permission-denied.sh` | modified |
| `.claude/hooks/post-tool-failure.sh` | modified |
| `.claude/hooks/session-end.sh` | modified |
| `.claude/hooks/stop-failure.sh` | modified |
| `.claude/hooks/usage-sentinel.sh` | modified |
| `.codex-plugin/plugin.json` | modified |
| `.codex/hooks/run.sh` | modified |
| `.cursor/hooks/guard-read.sh` | modified |
| `.cursor/hooks/on-agent-response.sh` | modified |
| `.cursor/hooks/on-precompact.sh` | modified |
| `.cursor/hooks/on-session-start.sh` | modified |
| _(+36 more files not shown)_ | — |

---

## 🌿 Git Context
```
Branch  : main
Commit  : 6ef0d89 fix: Phase 0 — close the core bugs before new runtimes inherit them (v3.1.1)
Status  : M api_docs.md
 M docs/PLAN_v4_universal_runtime.md
 M session_handover.md
```

Recent commits:
```
6ef0d89 fix: Phase 0 — close the core bugs before new runtimes inherit them (v3.1.1)
b6d2eb4 docs: v4.0 plan — universal runtime support
b9104c0 chore(context): save session state — Upgrade CEK to current Claude Code compatibility (v3.0.0) — audit complete, plan awaiting approval [2026-09-14T14:52:05Z]
147001f chore(context): save session state — Upgrade CEK to current Claude Code compatibility (v3.0.0) — audit complete, plan awaiting approval [2026-09-13T18:30:19Z]
8d58226 docs: fix every command claim against the runtimes' own docs (R-031)
```

---

## ⚠️ Critical Rules
- Never commit secrets or API keys
- Run /handover before switching devices
- **Plan before making changes** — the user asked for this explicitly; present a plan and get approval first
- **Do not trust WebFetch for Claude Code hook field names** — it truncates and the summariser fabricates. Use the extracted PDF text.
- Verify subagent findings against the source before acting; two agents contradicted each other on `FileChanged` and one was wrong
- `state.json` is gitignored by design — do not re-add it to any `git add` list

---

## 🧬 Bioinformatics Context (if applicable)
- Not configured for this project

---
_Auto-updated by `pre-compact.sh` hook and `/handover` skill._
_Read this at the start of every session. Update with `/handover`._
