"""PostgreSQL ulanish va so'rovlar uchun yordamchi modul.

Connection pool ishlatamiz — DNS lookup bir marta bajariladi va
ulanishlar qayta ishlatiladi. Bu Render kabi serverless muhitda
ham, lokal'da ham tez va ishonchli.
"""
import os
import threading
from contextlib import contextmanager

import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2.pool import ThreadedConnectionPool


_pool: ThreadedConnectionPool | None = None
_pool_lock = threading.Lock()


def _conn_params() -> dict:
    return {
        "host":     os.environ["SUPABASE_DB_HOST"],
        "port":     int(os.environ.get("SUPABASE_DB_PORT", 5432)),
        "user":     os.environ["SUPABASE_DB_USER"],
        "password": os.environ["SUPABASE_DB_PASSWORD"],
        "dbname":   os.environ.get("SUPABASE_DB_NAME", "postgres"),
        "sslmode":  "require",
        "connect_timeout":  30,
        "keepalives":       1,
        "keepalives_idle":  30,
        "keepalives_interval": 10,
        "keepalives_count": 5,
    }


def _get_pool() -> ThreadedConnectionPool:
    global _pool
    if _pool is None:
        with _pool_lock:
            if _pool is None:
                _pool = ThreadedConnectionPool(
                    minconn=1,
                    maxconn=int(os.environ.get("DB_POOL_MAX", 10)),
                    **_conn_params(),
                )
    return _pool


@contextmanager
def cursor(commit: bool = False):
    """Pool'dan ulanish oladi va kursor qaytaradi.

    Ishlatish:
        with cursor() as cur:
            cur.execute("SELECT 1")
            row = cur.fetchone()
    """
    pool = _get_pool()
    conn = pool.getconn()
    cur = None
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        yield cur
        if commit:
            conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        if cur is not None:
            cur.close()
        pool.putconn(conn)


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
