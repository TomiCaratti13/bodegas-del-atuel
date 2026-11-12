# Demostracion de Concurrencia: La Ultima Botella (Etapa 2)

## Escenario
Dos sesiones simultaneas (`psql` Terminal A y Terminal B) intentan vender la ultima botella disponible (`cantidad = 1`) de un vino en la sala 1 bajo el nivel de aislamiento por defecto de PostgreSQL (`READ COMMITTED`).

---

## Caso 1: SIN bloqueo explicito (`SELECT ...` sin `FOR UPDATE`)
1. Ambas sesiones inician `BEGIN;`.
2. **Sesion A** consulta `SELECT cantidad FROM stock_sala WHERE id_sala = 1 AND cod_vino = 1;` -> lee `1`.
3. **Sesion B** consulta `SELECT cantidad FROM stock_sala WHERE id_sala = 1 AND cod_vino = 1;` -> lee `1` (porque A aun no hizo `COMMIT`, y `READ COMMITTED` lee la ultima version confirmada).
4. Ambas aplicaciones creen que hay stock disponible.
5. **Sesion A** ejecuta `UPDATE stock_sala SET cantidad = cantidad - 1 ...; COMMIT;` -> stock pasa a `0`.
6. **Sesion B** ejecuta `UPDATE stock_sala SET cantidad = cantidad - 1 ...;` -> en `READ COMMITTED`, PostgreSQL re-evalua la fila actualizada (`0 - 1 = -1`) y recien falla por el `CHECK (cantidad >= 0)` (o si no existiera ese check ni validacion atomica, produciria sobregiro / doble venta).

---

## Caso 2: CON bloqueo pesimista (`SELECT ... FOR UPDATE`, implementado en `trg_fn_renglon_comp_validar_y_calcular`)
En el trigger real `trg_renglon_comp_before_insert`, la verificacion ejecuta:
```sql
SELECT ss.cantidad INTO v_stock
FROM stock_sala ss
WHERE ss.id_sala = v_sala AND ss.cod_vino = NEW.cod_vino
FOR UPDATE;
```

### Pasos reproducibles en dos terminales `psql`
Preparar stock = 1 (dentro de prueba controlada):
```sql
UPDATE stock_sala SET cantidad = 1 WHERE id_sala = 1 AND cod_vino = 1;
```

| Paso | Sesion A | Sesion B |
| :--- | :--- | :--- |
| 1 | `BEGIN;` | `BEGIN;` |
| 2 | `INSERT INTO comprobante (id_cliente, id_sala) VALUES (1, 1) RETURNING nro_comprobante;` (ej. `150001`) | `INSERT INTO comprobante (id_cliente, id_sala) VALUES (2, 1) RETURNING nro_comprobante;` (ej. `150002`) |
| 3 | `INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (150001, 1, 1);` -> **adquiere lock de fila en `stock_sala` y descuenta a 0.** | |
| 4 | | `INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (150002, 1, 1);` -> **queda bloqueada esperando a Sesion A.** |
| 5 | `COMMIT;` | **Se desbloquea inmediatamente**, lee `cantidad = 0` actualizado y aborta con `ERROR: Stock insuficiente del vino 1 en la sala 1 (disponible: 0, solicitado: 1) (RN-09)`. |
| 6 | | `ROLLBACK;` |

## Conclusion
Con `READ COMMITTED` + `SELECT ... FOR UPDATE` sobre `stock_sala`, PostgreSQL serializa el acceso a la fila critica sin necesidad de elevar toda la base a `SERIALIZABLE`, evitando condiciones de carrera y garantizando que nunca se venda la misma botella dos veces.

*(Adjuntar capturas de ambas terminales `psql` al completar la ejecucion local).*
