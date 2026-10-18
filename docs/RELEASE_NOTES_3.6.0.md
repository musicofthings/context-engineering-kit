# context-engineering-kit v3.6.0

**Date:** 2026-10-18
**Tag:** `v3.6.0`
**Artifact:** `context-engineering-kit-3.6.0.zip` (build with `python scripts/package_plugin.py`)

Phase 5 of the [v4.0 universal-runtime plan](PLAN_v4_universal_runtime.md):
**Warp Project Rules Generator & Honest Capability Classification**.

Warp has no lifecycle hooks mechanism (`warpdotdev/warp#6857` remains open since July 2025). This release introduces a generator for standardized, uppercase `AGENTS.md` and `WARP.md` project rules that direct Warp coding agents to `cek-mcp` tools, enforces filename conventions, and establishes a clear 3-tier runtime capability classification across all documentation.

---

## What this brings

1. **Project rules generator (`scripts/generate_agents_rules.py`):**
   - Emits standardized, runtime-neutral `AGENTS.md` rules directing agents to `session_handover.md` and `cek-mcp` tools (`handover_read`, `handover_write`, `context_health`, `usage_status`).
   - Supports `--warp` flag to emit `WARP.md` with explicit precedence notes (Warp prioritises `WARP.md` over `AGENTS.md` when both exist in the same directory).
   - Supports `--check` for drift detection in CI and `check_sync.sh`.
   - Supports `--target` and `--output` flags for targeting external repos.

2. **Honest capability disclosure & 3-tier classification:**
   - Clearly classifies all supported platforms into three capability tiers in `README.md`, `AGENTS.md`, and `docs/runtime-capability-matrix.md`:
     1. **Tier 1 — Automatic (Full Hooks):** Claude Code (CLI & Desktop), Cursor IDE, Codex, Grok Build, opencode.
     2. **Tier 2 — Hybrid (Hooks + MCP):** Antigravity CLI / IDE (`agy`) — 5 hooks (Pre/PostToolUse, Pre/PostInvocation, Stop) with on-demand MCP handover writes for compaction.
     3. **Tier 3 — On-Request / Read-Only (Rules + MCP / Skills):** Warp, Cline, Continue, Goose, Zed, and Claude Cowork.
   - Explicitly discloses Warp limitations: zero automatic hooks, no guaranteed save at 85%, and no automatic pre-compaction snapshot. Context preservation in Warp is on-request via `cek-mcp`.

3. **Case-sensitivity & casing guards:**
   - Enforces uppercase naming convention: Warp and Codex discover project rules files by exact all-caps names (`AGENTS.md`, `WARP.md`).
   - Lowercase `agents.md` is strictly forbidden to prevent silent failures on case-sensitive filesystems (Linux / CI).

4. **Test suite & CI integration:**
   - `scripts/check_sync.sh` asserts `generate_agents_rules.py --check` passes cleanly and tracks entrypoints.
   - `scripts/eval_phase_c.sh` adds 6 negative-controlled test assertions (eval count 54 → 60):
     - `--check` passes on tracked `AGENTS.md`.
     - Drift detection detects modified content (negative control).
     - Missing target file detection (negative control).
     - `--warp` emits `WARP.md` with precedence note and MCP guidance.
     - Git tracks exact uppercase `AGENTS.md`.
     - Explicit disclosure that Warp has no lifecycle hooks in `AGENTS.md` and `README.md`.
