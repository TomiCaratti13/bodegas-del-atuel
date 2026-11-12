-- ==============================================================================
-- 006_vistas.sql
-- Etapa 2: Vistas para consultas frecuentes, reportes y ficha completa de vino (S9).
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- Vista 1: Stock consolidado por vino (deposito central + suma de todas las salas)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_stock_total_vino AS
SELECT
    v.cod_vino,
    v.nombre,
    v.tipo,
    v.anada,
    v.volumen_ml,
    v.precio,
    b.razon_social AS bodega,
    COALESCE(sd.cantidad, 0) AS stock_deposito,
    COALESCE(SUM(ss.cantidad), 0)::INTEGER AS stock_salas,
    (COALESCE(sd.cantidad, 0) + COALESCE(SUM(ss.cantidad), 0))::INTEGER AS stock_total
FROM vino v
JOIN bodega b ON b.cuit = v.cuit_bodega
LEFT JOIN stock_deposito sd ON sd.cod_vino = v.cod_vino
LEFT JOIN stock_sala ss ON ss.cod_vino = v.cod_vino
GROUP BY v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml, v.precio, b.razon_social, sd.cantidad;

-- ------------------------------------------------------------------------------
-- Vista 2: Ventas mensuales agrupadas por sala de venta
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_ventas_mensuales_sala AS
SELECT
    sv.id_sala,
    sv.calle || ' ' || sv.numero AS direccion_sala,
    l.nombre AS localidad,
    DATE_TRUNC('month', c.fecha)::DATE AS mes,
    COUNT(c.nro_comprobante) AS cantidad_comprobantes,
    COALESCE(SUM(c.subtotal), 0.00)::NUMERIC(14,2) AS monto_bruto,
    COALESCE(SUM(c.descuento), 0.00)::NUMERIC(14,2) AS monto_descuento,
    COALESCE(SUM(c.total), 0.00)::NUMERIC(14,2) AS monto_neto
FROM sala_venta sv
JOIN localidad l ON l.id_localidad = sv.id_localidad
LEFT JOIN comprobante c ON c.id_sala = sv.id_sala
GROUP BY sv.id_sala, sv.calle, sv.numero, l.nombre, DATE_TRUNC('month', c.fecha)::DATE;

-- ------------------------------------------------------------------------------
-- Vista 3: Documentos pendientes (ingresos y transferencias no procesados)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_documentos_pendientes AS
SELECT
    'ingreso'::TEXT AS tipo_documento,
    i.cod_ingreso AS nro_documento,
    i.fecha AS fecha_documento,
    i.estado,
    b.razon_social AS origen_o_sala,
    t.razon_social AS transportista,
    COUNT(ri.cod_vino) AS cantidad_renglones,
    COALESCE(SUM(ri.cantidad), 0)::INTEGER AS total_botellas
FROM ingreso i
JOIN bodega b ON b.cuit = i.cuit_bodega
JOIN transportista t ON t.cod_transportista = i.cod_transportista
LEFT JOIN renglon_ingreso ri ON ri.cod_ingreso = i.cod_ingreso
WHERE i.estado <> 'procesado'
GROUP BY i.cod_ingreso, i.fecha, i.estado, b.razon_social, t.razon_social
UNION ALL
SELECT
    'transferencia'::TEXT AS tipo_documento,
    tr.nro_solicitud AS nro_documento,
    tr.fecha_confeccion AS fecha_documento,
    tr.estado,
    sv.calle || ' ' || sv.numero || ' (' || l.nombre || ')' AS origen_o_sala,
    NULL::VARCHAR AS transportista,
    COUNT(rt.cod_vino) AS cantidad_renglones,
    COALESCE(SUM(rt.cantidad), 0)::INTEGER AS total_botellas
FROM transferencia tr
JOIN sala_venta sv ON sv.id_sala = tr.id_sala
JOIN localidad l ON l.id_localidad = sv.id_localidad
LEFT JOIN renglon_transferencia rt ON rt.nro_solicitud = tr.nro_solicitud
WHERE tr.estado <> 'procesado'
GROUP BY tr.nro_solicitud, tr.fecha_confeccion, tr.estado, sv.calle, sv.numero, l.nombre;

-- ------------------------------------------------------------------------------
-- Vista 4: Ficha completa de vino (apoya consulta S9 y catalogo de API)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_ficha_vino AS
SELECT
    v.cod_vino,
    v.nombre,
    v.tipo,
    v.anada,
    v.volumen_ml,
    v.graduacion,
    v.precio,
    v.cuit_bodega,
    b.razon_social AS bodega_razon_social,
    COALESCE(
        (SELECT STRING_AGG(ce.nombre || ' (' || cv.porcentaje || '%)', ', ' ORDER BY cv.porcentaje DESC, ce.nombre)
           FROM composicion_vino cv
           JOIN cepa ce ON ce.id_cepa = cv.id_cepa
          WHERE cv.cod_vino = v.cod_vino),
        ''
    ) AS cepas_composicion,
    COALESCE(
        (SELECT STRING_AGG(m.nombre || ' (' || m.temperatura_servicio || ' C)', ', ' ORDER BY m.nombre)
           FROM vino_maridaje vm
           JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
          WHERE vm.cod_vino = v.cod_vino),
        ''
    ) AS maridajes_recomendados,
    fn_stock_total_vino(v.cod_vino) AS stock_total
FROM vino v
JOIN bodega b ON b.cuit = v.cuit_bodega;
