# Bodegas del Atuel — Sistema de Gestion y Distribucion Vitivinicola

Trabajo Practico Integrador · Bases de Datos · Ingenieria en Sistemas (UTN FRSR)

## Arquitectura y Restricciones Clave
- **Base de datos:** PostgreSQL 16 (migraciones SQL escritas a mano en `db/migrations/001` a `008`).
- **Acceso a datos:** SQL directo parametrizado con `psycopg` v3 y `psycopg_pool` (**sin ORM ni query builders**).
- **Regla de oro:** toda la logica de negocio (precios, descuentos, calculo de comprobantes, validacion de stock, auditoria y transiciones de estado) vive en PostgreSQL mediante constraints, funciones, procedimientos y triggers. La API y el front no recalculan importes ni stock.
- **Privilegios minimos:** la API se conecta exclusivamente con el rol `app_rw` (no propietario).

## Requisitos
- Docker y Docker Compose
- Python 3.12+ (para ejecutar `db/seed/seed.py` localmente o en contenedor)

## Levantar todo en local (un solo comando)
```bash
cp .env.example .env
docker compose up --build
```
- Front: http://localhost:8080
- API Swagger / OpenAPI: http://localhost:8000/docs
- Salud API: http://localhost:8000/salud

## Carga masiva de datos (Etapa 3)
```bash
pip install -r db/seed/requirements.txt
# Carga completa local (20.000 clientes, 150.000 comprobantes, ~525.000 renglones)
POSTGRES_HOST=localhost POSTGRES_PASSWORD=dev_owner_change_me python db/seed/seed.py --scale full

# Comparativa fila-a-fila vs COPY
POSTGRES_HOST=localhost POSTGRES_PASSWORD=dev_owner_change_me python db/seed/seed.py --benchmark
```

## Pruebas SQL (Etapa 2) y Pruebas de API (Etapa 6)
```bash
# Pruebas SQL de reglas RN-01 a RN-15
docker compose exec -T db psql -U bodegas_owner -d bodegas_atuel -f /dev/stdin < db/tests/db_tests.sql

# Pruebas automaticas de la API (requiere base cargada)
docker compose exec api pytest -v
```

## Estructura del Repositorio
- `db/migrations/`: `001_esquema.sql` a `008_indices.sql`
- `db/seed/`: catalogos CSV reales y script `seed.py`
- `db/tests/`: `db_tests.sql`
- `consultas/`: `update.sql`, `insert.sql`, `delete.sql`, `select.sql`
- `api/`: API REST FastAPI + `psycopg`
- `front/`: Interfaz React + Vite (5 pantallas minimas)
- `docs/`: DER (`der.dbml`), esquema relacional, diccionario de datos, decisiones e informes
