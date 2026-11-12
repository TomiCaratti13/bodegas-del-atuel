-- ==============================================================================
-- consultas/select.sql
-- Etapa 5: Consultas de seleccion basicas (S1 a S8) y avanzadas (S9 a S12).
-- Todos los periodos relativos usan CURRENT_DATE.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- S1: Ranking de los 10 vinos con mayor cantidad de botellas vendidas en toda la red.
-- Estrategia: JOIN vino + renglon_comprobante, SUM(cantidad) descendente LIMIT 10.
--             (Candidata para medicion EXPLAIN en Etapa 4).
-- ------------------------------------------------------------------------------
SELECT
    v.cod_vino,
    v.nombre,
    v.tipo,
    v.anada,
    v.volumen_ml,
    SUM(rc.cantidad) AS botellas_vendidas
FROM vino v
JOIN renglon_comprobante rc ON rc.cod_vino = v.cod_vino
GROUP BY v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml
ORDER BY botellas_vendidas DESC, v.cod_vino ASC
LIMIT 10;

-- ------------------------------------------------------------------------------
-- S2: Listar codigos y nombres de los vinos que se vendieron en todas las salas.
-- Estrategia: Division relacional mediante doble NOT EXISTS ("no existe sala en
--             la que no se haya vendido este vino").
-- ------------------------------------------------------------------------------
SELECT v.cod_vino, v.nombre, v.anada, v.volumen_ml
FROM vino v
WHERE NOT EXISTS (
    SELECT 1
      FROM sala_venta sv
     WHERE NOT EXISTS (
         SELECT 1
           FROM comprobante c
           JOIN renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
          WHERE c.id_sala = sv.id_sala
            AND rc.cod_vino = v.cod_vino
     )
)
ORDER BY v.cod_vino;

-- ------------------------------------------------------------------------------
-- S3: Cantidad de clientes de cada tipo que compraron en una sala determinada en
--     la ultima semana.
-- Parametro concreto: id_sala = 1 (modificable).
-- Estrategia: COUNT(DISTINCT cl.id_cliente) agrupado por tipo_cliente en ultimos 7 dias.
-- ------------------------------------------------------------------------------
SELECT
    cl.tipo_cliente,
    COUNT(DISTINCT cl.id_cliente) AS cantidad_clientes
FROM comprobante c
JOIN cliente cl ON cl.id_cliente = c.id_cliente
WHERE c.id_sala = 1
  AND c.fecha >= (CURRENT_DATE - INTERVAL '7 days')
GROUP BY cl.tipo_cliente
ORDER BY cl.tipo_cliente;

-- ------------------------------------------------------------------------------
-- S4: Top 5 de las salas que solicitaron mayor cantidad de un vino determinado
--     mediante transferencias en los ultimos 15 dias.
-- Parametro concreto: cod_vino = 1 (modificable).
-- Estrategia: JOIN transferencia + renglon_transferencia + sala_venta + localidad.
--             (Candidata para medicion EXPLAIN en Etapa 4).
-- ------------------------------------------------------------------------------
SELECT
    sv.id_sala,
    sv.calle || ' ' || sv.numero AS direccion,
    l.nombre AS localidad,
    SUM(rt.cantidad) AS cantidad_solicitada
FROM transferencia t
JOIN renglon_transferencia rt ON rt.nro_solicitud = t.nro_solicitud
JOIN sala_venta sv ON sv.id_sala = t.id_sala
JOIN localidad l ON l.id_localidad = sv.id_localidad
WHERE rt.cod_vino = 1
  AND t.fecha_confeccion >= (CURRENT_DATE - INTERVAL '15 days')
GROUP BY sv.id_sala, sv.calle, sv.numero, l.nombre
ORDER BY cantidad_solicitada DESC, sv.id_sala ASC
LIMIT 5;

-- ------------------------------------------------------------------------------
-- S5: Listado de las salas con menor cantidad de transferencias pendientes (no procesadas).
-- Estrategia: LEFT JOIN a transferencia con filtro estado <> 'procesado' para
--             incluir salas con 0 pendientes; aprovecha idx_transferencia_pendientes.
-- ------------------------------------------------------------------------------
SELECT
    sv.id_sala,
    sv.calle || ' ' || sv.numero AS direccion,
    l.nombre AS localidad,
    COUNT(t.nro_solicitud) AS transferencias_pendientes
FROM sala_venta sv
JOIN localidad l ON l.id_localidad = sv.id_localidad
LEFT JOIN transferencia t
       ON t.id_sala = sv.id_sala
      AND t.estado <> 'procesado'
GROUP BY sv.id_sala, sv.calle, sv.numero, l.nombre
ORDER BY transferencias_pendientes ASC, sv.id_sala ASC;

-- ------------------------------------------------------------------------------
-- S6: Para una sala determinada, los vinos sin stock en la sala pero con stock
--     en el deposito central.
-- Parametro concreto: id_sala = 1 (modificable).
-- ------------------------------------------------------------------------------
SELECT
    v.cod_vino,
    v.nombre,
    v.tipo,
    v.anada,
    v.volumen_ml,
    sd.cantidad AS stock_deposito,
    COALESCE(ss.cantidad, 0) AS stock_sala
FROM vino v
JOIN stock_deposito sd ON sd.cod_vino = v.cod_vino
LEFT JOIN stock_sala ss
       ON ss.cod_vino = v.cod_vino
      AND ss.id_sala = 1
WHERE sd.cantidad > 0
  AND COALESCE(ss.cantidad, 0) = 0
ORDER BY sd.cantidad DESC, v.cod_vino ASC;

-- ------------------------------------------------------------------------------
-- S7: Cual es la empresa de transporte con mayor actividad en el ultimo mes?
-- Estrategia: Cuenta ingresos trasladados en el ultimo mes (y total de botellas)
--             desde CURRENT_DATE.
-- ------------------------------------------------------------------------------
SELECT
    tr.cod_transportista,
    tr.razon_social,
    COUNT(DISTINCT i.cod_ingreso) AS cantidad_ingresos,
    COALESCE(SUM(ri.cantidad), 0) AS botellas_trasladadas
FROM transportista tr
JOIN ingreso i ON i.cod_transportista = tr.cod_transportista
LEFT JOIN renglon_ingreso ri ON ri.cod_ingreso = i.cod_ingreso
WHERE i.fecha >= (CURRENT_DATE - INTERVAL '1 month')
GROUP BY tr.cod_transportista, tr.razon_social
ORDER BY cantidad_ingresos DESC, botellas_trasladadas DESC
LIMIT 1;

-- ------------------------------------------------------------------------------
-- S8: Monto total de ventas por sala en el ultimo trimestre, en orden descendente.
-- Estrategia: Filtra comprobantes del ultimo trimestre y agrega SUM(total);
--             aprovecha idx_comprobante_sala_fecha INCLUDE (total) (Etapa 4).
-- ------------------------------------------------------------------------------
SELECT
    sv.id_sala,
    sv.calle || ' ' || sv.numero AS direccion,
    l.nombre AS localidad,
    COUNT(c.nro_comprobante) AS cantidad_ventas,
    COALESCE(SUM(c.total), 0.00)::NUMERIC(14,2) AS monto_total
FROM sala_venta sv
JOIN localidad l ON l.id_localidad = sv.id_localidad
LEFT JOIN comprobante c
       ON c.id_sala = sv.id_sala
      AND c.fecha >= (CURRENT_DATE - INTERVAL '3 months')
GROUP BY sv.id_sala, sv.calle, sv.numero, l.nombre
ORDER BY monto_total DESC;

-- ------------------------------------------------------------------------------
-- S9 (Avanzada): Ficha de un vino: cepas con sus porcentajes, bodega elaboradora,
--                maridajes y stock total (deposito mas salas).
-- Herramienta esperada: Joins, agregacion y vista (vw_ficha_vino).
-- Parametro concreto: cod_vino = 1 (modificable).
-- ------------------------------------------------------------------------------
SELECT
    cod_vino,
    nombre,
    tipo,
    anada,
    volumen_ml,
    graduacion,
    precio,
    bodega_razon_social,
    cepas_composicion,
    maridajes_recomendados,
    stock_total
FROM vw_ficha_vino
WHERE cod_vino = 1;

-- ------------------------------------------------------------------------------
-- S10 (Avanzada): Rendimiento en kg por hectarea de cada parcela y campana,
--                 e identificar las parcelas que rinden menos que el promedio de su finca.
-- Herramienta esperada: CTE + subconsulta correlacionada.
-- ------------------------------------------------------------------------------
WITH rendimiento_parcela AS (
    SELECT
        f.id_finca,
        f.nombre AS finca,
        p.nro_parcela,
        lu.campana,
        p.superficie_ha,
        lu.kg_cosechados,
        ROUND(lu.kg_cosechados / p.superficie_ha, 2) AS kg_por_ha
    FROM lote_uva lu
    JOIN parcela p
      ON p.id_finca = lu.id_finca
     AND p.nro_parcela = lu.nro_parcela
    JOIN finca f ON f.id_finca = p.id_finca
)
SELECT
    rp.id_finca,
    rp.finca,
    rp.nro_parcela,
    rp.campana,
    rp.kg_por_ha,
    (SELECT ROUND(AVG(rp2.kg_por_ha), 2)
       FROM rendimiento_parcela rp2
      WHERE rp2.id_finca = rp.id_finca) AS promedio_finca_kg_ha,
    CASE
        WHEN rp.kg_por_ha < (
            SELECT AVG(rp2.kg_por_ha)
              FROM rendimiento_parcela rp2
             WHERE rp2.id_finca = rp.id_finca
        ) THEN 'Por debajo del promedio'
        ELSE 'En o sobre el promedio'
    END AS evaluacion_rendimiento
FROM rendimiento_parcela rp
ORDER BY rp.id_finca, rp.campana DESC, rp.kg_por_ha ASC;

-- ------------------------------------------------------------------------------
-- S11 (Avanzada): Ranking de vinos dentro de cada sala por botellas vendidas y
--                 ventas acumuladas mensuales por sala.
-- Herramienta esperada: RANK() OVER (PARTITION BY ...) y suma acumulada con ventana.
-- ------------------------------------------------------------------------------
-- Parte A: Ranking de vinos dentro de cada sala por botellas vendidas
WITH ventas_vino_sala AS (
    SELECT
        c.id_sala,
        rc.cod_vino,
        v.nombre AS vino,
        SUM(rc.cantidad) AS botellas_vendidas
    FROM comprobante c
    JOIN renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
    JOIN vino v ON v.cod_vino = rc.cod_vino
    GROUP BY c.id_sala, rc.cod_vino, v.nombre
)
SELECT
    id_sala,
    cod_vino,
    vino,
    botellas_vendidas,
    RANK() OVER (PARTITION BY id_sala ORDER BY botellas_vendidas DESC) AS ranking_en_sala
FROM ventas_vino_sala
ORDER BY id_sala, ranking_en_sala, cod_vino;

-- Parte B: Ventas acumuladas mensuales por sala (running total)
WITH ventas_mes_sala AS (
    SELECT
        id_sala,
        DATE_TRUNC('month', fecha)::DATE AS mes,
        SUM(total)::NUMERIC(14,2) AS venta_mensual
    FROM comprobante
    GROUP BY id_sala, DATE_TRUNC('month', fecha)::DATE
)
SELECT
    id_sala,
    mes,
    venta_mensual,
    SUM(venta_mensual) OVER (
        PARTITION BY id_sala
        ORDER BY mes ASC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )::NUMERIC(14,2) AS venta_acumulada
FROM ventas_mes_sala
ORDER BY id_sala, mes;

-- ------------------------------------------------------------------------------
-- S12 (Avanzada): Clientes que compraron todos los vinos de una bodega determinada,
--                 y clientes que nunca compraron ningun vino tinto.
-- Herramienta esperada: NOT EXISTS (division) y anti-join.
-- Parametro concreto: primera bodega del dataset (modificable).
-- ------------------------------------------------------------------------------
-- Parte A: Clientes que compraron TODOS los vinos de la bodega seleccionada (division)
WITH bodega_obj AS (
    SELECT cuit FROM bodega ORDER BY cuit LIMIT 1
)
SELECT cl.id_cliente, cl.nombre_razon_social, cl.tipo_cliente
FROM cliente cl
WHERE EXISTS (SELECT 1 FROM vino v JOIN bodega_obj bo ON bo.cuit = v.cuit_bodega)
  AND NOT EXISTS (
      SELECT 1
        FROM vino v
        JOIN bodega_obj bo ON bo.cuit = v.cuit_bodega
       WHERE NOT EXISTS (
           SELECT 1
             FROM comprobante c
             JOIN renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
            WHERE c.id_cliente = cl.id_cliente
              AND rc.cod_vino = v.cod_vino
       )
  )
ORDER BY cl.id_cliente;

-- Parte B: Clientes que NUNCA compraron ningun vino tinto (anti-join con LEFT JOIN)
WITH compradores_tinto AS (
    SELECT DISTINCT c.id_cliente
      FROM comprobante c
      JOIN renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
      JOIN vino v ON v.cod_vino = rc.cod_vino
     WHERE v.tipo = 'tinto'
)
SELECT cl.id_cliente, cl.nombre_razon_social, cl.tipo_cliente
FROM cliente cl
LEFT JOIN compradores_tinto ct ON ct.id_cliente = cl.id_cliente
WHERE ct.id_cliente IS NULL
ORDER BY cl.id_cliente
LIMIT 50;
