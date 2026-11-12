import { useEffect, useState } from "react";
import { api } from "../api/client";

export default function VinoFormPage({ catalogos, editingVino, onDone }) {
  const [nombre, setNombre] = useState("");
  const [tipo, setTipo] = useState("tinto");
  const [anada, setAnada] = useState("2022");
  const [volumenMl, setVolumenMl] = useState("750");
  const [graduacion, setGraduacion] = useState("14.0");
  const [precio, setPrecio] = useState("12500");
  const [cuitBodega, setCuitBodega] = useState("");
  const [composiciones, setComposiciones] = useState([{ id_cepa: "", porcentaje: "100" }]);
  const [maridajesIds, setMaridajesIds] = useState([]);
  const [error, setError] = useState("");
  const [okMsg, setOkMsg] = useState("");

  useEffect(() => {
    if (catalogos.bodegas.length && !cuitBodega) {
      setCuitBodega(catalogos.bodegas[0].cuit);
    }
    if (catalogos.cepas.length && composiciones[0]?.id_cepa === "") {
      setComposiciones([{ id_cepa: String(catalogos.cepas[0].id_cepa), porcentaje: "100" }]);
    }
  }, [catalogos]);

  useEffect(() => {
    if (editingVino) {
      setNombre(editingVino.nombre);
      setTipo(editingVino.tipo);
      setAnada(String(editingVino.anada));
      setVolumenMl(String(editingVino.volumen_ml));
      setGraduacion(String(editingVino.graduacion));
      setPrecio(String(editingVino.precio));
      setCuitBodega(editingVino.cuit_bodega);
    }
  }, [editingVino]);

  function addCepaRow() {
    const firstCepa = catalogos.cepas[0]?.id_cepa || "";
    setComposiciones([...composiciones, { id_cepa: String(firstCepa), porcentaje: "0" }]);
  }

  function updateCepaRow(idx, field, value) {
    const next = composiciones.map((c, i) => (i === idx ? { ...c, [field]: value } : c));
    setComposiciones(next);
  }

  function removeCepaRow(idx) {
    setComposiciones(composiciones.filter((_, i) => i !== idx));
  }

  function toggleMaridaje(id) {
    setMaridajesIds((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  }

  async function handleSubmit(e) {
    e.preventDefault();
    setError("");
    setOkMsg("");
    try {
      if (editingVino) {
        const res = await api.updateVino(editingVino.cod_vino, {
          nombre,
          tipo,
          anada: Number(anada),
          volumen_ml: Number(volumenMl),
          graduacion: Number(graduacion),
          precio: Number(precio),
        });
        setOkMsg(`Vino #${res.cod_vino} actualizado correctamente (cambio de precio auditado en RN-13).`);
      } else {
        // Se envia directamente al backend para que la BD valide RN-05 (suma = 100%) y CHECKs
        const res = await api.createVino({
          nombre,
          tipo,
          anada: Number(anada),
          volumen_ml: Number(volumenMl),
          graduacion: Number(graduacion),
          precio: Number(precio),
          cuit_bodega: cuitBodega,
          composiciones: composiciones.map((c) => ({
            id_cepa: Number(c.id_cepa),
            porcentaje: Number(c.porcentaje),
          })),
          maridajes_ids: maridajesIds,
        });
        setOkMsg(`Vino #${res.cod_vino} "${res.nombre}" creado correctamente.`);
      }
    } catch (err) {
      setError(err.message);
    }
  }

  return (
    <div className="card">
      <div className="row" style={{ justifyContent: "space-between" }}>
        <h2>{editingVino ? `Editar Vino #${editingVino.cod_vino}` : "Alta de Vino"}</h2>
        {editingVino && (
          <button className="secondary" onClick={onDone}>
            Cambiar a Alta Nueva
          </button>
        )}
      </div>

      {error && <div className="alert-error">{error}</div>}
      {okMsg && <div className="alert-ok">{okMsg}</div>}

      <form onSubmit={handleSubmit}>
        <div className="row">
          <div className="field">
            <label>Nombre comercial</label>
            <input required value={nombre} onChange={(e) => setNombre(e.target.value)} />
          </div>
          <div className="field">
            <label>Tipo</label>
            <select value={tipo} onChange={(e) => setTipo(e.target.value)}>
              <option value="tinto">Tinto</option>
              <option value="blanco">Blanco</option>
              <option value="rosado">Rosado</option>
              <option value="espumante">Espumante</option>
            </select>
          </div>
          <div className="field">
            <label>Anada</label>
            <input type="number" required value={anada} onChange={(e) => setAnada(e.target.value)} />
          </div>
          <div className="field">
            <label>Presentacion (ml)</label>
            <select value={volumenMl} onChange={(e) => setVolumenMl(e.target.value)}>
              <option value="187">187 ml</option>
              <option value="375">375 ml</option>
              <option value="750">750 ml</option>
              <option value="1500">1500 ml</option>
              <option value="3000">3000 ml</option>
            </select>
          </div>
        </div>

        <div className="row" style={{ marginTop: "0.75rem" }}>
          <div className="field">
            <label>Graduacion alcoholica (5 - 20)</label>
            <input type="number" step="0.01" required value={graduacion} onChange={(e) => setGraduacion(e.target.value)} />
          </div>
          <div className="field">
            <label>Precio ($)</label>
            <input type="number" step="0.01" required value={precio} onChange={(e) => setPrecio(e.target.value)} />
          </div>
          {!editingVino && (
            <div className="field">
              <label>Bodega elaboradora</label>
              <select value={cuitBodega} onChange={(e) => setCuitBodega(e.target.value)}>
                {catalogos.bodegas.map((b) => (
                  <option key={b.cuit} value={b.cuit}>{b.razon_social}</option>
                ))}
              </select>
            </div>
          )}
        </div>

        {!editingVino && (
          <>
            <div style={{ marginTop: "1rem" }}>
              <div className="row" style={{ justifyContent: "space-between" }}>
                <h4>Composicion de cepas (debe sumar 100% — validado por trigger RN-05 en PostgreSQL)</h4>
                <button type="button" className="secondary" onClick={addCepaRow}>+ Agregar cepa</button>
              </div>
              {composiciones.map((c, idx) => (
                <div className="row" key={idx} style={{ marginTop: "0.5rem" }}>
                  <div className="field">
                    <label>Cepa</label>
                    <select value={c.id_cepa} onChange={(e) => updateCepaRow(idx, "id_cepa", e.target.value)}>
                      {catalogos.cepas.map((ce) => (
                        <option key={ce.id_cepa} value={ce.id_cepa}>{ce.nombre} ({ce.tipo})</option>
                      ))}
                    </select>
                  </div>
                  <div className="field">
                    <label>Porcentaje (%)</label>
                    <input
                      type="number"
                      step="0.01"
                      value={c.porcentaje}
                      onChange={(e) => updateCepaRow(idx, "porcentaje", e.target.value)}
                    />
                  </div>
                  {composiciones.length > 1 && (
                    <button type="button" className="secondary" onClick={() => removeCepaRow(idx)}>Quitar</button>
                  )}
                </div>
              ))}
            </div>

            <div style={{ marginTop: "1rem" }}>
              <h4>Maridajes recomendados</h4>
              <div className="row">
                {catalogos.maridajes.map((m) => (
                  <label key={m.id_maridaje} style={{ display: "flex", gap: "0.35rem", alignItems: "center" }}>
                    <input
                      type="checkbox"
                      checked={maridajesIds.includes(m.id_maridaje)}
                      onChange={() => toggleMaridaje(m.id_maridaje)}
                    />
                    {m.nombre} ({m.temperatura_servicio}°C)
                  </label>
                ))}
              </div>
            </div>
          </>
        )}

        <div style={{ marginTop: "1.25rem" }}>
          <button type="submit" className="primary">
            {editingVino ? "Guardar cambios" : "Crear vino"}
          </button>
        </div>
      </form>
    </div>
  );
}
