# context-engineering-kit v3.0.1

**Release date:** 2026-09-13  
**Tag:** `v3.0.1`  
**Artifact:** `context-engineering-kit-3.0.1.zip` (build with `python scripts/package_plugin.py`)

Patch release. One fix, no breaking changes, no migration — but it matters most
for the thing this kit is for: running across many repositories.

---

## The fix

Kit state could still be written outside a project checkout — into `$HOME`, or
into Claude Code's own `~/.claude/` config directory.

`scripts/resolve_state_dir.sh` has carried a containment guard since 2026-08-30
that refuses exactly those locations. The guard was correct. It was only
*reachable* from `state_write()`. Seven other writers went straight to disk:

| Writer | What it wrote |
|---|---|
| `scripts/session_finalize.sh` | `history.jsonl` — a plain `printf >>`, never consulted the guard |
| `.claude/hooks/native-event-log.sh` | `native-events.jsonl` |
| `.claude/hooks/config-changed.sh` | `config-audit.log` |
| `.claude/hooks/pre-compact.sh` | `compact-audit.log` |
| `.claude/hooks/session-start.sh` | `docs-refresh.log` |
| `scripts/auto_init_project.sh` | `state.json` — computes its own path, had only the git check |
| `scripts/cek_paths.py` | everything — the Python half of the same contract had **no guard at all** |

This was found by cleaning up, not by reading code: `~/.claude/session/`
reappeared holding a `state.json` and a `history.jsonl` whose `session_cwd` was
`$HOME`. The Python path explains the first file, the direct append explains the
second.

**Now:** `cek_state_ok()` and a guarded `state_append()` in
`resolve_state_dir.sh`, with every direct writer routed through one or gated on
the other. `cek_paths.py` gains `state_rejection_reason()` and
`state_writes_allowed()` mirroring the shell rules, and `state_update()` refuses
instead of writing. `auto_init_project.sh` gets the `$HOME` and `~/.claude`
rules it never had.

## And a second bug underneath it

Both guards compared paths as strings. But `git rev-parse --show-toplevel`
always returns a **physical** path, while `$HOME` is whatever the environment
says. Wherever `$HOME` or a parent is a symlink — `/var` → `/private/var` on
macOS is the everyday case — the comparison silently failed to match and the
guard waved the write through.

Both sides are resolved before comparison now.

This is why the new regression test uses a `$HOME` that is *itself* a git repo:
that makes the assertions exercise the `$HOME` branch rather than stopping at
the "not a git repository" check. Against the pre-fix code, five of its seven
assertions fail. A test using an ordinary temp directory would have passed and
proven nothing.

## Coverage

`scripts/eval_hooks_smoke.sh` grows three containment assertions — 67 checks, up
from 64:

- `cek_state_ok` is false for a `$HOME` that is a git repository
- Python `state_update()` refuses and writes nothing
- zero files land under `$HOME/.claude` after firing every direct writer at it

Full suite: `eval_phase_c` 28/28, `eval_usage_lifecycle` 29/29,
`eval_hooks_smoke` 67/67.

---

## Who should upgrade

Anyone running v3.0.0 across more than one repository, and anyone who has ever
started a session outside a project directory. If `~/.claude/session/` exists on
your machine, it is leftover kit state and is safe to delete:

```bash
ls -la ~/.claude/session    # look before deleting
rm -r ~/.claude/session
```

The guard clears that directory itself when it next rejects a write from there,
but only if a hook fires from `$HOME` again — which is why stale copies persist.

## Upgrade

No steps. Reinstall the plugin or pull `main`.

## Install

**Plugin zip (Cowork / Desktop):** download `context-engineering-kit-3.0.1.zip`
from this release.

**CLI / Cursor / Grok / Codex:**
```bash
git clone https://github.com/musicofthings/context-engineering-kit.git
cd context-engineering-kit
bash setup.sh   # Claude CLI
```

## Verify
```bash
bash scripts/eval_hooks_smoke.sh   # 67 checks, containment block at the end
bash scripts/check_sync.sh
/context-health                    # in Claude Code
```

## Docs
- v3.0.0 release notes (breaking changes, known gaps): `docs/RELEASE_NOTES_3.0.0.md`
- Compatibility review, R-026 entry: `docs/sota-compatibility-review-2026-09.md`
- Capability matrix: `docs/runtime-capability-matrix.md`

## Unchanged from v3.0.0

The known gaps listed in the v3.0.0 notes all still stand: Grok remains
unverified against a published hook spec, `AGENTS.md` still reads Claude-first,
`SessionEnd` still fires on `/clear` and `/resume`, and CI still does not
exercise a real Codex install.
