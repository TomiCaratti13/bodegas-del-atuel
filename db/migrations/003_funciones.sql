-- ==============================================================================
-- 003_funciones.sql
-- Etapa 2: Funciones SQL y PL/pgSQL reutilizables.
-- Cada funcion documenta proposito, parametros y volatilidad (IMMUTABLE/STABLE).
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- fn_descuento_base_tipo
-- Proposito: Devuelve el porcentaje de descuento base segun el tipo de cliente (RN-06).
-- Parametros: p_tipo (tipo_cliente_enum)
-- Volatilidad: IMMUTABLE (el mapeo depende exclusivamente del parametro de entrada).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_descuento_base_tipo(p_tipo tipo_cliente_enum)
RETURNS NUMERIC(5,2)
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE p_tipo
        WHEN 'socio'        THEN 10.00
        WHEN 'distribuidor' THEN 20.00
        WHEN 'exportador'   THEN 30.00
    END;
$$;

-- ------------------------------------------------------------------------------
-- fn_descuento_cliente
-- Proposito: Obtiene el porcentaje de descuento vigente para un cliente dado (RN-06).
-- Parametros: p_id_cliente (INTEGER)
-- Volatilidad: STABLE (consulta la tabla cliente; no modifica datos).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_descuento_cliente(p_id_cliente INTEGER)
RETURNS NUMERIC(5,2)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_descuento NUMERIC(5,2);
BEGIN
    SELECT descuento_pct
      INTO v_descuento
      FROM cliente
     WHERE id_cliente = p_id_cliente;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cliente % inexistente al calcular descuento (RN-06)', p_id_cliente;
    END IF;

    RETURN v_descuento;
END;
$$;

-- ------------------------------------------------------------------------------
-- fn_stock_sala
-- Proposito: Devuelve la cantidad disponible de un vino en una sala (0 si no hay fila).
-- Parametros: p_sala (INTEGER), p_vino (INTEGER)
-- Volatilidad: STABLE (lee la tabla stock_sala dentro de la transaccion actual).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_stock_sala(p_sala INTEGER, p_vino INTEGER)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        (SELECT s.cantidad
           FROM stock_sala s
          WHERE s.id_sala = p_sala
            AND s.cod_vino = p_vino),
        0
    );
$$;

-- ------------------------------------------------------------------------------
-- fn_total_comprobante
-- Proposito: Calcula el total neto de un comprobante sumando los subtotales de
--            sus renglones con descuento aplicado (RN-08).
-- Parametros: p_nro (INTEGER)
-- Volatilidad: STABLE (agrega filas de renglon_comprobante).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_total_comprobante(p_nro INTEGER)
RETURNS NUMERIC(14,2)
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(SUM(rc.subtotal), 0.00)::NUMERIC(14,2)
      FROM renglon_comprobante rc
     WHERE rc.nro_comprobante = p_nro;
$$;

-- ------------------------------------------------------------------------------
-- fn_antiguedad_anios
-- Proposito: Calcula los anios completos transcurridos desde una fecha hasta hoy.
-- Parametros: p_fecha (DATE)
-- Volatilidad: STABLE (depende de CURRENT_DATE; constante dentro de una sentencia).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_antiguedad_anios(p_fecha DATE)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
    SELECT EXTRACT(YEAR FROM AGE(CURRENT_DATE, p_fecha))::INTEGER;
$$;

-- ------------------------------------------------------------------------------
-- fn_stock_total_vino
-- Proposito: Suma el stock del deposito central y el de todas las salas para un vino.
-- Parametros: p_vino (INTEGER)
-- Volatilidad: STABLE (lee stock_deposito y stock_sala).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_stock_total_vino(p_vino INTEGER)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE((SELECT sd.cantidad FROM stock_deposito sd WHERE sd.cod_vino = p_vino), 0)
         + COALESCE((SELECT SUM(ss.cantidad) FROM stock_sala ss WHERE ss.cod_vino = p_vino), 0);
$$;
