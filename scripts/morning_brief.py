"""
morning_brief.py — Daily AI news digest from RSS feeds.

Usage:
    python scripts/morning_brief.py           # print to terminal
    python scripts/morning_brief.py --save    # also write to briefs/YYYY-MM-DD.md
    python scripts/morning_brief.py --quiet   # write file only, no terminal output
"""

import argparse
import json
import re
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

import feedparser

# ── paths ──────────────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parent.parent
CONFIG_FILE = ROOT / "config" / "morning_brief.json"
BRIEFS_DIR = ROOT / "briefs"

# ── helpers ────────────────────────────────────────────────────────────────────

def strip_html(text: str) -> str:
    """Remove HTML tags and collapse whitespace."""
    text = re.sub(r"<[^>]+>", " ", text or "")
    text = re.sub(r"\s+", " ", text).strip()
    return text


def truncate(text: str, limit: int = 180) -> str:
    if len(text) <= limit:
        return text
    return text[:limit].rsplit(" ", 1)[0] + "…"


def parse_published(entry) -> datetime | None:
    """Return a tz-aware datetime from an entry, or None."""
    if hasattr(entry, "published_parsed") and entry.published_parsed:
        try:
            return datetime(*entry.published_parsed[:6], tzinfo=timezone.utc)
        except Exception:
            pass
    if hasattr(entry, "updated_parsed") and entry.updated_parsed:
        try:
            return datetime(*entry.updated_parsed[:6], tzinfo=timezone.utc)
        except Exception:
            pass
    return None


def fetch_feed(feed_cfg: dict, max_items: int, max_age_hours: int) -> list[dict]:
    """Fetch and filter one RSS feed. Returns list of article dicts."""
    cutoff = datetime.now(timezone.utc) - timedelta(hours=max_age_hours)
    try:
        parsed = feedparser.parse(feed_cfg["url"], request_headers={"User-Agent": "morning-brief/1.0"})
    except Exception as e:
        return [{"error": str(e)}]

    if parsed.get("bozo") and not parsed.entries:
        return []

    articles = []
    for entry in parsed.entries:
        pub = parse_published(entry)
        # if we can determine age and it's too old, skip
        if pub and pub < cutoff:
            continue

        summary = strip_html(
            getattr(entry, "summary", "")
            or getattr(entry, "description", "")
            or ""
        )

        articles.append({
            "title": strip_html(getattr(entry, "title", "(no title)")),
            "url": getattr(entry, "link", ""),
            "summary": truncate(summary),
            "published": pub.strftime("%H:%M UTC") if pub else "unknown time",
        })

        if len(articles) >= max_items:
            break

    return articles


def _fetch_all(config: dict, max_age: int) -> tuple[list[dict], int]:
    """Fetch all feeds for a given time window. Returns (sections, total_count)."""
    max_items = config.get("max_items_per_feed", 3)
    sections = []
    total = 0
    for feed_cfg in config.get("feeds", []):
        name = feed_cfg["name"]
        emoji = feed_cfg.get("emoji", "•")
        articles = fetch_feed(feed_cfg, max_items, max_age)
        if not articles:
            continue
        if len(articles) == 1 and "error" in articles[0]:
            sections.append({"name": name, "emoji": emoji, "error": articles[0]["error"]})
            continue
        sections.append({"name": name, "emoji": emoji, "articles": articles})
        total += len(articles)
    return sections, total


def _render(sections: list[dict], now: datetime, max_age: int, fallback: bool) -> tuple[str, str]:
    """Render sections into (terminal_text, markdown_text)."""
    date_str = now.strftime("%A, %d %B %Y")
    time_str = now.strftime("%H:%M UTC")
    days = max_age // 24
    window = f"last {days} days (extended — few recent stories)" if fallback else "last 24h"

    terminal_lines = [
        "",
        "═" * 60,
        f"  AI Morning Brief — {date_str} at {time_str}",
        f"  Window: {window}",
        "═" * 60,
    ]
    md_lines = [
        "# AI Morning Brief",
        f"_{date_str} at {time_str} · {window}_",
        "",
    ]

    total_articles = 0
    for section in sections:
        name, emoji = section["name"], section["emoji"]
        if "error" in section:
            terminal_lines.append(f"\n  {emoji} {name}  [fetch error: {section['error']}]")
            continue
        terminal_lines += ["", f"  {emoji}  {name}", "  " + "─" * 50]
        md_lines += [f"## {emoji} {name}", ""]
        for art in section["articles"]:
            total_articles += 1
            terminal_lines += [f"  • {art['title']}", f"    {art['url']}"]
            if art["summary"]:
                terminal_lines.append(f"    {art['summary']}")
            terminal_lines.append(f"    [{art['published']}]")
            md_lines += [f"### [{art['title']}]({art['url']})", f"_{art['published']}_", ""]
            if art["summary"]:
                md_lines += [art["summary"], ""]
            md_lines.append("")

    terminal_lines += [
        "",
        "═" * 60,
        f"  {total_articles} stories across {len(sections)} sources",
        "═" * 60,
        "",
    ]
    md_lines += ["---", f"_{total_articles} stories · generated by morning_brief.py_"]
    return "\n".join(terminal_lines), "\n".join(md_lines)


def build_brief(config: dict) -> tuple[str, str]:
    """
    Fetch all feeds and return (terminal_text, markdown_text).
    Falls back to a 5-day window if fewer than `fallback_threshold` stories found.
    """
    now = datetime.now(timezone.utc)
    max_age = config.get("max_age_hours", 24)
    fallback_hours = config.get("fallback_max_age_hours", 120)  # 5 days
    threshold = config.get("fallback_threshold", 3)

    sections, total = _fetch_all(config, max_age)
    fallback = False
    if total < threshold:
        sections, total = _fetch_all(config, fallback_hours)
        fallback = True

    return _render(sections, now, fallback_hours if fallback else max_age, fallback)


# ── main ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Daily AI morning brief from RSS feeds.")
    parser.add_argument("--save", action="store_true", help="Write brief to briefs/YYYY-MM-DD.md")
    parser.add_argument("--quiet", action="store_true", help="Suppress terminal output (implies --save)")
    args = parser.parse_args()

    if args.quiet:
        args.save = True

    config = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
    terminal_text, md_text = build_brief(config)

    if not args.quiet:
        try:
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        except AttributeError:
            pass
        print(terminal_text)

    if args.save:
        BRIEFS_DIR.mkdir(exist_ok=True)
        date_slug = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        out_path = BRIEFS_DIR / f"{date_slug}.md"
        out_path.write_text(md_text, encoding="utf-8")
        if not args.quiet:
            print(f"  Saved → {out_path}")


if __name__ == "__main__":
    main()
