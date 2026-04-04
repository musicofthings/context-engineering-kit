---
name: token-status
description: Show context window usage, burn rate, model recommendation, session time elapsed vs budget window, and daily token/cost metrics from ccusage. Invoke with /token-status. Auto-invoked when context exceeds 65%.
user-invocable: true
auto-invoke-when: context usage is high, tokens are running out, before starting a large task, user asks about usage or limits
---

# Token Status v2.2 — Context + Usage Monitor

## 1. Context Window

Estimate and display:
```
Context: [████████░░░░░░░░] ~52%  🟡  CAUTION
Tokens used: ~53,000 / 200,000
```

Thresholds: 0–50% 🟢 | 50–70% 🟡 | 70–85% 🟠 | 85%+ 🔴

## 2. Session Budget (time or cost)

Read `.claude/session/state.json` for `session_start_time`.
Read `config/usage_budget.json` for subscription type and window.

Calculate elapsed time and display:
```
Subscription : pro  (5-hour window)
Elapsed      : 127 min  /  300 min
Budget used  : 42%  🟢
Remaining    : ~173 min (~2h 53m)
```

For API billing, read `session_cost_usd` from state.json and compare to `daily_budget_usd`.

## 3. Daily Usage from ccusage

Run this and display the output:
```bash
python3 scripts/usage_report.py --days 1
```

If ccusage data is not available, note: "Install ccusage (`npm install -g ccusage`) for historical token tracking."

Also run with `--write-summary` to refresh the usage_summary.json cache:
```bash
python3 scripts/usage_report.py --days 1 --write-summary
```

## 4. State Freshness

Read `.claude/session/state.json`:
```
State source : stop-hook-heuristic / agent-precompact-hook / handover-skill
Last updated : [timestamp]
Active task  : [value]
Next action  : [value]
```

Show last 3 entries from `.claude/session/turn-ledger.jsonl` if present.

## 5. Usage Sentinel Status

Read `.claude/session/` for sentinel files:
- `.sentinel_warn` exists: "Warning threshold was crossed this session"
- `.sentinel_save` exists: "Auto-save threshold was crossed — state was saved"
- `.sentinel_critical` exists: "Critical threshold was crossed this session"
- None exist: "No thresholds crossed yet"

## 6. Model Recommendation

| Situation | Action |
|-----------|--------|
| Simple edits | `/model claude-haiku-4-5-20251001` |
| Standard dev | Stay on Sonnet (default) |
| Architecture | `/model claude-opus-4-6` |
| Context > 80% | `/fast` mode |
| Budget > 80% | Switch to Haiku to extend remaining window |

## 7. Quick actions

- `/compact-smart`  — smart compaction
- `/handover`       — update state.json with precise data
- `/session-sync save` — commit state to git
- `/compact` — standard compaction
