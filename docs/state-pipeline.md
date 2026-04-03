# State Pipeline — How Task State Stays Current

_v2.1 — This document explains the three-layer system that keeps `state.json` fresh
at all times, including before compaction._

---

## The problem (v2.0 gap)

In v2.0, the `PreCompact` hook called `generate_session_handover.py` which read
`state.json` to know the active task, phase, and next action. But `state.json`
only had fresh data if `/handover` had been run manually during the session.
If you never ran `/handover`, the hook saved stale or empty task descriptions.

---

## The three-layer solution (v2.1)

```
Every turn (Stop event)
    └─► extract-state-on-stop.sh       [Layer 1 — async, heuristic, free]
           Pattern-matches assistant response
           Updates: next_action, active_task hint, phase hint
           Source tag: "stop-hook-heuristic"
           Runs in background, never blocks responses

When context hits ~85% (PreCompact event)
    └─► Agent hook: Haiku reads conversation  [Layer 2 — agent, ~50ms, ~500 tokens]
           Full conversation → structured extraction
           Updates: active_task, phase, next_action, blockers,
                    completed_items, key_files
           Source tag: "agent-precompact-hook"
           Runs BEFORE pre-compact.sh so shell script has fresh data

    └─► pre-compact.sh                 [Shell script, reads fresh state.json]
           Reads state.json (now populated by Layer 2)
           Generates session_handover.md
           Updates CLAUDE.md active section
           Injects context summary

Manual (any time)
    └─► /handover skill                [Layer 3 — manual, most precise]
           You describe the task yourself
           Overwrites with authoritative human-verified data
           Source tag: "handover-skill"
           Best quality — use before major compactions or device switches
```

---

## Priority and trust hierarchy

When `state.json` has multiple updates, the priority is:

```
handover-skill > agent-precompact-hook > stop-hook-heuristic
```

The `extract-state-on-stop.sh` script only updates `active_task` if it is currently
`"unknown"` or `"initial setup"` — it never overwrites a good value from a higher layer.

The agent hook at PreCompact always overwrites (because it has full conversation context).

The `/handover` skill always overwrites (because it has human intent).

---

## What each layer costs

| Layer | Trigger | Cost | Quality | Blocks response? |
|-------|---------|------|---------|-----------------|
| Stop heuristic | Every turn | Zero (bash regex) | Medium — catches ~70% | No (async) |
| PreCompact agent | At compaction | ~500 Haiku tokens | High — reads full conversation | Yes (before shell hook) |
| /handover skill | Manual | ~200 Sonnet tokens | Highest — human verified | No |

---

## Reading state.json

```bash
cat .claude/session/state.json
```

Key fields:
- `active_task` — what is being built right now
- `next_action` — the single most important next step
- `phase` — current development phase
- `state_source` — which layer last wrote this data
- `state_extracted_at` — when the agent last extracted (PreCompact layer)
- `last_activity` — when Stop hook last ran (continuous layer)

---

## Checking turn-ledger

The turn ledger records every turn where the Stop heuristic extracted something:

```bash
tail -10 .claude/session/turn-ledger.jsonl | jq '.'
```

Example output:
```json
{"ts":"2026-04-03T09:15:00Z","turn":12,"next_action":"write the pre-compact hook script","task_hint":"writing hooks for context-engineering-kit"}
{"ts":"2026-04-03T09:22:00Z","turn":14,"next_action":"test the agent hook configuration in settings.json","task_hint":""}
```

This lets you see what the heuristic was tracking, and diagnose if it missed something
important (in which case run `/handover` to fix it).

---

## Best practice workflow

1. **At session start**: `claude /context-health` — check state freshness
2. **During heavy sessions**: `/handover` every 2–3 hours or after each major phase
3. **Trust the automation**: Layers 1 + 2 give you a solid floor; Layer 3 raises the ceiling
4. **Before switching devices**: `claude /session-sync save` — commits the latest state
