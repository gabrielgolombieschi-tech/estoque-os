export type RelatorioDestinoItem = {
  numero_item_xml?: number | null;
  codigo?: string | null;
  descricao?: string | null;
  unidade?: string | null;
  quantidade?: number | string | null;
  destino_tipo?: "ESTOQUE" | "OS" | string | null;
  destino_label?: string | null;
  os_id?: number | string | null;
  os_numero?: string | null;
  pedido_codigo?: string | null;
};

export type RelatorioDestinoImportacao = {
  nf_entrada_id?: number | string | null;
  chave?: string | null;
  numero?: string | null;
  serie?: string | null;
  emitente?: string | null;
  data_emissao?: string | null;
  itens?: RelatorioDestinoItem[];
  fileName?: string;
};

export function isRelatorioDestinoImportacao(value: unknown): value is RelatorioDestinoImportacao {
  if (!value || typeof value !== "object") return false;
  return Array.isArray((value as Record<string, unknown>).itens);
}

function escapeHtml(value: unknown): string {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function formatDateBR(iso?: string | null): string {
  if (!iso) return "";
  const v = String(iso);
  const d = new Date(v.includes("T") ? v : `${v}T00:00:00`);
  if (Number.isNaN(d.getTime())) return v;
  return d.toLocaleDateString("pt-BR");
}

function formatQtyBR(value: unknown): string {
  const n = typeof value === "number" ? value : Number(value ?? 0);
  return (Number.isFinite(n) ? n : 0).toLocaleString("pt-BR", { maximumFractionDigits: 3 });
}

function buildRelatorioDestinoHtml(relatorios: RelatorioDestinoImportacao[]): string {
  const printedAt = new Date().toLocaleString("pt-BR");
  const sections = relatorios
    .map((relatorio, index) => {
      const itens = Array.isArray(relatorio.itens) ? relatorio.itens : [];
      const rows = itens
        .map((item, idx) => {
          const fallbackDestino =
            item.destino_tipo === "OS" ? `OS ${item.os_numero ?? item.os_id ?? ""}`.trim() : "Estoque";
          const destino = String(item.destino_label ?? "").trim() || fallbackDestino || "Estoque";
          return `
            <tr>
              <td class="num">${escapeHtml(item.numero_item_xml ?? idx + 1)}</td>
              <td>${escapeHtml(item.codigo ?? "-")}</td>
              <td>${escapeHtml(item.descricao ?? "-")}</td>
              <td class="center">${escapeHtml(item.unidade ?? "-")}</td>
              <td class="num">${escapeHtml(formatQtyBR(item.quantidade))}</td>
              <td class="destino">${escapeHtml(destino)}</td>
              <td>${escapeHtml(item.pedido_codigo ?? "-")}</td>
            </tr>`;
        })
        .join("");

      return `
        <section class="${index > 0 ? "page-break" : ""}">
          <div class="meta">
            <div><strong>NF:</strong> ${escapeHtml(relatorio.numero ?? "-")}/${escapeHtml(relatorio.serie ?? "-")}</div>
            <div><strong>Emissao:</strong> ${escapeHtml(formatDateBR(relatorio.data_emissao))}</div>
            <div><strong>Emitente:</strong> ${escapeHtml(relatorio.emitente ?? "-")}</div>
            <div><strong>Chave:</strong> ${escapeHtml(relatorio.chave ?? "-")}</div>
            <div><strong>Arquivo:</strong> ${escapeHtml(relatorio.fileName ?? "-")}</div>
          </div>
          <table>
            <thead>
              <tr>
                <th>Item</th>
                <th>Codigo</th>
                <th>Descricao</th>
                <th>Un</th>
                <th>Qtd</th>
                <th>Destino</th>
                <th>Pedido</th>
              </tr>
            </thead>
            <tbody>
              ${rows || `<tr><td colspan="7" class="empty">Sem itens para direcionamento.</td></tr>`}
            </tbody>
          </table>
        </section>`;
    })
    .join("");

  return `<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8" />
  <title>Relatorio de destino dos itens</title>
  <style>
    * { box-sizing: border-box; }
    body { font-family: Arial, sans-serif; color: #111; margin: 24px; font-size: 12px; }
    h1 { font-size: 18px; margin: 0 0 4px; }
    .subtitle { color: #444; margin-bottom: 16px; }
    .meta { display: grid; grid-template-columns: 1fr 1fr; gap: 6px 20px; margin: 12px 0 16px; }
    table { width: 100%; border-collapse: collapse; }
    th { background: #e8e8e8; text-align: left; font-weight: 700; }
    th, td { border: 1px solid #999; padding: 7px 8px; vertical-align: top; }
    .num { text-align: right; font-variant-numeric: tabular-nums; }
    .center { text-align: center; }
    .destino { font-weight: 700; font-size: 13px; }
    .empty { text-align: center; color: #555; padding: 18px; }
    .page-break { page-break-before: always; margin-top: 24px; }
    @page { margin: 12mm; }
  </style>
</head>
<body>
  <h1>Relatorio de destino dos itens</h1>
  <div class="subtitle">Impresso em ${escapeHtml(printedAt)} - uso do almoxarifado</div>
  ${sections}
</body>
</html>`;
}

export function imprimirRelatorioDestinos(relatorios: RelatorioDestinoImportacao[]) {
  if (typeof window === "undefined" || relatorios.length === 0) return;
  const frame = document.createElement("iframe");
  frame.style.position = "fixed";
  frame.style.right = "0";
  frame.style.bottom = "0";
  frame.style.width = "0";
  frame.style.height = "0";
  frame.style.border = "0";
  frame.srcdoc = buildRelatorioDestinoHtml(relatorios);
  document.body.appendChild(frame);
  window.setTimeout(() => {
    frame.contentWindow?.focus();
    frame.contentWindow?.print();
  }, 300);
  window.setTimeout(() => frame.remove(), 60000);
}
