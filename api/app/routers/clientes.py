"""Endpoints CRUD de clientes (socio, distribuidor, exportador)."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, status
import psycopg

from app.db import get_conn
from app.repositories import clientes_repo
from app.schemas import ClienteCreate, ClienteUpdate

router = APIRouter(prefix="/clientes", tags=["Clientes"])


@router.get("")
def listar_clientes(
    tipo_cliente: str | None = None,
    q: str | None = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    conn: psycopg.Connection = Depends(get_conn),
):
    return clientes_repo.list_clientes(
        conn, tipo_cliente=tipo_cliente, q=q, page=page, page_size=page_size
    )


@router.get("/{id_cliente}")
def obtener_cliente(id_cliente: int, conn: psycopg.Connection = Depends(get_conn)):
    return clientes_repo.get_cliente(conn, id_cliente)


@router.post("", status_code=status.HTTP_201_CREATED)
def crear_cliente(payload: ClienteCreate, conn: psycopg.Connection = Depends(get_conn)):
    return clientes_repo.create_cliente(conn, payload)


@router.put("/{id_cliente}")
def actualizar_cliente(
    id_cliente: int, payload: ClienteUpdate, conn: psycopg.Connection = Depends(get_conn)
):
    return clientes_repo.update_cliente(conn, id_cliente, payload)


@router.delete("/{id_cliente}", status_code=status.HTTP_204_NO_CONTENT)
def eliminar_cliente(id_cliente: int, conn: psycopg.Connection = Depends(get_conn)):
    clientes_repo.delete_cliente(conn, id_cliente)
