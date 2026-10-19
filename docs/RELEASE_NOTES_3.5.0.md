# context-engineering-kit v3.5.0

**Date:** 2026-10-18
**Tag:** `v3.5.0`
**Artifact:** `context-engineering-kit-3.5.0.zip` (build with `python scripts/package_plugin.py`)

Phase 3 of the [v4.0 universal-runtime plan](PLAN_v4_universal_runtime.md):
**Antigravity CLI / IDE adapter (`agy`)**.

Google sunset Gemini CLI on 2026-06-18, replaced by Antigravity CLI. This release adds
native hook adapter support for Antigravity in `.agents/hooks/run.sh` with
`.agents/hooks.json` generated from the single runtime registry.

---

## What this brings

1. **Native hook adapter (`.agents/hooks/run.sh`):**
   - Dispatches to the single shared logic core under `.claude/hooks/`.
   - Normalises Antigravity's protojson camelCase payloads (`conversationId`,
     `workspacePaths`, `transcriptPath`, etc.) to canonical snake_case.
   - Maps Antigravity's nested tool calls and PascalCase tool arguments:
     `toolCall.name` (`run_command` → `Bash`, `write_to_file` → `Write`,
     `replace_file_content` → `Edit`, `view_file` → `Read`) and maps arguments
     (`CommandLine` → `command`, `TargetFile` → `file_path`, etc.).

2. **JSON output contract handling:**
   - `PreToolUse`: translates the core's exit 2 into Antigravity's blocking JSON
     contract `{"decision": "deny", "reason": "..."}`, allowing safe commands with
     `{"decision": "allow"}`.
   - `PostToolUse`: returns `{}` to cleanly complete file change tracking.
   - `Stop`: runs the stop chain and returns `{}` to cleanly allow agent termination.

3. **Session boundary synthesis & context injection:**
   - Synthesizes `SessionStart` when `PreInvocation` has `invocationNum == 0`, injecting
     the session banner and morning brief via `injectSteps` (`ephemeralMessage`).
   - Runs `usage-sentinel.sh` on subsequent turns, surfacing usage alerts via `injectSteps`.

4. **Honest capability disclosure & limitations:**
   - ~~Antigravity emits 5 events only; it has **no native session start/end or compaction events**.~~
     **Erratum (v4.0.1, 2026-10-19):** Antigravity emits **six** events and `SessionStart` is
     native. The synthesis described above was a workaround for a misreading of
     `antigravity.google/docs/hooks`; the chain binds the real event as of v4.0.1. The absence
     of session **end** and compaction events still holds.
   - Compaction context preservation is not triggerable via hooks on Antigravity; on-demand
     compaction handover recovery is handled via `cek-mcp` (`handover_write` / `handover_read`).

5. **Test coverage:**
   - 8 new negative-controlled assertions added to `scripts/eval_phase_c.sh` (evals 46 → 54).
   - Validates syntax, runtime capability queries, destructive command blocking, safe command
     allowing, session banner synthesis, and stop output.
