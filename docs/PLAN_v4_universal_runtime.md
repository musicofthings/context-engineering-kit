# v4.0 — Universal runtime support

**Status:** proposed, awaiting approval
**Date:** 2026-09-17
**Baseline:** v3.1.0 @ `b9104c0` (pushed to `origin/main`)
**Supersedes:** the open items in `session_handover.md` (Phases 0–3 of the v3.0.0
Claude-compatibility audit landed in `cb68658..8d58226`; that handover is stale).

---

## Part 1 — Code review of the repo as it stands

Health is good. All three eval suites pass on this machine: `eval_phase_c.sh`
31/31, `eval_hooks_smoke.sh` 70/70, `eval_usage_lifecycle.sh` 29/29. `ruff check`
clean, `generate_runtime_hooks.py --check` clean, every `.sh` parses, every
`.json` parses. Skill frontmatter is on the current keys (`when_to_use`,
`argument-hint`). The findings below are what the suites do not cover.

### F1 — `session_handover.md` accretes garbage on every regeneration (P0)

`_extract_section()` in `scripts/generate_session_handover.py:46` captures
everything from a `## ` heading to the next `## ` heading. The template at
`scripts/generate_session_handover.py:232` emits the section heading **plus two
literal table-header rows**, then interpolates the captured body underneath. So
each regeneration re-captures the header rows it emitted last time and emits a
fresh pair above them. The trailing `---` separators are captured the same way
for five of the six carried sections — `bioinfo` is the only one that strips it
(`:103`), so the author hit this once and patched a single instance.

Reproduced on a clean checkout, four regenerations:

```
round 1: "---" separators=13   decision-header-rows=1   lines=103
round 2: "---" separators=17   decision-header-rows=2   lines=113
round 3: "---" separators=21   decision-header-rows=3   lines=123
round 4: "---" separators=25   decision-header-rows=4   lines=133
```

+10 lines and +4 separators per run, unbounded. The live `session_handover.md`
in this repo already carries six rounds of it: six copies of
`| Decision | Rationale | Date |` and six runs of `---` under three sections.

This regenerates on `PreCompact`, at the 85% and 92% usage thresholds, and at
`SessionEnd` — several times a working day. The file is re-read into context at
every session start. A token-hygiene tool is spending tokens on its own noise.

**Fix:** strip the emitted scaffold from what `_extract_section` returns —
drop a leading table header if the template supplies one, and drop trailing
`---`/blank lines for every section, not just `bioinfo`. Add a regression eval
that regenerates three times and asserts the line count is stable.

### F2 — `session_handover.md.lock` is never removed, and is not ignored (P1)

`cek_paths.state_lock()` (`scripts/cek_paths.py:131`) creates both
`<file>.lock` (flock) and `<file>.lockd` (mkdir). The `finally` block removes
the `.lockd` directory but only *closes* the `.lock` file — it is never
unlinked. For state files that is fine and deliberate: they live under
`.claude/session/`, which `.gitignore` covers with `*.lock`.

But `generate_session_handover.py:307` takes the same lock on **`output_path`**,
which is `session_handover.md` at the **repo root**. `.gitignore` has no
root-level `*.lock` rule, so every project the kit touches grows a permanent
untracked `session_handover.md.lock`. This repo has been carrying one since
2026-09-14; it is the `?? session_handover.md.lock` in `git status` right now.

This is the same class of problem the self-ignoring `.claude/session/.gitignore`
was written to solve — kit bookkeeping showing up in a host project's
`git status` and getting swept into unrelated `git add -A` commits.

**Fix:** add `/*.lock`, `/*.lockd/` to `.gitignore`, and have
`auto_init_project.sh` add the same two lines to host projects it bootstraps.
Cheaper alternative worth considering: park the handover lock beside the state
file rather than beside the output.

### F3 — `permission-denied.sh` writes into a rejected state directory (P1)

`resolve_state_dir.sh` refuses to create state outside a real project, and for
`$HOME`/`~/.claude` it additionally `rm -rf`s any stale directory a previous kit
version left. `.claude/hooks/permission-denied.sh:54` then runs an unconditional
`mkdir -p "$STATE_DIR"` and appends with a bare `>>`, without consulting
`cek_state_ok`. It recreates exactly what the guard just deleted.

Reproduced in isolation with `HOME` and `CLAUDE_PROJECT_DIR` pointed at a
non-git temp dir:

```
--- permission-denied.sh leaked: ---
<HOME>/.claude
<HOME>/.claude/session
<HOME>/.claude/session/tool-failures.jsonl
```

`post-tool-failure.sh` and `stop-failure.sh` are clean only by accident — they
skip the `mkdir`, so their `>>` fails against a missing directory and the
`2>/dev/null || true` swallows it.

The containment eval at `scripts/eval_hooks_smoke.sh:315` exercises three
writers (`native-event-log.sh`, `config-changed.sh`, `session_finalize.sh`) and
passes. It does not exercise this one. Running the four appenders back-to-back
also hides it: the next hook's `resolve_state_dir.sh` cleans up the previous
one's leak, so only an isolated run shows it.

On Claude Code this hook is not wired (see F4), so the exposure is Grok, where
`PermissionDenied` dispatches to it directly.

**Fix:** gate on `cek_state_ok` before `mkdir`, and route the append through
`state_append()` — the four bare `>>` writers are `usage-sentinel.sh:188`,
`stop-failure.sh:41`, `post-tool-failure.sh:26`, `permission-denied.sh:56`.
Extend the leak eval to loop over every writer rather than a hand-picked three.

### F4 — `PermissionDenied` on Claude Code is wired to the wrong handler (P2)

`docs/runtime-capability-matrix.md:35` lists the `PermissionDenied` row as
`permission-denied.sh + native-event-log.sh`. `hooks/hooks.json` wires only
`native-event-log.sh`. The dedicated handler — which is what increments
`.permission_denials` and records the denial reason — runs on Grok only. The
counter is permanently 0 on Claude Code, and the matrix says otherwise.

Note also that `api_docs.md:26` documents a `hookSpecificOutput.retry: true`
response for this event. The kit does not use it. That is a reasonable default
for a context tool, but it should be a recorded decision rather than an omission.

### F5 — Cursor sits outside the generator's validation (P2)

`scripts/generate_runtime_hooks.py` is the stated single source of truth for
multi-runtime wiring, and `RUNTIME_EVENTS` is described as the authoritative
per-runtime allow-list. Cursor appears in neither. `.cursor/hooks.json` and the
twelve scripts under `.cursor/hooks/` are hand-maintained, so the guard that
caught `.codex/hooks.json` shipping three events Codex does not have cannot fire
for Cursor.

The same table now exists in three places that cannot disagree safely:

| Copy | Location | Covers |
|---|---|---|
| `RUNTIME_EVENTS` | `scripts/generate_runtime_hooks.py:162` | codex, grok |
| `cek_runtime_supports()` | `scripts/cek_runtime.sh:62` | claude, cursor, codex, grok |
| Event support table | `docs/runtime-capability-matrix.md:38` | claude, cursor, codex, grok |

Three copies is already one too many at four runtimes. At seven it is the thing
that breaks. See Phase 1.

### F6 — Minor

- **`stop-failure.sh:36`** reads `.failure_type // .error_type`. The v3.0.0
  audit recorded that neither field exists in the `StopFailure` payload and that
  the real field is `error` (plus `error_details`) — it was listed as a Phase 1
  fix and did not land. Every `StopFailure` is currently recorded as
  `"unknown"`, which makes the rate-limit-frequency signal the hook exists for
  useless. Re-verify against the hook reference before changing, then change it.
- **Inject text is still imperative.** `usage-sentinel.sh:224` says
  `Tell the user in one line about the usage state.` The v3.0.0 audit flagged
  this phrasing as the shape that trips prompt-injection defences and planned to
  rewrite it as factual statements. Not done.
- **Cursor `preCompact` has an output field the adapter does not use.**
  `.cursor/hooks/on-precompact.sh` routes the kit banner to stderr as
  "observe-only". Cursor's `preCompact` accepts `{"user_message": "..."}`, which
  surfaces the text properly when compaction fires. One-line change.
- **Your installed copy is behind.** `~/.claude/plugins/marketplaces/local-desktop-app-uploads/context-engineering-kit`
  is v3.0.0 (and `installed_plugins.json` records it as 2.5.0 — the registry
  entry is stale too). The session banner in this session read v3.0.0 while the
  repo is v3.1.0. Re-upload the zip after the next release.

---

## Part 2 — Universal runtime support

### What the targets can actually do

Verified against each vendor's own documentation, 2026-09-17.

| Runtime | Extension surface | Lifecycle hooks | Context injection | Verdict |
|---|---|---|---|---|
| **Claude Code** | plugin + `.claude/settings.json` | 30+ events | `SessionStart`, `UserPromptSubmit`, `PostModelSwitch` stdout | shipped |
| **Cursor** | `.cursor/hooks.json` + plugins (via `workspaceOpen` → `pluginPaths`) | 18 agent events | `sessionStart.additional_context`, `postToolUse.additional_context` | shipped, needs generator coverage |
| **Codex** | plugin manifest + `.codex/hooks.json` | 12 events | `SessionStart` | shipped |
| **Grok** | `.grok/hooks/*.json` | 14 events | `SessionStart` | shipped |
| **Gemini CLI** | `.gemini/settings.json` + extensions | `BeforeTool`, `AfterAgent`, `SessionStart`, … (v0.26.0+, Jan 2026) | hook JSON response | **new — cheapest** |
| **opencode** | JS/TS plugin, `.opencode/plugins/` or npm | 25+ events | `experimental.session.compacting` → `output.context.push()`, `tui.prompt.append` | **new — needs a shim** |
| **Warp** | `AGENTS.md` rules + MCP | **none** | rules file only | **new — read-side only** |

Three things this changes about the plan:

**Gemini CLI is nearly free.** Shell commands, stdin JSON, **snake_case field
names** (`tool_input`, matching the shared core exactly), a `matcher` key, and a
`{decision, reason, systemMessage}` response. Config shape is close enough to
Claude's that it is a generator target, not a rewrite. Its `$GEMINI_PROJECT_DIR`
maps to `CLAUDE_PROJECT_DIR`. Event *names* differ (`BeforeTool` not
`PreToolUse`), which is a rename table, not an architecture problem. Extensions
can bundle hooks, which gives a distribution path.

**opencode is the best fit for what this kit does, and the most work.** It is
the only runtime with a compaction hook that can *inject into the compaction
prompt itself* — `experimental.session.compacting` takes
`output.context.push(...)`, and the docs' own example is "current task status,
important decisions made, files being actively worked on". That is
`session_handover.md`. It is also the only one where the kit could replace the
compaction prompt outright (`output.prompt`), which is what `/compact-smart`
approximates by asking the model nicely. Cost: plugins are JS/TS modules, not
shell. The adapter is a JS shim that serialises the event to Claude-shaped JSON
and pipes it to the existing bash core via the injected `$` (Bun shell) handle.

**Warp cannot do this.** Warp has no hook mechanism. Hooks are an open,
unassigned feature request (`warpdotdev/warp#6857`, filed Jul 2025, still open).
Warp reads `AGENTS.md`/`WARP.md` as project rules, auto-applied from the repo
root and the current subdirectory, and it speaks MCP. So Warp support means:
a well-formed `AGENTS.md` that points the agent at `session_handover.md`, plus
an MCP server it can call. **There is no automatic save on Warp** and the
README must say so rather than listing Warp beside Claude Code. Note
`AGENTS.md` must be all-caps, and `WARP.md` wins if both exist.

### The architectural move: an MCP server as the universal floor

Every runtime in that table speaks MCP — including Warp, and including every
open-source agent not in the table (Cline, Continue, Goose, Aider-with-MCP,
Zed). A small `cek-mcp` server exposing the kit's existing logic as tools
(`handover_write`, `handover_read`, `state_get`, `usage_status`,
`session_sync`) gives the kit a working surface everywhere, at one
implementation cost, with no per-runtime adapter.

It is strictly weaker than hooks — the model has to *choose* to call it, so
there is no guaranteed save at 85% — but it is the difference between "Warp is
unsupported" and "Warp works, manually". It is also the honest answer to "other
open source coding agents": support the protocol, not the product list.

Recommended split: **hooks where they exist (guaranteed execution), MCP
everywhere else (best effort)**, and say which one you are getting.

### Phases

Each phase is independently shippable. Phase 0 blocks everything else because
those bugs are in the shared core and would be inherited by three new runtimes.

**Phase 0 — fix the core first** — ✅ **shipped as v3.1.1**, see
[`RELEASE_NOTES_3.1.1.md`](RELEASE_NOTES_3.1.1.md). Evals 130 → 135, all five
new assertions negative-controlled. One extra fix landed that the review had
not found: `state_lock()` in `cek_paths.py` had no containment guard either,
which only surfaced once the handover lock moved under `.claude/session/`.
- F1 handover accretion + a regression eval asserting stable line count
- F2 root-level lock ignore, in the repo and in `auto_init_project.sh`
- F3 containment on all four bare appenders + leak eval over every writer
- F4 wire `permission-denied.sh` on Claude, or correct the matrix
- F6 `StopFailure` field names, imperative inject text, Cursor `user_message`
- Ship as **v3.1.1**. No behaviour change for existing users beyond the fixes.

**Phase 1 — one registry, generated everywhere** *(the enabling refactor)*
- Move the event table out of Python into `config/runtime_events.json`: per
  runtime, the supported events, event-name aliases, timeout ceilings, async
  support, payload casing, and the injection mechanism.
- `generate_runtime_hooks.py` reads it and emits **all** adapter configs,
  Cursor included. `cek_runtime_supports()` reads it too, instead of carrying a
  second copy. `docs/runtime-capability-matrix.md` becomes generated output.
- `--check` then guards every runtime, and adding a runtime is a table entry
  plus an adapter script.
- Ship as **v3.2.0**. Still four runtimes; the point is that the fifth is cheap.

**Phase 2 — Gemini CLI** *(first new runtime, proves the registry)*
- `.gemini/hooks/run.sh` adapter on the `cek_runtime.sh` pattern, `CEK_RUNTIME=gemini`
- Event-name alias table (`BeforeTool`→`PreToolUse`, `AfterAgent`→`Stop`, …)
- `.gemini/settings.json` hooks block, generated
- `GEMINI_PROJECT_DIR` → `CLAUDE_PROJECT_DIR` in detection
- Decision-response translation: exit 2 → `{"decision":"deny","reason":…}`
- Gemini CLI extension manifest so it installs in one command
- Ship as **v3.3.0**

**Phase 3 — opencode** *(first non-shell runtime)*
- `.opencode/plugins/cek.ts` — thin shim, no logic. Maps
  `session.created`→`session-start`, `session.idle`→`stop`,
  `experimental.session.compacting`→`pre-compact`, `session.compacted`→`post-compact`,
  `tool.execute.before`→`guard-dangerous` (throw to block),
  `tool.execute.after`→`track-changes`, `file.edited`→`track-changes`,
  `permission.asked`/`permission.replied`→the permission handlers.
- Serialise each event to Claude-shaped snake_case JSON, pipe to the bash core.
- Use `experimental.session.compacting` to push the live handover into the
  compaction prompt — the one place this kit gets a better result than on
  Claude Code. Do **not** override `output.prompt` by default.
- Publish to npm as `opencode-context-engineering-kit` so it installs via the
  `plugin` array; keep the local-directory path working too.
- Open question to settle first: does the bash core stay the single source of
  truth, or does opencode get a native TS path? Recommendation: shim only. Two
  cores is how this kit's `.claude/skills` duplication happened.
- Ship as **v3.4.0**

**Phase 4 — `cek-mcp`, the universal floor**
- stdio MCP server wrapping the existing Python/shell logic. Tools:
  `handover_read`, `handover_write`, `state_get`, `usage_status`,
  `session_sync`, `context_health`.
- Reuse `cek_paths.py` for all state access so the containment guard and the
  locks apply unchanged.
- Ship config snippets for Warp, Cursor, Claude Code, Codex, Gemini, opencode,
  Cline, Continue, Goose, Zed.
- Ship as **v3.5.0**

**Phase 5 — Warp, honestly**
- `AGENTS.md` generator that emits a Warp-compatible rules file pointing at
  `session_handover.md`, with the caps-filename and `WARP.md`-precedence rules
  handled.
- Wire `cek-mcp` as the write path.
- README capability table that distinguishes **automatic** (hooks) from
  **on-request** (MCP) from **read-only** (rules file). Do not list Warp as
  "supported" without that qualifier.
- Ship as **v3.6.0**

**Phase 6 — v4.0.0**
- Per-runtime eval suites, extending `eval_phase_c.sh`
- Regenerated capability matrix as the single published reference
- `scripts/package_plugin.py` emits per-runtime bundles
- Install-verification script per runtime, on the `eval_codex_install.sh` model

### Decisions to make before Phase 1 starts

1. **Scope.** Six phases is a lot. Gemini CLI + MCP (Phases 0,1,2,4) covers the
   most surface for the least work and makes Warp and every other MCP-speaking
   agent reachable. opencode (Phase 3) is the highest-quality integration but
   the only one needing a second language. Which subset ships first?
2. **opencode: shim or native?** Recommendation above is shim-only.
3. **Warp positioning.** Confirm that "read-only, no auto-save" is acceptable
   to advertise, or drop Warp until it has hooks.
4. **The `.claude/` directory as the core's home.** Five runtimes now source
   logic out of a directory named after one of them. Renaming to `core/` or
   `cek/` is a breaking change for anyone who has pinned paths; leaving it is a
   growing confusion. Decide at v4.0.0, not later.

---

## Appendix — what the current matrix does not say

- Cursor now loads Claude Code hooks natively ("Third Party Hooks"). Since
  v3.0.0 `.claude/settings.json` declares no hooks, so nothing double-fires
  today — but this is a second runtime (after Grok) that reads Claude's config,
  and the invariant "`.claude/settings.json` declares no hooks" is now
  load-bearing for two runtimes. It should be an eval, not a convention.
- Cursor `sessionStart` can return `env`, which is set for every subsequent
  hook in that session. The adapter currently re-derives `CEK_*` on each
  invocation. Minor speedup, and it removes a class of drift.
- Cursor cloud agents run project hooks but **not** `sessionStart`/`sessionEnd`.
  The kit's whole session-boundary model degrades there. Worth a documented
  note; `beforeSubmitPrompt` is the fallback entry point.
