# AGENTS.md — Multi-Agent Workflow Definitions
_Part of context-engineering-kit_

This file defines the roles, responsibilities, and runtime protocols for AI agents
collaborating on this project.

> **Filename matters.** This is the `AGENTS.md` standard, which Codex and Warp
> discover by exact uppercase name. If `WARP.md` exists beside it, Warp prioritises
> `WARP.md`. On case-sensitive filesystems (Linux/CI), lowercase names are ignored.

**How to read this file.** The agent roles and communication protocols are
runtime-neutral. Anything harness-specific is documented in the *Runtime mechanics*
table and the *Invoking subagents* guide below.

---

## ORCHESTRATOR
**Role:** Coordinates all other agents. Reads `session_handover.md` at start. Decides which
subagent or tool to dispatch. Writes task completion state back to `session_handover.md`.

**Responsibilities:**
- Read session state before every work session (via `session_handover.md` or `cek-mcp:handover_read`)
- Dispatch specialised agents for defined tasks
- Enforce commit protocol (solo default: commit on main; branches only when requested)
- Refresh the handover before any compaction or context window reset
- Update `session_handover.md` (or call `cek-mcp:handover_write`) with every completed phase gate

**Decision tree** (runtime-neutral):
```
New session start
  → Read session_handover.md (or call cek-mcp:handover_read)  ← state anchor
  → Read project instruction file (AGENTS.md / WARP.md / CLAUDE.md)
  → Assess context usage
  → If context is high: compact before starting new work, not during it
  → Dispatch the appropriate agent / tool for the active task
  → After the task: update the handover, then check git status
```

**Runtime mechanics for harness-specific operations:**

| Runtime | Assess Context Usage | Compact / Save State | Lifecycle Hooks? |
|---------|----------------------|----------------------|:----------------:|
| **Claude Code** | `/token-status` | `/compact-smart` | ✅ Full (30+ events) |
| **Cursor** | Native IDE status | `preCompact` hook snapshots state | ✅ Full (18 events) |
| **Codex** | `.claude/session/usage-forecast.json` | `PreCompact` hook snapshots state | ✅ Full (12 events) |
| **Grok Build** | Native TUI status | `PreCompact` hook snapshots state | ✅ Full (14 events) |
| **opencode** | Native status | Handover injected directly into compaction prompt | ✅ Full (25+ events) |
| **Antigravity CLI / IDE** | `injectSteps` on `PreInvocation` | `cek-mcp:handover_write` (no compaction hook) | ⚠️ Partial (5 events) |
| **Warp** | `cek-mcp:usage_status` | `cek-mcp:handover_write` before manual reset | ❌ **None** (Rules + MCP) |

---

## Warp & MCP Execution Rules

Warp coding agents do not have lifecycle hooks. There is **no automatic save at 85%**
and **no hook before context compaction**. Warp agents must strictly follow these rules:

1. **Session Start:** Read `session_handover.md` immediately, or call MCP tool `handover_read`.
2. **Phase Completion:** When a task or milestone finishes, call MCP tool `handover_write`
   (or write `session_handover.md`) to persist progress for future sessions.
3. **Before Context Reset:** Always run `handover_write` before clearing or compacting the chat.
4. **Health Audit:** Call MCP tool `context_health` to verify repository wiring.

---

## CONTEXT-UPDATER
**Role:** Maintains all context engineering files. Invoked by pre-compact hook or manual request.

**Responsibilities:**
- Update `session_handover.md` with current task state
- Update `CLAUDE.md` / `AGENTS.md` "Active work context" section
- Update `README.md` synopsis if architecture changed
- Commit updated files with `chore(context):` prefix

**Trigger:** Hook on supported runtimes, explicit `/handover` / `$handover`, or `cek-mcp:handover_write`.

---

## SESSION-SCRIBE
**Role:** Captures and structures work done in a session for future reference.

**Responsibilities:**
- Extract architecture decisions from conversation → decisions log
- Extract lessons learned → lessons log
- Identify and record any frozen constraints or hard requirements
- Tag high-value code snippets for preservation before compaction

---

## VALIDATOR (for bioinformatics / science pipelines)
**Role:** Validates pipeline outputs before phase gate is passed.

**Responsibilities:**
- Run test suite before any phase gate
- Validate domain formats (e.g., VCF, PDB, coordinates)
- Check scoring criteria and constraint compliance

---

## REPORTER (for bioinformatics / pipeline projects)
**Role:** Generates final reports from pipeline runs.

**Responsibilities:**
- Aggregate scoring data from output directories
- Generate structured candidate dossiers (Markdown, JSON, CSV)
- Flag candidates for review with rationale

---

## Agent Communication Protocol

All agents communicate through files and MCP tools — no in-memory state between agents:
```
ORCHESTRATOR    → reads:  session_handover.md, .claude/session/state.json, or cek-mcp:handover_read
                → writes: session_handover.md, or cek-mcp:handover_write
CONTEXT-UPDATER → reads:  conversation history, current task status
                → writes: session_handover.md, CLAUDE.md, AGENTS.md
SESSION-SCRIBE  → reads:  conversation history
                → writes: CLAUDE.md (decisions, lessons)
```

## Invoking Subagents & Tools

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

| Runtime | Skill / Tool Invocation | Notes |
|---------|-------------------------|-------|
| **Claude Code** | `/context-health`, `/handover`, `/token-status` | Plugin-scoped slash commands |
| **Codex** | `$context-health`, `$handover`, or `/skills` | Documented `$` mentions or picker |
| **Cursor** | Stated in prose in agent prompt | Uses project hooks |
| **Grok Build** | Prose instructions | Needs `/hooks-trust` on first open |
| **opencode** | Local plugin or slash commands | Injects handover into compaction |
| **Antigravity CLI / IDE** | Prose instructions or `cek-mcp` tools | PreToolUse guard & invocation banner |
| **Warp** | MCP tools (`handover_read`, `handover_write`) | Guided by this rules file; no hooks |

### Runtime-Specific Caveats

- **Warp:** Warp has no lifecycle hooks mechanism (`warpdotdev/warp#6857` remains open). Context preservation is **on-request** via `cek-mcp`.
- **Codex:** Project hooks load only when the `.codex/` layer is trusted. `SessionEnd` hooks are capped at 3 seconds, so end-of-session work must be fast.
- **Antigravity CLI / IDE:** No compaction event exists; call `cek-mcp:handover_write` to preserve state across compacts.
