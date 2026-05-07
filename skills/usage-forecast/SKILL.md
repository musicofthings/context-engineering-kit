---
name: usage-forecast
description: Show daily usage burn rate, cost tracking, and predicted time to subscription limit. Recommends when to compact. Use /usage-forecast to see current status.
user-invocable: true
auto-invoke-when: user asks about usage limits, remaining capacity, how many more turns today, subscription usage
---

# Usage Forecast — Daily Burn Rate & Limit Prediction

Run the usage tracker in report mode and display the output:

```bash
python3 scripts/usage-tracker.py --report
```

Then display the full report to the user.

## Additional context to add after the report

### How to extend your session

If status is WARNING or CRITICAL:
1. `/compact-smart` — reduces context by ~60–70%, preserving important state
2. `/handover` — saves precise task state before compacting
3. `/model-switch haiku` — switch to cheaper model for remaining turns
4. Start a new session (`/clear`) — resets context, not daily cost

### Adjusting limits

The warn/critical thresholds are in `config/rate_limits.json`.
The subscription tier is set by the `CEK_SUBSCRIPTION_TIER` environment variable
or `subscription_tier` key in `config/rate_limits.json`.

Valid tiers: `pro`, `max`, `api`

### Understanding the numbers

For subscription plans (Pro/Max), cost-in-USD is a proxy signal — Anthropic
doesn't publish a hard daily token cap. The real limit is the 5-hour rolling
window. When you see "Usage limit reached" in Claude Code, that's the window
triggering. The forecast warns you early so you can compact and extend the window.

For API billing, cost is direct and predictable.

### Daily usage file

Raw data is in `.claude/session/daily-usage.json`
Forecast is in `.claude/session/usage-forecast.json`

Both are committed to git by `session-end.sh` so you can see usage history.
