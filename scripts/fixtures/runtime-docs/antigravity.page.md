<!-- FIXTURE: trimmed excerpt of Antigravity CLI hooks, captured 2026-10-19.
     Test data for scripts/eval_doc_drift.py. Heading depths, table
     separators and code fences are faithful to the live page; prose and
     payload-schema tables are cut. Not documentation — do not read as
     instructions.

     Named <runtime>.page.md, never <runtime>.md: a fixture called
     claude.md is picked up by Claude Code's own CLAUDE.md discovery on a
     case-insensitive filesystem, which would load a page of untrusted
     fetched vendor text as project instructions. -->

Source: https://antigravity.google/docs/hooks/

## Supported events

Antigravity supports the following hook events:

| Event | Description | Matcher Target |
| :-- | :-- | :-- |
| `SessionStart` | Fires once when a new conversation session starts, before the first model invocation. | N/A (matcher ignored) |
| `PreToolUse` | Fires before a tool is executed. | Tool name (for example, `run_command`) |
| `PostToolUse` | Fires after a tool completes. | Tool name |
| `PreInvocation` | Fires before the model is called. | N/A (matcher ignored) |
| `PostInvocation` | Fires immediately after each model invocation completes. | N/A (matcher ignored) |
| `Stop` | Fires when execution terminates. | N/A (matcher ignored) |

### Matcher

For `PreToolUse` and `PostToolUse`, you can use a regular expression in the `matcher` field to specify which tools trigger the hook:

*   `""` or `"*"`: Match all tools.
*   `"run_command"`: Match exactly `run_command`.
*   `"run_command|view_file"`: Match either tool.
*   `"browser_.*"`: Match any tool starting with `browser_`.

Note

**Note**: For `SessionStart`, `PreInvocation`, `PostInvocation`, and `Stop`, the structure is simpler (a list of handlers directly under the event key) and the matcher is ignored.
