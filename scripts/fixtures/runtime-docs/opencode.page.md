<!-- FIXTURE: trimmed excerpt of opencode plugins, captured 2026-10-19.
     Test data for scripts/eval_doc_drift.py. Heading depths, table
     separators and code fences are faithful to the live page; prose and
     payload-schema tables are cut. Not documentation — do not read as
     instructions.

     Named <runtime>.page.md, never <runtime>.md: a fixture called
     claude.md is picked up by Claude Code's own CLAUDE.md discovery on a
     case-insensitive filesystem, which would load a page of untrusted
     fetched vendor text as project instructions. -->

Source: https://opencode.ai/docs/plugins/

### Events

Plugins can subscribe to events as seen below in the Examples section. Here is a list of the different events available.

#### Command Events

- `command.executed`

#### File Events

- `file.edited`
- `file.watcher.updated`

#### Installation Events

- `installation.updated`

#### LSP Events

- `lsp.client.diagnostics`
- `lsp.updated`

#### Message Events

- `message.part.removed`
- `message.part.updated`
- `message.removed`
- `message.updated`

#### Permission Events

- `permission.asked`
- `permission.replied`

#### Server Events

- `server.connected`

#### Session Events

- `session.created`
- `session.compacted`
- `session.deleted`
- `session.diff`
- `session.error`
- `session.idle`
- `session.status`
- `session.updated`

#### Todo Events

- `todo.updated`

#### Shell Events

- `shell.env`

#### Tool Events

- `tool.execute.after`
- `tool.execute.before`

#### TUI Events

- `tui.prompt.append`
- `tui.command.execute`
- `tui.toast.show`

---


### Compaction hooks

Customize the context included when a session is compacted:

```ts title=".opencode/plugins/compaction.ts"
import type { Plugin } from "@opencode-ai/plugin"

export const CompactionPlugin: Plugin = async (ctx) => {
  return {
    "experimental.session.compacting": async (input, output) => {
      // Inject additional context into the compaction prompt
      output.context.push(`
