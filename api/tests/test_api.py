"""Pruebas automaticas de la API REST contra PostgreSQL real (Etapa 6).
Incluye >= 8 pruebas, >= 3 violaciones de reglas de negocio de la BD y prueba de SQLi.
"""

from __future__ import annotations

import uuid

from fastapi.testclient import TestClient
import pytest

from app.main import app


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


def test_01_salud_y_rol_minimo(client: TestClient):
    r = client.get("/salud")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["db"]["ok"] == 1
    assert body["db"]["db_user"] == "app_rw"


def test_02_listar_vinos_paginado_y_filtros(client: TestClient):
    r = client.get("/vinos", params={"tipo": "tinto", "page": 1, "page_size": 5})
    assert r.status_code == 200
    data = r.json()
    assert "items" in data and "total" in data
    assert len(data["items"]) <= 5


def test_03_violacion_rn05_composicion_no_suma_100(client: TestClient):
    cats = client.get("/catalogos").json()
    bodega = cats["bodegas"][0]["cuit"]
    cepa = cats["cepas"][0]["id_cepa"]
    uniq = uuid.uuid4().hex[:6]

    r = client.post(
        "/vinos",
        json={
            "nombre": f"Vino Invalido {uniq}",
            "tipo": "tinto",
            "anada": 2023,
            "volumen_ml": 750,
            "graduacion": 13.5,
            "precio": 9500,
            "cuit_bodega": bodega,
            "composiciones": [{"id_cepa": cepa, "porcentaje": 80}],
            "maridajes_ids": [],
        },
    )
    assert r.status_code == 409
    assert r.json()["sqlstate"] == "P0001"


def test_04_violacion_rn01_precio_negativo(client: TestClient):
    cats = client.get("/catalogos").json()
    bodega = cats["bodegas"][0]["cuit"]
    cepa = cats["cepas"][0]["id_cepa"]
    uniq = uuid.uuid4().hex[:6]

    r = client.post(
        "/vinos",
        json={
            "nombre": f"Vino Negativo {uniq}",
            "tipo": "tinto",
            "anada": 2023,
            "volumen_ml": 750,
            "graduacion": 13.5,
            "precio": -500,
            "cuit_bodega": bodega,
            "composiciones": [{"id_cepa": cepa, "porcentaje": 100}],
            "maridajes_ids": [],
        },
    )
    assert r.status_code == 422
    assert r.json()["sqlstate"] == "23514"


def test_05_alta_vino_y_auditoria_precio_rn13(client: TestClient):
    cats = client.get("/catalogos").json()
    bodega = cats["bodegas"][0]["cuit"]
    cepa = cats["cepas"][0]["id_cepa"]
    maridaje = cats["maridajes"][0]["id_maridaje"]
    uniq = uuid.uuid4().hex[:6]

    r_create = client.post(
        "/vinos",
        json={
            "nombre": f"Vino Test API {uniq}",
            "tipo": "tinto",
            "anada": 2022,
            "volumen_ml": 750,
            "graduacion": 14.0,
            "precio": 10000,
            "cuit_bodega": bodega,
            "composiciones": [{"id_cepa": cepa, "porcentaje": 100}],
            "maridajes_ids": [maridaje],
        },
    )
    assert r_create.status_code == 201
    cod_vino = r_create.json()["cod_vino"]

    r_upd = client.put(f"/vinos/{cod_vino}", json={"precio": 12000})
    assert r_upd.status_code == 200
    assert float(r_upd.json()["precio"]) == 12000.0

    r_traz = client.get(f"/reportes/trazabilidad/{cod_vino}")
    assert r_traz.status_code == 200
    hist = r_traz.json()["historial_precios"]
    assert len(hist) >= 1
    assert float(hist[0]["precio_anterior"]) == 10000.0
    assert float(hist[0]["precio_nuevo"]) == 12000.0


def test_06_violacion_rn09_venta_sin_stock_no_deja_datos_a_medias(client: TestClient):
    clientes = client.get("/clientes", params={"page_size": 1}).json()["items"]
    vinos = client.get("/vinos", params={"page_size": 1}).json()["items"]
    id_cliente = clientes[0]["id_cliente"]
    cod_vino = vinos[0]["cod_vino"]

    r = client.post(
        "/comprobantes",
        json={
            "id_cliente": id_cliente,
            "id_sala": 1,
            "renglones": [{"cod_vino": cod_vino, "cantidad": 9999999}],
        },
    )
    assert r.status_code == 409
    assert r.json()["sqlstate"] == "P0001"
    assert "RN-09" in r.json()["error"]


def test_07_venta_valida_calcula_totales_en_bd(client: TestClient):
    cats = client.get("/catalogos").json()
    bodega = cats["bodegas"][0]["cuit"]
    transp = cats["transportistas"][0]["cod_transportista"]
    cepa = cats["cepas"][0]["id_cepa"]
    localidad = cats["localidades"][0]["id_localidad"]
    uniq = uuid.uuid4().hex[:6]

    # Crea vino y cliente socio (10% descuento)
    vino = client.post(
        "/vinos",
        json={
            "nombre": f"Vino Venta {uniq}",
            "tipo": "blanco",
            "anada": 2023,
            "volumen_ml": 750,
            "graduacion": 12.5,
            "precio": 10000,
            "cuit_bodega": bodega,
            "composiciones": [{"id_cepa": cepa, "porcentaje": 100}],
        },
    ).json()
    cod_vino = vino["cod_vino"]

    cli = client.post(
        "/clientes",
        json={
            "tipo_cliente": "socio",
            "nombre_razon_social": f"Socio Test {uniq}",
            "tipo_documento": "DNI",
            "nro_documento": f"9{uuid.uuid4().int % 89999999 + 10000000}",
            "direccion": "San Martin 100",
            "id_localidad": localidad,
        },
    ).json()

    # Ingresa 10 botellas a deposito y transfiere 5 a sala 1
    ing = client.post("/ingresos", json={"cod_transportista": transp, "cuit_bodega": bodega}).json()
    cod_ing = ing["cod_ingreso"]
    client.post(f"/ingresos/{cod_ing}/renglones", json={"cod_vino": cod_vino, "cantidad": 10})
    client.post(f"/ingresos/{cod_ing}/terminar")
    assert client.post(f"/ingresos/{cod_ing}/procesar").status_code == 200

    tr = client.post("/transferencias", json={"id_sala": 1}).json()
    nro_tr = tr["nro_solicitud"]
    client.post(f"/transferencias/{nro_tr}/renglones", json={"cod_vino": cod_vino, "cantidad": 5})
    client.post(f"/transferencias/{nro_tr}/terminar")
    assert client.post(f"/transferencias/{nro_tr}/procesar").status_code == 200

    # Vende 2 botellas: 2 * 10.000 = 20.000 bruto, 10% desc = 2.000, total = 18.000
    comp = client.post(
        "/comprobantes",
        json={
            "id_cliente": cli["id_cliente"],
            "id_sala": 1,
            "renglones": [{"cod_vino": cod_vino, "cantidad": 2}],
        },
    )
    assert comp.status_code == 201
    body = comp.json()
    assert float(body["subtotal"]) == 20000.0
    assert float(body["descuento"]) == 2000.0
    assert float(body["total"]) == 18000.0


def test_08_violacion_rn12_renglon_transferencia_terminada(client: TestClient):
    vinos = client.get("/vinos", params={"page_size": 1}).json()["items"]
    cod_vino = vinos[0]["cod_vino"]

    tr = client.post("/transferencias", json={"id_sala": 1}).json()
    nro = tr["nro_solicitud"]
    assert client.post(f"/transferencias/{nro}/renglones", json={"cod_vino": cod_vino, "cantidad": 1}).status_code == 201
    assert client.post(f"/transferencias/{nro}/terminar").status_code == 200

    # Intentar agregar renglon cuando ya esta 'terminado' debe fallar (RN-12)
    r_block = client.post(f"/transferencias/{nro}/renglones", json={"cod_vino": cod_vino, "cantidad": 2})
    assert r_block.status_code == 409
    assert r_block.json()["sqlstate"] == "P0001"


def test_09_reportes_disponibles(client: TestClient):
    assert client.get("/reportes/top-vinos").status_code == 200
    assert client.get("/reportes/ventas-por-sala").status_code == 200
    assert client.get("/reportes/vinos-sin-stock", params={"id_sala": 1}).status_code == 200


def test_10_inyeccion_sql_fallida_por_parametrizacion(client: TestClient):
    r = client.get("/vinos", params={"q": "' OR '1'='1' --"})
    assert r.status_code == 200
    assert r.json()["items"] == []
