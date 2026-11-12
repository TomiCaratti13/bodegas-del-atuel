"""Capa de acceso a datos para reportes (Seccion 8) y catalogos auxiliares."""

from __future__ import annotations

from typing import Any
import psycopg

from app.errors import NotFoundError


def top_vinos(conn: psycopg.Connection) -> list[dict[str, Any]]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml,
                   SUM(rc.cantidad) AS botellas_vendidas
              FROM vino v
              JOIN renglon_comprobante rc ON rc.cod_vino = v.cod_vino
             GROUP BY v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml
             ORDER BY botellas_vendidas DESC, v.cod_vino ASC
             LIMIT 10
            """
        )
        return cur.fetchall()


def ventas_por_sala(conn: psycopg.Connection) -> list[dict[str, Any]]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT sv.id_sala,
                   sv.calle || ' ' || sv.numero AS direccion,
                   l.nombre AS localidad,
                   COUNT(c.nro_comprobante) AS cantidad_ventas,
                   COALESCE(SUM(c.total), 0.00)::NUMERIC(14,2) AS monto_total
              FROM sala_venta sv
              JOIN localidad l ON l.id_localidad = sv.id_localidad
              LEFT JOIN comprobante c
                     ON c.id_sala = sv.id_sala
                    AND c.fecha >= (CURRENT_DATE - INTERVAL '3 months')
             GROUP BY sv.id_sala, sv.calle, sv.numero, l.nombre
             ORDER BY monto_total DESC
            """
        )
        return cur.fetchall()


def vinos_sin_stock_sala(conn: psycopg.Connection, id_sala: int) -> list[dict[str, Any]]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml,
                   sd.cantidad AS stock_deposito,
                   COALESCE(ss.cantidad, 0) AS stock_sala
              FROM vino v
              JOIN stock_deposito sd ON sd.cod_vino = v.cod_vino
              LEFT JOIN stock_sala ss
                     ON ss.cod_vino = v.cod_vino
                    AND ss.id_sala = %s
             WHERE sd.cantidad > 0
               AND COALESCE(ss.cantidad, 0) = 0
             ORDER BY sd.cantidad DESC, v.cod_vino ASC
            """,
            (id_sala,),
        )
        return cur.fetchall()


def transportista_activo(conn: psycopg.Connection) -> dict[str, Any] | None:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT tr.cod_transportista, tr.razon_social,
                   COUNT(DISTINCT i.cod_ingreso) AS cantidad_ingresos,
                   COALESCE(SUM(ri.cantidad), 0) AS botellas_trasladadas
              FROM transportista tr
              JOIN ingreso i ON i.cod_transportista = tr.cod_transportista
              LEFT JOIN renglon_ingreso ri ON ri.cod_ingreso = i.cod_ingreso
             WHERE i.fecha >= (CURRENT_DATE - INTERVAL '1 month')
             GROUP BY tr.cod_transportista, tr.razon_social
             ORDER BY cantidad_ingresos DESC, botellas_trasladadas DESC
             LIMIT 1
            """
        )
        return cur.fetchone()


def trazabilidad_vino(conn: psycopg.Connection, cod_vino: int) -> dict[str, Any]:
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM vw_ficha_vino WHERE cod_vino = %s", (cod_vino,))
        ficha = cur.fetchone()
        if not ficha:
            raise NotFoundError(f"Vino {cod_vino} no encontrado")

        cur.execute(
            """
            SELECT COALESCE(sd.cantidad, 0) AS stock_deposito
              FROM vino v
              LEFT JOIN stock_deposito sd ON sd.cod_vino = v.cod_vino
             WHERE v.cod_vino = %s
            """,
            (cod_vino,),
        )
        ficha["stock_deposito"] = cur.fetchone()["stock_deposito"]

        cur.execute(
            """
            SELECT ss.id_sala, sv.calle || ' ' || sv.numero AS sala, ss.cantidad
              FROM stock_sala ss
              JOIN sala_venta sv ON sv.id_sala = ss.id_sala
             WHERE ss.cod_vino = %s
             ORDER BY ss.id_sala
            """,
            (cod_vino,),
        )
        ficha["stock_por_sala"] = cur.fetchall()

        cur.execute(
            """
            SELECT precio_anterior, precio_nuevo, fecha_hora, usuario
              FROM auditoria_precio
             WHERE cod_vino = %s
             ORDER BY fecha_hora DESC
            """,
            (cod_vino,),
        )
        ficha["historial_precios"] = cur.fetchall()

    return ficha


def list_catalogos(conn: psycopg.Connection) -> dict[str, Any]:
    with conn.cursor() as cur:
        cur.execute("SELECT id_cepa, nombre, tipo FROM cepa ORDER BY nombre")
        cepas = cur.fetchall()
        cur.execute("SELECT cuit, razon_social FROM bodega ORDER BY razon_social")
        bodegas = cur.fetchall()
        cur.execute(
            """
            SELECT sv.id_sala, sv.calle || ' ' || sv.numero AS direccion,
                   l.nombre AS localidad, sv.dia_cierre
              FROM sala_venta sv
              JOIN localidad l ON l.id_localidad = sv.id_localidad
             ORDER BY sv.id_sala
            """
        )
        salas = cur.fetchall()
        cur.execute("SELECT id_maridaje, nombre, temperatura_servicio FROM maridaje ORDER BY nombre")
        maridajes = cur.fetchall()
        cur.execute("SELECT id_localidad, nombre, provincia, codigo_postal FROM localidad ORDER BY nombre")
        localidades = cur.fetchall()
        cur.execute("SELECT cod_transportista, razon_social FROM transportista ORDER BY razon_social")
        transportistas = cur.fetchall()
    return {
        "cepas": cepas,
        "bodegas": bodegas,
        "salas": salas,
        "maridajes": maridajes,
        "localidades": localidades,
        "transportistas": transportistas,
    }
