# Esquema Relacional y Verificacion de Normalizacion (3FN)

## 1. Esquema Relacional

- **localidad** (<u>id_localidad</u>, codigo_postal, nombre, provincia, encargado_regional)
- **sala_venta** (<u>id_sala</u>, calle, numero, dia_cierre, *id_localidad*)
- **empleado** (<u>cuit</u>, nombre, fecha_ingreso, salario, *id_sala*)
- **finca** (<u>id_finca</u>, nombre, superficie_ha, departamento, provincia)
- **cepa** (<u>id_cepa</u>, nombre, tipo)
- **parcela** (<u>*id_finca*, nro_parcela</u>, superficie_ha, anio_plantacion, *id_cepa*)
- **bodega** (<u>cuit</u>, razon_social, domicilio)
- **lote_uva** (<u>nro_lote</u>, *id_finca*, *nro_parcela*, campana, fecha_cosecha, kg_cosechados, *cuit_bodega*)
- **analisis_calidad** (<u>id_analisis</u>, *nro_lote*, fecha, grado_brix, ph, acidez_total)
- **vino** (<u>cod_vino</u>, nombre, tipo, anada, volumen_ml, graduacion, precio, *cuit_bodega*)
- **composicion_vino** (<u>*cod_vino*, *id_cepa*</u>, porcentaje)
- **maridaje** (<u>id_maridaje</u>, nombre, temperatura_servicio)
- **vino_maridaje** (<u>*cod_vino*, *id_maridaje*</u>)
- **cliente** (<u>id_cliente</u>, tipo_cliente, nombre_razon_social, tipo_documento, nro_documento, direccion, *id_localidad*, fecha_alta, descuento_pct)
- **cliente_socio** (<u>*id_cliente*</u>, tipo_cliente)
- **cliente_distribuidor** (<u>*id_cliente*</u>, tipo_cliente, zona_cobertura, nro_habilitacion)
- **cliente_exportador** (<u>*id_cliente*</u>, tipo_cliente, pais_destino_principal)
- **permiso_exportacion** (<u>codigo</u>, *id_exportador*, fecha_emision, fecha_vencimiento)
- **comprobante** (<u>nro_comprobante</u>, fecha, *id_cliente*, *id_sala*, subtotal, descuento, total)
- **renglon_comprobante** (<u>*nro_comprobante*, *cod_vino*</u>, cantidad, precio_unitario, descuento_pct, subtotal)
- **transportista** (<u>cod_transportista</u>, razon_social, cuit, email, telefono, domicilio)
- **transportista_localidad** (<u>*cod_transportista*, *id_localidad*</u>)
- **stock_deposito** (<u>*cod_vino*</u>, cantidad)
- **stock_sala** (<u>*id_sala*, *cod_vino*</u>, cantidad)
- **ingreso** (<u>cod_ingreso</u>, fecha, estado, *cod_transportista*, *cuit_bodega*)
- **renglon_ingreso** (<u>*cod_ingreso*, *cod_vino*</u>, cantidad)
- **transferencia** (<u>nro_solicitud</u>, *id_sala*, fecha_confeccion, estado)
- **renglon_transferencia** (<u>*nro_solicitud*, *cod_vino*</u>, cantidad)
- **auditoria_precio** (<u>id_auditoria</u>, *cod_vino*, precio_anterior, precio_nuevo, fecha_hora, usuario)

---

## 2. Verificacion hasta Tercera Forma Normal (3FN)

1. **1FN (Atomicidad):** Todos los atributos son atomicos; no hay grupos repetitivos ni listas multivaluadas (las composiciones de cepas, maridajes, coberturas de transportistas, permisos y renglones se modelan en tablas independientes).
2. **2FN (Sin dependencias parciales):** En todas las tablas con clave primaria compuesta (`parcela`, `composicion_vino`, `vino_maridaje`, `renglon_comprobante`, `transportista_localidad`, `stock_sala`, `renglon_ingreso`, `renglon_transferencia`), cada atributo no primo depende funcionalmente de la clave completa:
   - En `parcela`: `(id_finca, nro_parcela) -> superficie_ha, anio_plantacion, id_cepa`.
   - En `composicion_vino`: `(cod_vino, id_cepa) -> porcentaje`.
   - En `renglon_comprobante`: `(nro_comprobante, cod_vino) -> cantidad, precio_unitario, descuento_pct, subtotal`.
   - En `stock_sala`: `(id_sala, cod_vino) -> cantidad`.
3. **3FN (Sin dependencias transitivas entre atributos no primos):**
   - **Encargado regional (`RN-02`):** `id_localidad -> encargado_regional` vive en `localidad` y **no** en `sala_venta`. Si hubiera estado en `sala_venta`, existiria la dependencia transitiva `id_sala -> id_localidad -> encargado_regional`.
   - **Datos de bodega y vino:** `cuit_bodega -> razon_social, domicilio` vive en `bodega`, evitando transitividad en `vino`, `lote_uva` o `ingreso`.
   - **Precio historico en renglon vs catalogo:** `vino.precio` es el precio vigente actual; `renglon_comprobante.precio_unitario` es el precio historico congelado al momento de la venta (no depende transitivamente de `cod_vino` porque el precio de `vino` puede cambiar con el tiempo sin alterar ventas pasadas).
   - **Descuento en `cliente`:** `descuento_pct` es atributo propio del cliente (iniciado segun su tipo y editable por regla de negocio como en `U6`), no un atributo redundante de otro no primo.
