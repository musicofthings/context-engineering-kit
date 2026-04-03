# Token Hygiene
_Loaded automatically by Claude Code from .claude/rules/_

## Context window management

- Use `@filepath` references instead of pasting file contents inline
- Never paste entire VCF, FASTA, BAM, or log files — reference by path
- Use `/compact-smart` when context exceeds 70% (not the default `/compact`)
- Run `/handover` before any compaction to preserve task state
- Use `/clear` only to start a genuinely new task — it loses conversation history
- Prefer `/compact` over `/clear` when continuing the same task

## Model selection for efficiency

- Use Haiku for: formatting, linting, simple renames, boilerplate generation
- Use Sonnet (default) for: standard development, analysis, pipelines
- Use Opus only for: architecture decisions, complex reasoning, edge-case ACMG classification
- Activate `/fast` for Opus when context > 70% and Opus reasoning is needed

## Context rot prevention

- Start new Claude Code sessions for genuinely new, unrelated tasks
- Keep CLAUDE.md under 500 lines — move detail to `.claude/rules/` files
- Archive completed project phases to `docs/archive/` rather than keeping in CLAUDE.md
- After each session: run `/handover` to externalise state before it's lost

## Bioinformatics-specific

- Pipeline stdout: extract only error lines, not full stdout (saves 80–95% tokens)
- VCF analysis: reference file, describe variant by HGVS notation in chat
- gnomAD/ClinVar queries: ask for specific fields, not full JSON responses
- For large cohorts: process in batches, save intermediate results to files
