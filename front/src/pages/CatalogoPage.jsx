import { useEffect, useState } from "react";
import { api } from "../api/client";

export default function CatalogoPage({ catalogos, onEditVino }) {
  const [filters, setFilters] = useState({ tipo: "", cepa: "", bodega: "", anada: "", q: "" });
  const [page, setPage] = useState(1);
  const [data, setData] = useState({ items: [], total: 0, page_size: 10 });
  const [detalle, setDetalle] = useState(null);
  const [error, setError] = useState("");

  async function cargar(p = page) {
    setError("");
    try {
      const res = await api.listVinos({ ...filters, page: p, page_size: 10 });
      setData(res);
    } catch (e) {
      setError(e.message);
    }
  }

  useEffect(() => {
    cargar(1);
    setPage(1);
  }, [filters.tipo, filters.cepa, filters.bodega, filters.anada, filters.q]);

  async function verDetalle(cod) {
    setError("");
    try {
      const d = await api.getVino(cod);
      setDetalle(d);
    } catch (e) {
      setError(e.message);
    }
  }

  const totalPages = Math.max(1, Math.ceil(data.total / 10));

  return (
    <div>
      <div className="card">
        <h2>Catalogo de Vinos</h2>
        {error && <div className="alert-error">{error}</div>}
        <div className="row">
          <div className="field">
            <label>Nombre</label>
            <input
              placeholder="Buscar por nombre..."
              value={filters.q}
              onChange={(e) => setFilters({ ...filters, q: e.target.value })}
            />
          </div>
          <div className="field">
            <label>Tipo</label>
            <select value={filters.tipo} onChange={(e) => setFilters({ ...filters, tipo: e.target.value })}>
              <option value="">Todos</option>
              <option value="tinto">Tinto</option>
              <option value="blanco">Blanco</option>
              <option value="rosado">Rosado</option>
              <option value="espumante">Espumante</option>
            </select>
          </div>
          <div className="field">
            <label>Cepa</label>
            <select value={filters.cepa} onChange={(e) => setFilters({ ...filters, cepa: e.target.value })}>
              <option value="">Todas</option>
              {catalogos.cepas.map((c) => (
                <option key={c.id_cepa} value={c.id_cepa}>
                  {c.nombre}
                </option>
              ))}
            </select>
          </div>
          <div className="field">
            <label>Bodega</label>
            <select value={filters.bodega} onChange={(e) => setFilters({ ...filters, bodega: e.target.value })}>
              <option value="">Todas</option>
              {catalogos.bodegas.map((b) => (
                <option key={b.cuit} value={b.cuit}>
                  {b.razon_social}
                </option>
              ))}
            </select>
          </div>
          <div className="field">
            <label>Anada</label>
            <input
              type="number"
              placeholder="Ej. 2021"
              value={filters.anada}
              onChange={(e) => setFilters({ ...filters, anada: e.target.value })}
            />
          </div>
        </div>

        <table>
          <thead>
            <tr>
              <th>Cod.</th>
              <th>Nombre</th>
              <th>Tipo</th>
              <th>Anada</th>
              <th>Vol.</th>
              <th>Bodega</th>
              <th>Precio</th>
              <th>Stock Total</th>
              <th>Acciones</th>
            </tr>
          </thead>
          <tbody>
            {data.items.map((v) => (
              <tr key={v.cod_vino}>
                <td>{v.cod_vino}</td>
                <td>{v.nombre}</td>
                <td><span className="badge">{v.tipo}</span></td>
                <td>{v.anada}</td>
                <td>{v.volumen_ml} ml</td>
                <td>{v.bodega}</td>
                <td>${Number(v.precio).toLocaleString("es-AR")}</td>
                <td>{v.stock_total}</td>
                <td className="row">
                  <button className="secondary" onClick={() => verDetalle(v.cod_vino)}>Detalle</button>
                  <button className="secondary" onClick={() => onEditVino(v)}>Editar</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        <div className="row" style={{ marginTop: "0.75rem", justifyContent: "space-between" }}>
          <span>Total: {data.total} vinos (pagina {page} de {totalPages})</span>
          <div className="row">
            <button
              className="secondary"
              disabled={page <= 1}
              onClick={() => {
                const p = page - 1;
                setPage(p);
                cargar(p);
              }}
            >
              Anterior
            </button>
            <button
              className="secondary"
              disabled={page >= totalPages}
              onClick={() => {
                const p = page + 1;
                setPage(p);
                cargar(p);
              }}
            >
              Siguiente
            </button>
          </div>
        </div>
      </div>

      {detalle && (
        <div className="card">
          <div className="row" style={{ justifyContent: "space-between" }}>
            <h3>Detalle: {detalle.nombre} ({detalle.anada}, {detalle.volumen_ml} ml)</h3>
            <button className="secondary" onClick={() => setDetalle(null)}>Cerrar</button>
          </div>
          <p>
            <strong>Bodega:</strong> {detalle.bodega} | <strong>Graduacion:</strong> {detalle.graduacion}° |{" "}
            <strong>Precio:</strong> ${Number(detalle.precio).toLocaleString("es-AR")} |{" "}
            <strong>Stock total:</strong> {detalle.stock_total}
          </p>
          <div className="grid-2">
            <div>
              <h4>Composicion de cepas</h4>
              <ul>
                {detalle.composiciones.map((c) => (
                  <li key={c.id_cepa}>{c.cepa} ({c.tipo}): {c.porcentaje}%</li>
                ))}
              </ul>
            </div>
            <div>
              <h4>Maridajes recomendados</h4>
              {detalle.maridajes.length === 0 ? (
                <p>Sin maridajes cargados.</p>
              ) : (
                <ul>
                  {detalle.maridajes.map((m) => (
                    <li key={m.id_maridaje}>{m.nombre} — {m.temperatura_servicio} °C</li>
                  ))}
                </ul>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
