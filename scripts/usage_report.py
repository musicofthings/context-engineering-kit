#!/usr/bin/env python3
"""
scripts/usage_report.py
Reads ccusage JSONL files from ~/.claude/projects/ to report daily token and cost metrics.
Called by /token-status skill and context-health skill.
Also writes a summary to .claude/session/usage_summary.json for hook consumption.
"""

import json
import os
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path
from collections import defaultdict


CLAUDE_DIR = Path.home() / ".claude" / "projects"
OUTPUT_FILE = Path(os.environ.get("CLAUDE_PROJECT_DIR", ".")) / ".claude" / "session" / "usage_summary.json"


def load_ccusage_entries(days_back: int = 1) -> list[dict]:
    """Read JSONL entries from ~/.claude/projects/ for the last N days."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=days_back)
    entries = []

    if not CLAUDE_DIR.exists():
        return entries

    for jsonl_file in CLAUDE_DIR.rglob("*.jsonl"):
        try:
            with open(jsonl_file) as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = json.loads(line)
                        ts_str = entry.get("timestamp") or entry.get("ts") or entry.get("created_at", "")
                        if ts_str:
                            ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                            if ts >= cutoff:
                                entries.append(entry)
                    except (json.JSONDecodeError, ValueError):
                        continue
        except (PermissionError, OSError):
            continue

    return entries


def aggregate_metrics(entries: list[dict]) -> dict:
    """Aggregate token and cost metrics from entries."""
    totals = {
        "input_tokens": 0,
        "output_tokens": 0,
        "cache_read_tokens": 0,
        "cache_write_tokens": 0,
        "total_cost_usd": 0.0,
        "session_count": 0,
        "model_breakdown": defaultdict(lambda: {"input": 0, "output": 0, "cost": 0.0}),
    }

    session_ids = set()

    for entry in entries:
        usage = entry.get("usage") or entry.get("costUSD") and entry or {}

        # Token fields vary by ccusage version
        totals["input_tokens"]       += usage.get("input_tokens", 0) or entry.get("inputTokens", 0)
        totals["output_tokens"]      += usage.get("output_tokens", 0) or entry.get("outputTokens", 0)
        totals["cache_read_tokens"]  += usage.get("cache_read_input_tokens", 0)
        totals["cache_write_tokens"] += usage.get("cache_creation_input_tokens", 0)

        cost = entry.get("costUSD", 0) or entry.get("cost_usd", 0) or 0
        totals["total_cost_usd"] += float(cost)

        model = entry.get("model", "unknown")
        totals["model_breakdown"][model]["input"]  += usage.get("input_tokens", 0)
        totals["model_breakdown"][model]["output"] += usage.get("output_tokens", 0)
        totals["model_breakdown"][model]["cost"]   += float(cost)

        sid = entry.get("session_id") or entry.get("sessionId", "")
        if sid:
            session_ids.add(sid)

    totals["session_count"] = len(session_ids)
    totals["model_breakdown"] = dict(totals["model_breakdown"])
    return totals


def format_tokens(n: int) -> str:
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n/1_000:.0f}K"
    return str(n)


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Usage report from ccusage data")
    parser.add_argument("--days", type=int, default=1, help="Days to look back (default: 1 = today)")
    parser.add_argument("--json", action="store_true", help="Output JSON instead of text")
    parser.add_argument("--write-summary", action="store_true", help="Write summary to usage_summary.json")
    args = parser.parse_args()

    entries = load_ccusage_entries(days_back=args.days)
    metrics = aggregate_metrics(entries)

    total_tokens = metrics["input_tokens"] + metrics["output_tokens"]
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    summary = {
        "generated_at": timestamp,
        "period_days": args.days,
        "total_tokens": total_tokens,
        "input_tokens": metrics["input_tokens"],
        "output_tokens": metrics["output_tokens"],
        "cache_read_tokens": metrics["cache_read_tokens"],
        "total_cost_usd": round(metrics["total_cost_usd"], 4),
        "session_count": metrics["session_count"],
        "model_breakdown": metrics["model_breakdown"],
        "ccusage_entries_found": len(entries),
        "data_source": str(CLAUDE_DIR),
    }

    if args.json or args.write_summary:
        if args.write_summary:
            OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
            OUTPUT_FILE.write_text(json.dumps(summary, indent=2))
            print(f"[usage_report] Summary written to {OUTPUT_FILE}", file=sys.stderr)

        if args.json:
            print(json.dumps(summary, indent=2))
        return

    # ── Human-readable report ─────────────────────────────────────────────────
    print(f"\n{'═'*52}")
    print(f" Usage Report — Last {args.days} day(s)")
    print(f"{'═'*52}")
    print(f" Total tokens  : {format_tokens(total_tokens)}")
    print(f"   Input        : {format_tokens(metrics['input_tokens'])}")
    print(f"   Output       : {format_tokens(metrics['output_tokens'])}")
    print(f"   Cache read   : {format_tokens(metrics['cache_read_tokens'])}")
    print(f" Total cost     : ${metrics['total_cost_usd']:.4f} USD")
    print(f" Sessions       : {metrics['session_count']}")

    if metrics["model_breakdown"]:
        print(f"\n Model breakdown:")
        for model, stats in sorted(metrics["model_breakdown"].items()):
            print(f"   {model[:35]:<35} {format_tokens(stats['input']+stats['output']):>6} tokens  ${stats['cost']:.4f}")

    if not entries:
        print(f"\n  ⚠️  No ccusage data found in {CLAUDE_DIR}")
        print(f"  Install ccusage: npm install -g ccusage")
        print(f"  Or check path: {CLAUDE_DIR}")

    print(f"\n Data source: {CLAUDE_DIR}")
    print(f" Generated:   {timestamp}")
    print(f"{'═'*52}\n")


if __name__ == "__main__":
    main()
