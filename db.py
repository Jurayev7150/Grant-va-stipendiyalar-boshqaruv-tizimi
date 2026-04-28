"""PostgreSQL ulanish va so'rovlar uchun yordamchi modul."""
import os
from contextlib import contextmanager

import psycopg2
from psycopg2.extras import RealDictCursor


def _conn_params():
    return {
        "host":     os.environ["SUPABASE_DB_HOST"],
        "port":     int(os.environ.get("SUPABASE_DB_PORT", 5432)),
        "user":     os.environ["SUPABASE_DB_USER"],
        "password": os.environ["SUPABASE_DB_PASSWORD"],
        "dbname":   os.environ.get("SUPABASE_DB_NAME", "postgres"),
        "sslmode":  "require",
        "connect_timeout": 10,
    }


def get_conn():
    return psycopg2.connect(**_conn_params())


@contextmanager
def cursor(commit: bool = False):
    """Avtomatik yopiladigan ulanish va kursor.

    Ishlatish:
        with cursor() as cur:
            cur.execute("SELECT 1")
            row = cur.fetchone()
    """
    conn = get_conn()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        yield cur
        if commit:
            conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()


def fetch_all(sql: str, params: tuple = ()) -> list[dict]:
    with cursor() as cur:
        cur.execute(sql, params)
        return [dict(row) for row in cur.fetchall()]


def fetch_one(sql: str, params: tuple = ()) -> dict | None:
    with cursor() as cur:
        cur.execute(sql, params)
        row = cur.fetchone()
        return dict(row) if row else None


def execute(sql: str, params: tuple = ()) -> None:
    with cursor(commit=True) as cur:
        cur.execute(sql, params)


def execute_returning(sql: str, params: tuple = ()) -> dict | None:
    """INSERT ... RETURNING ... uchun."""
    with cursor(commit=True) as cur:
        cur.execute(sql, params)
        row = cur.fetchone()
        return dict(row) if row else None
