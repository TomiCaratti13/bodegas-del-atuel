"""Endpoints de reportes (Seccion 8) y catalogos auxiliares."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
import psycopg

from app.db import get_conn
from app.repositories import reportes_repo

router = APIRouter(tags=["Reportes"])


@router.get("/reportes/top-vinos")
def top_vinos(conn: psycopg.Connection = Depends(get_conn)):
    return reportes_repo.top_vinos(conn)


@router.get("/reportes/ventas-por-sala")
def ventas_por_sala(conn: psycopg.Connection = Depends(get_conn)):
    return reportes_repo.ventas_por_sala(conn)


@router.get("/reportes/vinos-sin-stock")
def vinos_sin_stock(
    id_sala: int = Query(1, ge=1),
    conn: psycopg.Connection = Depends(get_conn),
):
    return reportes_repo.vinos_sin_stock_sala(conn, id_sala)


@router.get("/reportes/transportista-activo")
def transportista_activo(conn: psycopg.Connection = Depends(get_conn)):
    return reportes_repo.transportista_activo(conn)


@router.get("/reportes/trazabilidad/{cod}")
def trazabilidad_vino(cod: int, conn: psycopg.Connection = Depends(get_conn)):
    return reportes_repo.trazabilidad_vino(conn, cod)


@router.get("/catalogos")
def catalogos(conn: psycopg.Connection = Depends(get_conn)):
    return reportes_repo.list_catalogos(conn)
