---
name: compact-smart
description: Run a relevance-scored compaction that preserves the most important context. Unlike /compact which summarises everything uniformly, this retains code snippets, architecture decisions, and active task state at higher fidelity.
user-invocable: true
auto-invoke-when: context is above 70%, user wants to compact without losing important details
---

# Smart Compaction — Relevance-Scored Context Preservation

## What this does differently from `/compact`

Standard `/compact` summarises all conversation turns uniformly.
`/compact-smart` (this skill) first:
1. Identifies high-value content to preserve verbatim
2. Summarises low-value content aggressively
3. Generates/updates `session_handover.md` first
4. Then runs compaction with a custom summary prompt

## Step 1 — Pre-compaction snapshot

Before compacting, capture and write to `session_handover.md`:
- Active task, phase, next action
- Any code snippets that were just written (file paths + function names)
- Architecture decisions made this session
- Any errors encountered and how they were resolved

Confirm: "✅ Pre-compaction snapshot written to session_handover.md"

## Step 2 — Identify what to preserve

Scan this conversation and tag:

**HIGH VALUE — preserve verbatim:**
- Code that was written and accepted (functions, configs)
- Error messages and their solutions
- Architecture decisions with rationale
- File paths and their purposes
- Commit hashes or branch names
- ACMG criteria in use (if bioinformatics work)
- Any frozen constraints or requirements

**LOW VALUE — summarise aggressively:**
- Exploration that was abandoned
- Repeated requests for clarification
- Verbose error output beyond the key error line
- Multiple iterations of the same problem

## Step 3 — Run compaction with custom prompt

Execute:
```
/compact Preserve verbatim: all code written this session, file paths modified, architecture decisions, active task state, next action. Summarise: exploratory discussion, abandoned approaches, verbose output. The project is context-engineering-kit. Branch: [branch]. Active task: [task].
```

## Step 4 — Verify and report

After compaction, report:
- "✅ Smart compaction complete"
- "Preserved: [N] code blocks, [N] decisions, active task state"
- "Estimated context now: [X]%"
- "session_handover.md is current — read it to verify"
