"""
seed.py - Etapa 3: Carga masiva reproducible para Bodegas del Atuel.

Uso:
    python seed.py --scale full       # 20.000 clientes, 150.000 comprobantes, ~525.000 renglones
    python seed.py --scale cloud      # Carga reducida para nube gratuita (12.000+ renglones)
    python seed.py --benchmark        # Compara insercion fila-a-fila vs COPY por lotes
"""

from __future__ import annotations

import argparse
import csv
import io
import os
import random
import time
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path

import psycopg
from faker import Faker

SEED = 2026
BASE_DIR = Path(__file__).resolve().parent

SCALES = {
    "full": {
        "bodegas": 12,
        "fincas": 20,
        "parcelas_por_finca": 18,      # 360 parcelas
        "salas": 20,
        "empleados": 120,
        "transportistas": 15,
        "vinos": 350,
        "lotes_por_parcela_anios": 5,  # ~1.800 lotes
        "ingresos": 800,
        "transferencias": 1200,
        "clientes": 20000,
        "comprobantes": 150000,
        "min_renglones": 3,
        "max_renglones": 4,            # ~525.000 renglones
    },
    "cloud": {
        "bodegas": 8,
        "fincas": 10,
        "parcelas_por_finca": 10,
        "salas": 10,
        "empleados": 40,
        "transportistas": 10,
        "vinos": 120,
        "lotes_por_parcela_anios": 3,
        "ingresos": 150,
        "transferencias": 250,
        "clientes": 2500,
        "comprobantes": 4500,
        "min_renglones": 3,
        "max_renglones": 3,            # 13.500 renglones (> 10.000 requerido en nube)
    },
}


def get_dsn() -> str:
    if dsn := os.getenv("DATABASE_URL"):
        return dsn
    host = os.getenv("POSTGRES_HOST", "localhost")
    port = os.getenv("POSTGRES_PORT", "5432")
    db = os.getenv("POSTGRES_DB", "bodegas_atuel")
    user = os.getenv("POSTGRES_USER", "bodegas_owner")
    pwd = os.getenv("POSTGRES_PASSWORD", "postgres")
    return f"postgresql://{user}:{pwd}@{host}:{port}/{db}"


def load_csv(filename: str) -> list[dict[str, str]]:
    with open(BASE_DIR / filename, mode="r", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def make_cuit(prefix: str, idx: int) -> str:
    return f"{prefix}{idx:09d}"[:11]


def copy_rows(cur: psycopg.Cursor, table: str, columns: list[str], rows: list[tuple]) -> None:
    if not rows:
        return
    cols_sql = ", ".join(columns)
    with cur.copy(f"COPY {table} ({cols_sql}) FROM STDIN") as copy:
        for row in rows:
            copy.write_row(row)


def reset_identities(cur: psycopg.Cursor) -> None:
    tables_cols = [
        ("localidad", "id_localidad"),
        ("sala_venta", "id_sala"),
        ("finca", "id_finca"),
        ("cepa", "id_cepa"),
        ("lote_uva", "nro_lote"),
        ("analisis_calidad", "id_analisis"),
        ("vino", "cod_vino"),
        ("maridaje", "id_maridaje"),
        ("cliente", "id_cliente"),
        ("comprobante", "nro_comprobante"),
        ("transportista", "cod_transportista"),
        ("ingreso", "cod_ingreso"),
        ("transferencia", "nro_solicitud"),
        ("auditoria_precio", "id_auditoria"),
    ]
    for tbl, col in tables_cols:
        cur.execute(
            f"""
            SELECT setval(
                pg_get_serial_sequence('{tbl}', '{col}'),
                COALESCE((SELECT MAX({col}) FROM {tbl}), 1),
                (SELECT COUNT(*) > 0 FROM {tbl})
            );
            """
        )


def truncate_all(cur: psycopg.Cursor) -> None:
    cur.execute(
        """
        TRUNCATE TABLE
            auditoria_precio,
            renglon_transferencia, transferencia,
            renglon_ingreso, ingreso,
            stock_sala, stock_deposito,
            transportista_localidad, transportista,
            renglon_comprobante, comprobante,
            permiso_exportacion, cliente_exportador, cliente_distribuidor, cliente_socio, cliente,
            vino_maridaje, maridaje, composicion_vino, vino,
            analisis_calidad, lote_uva, bodega, parcela, cepa, finca,
            empleado, sala_venta, localidad
        RESTART IDENTITY CASCADE;
        """
    )


def seed_database(conn: psycopg.Connection, scale_name: str) -> dict[str, int]:
    cfg = SCALES[scale_name]
    rng = random.Random(SEED)
    fake = Faker("es_AR")
    Faker.seed(SEED)
    hoy = date.today()

    t0 = time.perf_counter()
    cepas_csv = load_csv("cepas.csv")
    maridajes_csv = load_csv("maridajes.csv")
    localidades_csv = load_csv("localidades_mendoza.csv")

    with conn.cursor() as cur:
        truncate_all(cur)

        # Deshabilitamos triggers de usuario durante la carga historica controlada.
        # La coherencia matematica (totales, descuentos, stocks >= 0, cortes = 100%)
        # se construye exactamente y se verifica con consultas de control al final.
        cur.execute("ALTER TABLE cliente DISABLE TRIGGER USER;")
        cur.execute("ALTER TABLE composicion_vino DISABLE TRIGGER USER;")
        cur.execute("ALTER TABLE ingreso DISABLE TRIGGER USER;")
        cur.execute("ALTER TABLE renglon_ingreso DISABLE TRIGGER USER;")
        cur.execute("ALTER TABLE transferencia DISABLE TRIGGER USER;")
        cur.execute("ALTER TABLE renglon_transferencia DISABLE TRIGGER USER;")
        cur.execute("ALTER TABLE comprobante DISABLE TRIGGER USER;")
        cur.execute("ALTER TABLE renglon_comprobante DISABLE TRIGGER USER;")

        # 1. Localidades (18 reales de Mendoza)
        loc_rows = [
            (r["codigo_postal"], r["nombre"], r["provincia"], fake.name())
            for r in localidades_csv
        ]
        cur.executemany(
            "INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional) VALUES (%s, %s, %s, %s)",
            loc_rows,
        )
        cur.execute("SELECT id_localidad, nombre FROM localidad ORDER BY id_localidad")
        localidades = cur.fetchall()
        loc_ids = [r[0] for r in localidades]

        # 2. Cepas (12 reales) y Maridajes (8 reales)
        cur.executemany("INSERT INTO cepa (nombre, tipo) VALUES (%s, %s)", [(r["nombre"], r["tipo"]) for r in cepas_csv])
        cur.execute("SELECT id_cepa, nombre, tipo FROM cepa ORDER BY id_cepa")
        cepas = cur.fetchall()
        tintas = [c[0] for c in cepas if c[2] == "tinta"]
        blancas = [c[0] for c in cepas if c[2] == "blanca"]

        cur.executemany(
            "INSERT INTO maridaje (nombre, temperatura_servicio) VALUES (%s, %s)",
            [(r["nombre"], int(r["temperatura_servicio"])) for r in maridajes_csv],
        )
        cur.execute("SELECT id_maridaje FROM maridaje ORDER BY id_maridaje")
        maridaje_ids = [r[0] for r in cur.fetchall()]

        # 3. Salas de venta
        dias = ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"]
        salas_rows = []
        for i in range(cfg["salas"]):
            dia = "lunes" if i % 4 == 0 else ("miercoles" if i % 4 == 1 else rng.choice(dias))
            salas_rows.append((fake.street_name(), str(rng.randint(100, 2900)), dia, loc_ids[i % len(loc_ids)]))
        cur.executemany(
            "INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad) VALUES (%s, %s, %s, %s)",
            salas_rows,
        )
        cur.execute("SELECT id_sala FROM sala_venta ORDER BY id_sala")
        sala_ids = [r[0] for r in cur.fetchall()]

        # 4. Empleados (incluye > 5 anios y < 2 anios para U2 y D3)
        emp_rows = []
        for i in range(cfg["empleados"]):
            cuit = make_cuit("20", 300000000 + i)
            antig_dias = rng.randint(1850, 4000) if i % 2 == 0 else rng.randint(30, 650)
            emp_rows.append(
                (cuit, fake.name(), hoy - timedelta(days=antig_dias), round(rng.uniform(450000, 1400000), 2), rng.choice(sala_ids))
            )
        copy_rows(cur, "empleado", ["cuit", "nombre", "fecha_ingreso", "salario", "id_sala"], emp_rows)

        # 5. Fincas y Parcelas
        deptos = [r["departamento"] for r in localidades_csv]
        fincas_rows = [
            (f"Finca {fake.last_name()} {i+1}", round(rng.uniform(30, 250), 2), deptos[i % len(deptos)], "Mendoza")
            for i in range(cfg["fincas"])
        ]
        cur.executemany(
            "INSERT INTO finca (nombre, superficie_ha, departamento, provincia) VALUES (%s, %s, %s, %s)",
            fincas_rows,
        )
        cur.execute("SELECT id_finca FROM finca ORDER BY id_finca")
        finca_ids = [r[0] for r in cur.fetchall()]

        parcelas_rows = []
        parcela_keys = []
        # Dejamos 1 cepa blanca fuera de una fraccion para posibles pruebas, pero usamos casi todas
        cepas_plantables = [c[0] for c in cepas]
        for fid in finca_ids:
            for p in range(1, cfg["parcelas_por_finca"] + 1):
                parcelas_rows.append((fid, p, round(rng.uniform(1.5, 12.0), 2), rng.randint(1995, 2021), rng.choice(cepas_plantables)))
                parcela_keys.append((fid, p))
        copy_rows(cur, "parcela", ["id_finca", "nro_parcela", "superficie_ha", "anio_plantacion", "id_cepa"], parcelas_rows)

        # 6. Bodegas
        bodegas = []
        for i in range(cfg["bodegas"]):
            cuit = make_cuit("30", 710000000 + i)
            bodegas.append((cuit, f"Bodega {fake.company()} {i+1}", fake.address().replace("\n", ", ")))
        copy_rows(cur, "bodega", ["cuit", "razon_social", "domicilio"], bodegas)
        bodega_cuits = [b[0] for b in bodegas]

        # 7. Lotes de uva y analisis de calidad (ultimos 5 anios, feb-abr)
        lote_rows = []
        anio_actual = hoy.year
        campanas = list(range(anio_actual - cfg["lotes_por_parcela_anios"], anio_actual))
        for (fid, p) in parcela_keys:
            for camp in campanas:
                mes = rng.choice([2, 3, 4])
                dia = rng.randint(1, 28)
                lote_rows.append(
                    (fid, p, camp, date(camp, mes, dia), round(rng.uniform(3500, 22000), 2), rng.choice(bodega_cuits))
                )
        copy_rows(
            cur,
            "lote_uva",
            ["id_finca", "nro_parcela", "campana", "fecha_cosecha", "kg_cosechados", "cuit_bodega"],
            lote_rows,
        )
        cur.execute("SELECT nro_lote, fecha_cosecha FROM lote_uva")
        lotes = cur.fetchall()
        analisis_rows = []
        for nro_lote, f_cos in lotes:
            for k in range(rng.randint(1, 3)):
                analisis_rows.append(
                    (nro_lote, f_cos + timedelta(days=k * 3), round(rng.uniform(20.0, 26.5), 2), round(rng.uniform(3.2, 3.8), 2), round(rng.uniform(4.5, 7.5), 2))
                )
        copy_rows(cur, "analisis_calidad", ["nro_lote", "fecha", "grado_brix", "ph", "acidez_total"], analisis_rows)

        # 8. Vinos, composicion (100% exacto) y maridajes
        nombres_base = [
            "Atuel Reserva", "Valle Alto", "Gran Corte", "Cosecha Tardia", "Roble del Sur",
            "Altura Andina", "Piedra Viva", "Sendero Austral", "Nieve y Sol", "Finca Vieja",
            "Don Mendoza", "San Rafaelino", "Raices", "Aluvion", "Cordillera",
        ]
        tipos_vino = ["tinto", "blanco", "rosado", "espumante"]
        volumenes = [187, 375, 750, 1500, 3000]
        seen_vino_uq = set()
        vinos_rows = []
        vino_specs = []
        idx = 0
        while len(vinos_rows) < cfg["vinos"]:
            nom = f"{nombres_base[idx % len(nombres_base)]} {idx // len(nombres_base) + 1}".strip()
            tipo = tipos_vino[idx % 4]
            anada = rng.randint(2018, anio_actual - 1)
            vol = rng.choice(volumenes)
            idx += 1
            if (nom, anada, vol) in seen_vino_uq:
                continue
            seen_vino_uq.add((nom, anada, vol))
            grad = round(rng.uniform(14.0, 15.2) if tipo == "tinto" and idx % 3 == 0 else rng.uniform(11.5, 14.8), 2)
            precio = round(rng.uniform(4500, 35000), 2)
            bodega = bodega_cuits[len(vinos_rows) % len(bodega_cuits)]
            vinos_rows.append((nom, tipo, anada, vol, grad, precio, bodega))
            vino_specs.append((tipo, bodega))

        cur.executemany(
            "INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega) VALUES (%s, %s, %s, %s, %s, %s, %s)",
            vinos_rows,
        )
        cur.execute("SELECT cod_vino, tipo, precio, cuit_bodega FROM vino ORDER BY cod_vino")
        vinos_db = cur.fetchall()
        vino_precio = {r[0]: float(r[2]) for r in vinos_db}
        vino_tipo = {r[0]: r[1] for r in vinos_db}
        vino_ids = [r[0] for r in vinos_db]

        comp_rows = []
        vm_rows = []
        for cod_vino, tipo, _, _ in vinos_db:
            pool_cepas = tintas if tipo in ("tinto", "rosado") else blancas
            if rng.random() < 0.45:
                c1 = rng.choice(pool_cepas)
                comp_rows.append((cod_vino, c1, 100.00))
            else:
                c1, c2 = rng.sample(pool_cepas, 2)
                p1 = rng.choice([60, 70, 75, 80, 85])
                comp_rows.append((cod_vino, c1, float(p1)))
                comp_rows.append((cod_vino, c2, float(100 - p1)))

            for mid in rng.sample(maridaje_ids, rng.randint(1, 3)):
                vm_rows.append((cod_vino, mid))

        copy_rows(cur, "composicion_vino", ["cod_vino", "id_cepa", "porcentaje"], comp_rows)
        copy_rows(cur, "vino_maridaje", ["cod_vino", "id_maridaje"], vm_rows)

        # 9. Transportistas y cobertura
        transp_rows = []
        for i in range(cfg["transportistas"]):
            transp_rows.append(
                (f"Logistica {fake.last_name()} {i+1}", make_cuit("30", 600000000 + i), f"logistica{i+1}@atuel.com", fake.phone_number()[:20], fake.address().replace("\n", ", "))
            )
        cur.executemany(
            "INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio) VALUES (%s, %s, %s, %s, %s)",
            transp_rows,
        )
        cur.execute("SELECT cod_transportista FROM transportista ORDER BY cod_transportista")
        transp_ids = [r[0] for r in cur.fetchall()]

        tl_rows = []
        for tid in transp_ids:
            for lid in rng.sample(loc_ids, rng.randint(3, min(10, len(loc_ids)))):
                tl_rows.append((tid, lid))
        copy_rows(cur, "transportista_localidad", ["cod_transportista", "id_localidad"], tl_rows)

        # 10. Clientes (20.000 en full) + subtipos + permisos exportacion
        cli_rows = []
        socio_rows = []
        dist_rows = []
        exp_rows = []
        perm_rows = []
        cli_descuento = {}
        tipos_cli = ["socio", "distribuidor", "exportador"]
        paises = ["Brasil", "Estados Unidos", "Reino Unido", "Alemania", "Canada", "China"]

        for cid in range(1, cfg["clientes"] + 1):
            r_val = rng.random()
            t_cli = "socio" if r_val < 0.75 else ("distribuidor" if r_val < 0.90 else "exportador")
            desc = 10.00 if t_cli == "socio" else (20.00 if t_cli == "distribuidor" else 30.00)
            cli_descuento[cid] = desc
            doc_tipo = "DNI" if t_cli == "socio" else "CUIT"
            nro_doc = f"{10000000 + cid}" if doc_tipo == "DNI" else make_cuit("30", 500000000 + cid)
            antig_dias = rng.randint(1900, 2800) if cid % 10 == 0 else rng.randint(10, 1800)
            f_alta = hoy - timedelta(days=antig_dias)
            cli_rows.append(
                (t_cli, fake.name() if t_cli == "socio" else fake.company(), doc_tipo, nro_doc, fake.street_address(), rng.choice(loc_ids), f_alta, desc)
            )
            if t_cli == "socio":
                socio_rows.append((cid, "socio"))
            elif t_cli == "distribuidor":
                dist_rows.append((cid, "distribuidor", rng.choice(["Cuyo", "Centro", "NOA", "Patagonia", "AMBA"]), f"HAB-{cid:06d}"))
            else:
                exp_rows.append((cid, "exportador", rng.choice(paises)))
                n_perm = 4 if cid % 5 == 0 else rng.randint(1, 3)  # Algunos > 3 permisos para U6
                for p_i in range(n_perm):
                    f_em = hoy - timedelta(days=rng.randint(30, 500))
                    perm_rows.append((f"PEXP-{cid}-{p_i+1}", cid, f_em, f_em + timedelta(days=rng.randint(180, 730))))

        copy_rows(
            cur,
            "cliente",
            ["tipo_cliente", "nombre_razon_social", "tipo_documento", "nro_documento", "direccion", "id_localidad", "fecha_alta", "descuento_pct"],
            cli_rows,
        )
        copy_rows(cur, "cliente_socio", ["id_cliente", "tipo_cliente"], socio_rows)
        copy_rows(cur, "cliente_distribuidor", ["id_cliente", "tipo_cliente", "zona_cobertura", "nro_habilitacion"], dist_rows)
        copy_rows(cur, "cliente_exportador", ["id_cliente", "tipo_cliente", "pais_destino_principal"], exp_rows)
        copy_rows(cur, "permiso_exportacion", ["codigo", "id_exportador", "fecha_emision", "fecha_vencimiento"], perm_rows)

        # 11. Ingresos y Transferencias (incluye historicos > 365 dias, recientes 15 dias y pendientes)
        stock_dep = defaultdict(int)
        stock_sal = defaultdict(int)

        ing_rows = []
        reng_ing_rows = []
        for iid in range(1, cfg["ingresos"] + 1):
            if iid <= int(cfg["ingresos"] * 0.90):
                estado = "procesado"
                dias_atras = rng.randint(400, 900) if iid % 5 == 0 else rng.randint(1, 350)
            elif iid <= int(cfg["ingresos"] * 0.95):
                estado = "terminado"
                dias_atras = rng.randint(0, 15)
            else:
                estado = "en_confeccion"
                dias_atras = rng.randint(0, 7)

            # Dejamos un transportista con menos envios para I1
            t_choice = transp_ids[0] if iid % 50 == 0 else rng.choice(transp_ids[1:])
            ing_rows.append((hoy - timedelta(days=dias_atras), estado, t_choice, rng.choice(bodega_cuits)))
            for vid in rng.sample(vino_ids, rng.randint(3, 6)):
                cant = rng.randint(800, 2500) if scale_name == "full" else rng.randint(200, 800)
                reng_ing_rows.append((iid, vid, cant))
                if estado == "procesado":
                    stock_dep[vid] += cant

        copy_rows(cur, "ingreso", ["fecha", "estado", "cod_transportista", "cuit_bodega"], ing_rows)
        copy_rows(cur, "renglon_ingreso", ["cod_ingreso", "cod_vino", "cantidad"], reng_ing_rows)

        transf_rows = []
        reng_transf_rows = []
        for tid in range(1, cfg["transferencias"] + 1):
            if tid <= int(cfg["transferencias"] * 0.85):
                estado = "procesado"
                dias_atras = rng.randint(0, 14) if tid % 3 == 0 else rng.randint(15, 300)
            elif tid <= int(cfg["transferencias"] * 0.92):
                estado = "terminado"
                dias_atras = rng.randint(0, 10)
            else:
                estado = "en_confeccion"
                dias_atras = rng.randint(0, 5)

            sid = rng.choice(sala_ids)
            transf_rows.append((sid, hoy - timedelta(days=dias_atras), estado))
            for vid in rng.sample(vino_ids, rng.randint(2, 5)):
                if estado == "procesado":
                    disp = stock_dep[vid]
                    if disp <= 20:
                        continue
                    cant = min(rng.randint(50, 300), disp // 4 + 1)
                    stock_dep[vid] -= cant
                    stock_sal[(sid, vid)] += cant
                else:
                    cant = rng.randint(10, 40)
                reng_transf_rows.append((tid, vid, cant))

        copy_rows(cur, "transferencia", ["id_sala", "fecha_confeccion", "estado"], transf_rows)
        copy_rows(cur, "renglon_transferencia", ["nro_solicitud", "cod_vino", "cantidad"], reng_transf_rows)

        # 12. Comprobantes y renglones (150k comprobantes / ~525k renglones en full)
        # Aseguramos:
        #   - Los primeros vinos se venden en TODAS las salas (para S2)
        #   - Algunos clientes compraron todos los vinos de la bodega 1 (para S12)
        #   - Algunos clientes nunca compraron vino tinto (para S12)
        #   - Algunos comprobantes > 5 anios (para D1) y algunos clientes socios sin compras (para D4)
        vinos_bodega_1 = [r[0] for r in vinos_db if r[3] == bodega_cuits[0]]
        vinos_no_tintos = [vid for vid in vino_ids if vino_tipo[vid] != "tinto"]

        # Reservamos clientes del final (ej. ultimos 2%) sin compras para D4/D6
        max_cli_comprador = int(cfg["clientes"] * 0.97)
        clientes_solo_blancos = set(range(1, min(15, max_cli_comprador)))

        # Calculamos ventas garantizando que stock_sal nunca sea negativo:
        # primero generamos renglones y sumamos el stock necesario a stock_sal/stock_dep si hiciera falta,
        # manteniendo coherencia (ingreso >= transferencias >= ventas).
        comp_rows = []
        reng_comp_rows = []

        # Semilla especial para S2: el vino_ids[0] y vino_ids[1] se venden en todas las salas
        comp_idx = 0
        for sid in sala_ids:
            comp_idx += 1
            cid = 20 + comp_idx
            desc_pct = cli_descuento[cid]
            sub_bruto = 0.0
            tot_neto = 0.0
            for vid in vino_ids[:2]:
                cant = 2
                pu = vino_precio[vid]
                sub_r = round(cant * pu * (1 - desc_pct / 100.0), 2)
                sub_bruto += cant * pu
                tot_neto += sub_r
                reng_comp_rows.append((comp_idx, vid, cant, pu, desc_pct, sub_r))
                stock_sal[(sid, vid)] += 20  # aseguramos stock inicial suficiente para venta historica
                stock_sal[(sid, vid)] -= cant
            comp_rows.append((hoy - timedelta(days=rng.randint(1, 30)), cid, sid, round(sub_bruto, 2), round(sub_bruto - tot_neto, 2), round(tot_neto, 2)))

        # Semilla especial para S12: cliente 25 compro todos los vinos de bodega 1
        if vinos_bodega_1:
            comp_idx += 1
            cid = 25
            sid = sala_ids[0]
            desc_pct = cli_descuento[cid]
            sub_bruto = 0.0
            tot_neto = 0.0
            for vid in vinos_bodega_1:
                pu = vino_precio[vid]
                sub_r = round(pu * (1 - desc_pct / 100.0), 2)
                sub_bruto += pu
                tot_neto += sub_r
                reng_comp_rows.append((comp_idx, vid, 1, pu, desc_pct, sub_r))
            comp_rows.append((hoy - timedelta(days=10), cid, sid, round(sub_bruto, 2), round(sub_bruto - tot_neto, 2), round(tot_neto, 2)))

        # Carga masiva restante con fechas ordenadas cronologicamente para favorecer BRIN(fecha)
        restantes = cfg["comprobantes"] - comp_idx
        fecha_inicio = hoy - timedelta(days=2100)  # ~5.7 anios atras hasta hoy
        for k in range(restantes):
            comp_idx += 1
            # Avance monotono aproximado de fecha para que la tabla quede fisicamente correlacionada con fecha
            progreso = k / max(1, restantes - 1)
            dias_desde_inicio = int(progreso * 2100) + rng.randint(-3, 3)
            dias_desde_inicio = max(0, min(2100, dias_desde_inicio))
            f_comp = fecha_inicio + timedelta(days=dias_desde_inicio)

            cid = rng.randint(1, max_cli_comprador)
            sid = rng.choice(sala_ids)
            desc_pct = cli_descuento[cid]
            n_reng = rng.randint(cfg["min_renglones"], cfg["max_renglones"])
            pool = vinos_no_tintos if cid in clientes_solo_blancos and len(vinos_no_tintos) >= n_reng else vino_ids
            elegidos = rng.sample(pool, n_reng)

            sub_bruto = 0.0
            tot_neto = 0.0
            for vid in elegidos:
                cant = rng.randint(1, 6)
                pu = vino_precio[vid]
                sub_r = round(cant * pu * (1 - desc_pct / 100.0), 2)
                sub_bruto += cant * pu
                tot_neto += sub_r
                reng_comp_rows.append((comp_idx, vid, cant, pu, desc_pct, sub_r))

            comp_rows.append((f_comp, cid, sid, round(sub_bruto, 2), round(sub_bruto - tot_neto, 2), round(tot_neto, 2)))

        copy_rows(cur, "comprobante", ["fecha", "id_cliente", "id_sala", "subtotal", "descuento", "total"], comp_rows)
        copy_rows(
            cur,
            "renglon_comprobante",
            ["nro_comprobante", "cod_vino", "cantidad", "precio_unitario", "descuento_pct", "subtotal"],
            reng_comp_rows,
        )

        # 13. Stock deposito y stock sala finales (coherentes y >= 0, garantizando casos para S6 y ventas futuras)
        dep_rows = [(vid, max(stock_dep[vid], 100)) for vid in vino_ids]
        copy_rows(cur, "stock_deposito", ["cod_vino", "cantidad"], dep_rows)

        sal_rows = []
        for sid in sala_ids:
            for idx_v, vid in enumerate(vino_ids):
                # En sala 1, dejamos algunos vinos con stock 0 para probar S6 y RN-09
                if sid == sala_ids[0] and idx_v % 10 == 9:
                    cant_final = 0
                else:
                    cant_final = max(stock_sal[(sid, vid)], rng.randint(15, 120))
                sal_rows.append((sid, vid, cant_final))
        copy_rows(cur, "stock_sala", ["id_sala", "cod_vino", "cantidad"], sal_rows)

        # Rehabilitar triggers y sincronizar secuencias
        cur.execute("ALTER TABLE cliente ENABLE TRIGGER USER;")
        cur.execute("ALTER TABLE composicion_vino ENABLE TRIGGER USER;")
        cur.execute("ALTER TABLE ingreso ENABLE TRIGGER USER;")
        cur.execute("ALTER TABLE renglon_ingreso ENABLE TRIGGER USER;")
        cur.execute("ALTER TABLE transferencia ENABLE TRIGGER USER;")
        cur.execute("ALTER TABLE renglon_transferencia ENABLE TRIGGER USER;")
        cur.execute("ALTER TABLE comprobante ENABLE TRIGGER USER;")
        cur.execute("ALTER TABLE renglon_comprobante ENABLE TRIGGER USER;")

        reset_identities(cur)
        conn.commit()

        elapsed = time.perf_counter() - t0
        print(f"[seed] Carga '{scale_name}' completada en {elapsed:.2f}s")

        # Consultas de control de Etapa 3
        counts = run_control_queries(cur)
        return counts


def run_control_queries(cur: psycopg.Cursor) -> dict[str, int]:
    tables = [
        "localidad", "sala_venta", "empleado", "finca", "parcela", "cepa",
        "lote_uva", "analisis_calidad", "bodega", "vino", "composicion_vino",
        "maridaje", "vino_maridaje", "cliente", "cliente_socio",
        "cliente_distribuidor", "cliente_exportador", "permiso_exportacion",
        "comprobante", "renglon_comprobante", "transportista",
        "transportista_localidad", "stock_deposito", "stock_sala",
        "ingreso", "renglon_ingreso", "transferencia", "renglon_transferencia",
    ]
    counts: dict[str, int] = {}
    print("\n--- Conteo de filas por tabla ---")
    for t in tables:
        cur.execute(f"SELECT COUNT(*) FROM {t}")
        cnt = cur.fetchone()[0]
        counts[t] = cnt
        print(f"  {t:26s}: {cnt:>10,d}")

    checks = {
        "stock_sala_negativo": "SELECT COUNT(*) FROM stock_sala WHERE cantidad < 0",
        "stock_deposito_negativo": "SELECT COUNT(*) FROM stock_deposito WHERE cantidad < 0",
        "cortes_distintos_100": """
            SELECT COUNT(*) FROM (
                SELECT cod_vino FROM composicion_vino GROUP BY cod_vino HAVING SUM(porcentaje) <> 100
            ) t
        """,
        "comprobantes_descuadrados": """
            SELECT COUNT(*) FROM (
                SELECT c.nro_comprobante
                FROM comprobante c
                LEFT JOIN renglon_comprobante r ON r.nro_comprobante = c.nro_comprobante
                GROUP BY c.nro_comprobante, c.total
                HAVING ABS(c.total - COALESCE(SUM(r.subtotal), 0)) > 0.01
            ) t
        """,
    }
    print("\n--- Consultas de control de integridad ---")
    for name, sql in checks.items():
        cur.execute(sql)
        bad = cur.fetchone()[0]
        print(f"  {name:28s}: {bad} inconsistencias")
        if bad != 0:
            raise RuntimeError(f"Control fallido en {name}: {bad}")
    return counts


def run_benchmark(conn: psycopg.Connection) -> None:
    """Compara insercion fila-a-fila vs COPY por lotes sobre 5.000 registros temporales."""
    n = 5000
    rows = [(f"Bench {i}", "tinto", 2022, 750, 13.5, 5000.0) for i in range(n)]
    with conn.cursor() as cur:
        cur.execute(
            """
            CREATE TEMP TABLE tmp_bench (
                nombre VARCHAR(100),
                tipo VARCHAR(20),
                anada SMALLINT,
                volumen_ml INTEGER,
                graduacion NUMERIC(4,2),
                precio NUMERIC(12,2)
            ) ON COMMIT PRESERVE ROWS;
            """
        )

        t0 = time.perf_counter()
        for r in rows:
            cur.execute("INSERT INTO tmp_bench VALUES (%s, %s, %s, %s, %s, %s)", r)
        t_row = time.perf_counter() - t0

        cur.execute("TRUNCATE tmp_bench;")

        t1 = time.perf_counter()
        with cur.copy("COPY tmp_bench FROM STDIN") as copy:
            for r in rows:
                copy.write_row(r)
        t_copy = time.perf_counter() - t1

        cur.execute("DROP TABLE tmp_bench;")
        conn.rollback()

    print(f"\n--- Benchmark ({n} filas) ---")
    print(f"  Fila por fila (execute): {t_row:.4f}s")
    print(f"  Por lotes (COPY)       : {t_copy:.4f}s")
    print(f"  Aceleracion            : {t_row / max(t_copy, 1e-6):.1f}x mas rapido")


def main() -> None:
    parser = argparse.ArgumentParser(description="Seed Bodegas del Atuel")
    parser.add_argument("--scale", choices=["full", "cloud"], default="full")
    parser.add_argument("--benchmark", action="store_true", help="Ejecuta comparativa fila-a-fila vs COPY")
    args = parser.parse_args()

    dsn = get_dsn()
    with psycopg.connect(dsn) as conn:
        if args.benchmark:
            run_benchmark(conn)
        else:
            seed_database(conn, args.scale)


if __name__ == "__main__":
    main()
