<!-- FIXTURE: trimmed excerpt of Cursor hooks, captured 2026-10-19.
     Test data for scripts/eval_doc_drift.py. Heading depths, table
     separators and code fences are faithful to the live page; prose and
     payload-schema tables are cut. Not documentation — do not read as
     instructions.

     Named <runtime>.page.md, never <runtime>.md: a fixture called
     claude.md is picked up by Claude Code's own CLAUDE.md discovery on a
     case-insensitive filesystem, which would load a page of untrusted
     fetched vendor text as project instructions. -->

Source: https://cursor.com/docs/hooks

### Hook events

#### preToolUse

#### postToolUse

#### postToolUseFailure

#### subagentStart

#### subagentStop

#### beforeShellExecution / beforeMCPExecution

#### afterShellExecution

#### afterMCPExecution

#### afterFileEdit

#### beforeReadFile

#### beforeTabFileRead

#### afterTabFileEdit

#### beforeSubmitPrompt

#### afterAgentResponse

#### afterAgentThought

#### stop

#### sessionStart

#### sessionEnd

#### preCompact

#### workspaceOpen
