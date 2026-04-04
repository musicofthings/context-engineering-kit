# /morning-brief

Run the daily AI news digest from RSS feeds and display it in the terminal.

## What to do

Run this bash command and display the output to the user:

```bash
python scripts/morning_brief.py --save
```

Then tell the user:
- How many stories were fetched
- That the brief was saved to `briefs/YYYY-MM-DD.md`
- They can edit `config/morning_brief.json` to add/remove RSS feeds
