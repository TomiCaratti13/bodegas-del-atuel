"""Capa de acceso a datos para clientes (supertipo y 3 subtipos)."""

from __future__ import annotations

from typing import Any
import psycopg

from app.errors import NotFoundError
from app.schemas import ClienteCreate, ClienteUpdate


def list_clientes(
    conn: psycopg.Connection,
    *,
    tipo_cliente: str | None = None,
    q: str | None = None,
    page: int = 1,
    page_size: int = 20,
) -> dict[str, Any]:
    conditions = ["1=1"]
    params: list[Any] = []
    if tipo_cliente:
        conditions.append("c.tipo_cliente = %s")
        params.append(tipo_cliente)
    if q:
        conditions.append("lower(c.nombre_razon_social) LIKE %s")
        params.append(f"%{q.lower()}%")

    where_sql = " AND ".join(conditions)
    offset = (page - 1) * page_size

    with conn.cursor() as cur:
        cur.execute(f"SELECT COUNT(*) AS total FROM cliente c WHERE {where_sql}", params)
        total = cur.fetchone()["total"]

        cur.execute(
            f"""
            SELECT c.id_cliente, c.tipo_cliente, c.nombre_razon_social,
                   c.tipo_documento, c.nro_documento, c.direccion,
                   c.id_localidad, l.nombre AS localidad, c.fecha_alta, c.descuento_pct,
                   cd.zona_cobertura, cd.nro_habilitacion,
                   ce.pais_destino_principal
              FROM cliente c
              JOIN localidad l ON l.id_localidad = c.id_localidad
              LEFT JOIN cliente_distribuidor cd ON cd.id_cliente = c.id_cliente
              LEFT JOIN cliente_exportador ce ON ce.id_cliente = c.id_cliente
             WHERE {where_sql}
             ORDER BY c.id_cliente DESC
             LIMIT %s OFFSET %s
            """,
            [*params, page_size, offset],
        )
        items = cur.fetchall()

    return {"items": items, "total": total, "page": page, "page_size": page_size}


def get_cliente(conn: psycopg.Connection, id_cliente: int) -> dict[str, Any]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT c.id_cliente, c.tipo_cliente, c.nombre_razon_social,
                   c.tipo_documento, c.nro_documento, c.direccion,
                   c.id_localidad, l.nombre AS localidad, c.fecha_alta, c.descuento_pct,
                   cd.zona_cobertura, cd.nro_habilitacion,
                   ce.pais_destino_principal
              FROM cliente c
              JOIN localidad l ON l.id_localidad = c.id_localidad
              LEFT JOIN cliente_distribuidor cd ON cd.id_cliente = c.id_cliente
              LEFT JOIN cliente_exportador ce ON ce.id_cliente = c.id_cliente
             WHERE c.id_cliente = %s
            """,
            (id_cliente,),
        )
        row = cur.fetchone()
        if not row:
            raise NotFoundError(f"Cliente {id_cliente} no encontrado")

        if row["tipo_cliente"] == "exportador":
            cur.execute(
                """
                SELECT codigo, fecha_emision, fecha_vencimiento
                  FROM permiso_exportacion
                 WHERE id_exportador = %s
                 ORDER BY fecha_emision DESC
                """,
                (id_cliente,),
            )
            row["permisos"] = cur.fetchall()
        return row


def create_cliente(conn: psycopg.Connection, data: ClienteCreate) -> dict[str, Any]:
    with conn.transaction():
        with conn.cursor() as cur:
            # El trigger trg_cliente_descuento_inicial fija descuento_pct segun tipo_cliente (RN-06)
            cur.execute(
                """
                INSERT INTO cliente (
                    tipo_cliente, nombre_razon_social, tipo_documento,
                    nro_documento, direccion, id_localidad
                )
                VALUES (%s, %s, %s, %s, %s, %s)
                RETURNING id_cliente
                """,
                (
                    data.tipo_cliente,
                    data.nombre_razon_social,
                    data.tipo_documento,
                    data.nro_documento,
                    data.direccion,
                    data.id_localidad,
                ),
            )
            id_cliente = cur.fetchone()["id_cliente"]

            if data.tipo_cliente == "socio":
                cur.execute(
                    "INSERT INTO cliente_socio (id_cliente) VALUES (%s)",
                    (id_cliente,),
                )
            elif data.tipo_cliente == "distribuidor":
                cur.execute(
                    """
                    INSERT INTO cliente_distribuidor (id_cliente, zona_cobertura, nro_habilitacion)
                    VALUES (%s, %s, %s)
                    """,
                    (id_cliente, data.zona_cobertura, data.nro_habilitacion),
                )
            elif data.tipo_cliente == "exportador":
                cur.execute(
                    """
                    INSERT INTO cliente_exportador (id_cliente, pais_destino_principal)
                    VALUES (%s, %s)
                    """,
                    (id_cliente, data.pais_destino_principal),
                )
                for p in data.permisos:
                    cur.execute(
                        """
                        INSERT INTO permiso_exportacion (codigo, id_exportador, fecha_emision, fecha_vencimiento)
                        VALUES (%s, %s, %s, %s)
                        """,
                        (p.codigo, id_cliente, p.fecha_emision, p.fecha_vencimiento),
                    )

    return get_cliente(conn, id_cliente)


def update_cliente(conn: psycopg.Connection, id_cliente: int, data: ClienteUpdate) -> dict[str, Any]:
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute("SELECT tipo_cliente FROM cliente WHERE id_cliente = %s", (id_cliente,))
            existing = cur.fetchone()
            if not existing:
                raise NotFoundError(f"Cliente {id_cliente} no encontrado")

            base_updates: dict[str, Any] = {}
            if data.nombre_razon_social is not None:
                base_updates["nombre_razon_social"] = data.nombre_razon_social
            if data.direccion is not None:
                base_updates["direccion"] = data.direccion
            if data.id_localidad is not None:
                base_updates["id_localidad"] = data.id_localidad

            if base_updates:
                sets = [f"{k} = %s" for k in base_updates]
                cur.execute(
                    f"UPDATE cliente SET {', '.join(sets)} WHERE id_cliente = %s",
                    [*base_updates.values(), id_cliente],
                )

            if existing["tipo_cliente"] == "distribuidor" and data.zona_cobertura is not None:
                cur.execute(
                    "UPDATE cliente_distribuidor SET zona_cobertura = %s WHERE id_cliente = %s",
                    (data.zona_cobertura, id_cliente),
                )
            elif existing["tipo_cliente"] == "exportador" and data.pais_destino_principal is not None:
                cur.execute(
                    "UPDATE cliente_exportador SET pais_destino_principal = %s WHERE id_cliente = %s",
                    (data.pais_destino_principal, id_cliente),
                )

    return get_cliente(conn, id_cliente)


def delete_cliente(conn: psycopg.Connection, id_cliente: int) -> None:
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute("DELETE FROM cliente WHERE id_cliente = %s RETURNING id_cliente", (id_cliente,))
            if not cur.fetchone():
                raise NotFoundError(f"Cliente {id_cliente} no encontrado")
