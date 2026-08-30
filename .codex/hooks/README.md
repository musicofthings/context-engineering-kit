# Codex adapter (Phase C)

Portable entrypoint for Codex. **Do not** put absolute machine paths in
`hooks.json` — regenerate with:

```bash
python scripts/generate_runtime_hooks.py
```

`run.sh` sets `CEK_RUNTIME=codex` and dispatches to `.claude/hooks/*`
(single logic core). See `docs/runtime-capability-matrix.md`.
