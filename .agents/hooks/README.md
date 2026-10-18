# Antigravity adapter (Phase 3)

Portable entrypoint for Antigravity CLI / IDE (`agy`). **Do not** put absolute machine paths in
`hooks.json` — regenerate with:

```bash
python scripts/generate_runtime_hooks.py
```

`run.sh` sets `CEK_RUNTIME=antigravity`, translates camelCase payloads and tool arguments,
handles JSON output decisions, and dispatches to `.claude/hooks/*` (single logic core).
See `docs/runtime-capability-matrix.md`.
