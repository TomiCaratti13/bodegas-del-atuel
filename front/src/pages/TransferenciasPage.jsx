import { useEffect, useState } from "react";
import { api } from "../api/client";

export default function TransferenciasPage({ catalogos }) {
  const [lista, setLista] = useState([]);
  const [vinos, setVinos] = useState([]);
  const [idSala, setIdSala] = useState("");
  const [actual, setActual] = useState(null);
  const [codVino, setCodVino] = useState("");
  const [cantidad, setCantidad] = useState("5");
  const [error, setError] = useState("");
  const [okMsg, setOkMsg] = useState("");

  async function cargarLista() {
    try {
      const [trRes, vinRes] = await Promise.all([
        api.listTransferencias(1),
        api.listVinos({ page: 1, page_size: 50 }),
      ]);
      setLista(trRes.items);
      setVinos(vinRes.items);
      if (vinRes.items.length && !codVino) setCodVino(String(vinRes.items[0].cod_vino));
    } catch (e) {
      setError(e.message);
    }
  }

  useEffect(() => {
    cargarLista();
  }, []);

  useEffect(() => {
    if (catalogos.salas.length && !idSala) {
      setIdSala(String(catalogos.salas[0].id_sala));
    }
  }, [catalogos]);

  async function seleccionar(nro) {
    setError("");
    setOkMsg("");
    try {
      const tr = await api.getTransferencia(nro);
      setActual(tr);
    } catch (e) {
      setError(e.message);
    }
  }

  async function crearTransferencia() {
    setError("");
    setOkMsg("");
    try {
      const tr = await api.createTransferencia({ id_sala: Number(idSala) });
      setActual(tr);
      setOkMsg(`Transferencia #${tr.nro_solicitud} creada en estado ${tr.estado}.`);
      cargarLista();
    } catch (e) {
      setError(e.message);
    }
  }

  async function agregarRenglon(e) {
    e.preventDefault();
    if (!actual) return;
    setError("");
    setOkMsg("");
    try {
      const tr = await api.addRenglonTransferencia(actual.nro_solicitud, {
        cod_vino: Number(codVino),
        cantidad: Number(cantidad),
      });
      setActual(tr);
      setOkMsg("Renglon agregado.");
    } catch (e) {
      setError(e.message);
    }
  }

  async function terminar() {
    if (!actual) return;
    setError("");
    setOkMsg("");
    try {
      const tr = await api.terminarTransferencia(actual.nro_solicitud);
      setActual(tr);
      setOkMsg(`Transferencia #${tr.nro_solicitud} pasada a estado 'terminado'.`);
      cargarLista();
    } catch (e) {
      setError(e.message);
    }
  }

  async function procesar() {
    if (!actual) return;
    setError("");
    setOkMsg("");
    try {
      const tr = await api.procesarTransferencia(actual.nro_solicitud);
      setActual(tr);
      setOkMsg(`Transferencia #${tr.nro_solicitud} procesada via sp_procesar_transferencia().`);
      cargarLista();
    } catch (e) {
      setError(e.message);
    }
  }

  return (
    <div className="grid-2">
      <div className="card">
        <h2>Transferencias</h2>
        {error && <div className="alert-error">{error}</div>}
        {okMsg && <div className="alert-ok">{okMsg}</div>}

        <div className="row">
          <div className="field">
            <label>Sala solicitante</label>
            <select value={idSala} onChange={(e) => setIdSala(e.target.value)}>
              {catalogos.salas.map((s) => (
                <option key={s.id_sala} value={s.id_sala}>
                  Sala #{s.id_sala} — {s.direccion}
                </option>
              ))}
            </select>
          </div>
          <button className="primary" onClick={crearTransferencia}>Nueva transferencia</button>
        </div>

        <table>
          <thead>
            <tr>
              <th>Nro.</th>
              <th>Sala</th>
              <th>Fecha</th>
              <th>Estado</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {lista.map((t) => (
              <tr key={t.nro_solicitud}>
                <td>#{t.nro_solicitud}</td>
                <td>{t.sala}</td>
                <td>{t.fecha_confeccion}</td>
                <td><span className="badge">{t.estado}</span></td>
                <td>
                  <button className="secondary" onClick={() => seleccionar(t.nro_solicitud)}>Abrir</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h3>Detalle de Transferencia</h3>
        {!actual ? (
          <p>Selecciona una transferencia o crea una nueva para gestionar sus renglones y estados.</p>
        ) : (
          <div>
            <p>
              <strong>Solicitud #{actual.nro_solicitud}</strong> | <strong>Sala:</strong> {actual.sala} |{" "}
              <strong>Fecha:</strong> {actual.fecha_confeccion} |{" "}
              <strong>Estado:</strong> <span className="badge">{actual.estado}</span>
            </p>

            <div className="row" style={{ marginBottom: "1rem" }}>
              <button
                className="primary"
                disabled={actual.estado !== "en_confeccion"}
                onClick={terminar}
              >
                Terminar
              </button>
              <button
                className="primary"
                disabled={actual.estado !== "terminado"}
                onClick={procesar}
              >
                Procesar (impactar stock)
              </button>
            </div>

            <form onSubmit={agregarRenglon} className="row">
              <div className="field">
                <label>Vino</label>
                <select
                  disabled={actual.estado !== "en_confeccion"}
                  value={codVino}
                  onChange={(e) => setCodVino(e.target.value)}
                >
                  {vinos.map((v) => (
                    <option key={v.cod_vino} value={v.cod_vino}>
                      #{v.cod_vino} {v.nombre} ({v.anada})
                    </option>
                  ))}
                </select>
              </div>
              <div className="field" style={{ maxWidth: "120px" }}>
                <label>Cantidad</label>
                <input
                  type="number"
                  disabled={actual.estado !== "en_confeccion"}
                  value={cantidad}
                  onChange={(e) => setCantidad(e.target.value)}
                />
              </div>
              <button
                type="submit"
                className="secondary"
                disabled={actual.estado !== "en_confeccion"}
              >
                Agregar renglon
              </button>
            </form>

            <table>
              <thead>
                <tr>
                  <th>Cod.</th>
                  <th>Vino</th>
                  <th>Cantidad</th>
                </tr>
              </thead>
              <tbody>
                {actual.renglones.map((r) => (
                  <tr key={r.cod_vino}>
                    <td>{r.cod_vino}</td>
                    <td>{r.vino}</td>
                    <td>{r.cantidad}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
