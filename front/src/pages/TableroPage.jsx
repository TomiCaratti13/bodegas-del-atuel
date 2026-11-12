import { useEffect, useRef, useState } from "react";
import { Chart, BarController, BarElement, CategoryScale, LinearScale, Tooltip } from "chart.js";
import { api } from "../api/client";

Chart.register(BarController, BarElement, CategoryScale, LinearScale, Tooltip);

export default function TableroPage({ catalogos }) {
  const [topVinos, setTopVinos] = useState([]);
  const [ventasSala, setVentasSala] = useState([]);
  const [sinStock, setSinStock] = useState([]);
  const [idSala, setIdSala] = useState("1");
  const [error, setError] = useState("");
  const canvasRef = useRef(null);
  const chartRef = useRef(null);

  useEffect(() => {
    async function load() {
      setError("");
      try {
        const [top, ventas] = await Promise.all([api.getTopVinos(), api.getVentasPorSala()]);
        setTopVinos(top);
        setVentasSala(ventas);
      } catch (e) {
        setError(e.message);
      }
    }
    load();
  }, []);

  useEffect(() => {
    async function loadSinStock() {
      try {
        const rows = await api.getVinosSinStock(idSala);
        setSinStock(rows);
      } catch (e) {
        setError(e.message);
      }
    }
    if (idSala) loadSinStock();
  }, [idSala]);

  useEffect(() => {
    if (!canvasRef.current || ventasSala.length === 0) return;
    if (chartRef.current) {
      chartRef.current.destroy();
    }
    chartRef.current = new Chart(canvasRef.current, {
      type: "bar",
      data: {
        labels: ventasSala.map((s) => `Sala #${s.id_sala} (${s.localidad})`),
        datasets: [
          {
            label: "Ventas ultimo trimestre ($)",
            data: ventasSala.map((s) => Number(s.monto_total)),
            backgroundColor: "#6b1d2f",
          },
        ],
      },
      options: {
        responsive: true,
        plugins: { legend: { display: false } },
      },
    });
    return () => {
      if (chartRef.current) chartRef.current.destroy();
    };
  }, [ventasSala]);

  return (
    <div>
      {error && <div className="alert-error">{error}</div>}

      <div className="card">
        <h2>Ventas por sala en el ultimo trimestre</h2>
        <canvas ref={canvasRef} height="100" />
      </div>

      <div className="grid-2">
        <div className="card">
          <h3>Ranking Top 10 Vinos Mas Vendidos</h3>
          <table>
            <thead>
              <tr>
                <th>#</th>
                <th>Vino</th>
                <th>Tipo</th>
                <th>Botellas</th>
              </tr>
            </thead>
            <tbody>
              {topVinos.map((v, idx) => (
                <tr key={v.cod_vino}>
                  <td>{idx + 1}</td>
                  <td>{v.nombre} ({v.anada})</td>
                  <td>{v.tipo}</td>
                  <td>{Number(v.botellas_vendidas).toLocaleString("es-AR")}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="card">
          <div className="row" style={{ justifyContent: "space-between" }}>
            <h3>Vinos sin stock en sala (con stock en deposito)</h3>
            <select value={idSala} onChange={(e) => setIdSala(e.target.value)}>
              {catalogos.salas.map((s) => (
                <option key={s.id_sala} value={s.id_sala}>
                  Sala #{s.id_sala} — {s.localidad}
                </option>
              ))}
            </select>
          </div>
          <table>
            <thead>
              <tr>
                <th>Cod.</th>
                <th>Vino</th>
                <th>Deposito</th>
                <th>Sala</th>
              </tr>
            </thead>
            <tbody>
              {sinStock.map((v) => (
                <tr key={v.cod_vino}>
                  <td>{v.cod_vino}</td>
                  <td>{v.nombre} ({v.anada})</td>
                  <td>{v.stock_deposito}</td>
                  <td>{v.stock_sala}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
