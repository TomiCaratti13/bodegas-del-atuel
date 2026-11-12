// Capa unica de comunicacion con la API REST.
// No calcula totales, descuentos ni stock; propaga textualmente los errores de PostgreSQL.

const API_BASE_URL = (import.meta.env.VITE_API_URL || "http://localhost:8000").replace(/\/+$/, "");

async function request(path, options = {}) {
  const url = `${API_BASE_URL}${path}`;
  const res = await fetch(url, {
    headers: {
      "Content-Type": "application/json",
      ...(options.headers || {}),
    },
    ...options,
  });

  if (res.status === 204) {
    return null;
  }

  let data = null;
  try {
    data = await res.json();
  } catch {
    data = null;
  }

  if (!res.ok) {
    const msg =
      (data && (data.error || (typeof data.detail === "string" ? data.detail : JSON.stringify(data.detail)))) ||
      `Error HTTP ${res.status}`;
    const sqlInfo = data && data.sqlstate ? ` [SQLSTATE ${data.sqlstate}]` : "";
    const err = new Error(`${msg}${sqlInfo}`);
    err.status = res.status;
    err.payload = data;
    throw err;
  }

  return data;
}

export const api = {
  getSalud: () => request("/salud"),
  getCatalogos: () => request("/catalogos"),

  // Vinos
  listVinos: (params = {}) => {
    const qs = new URLSearchParams();
    Object.entries(params).forEach(([k, v]) => {
      if (v !== "" && v !== null && v !== undefined) qs.set(k, String(v));
    });
    return request(`/vinos?${qs.toString()}`);
  },
  getVino: (cod) => request(`/vinos/${cod}`),
  createVino: (payload) => request("/vinos", { method: "POST", body: JSON.stringify(payload) }),
  updateVino: (cod, payload) => request(`/vinos/${cod}`, { method: "PUT", body: JSON.stringify(payload) }),

  // Clientes
  listClientes: (params = {}) => {
    const qs = new URLSearchParams();
    Object.entries(params).forEach(([k, v]) => {
      if (v !== "" && v !== null && v !== undefined) qs.set(k, String(v));
    });
    return request(`/clientes?${qs.toString()}`);
  },

  // Comprobantes (ventas)
  createComprobante: (payload) => request("/comprobantes", { method: "POST", body: JSON.stringify(payload) }),
  getComprobante: (nro) => request(`/comprobantes/${nro}`),

  // Transferencias
  listTransferencias: (page = 1) => request(`/transferencias?page=${page}&page_size=20`),
  getTransferencia: (nro) => request(`/transferencias/${nro}`),
  createTransferencia: (payload) => request("/transferencias", { method: "POST", body: JSON.stringify(payload) }),
  addRenglonTransferencia: (nro, payload) =>
    request(`/transferencias/${nro}/renglones`, { method: "POST", body: JSON.stringify(payload) }),
  terminarTransferencia: (nro) => request(`/transferencias/${nro}/terminar`, { method: "POST" }),
  procesarTransferencia: (nro) => request(`/transferencias/${nro}/procesar`, { method: "POST" }),

  // Reportes
  getTopVinos: () => request("/reportes/top-vinos"),
  getVentasPorSala: () => request("/reportes/ventas-por-sala"),
  getVinosSinStock: (idSala) => request(`/reportes/vinos-sin-stock?id_sala=${idSala}`),
};
