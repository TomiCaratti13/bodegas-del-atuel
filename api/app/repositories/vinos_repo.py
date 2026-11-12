"""Capa de acceso a datos para vinos (SQL directo parametrizado)."""

from __future__ import annotations

from typing import Any
import psycopg

from app.errors import NotFoundError
from app.schemas import VinoCreate, VinoUpdate


def list_vinos(
    conn: psycopg.Connection,
    *,
    tipo: str | None = None,
    id_cepa: int | None = None,
    cuit_bodega: str | None = None,
    anada: int | None = None,
    q: str | None = None,
    page: int = 1,
    page_size: int = 20,
) -> dict[str, Any]:
    conditions = ["1=1"]
    params: list[Any] = []

    if tipo:
        conditions.append("v.tipo = %s")
        params.append(tipo)
    if cuit_bodega:
        conditions.append("v.cuit_bodega = %s")
        params.append(cuit_bodega)
    if anada is not None:
        conditions.append("v.anada = %s")
        params.append(anada)
    if q:
        conditions.append("lower(v.nombre) LIKE %s")
        params.append(f"%{q.lower()}%")
    if id_cepa is not None:
        conditions.append(
            "EXISTS (SELECT 1 FROM composicion_vino cv WHERE cv.cod_vino = v.cod_vino AND cv.id_cepa = %s)"
        )
        params.append(id_cepa)

    where_sql = " AND ".join(conditions)
    offset = (page - 1) * page_size

    with conn.cursor() as cur:
        cur.execute(f"SELECT COUNT(*) AS total FROM vino v WHERE {where_sql}", params)
        total = cur.fetchone()["total"]

        cur.execute(
            f"""
            SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml,
                   v.graduacion, v.precio, v.cuit_bodega, b.razon_social AS bodega,
                   fn_stock_total_vino(v.cod_vino) AS stock_total
              FROM vino v
              JOIN bodega b ON b.cuit = v.cuit_bodega
             WHERE {where_sql}
             ORDER BY v.cod_vino DESC
             LIMIT %s OFFSET %s
            """,
            [*params, page_size, offset],
        )
        items = cur.fetchall()

    return {"items": items, "total": total, "page": page, "page_size": page_size}


def get_vino(conn: psycopg.Connection, cod_vino: int) -> dict[str, Any]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml,
                   v.graduacion, v.precio, v.cuit_bodega, b.razon_social AS bodega,
                   fn_stock_total_vino(v.cod_vino) AS stock_total
              FROM vino v
              JOIN bodega b ON b.cuit = v.cuit_bodega
             WHERE v.cod_vino = %s
            """,
            (cod_vino,),
        )
        vino = cur.fetchone()
        if not vino:
            raise NotFoundError(f"Vino {cod_vino} no encontrado")

        cur.execute(
            """
            SELECT cv.id_cepa, c.nombre AS cepa, c.tipo, cv.porcentaje
              FROM composicion_vino cv
              JOIN cepa c ON c.id_cepa = cv.id_cepa
             WHERE cv.cod_vino = %s
             ORDER BY cv.porcentaje DESC, c.nombre
            """,
            (cod_vino,),
        )
        vino["composiciones"] = cur.fetchall()

        cur.execute(
            """
            SELECT m.id_maridaje, m.nombre, m.temperatura_servicio
              FROM vino_maridaje vm
              JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
             WHERE vm.cod_vino = %s
             ORDER BY m.nombre
            """,
            (cod_vino,),
        )
        vino["maridajes"] = cur.fetchall()

    return vino


def create_vino(conn: psycopg.Connection, data: VinoCreate) -> dict[str, Any]:
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                RETURNING cod_vino
                """,
                (
                    data.nombre,
                    data.tipo,
                    data.anada,
                    data.volumen_ml,
                    data.graduacion,
                    data.precio,
                    data.cuit_bodega,
                ),
            )
            cod_vino = cur.fetchone()["cod_vino"]

            for comp in data.composiciones:
                cur.execute(
                    """
                    INSERT INTO composicion_vino (cod_vino, id_cepa, porcentaje)
                    VALUES (%s, %s, %s)
                    """,
                    (cod_vino, comp.id_cepa, comp.porcentaje),
                )

            for id_mar in data.maridajes_ids:
                cur.execute(
                    "INSERT INTO vino_maridaje (cod_vino, id_maridaje) VALUES (%s, %s)",
                    (cod_vino, id_mar),
                )

    return get_vino(conn, cod_vino)


def update_vino(conn: psycopg.Connection, cod_vino: int, data: VinoUpdate) -> dict[str, Any]:
    fields = data.model_dump(exclude_none=True)
    if not fields:
        return get_vino(conn, cod_vino)

    set_clauses = [f"{col} = %s" for col in fields]
    values = list(fields.values()) + [cod_vino]

    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute(
                f"UPDATE vino SET {', '.join(set_clauses)} WHERE cod_vino = %s RETURNING cod_vino",
                values,
            )
            row = cur.fetchone()
            if not row:
                raise NotFoundError(f"Vino {cod_vino} no encontrado")

    return get_vino(conn, cod_vino)


def delete_vino(conn: psycopg.Connection, cod_vino: int) -> None:
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute("DELETE FROM vino WHERE cod_vino = %s RETURNING cod_vino", (cod_vino,))
            if not cur.fetchone():
                raise NotFoundError(f"Vino {cod_vino} no encontrado")
