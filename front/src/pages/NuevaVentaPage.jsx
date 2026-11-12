import { useEffect, useState } from "react";
import { api } from "../api/client";

export default function NuevaVentaPage({ catalogos }) {
  const [clientes, setClientes] = useState([]);
  const [vinos, setVinos] = useState([]);
  const [idCliente, setIdCliente] = useState("");
  const [idSala, setIdSala] = useState("");
  const [renglones, setRenglones] = useState([{ cod_vino: "", cantidad: "1" }]);
  const [comprobante, setComprobante] = useState(null);
  const [error, setError] = useState("");

  useEffect(() => {
    async function init() {
      try {
        const [cliRes, vinRes] = await Promise.all([
          api.listClientes({ page: 1, page_size: 50 }),
          api.listVinos({ page: 1, page_size: 50 }),
        ]);
        setClientes(cliRes.items);
        setVinos(vinRes.items);
        if (cliRes.items.length) setIdCliente(String(cliRes.items[0].id_cliente));
        if (vinRes.items.length) setRenglones([{ cod_vino: String(vinRes.items[0].cod_vino), cantidad: "1" }]);
      } catch (e) {
        setError(e.message);
      }
    }
    init();
  }, []);

  useEffect(() => {
    if (catalogos.salas.length && !idSala) {
      setIdSala(String(catalogos.salas[0].id_sala));
    }
  }, [catalogos]);

  function addRenglon() {
    const first = vinos[0]?.cod_vino || "";
    setRenglones([...renglones, { cod_vino: String(first), cantidad: "1" }]);
  }

  function updateRenglon(idx, field, val) {
    setRenglones(renglones.map((r, i) => (i === idx ? { ...r, [field]: val } : r)));
  }

  function removeRenglon(idx) {
    setRenglones(renglones.filter((_, i) => i !== idx));
  }

  async function registrarVenta(e) {
    e.preventDefault();
    setError("");
    setComprobante(null);
    try {
      // No se calculan precios, descuentos ni stock en el front: todo lo calcula la base de datos.
      const res = await api.createComprobante({
        id_cliente: Number(idCliente),
        id_sala: Number(idSala),
        renglones: renglones.map((r) => ({
          cod_vino: Number(r.cod_vino),
          cantidad: Number(r.cantidad),
        })),
      });
      setComprobante(res);
    } catch (err) {
      setError(err.message);
    }
  }

  return (
    <div className="card">
      <h2>Nueva Venta (Comprobante)</h2>
      <p>Los precios, descuentos por tipo de cliente, validacion de stock y totales son calculados integramente en PostgreSQL.</p>
      {error && <div className="alert-error">{error}</div>}

      <form onSubmit={registrarVenta}>
        <div className="row">
          <div className="field">
            <label>Cliente</label>
            <select value={idCliente} onChange={(e) => setIdCliente(e.target.value)}>
              {clientes.map((c) => (
                <option key={c.id_cliente} value={c.id_cliente}>
                  #{c.id_cliente} — {c.nombre_razon_social} ({c.tipo_cliente})
                </option>
              ))}
            </select>
          </div>
          <div className="field">
            <label>Sala de venta</label>
            <select value={idSala} onChange={(e) => setIdSala(e.target.value)}>
              {catalogos.salas.map((s) => (
                <option key={s.id_sala} value={s.id_sala}>
                  Sala #{s.id_sala} — {s.direccion} ({s.localidad})
                </option>
              ))}
            </select>
          </div>
        </div>

        <div style={{ marginTop: "1rem" }}>
          <div className="row" style={{ justifyContent: "space-between" }}>
            <h4>Renglones</h4>
            <button type="button" className="secondary" onClick={addRenglon}>+ Agregar vino</button>
          </div>
          {renglones.map((r, idx) => (
            <div className="row" key={idx} style={{ marginTop: "0.5rem" }}>
              <div className="field">
                <label>Vino</label>
                <select value={r.cod_vino} onChange={(e) => updateRenglon(idx, "cod_vino", e.target.value)}>
                  {vinos.map((v) => (
                    <option key={v.cod_vino} value={v.cod_vino}>
                      #{v.cod_vino} {v.nombre} ({v.anada}, {v.volumen_ml}ml) — ${Number(v.precio).toLocaleString("es-AR")}
                    </option>
                  ))}
                </select>
              </div>
              <div className="field" style={{ maxWidth: "160px" }}>
                <label>Cantidad</label>
                <input
                  type="number"
                  value={r.cantidad}
                  onChange={(e) => updateRenglon(idx, "cantidad", e.target.value)}
                />
              </div>
              {renglones.length > 1 && (
                <button type="button" className="secondary" onClick={() => removeRenglon(idx)}>Quitar</button>
              )}
            </div>
          ))}
        </div>

        <div style={{ marginTop: "1.25rem" }}>
          <button type="submit" className="primary">Confirmar venta</button>
        </div>
      </form>

      {comprobante && (
        <div className="alert-ok" style={{ marginTop: "1rem" }}>
          <h3>Comprobante #{comprobante.nro_comprobante} emitido</h3>
          <p>
            <strong>Cliente:</strong> {comprobante.cliente} ({comprobante.tipo_cliente}) |{" "}
            <strong>Sala:</strong> {comprobante.sala} | <strong>Fecha:</strong> {comprobante.fecha}
          </p>
          <table>
            <thead>
              <tr>
                <th>Vino</th>
                <th>Cantidad</th>
                <th>Precio unit.</th>
                <th>Descuento</th>
                <th>Subtotal</th>
              </tr>
            </thead>
            <tbody>
              {comprobante.renglones.map((rg) => (
                <tr key={rg.cod_vino}>
                  <td>{rg.vino}</td>
                  <td>{rg.cantidad}</td>
                  <td>${Number(rg.precio_unitario).toLocaleString("es-AR")}</td>
                  <td>{rg.descuento_pct}%</td>
                  <td>${Number(rg.subtotal).toLocaleString("es-AR")}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <p style={{ marginTop: "0.75rem" }}>
            <strong>Subtotal bruto:</strong> ${Number(comprobante.subtotal).toLocaleString("es-AR")} |{" "}
            <strong>Descuento:</strong> -${Number(comprobante.descuento).toLocaleString("es-AR")} |{" "}
            <strong>Total calculado por BD:</strong> ${Number(comprobante.total).toLocaleString("es-AR")}
          </p>
        </div>
      )}
    </div>
  );
}
