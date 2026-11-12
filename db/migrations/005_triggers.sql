-- ==============================================================================
-- 005_triggers.sql
-- Etapa 2: Triggers que garantizan las reglas de negocio dentro de PostgreSQL.
-- Cada trigger referencia explicitamente la regla de negocio (RN-XX) que protege.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- RN-06: Descuento inicial automatico segun tipo de cliente al dar de alta
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_cliente_descuento_inicial()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.descuento_pct := fn_descuento_base_tipo(NEW.tipo_cliente);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cliente_descuento_inicial
BEFORE INSERT ON cliente
FOR EACH ROW
EXECUTE FUNCTION trg_fn_cliente_descuento_inicial();

-- ------------------------------------------------------------------------------
-- RN-08 y RN-09: Validacion de stock (con bloqueo FOR UPDATE) y calculo de
--                precio unitario, descuento y subtotal del renglon BEFORE INSERT
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_renglon_comp_validar_y_calcular()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_sala       INTEGER;
    v_id_cliente INTEGER;
    v_stock      INTEGER;
    v_precio     NUMERIC(12,2);
    v_desc_pct   NUMERIC(5,2);
BEGIN
    SELECT c.id_sala, c.id_cliente
      INTO v_sala, v_id_cliente
      FROM comprobante c
     WHERE c.nro_comprobante = NEW.nro_comprobante;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Comprobante % inexistente', NEW.nro_comprobante;
    END IF;

    -- Bloqueo pesimista sobre stock_sala para evitar doble venta concurrente (RN-09)
    SELECT ss.cantidad
      INTO v_stock
      FROM stock_sala ss
     WHERE ss.id_sala = v_sala
       AND ss.cod_vino = NEW.cod_vino
     FOR UPDATE;

    IF NOT FOUND OR v_stock < NEW.cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente del vino % en la sala % (disponible: %, solicitado: %) (RN-09)',
            NEW.cod_vino, v_sala, COALESCE(v_stock, 0), NEW.cantidad;
    END IF;

    SELECT v.precio
      INTO v_precio
      FROM vino v
     WHERE v.cod_vino = NEW.cod_vino;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Vino % inexistente', NEW.cod_vino;
    END IF;

    v_desc_pct := fn_descuento_cliente(v_id_cliente);

    -- RN-08: Los importes del renglon no se cargan a mano, se calculan en la base
    NEW.precio_unitario := v_precio;
    NEW.descuento_pct   := v_desc_pct;
    NEW.subtotal        := ROUND(NEW.cantidad * v_precio * (1 - v_desc_pct / 100.0), 2);

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_comp_before_insert
BEFORE INSERT ON renglon_comprobante
FOR EACH ROW
EXECUTE FUNCTION trg_fn_renglon_comp_validar_y_calcular();

-- ------------------------------------------------------------------------------
-- RN-08 y RN-09: Descuento efectivo de stock_sala y recalculo de cabecera de
--                comprobante AFTER INSERT / UPDATE / DELETE en renglon_comprobante
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_renglon_comp_impactar()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_nro       INTEGER;
    v_sala      INTEGER;
    v_subtotal  NUMERIC(14,2);
    v_total     NUMERIC(14,2);
BEGIN
    v_nro := COALESCE(NEW.nro_comprobante, OLD.nro_comprobante);

    SELECT c.id_sala
      INTO v_sala
      FROM comprobante c
     WHERE c.nro_comprobante = v_nro;

    IF TG_OP = 'INSERT' THEN
        UPDATE stock_sala
           SET cantidad = cantidad - NEW.cantidad
         WHERE id_sala = v_sala
           AND cod_vino = NEW.cod_vino;
    ELSIF TG_OP = 'UPDATE' AND NEW.cantidad IS DISTINCT FROM OLD.cantidad THEN
        UPDATE stock_sala
           SET cantidad = cantidad + OLD.cantidad - NEW.cantidad
         WHERE id_sala = v_sala
           AND cod_vino = NEW.cod_vino;
    END IF;

    -- Si la cabecera existe (en ON DELETE CASCADE de comprobante ya no existe), recalcula totales
    IF FOUND THEN
        SELECT COALESCE(SUM(rc.cantidad * rc.precio_unitario), 0.00)::NUMERIC(14,2)
          INTO v_subtotal
          FROM renglon_comprobante rc
         WHERE rc.nro_comprobante = v_nro;

        v_total := fn_total_comprobante(v_nro);

        UPDATE comprobante
           SET subtotal  = v_subtotal,
               descuento = GREATEST(v_subtotal - v_total, 0.00),
               total     = v_total
         WHERE nro_comprobante = v_nro;
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_renglon_comp_after
AFTER INSERT OR UPDATE OR DELETE ON renglon_comprobante
FOR EACH ROW
EXECUTE FUNCTION trg_fn_renglon_comp_impactar();

-- ------------------------------------------------------------------------------
-- RN-10: Control de transiciones de estado en INGRESO
--        Solo permite: en_confeccion -> terminado -> procesado (sin retrocesos).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_ingreso_estado()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_items INTEGER;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.estado IS DISTINCT FROM 'en_confeccion' THEN
            RAISE EXCEPTION 'Todo nuevo ingreso debe iniciar en estado en_confeccion (RN-10)';
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.estado IS NOT DISTINCT FROM OLD.estado THEN
        RETURN NEW;
    END IF;

    IF OLD.estado = 'en_confeccion' AND NEW.estado = 'terminado' THEN
        SELECT COUNT(*) INTO v_items FROM renglon_ingreso WHERE cod_ingreso = NEW.cod_ingreso;
        IF v_items = 0 THEN
            RAISE EXCEPTION 'No se puede terminar el ingreso % sin renglones (RN-10)', NEW.cod_ingreso;
        END IF;
        RETURN NEW;
    ELSIF OLD.estado = 'terminado' AND NEW.estado = 'procesado' THEN
        IF current_setting('app.procesando_doc', true) IS DISTINCT FROM 'true' THEN
            RAISE EXCEPTION 'El ingreso % solo puede pasar a procesado mediante sp_procesar_ingreso (RN-10)', NEW.cod_ingreso;
        END IF;
        RETURN NEW;
    ELSE
        RAISE EXCEPTION 'Transicion de estado invalida en ingreso %: % -> % (RN-10)',
            NEW.cod_ingreso, OLD.estado, NEW.estado;
    END IF;
END;
$$;

CREATE TRIGGER trg_ingreso_control_estado
BEFORE INSERT OR UPDATE ON ingreso
FOR EACH ROW
EXECUTE FUNCTION trg_fn_ingreso_estado();

-- ------------------------------------------------------------------------------
-- RN-11: Control de fecha de confeccion actual e inmutable y estados en TRANSFERENCIA
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_transferencia_estado_fecha()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_items INTEGER;
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.fecha_confeccion := CURRENT_DATE;
        IF NEW.estado IS DISTINCT FROM 'en_confeccion' THEN
            RAISE EXCEPTION 'Toda nueva transferencia debe iniciar en estado en_confeccion (RN-11)';
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.fecha_confeccion IS DISTINCT FROM OLD.fecha_confeccion THEN
        RAISE EXCEPTION 'La fecha de confeccion de una transferencia no puede modificarse (RN-11)';
    END IF;

    IF NEW.estado IS NOT DISTINCT FROM OLD.estado THEN
        RETURN NEW;
    END IF;

    IF OLD.estado = 'en_confeccion' AND NEW.estado = 'terminado' THEN
        SELECT COUNT(*) INTO v_items FROM renglon_transferencia WHERE nro_solicitud = NEW.nro_solicitud;
        IF v_items = 0 THEN
            RAISE EXCEPTION 'No se puede terminar la transferencia % sin renglones (RN-11)', NEW.nro_solicitud;
        END IF;
        RETURN NEW;
    ELSIF OLD.estado = 'terminado' AND NEW.estado = 'procesado' THEN
        IF current_setting('app.procesando_doc', true) IS DISTINCT FROM 'true' THEN
            RAISE EXCEPTION 'La transferencia % solo puede pasar a procesado mediante sp_procesar_transferencia (RN-11)', NEW.nro_solicitud;
        END IF;
        RETURN NEW;
    ELSE
        RAISE EXCEPTION 'Transicion de estado invalida en transferencia %: % -> % (RN-11)',
            NEW.nro_solicitud, OLD.estado, NEW.estado;
    END IF;
END;
$$;

CREATE TRIGGER trg_transferencia_control
BEFORE INSERT OR UPDATE ON transferencia
FOR EACH ROW
EXECUTE FUNCTION trg_fn_transferencia_estado_fecha();

-- ------------------------------------------------------------------------------
-- RN-12: Bloqueo de alta, modificacion o borrado de renglones en ingresos y
--        transferencias que no esten en estado 'en_confeccion'.
--        Permite ON DELETE CASCADE cuando la cabecera ya fue eliminada (ej. D5).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_bloqueo_renglon_ingreso()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_cod    INTEGER;
    v_estado estado_documento;
BEGIN
    v_cod := COALESCE(NEW.cod_ingreso, OLD.cod_ingreso);

    SELECT i.estado
      INTO v_estado
      FROM ingreso i
     WHERE i.cod_ingreso = v_cod;

    -- Si la cabecera no existe en DELETE, proviene de ON DELETE CASCADE (ej. D5)
    IF NOT FOUND AND TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    IF v_estado IS DISTINCT FROM 'en_confeccion' THEN
        RAISE EXCEPTION 'No se admiten cambios en renglones del ingreso % porque esta en estado % (RN-12)',
            v_cod, v_estado;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_bloqueo_renglon_ingreso
BEFORE INSERT OR UPDATE OR DELETE ON renglon_ingreso
FOR EACH ROW
EXECUTE FUNCTION trg_fn_bloqueo_renglon_ingreso();

CREATE OR REPLACE FUNCTION trg_fn_bloqueo_renglon_transferencia()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_nro    INTEGER;
    v_estado estado_documento;
BEGIN
    v_nro := COALESCE(NEW.nro_solicitud, OLD.nro_solicitud);

    SELECT t.estado
      INTO v_estado
      FROM transferencia t
     WHERE t.nro_solicitud = v_nro;

    IF NOT FOUND AND TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    IF v_estado IS DISTINCT FROM 'en_confeccion' THEN
        RAISE EXCEPTION 'No se admiten cambios en renglones de la transferencia % porque esta en estado % (RN-12)',
            v_nro, v_estado;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_bloqueo_renglon_transferencia
BEFORE INSERT OR UPDATE OR DELETE ON renglon_transferencia
FOR EACH ROW
EXECUTE FUNCTION trg_fn_bloqueo_renglon_transferencia();

-- ------------------------------------------------------------------------------
-- RN-13: Auditoria automatica de todo cambio de precio de un vino
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_auditoria_precio_vino()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.precio IS DISTINCT FROM OLD.precio THEN
        INSERT INTO auditoria_precio (cod_vino, precio_anterior, precio_nuevo, fecha_hora, usuario)
        VALUES (NEW.cod_vino, OLD.precio, NEW.precio, CURRENT_TIMESTAMP, current_user);
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_auditoria_precio_vino
AFTER UPDATE OF precio ON vino
FOR EACH ROW
EXECUTE FUNCTION trg_fn_auditoria_precio_vino();

-- ------------------------------------------------------------------------------
-- RN-05: Constraint trigger diferido para validar que los porcentajes de corte
--        de un vino sumen exactamente 100 al finalizar la transaccion.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_composicion_suma_100()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_cod_vino INTEGER;
    v_suma     NUMERIC(6,2);
BEGIN
    v_cod_vino := COALESCE(NEW.cod_vino, OLD.cod_vino);

    -- Si el vino fue eliminado (cascada), no validar
    PERFORM 1 FROM vino WHERE cod_vino = v_cod_vino;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    SELECT COALESCE(SUM(porcentaje), 0.00)
      INTO v_suma
      FROM composicion_vino
     WHERE cod_vino = v_cod_vino;

    IF v_suma <> 100.00 THEN
        RAISE EXCEPTION 'La composicion de cepas del vino % debe sumar exactamente 100%% (suma actual: %%%) (RN-05)',
            v_cod_vino, v_suma;
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_composicion_vino_suma_100
AFTER INSERT OR UPDATE OR DELETE ON composicion_vino
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION trg_fn_composicion_suma_100();
