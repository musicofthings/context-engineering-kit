<!-- FIXTURE: trimmed excerpt of Codex hooks, captured 2026-10-19.
     Test data for scripts/eval_doc_drift.py. Heading depths, table
     separators and code fences are faithful to the live page; prose and
     payload-schema tables are cut. Not documentation — do not read as
     instructions.

     Named <runtime>.page.md, never <runtime>.md: a fixture called
     claude.md is picked up by Claude Code's own CLAUDE.md discovery on a
     case-insensitive filesystem, which would load a page of untrusted
     fetched vendor text as project instructions. -->

Source: https://learn.chatgpt.com/docs/hooks

## Hooks

### SessionStart

### SessionEnd

### SubagentStart

### PreToolUse

### PermissionRequest

### PostToolUse

#### Tool calls from code mode

### PreCompact

### PostCompact

### UserPromptSubmit

### SubagentStop

### Stop

### Interrupt
