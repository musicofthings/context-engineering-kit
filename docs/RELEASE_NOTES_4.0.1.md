# context-engineering-kit v4.0.1

**Date:** 2026-10-19
**Tag:** `v4.0.1`
**Artifact:** `context-engineering-kit-4.0.1.zip` (build with `python scripts/package_plugin.py --runtime all`)

Correctness release: **every runtime claim re-verified against its live doc**, and the
three findings that re-verification turned up are closed.

All six runtime sources were fetched and read on 2026-10-19. `verified` in
`config/runtime_events.json` now reads `2026-10-19` for all of them because each was
actually re-checked, not because the file was touched.

---

## Fixed

### 1. Antigravity's `SessionStart` is native — the kit was synthesizing it

`antigravity.google/docs/hooks/` lists **six** events, and `SessionStart` is one of them:
it fires once before the first model invocation and returns `injectSteps`, exactly like
`PreInvocation`. v3.5.0–v4.0.0 read that surface as five events and synthesized
SessionStart on `PreInvocation` when `invocationNum == 0`.

- `.agents/hooks.json` now binds the `session-start` chain to the native event.
- `PreInvocation` keeps the usage sentinel alone. Antigravity has no `UserPromptSubmit`,
  so it remains the only pre-model point where the thresholds can be evaluated.
- The registry's antigravity `events` map gains `SessionStart`, so
  `cek_runtime_supports SessionStart` answers correctly on that runtime for the first time.

### 2. A null `invocation_num` silently skipped the session banner

`.agents/hooks/run.sh` normalised payloads by writing `data.get("invocationNum", …)`
into `invocation_num` unconditionally. The key was therefore always present and `null`
when the payload lacked it, which made every downstream `.get(key, default)` dead code
and handed the shell the string `"None"`. `[ "None" -eq 0 ]` raised
`integer expression expected` and fell through to the non-session branch.

The normaliser now omits absent keys instead of nulling them — a fix that covers
`transcript_path`, `artifact_dir`, `fully_idle`, `stop_reason`, `step_idx` and
`file_path` as well. Two regression tests cover it (`eval_phase_c`,
`eval_antigravity_install`).

### 3. `multi_replace_file_content` escaped change tracking

The Antigravity `PostToolUse` matcher read `write_to_file|replace_file_content`.
Antigravity documents `multi_replace_file_content` as its non-contiguous multi-edit
tool, so those edits never reached `track-changes.sh`. The matcher now covers all three.

---

## Documentation corrected

- **README's Lifecycle Hooks column was wrong for three runtimes.** It read "18 events"
  for Cursor (12 bound, 21 documented) and "25+ events" for opencode (9 bound), mixing
  kit coverage with runtime inventory. Every cell is now `N of M events` — N bound by the
  kit, M documented by the vendor — and `generate_runtime_hooks.py --check` asserts both.
- **README claimed `PostInvocation` was wired.** It is not, and `Stop` already covers
  end-of-turn. The Option I table says so now.
- **Registry omitted three events Claude Code emits.** `MessageDisplay`, `Elicitation`
  and `ElicitationResult` were absent from `runtimes.claude.events`, which per the file's
  own `_events_format` asserts the runtime does not emit them. It does; the kit
  deliberately wires none of them, the way `WorktreeCreate` was already handled. They are
  now in the map, marked `_not wired_` in the generated matrix.
- **Cursor's `loop_limit`** (default 5 for Cursor hooks on `stop` / `subagentStop`,
  `null` for Claude Code hooks) is documented in the capability matrix.
- **`afterAgentThought`** joined the matrix's *Deliberately unused* list so that list
  stays exhaustive against Cursor's 21 documented events.
- v3.5.0's release note carries an erratum rather than a rewrite.

---

## New guard

`validate_readme_counts()` in `scripts/generate_runtime_hooks.py` counts bound events
from each shipped hook config and takes the documented total from the registry's new
`documented_event_total` field, then holds README's tier table to both. The three wrong
counts above would all have failed it. `--check` runs it, so `check_sync.sh` and CI do too.

---

## Verified unchanged

No drift found in:

- **Grok Build** — 14 events, camelCase payload, 5s default timeout, `PreToolUse` the only
  blocking event, reads `.claude/settings.json` and `.cursor/hooks.json` as well. Its doc
  is still dated 2026-07-02.
- **Codex** — 12 events exactly. Hash-based hook trust, the ~2,500-token output spill,
  `additionalContextLimit`, and the plugin-manifest `hooks` override all still hold.
- **opencode** — all 8 canonical mappings plus `file.edited`; the
  `experimental.session.compacting` contract is unchanged.
- **Cursor** — all 12 bound events still exist; cloud agents still defer
  `sessionStart` / `sessionEnd` / the MCP hooks.
- **Warp** — still no hooks mechanism. `warpdotdev/warp#6857` remains open (opened
  2025-07-17), and `WARP.md` still takes precedence over `AGENTS.md`. Tier 3 stands.

All six `source` URLs return 200. All 8 eval suites pass.
