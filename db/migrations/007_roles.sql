-- ==============================================================================
-- 007_roles.sql
-- Etapa 2: Roles con privilegios minimos.
--   1. Propietario (current_user / bodegas_owner): dueno del esquema y migraciones.
--   2. app_rw: rol de lectura/escritura usado por la API REST (sin DDL ni DROP).
--   3. app_ro: rol de solo lectura para reportes/BI.
-- NOTA DE SEGURIDAD: No se incluyen contrasenas en el repositorio.
-- Las contrasenas de inicio de sesion se asignan fuera de Git via variables de entorno.
-- ==============================================================================

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_rw') THEN
        CREATE ROLE app_rw NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_ro') THEN
        CREATE ROLE app_ro NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    END IF;
END $$;

-- Permisos para app_rw (API REST)
GRANT USAGE ON SCHEMA public TO app_rw;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_rw;
-- La tabla de auditoria solo se inserta via trigger y se consulta en reportes:
-- impedir alteracion manual de registros historicos por la API
REVOKE UPDATE, DELETE ON TABLE auditoria_precio FROM app_rw;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_rw;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO app_rw;

-- Permisos por defecto para objetos futuros creados por el propietario
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO app_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT EXECUTE ON ROUTINES TO app_rw;

-- Permisos para app_ro (solo lectura / reportes)
GRANT USAGE ON SCHEMA public TO app_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_ro;
GRANT EXECUTE ON FUNCTION fn_stock_sala(INTEGER, INTEGER),
                           fn_descuento_cliente(INTEGER),
                           fn_descuento_base_tipo(tipo_cliente_enum),
                           fn_total_comprobante(INTEGER),
                           fn_antiguedad_anios(DATE),
                           fn_stock_total_vino(INTEGER) TO app_ro;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO app_ro;
