-- ==============================================================================
-- 002_constraints.sql
-- Etapa 2: Restricciones UNIQUE, CHECK, DEFAULT y acciones referenciales
-- (ON DELETE / ON UPDATE) explicitas y justificadas.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Restricciones UNIQUE adicionales a las claves primarias
-- ------------------------------------------------------------------------------
ALTER TABLE localidad
    ADD CONSTRAINT uq_localidad_nombre_provincia UNIQUE (nombre, provincia);

ALTER TABLE finca
    ADD CONSTRAINT uq_finca_nombre UNIQUE (nombre);

ALTER TABLE cepa
    ADD CONSTRAINT uq_cepa_nombre UNIQUE (nombre);

-- RN-04: Una parcela se cosecha como maximo una vez por campana
ALTER TABLE lote_uva
    ADD CONSTRAINT uq_lote_parcela_campana UNIQUE (id_finca, nro_parcela, campana);

ALTER TABLE bodega
    ADD CONSTRAINT uq_bodega_razon_social UNIQUE (razon_social);

ALTER TABLE vino
    ADD CONSTRAINT uq_vino_nombre_anada_volumen UNIQUE (nombre, anada, volumen_ml);

ALTER TABLE maridaje
    ADD CONSTRAINT uq_maridaje_nombre UNIQUE (nombre);

ALTER TABLE cliente
    ADD CONSTRAINT uq_cliente_documento UNIQUE (tipo_documento, nro_documento);

ALTER TABLE cliente_distribuidor
    ADD CONSTRAINT uq_distribuidor_habilitacion UNIQUE (nro_habilitacion);

ALTER TABLE transportista
    ADD CONSTRAINT uq_transportista_cuit UNIQUE (cuit);

-- ------------------------------------------------------------------------------
-- 2. Valores DEFAULT
-- ------------------------------------------------------------------------------
ALTER TABLE cliente
    ALTER COLUMN fecha_alta SET DEFAULT CURRENT_DATE,
    ALTER COLUMN descuento_pct SET DEFAULT 10.00;

ALTER TABLE cliente_socio
    ALTER COLUMN tipo_cliente SET DEFAULT 'socio';

ALTER TABLE cliente_distribuidor
    ALTER COLUMN tipo_cliente SET DEFAULT 'distribuidor';

ALTER TABLE cliente_exportador
    ALTER COLUMN tipo_cliente SET DEFAULT 'exportador';

ALTER TABLE comprobante
    ALTER COLUMN fecha SET DEFAULT CURRENT_DATE,
    ALTER COLUMN subtotal SET DEFAULT 0.00,
    ALTER COLUMN descuento SET DEFAULT 0.00,
    ALTER COLUMN total SET DEFAULT 0.00;

ALTER TABLE stock_deposito
    ALTER COLUMN cantidad SET DEFAULT 0;

ALTER TABLE stock_sala
    ALTER COLUMN cantidad SET DEFAULT 0;

ALTER TABLE ingreso
    ALTER COLUMN fecha SET DEFAULT CURRENT_DATE,
    ALTER COLUMN estado SET DEFAULT 'en_confeccion';

ALTER TABLE transferencia
    ALTER COLUMN fecha_confeccion SET DEFAULT CURRENT_DATE,
    ALTER COLUMN estado SET DEFAULT 'en_confeccion';

ALTER TABLE auditoria_precio
    ALTER COLUMN fecha_hora SET DEFAULT CURRENT_TIMESTAMP,
    ALTER COLUMN usuario SET DEFAULT current_user;

-- ------------------------------------------------------------------------------
-- 3. Restricciones CHECK (incluyendo validaciones entre columnas)
-- ------------------------------------------------------------------------------
ALTER TABLE empleado
    ADD CONSTRAINT chk_empleado_salario CHECK (salario > 0);

ALTER TABLE finca
    ADD CONSTRAINT chk_finca_superficie CHECK (superficie_ha > 0);

ALTER TABLE parcela
    ADD CONSTRAINT chk_parcela_nro CHECK (nro_parcela > 0),
    ADD CONSTRAINT chk_parcela_superficie CHECK (superficie_ha > 0),
    ADD CONSTRAINT chk_parcela_anio CHECK (anio_plantacion BETWEEN 1900 AND 2100);

ALTER TABLE lote_uva
    ADD CONSTRAINT chk_lote_campana CHECK (campana BETWEEN 1990 AND 2100),
    ADD CONSTRAINT chk_lote_kg CHECK (kg_cosechados > 0);

ALTER TABLE analisis_calidad
    ADD CONSTRAINT chk_analisis_brix CHECK (grado_brix BETWEEN 5 AND 45),
    ADD CONSTRAINT chk_analisis_ph CHECK (ph BETWEEN 2.0 AND 5.0),
    ADD CONSTRAINT chk_analisis_acidez CHECK (acidez_total > 0);

-- RN-01 y RN-15: Precio positivo y graduacion entre 5 y 20
ALTER TABLE vino
    ADD CONSTRAINT chk_vino_anada CHECK (anada BETWEEN 1990 AND 2100),
    ADD CONSTRAINT chk_vino_volumen CHECK (volumen_ml IN (187, 375, 750, 1500, 3000)),
    ADD CONSTRAINT chk_vino_graduacion CHECK (graduacion BETWEEN 5 AND 20),
    ADD CONSTRAINT chk_vino_precio CHECK (precio > 0);

ALTER TABLE maridaje
    ADD CONSTRAINT chk_maridaje_temp CHECK (temperatura_servicio BETWEEN -5 AND 30);

-- RN-06: Tipo de documento valido y rango de descuento
ALTER TABLE cliente
    ADD CONSTRAINT chk_cliente_tipo_doc CHECK (tipo_documento IN ('DNI', 'CUIT', 'CUIL', 'PASAPORTE')),
    ADD CONSTRAINT chk_cliente_descuento CHECK (descuento_pct BETWEEN 0 AND 100);

-- Disyuncion de subtipos
ALTER TABLE cliente_socio
    ADD CONSTRAINT chk_subtipo_socio CHECK (tipo_cliente = 'socio');

ALTER TABLE cliente_distribuidor
    ADD CONSTRAINT chk_subtipo_distribuidor CHECK (tipo_cliente = 'distribuidor');

ALTER TABLE cliente_exportador
    ADD CONSTRAINT chk_subtipo_exportador CHECK (tipo_cliente = 'exportador');

-- RN-07: CHECK entre columnas (vencimiento posterior a emision)
ALTER TABLE permiso_exportacion
    ADD CONSTRAINT chk_permiso_fechas CHECK (fecha_vencimiento > fecha_emision);

ALTER TABLE comprobante
    ADD CONSTRAINT chk_comprobante_importes CHECK (subtotal >= 0 AND descuento >= 0 AND total >= 0),
    ADD CONSTRAINT chk_comprobante_total_le_sub CHECK (total <= subtotal);

ALTER TABLE renglon_comprobante
    ADD CONSTRAINT chk_rc_cantidad CHECK (cantidad > 0),
    ADD CONSTRAINT chk_rc_precio CHECK (precio_unitario > 0),
    ADD CONSTRAINT chk_rc_descuento CHECK (descuento_pct BETWEEN 0 AND 100),
    ADD CONSTRAINT chk_rc_subtotal CHECK (subtotal >= 0);

-- RN-09: El stock nunca es negativo
ALTER TABLE stock_deposito
    ADD CONSTRAINT chk_stock_deposito_no_neg CHECK (cantidad >= 0);

ALTER TABLE stock_sala
    ADD CONSTRAINT chk_stock_sala_no_neg CHECK (cantidad >= 0);

-- RN-15: Cantidades positivas en renglones
ALTER TABLE renglon_ingreso
    ADD CONSTRAINT chk_ri_cantidad CHECK (cantidad > 0);

ALTER TABLE renglon_transferencia
    ADD CONSTRAINT chk_rt_cantidad CHECK (cantidad > 0);

ALTER TABLE auditoria_precio
    ADD CONSTRAINT chk_auditoria_precios CHECK (precio_anterior > 0 AND precio_nuevo > 0);

-- ------------------------------------------------------------------------------
-- 4. Acciones referenciales (ON DELETE / ON UPDATE) explicitas
--    RESTRICT en catalogos con movimientos (RN-14);
--    CASCADE solo en entidades debiles y renglones dependientes de su cabecera.
-- ------------------------------------------------------------------------------
ALTER TABLE sala_venta
    DROP CONSTRAINT fk_sala_localidad,
    ADD CONSTRAINT fk_sala_localidad FOREIGN KEY (id_localidad)
        REFERENCES localidad (id_localidad) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE empleado
    DROP CONSTRAINT fk_empleado_sala,
    ADD CONSTRAINT fk_empleado_sala FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE parcela
    DROP CONSTRAINT fk_parcela_finca,
    ADD CONSTRAINT fk_parcela_finca FOREIGN KEY (id_finca)
        REFERENCES finca (id_finca) ON DELETE CASCADE ON UPDATE CASCADE,
    DROP CONSTRAINT fk_parcela_cepa,
    ADD CONSTRAINT fk_parcela_cepa FOREIGN KEY (id_cepa)
        REFERENCES cepa (id_cepa) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE lote_uva
    DROP CONSTRAINT fk_lote_parcela,
    ADD CONSTRAINT fk_lote_parcela FOREIGN KEY (id_finca, nro_parcela)
        REFERENCES parcela (id_finca, nro_parcela) ON DELETE RESTRICT ON UPDATE CASCADE,
    DROP CONSTRAINT fk_lote_bodega,
    ADD CONSTRAINT fk_lote_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE analisis_calidad
    DROP CONSTRAINT fk_analisis_lote,
    ADD CONSTRAINT fk_analisis_lote FOREIGN KEY (nro_lote)
        REFERENCES lote_uva (nro_lote) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE vino
    DROP CONSTRAINT fk_vino_bodega,
    ADD CONSTRAINT fk_vino_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE composicion_vino
    DROP CONSTRAINT fk_comp_vino,
    ADD CONSTRAINT fk_comp_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE CASCADE ON UPDATE CASCADE,
    DROP CONSTRAINT fk_comp_cepa,
    ADD CONSTRAINT fk_comp_cepa FOREIGN KEY (id_cepa)
        REFERENCES cepa (id_cepa) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE vino_maridaje
    DROP CONSTRAINT fk_vm_vino,
    ADD CONSTRAINT fk_vm_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE CASCADE ON UPDATE CASCADE,
    DROP CONSTRAINT fk_vm_maridaje,
    ADD CONSTRAINT fk_vm_maridaje FOREIGN KEY (id_maridaje)
        REFERENCES maridaje (id_maridaje) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE cliente
    DROP CONSTRAINT fk_cliente_localidad,
    ADD CONSTRAINT fk_cliente_localidad FOREIGN KEY (id_localidad)
        REFERENCES localidad (id_localidad) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE cliente_socio
    DROP CONSTRAINT fk_socio_cliente,
    ADD CONSTRAINT fk_socio_cliente FOREIGN KEY (id_cliente, tipo_cliente)
        REFERENCES cliente (id_cliente, tipo_cliente) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE cliente_distribuidor
    DROP CONSTRAINT fk_dist_cliente,
    ADD CONSTRAINT fk_dist_cliente FOREIGN KEY (id_cliente, tipo_cliente)
        REFERENCES cliente (id_cliente, tipo_cliente) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE cliente_exportador
    DROP CONSTRAINT fk_exp_cliente,
    ADD CONSTRAINT fk_exp_cliente FOREIGN KEY (id_cliente, tipo_cliente)
        REFERENCES cliente (id_cliente, tipo_cliente) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE permiso_exportacion
    DROP CONSTRAINT fk_permiso_exportador,
    ADD CONSTRAINT fk_permiso_exportador FOREIGN KEY (id_exportador)
        REFERENCES cliente_exportador (id_cliente) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE comprobante
    DROP CONSTRAINT fk_comp_cliente,
    ADD CONSTRAINT fk_comp_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente) ON DELETE RESTRICT ON UPDATE CASCADE,
    DROP CONSTRAINT fk_comp_sala,
    ADD CONSTRAINT fk_comp_sala FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE renglon_comprobante
    DROP CONSTRAINT fk_rc_comprobante,
    ADD CONSTRAINT fk_rc_comprobante FOREIGN KEY (nro_comprobante)
        REFERENCES comprobante (nro_comprobante) ON DELETE CASCADE ON UPDATE CASCADE,
    DROP CONSTRAINT fk_rc_vino,
    ADD CONSTRAINT fk_rc_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE transportista_localidad
    DROP CONSTRAINT fk_tl_transportista,
    ADD CONSTRAINT fk_tl_transportista FOREIGN KEY (cod_transportista)
        REFERENCES transportista (cod_transportista) ON DELETE CASCADE ON UPDATE CASCADE,
    DROP CONSTRAINT fk_tl_localidad,
    ADD CONSTRAINT fk_tl_localidad FOREIGN KEY (id_localidad)
        REFERENCES localidad (id_localidad) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE stock_deposito
    DROP CONSTRAINT fk_stock_dep_vino,
    ADD CONSTRAINT fk_stock_dep_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE stock_sala
    DROP CONSTRAINT fk_stock_sala_sala,
    ADD CONSTRAINT fk_stock_sala_sala FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE CASCADE,
    DROP CONSTRAINT fk_stock_sala_vino,
    ADD CONSTRAINT fk_stock_sala_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE ingreso
    DROP CONSTRAINT fk_ingreso_transportista,
    ADD CONSTRAINT fk_ingreso_transportista FOREIGN KEY (cod_transportista)
        REFERENCES transportista (cod_transportista) ON DELETE RESTRICT ON UPDATE CASCADE,
    DROP CONSTRAINT fk_ingreso_bodega,
    ADD CONSTRAINT fk_ingreso_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE renglon_ingreso
    DROP CONSTRAINT fk_ri_ingreso,
    ADD CONSTRAINT fk_ri_ingreso FOREIGN KEY (cod_ingreso)
        REFERENCES ingreso (cod_ingreso) ON DELETE CASCADE ON UPDATE CASCADE,
    DROP CONSTRAINT fk_ri_vino,
    ADD CONSTRAINT fk_ri_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE transferencia
    DROP CONSTRAINT fk_transf_sala,
    ADD CONSTRAINT fk_transf_sala FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE renglon_transferencia
    DROP CONSTRAINT fk_rt_transferencia,
    ADD CONSTRAINT fk_rt_transferencia FOREIGN KEY (nro_solicitud)
        REFERENCES transferencia (nro_solicitud) ON DELETE CASCADE ON UPDATE CASCADE,
    DROP CONSTRAINT fk_rt_vino,
    ADD CONSTRAINT fk_rt_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE auditoria_precio
    DROP CONSTRAINT fk_auditoria_vino,
    ADD CONSTRAINT fk_auditoria_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE CASCADE;
