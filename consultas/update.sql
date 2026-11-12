-- ==============================================================================
-- consultas/update.sql
-- Etapa 5: Operaciones de modificacion (U1 a U6).
-- Cada sentencia se prueba dentro de una transaccion con control previo,
-- modificacion, control posterior y ROLLBACK para preservar el dataset.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- U1: Recalcular el total de todos los comprobantes aplicando el descuento que
--     corresponde al tipo de cliente.
-- Estrategia: Usa fn_descuento_cliente() sobre el subtotal bruto acumulado de
--             los renglones de cada comprobante.
-- ------------------------------------------------------------------------------
BEGIN;
SELECT COUNT(*) AS comprobantes_totales, SUM(total) AS suma_total_previa FROM comprobante;

WITH sumas AS (
    SELECT
        c.nro_comprobante,
        COALESCE(SUM(rc.cantidad * rc.precio_unitario), 0.00)::NUMERIC(14,2) AS sub_bruto,
        fn_descuento_cliente(c.id_cliente) AS desc_pct
    FROM comprobante c
    LEFT JOIN renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
    GROUP BY c.nro_comprobante, c.id_cliente
)
UPDATE comprobante c
   SET subtotal  = s.sub_bruto,
       descuento = ROUND(s.sub_bruto * s.desc_pct / 100.0, 2),
       total     = ROUND(s.sub_bruto * (1 - s.desc_pct / 100.0), 2)
  FROM sumas s
 WHERE c.nro_comprobante = s.nro_comprobante;

SELECT COUNT(*) AS comprobantes_totales, SUM(total) AS suma_total_posterior FROM comprobante;
ROLLBACK;

-- ------------------------------------------------------------------------------
-- U2: Aumentar un 20 % el salario de los empleados con mas de 5 anios de antiguedad.
-- Estrategia: Filtra usando fn_antiguedad_anios(fecha_ingreso) >= 5
--             (o fecha_ingreso < CURRENT_DATE - INTERVAL '5 years').
-- ------------------------------------------------------------------------------
BEGIN;
SELECT COUNT(*) AS empleados_afectados, ROUND(AVG(salario), 2) AS salario_promedio_antes
  FROM empleado
 WHERE fecha_ingreso < (CURRENT_DATE - INTERVAL '5 years');

UPDATE empleado
   SET salario = ROUND(salario * 1.20, 2)
 WHERE fecha_ingreso < (CURRENT_DATE - INTERVAL '5 years');

SELECT COUNT(*) AS empleados_afectados, ROUND(AVG(salario), 2) AS salario_promedio_despues
  FROM empleado
 WHERE fecha_ingreso < (CURRENT_DATE - INTERVAL '5 years');
ROLLBACK;

-- ------------------------------------------------------------------------------
-- U3: Incrementar un 13 % el precio de los vinos elaborados por una bodega determinada.
-- Parametro concreto: primera bodega del dataset (cambiar cuit_bodega segun necesidad).
-- Efecto secundario observado: dispara trg_auditoria_precio_vino (RN-13) por cada vino.
-- ------------------------------------------------------------------------------
BEGIN;
SELECT COUNT(*) AS cant_auditorias_previas FROM auditoria_precio;

UPDATE vino
   SET precio = ROUND(precio * 1.13, 2)
 WHERE cuit_bodega = (SELECT cuit FROM bodega ORDER BY cuit LIMIT 1);

SELECT COUNT(*) AS cant_auditorias_posteriores FROM auditoria_precio;
SELECT cod_vino, precio_anterior, precio_nuevo, usuario FROM auditoria_precio ORDER BY id_auditoria DESC LIMIT 5;
ROLLBACK;

-- ------------------------------------------------------------------------------
-- U4: En las salas cuyo dia de cierre es lunes cambiarlo a miercoles y viceversa,
--     en una sola sentencia.
-- Estrategia: Expresion CASE atomica evaluada sobre el valor previo de dia_cierre.
-- ------------------------------------------------------------------------------
BEGIN;
SELECT dia_cierre, COUNT(*) FROM sala_venta WHERE dia_cierre IN ('lunes', 'miercoles') GROUP BY dia_cierre;

UPDATE sala_venta
   SET dia_cierre = CASE dia_cierre
                        WHEN 'lunes'     THEN 'miercoles'::dia_semana
                        WHEN 'miercoles' THEN 'lunes'::dia_semana
                    END
 WHERE dia_cierre IN ('lunes', 'miercoles');

SELECT dia_cierre, COUNT(*) FROM sala_venta WHERE dia_cierre IN ('lunes', 'miercoles') GROUP BY dia_cierre;
ROLLBACK;

-- ------------------------------------------------------------------------------
-- U5: Aplicar un 15 % de descuento de precio a los 10 vinos menos vendidos de toda la red.
-- Estrategia: CTE con LEFT JOIN a renglon_comprobante para incluir tambien vinos con
--             0 ventas; orden ascendente por botellas vendidas LIMIT 10.
--             Dispara trg_auditoria_precio_vino (RN-13).
-- ------------------------------------------------------------------------------
BEGIN;
WITH menos_vendidos AS (
    SELECT v.cod_vino, COALESCE(SUM(rc.cantidad), 0) AS total_vendido
      FROM vino v
      LEFT JOIN renglon_comprobante rc ON rc.cod_vino = v.cod_vino
     GROUP BY v.cod_vino
     ORDER BY total_vendido ASC, v.cod_vino ASC
     LIMIT 10
)
SELECT v.cod_vino, v.nombre, v.precio AS precio_antes, mv.total_vendido
  FROM vino v
  JOIN menos_vendidos mv ON mv.cod_vino = v.cod_vino;

WITH menos_vendidos AS (
    SELECT v.cod_vino
      FROM vino v
      LEFT JOIN renglon_comprobante rc ON rc.cod_vino = v.cod_vino
     GROUP BY v.cod_vino
     ORDER BY COALESCE(SUM(rc.cantidad), 0) ASC, v.cod_vino ASC
     LIMIT 10
)
UPDATE vino v
   SET precio = ROUND(v.precio * 0.85, 2)
  FROM menos_vendidos mv
 WHERE v.cod_vino = mv.cod_vino;

SELECT COUNT(*) AS auditorias_generadas FROM auditoria_precio;
ROLLBACK;

-- ------------------------------------------------------------------------------
-- U6: A los exportadores con mas de 3 permisos de exportacion, subirles el descuento al 35 %.
-- Estrategia: Subconsulta con GROUP BY + HAVING COUNT(*) > 3 sobre permiso_exportacion.
-- ------------------------------------------------------------------------------
BEGIN;
SELECT COUNT(*) AS exportadores_previos_35
  FROM cliente
 WHERE tipo_cliente = 'exportador' AND descuento_pct = 35.00;

UPDATE cliente
   SET descuento_pct = 35.00
 WHERE tipo_cliente = 'exportador'
   AND id_cliente IN (
       SELECT id_exportador
         FROM permiso_exportacion
        GROUP BY id_exportador
       HAVING COUNT(*) > 3
   );

SELECT COUNT(*) AS exportadores_con_35
  FROM cliente
 WHERE tipo_cliente = 'exportador' AND descuento_pct = 35.00;
ROLLBACK;
