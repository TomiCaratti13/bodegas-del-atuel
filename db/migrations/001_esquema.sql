-- ==============================================================================
-- 001_esquema.sql
-- Etapa 1: Tipos propios, dominios, tablas, claves primarias y foraneas base.
-- Las restricciones adicionales (UNIQUE, CHECK, DEFAULT, ON DELETE/ON UPDATE)
-- se completan en 002_constraints.sql.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Tipos enumerados y dominios
-- ------------------------------------------------------------------------------
CREATE TYPE estado_documento AS ENUM ('en_confeccion', 'terminado', 'procesado');
CREATE TYPE tipo_vino AS ENUM ('tinto', 'blanco', 'rosado', 'espumante');
CREATE TYPE tipo_cepa AS ENUM ('tinta', 'blanca');
CREATE TYPE tipo_cliente_enum AS ENUM ('socio', 'distribuidor', 'exportador');
CREATE TYPE dia_semana AS ENUM ('lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo');

CREATE DOMAIN cuit_dom AS CHAR(11)
    CHECK (VALUE ~ '^[0-9]{11}$');

CREATE DOMAIN porcentaje_corte_dom AS NUMERIC(5,2)
    CHECK (VALUE > 0 AND VALUE <= 100);

-- ------------------------------------------------------------------------------
-- 2. Localidades, salas de venta y empleados
-- ------------------------------------------------------------------------------
CREATE TABLE localidad (
    id_localidad       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo_postal      VARCHAR(10) NOT NULL,
    nombre             VARCHAR(100) NOT NULL,
    provincia          VARCHAR(80) NOT NULL,
    encargado_regional VARCHAR(120) NOT NULL
);

CREATE TABLE sala_venta (
    id_sala      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    calle        VARCHAR(120) NOT NULL,
    numero       VARCHAR(15) NOT NULL,
    dia_cierre   dia_semana NOT NULL,
    id_localidad INTEGER NOT NULL,
    CONSTRAINT fk_sala_localidad FOREIGN KEY (id_localidad)
        REFERENCES localidad (id_localidad)
);

CREATE TABLE empleado (
    cuit          cuit_dom PRIMARY KEY,
    nombre        VARCHAR(120) NOT NULL,
    fecha_ingreso DATE NOT NULL,
    salario       NUMERIC(12,2) NOT NULL,
    id_sala       INTEGER NOT NULL,
    CONSTRAINT fk_empleado_sala FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala)
);

-- ------------------------------------------------------------------------------
-- 3. Produccion de uva (fincas, parcelas, cepas, lotes y analisis)
-- ------------------------------------------------------------------------------
CREATE TABLE finca (
    id_finca      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre        VARCHAR(120) NOT NULL,
    superficie_ha NUMERIC(10,2) NOT NULL,
    departamento  VARCHAR(80) NOT NULL,
    provincia     VARCHAR(80) NOT NULL
);

CREATE TABLE cepa (
    id_cepa INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre  VARCHAR(80) NOT NULL,
    tipo    tipo_cepa NOT NULL
);

-- Entidad debil de finca: PK compuesta (id_finca, nro_parcela)
CREATE TABLE parcela (
    id_finca        INTEGER NOT NULL,
    nro_parcela     INTEGER NOT NULL,
    superficie_ha   NUMERIC(10,2) NOT NULL,
    anio_plantacion SMALLINT NOT NULL,
    id_cepa         INTEGER NOT NULL,
    PRIMARY KEY (id_finca, nro_parcela),
    CONSTRAINT fk_parcela_finca FOREIGN KEY (id_finca)
        REFERENCES finca (id_finca),
    CONSTRAINT fk_parcela_cepa FOREIGN KEY (id_cepa)
        REFERENCES cepa (id_cepa)
);

CREATE TABLE bodega (
    cuit         cuit_dom PRIMARY KEY,
    razon_social VARCHAR(150) NOT NULL,
    domicilio    VARCHAR(200) NOT NULL
);

CREATE TABLE lote_uva (
    nro_lote      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_finca      INTEGER NOT NULL,
    nro_parcela   INTEGER NOT NULL,
    campana       SMALLINT NOT NULL,
    fecha_cosecha DATE NOT NULL,
    kg_cosechados NUMERIC(12,2) NOT NULL,
    cuit_bodega   cuit_dom NOT NULL,
    CONSTRAINT fk_lote_parcela FOREIGN KEY (id_finca, nro_parcela)
        REFERENCES parcela (id_finca, nro_parcela),
    CONSTRAINT fk_lote_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit)
);

CREATE TABLE analisis_calidad (
    id_analisis  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nro_lote     INTEGER NOT NULL,
    fecha        DATE NOT NULL,
    grado_brix   NUMERIC(4,2) NOT NULL,
    ph           NUMERIC(4,2) NOT NULL,
    acidez_total NUMERIC(5,2) NOT NULL,
    CONSTRAINT fk_analisis_lote FOREIGN KEY (nro_lote)
        REFERENCES lote_uva (nro_lote)
);

-- ------------------------------------------------------------------------------
-- 4. Vinos, composicion y maridajes
-- ------------------------------------------------------------------------------
CREATE TABLE vino (
    cod_vino    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre      VARCHAR(100) NOT NULL,
    tipo        tipo_vino NOT NULL,
    anada       SMALLINT NOT NULL,
    volumen_ml  INTEGER NOT NULL,
    graduacion  NUMERIC(4,2) NOT NULL,
    precio      NUMERIC(12,2) NOT NULL,
    cuit_bodega cuit_dom NOT NULL,
    CONSTRAINT fk_vino_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit)
);

CREATE TABLE composicion_vino (
    cod_vino   INTEGER NOT NULL,
    id_cepa    INTEGER NOT NULL,
    porcentaje porcentaje_corte_dom NOT NULL,
    PRIMARY KEY (cod_vino, id_cepa),
    CONSTRAINT fk_comp_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino),
    CONSTRAINT fk_comp_cepa FOREIGN KEY (id_cepa)
        REFERENCES cepa (id_cepa)
);

CREATE TABLE maridaje (
    id_maridaje          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre               VARCHAR(80) NOT NULL,
    temperatura_servicio SMALLINT NOT NULL
);

CREATE TABLE vino_maridaje (
    cod_vino    INTEGER NOT NULL,
    id_maridaje INTEGER NOT NULL,
    PRIMARY KEY (cod_vino, id_maridaje),
    CONSTRAINT fk_vm_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino),
    CONSTRAINT fk_vm_maridaje FOREIGN KEY (id_maridaje)
        REFERENCES maridaje (id_maridaje)
);

-- ------------------------------------------------------------------------------
-- 5. Clientes (supertipo + subtipos disjuntos) y permisos de exportacion
-- ------------------------------------------------------------------------------
CREATE TABLE cliente (
    id_cliente          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo_cliente        tipo_cliente_enum NOT NULL,
    nombre_razon_social VARCHAR(150) NOT NULL,
    tipo_documento      VARCHAR(20) NOT NULL,
    nro_documento       VARCHAR(20) NOT NULL,
    direccion           VARCHAR(200) NOT NULL,
    id_localidad        INTEGER NOT NULL,
    fecha_alta          DATE NOT NULL,
    descuento_pct       NUMERIC(5,2) NOT NULL,
    CONSTRAINT fk_cliente_localidad FOREIGN KEY (id_localidad)
        REFERENCES localidad (id_localidad),
    CONSTRAINT uq_cliente_id_tipo UNIQUE (id_cliente, tipo_cliente)
);

CREATE TABLE cliente_socio (
    id_cliente   INTEGER PRIMARY KEY,
    tipo_cliente tipo_cliente_enum NOT NULL,
    CONSTRAINT fk_socio_cliente FOREIGN KEY (id_cliente, tipo_cliente)
        REFERENCES cliente (id_cliente, tipo_cliente)
);

CREATE TABLE cliente_distribuidor (
    id_cliente       INTEGER PRIMARY KEY,
    tipo_cliente     tipo_cliente_enum NOT NULL,
    zona_cobertura   VARCHAR(150) NOT NULL,
    nro_habilitacion VARCHAR(50) NOT NULL,
    CONSTRAINT fk_dist_cliente FOREIGN KEY (id_cliente, tipo_cliente)
        REFERENCES cliente (id_cliente, tipo_cliente)
);

CREATE TABLE cliente_exportador (
    id_cliente             INTEGER PRIMARY KEY,
    tipo_cliente           tipo_cliente_enum NOT NULL,
    pais_destino_principal VARCHAR(80) NOT NULL,
    CONSTRAINT fk_exp_cliente FOREIGN KEY (id_cliente, tipo_cliente)
        REFERENCES cliente (id_cliente, tipo_cliente)
);

CREATE TABLE permiso_exportacion (
    codigo            VARCHAR(40) PRIMARY KEY,
    id_exportador     INTEGER NOT NULL,
    fecha_emision     DATE NOT NULL,
    fecha_vencimiento DATE NOT NULL,
    CONSTRAINT fk_permiso_exportador FOREIGN KEY (id_exportador)
        REFERENCES cliente_exportador (id_cliente)
);

-- ------------------------------------------------------------------------------
-- 6. Comprobantes de venta y renglones
-- ------------------------------------------------------------------------------
CREATE TABLE comprobante (
    nro_comprobante INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha           DATE NOT NULL,
    id_cliente      INTEGER NOT NULL,
    id_sala         INTEGER NOT NULL,
    subtotal        NUMERIC(14,2) NOT NULL,
    descuento       NUMERIC(14,2) NOT NULL,
    total           NUMERIC(14,2) NOT NULL,
    CONSTRAINT fk_comp_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente),
    CONSTRAINT fk_comp_sala FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala)
);

CREATE TABLE renglon_comprobante (
    nro_comprobante INTEGER NOT NULL,
    cod_vino        INTEGER NOT NULL,
    cantidad        INTEGER NOT NULL,
    precio_unitario NUMERIC(12,2) NOT NULL,
    descuento_pct   NUMERIC(5,2) NOT NULL,
    subtotal        NUMERIC(14,2) NOT NULL,
    PRIMARY KEY (nro_comprobante, cod_vino),
    CONSTRAINT fk_rc_comprobante FOREIGN KEY (nro_comprobante)
        REFERENCES comprobante (nro_comprobante),
    CONSTRAINT fk_rc_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino)
);

-- ------------------------------------------------------------------------------
-- 7. Transportistas, cobertura, ingresos, transferencias y stock
-- ------------------------------------------------------------------------------
CREATE TABLE transportista (
    cod_transportista INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    razon_social      VARCHAR(150) NOT NULL,
    cuit              cuit_dom NOT NULL,
    email             VARCHAR(150) NOT NULL,
    telefono          VARCHAR(40) NOT NULL,
    domicilio         VARCHAR(200) NOT NULL
);

CREATE TABLE transportista_localidad (
    cod_transportista INTEGER NOT NULL,
    id_localidad      INTEGER NOT NULL,
    PRIMARY KEY (cod_transportista, id_localidad),
    CONSTRAINT fk_tl_transportista FOREIGN KEY (cod_transportista)
        REFERENCES transportista (cod_transportista),
    CONSTRAINT fk_tl_localidad FOREIGN KEY (id_localidad)
        REFERENCES localidad (id_localidad)
);

CREATE TABLE stock_deposito (
    cod_vino INTEGER PRIMARY KEY,
    cantidad INTEGER NOT NULL,
    CONSTRAINT fk_stock_dep_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino)
);

CREATE TABLE stock_sala (
    id_sala  INTEGER NOT NULL,
    cod_vino INTEGER NOT NULL,
    cantidad INTEGER NOT NULL,
    PRIMARY KEY (id_sala, cod_vino),
    CONSTRAINT fk_stock_sala_sala FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala),
    CONSTRAINT fk_stock_sala_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino)
);

CREATE TABLE ingreso (
    cod_ingreso       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha             DATE NOT NULL,
    estado            estado_documento NOT NULL,
    cod_transportista INTEGER NOT NULL,
    cuit_bodega       cuit_dom NOT NULL,
    CONSTRAINT fk_ingreso_transportista FOREIGN KEY (cod_transportista)
        REFERENCES transportista (cod_transportista),
    CONSTRAINT fk_ingreso_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit)
);

CREATE TABLE renglon_ingreso (
    cod_ingreso INTEGER NOT NULL,
    cod_vino    INTEGER NOT NULL,
    cantidad    INTEGER NOT NULL,
    PRIMARY KEY (cod_ingreso, cod_vino),
    CONSTRAINT fk_ri_ingreso FOREIGN KEY (cod_ingreso)
        REFERENCES ingreso (cod_ingreso),
    CONSTRAINT fk_ri_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino)
);

CREATE TABLE transferencia (
    nro_solicitud    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_sala          INTEGER NOT NULL,
    fecha_confeccion DATE NOT NULL,
    estado           estado_documento NOT NULL,
    CONSTRAINT fk_transf_sala FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala)
);

CREATE TABLE renglon_transferencia (
    nro_solicitud INTEGER NOT NULL,
    cod_vino      INTEGER NOT NULL,
    cantidad      INTEGER NOT NULL,
    PRIMARY KEY (nro_solicitud, cod_vino),
    CONSTRAINT fk_rt_transferencia FOREIGN KEY (nro_solicitud)
        REFERENCES transferencia (nro_solicitud),
    CONSTRAINT fk_rt_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino)
);

-- ------------------------------------------------------------------------------
-- 8. Auditoria de precios (RN-13)
-- ------------------------------------------------------------------------------
CREATE TABLE auditoria_precio (
    id_auditoria    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cod_vino        INTEGER NOT NULL,
    precio_anterior NUMERIC(12,2) NOT NULL,
    precio_nuevo    NUMERIC(12,2) NOT NULL,
    fecha_hora      TIMESTAMPTZ NOT NULL,
    usuario         VARCHAR(100) NOT NULL,
    CONSTRAINT fk_auditoria_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino)
);
