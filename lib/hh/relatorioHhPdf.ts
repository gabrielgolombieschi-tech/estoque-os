// Gerador do PDF do relatorio de horas (HH).
//
// Movido de app/os/[id]/components/RelatorioHHSection.tsx. O layout esta igual;
// mudaram tres coisas para o mesmo codigo servir a tela e ao aplicativo:
//
//   1. a logo chega por um carregador injetado (fetch no navegador, disco no
//      servidor) em vez de um fetch fixo;
//   2. a medicao da logo le os bytes do PNG em vez de usar `new Image()`;
//   3. a funcao devolve os bytes do PDF em vez de chamar doc.save().
//
// Quem baixa decide o que fazer com os bytes: o navegador dispara o download,
// a rota devolve como resposta e o aplicativo abre o compartilhamento.

import type { CellHookData, RowInput } from "jspdf-autotable";

import { type CarregadorDeImagem, tamanhoNaturalDaImagem } from "@/lib/pdf/imagemPdf";
import {
  formatCurrencyBRL,
  formatDateDDMMAA,
  formatHoursBR,
  formatTimeHHMM,
  getHorasSplitEfetivo,
  getHorasTrabalhadasEfetivas,
  getTipoHHLabelFromSplit,
  getValorTotalEfetivo,
  type HhLancamentoViewRow,
} from "./relatorioHhCalculos";

export type CabecalhoRelatorioHh = {
  empresaNome?: string;
  clienteNome?: string;
  numeroOS?: string;
  osDescricao?: string;
  periodoLabel?: string;
  emissaoLabel?: string;
};

/** Nome do arquivo — o mesmo que a tela ja baixava. */
export function nomeArquivoRelatorioHh(osId: number, agora: Date = new Date()): string {
  const dataStr = agora.toISOString().slice(0, 10);
  return `relatorio-hh-os-${osId}-${dataStr}.pdf`;
}

export async function gerarRelatorioHhPdf(
  hhRows: HhLancamentoViewRow[],
  osId: number,
  header: CabecalhoRelatorioHh | undefined,
  opcoes: { carregarImagem: CarregadorDeImagem }
): Promise<Uint8Array> {
  // Importa jsPDF dinamicamente
  const { jsPDF } = await import("jspdf");
  const autoTable = await import("jspdf-autotable");

  const doc = new jsPDF({
    orientation: "landscape",
    unit: "mm",
    format: "a4",
  });

  const margin = 12;
  const headerHeight = 28;
  const topStartY = margin + headerHeight + 4;

  // Paleta e fontes
  const titleColor: [number, number, number] = [20, 20, 20];
  const subtitleColor: [number, number, number] = [60, 60, 60];
  const tableHeadFill: [number, number, number] = [32, 32, 32];
  const tableHeadText: [number, number, number] = [240, 240, 240];
  const tableBodyText: [number, number, number] = [40, 40, 40];
  const zebraFill: [number, number, number] = [248, 248, 248];

  const empresaNome = header?.empresaNome?.trim() || "—";
  const clienteNome = header?.clienteNome?.trim() || "—";
  const numeroOS = header?.numeroOS?.trim() || String(osId);
  const osDescricao = header?.osDescricao?.trim() || "";
  const periodoLabel = header?.periodoLabel?.trim() || "—";
  const emissaoLabel = header?.emissaoLabel?.trim() || new Date().toLocaleString("pt-BR");

  const osLine = osDescricao ? `OS ${numeroOS} - ${osDescricao}` : `OS ${numeroOS}`;
  const logoDataUrl = await opcoes.carregarImagem("/Segau2.png");
  const logoSize = tamanhoNaturalDaImagem(logoDataUrl);
  const logoBox = { w: 18, h: 18 };

  const truncateToWidth = (text: string, maxWidth: number) => {
    const clean = String(text ?? "").replace(/\s+/g, " ").trim();
    if (!clean) return "";
    if (maxWidth <= 0) return "";
    if (doc.getTextWidth(clean) <= maxWidth) return clean;

    const ellipsis = "…";
    if (doc.getTextWidth(ellipsis) > maxWidth) return ellipsis;

    let lo = 0;
    let hi = clean.length;
    while (lo < hi) {
      const mid = Math.ceil((lo + hi) / 2);
      const candidate = clean.slice(0, mid) + ellipsis;
      if (doc.getTextWidth(candidate) <= maxWidth) lo = mid;
      else hi = mid - 1;
    }
    const finalLen = Math.max(0, lo);
    return clean.slice(0, finalLen) + ellipsis;
  };

  const wrapTwoLines = (text: string, maxWidth: number) => {
    const clean = String(text ?? "").replace(/\s+/g, " ").trim();
    if (!clean) return [""];
    const lines = doc.splitTextToSize(clean, Math.max(10, maxWidth)) as string[];
    if (lines.length <= 1) return [truncateToWidth(lines[0] ?? clean, maxWidth)];
    if (lines.length === 2) return [truncateToWidth(lines[0], maxWidth), truncateToWidth(lines[1], maxWidth)];
    return [truncateToWidth(lines[0], maxWidth), truncateToWidth(lines.slice(1).join(" "), maxWidth)];
  };

  const drawHeader = (pageNumber: number, pageCount: number) => {
    const pageSize = doc.internal.pageSize;
    const pageWidth = pageSize.getWidth();
    const rightX = pageWidth - margin;
    const leftX = margin + 22;
    const gap = 6;

    // Linha superior
    doc.setDrawColor(17, 24, 39);
    doc.setLineWidth(0.6);
    doc.line(margin, margin + headerHeight + 1, pageWidth - margin, margin + headerHeight + 1);

    // Logo (opcional)
    if (logoDataUrl) {
      try {
        let drawW = logoBox.w;
        let drawH = logoBox.h;
        if (logoSize) {
          const ratio = logoSize.width / logoSize.height;
          drawW = logoBox.w;
          drawH = drawW / ratio;
          if (drawH > logoBox.h) {
            drawH = logoBox.h;
            drawW = drawH * ratio;
          }
        }
        const x = margin + (logoBox.w - drawW) / 2;
        const y = margin + (logoBox.h - drawH) / 2;
        doc.addImage(logoDataUrl, "PNG", x, y, drawW, drawH);
      } catch {
        // ignora se falhar
      }
    }

    // Bloco empresa/cliente (esquerda)
    // Primeiro mede o título para reservar espaço e impedir sobreposição
    doc.setFont("helvetica", "bold");
    doc.setFontSize(15);
    const titulo = "Relatório de Horas Lançadas";
    const tituloWidth = doc.getTextWidth(titulo);
    const tituloLeftEdge = pageWidth / 2 - tituloWidth / 2;
    const tituloRightEdge = pageWidth / 2 + tituloWidth / 2;

    // Mede o bloco da direita e limita para não invadir o título
    doc.setFont("helvetica", "normal");
    doc.setFontSize(9);
    const rightLines = [`Emissão: ${emissaoLabel}`, `Período: ${periodoLabel}`, `Página ${pageNumber} de ${pageCount}`];
    const measuredRightWidth = Math.max(...rightLines.map((t) => doc.getTextWidth(t)));
    const maxRightWidth = Math.max(40, rightX - (tituloRightEdge + gap));
    const rightColWidth = Math.min(Math.max(55, measuredRightWidth + 2), maxRightWidth);
    const rightBlockStart = rightX - rightColWidth;

    // Calcula a largura máxima do bloco esquerdo sem invadir o título
    doc.setFont("helvetica", "bold");
    doc.setFontSize(11);
    const leftMaxEnd = tituloLeftEdge - gap;
    const leftMaxWidth = Math.max(20, leftMaxEnd - leftX);

    doc.setTextColor(titleColor[0], titleColor[1], titleColor[2]);
    doc.text(truncateToWidth(empresaNome, leftMaxWidth), leftX, margin + 7);

    doc.setFont("helvetica", "normal");
    doc.setFontSize(9);
    doc.setTextColor(subtitleColor[0], subtitleColor[1], subtitleColor[2]);
    doc.text(truncateToWidth(`Cliente: ${clienteNome}`, leftMaxWidth), leftX, margin + 13);

    // Título (centro)
    doc.setFont("helvetica", "bold");
    doc.setFontSize(15);
    doc.setTextColor(titleColor[0], titleColor[1], titleColor[2]);
    doc.text(titulo, pageWidth / 2, margin + 8, { align: "center" });

    // Linha de OS (centro) com quebra/truncamento e respeitando blocos esquerda/direita
    const centerLeftBound = leftX + leftMaxWidth + gap;
    const centerRightBound = rightBlockStart - gap;
    const centerMaxWidth = Math.max(60, centerRightBound - centerLeftBound);

    doc.setFontSize(11);
    doc.setFont("helvetica", "normal");
    doc.setTextColor(subtitleColor[0], subtitleColor[1], subtitleColor[2]);
    const osLines = wrapTwoLines(osLine, centerMaxWidth);
    doc.text(osLines[0] ?? "", pageWidth / 2, margin + 14, { align: "center" });
    if (osLines.length > 1 && osLines[1]) {
      doc.text(osLines[1], pageWidth / 2, margin + 18.5, { align: "center" });
    }

    // Metas (direita)
    doc.setFontSize(9);
    doc.setTextColor(subtitleColor[0], subtitleColor[1], subtitleColor[2]);
    doc.text(truncateToWidth(`Emissão: ${emissaoLabel}`, rightColWidth), rightX, margin + 7, { align: "right" });
    doc.text(truncateToWidth(`Período: ${periodoLabel}`, rightColWidth), rightX, margin + 13, { align: "right" });
    doc.text(truncateToWidth(`Página ${pageNumber} de ${pageCount}`, rightColWidth), rightX, margin + 19, { align: "right" });
  };

  // Tabela 1: Lançamentos
  const headRowLancamentos: RowInput = [
    "Funcionário",
    "Data",
    "Entrada 1",
    "Saída 1",
    "Entrada 2",
    "Saída 2",
    "Horas",
    "Tipo",
    "Horas Normais",
    "Extra 50%",
    "Extra 100%",
    "R$ Total",
  ];

  const bodyLancamentos: RowInput[] = [];

  let totalGeral = 0;
  let totalHoras = 0;
  let totalHorasNormais = 0;
  let totalHorasExtra50 = 0;
  let totalHorasExtra100 = 0;

  hhRows.forEach((r) => {
    const horas = getHorasTrabalhadasEfetivas(r);
    const split = getHorasSplitEfetivo(r, horas);
    const tipo = getTipoHHLabelFromSplit(r, horas);
    const total = getValorTotalEfetivo(r, horas);

    totalGeral += total;
    totalHoras += horas;
    totalHorasNormais += split.normais;
    totalHorasExtra50 += split.extra50;
    totalHorasExtra100 += split.extra100;

    bodyLancamentos.push([
      r.colaborador_nome ?? "—",
      formatDateDDMMAA(r.data),
      formatTimeHHMM(r.entrada_1) || formatTimeHHMM(r.hora_entrada) || "—",
      formatTimeHHMM(r.saida_1) || formatTimeHHMM(r.hora_saida) || "—",
      formatTimeHHMM(r.entrada_2) || "—",
      formatTimeHHMM(r.saida_2) || "—",
      formatHoursBR(horas),
      tipo,
      formatHoursBR(split.normais),
      formatHoursBR(split.extra50),
      formatHoursBR(split.extra100),
      formatCurrencyBRL(total),
    ]);
  });

  // Linha de TOTAL
  bodyLancamentos.push([
    "",
    "",
    "",
    "",
    "",
    "",
    formatHoursBR(totalHoras),
    "TOTAL",
    formatHoursBR(totalHorasNormais),
    formatHoursBR(totalHorasExtra50),
    formatHoursBR(totalHorasExtra100),
    formatCurrencyBRL(totalGeral),
  ]);

  // Tabela 1
  const totalRowIndex = bodyLancamentos.length - 1;
  autoTable.default(doc, {
    startY: topStartY,
    head: [headRowLancamentos],
    body: bodyLancamentos,
    margin: { top: topStartY, left: margin, right: margin, bottom: 10 },
    styles: {
      cellPadding: 1.6,
      lineWidth: 0.1,
      lineColor: [220, 220, 220],
      overflow: "linebreak",
    },
    didParseCell: (data: CellHookData) => {
      // Destaque profissional na linha TOTAL
      if (data?.section !== "body") return;
      if (data?.row?.index !== totalRowIndex) return;
      data.cell.styles.fontStyle = "bold";
      // Cinza bem suave (mais perceptível, porém profissional)
      data.cell.styles.fillColor = [238, 240, 243];
      data.cell.styles.textColor = [20, 20, 20];
      data.cell.styles.lineWidth = 0.2;
      data.cell.styles.fontSize = 9;
    },
    didDrawCell: (data: CellHookData) => {
      // Linha superior mais grossa para separar o TOTAL
      if (data?.section !== "body") return;
      if (data?.row?.index !== totalRowIndex) return;
      if (data?.column?.index !== 0) return;

      const tableMeta = data.table as unknown as { startX?: number; width?: number };
      const startX = Number(tableMeta.startX ?? 0);
      const width = Number(tableMeta.width ?? 0);
      const y = Number(data.cell?.y ?? 0);
      if (!Number.isFinite(startX) || !Number.isFinite(width) || !Number.isFinite(y) || width <= 0) return;

      doc.setDrawColor(140, 140, 140);
      doc.setLineWidth(0.6);
      doc.line(startX, y, startX + width, y);
    },
    columnStyles: {
      0: { cellWidth: 54 }, // Funcionário
      1: { cellWidth: 16, halign: "center" }, // Data (ddMMyy)
      2: { cellWidth: 16, halign: "center" }, // Entrada 1
      3: { cellWidth: 16, halign: "center" }, // Saída 1
      4: { cellWidth: 16, halign: "center" }, // Entrada 2
      5: { cellWidth: 16, halign: "center" }, // Saída 2
      6: { cellWidth: 16, halign: "right" }, // Horas
      7: { cellWidth: 30 }, // Tipo
      8: { cellWidth: 18, halign: "right" }, // Horas Normais
      9: { cellWidth: 18, halign: "right" }, // Extra 50%
      10: { cellWidth: 18, halign: "right" }, // Extra 100%
      11: { cellWidth: 23, halign: "right" }, // R$ Total
    },
    headStyles: {
      fillColor: tableHeadFill,
      textColor: tableHeadText,
      fontSize: 9,
      fontStyle: "bold",
      lineWidth: 0.2,
      lineColor: [220, 220, 220],
      halign: "center",
    },
    bodyStyles: {
      fontSize: 8.6,
      textColor: tableBodyText,
    },
    alternateRowStyles: {
      fillColor: zebraFill,
    },
  });

  // Tabela 2: Valores por funcionário/função
  const uniqueValores = new Map<string, { funcionario: string; funcao: string; valorHora: number }>();
  hhRows.forEach((r) => {
    const funcionario = (r.colaborador_nome ?? "—").trim() || "—";
    const funcao =
      r.especialidade_descricao && r.especialidade_descricao.trim() ? r.especialidade_descricao.trim() : "—";
    const valorHora = Number(r.valor_hora ?? 0);
    const key = `${funcionario}||${funcao}||${valorHora}`;
    if (!uniqueValores.has(key)) uniqueValores.set(key, { funcionario, funcao, valorHora });
  });

  const valoresSorted = Array.from(uniqueValores.values()).sort((a, b) => {
    const byFunc = a.funcionario.localeCompare(b.funcionario, "pt-BR", { sensitivity: "base" });
    if (byFunc !== 0) return byFunc;
    return a.funcao.localeCompare(b.funcao, "pt-BR", { sensitivity: "base" });
  });

  const headRowValores: RowInput = ["Funcionário", "Função", "V. Hora Normal", "V. Hora 50%", "V. Hora 100%"];
  const bodyValores: RowInput[] = valoresSorted.map((v) => {
    const v50 = v.valorHora * 1.5;
    const v100 = v.valorHora * 2.0;
    return [v.funcionario, v.funcao, formatCurrencyBRL(v.valorHora), formatCurrencyBRL(v50), formatCurrencyBRL(v100)];
  });

  if (bodyValores.length > 0) {
    const lastY =
      (doc as unknown as { lastAutoTable?: { finalY?: number } }).lastAutoTable?.finalY ?? topStartY;

    autoTable.default(doc, {
      startY: lastY + 8,
      head: [headRowValores],
      body: bodyValores,
      margin: { top: topStartY, left: margin, right: margin, bottom: 10 },
      styles: {
        cellPadding: 1.6,
        lineWidth: 0.1,
        lineColor: [220, 220, 220],
        overflow: "linebreak",
      },
      columnStyles: {
        0: { cellWidth: 75 }, // Funcionário
        1: { cellWidth: 75 }, // Função
        2: { cellWidth: 25, halign: "right" }, // V. Hora Normal
        3: { cellWidth: 25, halign: "right" }, // V. Hora 50%
        4: { cellWidth: 25, halign: "right" }, // V. Hora 100%
      },
      headStyles: {
        fillColor: tableHeadFill,
        textColor: tableHeadText,
        fontSize: 9,
        fontStyle: "bold",
        lineWidth: 0.2,
        lineColor: [220, 220, 220],
        halign: "center",
      },
      bodyStyles: {
        fontSize: 8.6,
        textColor: tableBodyText,
      },
      alternateRowStyles: {
        fillColor: zebraFill,
      },
    });
  }

  // Tabelas 3+: Resumo por função (Normal / Extra 50% / Extra 100%)
  type ResumoAgg = { funcao: string; valorHoraBase: number; horas: number; total: number };
  const resumoNormal = new Map<string, ResumoAgg>();
  const resumo50 = new Map<string, ResumoAgg>();
  const resumo100 = new Map<string, ResumoAgg>();

  for (const r of hhRows) {
    const funcao =
      r.especialidade_descricao && r.especialidade_descricao.trim() ? r.especialidade_descricao.trim() : "—";
    const valorHoraBase = Number(r.valor_hora ?? 0);
    const horas = getHorasTrabalhadasEfetivas(r);
    const split = getHorasSplitEfetivo(r, horas);

    const addBucket = (bucket: Map<string, ResumoAgg>, horasBucket: number, multiplier: number) => {
      if (!Number.isFinite(horasBucket) || horasBucket <= 0) return;
      const key = `${funcao}||${valorHoraBase}`;
      const cur = bucket.get(key) ?? { funcao, valorHoraBase, horas: 0, total: 0 };
      cur.horas += horasBucket;
      cur.total += Number((horasBucket * valorHoraBase * multiplier).toFixed(2));
      bucket.set(key, cur);
    };

    addBucket(resumoNormal, split.normais, 1);
    addBucket(resumo50, split.extra50, 1.5);
    addBucket(resumo100, split.extra100, 2);
  }

  const addResumoTable = (title: string, map: Map<string, ResumoAgg>, multiplier: number) => {
    const rows = Array.from(map.values()).filter((x) => (Number(x.horas) || 0) !== 0 || (Number(x.total) || 0) !== 0);
    if (!rows.length) return;

    rows.sort((a, b) => {
      const byFuncao = a.funcao.localeCompare(b.funcao, "pt-BR", { sensitivity: "base" });
      if (byFuncao !== 0) return byFuncao;
      return a.valorHoraBase - b.valorHoraBase;
    });

    const body: RowInput[] = [];
    let sumHoras = 0;
    let sumTotal = 0;

    for (const row of rows) {
      sumHoras += Number(row.horas ?? 0) || 0;
      sumTotal += Number(row.total ?? 0) || 0;
      body.push([
        row.funcao,
        formatHoursBR(row.horas),
        formatCurrencyBRL((Number(row.valorHoraBase ?? 0) || 0) * multiplier),
        formatCurrencyBRL(row.total),
      ]);
    }

    body.push(["TOTAL", formatHoursBR(sumHoras), "", formatCurrencyBRL(sumTotal)]);

    const lastY =
      (doc as unknown as { lastAutoTable?: { finalY?: number } }).lastAutoTable?.finalY ?? topStartY;

    // Title row (keeps title with table across page breaks)
    const titleRow =
      [
        {
          content: title,
          colSpan: 4,
          styles: {
            fillColor: [255, 255, 255],
            textColor: titleColor,
            fontStyle: "bold",
            halign: "left",
            fontSize: 10,
          },
        },
      ] as unknown as RowInput;

    const head: RowInput[] = [titleRow, ["Função", "Total horas", "Valor hora", "Total"]];

    autoTable.default(doc, {
      startY: lastY + 8,
      head,
      body,
      margin: { top: topStartY, left: margin, right: margin, bottom: 10 },
      styles: {
        cellPadding: 1.6,
        lineWidth: 0.1,
        lineColor: [220, 220, 220],
        overflow: "linebreak",
      },
      columnStyles: {
        0: { cellWidth: 120 }, // Função
        1: { cellWidth: 26, halign: "right" }, // Total horas
        2: { cellWidth: 28, halign: "right" }, // Valor hora
        3: { cellWidth: 28, halign: "right" }, // Total
      },
      headStyles: {
        fillColor: tableHeadFill,
        textColor: tableHeadText,
        fontSize: 9,
        fontStyle: "bold",
        lineWidth: 0.2,
        lineColor: [220, 220, 220],
        halign: "center",
      },
      bodyStyles: {
        fontSize: 8.6,
        textColor: tableBodyText,
      },
      alternateRowStyles: {
        fillColor: zebraFill,
      },
    });
  };

  addResumoTable("Resumo por função — Horas Normais", resumoNormal, 1);
  addResumoTable("Resumo por função — Extras 50%", resumo50, 1.5);
  addResumoTable("Resumo por função — Extras 100%", resumo100, 2);

  // Cabeçalho com paginação correta
  const pageCount = doc.getNumberOfPages();
  for (let page = 1; page <= pageCount; page += 1) {
    doc.setPage(page);
    drawHeader(page, pageCount);
  }

  return new Uint8Array(doc.output("arraybuffer"));
}
