#!/bin/bash
set -euo pipefail

# Asigna LOGIN y contrasenas desde variables de entorno al inicializar el contenedor.
# De esta forma 007_roles.sql permanece libre de secretos en el repositorio.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v api_pwd="${API_DB_PASSWORD:-dev_app_rw_change_me}" \
  -v ro_pwd="${RO_DB_PASSWORD:-dev_app_ro_change_me}" <<'EOSQL'
ALTER ROLE app_rw WITH LOGIN PASSWORD :'api_pwd';
ALTER ROLE app_ro WITH LOGIN PASSWORD :'ro_pwd';
EOSQL
