-- ==============================================================================
-- 004_procedimientos.sql
-- Etapa 2: Procedimientos transaccionales para procesar ingresos y transferencias.
-- Bloquean filas con FOR UPDATE y garantizan atomicidad todo-o-nada (RN-10, RN-11).
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- sp_procesar_ingreso
-- Proposito: Impacta un ingreso 'terminado' en stock_deposito y lo pasa a 'procesado'.
-- Regla: RN-10.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_procesar_ingreso(p_cod_ingreso INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado     estado_documento;
    v_cant_items INTEGER;
BEGIN
    -- Bloquea la cabecera del ingreso para evitar procesamiento concurrente
    SELECT estado
      INTO v_estado
      FROM ingreso
     WHERE cod_ingreso = p_cod_ingreso
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El ingreso % no existe (RN-10)', p_cod_ingreso;
    END IF;

    IF v_estado IS DISTINCT FROM 'terminado' THEN
        RAISE EXCEPTION 'El ingreso % debe estar en estado terminado para procesarse (estado actual: %) (RN-10)',
            p_cod_ingreso, v_estado;
    END IF;

    SELECT COUNT(*)
      INTO v_cant_items
      FROM renglon_ingreso
     WHERE cod_ingreso = p_cod_ingreso;

    IF v_cant_items = 0 THEN
        RAISE EXCEPTION 'El ingreso % no tiene renglones cargados y no puede procesarse (RN-10)',
            p_cod_ingreso;
    END IF;

    -- Marca autorizacion interna de transicion a 'procesado' dentro de la transaccion
    PERFORM set_config('app.procesando_doc', 'true', true);

    -- Impacta en el stock del deposito central (crea la fila si no existia)
    INSERT INTO stock_deposito (cod_vino, cantidad)
    SELECT ri.cod_vino, ri.cantidad
      FROM renglon_ingreso ri
     WHERE ri.cod_ingreso = p_cod_ingreso
     ORDER BY ri.cod_vino
    ON CONFLICT (cod_vino)
    DO UPDATE SET cantidad = stock_deposito.cantidad + EXCLUDED.cantidad;

    UPDATE ingreso
       SET estado = 'procesado'
     WHERE cod_ingreso = p_cod_ingreso;

    PERFORM set_config('app.procesando_doc', 'false', true);
END;
$$;

-- ------------------------------------------------------------------------------
-- sp_procesar_transferencia
-- Proposito: Descuenta del deposito central y suma al stock de la sala solicitante
--            para una transferencia 'terminado', pasandola a 'procesado'.
-- Regla: RN-11.
-- Nota: Verifica existencia y suficiencia en stock_deposito antes de descontar
--       para evitar el caso de filas ausentes sin error.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_procesar_transferencia(p_nro INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado        estado_documento;
    v_id_sala       INTEGER;
    v_cant_items    INTEGER;
    v_vino_faltante INTEGER;
    v_cant_req      INTEGER;
    v_cant_disp     INTEGER;
BEGIN
    -- Bloquea la cabecera de la transferencia
    SELECT estado, id_sala
      INTO v_estado, v_id_sala
      FROM transferencia
     WHERE nro_solicitud = p_nro
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La transferencia % no existe (RN-11)', p_nro;
    END IF;

    IF v_estado IS DISTINCT FROM 'terminado' THEN
        RAISE EXCEPTION 'La transferencia % debe estar en estado terminado para procesarse (estado actual: %) (RN-11)',
            p_nro, v_estado;
    END IF;

    SELECT COUNT(*)
      INTO v_cant_items
      FROM renglon_transferencia
     WHERE nro_solicitud = p_nro;

    IF v_cant_items = 0 THEN
        RAISE EXCEPTION 'La transferencia % no tiene renglones cargados y no puede procesarse (RN-11)',
            p_nro;
    END IF;

    -- Bloquea en orden deterministico las filas de stock_deposito involucradas (evita deadlocks)
    PERFORM 1
       FROM stock_deposito d
       JOIN renglon_transferencia r ON r.cod_vino = d.cod_vino
      WHERE r.nro_solicitud = p_nro
      ORDER BY d.cod_vino
      FOR UPDATE OF d;

    -- Detecta vinos sin fila en stock_deposito o con stock insuficiente
    SELECT r.cod_vino, r.cantidad, COALESCE(d.cantidad, 0)
      INTO v_vino_faltante, v_cant_req, v_cant_disp
      FROM renglon_transferencia r
      LEFT JOIN stock_deposito d ON d.cod_vino = r.cod_vino
     WHERE r.nro_solicitud = p_nro
       AND COALESCE(d.cantidad, 0) < r.cantidad
     ORDER BY r.cod_vino
     LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'Stock insuficiente en deposito central para el vino % (requerido: %, disponible: %) (RN-11)',
            v_vino_faltante, v_cant_req, v_cant_disp;
    END IF;

    PERFORM set_config('app.procesando_doc', 'true', true);

    -- Descuenta del deposito central
    UPDATE stock_deposito d
       SET cantidad = d.cantidad - r.cantidad
      FROM renglon_transferencia r
     WHERE r.nro_solicitud = p_nro
       AND d.cod_vino = r.cod_vino;

    -- Suma al stock de la sala solicitante (crea fila si no existia)
    INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
    SELECT v_id_sala, r.cod_vino, r.cantidad
      FROM renglon_transferencia r
     WHERE r.nro_solicitud = p_nro
     ORDER BY r.cod_vino
    ON CONFLICT (id_sala, cod_vino)
    DO UPDATE SET cantidad = stock_sala.cantidad + EXCLUDED.cantidad;

    UPDATE transferencia
       SET estado = 'procesado'
     WHERE nro_solicitud = p_nro;

    PERFORM set_config('app.procesando_doc', 'false', true);
END;
$$;
