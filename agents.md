# Agents — Multi-Agent Workflow Definitions
_Part of context-engineering-kit_

This file defines the roles and responsibilities of subagents used in this project.
Reference these in `.claude/subagents/` files or when orchestrating multi-agent tasks.

---

## ORCHESTRATOR
**Role:** Coordinates all other agents. Reads session_handover.md at start. Decides which
subagent to dispatch. Writes task completion state back to session_handover.md.

**Responsibilities:**
- Read session state before every work session
- Dispatch specialised agents for defined tasks
- Enforce commit protocol (never commit directly to main)
- Call `/handover` before any compaction
- Update `session_handover.md` with every completed phase gate

**Decision tree:**
```
New session start
  → Read session_handover.md
  → Read CLAUDE.md
  → Assess context usage (/token-status)
  → If context > 70%: run /compact-smart first
  → Dispatch appropriate agent for active task
  → After task: update handover + check git status
```

---

## CONTEXT-UPDATER
**Role:** Maintains all context engineering files. Invoked by pre-compact hook.

**Responsibilities:**
- Update `session_handover.md` with current task state
- Update CLAUDE.md "Active work context" section
- Update README.md synopsis if architecture changed
- Commit updated files with `chore(context):` prefix

**Trigger:** Called by `.claude/hooks/pre-compact.sh` and by `/handover` skill.

**Output:** Updated files + confirmation message with files changed.

---

## SESSION-SCRIBE
**Role:** Captures and structures work done in a session for future reference.

**Responsibilities:**
- Extract architecture decisions from conversation → `CLAUDE.md` decisions section
- Extract lessons learned → `CLAUDE.md` lessons section
- Identify and record any frozen constraints or hard requirements
- Tag high-value code snippets for preservation before compaction

**Trigger:** Invoked by `/handover` and `session-end.sh` hook.

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

## Invoking subagents in Claude Code

```
# Dispatch context updater
Task: update all context files with current session state.
Read CLAUDE.md and session_handover.md, update the active work context sections,
append any new architecture decisions, then confirm files updated.

# Dispatch session scribe
Task: extract all lessons learned and architecture decisions from this conversation.
Append them to CLAUDE.md in the correct sections with today's date.
```
