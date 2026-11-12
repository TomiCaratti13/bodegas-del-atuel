# Carga Masiva de Datos — Etapa 3

## Catalogos reales (CSV)
- `cepas.csv`: 12 cepas reales (7 tintas, 5 blancas) segun Anexo B.1.
- `maridajes.csv`: 8 maridajes con temperatura sugerida segun Anexo B.2.
- `localidades_mendoza.csv`: 18 departamentos y localidades de Mendoza segun Anexo B.3.

## Requisitos
```bash
pip install -r db/seed/requirements.txt
```

## Ejecucion (semilla fija `SEED = 2026`)
1. **Carga completa local** (20.000 clientes, 150.000 comprobantes, ~525.000 renglones):
   ```bash
   python db/seed/seed.py --scale full
   ```
2. **Carga reducida para capa gratuita en la nube** (> 10.000 renglones):
   ```bash
   python db/seed/seed.py --scale cloud
   ```
3. **Comparativa fila por fila vs COPY por lotes**:
   ```bash
   python db/seed/seed.py --benchmark
   ```

## Estrategia frente a los triggers
Durante la carga historica masiva de `comprobante` y `renglon_comprobante`, se deshabilitan temporalmente los triggers de usuario (`ALTER TABLE ... DISABLE TRIGGER USER`), se insertan datos matematicamente consistentes con `COPY` en orden topologico de dependencias FK, se rehabilitan los triggers y se ejecutan consultas de control (conteos, stock >= 0, cortes = 100%, totales consistentes).

## Volcado y restauracion (`pg_dump`)
```bash
# Generar volcado comprimido
pg_dump -h localhost -U bodegas_owner -d bodegas_atuel | gzip > dump_completo.sql.gz

# Restaurar en una base limpia
gunzip -c dump_completo.sql.gz | psql -h localhost -U bodegas_owner -d bodegas_atuel_restaurada
```
