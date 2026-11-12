# Decisiones de Diseno y Trazabilidad de Reglas

## 1. Decisiones de Diseno (Seccion 5)

### 1.1 Jerarquia de Clientes (`Socio`, `Distribuidor`, `Exportador`)
- **Estrategia elegida:** Supertipo (`cliente`) + 3 subtipos (`cliente_socio`, `cliente_distribuidor`, `cliente_exportador`), reforzados con restriccion `UNIQUE (id_cliente, tipo_cliente)` en `cliente` y clave foranea compuesta + `CHECK (tipo_cliente = '...')` en cada subtipo.
- **Alternativas descartadas:**
  - *Tabla unica con columna de tipo:* genera multiples columnas `NULL` (`zona_cobertura`, `nro_habilitacion`, `pais_destino_principal`) e impide que `permiso_exportacion` referencie solo a exportadores mediante FK nativa.
  - *Una tabla por subtipo sin supertipo:* duplicaria atributos comunes y obligaria a `comprobante` a tener 3 FKs opcionales o carecer de integridad referencial hacia `cliente`.
- **Ventajas de la elegida:** Cero nulos por subtipo, 3FN estricta, FK directa `comprobante -> cliente` y `permiso_exportacion -> cliente_exportador`, y disyuncion garantizada por el motor.

### 1.2 Claves Naturales vs. Claves Subrogadas
- **Claves naturales (`cuit_dom`):** `bodega(cuit)` y `empleado(cuit)` utilizan el CUIT de 11 digitos por ser identificador fiscal univoco, obligatorio y estable en Argentina.
- **Entidad debil:** `parcela` usa clave compuesta natural `(id_finca, nro_parcela)` porque no existe fuera de su finca.
- **Claves subrogadas (`GENERATED ALWAYS AS IDENTITY`):**
  - `localidad`: en Argentina distintas localidades comparten el mismo codigo postal de 4 digitos, por lo que `codigo_postal` no es unico; se usa `id_localidad` + `UNIQUE (nombre, provincia)`.
  - `vino`, `cliente`, `finca`, `sala_venta`, `comprobante`, `ingreso`, `transferencia`, `lote_uva`, `transportista`: claves enteras autogeneradas compactas para joins e indices, acompanadas de restricciones `UNIQUE` sobre sus claves de negocio (`(nombre, anada, volumen_ml)` en `vino`, `(tipo_documento, nro_documento)` en `cliente`, `(id_finca, nro_parcela, campana)` en `lote_uva`).

### 1.3 Tipos de Datos
- **Importes y salarios:** `NUMERIC(12,2)` / `NUMERIC(14,2)` — nunca `FLOAT`/`DOUBLE PRECISION`, evitando errores de redondeo binario.
- **Fechas y horas:** `DATE` para fechas operativas y `TIMESTAMPTZ` para auditoria (`auditoria_precio.fecha_hora`).
- **Estados y catalogos cerrados:** `ENUM` (`estado_documento`, `tipo_vino`, `tipo_cepa`, `tipo_cliente_enum`, `dia_semana`) y `DOMAIN` (`cuit_dom`, `porcentaje_corte_dom`) en lugar de texto libre.

### 1.4 Atributos Derivados
- **Almacenados con proteccion de triggers:** `comprobante.(subtotal, descuento, total)` y `renglon_comprobante.(precio_unitario, descuento_pct, subtotal)` se almacenan como foto historica inalterable ante futuros cambios de precio del vino o descuento del cliente. Se calculan automaticamente en `BEFORE/AFTER INSERT` (`trg_renglon_comp_before_insert`, `trg_renglon_comp_after`) usando `fn_descuento_cliente()` y `fn_total_comprobante()`.
- **Calculados al vuelo:** `stock_total` de un vino (`fn_stock_total_vino()` / `vw_stock_total_vino`) y `antiguedad` (`fn_antiguedad_anios()`).

### 1.5 Acciones Referenciales (`ON DELETE` / `ON UPDATE`)
- **`ON DELETE RESTRICT`:** en entidades con movimientos o historial (`vino`, `bodega`, `transportista`, `cliente`, `sala_venta`, `localidad`, `cepa`), cumpliendo `RN-14`.
- **`ON DELETE CASCADE`:** exclusivamente en entidades debiles o renglones que no existen sin su cabecera (`parcela` -> `finca`, `analisis_calidad` -> `lote_uva`, `renglon_*` -> cabecera, `composicion_vino` / `vino_maridaje` -> `vino`, `permiso_exportacion` -> `cliente_exportador`, subtipos -> `cliente`).
- **`ON UPDATE CASCADE`:** permite propagar actualizaciones si cambia una clave natural como `bodega.cuit`.

---

## 2. Guia: Donde va cada regla?

| Tipo de regla | Herramienta elegida | Ejemplo en Bodegas del Atuel |
| :--- | :--- | :--- |
| Valor valido de una sola fila | `NOT NULL`, `CHECK`, `DOMAIN` | `precio > 0`, `graduacion BETWEEN 5 AND 20`, `cuit_dom` |
| Existencia de dato relacionado | `FOREIGN KEY` (`RESTRICT`/`CASCADE`) | Renglon apunta a `vino`; `ON DELETE RESTRICT` en `bodega` |
| Unicidad | `PRIMARY KEY` / `UNIQUE` | `UNIQUE (id_finca, nro_parcela, campana)` en `lote_uva` |
| Depende de otras filas, tablas o fecha actual | `TRIGGER` (BEFORE, AFTER o CONSTRAINT DEFERRED) | Stock suficiente (`RN-09`), suma 100% (`RN-05`), `fecha_confeccion = CURRENT_DATE` (`RN-11`), auditoria (`RN-13`) |
| Calculo reutilizable | `FUNCTION` (`IMMUTABLE` / `STABLE`) | `fn_descuento_cliente()`, `fn_total_comprobante()`, `fn_stock_sala()` |
| Operacion multipaso todo-o-nada | `PROCEDURE` transaccional con `FOR UPDATE` | `sp_procesar_ingreso()`, `sp_procesar_transferencia()` |
| Presentacion y traduccion HTTP | API (`SQLSTATE` -> HTTP) y Front | Mapeo `P0001 -> 409`, `23514 -> 422` y mensajes visibles al usuario |

---

## 3. Tabla de Trazabilidad Regla -> Mecanismo -> Prueba

| Regla | Mecanismo en PostgreSQL | Caso de prueba (`db/tests/db_tests.sql` y `api/tests/test_api.py`) |
| :--- | :--- | :--- |
| **RN-01** | Columna `vino.precio` + `CHECK (precio > 0)` | `db_tests.sql` (precio = 0 -> `23514`) y `test_04` API (`-500 -> 422`) |
| **RN-02** | `sala_venta.id_localidad NOT NULL` + `localidad.encargado_regional` (3FN) | `db_tests.sql` (sala sin localidad -> `23502`) |
| **RN-03** | `empleado.id_sala NOT NULL` + `FK fk_empleado_sala` | `db_tests.sql` (empleado sin sala -> `23502`) |
| **RN-04** | `parcela.id_cepa NOT NULL` + `UNIQUE (id_finca, nro_parcela, campana)` | `db_tests.sql` (segunda cosecha misma campana -> `23505`) |
| **RN-05** | `CONSTRAINT TRIGGER trg_composicion_vino_suma_100 DEFERRABLE INITIALLY DEFERRED` | `db_tests.sql` (suma 70% -> `P0001`) y `test_03` API (suma 80% -> `409`) |
| **RN-06** | `fn_descuento_base_tipo()`, `fn_descuento_cliente()`, `trg_cliente_descuento_inicial`, `chk_cliente_descuento` | `db_tests.sql` (socio=10%, descuento 150 -> `23514`) |
| **RN-07** | `permiso_exportacion` + `CHECK (fecha_vencimiento > fecha_emision)` | `db_tests.sql` (vencimiento < emision -> `23514`) |
| **RN-08** | `fn_total_comprobante()` + `trg_renglon_comp_before_insert` + `trg_renglon_comp_after` | `db_tests.sql` y `test_07` API (totales calculados en BD) |
| **RN-09** | `trg_renglon_comp_before_insert` (`FOR UPDATE` en `stock_sala`) + `CHECK (cantidad >= 0)` | `db_tests.sql` y `test_06` API (`cantidad = 9999999 -> 409`) |
| **RN-10** | `ENUM estado_documento` + `trg_ingreso_control_estado` + `sp_procesar_ingreso()` | `db_tests.sql` (salto directo a procesado -> `P0001` y procesado OK) |
| **RN-11** | `trg_transferencia_control` + `sp_procesar_transferencia()` (`FOR UPDATE`) | `db_tests.sql` (fecha forzada/inmutable, falta stock deposito -> `P0001`) |
| **RN-12** | `trg_bloqueo_renglon_ingreso` y `trg_bloqueo_renglon_transferencia` | `db_tests.sql` y `test_08` API (agregar renglon tras terminar -> `409`) |
| **RN-13** | `trg_auditoria_precio_vino` (`AFTER UPDATE OF precio`) + tabla `auditoria_precio` | `db_tests.sql` y `test_05` API (historial de precios registrado) |
| **RN-14** | `ON DELETE RESTRICT` en `vino`, `bodega`, `transportista`, `cliente`, `sala_venta` | `db_tests.sql` (borrar vino/bodega/transportista con movimientos -> `23503`) |
| **RN-15** | `CHECK` positivos en precios, superficies, kg, cantidades y `graduacion BETWEEN 5 AND 20` | `db_tests.sql` (graduacion 25 -> `23514`) |
