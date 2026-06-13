"""
FBref ingestion script.

Scrapes the "Standard Stats" table for a given league/season from FBref
and loads it into raw.fbref_player_stats.

FBref embeds most of its stats tables inside HTML comments (to keep them
out of the directly-rendered DOM), so we need to pull them out before
handing the HTML to pandas.

Usage:
    python ingestion/fbref_scrape.py --comp-id 9 --comp-name "Premier-League" --season "2024-2025"

Notes / etiquette:
    - FBref asks for no more than ~1 request every few seconds. This
      script processes a single page per run, but if you extend it to
      loop over multiple pages, add a delay between requests.
    - Respect FBref's terms of use: https://www.sports-reference.com/bot-traffic.html
"""

import argparse
import json
import re
import time

import pandas as pd
import requests
from bs4 import BeautifulSoup, Comment

from db import get_connection, start_ingestion_run, finish_ingestion_run

USER_AGENT = (
    "Mozilla/5.0 (compatible; football-analytics-portfolio/0.1; "
    "+https://github.com/your-username/football-analytics)"
)

# Columns we always want as "core" typed columns rather than buried in the
# stats JSON blob. Everything else in the standard stats table is kept in
# `stats` as-is.
CORE_COLUMNS = {"player", "nation", "pos", "squad", "age", "min", "minutes"}


def fetch_page(url: str) -> str:
    resp = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=30)
    resp.raise_for_status()
    return resp.text


def extract_table(html: str, table_id: str) -> pd.DataFrame:
    """
    FBref wraps most stat tables in HTML comments. Search both the live
    DOM and comments for a table matching `table_id`.
    """
    soup = BeautifulSoup(html, "lxml")

    table = soup.find("table", id=re.compile(table_id))
    if table is None:
        for comment in soup.find_all(string=lambda text: isinstance(text, Comment)):
            if table_id in comment:
                comment_soup = BeautifulSoup(comment, "lxml")
                table = comment_soup.find("table", id=re.compile(table_id))
                if table is not None:
                    break

    if table is None:
        raise ValueError(f"Could not find table matching id '{table_id}'")

    df = pd.read_html(str(table))[0]

    # FBref standard stats tables have a two-row header (group + stat name).
    # Flatten it, preferring the more specific (lower) row.
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = [c[-1] for c in df.columns]

    # Drop repeated header rows that appear every ~25 rows in the table body
    if "Rk" in df.columns:
        df = df[df["Rk"] != "Rk"]

    return df


def row_to_record(row: pd.Series, season: str, competition: str, squad_col: str) -> dict:
    lower = {str(k).strip().lower(): v for k, v in row.items()}

    player_name = lower.get("player")
    squad = lower.get(squad_col, lower.get("squad"))
    position = lower.get("pos")
    age = lower.get("age")
    minutes = lower.get("min") or lower.get("minutes")

    # Everything else goes into the stats JSON blob, with simple key cleanup.
    stats = {
        k: (None if pd.isna(v) else v)
        for k, v in lower.items()
        if k not in CORE_COLUMNS and k != "rk"
    }

    return {
        "player_name": player_name,
        "season": season,
        "competition": competition,
        "squad": squad,
        "position": position,
        "age": str(age) if age is not None else None,
        "minutes_played": pd.to_numeric(minutes, errors="coerce"),
        "stats": json.dumps(stats, default=str),
    }


def load_records(conn, records: list[dict]) -> int:
    """
    Upsert records into raw.fbref_player_stats.

    NOTE: FBref player IDs aren't in the standard stats table HTML without
    extra parsing of player profile links. As a first pass we use a
    deterministic placeholder derived from name+squad+season so rows load
    cleanly; replace with real fbref_id extraction (from the <a href> in
    the player cell) as a follow-up improvement.
    """
    with conn.cursor() as cur:
        for rec in records:
            placeholder_id = f"placeholder:{rec['player_name']}:{rec['squad']}:{rec['season']}"
            cur.execute(
                """
                insert into raw.fbref_player_stats
                    (fbref_id, player_name, season, competition, squad, position,
                     age, minutes_played, stats, _source, _loaded_at)
                values (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'fbref', now())
                on conflict (fbref_id, season, competition, squad)
                do update set
                    player_name = excluded.player_name,
                    position = excluded.position,
                    age = excluded.age,
                    minutes_played = excluded.minutes_played,
                    stats = excluded.stats,
                    _loaded_at = now()
                """,
                (
                    placeholder_id,
                    rec["player_name"],
                    rec["season"],
                    rec["competition"],
                    rec["squad"],
                    rec["position"],
                    rec["age"],
                    rec["minutes_played"],
                    rec["stats"],
                ),
            )
    return len(records)


def main():
    parser = argparse.ArgumentParser(description="Scrape FBref standard stats for a league/season")
    parser.add_argument("--comp-id", required=True, help="FBref competition ID, e.g. 9 for Premier League")
    parser.add_argument("--comp-name", required=True, help="Competition name as used in FBref URL, e.g. Premier-League")
    parser.add_argument("--season", required=True, help="Season string, e.g. 2024-2025")
    args = parser.parse_args()

    url = (
        f"https://fbref.com/en/comps/{args.comp_id}/{args.season}/stats/"
        f"{args.season}-{args.comp_name}-Stats"
    )

    print(f"Fetching {url}")
    html = fetch_page(url)

    df = extract_table(html, table_id="stats_standard")
    print(f"Parsed {len(df)} rows")

    squad_col = "squad" if "squad" in [c.lower() for c in df.columns] else "team"

    records = [
        row_to_record(row, season=args.season, competition=args.comp_name, squad_col=squad_col)
        for _, row in df.iterrows()
        if pd.notna(row.get("Player"))
    ]

    with get_connection() as conn:
        run_id = start_ingestion_run(conn, source="fbref")
        try:
            rows_loaded = load_records(conn, records)
            finish_ingestion_run(conn, run_id, status="success", rows_loaded=rows_loaded)
            print(f"Loaded {rows_loaded} rows into raw.fbref_player_stats")
        except Exception as exc:
            finish_ingestion_run(conn, run_id, status="failed", rows_loaded=0, notes=str(exc))
            raise


if __name__ == "__main__":
    main()
