# Informe de Indices y Rendimiento — Etapa 4

## 1. Indices implementados (`db/migrations/008_indices.sql`)
1. **`idx_comprobante_sala_fecha` (`comprobante (id_sala, fecha) INCLUDE (total)`) — Compuesto + Covering:**
   - *Orden de columnas:* `id_sala` primero (predicado de igualdad en `S11` y `GROUP BY` en `S8`) y `fecha` segundo (predicado de rango en ultimo trimestre). `INCLUDE (total)` permite resolver `SUM(total)` mediante *Index-Only Scan* sin acceder al heap.
2. **`idx_transferencia_pendientes` (`transferencia (id_sala, fecha_confeccion) WHERE estado <> 'procesado'`) — Parcial:**
   - *Justificacion:* Solo ~15 % de las transferencias estan pendientes; indexar unicamente `estado <> 'procesado'` mantiene el indice pequeno y acelera `S5` y el tablero operativo.
3. **`idx_renglon_comp_vino` (`renglon_comprobante (cod_vino) INCLUDE (cantidad)`) — Sobre FK:**
   - *Justificacion:* PostgreSQL no indexa claves foraneas automaticamente; la PK de `renglon_comprobante` es `(nro_comprobante, cod_vino)`, inutil para filtrar o agrupar por `cod_vino` (`S1`, `S2`, `U5`).
4. **`idx_comprobante_cliente_fecha` (`comprobante (id_cliente, fecha)`) — Sobre FK:**
   - *Justificacion:* Acelera busquedas por cliente en `S12`, `D1` y `D4`.
5. **`idx_comprobante_fecha_brin` (`comprobante USING BRIN (fecha)`) — Tipo BRIN:**
   - *Justificacion:* Los comprobantes se cargan en orden cronologico; un indice BRIN almacena solo min/max por bloque de paginas, ocupando kilobytes frente a megabytes de un B-Tree.
6. **`idx_vino_nombre_lower` (`vino (lower(nombre))`) — Expresion:**
   - *Justificacion:* Soporta busquedas insensibles a mayusculas del catalogo en la API (`WHERE lower(v.nombre) LIKE ...`).
7. **`idx_renglon_transf_vino` (`renglon_transferencia (cod_vino)`) — Sobre FK:**
   - *Justificacion:* Acelera `S4` (transferencias recientes de un vino determinado).

---

## 2. Protocolo de Medicion (`EXPLAIN (ANALYZE, BUFFERS)`)

Ejecutar en `psql` tras correr `seed.py --scale full` **antes** y **despues** de aplicar `008_indices.sql` (ejecutando `ANALYZE;` en ambos casos):

```sql
ANALYZE;

-- Consulta S1 (Top 10 vinos mas vendidos sobre 500k+ renglones)
EXPLAIN (ANALYZE, BUFFERS)
SELECT v.cod_vino, v.nombre, SUM(rc.cantidad) AS botellas_vendidas
FROM vino v
JOIN renglon_comprobante rc ON rc.cod_vino = v.cod_vino
GROUP BY v.cod_vino, v.nombre
ORDER BY botellas_vendidas DESC LIMIT 10;

-- Consulta S4 (Top 5 salas que solicitaron vino 1 en ultimos 15 dias)
EXPLAIN (ANALYZE, BUFFERS)
SELECT sv.id_sala, SUM(rt.cantidad) AS cantidad_solicitada
FROM transferencia t
JOIN renglon_transferencia rt ON rt.nro_solicitud = t.nro_solicitud
JOIN sala_venta sv ON sv.id_sala = t.id_sala
WHERE rt.cod_vino = 1 AND t.fecha_confeccion >= (CURRENT_DATE - INTERVAL '15 days')
GROUP BY sv.id_sala ORDER BY cantidad_solicitada DESC LIMIT 5;

-- Consulta S8 (Ventas por sala en ultimo trimestre sobre 150k comprobantes)
EXPLAIN (ANALYZE, BUFFERS)
SELECT sv.id_sala, COALESCE(SUM(c.total), 0) AS monto_total
FROM sala_venta sv
LEFT JOIN comprobante c ON c.id_sala = sv.id_sala AND c.fecha >= (CURRENT_DATE - INTERVAL '3 months')
GROUP BY sv.id_sala ORDER BY monto_total DESC;
```

### Tabla comparativa (completar con valores medidos en entorno local)
| Consulta | Tiempo ANTES (ms) | Plan ANTES | Tiempo DESPUES (ms) | Plan DESPUES | Buffers leidos (Antes vs Despues) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **S1** | *(medir)* | `Seq Scan on renglon_comprobante` | *(medir)* | `Index Only Scan` / menor costo | *(medir)* |
| **S4** | *(medir)* | `Seq Scan on renglon_transferencia` | *(medir)* | `Bitmap Index Scan on idx_renglon_transf_vino` | *(medir)* |
| **S8** | *(medir)* | `Seq Scan on comprobante` | *(medir)* | `Index Only Scan on idx_comprobante_sala_fecha` / `Bitmap Index Scan (BRIN)` | *(medir)* |

---

## 3. Indice evaluado y descartado
- **Indice descartado:** `CREATE INDEX idx_vino_tipo ON vino (tipo);`
- **Motivo:** La columna `tipo` posee solo 4 valores posibles (`tinto`, `blanco`, `rosado`, `espumante`) en una tabla pequena (~350 filas). Su selectividad es muy baja (~25 % de la tabla por valor), por lo que PostgreSQL prefiere un `Seq Scan` antes que leer el indice y saltar al heap.

## 4. Costo de escritura
- Todo indice adicional acelera lecturas pero penaliza `INSERT`/`UPDATE`/`DELETE` porque cada operacion debe actualizar las estructuras B-Tree/BRIN.
- Para medirlo: ejecutar `seed.py --scale full` **sin** `008_indices.sql` (y crear indices al final) vs con los indices creados previamente, registrando la diferencia de segundos en la carga de `comprobante` y `renglon_comprobante`.

## 5. Caso en que el planificador NO usa un indice existente
- Al filtrar `comprobante` por un rango amplio (ej. ultimos 4 anios sobre 5.7 anios totales: > 70 % de las filas), aunque exista `idx_comprobante_fecha_brin`, el optimizador basado en costos elige `Seq Scan` porque leer secuencialmente toda la tabla resulta mas barato que acceder via indice. Lo mismo ocurre si se omite `ANALYZE` tras una carga masiva y las estadisticas de `pg_statistic` quedan desactualizadas.
