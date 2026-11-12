"""Capa de acceso a datos para operaciones transaccionales: comprobantes, transferencias e ingresos.
La API NO recalcula totales, descuentos ni stock: delega en triggers y procedimientos de PostgreSQL.
"""

from __future__ import annotations

from typing import Any
import psycopg

from app.errors import NotFoundError
from app.schemas import ComprobanteCreate, IngresoCreate, RenglonDocumentoCreate, TransferenciaCreate


# ------------------------------------------------------------------------------
# Comprobantes (Ventas)
# ------------------------------------------------------------------------------
def get_comprobante(conn: psycopg.Connection, nro_comprobante: int) -> dict[str, Any]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT c.nro_comprobante, c.fecha, c.id_cliente, cl.nombre_razon_social AS cliente,
                   cl.tipo_cliente, c.id_sala, sv.calle || ' ' || sv.numero AS sala,
                   c.subtotal, c.descuento, c.total
              FROM comprobante c
              JOIN cliente cl ON cl.id_cliente = c.id_cliente
              JOIN sala_venta sv ON sv.id_sala = c.id_sala
             WHERE c.nro_comprobante = %s
            """,
            (nro_comprobante,),
        )
        comp = cur.fetchone()
        if not comp:
            raise NotFoundError(f"Comprobante {nro_comprobante} no encontrado")

        cur.execute(
            """
            SELECT rc.cod_vino, v.nombre AS vino, rc.cantidad,
                   rc.precio_unitario, rc.descuento_pct, rc.subtotal
              FROM renglon_comprobante rc
              JOIN vino v ON v.cod_vino = rc.cod_vino
             WHERE rc.nro_comprobante = %s
             ORDER BY rc.cod_vino
            """,
            (nro_comprobante,),
        )
        comp["renglones"] = cur.fetchall()
    return comp


def create_comprobante(conn: psycopg.Connection, data: ComprobanteCreate) -> dict[str, Any]:
    # Toda la venta (cabecera + renglones) ocurre en una unica transaccion atomica.
    # Si algun renglon falla por falta de stock (RN-09), se revierte todo sin dejar cabecera huerfana.
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO comprobante (id_cliente, id_sala)
                VALUES (%s, %s)
                RETURNING nro_comprobante
                """,
                (data.id_cliente, data.id_sala),
            )
            nro = cur.fetchone()["nro_comprobante"]

            for item in data.renglones:
                # Los triggers BEFORE/AFTER INSERT validan stock, calculan precio/descuento/subtotal
                # y actualizan stock_sala + totales de comprobante.
                cur.execute(
                    """
                    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
                    VALUES (%s, %s, %s)
                    """,
                    (nro, item.cod_vino, item.cantidad),
                )

    return get_comprobante(conn, nro)


# ------------------------------------------------------------------------------
# Transferencias
# ------------------------------------------------------------------------------
def list_transferencias(conn: psycopg.Connection, page: int = 1, page_size: int = 20) -> dict[str, Any]:
    offset = (page - 1) * page_size
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) AS total FROM transferencia")
        total = cur.fetchone()["total"]
        cur.execute(
            """
            SELECT t.nro_solicitud, t.id_sala, sv.calle || ' ' || sv.numero AS sala,
                   l.nombre AS localidad, t.fecha_confeccion, t.estado
              FROM transferencia t
              JOIN sala_venta sv ON sv.id_sala = t.id_sala
              JOIN localidad l ON l.id_localidad = sv.id_localidad
             ORDER BY t.nro_solicitud DESC
             LIMIT %s OFFSET %s
            """,
            (page_size, offset),
        )
        items = cur.fetchall()
    return {"items": items, "total": total, "page": page, "page_size": page_size}


def get_transferencia(conn: psycopg.Connection, nro_solicitud: int) -> dict[str, Any]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT t.nro_solicitud, t.id_sala, sv.calle || ' ' || sv.numero AS sala,
                   t.fecha_confeccion, t.estado
              FROM transferencia t
              JOIN sala_venta sv ON sv.id_sala = t.id_sala
             WHERE t.nro_solicitud = %s
            """,
            (nro_solicitud,),
        )
        tr = cur.fetchone()
        if not tr:
            raise NotFoundError(f"Transferencia {nro_solicitud} no encontrada")

        cur.execute(
            """
            SELECT rt.cod_vino, v.nombre AS vino, rt.cantidad
              FROM renglon_transferencia rt
              JOIN vino v ON v.cod_vino = rt.cod_vino
             WHERE rt.nro_solicitud = %s
             ORDER BY rt.cod_vino
            """,
            (nro_solicitud,),
        )
        tr["renglones"] = cur.fetchall()
    return tr


def create_transferencia(conn: psycopg.Connection, data: TransferenciaCreate) -> dict[str, Any]:
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO transferencia (id_sala)
                VALUES (%s)
                RETURNING nro_solicitud
                """,
                (data.id_sala,),
            )
            nro = cur.fetchone()["nro_solicitud"]
    return get_transferencia(conn, nro)


def add_renglon_transferencia(
    conn: psycopg.Connection, nro_solicitud: int, data: RenglonDocumentoCreate
) -> dict[str, Any]:
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM transferencia WHERE nro_solicitud = %s", (nro_solicitud,))
            if not cur.fetchone():
                raise NotFoundError(f"Transferencia {nro_solicitud} no encontrada")
            cur.execute(
                """
                INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad)
                VALUES (%s, %s, %s)
                """,
                (nro_solicitud, data.cod_vino, data.cantidad),
            )
    return get_transferencia(conn, nro_solicitud)


def terminar_transferencia(conn: psycopg.Connection, nro_solicitud: int) -> dict[str, Any]:
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE transferencia
                   SET estado = 'terminado'
                 WHERE nro_solicitud = %s
                RETURNING nro_solicitud
                """,
                (nro_solicitud,),
            )
            if not cur.fetchone():
                raise NotFoundError(f"Transferencia {nro_solicitud} no encontrada")
    return get_transferencia(conn, nro_solicitud)


def procesar_transferencia(conn: psycopg.Connection, nro_solicitud: int) -> dict[str, Any]:
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute("CALL sp_procesar_transferencia(%s)", (nro_solicitud,))
    return get_transferencia(conn, nro_solicitud)


# ------------------------------------------------------------------------------
# Ingresos
# ------------------------------------------------------------------------------
def get_ingreso(conn: psycopg.Connection, cod_ingreso: int) -> dict[str, Any]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT i.cod_ingreso, i.fecha, i.estado, i.cod_transportista,
                   t.razon_social AS transportista, i.cuit_bodega, b.razon_social AS bodega
              FROM ingreso i
              JOIN transportista t ON t.cod_transportista = i.cod_transportista
              JOIN bodega b ON b.cuit = i.cuit_bodega
             WHERE i.cod_ingreso = %s
            """,
            (cod_ingreso,),
        )
        ing = cur.fetchone()
        if not ing:
            raise NotFoundError(f"Ingreso {cod_ingreso} no encontrado")

        cur.execute(
            """
            SELECT ri.cod_vino, v.nombre AS vino, ri.cantidad
              FROM renglon_ingreso ri
              JOIN vino v ON v.cod_vino = ri.cod_vino
             WHERE ri.cod_ingreso = %s
             ORDER BY ri.cod_vino
            """,
            (cod_ingreso,),
        )
        ing["renglones"] = cur.fetchall()
    return ing


def create_ingreso(conn: psycopg.Connection, data: IngresoCreate) -> dict[str, Any]:
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO ingreso (cod_transportista, cuit_bodega)
                VALUES (%s, %s)
                RETURNING cod_ingreso
                """,
                (data.cod_transportista, data.cuit_bodega),
            )
            cod = cur.fetchone()["cod_ingreso"]
    return get_ingreso(conn, cod)


def add_renglon_ingreso(
    conn: psycopg.Connection, cod_ingreso: int, data: RenglonDocumentoCreate
) -> dict[str, Any]:
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM ingreso WHERE cod_ingreso = %s", (cod_ingreso,))
            if not cur.fetchone():
                raise NotFoundError(f"Ingreso {cod_ingreso} no encontrado")
            cur.execute(
                """
                INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
                VALUES (%s, %s, %s)
                """,
                (cod_ingreso, data.cod_vino, data.cantidad),
            )
    return get_ingreso(conn, cod_ingreso)


def terminar_ingreso(conn: psycopg.Connection, cod_ingreso: int) -> dict[str, Any]:
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE ingreso
                   SET estado = 'terminado'
                 WHERE cod_ingreso = %s
                RETURNING cod_ingreso
                """,
                (cod_ingreso,),
            )
            if not cur.fetchone():
                raise NotFoundError(f"Ingreso {cod_ingreso} no encontrado")
    return get_ingreso(conn, cod_ingreso)


def procesar_ingreso(conn: psycopg.Connection, cod_ingreso: int) -> dict[str, Any]:
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute("CALL sp_procesar_ingreso(%s)", (cod_ingreso,))
    return get_ingreso(conn, cod_ingreso)
