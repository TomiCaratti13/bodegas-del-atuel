"""Conexion a PostgreSQL mediante pool nativo de psycopg (sin ORM)."""

from __future__ import annotations

import os
from collections.abc import Generator

import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool


def build_dsn() -> str:
    if url := os.getenv("DATABASE_URL"):
        return url
    host = os.getenv("POSTGRES_HOST", "localhost")
    port = os.getenv("POSTGRES_PORT", "5432")
    db = os.getenv("POSTGRES_DB", "bodegas_atuel")
    # La API se conecta por defecto con el rol de privilegios minimos app_rw
    user = os.getenv("API_DB_USER", "app_rw")
    pwd = os.getenv("API_DB_PASSWORD", "dev_app_rw_change_me")
    sslmode = os.getenv("POSTGRES_SSLMODE", "prefer")
    return f"postgresql://{user}:{pwd}@{host}:{port}/{db}?sslmode={sslmode}"


pool: ConnectionPool | None = None


def init_pool() -> ConnectionPool:
    global pool
    if pool is None:
        pool = ConnectionPool(
            conninfo=build_dsn(),
            min_size=2,
            max_size=10,
            kwargs={"row_factory": dict_row},
            open=True,
        )
    return pool


def close_pool() -> None:
    global pool
    if pool is not None:
        pool.close()
        pool = None


def get_conn() -> Generator[psycopg.Connection, None, None]:
    p = init_pool()
    with p.connection() as conn:
        yield conn
