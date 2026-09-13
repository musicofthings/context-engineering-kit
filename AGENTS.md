# Agents — Multi-Agent Workflow Definitions
_Part of context-engineering-kit_

This file defines the roles and responsibilities of subagents used in this project.
Reference these in `agents/` files or when orchestrating multi-agent tasks.

> **Filename matters.** This is the `AGENTS.md` standard, which Codex discovers by
> exact name. It was previously committed as lowercase `agents.md`, which resolves
> on case-insensitive filesystems (macOS, Windows) but not on Linux or in CI, so
> Codex found no instruction file there. Keep the name uppercase.

**How to read this file.** The agent roles and the communication protocol below
are runtime-neutral — they describe what each agent is responsible for, and hold
on any harness. Anything harness-specific is confined to two places: the
*Runtime mechanics* table under each role, and **Invoking subagents** at the end.
Claude-only material (slash commands, `.claude/` paths, hook filenames) lives in
`CLAUDE.md`, not here.

---

## ORCHESTRATOR
**Role:** Coordinates all other agents. Reads session_handover.md at start. Decides which
subagent to dispatch. Writes task completion state back to session_handover.md.

**Responsibilities:**
- Read session state before every work session
- Dispatch specialised agents for defined tasks
- Enforce commit protocol (solo default: commit on main; branches only when requested)
- Refresh the handover before any compaction (see Runtime mechanics below)
- Update `session_handover.md` with every completed phase gate

**Decision tree** (runtime-neutral):
```
New session start
  → Read session_handover.md          ← always; this is the state anchor
  → Read the project instruction file  ← AGENTS.md, plus CLAUDE.md on Claude Code
  → Assess context usage
  → If context is high: compact before starting new work, not during it
  → Dispatch the appropriate agent for the active task
  → After the task: update the handover, then check git status
```

**Runtime mechanics for the two harness-specific steps:**

| Step | Claude Code | Codex | Cursor / Grok |
|------|-------------|-------|---------------|
| Assess context usage | `/token-status` | no equivalent — read `.claude/session/usage-forecast.json` | same as Codex |
| Compact | `/compact-smart` | prepare the handover, then tell the user to run `/compact` | Cursor compacts on its own; `preCompact` reports the real percentage |

---

## CONTEXT-UPDATER
**Role:** Maintains all context engineering files. Invoked by pre-compact hook.

**Responsibilities:**
- Update `session_handover.md` with current task state
- Update CLAUDE.md "Active work context" section
- Update README.md synopsis if architecture changed
- Commit updated files with `chore(context):` prefix

**Trigger:** the pre-compact hook on any runtime, or an explicit handover request
(`/handover` on Claude Code, `$context-engineering-kit:handover` on Codex).

**Output:** Updated files + confirmation message with files changed.

---

## SESSION-SCRIBE
**Role:** Captures and structures work done in a session for future reference.

**Responsibilities:**
- Extract architecture decisions from conversation → `CLAUDE.md` decisions section
- Extract lessons learned → `CLAUDE.md` lessons section
- Identify and record any frozen constraints or hard requirements
- Tag high-value code snippets for preservation before compaction

**Trigger:** an explicit handover request, or the session-end hook on any runtime.

**Output:** Appended sections in CLAUDE.md + confirmation.

---

## VALIDATOR (for bioinformatics projects)
**Role:** Validates bioinformatics pipeline outputs before phase gate is passed.

**Responsibilities:**
- Run test suite before any phase gate
- Validate VCF format and variant counts
- Check ACMG criteria application
- Verify constraint compliance (frozen positions, scores)

**Output:** `results/validation_report.json` + pass/fail decision.

---

## REPORTER (for bioinformatics projects)
**Role:** Generates final reports from pipeline runs.

**Responsibilities:**
- Aggregate scoring data from `results/` directory
- Compute Pareto frontier if applicable
- Generate top-N JSON + CSV + Markdown dossier
- Flag candidates for review with rationale

**Output:** `results/final_report/` directory with ranked results.

---

## Agent communication protocol

All agents communicate through files only — no in-memory state between agents:
```
ORCHESTRATOR → reads:   session_handover.md, .claude/session/state.json
             → writes:  session_handover.md (task updates)
CONTEXT-UPDATER → reads:  stdin (current conversation context)
               → writes: session_handover.md, CLAUDE.md
SESSION-SCRIBE → reads:  conversation history
              → writes: CLAUDE.md (decisions, lessons)
```

## Invoking subagents

The agent prompts are runtime-neutral; only the invocation syntax differs.

```
# Dispatch context updater
Task: update all context files with current session state.
Read CLAUDE.md and session_handover.md, update the active work context sections,
append any new architecture decisions, then confirm files updated.

# Dispatch session scribe
Task: extract all lessons learned and architecture decisions from this conversation.
Append them to CLAUDE.md in the correct sections with today's date.
```

| Runtime | Skill invocation | Notes |
|---------|------------------|-------|
| Claude Code | `/context-health`, `/handover`, `/token-status` | Plugin-scoped form also works: `/context-engineering-kit:handover` |
| Codex | `$context-engineering-kit:context-health`, or the `/skills` picker | Codex has no `/model`; recommend a model and reasoning setting, don't claim to switch it |
| Cursor | Skills are not slash commands — state the task in prose | |
| Grok | Prose; skills are not slash commands | Hooks load from `.grok/hooks/*.json` in a trusted project; review them in Grok's own hooks UI before they run |

Codex-specific caveats:

- Project hooks load only when the `.codex/` layer is trusted. Run `/hooks` once
  to review and trust them; Codex records trust against each hook's hash, so a
  changed hook needs re-approval.
- `SessionEnd` hooks are capped at 3 seconds, so end-of-session work has to be
  fast or move earlier in the lifecycle.
