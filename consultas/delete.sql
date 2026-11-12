-- ==============================================================================
-- consultas/delete.sql
-- Etapa 5: Operaciones de borrado (D1 a D6).
-- Cada borrado se prueba en transaccion con conteo previo/posterior y ROLLBACK.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- D1: Borrar los comprobantes con mas de 5 anios de antiguedad asociados a
--     clientes socios del club.
-- Efecto observado: ON DELETE CASCADE elimina automaticamente sus renglones en
--                   renglon_comprobante.
-- ------------------------------------------------------------------------------
BEGIN;
SELECT COUNT(*) AS comprobantes_a_borrar
  FROM comprobante c
  JOIN cliente cl ON cl.id_cliente = c.id_cliente
 WHERE cl.tipo_cliente = 'socio'
   AND c.fecha < (CURRENT_DATE - INTERVAL '5 years');

DELETE FROM comprobante c
 USING cliente cl
 WHERE c.id_cliente = cl.id_cliente
   AND cl.tipo_cliente = 'socio'
   AND c.fecha < (CURRENT_DATE - INTERVAL '5 years');

SELECT COUNT(*) AS comprobantes_restantes_criterio
  FROM comprobante c
  JOIN cliente cl ON cl.id_cliente = c.id_cliente
 WHERE cl.tipo_cliente = 'socio'
   AND c.fecha < (CURRENT_DATE - INTERVAL '5 years');
ROLLBACK;

-- ------------------------------------------------------------------------------
-- D2: Eliminar las cepas que no componen ningun vino ni estan plantadas en ninguna parcela.
-- Estrategia: Anti-join con NOT EXISTS en composicion_vino y parcela.
-- ------------------------------------------------------------------------------
BEGIN;
SELECT COUNT(*) AS cepas_sin_uso
  FROM cepa c
 WHERE NOT EXISTS (SELECT 1 FROM composicion_vino cv WHERE cv.id_cepa = c.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id_cepa);

DELETE FROM cepa c
 WHERE NOT EXISTS (SELECT 1 FROM composicion_vino cv WHERE cv.id_cepa = c.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id_cepa);

SELECT COUNT(*) AS cepas_totales_despues FROM cepa;
ROLLBACK;

-- ------------------------------------------------------------------------------
-- D3: La sala de una localidad determinada fue dada de baja: eliminar los empleados
--     de esa sala que trabajaron menos de dos anios.
-- Parametro concreto: primera sala ubicada en 'San Rafael' (modificable).
-- ------------------------------------------------------------------------------
BEGIN;
SELECT COUNT(*) AS empleados_a_eliminar
  FROM empleado e
  JOIN sala_venta sv ON sv.id_sala = e.id_sala
  JOIN localidad l ON l.id_localidad = sv.id_localidad
 WHERE l.nombre = 'San Rafael'
   AND e.fecha_ingreso > (CURRENT_DATE - INTERVAL '2 years');

DELETE FROM empleado e
 USING sala_venta sv, localidad l
 WHERE e.id_sala = sv.id_sala
   AND sv.id_localidad = l.id_localidad
   AND l.nombre = 'San Rafael'
   AND e.fecha_ingreso > (CURRENT_DATE - INTERVAL '2 years');

SELECT COUNT(*) AS empleados_restantes_criterio
  FROM empleado e
  JOIN sala_venta sv ON sv.id_sala = e.id_sala
  JOIN localidad l ON l.id_localidad = sv.id_localidad
 WHERE l.nombre = 'San Rafael'
   AND e.fecha_ingreso > (CURRENT_DATE - INTERVAL '2 years');
ROLLBACK;

-- ------------------------------------------------------------------------------
-- D4: Borrar los clientes socios que nunca compraron y se dieron de alta hace mas de 5 anios.
-- Efecto observado: ON DELETE CASCADE limpia su fila en cliente_socio sin violar
--                   ON DELETE RESTRICT de comprobante porque no tienen compras.
-- ------------------------------------------------------------------------------
BEGIN;
SELECT COUNT(*) AS socios_inactivos_a_borrar
  FROM cliente cl
 WHERE cl.tipo_cliente = 'socio'
   AND cl.fecha_alta < (CURRENT_DATE - INTERVAL '5 years')
   AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente);

DELETE FROM cliente cl
 WHERE cl.tipo_cliente = 'socio'
   AND cl.fecha_alta < (CURRENT_DATE - INTERVAL '5 years')
   AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente);

SELECT COUNT(*) AS socios_inactivos_restantes
  FROM cliente cl
 WHERE cl.tipo_cliente = 'socio'
   AND cl.fecha_alta < (CURRENT_DATE - INTERVAL '5 years')
   AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente);
ROLLBACK;

-- ------------------------------------------------------------------------------
-- D5: Eliminar los ingresos en estado procesado de hace mas de 365 dias.
-- Efecto observado: ON DELETE CASCADE borra renglon_ingreso; el trigger de bloqueo
--                   RN-12 detecta que la cabecera ya fue eliminada y permite la cascada.
-- ------------------------------------------------------------------------------
BEGIN;
SELECT COUNT(*) AS ingresos_antiguos_a_borrar
  FROM ingreso
 WHERE estado = 'procesado'
   AND fecha < (CURRENT_DATE - 365);

DELETE FROM ingreso
 WHERE estado = 'procesado'
   AND fecha < (CURRENT_DATE - 365);

SELECT COUNT(*) AS ingresos_antiguos_restantes
  FROM ingreso
 WHERE estado = 'procesado'
   AND fecha < (CURRENT_DATE - 365);
ROLLBACK;

-- ------------------------------------------------------------------------------
-- D6: Borrar los clientes socios sin compras que viven en una localidad especifica.
-- Parametro concreto: 'San Rafael' (modificable).
-- ------------------------------------------------------------------------------
BEGIN;
SELECT COUNT(*) AS socios_sin_compras_localidad
  FROM cliente cl
  JOIN localidad l ON l.id_localidad = cl.id_localidad
 WHERE cl.tipo_cliente = 'socio'
   AND l.nombre = 'San Rafael'
   AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente);

DELETE FROM cliente cl
 USING localidad l
 WHERE cl.id_localidad = l.id_localidad
   AND cl.tipo_cliente = 'socio'
   AND l.nombre = 'San Rafael'
   AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente);

SELECT COUNT(*) AS socios_restantes_criterio
  FROM cliente cl
  JOIN localidad l ON l.id_localidad = cl.id_localidad
 WHERE cl.tipo_cliente = 'socio'
   AND l.nombre = 'San Rafael'
   AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente);
ROLLBACK;
