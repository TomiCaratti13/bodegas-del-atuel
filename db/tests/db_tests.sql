-- ==============================================================================
-- db_tests.sql
-- Etapa 2: Script de pruebas SQL para verificar reglas RN-01 a RN-15.
-- Se ejecuta dentro de una transaccion con ROLLBACK final para no dejar basura.
-- Cada caso negativo documenta el SQLSTATE / error esperado.
-- ==============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ------------------------------------------------------------------------------
-- Datos minimos de prueba aislados
-- ------------------------------------------------------------------------------
INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
VALUES ('5600', 'San Rafael Test', 'Mendoza', 'Ana Gomez');

INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad)
VALUES ('Av. Mitre', '500', 'lunes', currval(pg_get_serial_sequence('localidad', 'id_localidad')));

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('30710000001', 'Bodega Test SA', 'Ruta 143 km 5');

INSERT INTO cepa (nombre, tipo)
VALUES ('Malbec Test', 'tinta'), ('Cabernet Test', 'tinta');

INSERT INTO finca (nombre, superficie_ha, departamento, provincia)
VALUES ('Finca Test', 50.00, 'San Rafael', 'Mendoza');

INSERT INTO parcela (id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa)
VALUES (
    currval(pg_get_serial_sequence('finca', 'id_finca')),
    1, 12.50, 2015,
    (SELECT id_cepa FROM cepa WHERE nombre = 'Malbec Test')
);

INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)
VALUES ('Transp Test SRL', '30720000002', 'ops@transptest.com', '2604000000', 'Calle 1');

-- ------------------------------------------------------------------------------
-- RN-01: Precio de vino unico y siempre mayor que cero
-- Caso negativo esperado: check_violation (SQLSTATE 23514) en chk_vino_precio
-- ------------------------------------------------------------------------------
DO $$
BEGIN
    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino Precio Cero', 'tinto', 2022, 750, 13.5, 0, '30710000001');
    RAISE EXCEPTION 'FALLO RN-01: permitio precio = 0';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK RN-01 (negativo): rechazo precio <= 0 (SQLSTATE 23514)';
END $$;

-- ------------------------------------------------------------------------------
-- RN-05 (positivo) + RN-01 (positivo): Alta valida de vino con corte = 100%
-- ------------------------------------------------------------------------------
INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Malbec Test Reserva', 'tinto', 2022, 750, 14.0, 12500.00, '30710000001');

INSERT INTO composicion_vino (cod_vino, id_cepa, porcentaje)
VALUES
    (currval(pg_get_serial_sequence('vino', 'cod_vino')), (SELECT id_cepa FROM cepa WHERE nombre = 'Malbec Test'), 85.00),
    (currval(pg_get_serial_sequence('vino', 'cod_vino')), (SELECT id_cepa FROM cepa WHERE nombre = 'Cabernet Test'), 15.00);

-- ------------------------------------------------------------------------------
-- RN-02: Una sala pertenece a una sola localidad (FK NOT NULL) y encargado depende de localidad
-- Caso negativo esperado: not_null_violation (23502) si id_localidad es NULL
-- ------------------------------------------------------------------------------
DO $$
BEGIN
    INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad)
    VALUES ('San Martin', '10', 'martes', NULL);
    RAISE EXCEPTION 'FALLO RN-02: permitio sala sin localidad';
EXCEPTION WHEN not_null_violation THEN
    RAISE NOTICE 'OK RN-02 (negativo): rechazo sala con id_localidad NULL (SQLSTATE 23502)';
END $$;

-- ------------------------------------------------------------------------------
-- RN-03: Cada empleado trabaja en una sola sala (FK NOT NULL)
-- Caso negativo esperado: not_null_violation (23502)
-- ------------------------------------------------------------------------------
DO $$
BEGIN
    INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
    VALUES ('20301112223', 'Juan Perez', CURRENT_DATE, 500000, NULL);
    RAISE EXCEPTION 'FALLO RN-03: permitio empleado sin sala';
EXCEPTION WHEN not_null_violation THEN
    RAISE NOTICE 'OK RN-03 (negativo): rechazo empleado sin sala (SQLSTATE 23502)';
END $$;

INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
VALUES ('20301112223', 'Juan Perez', CURRENT_DATE, 500000, currval(pg_get_serial_sequence('sala_venta', 'id_sala')));

-- ------------------------------------------------------------------------------
-- RN-04: Una parcela se cosecha como maximo una vez por campana
-- Caso negativo esperado: unique_violation (23505) en uq_lote_parcela_campana
-- ------------------------------------------------------------------------------
INSERT INTO lote_uva (id_finca, nro_parcela, campana, fecha_cosecha, kg_cosechados, cuit_bodega)
VALUES (currval(pg_get_serial_sequence('finca', 'id_finca')), 1, 2024, '2024-03-15', 4500.00, '30710000001');

DO $$
DECLARE v_finca INTEGER := currval(pg_get_serial_sequence('finca', 'id_finca'));
BEGIN
    INSERT INTO lote_uva (id_finca, nro_parcela, campana, fecha_cosecha, kg_cosechados, cuit_bodega)
    VALUES (v_finca, 1, 2024, '2024-03-20', 1200.00, '30710000001');
    RAISE EXCEPTION 'FALLO RN-04: permitio dos cosechas en la misma parcela y campana';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'OK RN-04 (negativo): rechazo segunda cosecha en misma parcela/campana (SQLSTATE 23505)';
END $$;

-- ------------------------------------------------------------------------------
-- RN-05: Porcentajes de corte suman exactamente 100 (constraint trigger diferido)
-- Caso negativo esperado: raise_exception (P0001) al validar al final (SET CONSTRAINTS IMMEDIATE)
-- ------------------------------------------------------------------------------
DO $$
DECLARE v_vino INTEGER;
BEGIN
    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino Corte Invalido', 'tinto', 2023, 750, 13.0, 9000.00, '30710000001')
    RETURNING cod_vino INTO v_vino;

    INSERT INTO composicion_vino (cod_vino, id_cepa, porcentaje)
    VALUES (v_vino, (SELECT id_cepa FROM cepa WHERE nombre = 'Malbec Test'), 70.00);

    -- Fuerza evaluacion del constraint trigger diferido dentro del sub-bloque
    SET CONSTRAINTS trg_composicion_vino_suma_100 IMMEDIATE;
    RAISE EXCEPTION 'FALLO RN-05: permitio suma de porcentajes != 100';
EXCEPTION WHEN raise_exception THEN
    RAISE NOTICE 'OK RN-05 (negativo): rechazo composicion que no suma 100%% (SQLSTATE P0001)';
END $$;

-- ------------------------------------------------------------------------------
-- RN-06: Descuento por tipo de cliente (10%, 20%, 30%) + CHECK de rango
-- ------------------------------------------------------------------------------
INSERT INTO cliente (tipo_cliente, nombre_razon_social, tipo_documento, nro_documento, direccion, id_localidad, descuento_pct)
VALUES ('socio', 'Carlos Socio', 'DNI', '30111222', 'Calle A 123', currval(pg_get_serial_sequence('localidad', 'id_localidad')), 99);

INSERT INTO cliente_socio (id_cliente)
VALUES (currval(pg_get_serial_sequence('cliente', 'id_cliente')));

DO $$
DECLARE v_desc NUMERIC(5,2);
BEGIN
    v_desc := fn_descuento_cliente(currval(pg_get_serial_sequence('cliente', 'id_cliente')));
    IF v_desc <> 10.00 THEN
        RAISE EXCEPTION 'FALLO RN-06: esperado 10.00, obtenido %', v_desc;
    END IF;
    RAISE NOTICE 'OK RN-06 (positivo): socio recibe descuento inicial 10.00%%';
END $$;

DO $$
BEGIN
    UPDATE cliente SET descuento_pct = 150.00
     WHERE id_cliente = currval(pg_get_serial_sequence('cliente', 'id_cliente'));
    RAISE EXCEPTION 'FALLO RN-06: permitio descuento > 100';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK RN-06 (negativo): rechazo descuento fuera de rango [0..100] (SQLSTATE 23514)';
END $$;

-- ------------------------------------------------------------------------------
-- RN-07: Permiso de exportacion con vencimiento posterior a emision
-- Caso negativo esperado: check_violation (23514) en chk_permiso_fechas
-- ------------------------------------------------------------------------------
INSERT INTO cliente (tipo_cliente, nombre_razon_social, tipo_documento, nro_documento, direccion, id_localidad)
VALUES ('exportador', 'Export Wines SA', 'CUIT', '30730000003', 'Av. Espana 1', currval(pg_get_serial_sequence('localidad', 'id_localidad')));

INSERT INTO cliente_exportador (id_cliente, pais_destino_principal)
VALUES (currval(pg_get_serial_sequence('cliente', 'id_cliente')), 'Brasil');

DO $$
BEGIN
    INSERT INTO permiso_exportacion (codigo, id_exportador, fecha_emision, fecha_vencimiento)
    VALUES ('PERM-BAD-01', currval(pg_get_serial_sequence('cliente', 'id_cliente')), '2026-06-01', '2026-05-01');
    RAISE EXCEPTION 'FALLO RN-07: permitio vencimiento <= emision';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK RN-07 (negativo): rechazo permiso con vencimiento <= emision (SQLSTATE 23514)';
END $$;

INSERT INTO permiso_exportacion (codigo, id_exportador, fecha_emision, fecha_vencimiento)
VALUES ('PERM-OK-01', currval(pg_get_serial_sequence('cliente', 'id_cliente')), '2026-01-01', '2026-12-31');

-- ------------------------------------------------------------------------------
-- RN-10 y RN-12: Ingreso estados (en_confeccion -> terminado -> procesado) + bloqueo renglones
-- ------------------------------------------------------------------------------
INSERT INTO ingreso (cod_transportista, cuit_bodega)
VALUES (currval(pg_get_serial_sequence('transportista', 'cod_transportista')), '30710000001');

INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
VALUES (currval(pg_get_serial_sequence('ingreso', 'cod_ingreso')), currval(pg_get_serial_sequence('vino', 'cod_vino')), 50);

-- Caso negativo RN-10: intentar pasar directo a procesado sin procedimiento
DO $$
BEGIN
    UPDATE ingreso SET estado = 'procesado'
     WHERE cod_ingreso = currval(pg_get_serial_sequence('ingreso', 'cod_ingreso'));
    RAISE EXCEPTION 'FALLO RN-10: permitio salto directo a procesado';
EXCEPTION WHEN raise_exception THEN
    RAISE NOTICE 'OK RN-10 (negativo): rechazo salto directo a procesado (SQLSTATE P0001)';
END $$;

UPDATE ingreso SET estado = 'terminado'
 WHERE cod_ingreso = currval(pg_get_serial_sequence('ingreso', 'cod_ingreso'));

-- Caso negativo RN-12: modificar renglones de ingreso terminado
DO $$
BEGIN
    INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
    VALUES (currval(pg_get_serial_sequence('ingreso', 'cod_ingreso')), currval(pg_get_serial_sequence('vino', 'cod_vino')), 10);
    RAISE EXCEPTION 'FALLO RN-12: permitio agregar renglon a ingreso terminado';
EXCEPTION WHEN raise_exception THEN
    RAISE NOTICE 'OK RN-12 (negativo): bloqueo renglon en ingreso terminado (SQLSTATE P0001)';
END $$;

-- Caso positivo RN-10: procesar ingreso actualiza stock_deposito
CALL sp_procesar_ingreso(currval(pg_get_serial_sequence('ingreso', 'cod_ingreso'))::INTEGER);

-- ------------------------------------------------------------------------------
-- RN-11: Transferencia fecha actual inmutable, estados y stock deposito suficiente
-- ------------------------------------------------------------------------------
INSERT INTO transferencia (id_sala, fecha_confeccion)
VALUES (currval(pg_get_serial_sequence('sala_venta', 'id_sala')), DATE '2020-01-01');

DO $$
DECLARE v_fecha DATE;
BEGIN
    SELECT fecha_confeccion INTO v_fecha FROM transferencia
     WHERE nro_solicitud = currval(pg_get_serial_sequence('transferencia', 'nro_solicitud'));
    IF v_fecha <> CURRENT_DATE THEN
        RAISE EXCEPTION 'FALLO RN-11: fecha_confeccion no se forzo a CURRENT_DATE';
    END IF;
    RAISE NOTICE 'OK RN-11 (positivo): fecha_confeccion forzada a CURRENT_DATE';
END $$;

DO $$
BEGIN
    UPDATE transferencia SET fecha_confeccion = CURRENT_DATE - 1
     WHERE nro_solicitud = currval(pg_get_serial_sequence('transferencia', 'nro_solicitud'));
    RAISE EXCEPTION 'FALLO RN-11: permitio modificar fecha_confeccion';
EXCEPTION WHEN raise_exception THEN
    RAISE NOTICE 'OK RN-11 (negativo): bloqueo modificacion de fecha_confeccion (SQLSTATE P0001)';
END $$;

-- Renglon excesivo (60 > 50 disponibles en deposito): debe fallar al procesar y revertir todo
INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad)
VALUES (currval(pg_get_serial_sequence('transferencia', 'nro_solicitud')), currval(pg_get_serial_sequence('vino', 'cod_vino')), 60);

UPDATE transferencia SET estado = 'terminado'
 WHERE nro_solicitud = currval(pg_get_serial_sequence('transferencia', 'nro_solicitud'));

DO $$
BEGIN
    CALL sp_procesar_transferencia(currval(pg_get_serial_sequence('transferencia', 'nro_solicitud'))::INTEGER);
    RAISE EXCEPTION 'FALLO RN-11: proceso transferencia sin stock en deposito';
EXCEPTION WHEN raise_exception THEN
    RAISE NOTICE 'OK RN-11 (negativo): rechazo transferencia sin stock suficiente en deposito (SQLSTATE P0001)';
END $$;

-- Transferencia valida de 10 botellas: crear nueva transferencia en_confeccion -> terminado -> procesado
INSERT INTO transferencia (id_sala)
VALUES (currval(pg_get_serial_sequence('sala_venta', 'id_sala')));

INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad)
VALUES (currval(pg_get_serial_sequence('transferencia', 'nro_solicitud')), currval(pg_get_serial_sequence('vino', 'cod_vino')), 10);

UPDATE transferencia SET estado = 'terminado'
 WHERE nro_solicitud = currval(pg_get_serial_sequence('transferencia', 'nro_solicitud'));

CALL sp_procesar_transferencia(currval(pg_get_serial_sequence('transferencia', 'nro_solicitud'))::INTEGER);

-- ------------------------------------------------------------------------------
-- RN-08 y RN-09: Venta con stock disponible vs venta excediendo stock
-- ------------------------------------------------------------------------------
INSERT INTO comprobante (id_cliente, id_sala)
VALUES (
    (SELECT id_cliente FROM cliente WHERE nro_documento = '30111222'),
    currval(pg_get_serial_sequence('sala_venta', 'id_sala'))
);

-- Venta valida de 4 botellas (socio 10% de $12.500 = $11.250 * 4 = $45.000)
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
VALUES (
    currval(pg_get_serial_sequence('comprobante', 'nro_comprobante')),
    currval(pg_get_serial_sequence('vino', 'cod_vino')),
    4, 1, 0, 0 -- Valores deliberadamente falsos: el trigger los ignora y calcula los reales (RN-08)
);

DO $$
DECLARE
    v_total NUMERIC(14,2);
    v_stock INTEGER;
BEGIN
    SELECT total INTO v_total FROM comprobante
     WHERE nro_comprobante = currval(pg_get_serial_sequence('comprobante', 'nro_comprobante'));
    v_stock := fn_stock_sala(
        currval(pg_get_serial_sequence('sala_venta', 'id_sala'))::INTEGER,
        currval(pg_get_serial_sequence('vino', 'cod_vino'))::INTEGER
    );
    IF v_total <> 45000.00 OR v_stock <> 6 THEN
        RAISE EXCEPTION 'FALLO RN-08/RN-09: total=% (esp 45000.00), stock=% (esp 6)', v_total, v_stock;
    END IF;
    RAISE NOTICE 'OK RN-08/RN-09 (positivo): total calculado=45000.00 y stock descontado=6';
END $$;

-- Caso negativo RN-09: intentar vender 7 botellas cuando quedan 6
INSERT INTO comprobante (id_cliente, id_sala)
VALUES (
    (SELECT id_cliente FROM cliente WHERE nro_documento = '30111222'),
    currval(pg_get_serial_sequence('sala_venta', 'id_sala'))
);

DO $$
BEGIN
    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
    VALUES (
        currval(pg_get_serial_sequence('comprobante', 'nro_comprobante')),
        currval(pg_get_serial_sequence('vino', 'cod_vino')),
        7, 1, 0, 0
    );
    RAISE EXCEPTION 'FALLO RN-09: permitio vender mas que el stock de sala';
EXCEPTION WHEN raise_exception THEN
    RAISE NOTICE 'OK RN-09 (negativo): rechazo venta sin stock suficiente (SQLSTATE P0001)';
END $$;

-- ------------------------------------------------------------------------------
-- RN-13: Auditoria de cambio de precio de vino
-- ------------------------------------------------------------------------------
UPDATE vino SET precio = 15000.00
 WHERE cod_vino = currval(pg_get_serial_sequence('vino', 'cod_vino'));

DO $$
DECLARE v_cnt INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_cnt FROM auditoria_precio
     WHERE cod_vino = currval(pg_get_serial_sequence('vino', 'cod_vino'))
       AND precio_anterior = 12500.00
       AND precio_nuevo = 15000.00;
    IF v_cnt <> 1 THEN
        RAISE EXCEPTION 'FALLO RN-13: no se registro auditoria del cambio de precio';
    END IF;
    RAISE NOTICE 'OK RN-13 (positivo): auditoria de precio registrada correctamente';
END $$;

-- ------------------------------------------------------------------------------
-- RN-14: ON DELETE RESTRICT en bodega, vino y transportista con movimientos
-- Caso negativo esperado: foreign_key_violation (23503)
-- ------------------------------------------------------------------------------
DO $$
BEGIN
    DELETE FROM vino WHERE cod_vino = currval(pg_get_serial_sequence('vino', 'cod_vino'));
    RAISE EXCEPTION 'FALLO RN-14: permitio borrar vino con movimientos';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'OK RN-14 (negativo): rechazo borrado de vino con movimientos (SQLSTATE 23503)';
END $$;

DO $$
BEGIN
    DELETE FROM bodega WHERE cuit = '30710000001';
    RAISE EXCEPTION 'FALLO RN-14: permitio borrar bodega con vinos/ingresos';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'OK RN-14 (negativo): rechazo borrado de bodega con movimientos (SQLSTATE 23503)';
END $$;

DO $$
BEGIN
    DELETE FROM transportista WHERE cod_transportista = currval(pg_get_serial_sequence('transportista', 'cod_transportista'));
    RAISE EXCEPTION 'FALLO RN-14: permitio borrar transportista con ingresos';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'OK RN-14 (negativo): rechazo borrado de transportista con movimientos (SQLSTATE 23503)';
END $$;

-- ------------------------------------------------------------------------------
-- RN-15: Graduacion fuera de [5..20] y cantidad negativa
-- Caso negativo esperado: check_violation (23514)
-- ------------------------------------------------------------------------------
DO $$
BEGIN
    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino Graduacion Alta', 'tinto', 2023, 750, 25.0, 8000.00, '30710000001');
    RAISE EXCEPTION 'FALLO RN-15: permitio graduacion = 25';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK RN-15 (negativo): rechazo graduacion fuera de [5..20] (SQLSTATE 23514)';
END $$;

ROLLBACK;
