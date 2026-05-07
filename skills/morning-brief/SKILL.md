---
name: morning-brief
description: Display the daily AI news digest from configured RSS feeds. Auto-generated once per day at session start. Use /context-engineering-kit:morning-brief to read today's brief.
user-invocable: true
auto-invoke-when: user asks about today's AI news, what's new in AI, or morning brief
---

# /morning-brief

Run the daily AI news digest from RSS feeds and display it in the terminal.

## What to do

Run this bash command and display the output to the user:

```bash
python3 scripts/morning_brief.py --save
```

Then tell the user:
- How many stories were fetched
- That the brief was saved to `briefs/YYYY-MM-DD.md`
- They can edit `config/morning_brief.json` to add/remove RSS feeds
