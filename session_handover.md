# Session Handover
_Generated: 2026-09-17T18:52:38Z_
_Branch: main_
_Trigger: stable | Context at compact: unknown%_
_Compact count this project: 0_

---

## 🎯 Active Task
**What we're building/fixing:**
v4.0 universal runtime support — Phase 4 (cek-mcp universal floor) shipped as v3.4.0

**Phase:** Phases 0-2 and 4 complete; Phase 5 (Warp AGENTS.md) or Phase 3 (Antigravity) next
**Next action:** Decide: Phase 5 Warp (AGENTS.md generator, small — cek-mcp already reaches Warp) or Phase 3 Antigravity adapter (larger, partial parity, closed source)

---

## ✅ Completed This Session
- [x] Git sync — pushed to origin/main
- [x] Full-repo code review — 6 findings, 3 reproduced (docs/PLAN_v4_universal_runtime.md Part 1)
- [x] Verified runtime surfaces against vendor docs; **corrected**: Gemini CLI was sunset 2026-06-18, live runtime is Antigravity CLI
- [x] **Phase 0** shipped as v3.1.1 — handover accretion, lock placement, containment, StopFailure fields, PermissionDenied wiring
- [x] Re-verified Codex + Grok (no event drift) → found + fixed a live Grok/Cursor double-fire, shipped as v3.1.2
- [x] README Option G — Antigravity compatibility and limitations
- [x] **Phase 1** shipped as v3.2.0 — one runtime registry (config/runtime_events.json); generator, cek_runtime_supports() and the matrix table all read it; .cursor/hooks.json now generated
- [x] **Phase 2** shipped as v3.3.0 — opencode adapter (.opencode/plugins/cek.ts + hooks/run.sh); handover injected into the compaction prompt via experimental.session.compacting
- [x] **Phase 4** shipped as v3.4.0 — cek-mcp stdio MCP server (stdlib-only), reaches Warp/Cline/Continue/Goose/Zed/Antigravity; verified with the official MCP inspector
- [x] Evals 130 → 183; every new assertion negative-controlled (two were found passing for the wrong reason and tightened)

---

## 🔄 In Progress (Exact Resume Point)
**Branch:** `main`
**Last commit:** `2ba3e2b feat: Phase 2 — opencode support (v3.3.0)`
**Next immediate action:** Decide: Phase 5 Warp (AGENTS.md generator, small — cek-mcp already reaches Warp) or Phase 3 Antigravity adapter (larger, partial parity, closed source)

---

## 📋 Remaining Work
**Phases 0 and 1 are done** (v3.1.1, v3.1.2, v3.2.0). Full plan:
[`docs/PLAN_v4_universal_runtime.md`](docs/PLAN_v4_universal_runtime.md).

1. **Four open decisions** (plan's "Decisions to make" section):
   - Scope: all remaining phases, or the recommended subset — Phases 2 and 4 (opencode, MCP floor)?
   - opencode: JS shim over the bash core (recommended), or a native TS path?
   - Warp: is "read-only, no auto-save" acceptable to advertise, or drop it until it has hooks?
   - Rename `.claude/` (the shared core's home) to `core/`? Breaking; decide at v4.0.0 or not at all.

2. **Phase 5 — Warp** (small; `cek-mcp` already reaches Warp)
   - `AGENTS.md` generator emitting a Warp-compatible rules file pointing at `session_handover.md` and telling the agent to call `handover_read` first
   - Caps filename required; `WARP.md` wins if both exist
   - README capability table distinguishing automatic (hooks) / on-request (MCP) / read-only (rules)

3. **Phase 3 — Antigravity CLI** (`agy`) — larger; 5 events, no session or compaction events, closed source. README Option I documents the gaps. `cek-mcp` already covers it on-request

4. ~~**Phase 2 — opencode**~~ ✅ done (v3.3.0) · ~~**Phase 4 — cek-mcp**~~ ✅ done (v3.4.0)

3. **Phase 3 — Antigravity CLI** (`agy`) — 5 events only, no session or compaction events; partial parity. README Option G documents the gaps
4. **Phase 4 — `cek-mcp`** (universal floor; unlocks Warp, Cline, Continue, Goose, Zed — and is the ONLY handover path on Antigravity)
5. **Phase 5 — Warp** (AGENTS.md + MCP, honest capability disclosure)
6. **Phase 6 — v4.0.0** (per-runtime evals, generated matrix, per-runtime bundles)

**Carried over, not yet scoped:**
- `PreCompact` stamps `ctx=unknown%` into snapshot commits on Claude Code (`context_percent` is not a field on that event; Cursor supplies the real number)
- Grok's default hook timeout is 5s, not 30 — the session-start chain has never been profiled against that ceiling
- Installed plugin copy at `~/.claude/plugins/marketplaces/local-desktop-app-uploads/` is v3.0.0 — re-upload the zip

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
| `.claude-plugin/marketplace.json` | modified |
| `.claude-plugin/plugin.json` | modified |
| `.claude/hooks/native-event-log.sh` | modified |
| `.claude/hooks/permission-denied.sh` | modified |
| `.claude/hooks/post-tool-failure.sh` | modified |
| `.claude/hooks/session-start.sh` | modified |
| `.claude/hooks/stop-failure.sh` | modified |
| `.claude/hooks/usage-sentinel.sh` | modified |
| `.claude/settings.json` | modified |
| `.codex-plugin/plugin.json` | modified |
| `.cursor/hooks/_common.sh` | modified |
| `.cursor/hooks/guard-read.sh` | modified |
| `.cursor/hooks/on-precompact.sh` | modified |
| `.opencode/hooks/run.sh` | modified |
| `.opencode/plugins/cek.ts` | modified |
| _(+43 more files not shown)_ | — |

---

## 🌿 Git Context
```
Branch  : main
Commit  : 2ba3e2b feat: Phase 2 — opencode support (v3.3.0)
Status  : M .claude-plugin/marketplace.json
 M .claude-plugin/plugin.json
 M .claude/hooks/session-start.sh
 M .claude/settings.json
 M .codex-plugin/plugin.json
 M README.md
 M api_docs.md
 M docs/PLAN_v4_universal_runtime.md
 M scripts/eval_phase_c.sh
 M session_handover.md
?? docs/RELEASE_NOTES_3.4.0.md
?? docs/mcp-setup.md
?? scripts/cek_mcp.py
?? scripts/eval_mcp.py
```

Recent commits:
```
2ba3e2b feat: Phase 2 — opencode support (v3.3.0)
3c806c8 feat: Phase 1 — one runtime registry, generated everywhere (v3.2.0)
090fb4c fix: Grok ran the Cursor hooks too — double-fire (v3.1.2)
7d32c21 docs: correct the plan — Gemini CLI is dead, Antigravity CLI replaced it
6ef0d89 fix: Phase 0 — close the core bugs before new runtimes inherit them (v3.1.1)
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
