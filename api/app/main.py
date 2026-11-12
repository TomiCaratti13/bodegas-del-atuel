"""Aplicacion principal FastAPI - Bodegas del Atuel."""

from __future__ import annotations

from contextlib import asynccontextmanager
import os

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
import psycopg

from app.db import close_pool, get_conn, init_pool
from app.errors import NotFoundError, not_found_handler, pg_error_handler
from app.routers import clientes, operaciones, reportes, vinos


@asynccontextmanager
async def lifespan(_app: FastAPI):
    init_pool()
    try:
        yield
    finally:
        close_pool()


app = FastAPI(
    title="Bodegas del Atuel - API REST",
    description=(
        "API REST con SQL directo (psycopg v3, sin ORM) para el sistema de "
        "gestion y distribucion vitivinicola Bodegas del Atuel."
    ),
    version="1.0.0",
    lifespan=lifespan,
)

origins = [
    o.strip()
    for o in os.getenv("CORS_ORIGINS", "http://localhost:5173,http://localhost:8080").split(",")
    if o.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_exception_handler(psycopg.Error, pg_error_handler)
app.add_exception_handler(NotFoundError, not_found_handler)

app.include_router(vinos.router)
app.include_router(clientes.router)
app.include_router(operaciones.router)
app.include_router(reportes.router)


@app.get("/salud", tags=["Salud"])
def salud(conn: psycopg.Connection = Depends(get_conn)):
    with conn.cursor() as cur:
        cur.execute("SELECT 1 AS ok, current_user AS db_user")
        row = cur.fetchone()
    return {"status": "ok", "db": row}
