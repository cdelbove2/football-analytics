"""
Shared database connection helper for ingestion scripts.

Reads connection info from environment variables (see .env.example).
Keeping this tiny and dependency-light on purpose - this is meant to be
the kind of thing you could swap for SQLAlchemy later without much pain.
"""

import os
import contextlib

import psycopg2
from dotenv import load_dotenv

load_dotenv()

DB_HOST = os.getenv("FOOTBALL_DB_HOST", "localhost")
DB_PORT = os.getenv("FOOTBALL_DB_PORT", "5432")
DB_NAME = os.getenv("FOOTBALL_DB_NAME", "football")
DB_USER = os.getenv("FOOTBALL_DB_USER", "football")
DB_PASSWORD = os.getenv("FOOTBALL_DB_PASSWORD", "football")


@contextlib.contextmanager
def get_connection():
    """Yield a psycopg2 connection, committing on success and rolling back on error."""
    conn = psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
    )
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def start_ingestion_run(conn, source: str) -> str:
    """Insert a row into raw.ingestion_log and return the run_id."""
    with conn.cursor() as cur:
        cur.execute(
            "insert into raw.ingestion_log (source) values (%s) returning run_id",
            (source,),
        )
        run_id = cur.fetchone()[0]
    return run_id


def finish_ingestion_run(conn, run_id: str, status: str, rows_loaded: int, notes: str = None):
    with conn.cursor() as cur:
        cur.execute(
            """
            update raw.ingestion_log
            set finished_at = now(), status = %s, rows_loaded = %s, notes = %s
            where run_id = %s
            """,
            (status, rows_loaded, notes, run_id),
        )
