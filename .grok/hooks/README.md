# Grok adapter (Phase C)

`cek-hooks.json` is discovered by Grok Build when this folder is trusted
(`/hooks-trust`). `run.sh` sets `CEK_RUNTIME=grok` and dispatches to
`.claude/hooks/*`.

Grok may also load `.claude/settings.json`, which declares no hooks since
v3.0.0 — `cek-hooks.json` is the only Grok hook source. See
`docs/runtime-capability-matrix.md`.

Regenerate:

```bash
python scripts/generate_runtime_hooks.py
```
