# Guia Rapida de Estudio para la Defensa Oral — TPI Bodegas del Atuel

Esta guia resume todas las decisiones tecnicas, la arquitectura del sistema y las preguntas clave que suelen hacer los docentes en la mesa de examen para evaluar individualmente a cada integrante.

---

## 1. La "Regla de Oro" de la Catedra (Pregunta Obligatoria)

> **Pregunta docente:** *"Si un usuario malintencionado o un script externo inserta directamente una venta en la base de datos sin pasar por la API REST, ¿se rompe la consistencia de stock o los descuentos?"*
>
> **Respuesta:** **No.** La base de datos es la unica fuente de verdad y protege su propia integridad. La API REST y el frontend **no recalculan importes, no calculan descuentos ni descuentan stock por su cuenta**.
> - El descuento inicial se fija por trigger segun el tipo de cliente (`RN-06`).
> - La validacion de stock se hace con un trigger `BEFORE INSERT` con `FOR UPDATE` (`RN-09`).
> - El calculo de subtotales y totales lo ejecutan triggers usando `fn_total_comprobante` y `fn_descuento_cliente` (`RN-08`).
> - La API solo envia los datos crudos, invoca funciones/procedimientos y traduce los codigos `SQLSTATE` de PostgreSQL a respuestas HTTP.

---

## 2. Decisiones de Diseno y Normalizacion (Etapa 1)

### ¿Por que Supertipo + Subtipos en Clientes y no Tabla Unica?
- **Tabla unica:** generaria decenas de campos `NULL` (porque un socio no tiene `zona_cobertura` ni `pais_destino`), violando la limpieza del modelo, y no permitiria crear una clave foranea estricta desde `permiso_exportacion` hacia solo los exportadores.
- **Una tabla por subtipo sin supertipo:** obligaria a que la tabla `comprobante` tenga tres claves foraneas opcionales o pierda la integridad referencial.
- **Nuestra solucion:** `cliente` como supertipo (datos comunes + `descuento_pct`) y 3 tablas hijas (`cliente_socio`, `cliente_distribuidor`, `cliente_exportador`) vinculadas por `(id_cliente, tipo_cliente)` garantizando **disyuncion total** (un socio jamas puede figurar como distribuidor).

### ¿Por que no se uso `codigo_postal` como Clave Primaria en `localidad`?
En Argentina, el codigo postal tradicional de 4 digitos se repite entre varias localidades vecinas. Por eso se creo la clave subrogada `id_localidad` y se agrego la restriccion `UNIQUE (nombre, provincia)`.

### ¿Por que la entidad `parcela` es debil?
Una parcela se identifica con un numero relativo dentro de una finca (Parcela 1, Parcela 2). No tiene existencia ni significado independiente sin la finca a la que pertenece. Su clave primaria es compuesta: `(id_finca, nro_parcela)`.

### ¿Por que `encargado_regional` esta en `localidad` y no en `sala_venta`? (3FN)
Por regla de negocio (`RN-02`), cada localidad tiene un unico encargado regional que supervisa todas las salas de esa localidad. Si pusieramos `encargado_regional` en `sala_venta`, existiria la dependencia transitiva:
`id_sala -> id_localidad -> encargado_regional`
Al colocarlo en `localidad`, el esquema queda estrictamente en **Tercera Forma Normal (3FN)**.

---

## 3. Integridad y Logica en PostgreSQL (Etapa 2)

### ¿Por que `RN-05` (porcentajes de corte suman 100) usa un `CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED`?
Si fuera un `CHECK` a nivel de fila o un trigger normal inmediato, al insertar la primera cepa de un vino (ej. Malbec 85%), fallaria instantaneamente porque 85 != 100.
Al declararlo **diferido (`DEFERRED`)**, PostgreSQL permite insertar las distintas cepas a lo largo de la transaccion y **recien valida que la suma sea exactamente 100 al momento del `COMMIT`**.

### ¿Por que esta PROHIBIDO usar `CURRENT_DATE` dentro de una restriccion `CHECK`?
`CURRENT_DATE` no es una funcion deterministica (su resultado varia cada dia). Si se usa en un `CHECK`, al restaurar un backup con `pg_dump` dentro de 2 anios, la validacion se evaluaria con la fecha futura y haria fallar la restauracion de datos historicos validos. Por eso, las reglas dependientes de fechas se controlan mediante **triggers** o valores `DEFAULT`.

### ¿Como se resolvio la trampa de `sp_procesar_transferencia` (Anexo A.6)?
En el ejemplo base del anexo, si un vino de la transferencia no existia en `stock_deposito`, el `UPDATE` simplemente no afectaba filas y la transferencia pasaba a procesada sin error ni stock.
**Nuestra correccion:** el procedimiento bloquea primero las filas con `FOR UPDATE` ordenadas por `cod_vino` (evitando deadlocks) y realiza una consulta previa con `LEFT JOIN` para verificar que **todos los vinos existan en el deposito y tengan cantidad suficiente**. Si alguno falta, dispara `RAISE EXCEPTION` y revierte la transaccion entera.

---

## 4. Demostracion de Concurrencia (Pregunta Clasica)

> **Pregunta docente:** *"Explique que ocurre cuando dos personas quieren comprar la ultima botella de vino al mismo tiempo."*

- **Bajo nivel de aislamiento `READ COMMITTED` sin bloqueo:** Ambas transacciones leen `cantidad = 1` simultaneamente antes de que la otra confirme. Ambas proceden y se produce un sobregiro o error de constraint tardio.
- **Nuestra solucion:** Dentro del trigger `BEFORE INSERT` de renglon se ejecuta:
  ```sql
  SELECT cantidad FROM stock_sala WHERE id_sala = ... AND cod_vino = ... FOR UPDATE;
  ```
  La primera sesion adquiere un bloqueo exclusivo sobre esa fila. La segunda sesion **queda pausada en espera**. Cuando la primera confirma (`COMMIT`), la fila pasa a tener `cantidad = 0`. Al desbloquearse la segunda sesion, lee el nuevo valor `0` y aborta inmediatamente con:
  `ERROR: Stock insuficiente del vino X en la sala Y (RN-09)`.

---

## 5. Rendimiento e Indices (Etapa 4)

### ¿Por que PostgreSQL no usa siempre un indice existente?
El optimizador es basado en costos (`Cost-Based Optimizer`). Si una consulta pide un rango que abarca el 60% o 70% de la tabla (baja selectividad), es mas eficiente leer secuencialmente los bloques del disco (`Seq Scan`) que leer el indice y hacer miles de saltos aleatorios al heap (`Index Scan`). Tambien ocurre si no se ejecuta `ANALYZE` y las estadisticas de la tabla estan desactualizadas.

### ¿Que tipo de indices creamos y por que?
1. **Compuesto con `INCLUDE` (`idx_comprobante_sala_fecha`):** `(id_sala, fecha) INCLUDE (total)`. Permite resolver las ventas de un trimestre agrupadas por sala mediante **Index-Only Scan** sin tocar el disco de la tabla.
2. **Parcial (`idx_transferencia_pendientes`):** `WHERE estado <> 'procesado'`. Solo indexa el ~10% de documentos pendientes, ocupando minimo espacio en memoria.
3. **Sobre Clave Foranea (`idx_renglon_comp_vino`):** PostgreSQL **no indexa claves foraneas por defecto**. Sin este indice, agrupar las ventas por vino para armar el ranking obliga a recorrer 500.000 filas con `Seq Scan`.
4. **BRIN (`idx_comprobante_fecha_brin`):** Ocupa kilobytes en lugar de megabytes aprovechando que los comprobantes se guardan ordenados por fecha en el disco.

---

## 6. Seguridad y API REST (Etapas 2 y 6)

### ¿Con que rol se conecta la API?
Con el rol `app_rw`. Se aplico `REVOKE ALL ON SCHEMA public FROM PUBLIC;`. La API **no es duena de la base ni superusuario**: solo tiene permisos de `SELECT, INSERT, UPDATE, DELETE` en tablas operativas y `EXECUTE` en rutinas. No puede hacer `DROP TABLE`, ni modificar el esquema, ni alterar la tabla de auditoria.

### ¿Como se traduce un error de la base a HTTP?
La API captura los errores nativos de `psycopg` y lee el codigo `SQLSTATE`:
- `23505` (UNIQUE violado) -> `409 Conflict`
- `23514` / `23502` (CHECK o NOT NULL violado) -> `422 Unprocessable Entity`
- `P0001` (Trigger `RAISE EXCEPTION`) -> `409 Conflict` propagando el texto literal de la regla (ej. `RN-09`).
- `40001` / `40P01` (Deadlock / fallo de serializacion) -> `503 Service Unavailable` con cabecera `Retry-After: 1`.

### ¿Como se demuestra que no hay Inyeccion SQL?
En `api/tests/test_api.py` (test 10) se envia el parametro `q = "' OR '1'='1' --"`. Como se usa el driver nativo con tuplas de parametros `%s`, el motor de PostgreSQL trata las comillas y guiones como una simple cadena de texto literal a buscar, devolviendo 0 resultados sin romper la consulta ni exponer datos.
