"""Database access helpers (PostgreSQL via psycopg 3).

Every function opens a short-lived autocommit connection. Business rules are
enforced by the database (EXCLUDE constraints, triggers), so the web layer only
translates their errors into readable messages.
"""
import os

import psycopg
from psycopg.rows import dict_row

DSN = os.environ.get("DATABASE_URL", "postgresql://postgres@localhost:5432/evt")


def _connect():
    return psycopg.connect(DSN, row_factory=dict_row, autocommit=True)


def rows(sql, params=()):
    with _connect() as conn:
        return conn.execute(sql, params).fetchall()


def row(sql, params=()):
    with _connect() as conn:
        return conn.execute(sql, params).fetchone()


def run(sql, params=()):
    """Execute a write statement and return the number of affected rows."""
    with _connect() as conn:
        return conn.execute(sql, params).rowcount
