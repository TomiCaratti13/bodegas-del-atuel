-- ==============================================================================
-- 008_indices.sql
-- Etapa 4: Indices disenados a partir de planes EXPLAIN (ANALYZE, BUFFERS).
-- Incluye: compuesto con INCLUDE, parcial, sobre FK, BRIN temporal y de expresion.
-- ==============================================================================

-- 1. Indice compuesto con INCLUDE (cubre filtros por sala + rango de fechas en S8 y S11)
-- Orden: id_sala primero (predicado de igualdad) y fecha segundo (predicado de rango);
-- INCLUDE (total) habilita Index-Only Scan sin ir al heap para sumar montos.
CREATE INDEX IF NOT EXISTS idx_comprobante_sala_fecha
    ON comprobante (id_sala, fecha)
    INCLUDE (total);

-- 2. Indice parcial (solo indexa transferencias no procesadas: subconjunto chico de la tabla)
-- Acelera S5 y consultas de tablero operativo sobre documentos pendientes.
CREATE INDEX IF NOT EXISTS idx_transferencia_pendientes
    ON transferencia (id_sala, fecha_confeccion)
    WHERE estado <> 'procesado';

-- 3. Indice sobre clave foranea (PostgreSQL no indexa FKs automaticamente)
-- Acelera joins y agregaciones por vino en renglon_comprobante (S1, S2, U5).
CREATE INDEX IF NOT EXISTS idx_renglon_comp_vino
    ON renglon_comprobante (cod_vino)
    INCLUDE (cantidad);

-- 4. Indice sobre clave foranea en comprobante (id_cliente)
-- Acelera consultas por cliente (S3, S12, D1, D4).
CREATE INDEX IF NOT EXISTS idx_comprobante_cliente_fecha
    ON comprobante (id_cliente, fecha);

-- 5. Indice BRIN sobre comprobante(fecha)
-- Aprovecha la correlacion fisica temporal de los comprobantes historicos ocupando
-- una fraccion minima de espacio respecto a un B-Tree, ideal para filtros de periodo (S8).
CREATE INDEX IF NOT EXISTS idx_comprobante_fecha_brin
    ON comprobante USING BRIN (fecha);

-- 6. Indice de expresion para busquedas case-insensitive por nombre de vino en el catalogo
CREATE INDEX IF NOT EXISTS idx_vino_nombre_lower
    ON vino (lower(nombre));

-- 7. Indice sobre FK en renglon_transferencia(cod_vino) para S4 (solicitudes de un vino en 15 dias)
CREATE INDEX IF NOT EXISTS idx_renglon_transf_vino
    ON renglon_transferencia (cod_vino);
