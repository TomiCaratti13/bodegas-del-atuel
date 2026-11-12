import { useEffect, useState } from "react";
import { api } from "./api/client";
import CatalogoPage from "./pages/CatalogoPage";
import VinoFormPage from "./pages/VinoFormPage";
import NuevaVentaPage from "./pages/NuevaVentaPage";
import TransferenciasPage from "./pages/TransferenciasPage";
import TableroPage from "./pages/TableroPage";

export default function App() {
  const [tab, setTab] = useState("catalogo");
  const [editingVino, setEditingVino] = useState(null);
  const [catalogos, setCatalogos] = useState({
    cepas: [],
    bodegas: [],
    salas: [],
    maridajes: [],
    localidades: [],
    transportistas: [],
  });
  const [apiStatus, setApiStatus] = useState("");

  useEffect(() => {
    api.getSalud()
      .then((res) => setApiStatus(`Conectado (${res.db.db_user})`))
      .catch(() => setApiStatus("Sin conexion con API"));

    api.getCatalogos()
      .then(setCatalogos)
      .catch(() => {});
  }, []);

  return (
    <>
      <header>
        <div>
          <h1>Bodegas del Atuel</h1>
          <small>{apiStatus}</small>
        </div>
        <nav>
          <button className={tab === "catalogo" ? "active" : ""} onClick={() => setTab("catalogo")}>
            Catalogo
          </button>
          <button
            className={tab === "vino" ? "active" : ""}
            onClick={() => {
              setEditingVino(null);
              setTab("vino");
            }}
          >
            Alta / Edicion Vino
          </button>
          <button className={tab === "venta" ? "active" : ""} onClick={() => setTab("venta")}>
            Nueva Venta
          </button>
          <button className={tab === "transferencias" ? "active" : ""} onClick={() => setTab("transferencias")}>
            Transferencias
          </button>
          <button className={tab === "tablero" ? "active" : ""} onClick={() => setTab("tablero")}>
            Tablero
          </button>
        </nav>
      </header>

      <main>
        {tab === "catalogo" && (
          <CatalogoPage
            catalogos={catalogos}
            onEditVino={(v) => {
              setEditingVino(v);
              setTab("vino");
            }}
          />
        )}
        {tab === "vino" && (
          <VinoFormPage
            catalogos={catalogos}
            editingVino={editingVino}
            onDone={() => setEditingVino(null)}
          />
        )}
        {tab === "venta" && <NuevaVentaPage catalogos={catalogos} />}
        {tab === "transferencias" && <TransferenciasPage catalogos={catalogos} />}
        {tab === "tablero" && <TableroPage catalogos={catalogos} />}
      </main>
    </>
  );
}
