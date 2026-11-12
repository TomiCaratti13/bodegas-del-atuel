"""Endpoints de operaciones transaccionales: comprobantes, transferencias e ingresos."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, status
import psycopg

from app.db import get_conn
from app.repositories import operaciones_repo
from app.schemas import (
    ComprobanteCreate,
    IngresoCreate,
    RenglonDocumentoCreate,
    TransferenciaCreate,
)

router = APIRouter(tags=["Operaciones"])


# --- Comprobantes (Ventas) ---
@router.post("/comprobantes", status_code=status.HTTP_201_CREATED)
def crear_comprobante(payload: ComprobanteCreate, conn: psycopg.Connection = Depends(get_conn)):
    return operaciones_repo.create_comprobante(conn, payload)


@router.get("/comprobantes/{nro}")
def obtener_comprobante(nro: int, conn: psycopg.Connection = Depends(get_conn)):
    return operaciones_repo.get_comprobante(conn, nro)


# --- Transferencias ---
@router.get("/transferencias")
def listar_transferencias(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    conn: psycopg.Connection = Depends(get_conn),
):
    return operaciones_repo.list_transferencias(conn, page=page, page_size=page_size)


@router.get("/transferencias/{nro}")
def obtener_transferencia(nro: int, conn: psycopg.Connection = Depends(get_conn)):
    return operaciones_repo.get_transferencia(conn, nro)


@router.post("/transferencias", status_code=status.HTTP_201_CREATED)
def crear_transferencia(payload: TransferenciaCreate, conn: psycopg.Connection = Depends(get_conn)):
    return operaciones_repo.create_transferencia(conn, payload)


@router.post("/transferencias/{nro}/renglones", status_code=status.HTTP_201_CREATED)
def agregar_renglon_transferencia(
    nro: int, payload: RenglonDocumentoCreate, conn: psycopg.Connection = Depends(get_conn)
):
    return operaciones_repo.add_renglon_transferencia(conn, nro, payload)


@router.post("/transferencias/{nro}/terminar")
def terminar_transferencia(nro: int, conn: psycopg.Connection = Depends(get_conn)):
    return operaciones_repo.terminar_transferencia(conn, nro)


@router.post("/transferencias/{nro}/procesar")
def procesar_transferencia(nro: int, conn: psycopg.Connection = Depends(get_conn)):
    return operaciones_repo.procesar_transferencia(conn, nro)


# --- Ingresos ---
@router.get("/ingresos/{cod}")
def obtener_ingreso(cod: int, conn: psycopg.Connection = Depends(get_conn)):
    return operaciones_repo.get_ingreso(conn, cod)


@router.post("/ingresos", status_code=status.HTTP_201_CREATED)
def crear_ingreso(payload: IngresoCreate, conn: psycopg.Connection = Depends(get_conn)):
    return operaciones_repo.create_ingreso(conn, payload)


@router.post("/ingresos/{cod}/renglones", status_code=status.HTTP_201_CREATED)
def agregar_renglon_ingreso(
    cod: int, payload: RenglonDocumentoCreate, conn: psycopg.Connection = Depends(get_conn)
):
    return operaciones_repo.add_renglon_ingreso(conn, cod, payload)


@router.post("/ingresos/{cod}/terminar")
def terminar_ingreso(cod: int, conn: psycopg.Connection = Depends(get_conn)):
    return operaciones_repo.terminar_ingreso(conn, cod)


@router.post("/ingresos/{cod}/procesar")
def procesar_ingreso(cod: int, conn: psycopg.Connection = Depends(get_conn)):
    return operaciones_repo.procesar_ingreso(conn, cod)
