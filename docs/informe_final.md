# Informe Final — TPI «Bodegas del Atuel»

> Estructura alineada con la Seccion 10.2 del enunciado. Completar con las capturas y mediciones locales/nube obtenidas al ejecutar los scripts.

## 1. Introduccion y alcance
Sistema integral de gestion vitivinicola para «Bodegas del Atuel» que abarca produccion en fincas y parcelas, elaboracion en bodegas, stock en deposito central y red de salas de venta, transferencias, ingresos y facturacion a tres tipos de clientes, implementado sobre PostgreSQL 16 con API REST (FastAPI + `psycopg` v3 sin ORM) y frontend React.

## 2. Modelo de datos
- DER fuente: [der.dbml](der.dbml) (importable en dbdiagram.io para exportar PDF/PNG).
- Esquema relacional y justificacion 3FN: [esquema_relacional.md](esquema_relacional.md).
- Diccionario de datos: [diccionario_datos.md](diccionario_datos.md).
- Decisiones de diseno: [decisiones_diseno.md](decisiones_diseno.md).

## 3. Integridad y logica en la base de datos
- Scripts: `db/migrations/002_constraints.sql` a `007_roles.sql`.
- Trazabilidad completa `RN-01` a `RN-15` y guia de ubicacion de reglas: [decisiones_diseno.md](decisiones_diseno.md).
- Pruebas automatizadas en SQL: `db/tests/db_tests.sql`.
- Demostracion de concurrencia: [informe_concurrencia.md](informe_concurrencia.md).

## 4. Carga masiva
- Catalogos reales en CSV: `db/seed/cepas.csv`, `maridajes.csv`, `localidades_mendoza.csv`.
- Script reproducible con semilla fija (`SEED = 2026`): `db/seed/seed.py`.
- Orden topologico de carga: `localidad`, `cepa`, `maridaje` -> `sala_venta`, `finca`, `bodega`, `transportista` -> `empleado`, `parcela`, `vino`, `cliente`, `transportista_localidad` -> `lote_uva`, `composicion_vino`, `vino_maridaje`, `cliente_*` -> `analisis_calidad`, `permiso_exportacion`, `ingreso`, `transferencia` -> `renglon_*`, `comprobante`, `renglon_comprobante`, `stock_*`.
- *(Agregar tabla de conteos, tiempos de `seed.py --benchmark` y resultados de control ejecutados).*

## 5. Indices y rendimiento
- Definicion de indices: `db/migrations/008_indices.sql`.
- Analisis, comparativa `EXPLAIN (ANALYZE, BUFFERS)`, indice descartado y costo de escritura: [informe_rendimiento.md](informe_rendimiento.md).

## 6. Consultas SQL
- `consultas/update.sql` (`U1`–`U6`), `consultas/insert.sql` (`I1`–`I6`), `consultas/delete.sql` (`D1`–`D6`), `consultas/select.sql` (`S1`–`S12`).
- Todas las sentencias de modificacion se validaron dentro de bloques `BEGIN ... ROLLBACK` verificando el impacto de triggers y acciones `ON DELETE CASCADE`.

## 7. API REST y Frontend
- API (`api/`): FastAPI + `psycopg_pool`, SQL parametrizado en `api/app/repositories/`, traduccion de `SQLSTATE` en `api/app/errors.py`, documentacion OpenAPI en `/docs` y 10 pruebas en `api/tests/test_api.py`.
- Front (`front/`): 5 pantallas minimas en React consumiendo la API sin logica de calculo en el cliente.
- *(Adjuntar captura de prueba de inyeccion SQL fallida: `GET /vinos?q=' OR '1'='1' --`).*

## 8. Despliegue en la nube
- **Comparativa de proveedores (completar verificando limites vigentes):**
  - *Opcion A — Railway:* PostgreSQL en red privada interna (puerto no expuesto a internet), despliegue directo desde repo/Docker para API y Front con HTTPS automatico.
  - *Opcion B — Neon (PostgreSQL) + Render (API/Front):* Neon provee Postgres con `sslmode=require` y branching; Render ofrece Web Service Docker y Static Site con HTTPS.
- **Seguridad:** conexion cifrada (`POSTGRES_SSLMODE=require`), credenciales en variables de entorno del proveedor, API conectada con rol `app_rw`, backup con `pg_dump` y restauracion verificada en base nueva.
- *(Completar con URL publica HTTPS, comandos de backup/restore ejecutados y captura de trigger `RN-09` disparado en la nube).*

## 9. Conclusiones
- La separacion estricta de responsabilidades manteniendo reglas de integridad, calculos financieros y control de stock en PostgreSQL garantiza consistencia incluso frente a accesos concurrentes o clientes externos a la API.
