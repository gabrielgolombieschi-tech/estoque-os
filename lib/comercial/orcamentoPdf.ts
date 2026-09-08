// Gerador do PDF do orcamento (o botao "Baixar PDF" da tela de impressao).
//
// Movido de app/comercial/orcamentos/[id]/imprimir/page.tsx. O layout esta
// igual; mudaram duas coisas para o mesmo codigo servir a tela e ao aplicativo:
//
//   1. a logo chega por um carregador injetado (fetch no navegador, disco no
//      servidor) em vez de um fetch fixo;
//   2. a funcao devolve os bytes do PDF em vez de gravar o arquivo.
//
// Quem chamou decide o destino: a tela abre o seletor de "salvar como", a rota
// devolve como resposta e o aplicativo manda direto para o compartilhamento.

import { formatDecimalBR, formatMoneyBR } from "@/lib/decimal";
import { n, upperTrim } from "@/lib/comercial/utils";
import type { CarregadorDeImagem } from "@/lib/pdf/imagemPdf";
import {
  formatDateBR,
  formatEnderecoCliente,
  GARANTIA_PADRAO,
  getClienteContatoPrintInfo,
  joinNonEmpty,
  validadeDoOrcamento,
  type DadosOrcamentoPdf,
} from "./orcamentoPdfDados";

export async function gerarOrcamentoPdf(
  dados: DadosOrcamentoPdf,
  opcoes: { carregarImagem: CarregadorDeImagem }
): Promise<Uint8Array> {
  const { orcamento: orc, itens, empresa, cliente, vendedor, condicaoNome, itemMetaById, estoqueByItemId } = dados;

  const garantia = GARANTIA_PADRAO;
  const validade = validadeDoOrcamento(orc);
  const totalProdutos = n(orc.total_produtos);
  const totalMaoDeObra = n(orc.total_servicos);
  const frete = n(orc.valor_frete);
  const totalProposta = n(orc.total_liquido);

  const [{ jsPDF }, autoTableMod] = await Promise.all([import("jspdf"), import("jspdf-autotable")]);
  const autoTable = autoTableMod.default;

  const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" });
  doc.setProperties({
    title: joinNonEmpty([upperTrim(orc.codigo), upperTrim(orc.titulo) || "ORCAMENTO"], " - ") || "Orcamento",
    subject: "Orcamento comercial",
    author: empresa?.razao_social ?? "SEGAU",
  });

  const pageWidth = doc.internal.pageSize.getWidth();
  const pageHeight = doc.internal.pageSize.getHeight();
  const margin = 10;
  const contentWidth = pageWidth - margin * 2;

  const card = (x: number, y: number, w: number, h: number) => {
    doc.setDrawColor(154, 154, 154);
    doc.setLineWidth(0.25);
    doc.roundedRect(x, y, w, h, 2.5, 2.5, "S");
  };

  const writeLabelValue = (label: string, value: string, xLabel: number, xValue: number, y: number, valueWidth: number) => {
    doc.setFont("helvetica", "normal");
    doc.setFontSize(7.5);
    doc.setTextColor(102, 102, 102);
    doc.text(label, xLabel, y);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(8);
    doc.setTextColor(17, 17, 17);
    const lines = doc.splitTextToSize(value || "-", valueWidth) as string[];
    doc.text(lines, xValue, y);
  };

  const codigoTitulo = joinNonEmpty([upperTrim(orc.codigo), upperTrim(orc.titulo) || "ORCAMENTO"], " - ");
  const clienteNome = cliente ? upperTrim(cliente.razao_social || cliente.nome) : "-";
  const clienteContato = getClienteContatoPrintInfo(orc, cliente);
  const clienteEndereco = formatEnderecoCliente(cliente);
  const usuarioProposta = vendedor?.nome ?? vendedor?.email ?? String(orc.vendedor_usuario_id ?? "-");
  const dataProposta = formatDateBR(orc.emissao_date);
  const empresaLinha = joinNonEmpty([empresa?.cnpj ? `CNPJ: ${empresa.cnpj}` : null, empresa?.ie ? `IE: ${empresa.ie}` : null], " | ") || "-";
  const empresaRodape =
    joinNonEmpty(
      [empresa?.endereco, joinNonEmpty([empresa?.cidade, empresa?.uf], " - "), vendedor?.email ? `Contato comercial: ${vendedor.email}` : null],
      " | "
    ) || "-";

  const logoDataUrl = await opcoes.carregarImagem("/Segau2.png");

  doc.setFont("helvetica", "bold");
  doc.setFontSize(12);
  doc.setTextColor(17, 17, 17);
  doc.text(codigoTitulo || "ORCAMENTO", pageWidth / 2, 11.5, { align: "center" });

  doc.setFont("helvetica", "normal");
  doc.setFontSize(7.5);
  doc.setTextColor(80, 80, 80);
  doc.text("Pagina:", pageWidth - margin - 18, 9.5, { align: "right" });
  doc.text("Data:", pageWidth - margin - 18, 13.5, { align: "right" });
  doc.setFont("helvetica", "bold");
  doc.setTextColor(17, 17, 17);
  doc.text("1", pageWidth - margin, 9.5, { align: "right" });
  doc.text(formatDateBR(orc.emissao_date), pageWidth - margin, 13.5, { align: "right" });

  const topY = 16;
  const topH = 45;
  card(margin, topY, contentWidth, topH);

  if (logoDataUrl) {
    try {
      doc.addImage(logoDataUrl, "PNG", margin + 4, topY + 3, 30, 9);
    } catch {
      // ignora falha do logo e segue com o PDF
    }
  } else {
    doc.setFont("helvetica", "bold");
    doc.setFontSize(16);
    doc.text("SEGAU", margin + 4, topY + 8);
  }

  doc.setFont("helvetica", "bold");
  doc.setFontSize(9.5);
  doc.text(empresa?.razao_social ?? "SEGAU", margin + 4, topY + 17);

  doc.setFont("helvetica", "normal");
  doc.setFontSize(7);
  doc.setTextColor(51, 51, 51);
  doc.text(doc.splitTextToSize(upperTrim(orc.codigo) || "-", 95) as string[], margin + 4, topY + 21);
  doc.text(doc.splitTextToSize(empresaLinha, 95) as string[], margin + 4, topY + 26);
  doc.text(doc.splitTextToSize(`Usuario: ${usuarioProposta}`, 95) as string[], margin + 4, topY + 31);
  doc.text(doc.splitTextToSize(`Data: ${dataProposta}`, 95) as string[], margin + 4, topY + 36);
  doc.text(doc.splitTextToSize(empresaRodape, contentWidth - 8) as string[], margin + 4, topY + 42.5);

  const proposalSplitX = pageWidth - margin - 96;
  const proposalLabelX = proposalSplitX + 4;
  const proposalValueX = proposalSplitX + 42;
  const proposalValueWidth = 46;
  doc.setDrawColor(229, 229, 229);
  doc.line(proposalSplitX, topY + 3, proposalSplitX, topY + topH - 6);

  doc.setFont("helvetica", "bold");
  doc.setFontSize(7.5);
  doc.setTextColor(102, 102, 102);
  doc.text("Dados da Proposta", pageWidth - margin - 4, topY + 6, { align: "right" });

  writeLabelValue(
    "Codigo/Numero",
    joinNonEmpty([orc.codigo, orc.numero ? `N${orc.numero}` : null], " | ") || "-",
    proposalLabelX,
    proposalValueX,
    topY + 10.5,
    proposalValueWidth
  );
  writeLabelValue("Validade", validade, proposalLabelX, proposalValueX, topY + 16.5, proposalValueWidth);
  writeLabelValue("Condicao", condicaoNome ?? "(sem)", proposalLabelX, proposalValueX, topY + 22.5, proposalValueWidth);
  writeLabelValue("Garantia", garantia, proposalLabelX, proposalValueX, topY + 28.5, proposalValueWidth);
  writeLabelValue("Ult. alteracao", formatDateBR(orc.updated_at), proposalLabelX, proposalValueX, topY + 34.5, proposalValueWidth);

  const clienteY = topY + topH + 3;
  const clienteH = 40;
  const itensStartY = clienteY + clienteH + 4;
  card(margin, clienteY, contentWidth, clienteH);
  doc.setFont("helvetica", "bold");
  doc.setFontSize(8.5);
  doc.setTextColor(17, 17, 17);
  doc.text("Cliente", margin + 4, clienteY + 6);
  writeLabelValue("Razao/Nome", clienteNome, margin + 4, margin + 28, clienteY + 11, 110);
  writeLabelValue("CPF/CNPJ", cliente?.documento ?? "-", margin + 4, margin + 28, clienteY + 16, 110);
  writeLabelValue("Contato", clienteContato.nome, margin + 4, margin + 28, clienteY + 21, 110);
  writeLabelValue("Setor", clienteContato.setor, margin + 150, margin + 168, clienteY + 11, 108);
  writeLabelValue("E-mail", clienteContato.email, margin + 150, margin + 168, clienteY + 16, 108);
  writeLabelValue("Telefone", clienteContato.telefone, margin + 150, margin + 168, clienteY + 21, 108);
  writeLabelValue("Endereco", clienteEndereco, margin + 4, margin + 28, clienteY + 32, contentWidth - 32);

  const body = itens.length
    ? itens.map((it) => {
        const meta = itemMetaById[Number(it.item_id)];
        const codigo = upperTrim(String(it.item_codigo_interno ?? "")) || upperTrim(String(meta?.codigo_interno ?? "")) || "-";
        const marca = upperTrim(String(meta?.fabricante ?? "")) || "-";
        const ncm = upperTrim(String(meta?.ncm ?? "")) || "-";
        const unid = upperTrim(String(it.unidade ?? "")) || upperTrim(String(meta?.unidade_medida ?? "")) || "UN";
        const itemId = Number(it.item_id);
        const qtdSolicitada = n(it.quantidade);
        const estoqueAtual = Number(estoqueByItemId[itemId] ?? 0);
        const prazoLinha =
          Number.isFinite(itemId) && Number.isFinite(qtdSolicitada) && estoqueAtual >= qtdSolicitada ? "ENTREGA IMEDIATA" : "A CONFIRMAR";

        return [
          codigo,
          upperTrim(String(it.item_nome ?? "")) || "-",
          marca,
          unid,
          ncm,
          formatDecimalBR(n(it.quantidade)),
          formatMoneyBR(n(it.valor_unitario_liquido)),
          formatMoneyBR(n(it.valor_total)),
          prazoLinha,
        ];
      })
    : [["-", "Nenhum item no orcamento.", "-", "-", "-", "-", "-", "-", "-"]];

  autoTable(doc, {
    startY: itensStartY,
    margin: { left: margin, right: margin, top: itensStartY, bottom: 34 },
    head: [["Codigo", "Produto/Servico", "Marca", "Unid", "NCM", "Qtd", "Valor Unit.", "Valor Total", "Prazo"]],
    body,
    theme: "grid",
    styles: {
      fontSize: 7.5,
      cellPadding: 1.8,
      overflow: "linebreak",
      lineColor: [199, 199, 199],
      lineWidth: 0.15,
      textColor: [17, 17, 17],
      valign: "middle",
    },
    headStyles: {
      fillColor: [233, 233, 233],
      textColor: [17, 17, 17],
      fontStyle: "bold",
    },
    alternateRowStyles: {
      fillColor: [245, 245, 245],
    },
    columnStyles: {
      0: { cellWidth: 24 },
      1: { cellWidth: 96 },
      2: { cellWidth: 26 },
      3: { cellWidth: 14 },
      4: { cellWidth: 22 },
      5: { cellWidth: 15, halign: "right" },
      6: { cellWidth: 24, halign: "right" },
      7: { cellWidth: 24, halign: "right" },
      8: { cellWidth: 32 },
    },
  });

  let footerY = ((doc as { lastAutoTable?: { finalY?: number } }).lastAutoTable?.finalY ?? itensStartY) + 4;
  if (footerY > pageHeight - 40) {
    doc.addPage();
    footerY = 18;
  }

  const footerLeftW = 152;
  const footerRightW = contentWidth - footerLeftW - 4;
  const footerH = 34;

  card(margin, footerY, footerLeftW, footerH);
  doc.setFont("helvetica", "bold");
  doc.setFontSize(8.5);
  doc.text("Observacoes", margin + 4, footerY + 6);
  doc.setFont("helvetica", "normal");
  doc.setFontSize(7.5);
  doc.text(doc.splitTextToSize(upperTrim(String(orc.observacoes ?? "")) || "-", footerLeftW - 8) as string[], margin + 4, footerY + 11);

  card(margin + footerLeftW + 4, footerY, footerRightW, footerH);
  const totalXLabel = margin + footerLeftW + 8;
  const totalXValue = margin + footerLeftW + footerRightW;
  doc.setFont("helvetica", "normal");
  doc.setFontSize(7.5);
  doc.text("Valor total dos produtos", totalXLabel, footerY + 7);
  doc.text("Valor mao de obra", totalXLabel, footerY + 12);
  doc.text("Frete", totalXLabel, footerY + 17);
  doc.setFont("helvetica", "bold");
  doc.text(formatMoneyBR(totalProdutos), totalXValue - 4, footerY + 7, { align: "right" });
  doc.text(formatMoneyBR(totalMaoDeObra), totalXValue - 4, footerY + 12, { align: "right" });
  doc.text(formatMoneyBR(frete), totalXValue - 4, footerY + 17, { align: "right" });
  doc.setDrawColor(199, 199, 199);
  doc.line(margin + footerLeftW + 8, footerY + 21, totalXValue - 4, footerY + 21);
  doc.text("Total proposta", totalXLabel, footerY + 27);
  doc.setFontSize(10);
  doc.text(formatMoneyBR(totalProposta), totalXValue - 4, footerY + 27, { align: "right" });
  doc.setFont("helvetica", "normal");
  doc.setFontSize(7);
  doc.text("Impostos inclusos.", totalXLabel, footerY + 31);

  const pages = doc.getNumberOfPages();
  for (let i = 1; i <= pages; i += 1) {
    doc.setPage(i);
    doc.setFont("helvetica", "normal");
    doc.setFontSize(7);
    doc.setTextColor(90, 90, 90);
    doc.text(`Pagina ${i} de ${pages}`, pageWidth - margin, pageHeight - 4, { align: "right" });
  }

  return new Uint8Array(doc.output("arraybuffer"));
}
