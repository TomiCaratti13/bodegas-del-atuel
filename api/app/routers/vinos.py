"""Endpoints de catalogo y gestion de vinos."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, status
import psycopg

from app.db import get_conn
from app.repositories import vinos_repo
from app.schemas import VinoCreate, VinoUpdate

router = APIRouter(prefix="/vinos", tags=["Vinos"])


@router.get("")
def listar_vinos(
    tipo: str | None = None,
    cepa: int | None = None,
    bodega: str | None = None,
    anada: int | None = None,
    q: str | None = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    conn: psycopg.Connection = Depends(get_conn),
):
    return vinos_repo.list_vinos(
        conn,
        tipo=tipo,
        id_cepa=cepa,
        cuit_bodega=bodega,
        anada=anada,
        q=q,
        page=page,
        page_size=page_size,
    )


@router.get("/{cod}")
def obtener_vino(cod: int, conn: psycopg.Connection = Depends(get_conn)):
    return vinos_repo.get_vino(conn, cod)


@router.post("", status_code=status.HTTP_201_CREATED)
def crear_vino(payload: VinoCreate, conn: psycopg.Connection = Depends(get_conn)):
    return vinos_repo.create_vino(conn, payload)


@router.put("/{cod}")
def actualizar_vino(cod: int, payload: VinoUpdate, conn: psycopg.Connection = Depends(get_conn)):
    return vinos_repo.update_vino(conn, cod, payload)


@router.delete("/{cod}", status_code=status.HTTP_204_NO_CONTENT)
def eliminar_vino(cod: int, conn: psycopg.Connection = Depends(get_conn)):
    vinos_repo.delete_vino(conn, cod)
