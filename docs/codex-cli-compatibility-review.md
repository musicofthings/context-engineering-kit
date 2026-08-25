# Codex CLI Compatibility Review and Implementation Handoff

Status: implementation required
Review date: 2026-07-31
Kit version: 2.7.0
Source revision: `f8e0259cd994b7b6969af247db526fc926bb8e2c`
Codex CLI reviewed: 0.146.0

## Outcome

Context Engineering Kit has a useful Codex project adapter, but it is not yet a
compliant or reliable Codex CLI plugin. Four issues block release:

1. No `.codex-plugin/plugin.json`.
2. The Codex adapter swallows blocking exit codes.
3. Generated hook files contain events Codex does not support.
4. Hook execution assumes the repository root is the cwd and Bash is available.

The implementation should preserve existing Claude, Cursor, and Grok behavior.
Do not solve Codex compatibility by changing shared behavior without runtime
fixtures proving that the other adapters remain compatible.

## Recommended implementation order

1. **Packaging and security:** CEK-CODEX-001 through CEK-CODEX-004.
2. **Payload and state adapters:** CEK-CODEX-005, CEK-CODEX-009, and
   CEK-CODEX-010.
3. **Codex-native instructions and skills:** CEK-CODEX-006 through
   CEK-CODEX-008.
4. **Timing and performance:** CEK-CODEX-011.
5. **CI and documentation:** CEK-CODEX-012 and CEK-CODEX-013.

## Findings

### CEK-CODEX-001 — Add a compliant Codex plugin package

Priority: P0
Area: packaging, discovery

#### Current state

- The repository contains `.claude-plugin/plugin.json`, but no
  `.codex-plugin/plugin.json`.
- `scripts/package_plugin.py` reads its version only from the Claude manifest.
- The README's Codex installation path clones the repository and relies on
  project hooks; it does not install a self-contained Codex plugin.

#### Required change

- Add `.codex-plugin/plugin.json`.
- Declare the root `skills/` directory and a Codex-specific hook file. Do not
  point Codex at the existing Claude-oriented `hooks/hooks.json` until its
  unsupported events and semantics have been removed.
- Update `scripts/package_plugin.py` so a release archive validates and includes
  both runtime manifests.
- Add Codex plugin installation and upgrade instructions.

A minimal direction is:

```json
{
  "name": "context-engineering-kit",
  "version": "2.7.0",
  "skills": "./skills/",
  "hooks": "./hooks/codex-hooks.json"
}
```

Confirm the final fields against the current Codex plugin manifest reference
before implementation.

#### Done when

- Codex recognizes the packaged plugin without cloning CEK into the target
  repository.
- `$context-engineering-kit:context-health` appears through Codex skill
  discovery.
- Plugin hooks load from the packaged plugin.
- CI rejects an archive with a missing or invalid Codex manifest.

### CEK-CODEX-002 — Preserve blocking hook exit codes

Priority: P0
Area: security

#### Current state

`.codex/hooks/run.sh` dispatches generic hooks using:

```bash
printf '%s' "$INPUT" | cek_run_hook "$script" || true
```

`.claude/hooks/guard-dangerous.sh` uses exit code `2` to block a dangerous tool
call. The adapter converts that result to success, so the guard cannot block a
Codex command.

#### Required change

- Preserve exit code `2`, stderr, and any structured output expected by Codex.
- Decide explicitly how other nonzero hook failures should be handled; do not
  use a blanket `|| true`.
- Apply the same rule to named chains when one child hook blocks.

#### Done when

- A Codex `PreToolUse` fixture containing a known destructive command exits `2`.
- A safe command exits `0`.
- The block reason reaches Codex.
- A regression test fails if any adapter layer neutralizes the blocking status.

### CEK-CODEX-003 — Generate only supported Codex events

Priority: P0
Area: hook schema, correctness

#### Current state

`scripts/generate_runtime_hooks.py` currently emits these unsupported Codex
events:

- `PostToolUseFailure`
- `StopFailure`
- `Notification`

The plugin-level `hooks/hooks.json` additionally contains:

- `InstructionsLoaded`
- `FileChanged`

The current runtime capability matrix incorrectly marks several of these as
supported by Codex.

#### Required change

- Replace the shared event list with an explicit per-runtime capability map.
- Generate Codex events only from the currently supported set:
  `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`,
  `PostCompact`, `UserPromptSubmit`, `SubagentStop`, `Stop`, `SessionStart`,
  `SubagentStart`, and `SessionEnd`.
- Detect failed shell commands inside `PostToolUse` by parsing `tool_response`.
- Replace `Notification` with documented Codex `notify` or TUI notification
  configuration.
- Remove or redesign `StopFailure`, `InstructionsLoaded`, and `FileChanged`.
- Generate a dedicated `hooks/codex-hooks.json` for the plugin manifest.

#### Done when

- Schema validation rejects unknown Codex event names.
- Generated project and plugin hook files contain only supported events.
- `docs/runtime-capability-matrix.md` matches the generator.

### CEK-CODEX-004 — Make hook execution cwd-independent and Windows-native

Priority: P0
Area: portability

#### Current state

Generated commands use relative paths such as:

```text
bash .codex/hooks/run.sh ...
```

These fail when Codex starts below the repository root. They also require Bash,
which is not guaranteed in native Windows Codex installations.

#### Required change

Implement two supported modes:

1. **Installed plugin:** resolve commands and assets through `PLUGIN_ROOT`.
2. **Project adapter:** resolve the Git/project root before invoking the
   adapter.

Also:

- Add `commandWindows` entries or replace the adapter with a cross-platform
  Python entrypoint.
- Avoid machine-specific absolute paths in committed JSON.
- Update setup diagnostics to check for `codex`, not only `claude.cmd`.

#### Done when

- Hooks work when Codex starts at the repository root and from a nested
  subdirectory.
- Hooks work in native PowerShell without Git Bash.
- Linux/macOS Bash behavior remains functional.
- Generated configuration contains no machine-local paths.

### CEK-CODEX-005 — Add Codex-native hook payload parsing

Priority: P1
Area: Stop lifecycle, usage tracking, state extraction

#### Current state

- `.codex/hooks/run.sh` invokes `scripts/usage-tracker.py` with empty stdin, so
  the tracker exits without updating state.
- `scripts/usage-tracker.py` expects Claude fields including `rate_limits`,
  `cost`, `usage`, `turn_count`, and Claude transcript records.
- `.claude/hooks/extract-state-on-stop.sh` reads the last assistant response
  from a Claude-shaped transcript.
- `.claude/hooks/stop.sh` expects `stop_reason`, which is not part of the current
  Codex Stop payload.
- Codex provides `last_assistant_message`; its transcript format is explicitly
  unstable.

#### Required change

- Define normalized internal event types for every hook the shared core uses.
- Add a Codex parser that consumes stable fields such as `session_id`, `cwd`,
  `model`, `last_assistant_message`, and documented event-specific fields.
- Pass the original Stop JSON to the usage/state chain.
- Treat transcript parsing as an optional guarded fallback, not the primary
  Codex integration.
- Do not fabricate rate-limit or cost precision that Codex hooks do not expose.
  Label estimates as estimates or use Codex-native status data where available.

#### Done when

- Codex Stop fixtures update state and extract the next action from
  `last_assistant_message`.
- Missing optional fields do not crash or silently invent values.
- Claude Stop fixtures continue to pass.

### CEK-CODEX-006 — Use Codex instruction discovery

Priority: P1
Area: project instructions

#### Current state

- The repository has lowercase `agents.md`, not exact `AGENTS.md`.
- Its content directs agents to `CLAUDE.md`, `.claude/`, and Claude slash
  commands.
- `skills/init-cek/SKILL.md` creates `CLAUDE.md` rather than `AGENTS.md`.

Lowercase discovery may appear to work on case-insensitive Windows filesystems
but fails on case-sensitive systems.

#### Required change

- Add exact `AGENTS.md` for Codex.
- Split durable, runtime-neutral project context from Claude-specific
  instructions.
- Make `init-cek` preserve any existing `AGENTS.md` and require confirmation
  before replacing substantive content.
- Keep `CLAUDE.md` as a separate Claude adapter where needed.

#### Done when

- Codex discovers instructions on both Windows and Linux.
- Initialization never overwrites an existing substantive `AGENTS.md`.
- Generated instructions contain valid Codex skill syntax.

### CEK-CODEX-007 — Correct skill invocation and metadata

Priority: P1
Area: skills

#### Current state

Skill descriptions and README examples advertise Claude-style commands such as
`/context-health`, `/handover`, and `/model-switch`. Codex explicit skill
invocation uses `$skill-name` or the `/skills` picker.

Skill frontmatter also includes Claude-specific keys such as `user-invocable`,
`auto-invoke-when`, and `args` without a Codex metadata layer.

#### Required change

- Make root `skills/*/SKILL.md` descriptions runtime-neutral.
- Document installed Codex invocations such as
  `$context-engineering-kit:context-health`.
- Add `skills/<name>/agents/openai.yaml` where invocation policy, interface
  metadata, or dependencies are needed.
- Decide whether `.claude/skills/` remains generated from the root skills or is
  intentionally runtime-specific. Avoid manually maintained copies.

#### Done when

- Every root skill is discoverable by Codex.
- Every README Codex example uses `$skill` or `/skills`.
- `scripts/check_sync.sh` or its replacement prevents cross-runtime skill drift.

### CEK-CODEX-008 — Replace or disable Claude-only skill behavior

Priority: P1
Area: model selection, compaction, status

#### Current state

- `skills/model-switch/SKILL.md` hardcodes Haiku, Sonnet, Opus, Claude model
  identifiers, and `/fast`.
- It claims a skill can execute `/model`.
- `skills/compact-smart/SKILL.md` tells the agent to execute `/compact` and
  expects a `custom_instructions` PreCompact field not documented for Codex.
- `skills/token-status/SKILL.md` and `skills/usage-forecast/SKILL.md` assume
  Claude plugin environment variables and Claude usage data.
- Claude's custom shell status line does not map to Codex. Codex uses
  `tui.status_line` configuration.

#### Required change

- Implement runtime-specific skill sections or separate runtime variants.
- For Codex, recommend model and reasoning settings without claiming to switch
  them automatically.
- Have smart compaction prepare a handover, then instruct the user to invoke
  `/compact`.
- Use documented Codex status/configuration capabilities and clearly label
  unavailable usage data.
- Ensure skill-executed scripts have stable paths; do not assume
  `CLAUDE_PLUGIN_ROOT` exists outside plugin hook commands.

#### Done when

- No Codex-facing skill recommends Claude model identifiers or `/fast`.
- No skill claims it executed a TUI slash command.
- Token/status output distinguishes measured data from estimates.

### CEK-CODEX-009 — Redesign PermissionRequest handling

Priority: P1
Area: permissions, security

#### Current state

`.claude/hooks/auto-approve-permissions.sh` expects `Write`, `Edit`, or
`MultiEdit` and a `tool_input.file_path`. Codex uses canonical `apply_patch`,
with patch content in `tool_input.command`.

The intended allow-list also includes broad targets such as `README.md` and all
files below `docs/`.

#### Required change

- Prefer Codex sandbox/writable-root configuration over automatic approval for
  `apply_patch`.
- If edit auto-approval is retained, parse every path affected by the patch and
  reject ambiguous or out-of-scope patches.
- Restrict approvals to dedicated CEK state files.
- Keep shell-command approvals narrowly anchored and reject shell control
  operators.

#### Done when

- Canonical `apply_patch` fixtures do not bypass normal approval.
- Multi-file and path-traversal patches are denied or fall through.
- README and arbitrary documentation edits are not silently approved.

### CEK-CODEX-010 — Make initialization explicit and separate state scopes

Priority: P1
Area: state management, repository hygiene

#### Current state

`config/plugin_settings.json` enables `auto_activate_new_repos` by default.
SessionStart can create `.claude/session/` and `session_handover.md` in any
previously untouched Git repository. Initialization and setup workflows may
also stage or commit context files automatically.

Codex plugin hooks expose a writable `PLUGIN_DATA` directory, but CEK does not
use it.

#### Required change

- Default automatic initialization to off.
- Require explicit `$context-engineering-kit:init-cek` or equivalent consent
  before creating repository files.
- Store plugin-private mutable data under `PLUGIN_DATA`.
- Store intentionally shared repository state under a neutral `.cek/`
  directory, while providing migration from `.claude/session/`.
- Do not initialize Git, stage files, or commit without explicit user
  authorization.

#### Done when

- Installing or starting the plugin does not dirty an unrelated repository.
- Plugin updates do not erase mutable state.
- Migration is idempotent and preserves existing Claude workflows.

### CEK-CODEX-011 — Correct hook timing and timeout behavior

Priority: P2
Area: performance, lifecycle

#### Current state

Generated hooks use `"async": true`, but Codex currently parses this key
without executing command hooks asynchronously. These hooks therefore block
the session.

The generated Codex `SessionEnd` hook requests 30 seconds, while Codex limits
SessionEnd hooks to three seconds.

#### Required change

- Remove reliance on Codex `async`.
- Give every Codex hook a short explicit timeout.
- Keep SessionEnd at or below three seconds.
- Move expensive work earlier in the lifecycle, combine redundant hooks, or
  use a carefully managed background process where appropriate.

#### Done when

- No Codex hook relies on `async`.
- Timeout validation is part of generation/CI.
- SessionEnd finishes within the documented limit.
- Normal prompt and Stop latency is measured and documented.

### CEK-CODEX-012 — Add semantic Codex CI coverage

Priority: P2
Area: testing, maintainability

#### Current state

`.github/workflows/cek-quality.yml` runs only on Ubuntu. Codex checks primarily
verify shell syntax, generated-file drift, and the presence of event names.
They do not test Codex semantics.

#### Required change

Add:

- Codex manifest validation.
- Supported-event allow-list validation.
- Exit-code and structured-output tests.
- Payload fixtures for every supported Codex event used by CEK.
- Root-cwd and nested-cwd tests.
- Windows CI covering `commandWindows` or the cross-platform entrypoint.
- SessionEnd timeout validation.
- Skill discovery/invocation and `AGENTS.md` case-sensitivity checks.
- Tests proving generated files and runtime capability documentation agree.

#### Done when

- A regression of CEK-CODEX-002 through CEK-CODEX-011 fails CI.
- CI runs on both `ubuntu-latest` and `windows-latest`.

### CEK-CODEX-013 — Correct compatibility claims and installation docs

Priority: P2
Area: documentation

#### Current state

README and `docs/runtime-capability-matrix.md` claim broader Codex compatibility
than the implementation provides. Codex instructions currently require root
cwd, use Claude slash commands, and do not describe plugin packaging, project
trust, native Windows execution, or Codex status configuration.

#### Required change

- Update the capability matrix from the same runtime capability data used by
  the generator.
- Document both installed-plugin and per-project adapter modes.
- Document project trust requirements.
- Use Codex-native skill syntax and configuration.
- Clearly identify features unavailable on Codex.
- Remove the “full support” claim until all P0 and P1 acceptance criteria pass.

#### Done when

- A new Codex user can install, verify, initialize, use, and remove CEK using
  only the README.
- Documentation does not list unsupported events or Claude-only behavior as
  Codex features.

## Likely files to change

```text
.codex-plugin/plugin.json                   new
.codex/hooks.json                           generated
.codex/hooks/run.sh                         adapter or replacement
hooks/codex-hooks.json                      new/generated
hooks/hooks.json                            keep Claude-specific or split
scripts/generate_runtime_hooks.py           capability-aware generation
scripts/cek_runtime.sh                      normalized runtime interface
scripts/usage-tracker.py                    Codex payload/state support
scripts/auto_init_project.sh                opt-in initialization
.claude/hooks/extract-state-on-stop.sh       runtime-neutral input
.claude/hooks/stop.sh                        runtime-neutral input
.claude/hooks/auto-approve-permissions.sh    Codex permission semantics
skills/*/SKILL.md                           Codex invocation/runtime language
skills/*/agents/openai.yaml                 optional Codex metadata
AGENTS.md                                   new
agents.md                                   rename, replace, or retain adapter
scripts/package_plugin.py                   dual-manifest package validation
scripts/check_sync.sh                       generated-source validation
scripts/eval_phase_c.sh                     semantic Codex fixtures
.github/workflows/cek-quality.yml            Windows and schema coverage
docs/runtime-capability-matrix.md            corrected event support
README.md                                   Codex install and usage
```

## Final verification checklist

Run the existing checks:

```bash
python scripts/generate_runtime_hooks.py --check
bash scripts/check_sync.sh
bash scripts/eval_phase_c.sh
bash scripts/eval_usage_lifecycle.sh
git diff --check
```

Then verify the new Codex acceptance suite covers:

- [ ] Packaged plugin has a valid `.codex-plugin/plugin.json`.
- [ ] Skills load through `$context-engineering-kit:<skill>`.
- [ ] Plugin hooks and project hooks both load.
- [ ] Dangerous-command guard propagates exit `2`.
- [ ] Hook files contain only supported Codex events.
- [ ] Stop/state extraction uses stable Codex fields.
- [ ] Hooks work from nested cwd.
- [ ] Native Windows execution does not require Bash.
- [ ] Installing or starting CEK does not dirty a repository.
- [ ] No hook relies on unsupported asynchronous execution.
- [ ] SessionEnd completes in no more than three seconds.
- [ ] Linux and Windows CI pass.
- [ ] Claude, Cursor, and Grok regression suites still pass.

## Official Codex references

- Plugin structure: <https://learn.chatgpt.com/docs/build-plugins>
- Skills: <https://learn.chatgpt.com/docs/build-skills>
- Hooks and payloads: <https://learn.chatgpt.com/docs/hooks>
- `AGENTS.md`: <https://learn.chatgpt.com/docs/agent-configuration/agents-md>
- Configuration: <https://learn.chatgpt.com/docs/config-file/config-reference>
