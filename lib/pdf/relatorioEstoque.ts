import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";

type Filtros = {
  busca: string;
  codigoId: string;
  codigoFornecedor: string;
  fornecedorNome: string;
  ativos: "ativos" | "todos";
  abaixoMinimo: boolean;
};

type Row = {
  item_id: number;
  quantidade_atual: number;
  itens: {
    codigo_interno: string;
    nome: string;
    unidade_medida: string | null;
    estoque_minimo: number | null;
    estoque_ideal: number | null;
    estoque_maximo: number | null;
  } | null;
};

function formatNumberBR(value: number, decimals = 2) {
  return value.toLocaleString("pt-BR", { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
}

function buildFiltrosTexto(f: Filtros) {
  const parts: string[] = [];
  if (f.busca.trim()) parts.push(`Busca: ${f.busca.trim()}`);
  if (f.codigoId.trim()) parts.push(`Código (id): ${f.codigoId.trim()}`);
  if (f.codigoFornecedor.trim()) parts.push(`Código fornecedor: ${f.codigoFornecedor.trim()}`);
  if (f.fornecedorNome.trim()) parts.push(`Fornecedor: ${f.fornecedorNome.trim()}`);
  parts.push(`Ativos: ${f.ativos === "ativos" ? "Somente ativos" : "Todos"}`);
  parts.push(`Abaixo do mínimo: ${f.abaixoMinimo ? "Sim" : "Não"}`);
  return parts.join(" | ");
}

export function gerarRelatorioEstoque(rows: Row[], filtros: Filtros) {
  const doc = new jsPDF({ orientation: "portrait", unit: "pt", format: "a4" });
  const empresa = "SEGAU – Estoque + OS";
  const emitidoEm = new Date();
  const emitidoTexto = emitidoEm.toLocaleString("pt-BR");
  const filtrosTexto = buildFiltrosTexto(filtros);

  const pageWidth = doc.internal.pageSize.getWidth();
  const margin = 40;

  const header = () => {
    doc.setFontSize(12);
    doc.setTextColor(30);
    doc.text("Relatório de Estoque", margin, margin);
    doc.setFontSize(9);
    doc.setTextColor(70);
    doc.text(empresa, margin, margin + 14);
    doc.text(`Emitido em: ${emitidoTexto}`, margin, margin + 28);
    doc.text(doc.splitTextToSize(`Filtros: ${filtrosTexto || "Nenhum"}`, pageWidth - margin * 2), margin, margin + 42);
  };

  const footer = (page: number, total: number) => {
    const y = doc.internal.pageSize.getHeight() - 20;
    doc.setFontSize(9);
    doc.setTextColor(100);
    doc.text(`Documento gerado pelo sistema Estoque + OS`, margin, y);
    doc.text(`Página ${page} de ${total}`, pageWidth - margin, y, { align: "right" });
  };

  const tableBody = rows.map((r) => {
    const item = r.itens;
    return [
      String(r.item_id ?? ""),
      item?.codigo_interno ?? "",
      item?.nome ?? "",
      item?.unidade_medida ?? "UN",
      formatNumberBR(Number(r.quantidade_atual ?? 0), 3),
      formatNumberBR(Number(item?.estoque_minimo ?? 0), 3),
      formatNumberBR(Number(item?.estoque_ideal ?? 0), 3),
      formatNumberBR(Number(item?.estoque_maximo ?? 0), 3),
    ];
  });

  const topOffset = margin + 70;
  autoTable(doc, {
    head: [["ID", "Código", "Produto", "Und", "Saldo", "Mín", "Ideal", "Máx"]],
    body: tableBody,
    styles: {
      fontSize: 9,
      cellPadding: 6,
      overflow: "linebreak",
    },
    headStyles: {
      fillColor: [24, 24, 27],
      textColor: 255,
    },
    alternateRowStyles: { fillColor: [245, 245, 245] },
    margin: { left: margin, right: margin, top: topOffset },
    didDrawPage: () => {
      header();
    },
  });

  const totalPages = doc.getNumberOfPages();
  for (let i = 1; i <= totalPages; i++) {
    doc.setPage(i);
    footer(i, totalPages);
  }

  const fileName = `relatorio-estoque_${emitidoEm.toISOString().slice(0, 16).replace(/[:T]/g, "-")}.pdf`;
  doc.save(fileName);
}
