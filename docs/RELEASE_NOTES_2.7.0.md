# context-engineering-kit v2.7.0

**Release date:** 2026-07-28  
**Tag:** `v2.7.0`  
**Artifact:** `context-engineering-kit-2.7.0.zip` (build with `python scripts/package_plugin.py`)

## Highlights

### Real auto-save (Phase A)
At **85%** and **92%** of the usage window, the kit **executes** `generate_session_handover.py` (and optionally `session_sync.sh --save`). It no longer relies only on the model obeying an injected “run /handover” directive.

### Subagent-safe lifecycle (Phase B)
Subagents are tracked with ids and a configurable grace window. SessionStart preserves mid-flight counts and snapshots handover before a usage-window reset instead of zeroing children mid-flight.

### Multi-runtime adapters (Phase C)
| Runtime | Entry |
|---------|--------|
| Claude Code | `hooks/hooks.json` + `.claude/settings.json` |
| Cursor | `.cursor/hooks.json` → adapters |
| Codex | `.codex/hooks.json` → `run.sh` (portable paths) |
| Grok Build | `.grok/hooks/cek-hooks.json` → `run.sh` |

Shared bootstrap: `scripts/cek_runtime.sh`. Regenerate JSON: `python scripts/generate_runtime_hooks.py`.

### Real usage signal preference
`usage-tracker` mirrors rate-limit metrics into `state.json`. `usage-sentinel` prefers fresh `usage-forecast.json` (`rl_5h_pct` / `pct_used`) over wall-clock session age.

### CI
`.github/workflows/cek-quality.yml` — syntax, hook generation check, `check_sync`, Phase A/B/C evals.

## Install

**Plugin zip (Cowork / Desktop):** download `context-engineering-kit-2.7.0.zip` from this release.

**CLI / Cursor / Grok / Codex:**
```bash
git clone https://github.com/musicofthings/context-engineering-kit.git
cd context-engineering-kit
bash setup.sh   # Claude CLI
# Grok: /hooks-trust after open
# Cursor & Codex: open project as cwd
```

## Verify
```bash
bash scripts/check_sync.sh
bash scripts/eval_phase_c.sh
bash scripts/eval_usage_lifecycle.sh
/context-health   # in Claude Code
```

## Docs
- Landing: https://musicofthings.github.io/context-engineering-kit/
- Capability matrix: `docs/runtime-capability-matrix.md`
- Hooks flowchart: `docs/hooks-flowchart.md`

## Breaking / notes
- Solo default: commits on `main` (see `.claude/rules/commit-protocol.md`)
- Grok may load both Claude settings and `.grok/hooks` — doubles are safe via `hook_once` / usage sentinels
- Wall-clock usage remains the fallback when forecast data is missing or older than 2 hours
