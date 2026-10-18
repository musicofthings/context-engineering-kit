# context-engineering-kit v4.0.0

**Date:** 2026-10-18
**Tag:** `v4.0.0`
**Artifact:** `context-engineering-kit-4.0.0.zip` (build with `python scripts/package_plugin.py --runtime all`)

Major Milestone Release: **Universal Runtime Support (v4.0.0)**.

This release concludes the six-phase universal runtime roadmap defined in [`PLAN_v4_universal_runtime.md`](PLAN_v4_universal_runtime.md). Context-engineering-kit now provides unified, automated context preservation across eight distinct AI coding environments while sharing a single, hardened logic core.

---

## The Universal Architecture

Across all supported runtimes, context preservation, token tracking, dangerous command mitigation, and session handovers operate through a single truth:

1. **Single Source of Truth:**
   - Unified runtime registry in `config/runtime_events.json` defining verified event capabilities, payloads, and documentation sources.
   - All runtime hook configurations (`.cursor/hooks.json`, `.codex/hooks.json`, `.grok/hooks/cek-hooks.json`, `.agents/hooks.json`) and `docs/runtime-capability-matrix.md` are dynamically generated from this single registry.

2. **Three-Tier Capability Model:**
   - **Tier 1 — Automatic (Full Hooks):** Claude Code (CLI & Desktop), Cursor IDE, Codex, Grok Build, and opencode. Hooks fire automatically at session start/end, tool execution, and context compaction.
   - **Tier 2 — Hybrid (Hooks + MCP):** Antigravity CLI / IDE (`agy`). Emits five lifecycle events with custom protojson payloads and JSON decision handling; supplemented by `cek-mcp` for on-demand compaction state preservation.
   - **Tier 3 — On-Request / Read-Only (Rules + MCP / Skills):** Warp, Cline, Continue, Goose, Zed, and Claude Cowork. Standardized `AGENTS.md` / `WARP.md` project rules direct coding agents to `cek-mcp` tools (`handover_read`, `handover_write`, `context_health`, `usage_status`).

3. **Per-Runtime Distribution Bundles:**
   - `scripts/package_plugin.py` now supports `--runtime {universal,claude,codex,antigravity,opencode,cursor,all}`.
   - Tailored distribution zips exclude irrelevant runtime configs while packaging full hook adapters, skills, and documentation.

4. **Comprehensive Test Automation & Verification:**
   - New master test suite `scripts/eval_all_runtimes.sh` orchestrates all 8 evaluation suites:
     - `check_sync.sh`: single-source wiring, absolute path smell test, rules sync.
     - `eval_phase_c.sh`: multi-runtime adapter contracts, Grok normalizer, Cursor isolation, registry authority, uppercase filename guards.
     - `eval_mcp.py`: stdio MCP server protocol lifecycle, tool schema, containment guard, read-only mode.
     - `eval_usage_lifecycle.sh`: token tracking, threshold auto-saves (85%/92%), subagent grace periods.
     - `eval_hooks_smoke.sh`: core hook execution, state containment, session boundary transitions.
     - `eval_codex_install.sh`: end-to-end Codex plugin package, install, and cwd-independent hook dispatch.
     - `eval_antigravity_install.sh`: end-to-end Antigravity plugin package, install, workspace resolution, and state isolation.
     - `eval_opencode.mjs`: opencode plugin TypeScript module, compaction prompt injection, thrown error blocking.
   - Over 220 negative-controlled assertions pass with 100% success.
