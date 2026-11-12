-- ==============================================================================
-- consultas/insert.sql
-- Etapa 5: Operaciones de insercion (I1 a I6).
-- Cada sentencia se valida dentro de una transaccion con ROLLBACK final.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- I1: Insertar en transportista_localidad una nueva cobertura que vincule
--     General Alvear con el transportista que menos envios haya realizado en el
--     ultimo trimestre.
-- Estrategia: LEFT JOIN sobre transportista filtrando ingresos en los ultimos 3
--             meses desde CURRENT_DATE; ON CONFLICT DO NOTHING evita fallo si ya cubria.
-- ------------------------------------------------------------------------------
BEGIN;
SELECT COUNT(*) AS coberturas_antes FROM transportista_localidad;

INSERT INTO transportista_localidad (cod_transportista, id_localidad)
SELECT
    (SELECT t.cod_transportista
       FROM transportista t
       LEFT JOIN ingreso i
         ON i.cod_transportista = t.cod_transportista
        AND i.fecha >= (CURRENT_DATE - INTERVAL '3 months')
      GROUP BY t.cod_transportista
      ORDER BY COUNT(i.cod_ingreso) ASC, t.cod_transportista ASC
      LIMIT 1),
    (SELECT id_localidad FROM localidad WHERE nombre = 'General Alvear' LIMIT 1)
ON CONFLICT (cod_transportista, id_localidad) DO NOTHING;

SELECT COUNT(*) AS coberturas_despues FROM transportista_localidad;
ROLLBACK;

-- ------------------------------------------------------------------------------
-- I2: Si existe algun vino tinto con graduacion >= 14, crear el maridaje
--     'cordero al disco' y asociarlo a todos los vinos que cumplan esa condicion.
-- Estrategia: INSERT condicionado con WHERE EXISTS + asociacion masiva sobre
--             vino_maridaje.
-- ------------------------------------------------------------------------------
BEGIN;
INSERT INTO maridaje (nombre, temperatura_servicio)
SELECT 'cordero al disco', 17
 WHERE EXISTS (
     SELECT 1 FROM vino WHERE tipo = 'tinto' AND graduacion >= 14.00
 )
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO vino_maridaje (cod_vino, id_maridaje)
SELECT v.cod_vino, m.id_maridaje
  FROM vino v
  JOIN maridaje m ON m.nombre = 'cordero al disco'
 WHERE v.tipo = 'tinto' AND v.graduacion >= 14.00
ON CONFLICT (cod_vino, id_maridaje) DO NOTHING;

SELECT COUNT(*) AS vinos_asociados_cordero
  FROM vino_maridaje vm
  JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
 WHERE m.nombre = 'cordero al disco';
ROLLBACK;

-- ------------------------------------------------------------------------------
-- I3: Crear un nuevo comprobante con tres renglones para un cliente dado, en la
--     sala con ID 1, dentro de una transaccion y usando las funciones de calculo.
-- Estrategia: Se inserta la cabecera y los 3 renglones; los triggers invocan
--             fn_descuento_cliente() y fn_total_comprobante() y descuentan stock_sala.
-- Parametro cliente: cambiar id_cliente = 1 si se desea otro cliente.
-- ------------------------------------------------------------------------------
BEGIN;
WITH nuevo_comp AS (
    INSERT INTO comprobante (id_cliente, id_sala)
    VALUES (1, 1)
    RETURNING nro_comprobante
),
vinos_disp AS (
    SELECT cod_vino
      FROM stock_sala
     WHERE id_sala = 1 AND cantidad >= 1
     ORDER BY cod_vino
     LIMIT 3
)
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
SELECT nc.nro_comprobante, vd.cod_vino, 1, 1, 0, 0
  FROM nuevo_comp nc
  CROSS JOIN vinos_disp vd;

SELECT nro_comprobante, subtotal, descuento, total
  FROM comprobante
 WHERE nro_comprobante = currval(pg_get_serial_sequence('comprobante', 'nro_comprobante'));
ROLLBACK;

-- ------------------------------------------------------------------------------
-- I4: Insertar una nueva bodega.
-- ------------------------------------------------------------------------------
BEGIN;
INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('30799999991', 'Bodega Nueva Valle del Atuel SA', 'Ruta Nacional 143 km 12, San Rafael');

SELECT * FROM bodega WHERE cuit = '30799999991';
ROLLBACK;

-- ------------------------------------------------------------------------------
-- I5: Insertar una nueva sala de venta.
-- Parametro localidad: usa San Rafael (modificable en la subconsulta).
-- ------------------------------------------------------------------------------
BEGIN;
INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad)
VALUES (
    'Av. Hipolito Yrigoyen',
    '1450',
    'domingo',
    (SELECT id_localidad FROM localidad WHERE nombre = 'San Rafael' LIMIT 1)
)
RETURNING *;
ROLLBACK;

-- ------------------------------------------------------------------------------
-- I6: Crear un ingreso en confeccion de 120 botellas de un vino determinado,
--     elaborado por una bodega dada y trasladado por un transportista dado.
-- Estrategia: CTE encadena la insercion de la cabecera en estado 'en_confeccion'
--             y el renglon de 120 botellas en una unica sentencia atomica.
-- Parametro vino/bodega/transportista: toma un vino existente y su bodega real.
-- ------------------------------------------------------------------------------
BEGIN;
WITH datos AS (
    SELECT
        v.cod_vino,
        v.cuit_bodega,
        (SELECT cod_transportista FROM transportista ORDER BY cod_transportista LIMIT 1) AS cod_transp
      FROM vino v
     ORDER BY v.cod_vino
     LIMIT 1
),
nuevo_ing AS (
    INSERT INTO ingreso (estado, cod_transportista, cuit_bodega)
    SELECT 'en_confeccion', d.cod_transp, d.cuit_bodega
      FROM datos d
    RETURNING cod_ingreso
)
INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
SELECT ni.cod_ingreso, d.cod_vino, 120
  FROM nuevo_ing ni
  CROSS JOIN datos d
RETURNING *;
ROLLBACK;
