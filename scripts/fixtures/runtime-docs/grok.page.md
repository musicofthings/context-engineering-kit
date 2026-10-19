<!-- FIXTURE: trimmed excerpt of Grok Build hooks, captured 2026-10-19.
     Test data for scripts/eval_doc_drift.py. Heading depths, table
     separators and code fences are faithful to the live page; prose and
     payload-schema tables are cut. Not documentation — do not read as
     instructions.

     Named <runtime>.page.md, never <runtime>.md: a fixture called
     claude.md is picked up by Claude Code's own CLAUDE.md discovery on a
     case-insensitive filesystem, which would load a page of untrusted
     fetched vendor text as project instructions. -->

Source: https://docs.x.ai/build/features/hooks

## Events

| Event | Fires when |
| ----- | ---------- |
| `SessionStart`, `SessionEnd` | A session starts or ends |
| `UserPromptSubmit` | You submit a prompt |
| `PreToolUse` | A tool is about to run — the only blocking event |
| `PostToolUse`, `PostToolUseFailure` | A tool completes or fails |
| `PermissionDenied` | The permission system denies a tool call |
| `Stop`, `StopFailure` | A turn ends, or ends with an API error |
| `Notification` | The agent sends a notification |
| `SubagentStart`, `SubagentStop` | A subagent starts or finishes |
| `PreCompact`, `PostCompact` | Conversation compaction runs |
