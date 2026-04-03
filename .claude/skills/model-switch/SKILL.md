---
name: model-switch
description: Switch between Claude models (Haiku/Sonnet/Opus) based on task complexity. Use /model-switch [haiku|sonnet|opus|auto]. Auto mode analyses the current task and recommends the right model.
user-invocable: true
auto-invoke-when: user asks about model switching, token optimization, or cost reduction
---

# Model Switch — Intelligent Model Selection

Usage: `/model-switch [haiku|sonnet|opus|auto]`

## If called with `auto` or no argument:

Analyse the current task context and recommend a model:

**Switch to Haiku** (`/model claude-haiku-4-5-20251001`) when:
- Formatting, linting, or style fixes
- Simple variable renames or typo corrections
- Running/checking test output
- Generating boilerplate from a clear template
- Translating between languages
- Simple regex or data transforms

**Stay on Sonnet** (default, `claude-sonnet-4-6`) when:
- Writing new functions or modules
- Debugging logic errors
- Reading and understanding existing code
- Bioinformatics pipeline development
- Writing documentation
- Standard analysis tasks

**Switch to Opus** (`/model claude-opus-4-6`) when:
- Designing system architecture
- Complex multi-step reasoning
- Reviewing security or compliance decisions
- Novel algorithm design
- ACMG variant classification edge cases
- Legal or clinical document review

**Use `/fast` mode** when:
- Context is > 80% and you need to finish the current task
- Opus is needed but you want 2.5× speed

## If called with a specific model:

Execute the model switch:
```
/model [model-string]
```

Then confirm:
- "✅ Switched to [Model]. [Token cost implication]."
- "Current context: [X]% — [advice about compaction if relevant]"

## Token cost reference (approximate)

| Model | Input cost | Output cost | Best for |
|-------|-----------|-------------|---------|
| Haiku 4.5 | Lowest | Lowest | Simple edits |
| Sonnet 4.6 | Medium | Medium | Most work |
| Opus 4.6 | Highest | Highest | Complex decisions |
| Opus 4.6 + /fast | Highest | Highest | Speed-critical Opus work |

## Auto-switch thresholds (configured in config/model_thresholds.json)

The `stop.sh` hook reads these thresholds and may recommend a switch automatically.
