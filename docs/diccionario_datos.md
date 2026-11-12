# Diccionario de Datos — Bodegas del Atuel

## Tipos propios
- `estado_documento` (`ENUM`): `'en_confeccion'`, `'terminado'`, `'procesado'`
- `tipo_vino` (`ENUM`): `'tinto'`, `'blanco'`, `'rosado'`, `'espumante'`
- `tipo_cepa` (`ENUM`): `'tinta'`, `'blanca'`
- `tipo_cliente_enum` (`ENUM`): `'socio'`, `'distribuidor'`, `'exportador'`
- `dia_semana` (`ENUM`): `'lunes'`, `'martes'`, `'miercoles'`, `'jueves'`, `'viernes'`, `'sabado'`, `'domingo'`
- `cuit_dom` (`DOMAIN`): `CHAR(11)` con `CHECK (VALUE ~ '^[0-9]{11}$')`
- `porcentaje_corte_dom` (`DOMAIN`): `NUMERIC(5,2)` con `CHECK (VALUE > 0 AND VALUE <= 100)`

---

## Tablas

### `localidad`
| Columna | Tipo | Nulo | Restricciones | Descripcion |
| :--- | :--- | :--- | :--- | :--- |
| `id_localidad` | `INTEGER` | NO | `PK`, `IDENTITY` | Identificador de localidad |
| `codigo_postal` | `VARCHAR(10)` | NO | | Codigo postal |
| `nombre` | `VARCHAR(100)` | NO | `UNIQUE (nombre, provincia)` | Nombre de la localidad |
| `provincia` | `VARCHAR(80)` | NO | `UNIQUE (nombre, provincia)` | Provincia |
| `encargado_regional` | `VARCHAR(120)` | NO | | Responsable comercial unico por localidad (`RN-02`) |

### `sala_venta`
| Columna | Tipo | Nulo | Restricciones | Descripcion |
| :--- | :--- | :--- | :--- | :--- |
| `id_sala` | `INTEGER` | NO | `PK`, `IDENTITY` | Identificador de sala |
| `calle` | `VARCHAR(120)` | NO | | Calle de la sala |
| `numero` | `VARCHAR(15)` | NO | | Altura/numero |
| `dia_cierre` | `dia_semana` | NO | | Dia de cierre semanal |
| `id_localidad` | `INTEGER` | NO | `FK -> localidad(id_localidad) RESTRICT` | Localidad donde se ubica (`RN-02`) |

### `empleado`
| Columna | Tipo | Nulo | Restricciones | Descripcion |
| :--- | :--- | :--- | :--- | :--- |
| `cuit` | `cuit_dom` | NO | `PK` | CUIT de 11 digitos |
| `nombre` | `VARCHAR(120)` | NO | | Nombre y apellido |
| `fecha_ingreso` | `DATE` | NO | | Fecha de ingreso laboral |
| `salario` | `NUMERIC(12,2)` | NO | `CHECK (salario > 0)` | Salario mensual |
| `id_sala` | `INTEGER` | NO | `FK -> sala_venta(id_sala) RESTRICT` | Sala unica donde trabaja (`RN-03`) |

### `finca`
| Columna | Tipo | Nulo | Restricciones | Descripcion |
| :--- | :--- | :--- | :--- | :--- |
| `id_finca` | `INTEGER` | NO | `PK`, `IDENTITY` | Identificador de finca |
| `nombre` | `VARCHAR(120)` | NO | `UNIQUE` | Nombre de la finca |
| `superficie_ha` | `NUMERIC(10,2)` | NO | `CHECK (superficie_ha > 0)` | Superficie total en hectareas |
| `departamento` | `VARCHAR(80)` | NO | | Departamento |
| `provincia` | `VARCHAR(80)` | NO | | Provincia |

### `cepa`
| Columna | Tipo | Nulo | Restricciones | Descripcion |
| :--- | :--- | :--- | :--- | :--- |
| `id_cepa` | `INTEGER` | NO | `PK`, `IDENTITY` | Identificador de cepa |
| `nombre` | `VARCHAR(80)` | NO | `UNIQUE` | Nombre de la cepa |
| `tipo` | `tipo_cepa` | NO | | `'tinta'` o `'blanca'` |

### `parcela` (entidad debil)
| Columna | Tipo | Nulo | Restricciones | Descripcion |
| :--- | :--- | :--- | :--- | :--- |
| `id_finca` | `INTEGER` | NO | `PK`, `FK -> finca(id_finca) CASCADE` | Finca contenedora |
| `nro_parcela` | `INTEGER` | NO | `PK`, `CHECK (nro_parcela > 0)` | Numero dentro de la finca |
| `superficie_ha` | `NUMERIC(10,2)` | NO | `CHECK (superficie_ha > 0)` | Superficie en hectareas |
| `anio_plantacion` | `SMALLINT` | NO | `CHECK (BETWEEN 1900 AND 2100)` | Anio de plantacion |
| `id_cepa` | `INTEGER` | NO | `FK -> cepa(id_cepa) RESTRICT` | Cepa unica plantada (`RN-04`) |

### `bodega`
| Columna | Tipo | Nulo | Restricciones | Descripcion |
| :--- | :--- | :--- | :--- | :--- |
| `cuit` | `cuit_dom` | NO | `PK` | CUIT de la bodega |
| `razon_social` | `VARCHAR(150)` | NO | `UNIQUE` | Razon social |
| `domicilio` | `VARCHAR(200)` | NO | | Domicilio fiscal/planta |

### `lote_uva`
| Columna | Tipo | Nulo | Restricciones | Descripcion |
| :--- | :--- | :--- | :--- | :--- |
| `nro_lote` | `INTEGER` | NO | `PK`, `IDENTITY` | Numero de lote |
| `id_finca` | `INTEGER` | NO | `FK -> parcela`, `UQ (id_finca, nro_parcela, campana)` | Finca de la parcela |
| `nro_parcela` | `INTEGER` | NO | `FK -> parcela`, `UQ (id_finca, nro_parcela, campana)` | Numero de parcela |
| `campana` | `SMALLINT` | NO | `CHECK (BETWEEN 1990 AND 2100)`, `UQ` | Anio de cosecha (`RN-04`) |
| `fecha_cosecha` | `DATE` | NO | | Fecha de cosecha |
| `kg_cosechados` | `NUMERIC(12,2)` | NO | `CHECK (kg_cosechados > 0)` | Kilogramos cosechados |
| `cuit_bodega` | `cuit_dom` | NO | `FK -> bodega(cuit) RESTRICT` | Bodega destino |

### `analisis_calidad`
| Columna | Tipo | Nulo | Restricciones | Descripcion |
| :--- | :--- | :--- | :--- | :--- |
| `id_analisis` | `INTEGER` | NO | `PK`, `IDENTITY` | Identificador del analisis |
| `nro_lote` | `INTEGER` | NO | `FK -> lote_uva(nro_lote) CASCADE` | Lote evaluado |
| `fecha` | `DATE` | NO | | Fecha del analisis |
| `grado_brix` | `NUMERIC(4,2)` | NO | `CHECK (BETWEEN 5 AND 45)` | Grado Brix |
| `ph` | `NUMERIC(4,2)` | NO | `CHECK (BETWEEN 2.0 AND 5.0)` | pH |
| `acidez_total` | `NUMERIC(5,2)` | NO | `CHECK (acidez_total > 0)` | Acidez total (g/L) |

### `vino`
| Columna | Tipo | Nulo | Restricciones | Descripcion |
| :--- | :--- | :--- | :--- | :--- |
| `cod_vino` | `INTEGER` | NO | `PK`, `IDENTITY` | Codigo de vino |
| `nombre` | `VARCHAR(100)` | NO | `UQ (nombre, anada, volumen_ml)` | Nombre comercial |
| `tipo` | `tipo_vino` | NO | | `'tinto'`, `'blanco'`, `'rosado'`, `'espumante'` |
| `anada` | `SMALLINT` | NO | `CHECK (BETWEEN 1990 AND 2100)`, `UQ` | Anio de cosecha/anada |
| `volumen_ml` | `INTEGER` | NO | `CHECK (IN (187,375,750,1500,3000))`, `UQ` | Presentacion en ml |
| `graduacion` | `NUMERIC(4,2)` | NO | `CHECK (BETWEEN 5 AND 20)` | Graduacion alcoholica (`RN-15`) |
| `precio` | `NUMERIC(12,2)` | NO | `CHECK (precio > 0)` | Precio unico de venta (`RN-01`) |
| `cuit_bodega` | `cuit_dom` | NO | `FK -> bodega(cuit) RESTRICT` | Bodega elaboradora (`RN-14`) |

### `composicion_vino`
| Columna | Tipo | Nulo | Restricciones | Descripcion |
| :--- | :--- | :--- | :--- | :--- |
| `cod_vino` | `INTEGER` | NO | `PK`, `FK -> vino CASCADE` | Vino |
| `id_cepa` | `INTEGER` | NO | `PK`, `FK -> cepa RESTRICT` | Cepa componente |
| `porcentaje` | `porcentaje_corte_dom` | NO | `> 0 y <= 100`; suma = 100 (`RN-05`) | Porcentaje de corte |

### `maridaje` y `vino_maridaje`
- `maridaje`: `id_maridaje` (`PK`), `nombre` (`VARCHAR(80)`, `UNIQUE`), `temperatura_servicio` (`SMALLINT`, `CHECK BETWEEN -5 AND 30`).
- `vino_maridaje`: `cod_vino` (`PK`, `FK -> vino CASCADE`), `id_maridaje` (`PK`, `FK -> maridaje RESTRICT`).

### `cliente`, `cliente_socio`, `cliente_distribuidor`, `cliente_exportador`, `permiso_exportacion`
- `cliente`: `id_cliente` (`PK`), `tipo_cliente` (`tipo_cliente_enum`), `nombre_razon_social` (`VARCHAR(150)`), `tipo_documento` (`CHECK IN ('DNI','CUIT','CUIL','PASAPORTE')`), `nro_documento` (`UQ (tipo_documento, nro_documento)`), `direccion`, `id_localidad` (`FK RESTRICT`), `fecha_alta` (`DEFAULT CURRENT_DATE`), `descuento_pct` (`NUMERIC(5,2)`, `DEFAULT 10.00`, `CHECK BETWEEN 0 AND 100`).
- `cliente_socio`: `id_cliente` (`PK`), `tipo_cliente` (`DEFAULT 'socio'`, `CHECK = 'socio'`), `FK (id_cliente, tipo_cliente) CASCADE`.
- `cliente_distribuidor`: `id_cliente` (`PK`), `tipo_cliente` (`DEFAULT 'distribuidor'`, `CHECK = 'distribuidor'`), `zona_cobertura`, `nro_habilitacion` (`UNIQUE`), `FK CASCADE`.
- `cliente_exportador`: `id_cliente` (`PK`), `tipo_cliente` (`DEFAULT 'exportador'`, `CHECK = 'exportador'`), `pais_destino_principal`, `FK CASCADE`.
- `permiso_exportacion`: `codigo` (`PK`), `id_exportador` (`FK -> cliente_exportador CASCADE`), `fecha_emision`, `fecha_vencimiento` (`CHECK fecha_vencimiento > fecha_emision`, `RN-07`).

### `comprobante` y `renglon_comprobante`
- `comprobante`: `nro_comprobante` (`PK`), `fecha` (`DEFAULT CURRENT_DATE`), `id_cliente` (`FK RESTRICT`), `id_sala` (`FK RESTRICT`), `subtotal`, `descuento`, `total` (`NUMERIC(14,2)`, `DEFAULT 0`, `>= 0`, `total <= subtotal`).
- `renglon_comprobante`: `(nro_comprobante, cod_vino)` (`PK`, `FK comprobante CASCADE`, `FK vino RESTRICT`), `cantidad` (`> 0`), `precio_unitario` (`> 0`), `descuento_pct` (`0..100`), `subtotal` (`>= 0`).

### `transportista`, `transportista_localidad`, `stock_deposito`, `stock_sala`, `ingreso`, `renglon_ingreso`, `transferencia`, `renglon_transferencia`, `auditoria_precio`
- `transportista`: `cod_transportista` (`PK`), `razon_social`, `cuit` (`cuit_dom`, `UNIQUE`), `email`, `telefono`, `domicilio`.
- `transportista_localidad`: `(cod_transportista, id_localidad)` (`PK`, `FK transportista CASCADE`, `FK localidad RESTRICT`).
- `stock_deposito`: `cod_vino` (`PK`, `FK vino RESTRICT`), `cantidad` (`DEFAULT 0`, `CHECK >= 0`).
- `stock_sala`: `(id_sala, cod_vino)` (`PK`, `FK sala RESTRICT`, `FK vino RESTRICT`), `cantidad` (`DEFAULT 0`, `CHECK >= 0`).
- `ingreso`: `cod_ingreso` (`PK`), `fecha` (`DEFAULT CURRENT_DATE`), `estado` (`estado_documento`, `DEFAULT 'en_confeccion'`), `cod_transportista` (`FK RESTRICT`), `cuit_bodega` (`FK RESTRICT`).
- `renglon_ingreso`: `(cod_ingreso, cod_vino)` (`PK`, `FK ingreso CASCADE`, `FK vino RESTRICT`), `cantidad` (`> 0`).
- `transferencia`: `nro_solicitud` (`PK`), `id_sala` (`FK RESTRICT`), `fecha_confeccion` (`DEFAULT CURRENT_DATE`), `estado` (`estado_documento`, `DEFAULT 'en_confeccion'`).
- `renglon_transferencia`: `(nro_solicitud, cod_vino)` (`PK`, `FK transferencia CASCADE`, `FK vino RESTRICT`), `cantidad` (`> 0`).
- `auditoria_precio`: `id_auditoria` (`PK`), `cod_vino` (`FK RESTRICT`), `precio_anterior`, `precio_nuevo` (`> 0`), `fecha_hora` (`TIMESTAMPTZ`, `DEFAULT CURRENT_TIMESTAMP`), `usuario` (`VARCHAR(100)`, `DEFAULT current_user`).
