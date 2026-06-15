"use client";

import Link from "next/link";
import { useParams, useSearchParams } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny } from "@/lib/auth/capabilities";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import type { OrcamentoItemRow, OrcamentoRow } from "@/lib/comercial/types";
import { getOrcamento } from "@/lib/comercial/orcamentos.service";
import { formatDecimalBR, formatMoneyBR } from "@/lib/decimal";
import { n, upperTrim } from "@/lib/comercial/utils";

type EmpresaRow = {
  id: string;
  tenant_id: string;
  cnpj: string;
  razao_social: string;
  nome_fantasia: string | null;
  ie: string | null;
  uf: string | null;
  cidade: string | null;
  endereco: string | null;
};

type ClienteRow = {
  id: number;
  nome: string;
  razao_social: string | null;
  documento: string | null;
  email: string | null;
  telefone: string | null;
  logradouro: string | null;
  numero_endereco: string | null;
  complemento: string | null;
  bairro: string | null;
  cidade: string | null;
  uf: string | null;
  cep: string | null;
};

type UsuarioRow = { id: string; nome: string | null; email: string | null };

type ItemMetaRow = {
  id: number;
  codigo_interno: string | null;
  fabricante: string | null;
  ncm: string | null;
  unidade_medida: string | null;
};

type EstoqueRow = {
  item_id: number;
  quantidade_atual: number | null;
};

type ClienteContatoPrintInfo = {
  nome: string;
  setor: string;
  email: string;
  telefone: string;
};

type SaveFilePickerOptionsLike = {
  suggestedName?: string;
  types?: Array<{
    description?: string;
    accept: Record<string, string[]>;
  }>;
};

type FileSystemWritableFileStreamLike = {
  write(data: Blob): Promise<void>;
  close(): Promise<void>;
};

type FileSystemFileHandleLike = {
  createWritable(): Promise<FileSystemWritableFileStreamLike>;
};

type WindowWithSaveFilePicker = Window & {
  showSaveFilePicker?: (options?: SaveFilePickerOptionsLike) => Promise<FileSystemFileHandleLike>;
};

function formatDateBR(iso?: string | null) {
  if (!iso) return "-";
  const [y, m, d] = String(iso).slice(0, 10).split("-");
  if (!y || !m || !d) return String(iso);
  return `${d}/${m}/${y}`;
}

function addDays(dateLike: string | null | undefined, days: number): Date | null {
  const base = dateLike ? new Date(dateLike) : null;
  if (!base || Number.isNaN(base.getTime())) return null;
  const out = new Date(base);
  out.setDate(out.getDate() + days);
  return out;
}

function joinNonEmpty(parts: Array<string | null | undefined>, sep: string) {
  return parts
    .map((p) => String(p ?? "").trim())
    .filter(Boolean)
    .join(sep);
}

function formatEnderecoCliente(cli: ClienteRow | null) {
  if (!cli) return "-";
  const linha1 = joinNonEmpty(
    [
      cli.logradouro,
      cli.numero_endereco ? `, ${cli.numero_endereco}` : null,
      cli.complemento ? ` - ${cli.complemento}` : null,
    ],
    ""
  ).trim();
  const linha2 = joinNonEmpty([cli.bairro, cli.cidade, cli.uf], " - ");
  const cep = cli.cep ? `CEP: ${cli.cep}` : "";
  return joinNonEmpty([linha1 || null, linha2 || null, cep || null], " | ") || "-";
}

function lowerTrim(value: string | null | undefined) {
  return String(value ?? "").trim().toLocaleLowerCase("pt-BR");
}

function getClienteContatoPrintInfo(orc: OrcamentoRow | null, cli: ClienteRow | null): ClienteContatoPrintInfo {
  return {
    nome: upperTrim(String(orc?.solicitante_nome ?? "")) || "-",
    setor: upperTrim(String(orc?.solicitante_setor ?? "")) || "-",
    email: lowerTrim(orc?.solicitante_email) || lowerTrim(cli?.email) || "-",
    telefone: String(orc?.solicitante_telefone ?? "").trim() || String(cli?.telefone ?? "").trim() || "-",
  };
}

function blobToDataUrl(blob: Blob) {
  return new Promise<string | null>((resolve) => {
    const reader = new FileReader();
    reader.onload = () => resolve(typeof reader.result === "string" ? reader.result : null);
    reader.onerror = () => resolve(null);
    reader.readAsDataURL(blob);
  });
}

async function fetchImageAsDataUrl(src: string) {
  try {
    const res = await fetch(src, { cache: "force-cache" });
    if (!res.ok) return null;
    return await blobToDataUrl(await res.blob());
  } catch {
    return null;
  }
}

async function pickPdfSaveHandle(suggestedName: string): Promise<FileSystemFileHandleLike | "cancelled" | "unsupported"> {
  const picker = (window as WindowWithSaveFilePicker).showSaveFilePicker;
  if (!picker) return "unsupported";

  try {
    return await picker({
      suggestedName,
      types: [
        {
          description: "Arquivo PDF",
          accept: { "application/pdf": [".pdf"] },
        },
      ],
    });
  } catch (error: unknown) {
    const name = typeof error === "object" && error !== null && "name" in error ? String((error as { name?: unknown }).name ?? "") : "";
    if (name === "AbortError") return "cancelled";
    throw error;
  }
}

async function writeBlobToFileHandle(handle: FileSystemFileHandleLike, blob: Blob): Promise<void> {
  const writable = await handle.createWritable();
  await writable.write(blob);
  await writable.close();
}

export default function OrcamentoImprimirPage() {
  const params = useParams();
  const rawId = (params as Record<string, string | string[] | undefined>)?.id;
  const idParam = String(Array.isArray(rawId) ? rawId[0] : rawId ?? "");

  const sp = useSearchParams();
  const auto = String(sp.get("auto") ?? "").trim() === "1";

  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);

  const te = useTenantEmpresa();
  const tenantId = te.tenantId;
  const empresaId = te.empresaId;

  const { loading: permissionsLoading, ready, capabilities } = usePermissions();
  const canView = requireAny(capabilities, ["financeiro.read", "financeiro.write", "os.read", "os.write"]);

  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [orc, setOrc] = useState<OrcamentoRow | null>(null);
  const [itens, setItens] = useState<OrcamentoItemRow[]>([]);
  const [empresa, setEmpresa] = useState<EmpresaRow | null>(null);
  const [cliente, setCliente] = useState<ClienteRow | null>(null);
  const [vendedor, setVendedor] = useState<UsuarioRow | null>(null);
  const [condicaoNome, setCondicaoNome] = useState<string | null>(null);
  const [itemMetaById, setItemMetaById] = useState<Record<number, ItemMetaRow>>({});
  const [estoqueByItemId, setEstoqueByItemId] = useState<Record<number, number>>({});
  const [downloadingPdf, setDownloadingPdf] = useState(false);
  const [pdfErr, setPdfErr] = useState<string | null>(null);

  const didAutoPrintRef = useRef(false);

  useEffect(() => {
    const run = async () => {
      setErr(null);

      if (!supabase) return;
      if (!ready && permissionsLoading) return;
      if (!canView) {
        setLoading(false);
        setErr("Acesso negado.");
        return;
      }

      if (!tenantId || !empresaId) {
        setLoading(false);
        setErr("Contexto (tenant/empresa) nao carregado.");
        return;
      }

      setLoading(true);
      try {
        const { orcamento } = await getOrcamento(supabase, { tenantId, empresaId, idOrCodigo: idParam });
        setOrc(orcamento);

        const { data: itensRows, error: itensErr } = await applyTenantEmpresa(
          supabase.schema("r").from("r_orcamento_itens").select("*").eq("orcamento_id", orcamento.id).order("seq", { ascending: true }),
          tenantId,
          empresaId
        ).returns<OrcamentoItemRow[]>();
        if (itensErr) throw itensErr;
        const itens = (itensRows ?? []) as OrcamentoItemRow[];
        setItens(itens);

        const { data: emp, error: empErr } = await supabase
          .from("empresas")
          .select("id,tenant_id,cnpj,razao_social,nome_fantasia,ie,uf,cidade,endereco")
          .eq("tenant_id", tenantId)
          .eq("id", empresaId)
          .maybeSingle<EmpresaRow>();
        if (empErr) throw empErr;
        setEmpresa(emp?.id ? (emp as EmpresaRow) : null);

        const clienteId = Number(orcamento.cliente_id ?? 0);
        if (Number.isFinite(clienteId) && clienteId > 0) {
          const { data: cli, error: cliErr } = await applyTenantEmpresa(
            supabase
              .from("clientes")
              .select(
                "id,nome,razao_social,documento,email,telefone,logradouro,numero_endereco,complemento,bairro,cidade,uf,cep"
              )
              .eq("id", clienteId)
              .maybeSingle<ClienteRow>(),
            tenantId,
            empresaId
          );
          if (cliErr) throw cliErr;
          setCliente(cli?.id ? (cli as ClienteRow) : null);
        } else {
          setCliente(null);
        }

        const vendedorId = String(orcamento.vendedor_usuario_id ?? "").trim();
        if (vendedorId) {
          const { data: vend, error: vendErr } = await supabase
            .schema("a")
            .from("usuario")
            .select("id,nome,email")
            .eq("id", vendedorId)
            .is("deleted_at", null)
            .maybeSingle<UsuarioRow>();
          if (!vendErr) setVendedor(vend?.id ? (vend as UsuarioRow) : null);
        } else {
          setVendedor(null);
        }

        const condId = String(orcamento.condicao_pagamento_id ?? "").trim();
        if (condId) {
          const { data: cp, error: cpErr } = await applyTenantEmpresa(
            supabase.schema("c").from("condicao_pagamento").select("id,nome").eq("id", condId).maybeSingle<{ id: string; nome: string | null }>(),
            tenantId,
            empresaId
          );
          if (!cpErr) setCondicaoNome(cp?.nome ?? condId);
          else setCondicaoNome(condId);
        } else {
          setCondicaoNome(null);
        }

        // Enrich itens: marca/ncm/unidade/codigo (para garantir o campo Codigo no doc).
        try {
          const itemIds = Array.from(
            new Set(
              itens
                .map((it) => Number(it.item_id))
                .filter((v) => Number.isFinite(v) && v > 0)
            )
          );
          if (itemIds.length > 0) {
            const { data: metas, error: metasErr } = await applyTenantEmpresa(
              supabase
                .from("itens")
                .select("id,codigo_interno,fabricante,ncm,unidade_medida")
                .in("id", itemIds),
              tenantId,
              empresaId
            ).returns<ItemMetaRow[]>();
            if (!metasErr && metas) {
              const map: Record<number, ItemMetaRow> = {};
              for (const r of metas) {
                const id = Number(r.id);
                if (Number.isFinite(id) && id > 0) map[id] = r;
              }
              setItemMetaById(map);
            }

            const { data: estoqueRows, error: estoqueErr } = await applyTenantEmpresa(
              supabase.from("estoque").select("item_id,quantidade_atual").in("item_id", itemIds),
              tenantId,
              empresaId
            ).returns<EstoqueRow[]>();
            if (!estoqueErr && estoqueRows) {
              const estoqueMap: Record<number, number> = {};
              for (const row of estoqueRows) {
                const itemId = Number(row.item_id);
                const qtd = Number(row.quantidade_atual ?? 0);
                if (Number.isFinite(itemId) && itemId > 0) estoqueMap[itemId] = Number.isFinite(qtd) ? qtd : 0;
              }
              setEstoqueByItemId(estoqueMap);
            } else {
              setEstoqueByItemId({});
            }
          }
        } catch {
          // best-effort
          setEstoqueByItemId({});
        }
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : "Erro ao carregar.";
        setErr(msg);
        setOrc(null);
        setItens([]);
        setEmpresa(null);
        setCliente(null);
        setVendedor(null);
        setCondicaoNome(null);
        setItemMetaById({});
        setEstoqueByItemId({});
      } finally {
        setLoading(false);
      }
    };

    void run();
  }, [canView, empresaId, idParam, permissionsLoading, ready, supabase, tenantId]);

  useEffect(() => {
    if (!auto) return;
    if (didAutoPrintRef.current) return;
    if (loading || err || !orc) return;
    didAutoPrintRef.current = true;
    const t = setTimeout(() => window.print(), 250);
    return () => clearTimeout(t);
  }, [auto, err, loading, orc]);

  const garantia = "1 ANO CONTRA DEFEITOS DE FABRICACAO.";
  const validade = useMemo(() => {
    const ate = addDays(orc?.updated_at, 30);
    if (!ate) return "30 DIAS.";
    return `ATE ${ate.toLocaleDateString("pt-BR")}.`;
  }, [orc?.updated_at]);

  const totalProdutos = n(orc?.total_produtos);
  const totalMaoDeObra = n(orc?.total_servicos);
  const frete = n(orc?.valor_frete);
  const totalProposta = n(orc?.total_liquido);
  const clienteContatoPrint = useMemo(() => getClienteContatoPrintInfo(orc, cliente), [cliente, orc]);

  async function handleDownloadPdf() {
    if (!orc) return;

    const safeFileBase = (upperTrim(orc.codigo) || `orcamento-${idParam}` || "orcamento")
      .replace(/[\\/:*?"<>|]+/g, "-")
      .replace(/\s+/g, " ")
      .trim();
    const fileName = `${safeFileBase || "orcamento"}.pdf`;

    setPdfErr(null);
    setDownloadingPdf(true);
    try {
      const saveHandle = await pickPdfSaveHandle(fileName);
      if (saveHandle === "cancelled") return;

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

      const logoDataUrl = await fetchImageAsDataUrl("/Segau2.png");

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

      const blob = doc.output("blob");
      if (saveHandle === "unsupported") {
        doc.save(fileName);
      } else {
        await writeBlobToFileHandle(saveHandle, blob);
      }
    } catch (e: unknown) {
      console.error(e);
      setPdfErr(e instanceof Error ? e.message : "Falha ao gerar PDF.");
    } finally {
      setDownloadingPdf(false);
    }
  }

  return (
    <div className="orc-imp-root">
      <style jsx global>{`
        @page {
          /* Dimensoes fisicas evitam PDF salvo como A4 retrato com metadata de rotacao. */
          size: 297mm 210mm;
          page-orientation: upright;
          margin: 10mm;
        }

        html,
        body {
          background: #fff !important;
          color: #111 !important;
          height: auto !important;
        }
        body {
          margin: 0 !important;
        }
        :root {
          /* Evita o navegador aplicar heuristicas de tema escuro no print. */
          color-scheme: light !important;
        }
        main {
          background: #fff !important;
        }

        * {
          -webkit-print-color-adjust: exact;
          print-color-adjust: exact;
        }

        @media print {
          .orc-imp-toolbar {
            display: none !important;
          }
          main {
            padding: 0 !important;
            margin: 0 !important;
            max-width: none !important;
          }
          html,
          body,
          main,
          .orc-imp-root,
          .orc-imp-sheet {
            background: #fff !important;
            color: #111 !important;
          }
          .orc-imp-sheet {
            width: auto !important;
            max-width: none !important;
            min-height: 0 !important;
            padding: 0 !important;
          }
          .orc-imp-tableCard {
            break-inside: auto !important;
            page-break-inside: auto !important;
          }
        }

        .orc-imp-sheet {
          width: 277mm;
          max-width: 277mm;
          margin: 0 auto;
          /* Em tela mantemos a moldura visual equivalente a uma folha A4. */
          padding: 10mm;
          box-sizing: border-box;
          font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial;
          font-size: 12px;
          color: #111;
        }

        .orc-imp-toolbar {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 10px;
          padding: 10px 14px;
          border-bottom: 1px solid #ddd;
          position: sticky;
          top: 0;
          background: #fff;
          z-index: 5;
        }

        .orc-imp-btn {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          gap: 8px;
          padding: 8px 10px;
          border-radius: 8px;
          border: 1px solid #bbb;
          background: #fff;
          color: #111;
          text-decoration: none;
          font-size: 12px;
          font-weight: 700;
          cursor: pointer;
        }

        .orc-imp-btnPrimary {
          border-color: #111;
          background: #111;
          color: #fff;
        }

        .orc-imp-card {
          border: 1px solid #9a9a9a;
          border-radius: 10px;
          padding: 10px 12px;
          break-inside: avoid;
          page-break-inside: avoid;
        }

        .headerCard {
          border: 1px solid #d7d7d7;
          border-radius: 10px;
          padding: 10px 12px;
          break-inside: avoid;
          page-break-inside: avoid;
        }

        .headerTopLine {
          display: grid;
          grid-template-columns: 1fr 1fr 220px;
          align-items: center;
          gap: 10px;
          margin-bottom: 16px;
        }

        .headerCenterTitle {
          text-align: center;
          font-size: 14px;
          font-weight: 900;
          color: #111;
          letter-spacing: 0.01em;
          line-height: 1.2;
        }

        .headerRightMeta {
          display: grid;
          grid-template-columns: auto auto;
          justify-content: end;
          gap: 4px 8px;
          align-items: baseline;
        }

        .headerRightMetaLabel {
          font-size: 9px;
          color: #666;
          text-align: right;
          white-space: nowrap;
        }

        .headerRightMetaValue {
          font-size: 10px;
          font-weight: 800;
          color: #111;
          text-align: right;
          white-space: nowrap;
        }

        .headerTopGrid {
          display: grid;
          grid-template-columns: minmax(0, 1fr) 344px;
          gap: 12px;
          align-items: start;
        }

        .companyBlock {
          min-width: 0;
        }

        .companyLogo {
          width: auto;
          height: 32px;
          display: block;
          flex: 0 0 auto;
          margin-top: 1px;
        }

        .companyTitle {
          font-size: 14px;
          font-weight: 900;
          line-height: 1.15;
          margin: 0;
          color: #111;
        }

        .companySub {
          font-size: 9px;
          color: #333;
          line-height: 1.35;
        }

        .docMetaBlock {
          border-left: 1px solid #e5e5e5;
          padding-left: 12px;
        }

        .docMetaTitle {
          font-size: 9px;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: #666;
          font-weight: 800;
          margin-bottom: 6px;
          text-align: right;
        }

        .docMetaGrid {
          display: grid;
          grid-template-columns: auto 1fr;
          gap: 4px 10px;
          align-items: baseline;
        }

        .docMetaLabel {
          font-size: 9px;
          color: #666;
          text-align: right;
          white-space: nowrap;
        }

        .docMetaValue {
          font-size: 10px;
          font-weight: 800;
          color: #111;
          text-align: right;
          white-space: nowrap;
        }

        .headerBottomLine {
          margin-top: 8px;
          padding-top: 7px;
          border-top: 1px solid #ececec;
          font-size: 9px;
          color: #333;
          line-height: 1.35;
          word-break: break-word;
        }

        @media screen and (max-width: 900px) {
          .headerTopLine {
            grid-template-columns: 1fr;
          }
          .headerCenterTitle {
            text-align: left;
          }
          .headerRightMeta {
            justify-content: start;
          }
          .headerRightMetaLabel,
          .headerRightMetaValue {
            text-align: left;
          }
          .headerTopGrid {
            grid-template-columns: 1fr;
          }
          .docMetaBlock {
            border-left: 0;
            border-top: 1px solid #e5e5e5;
            padding-left: 0;
            padding-top: 8px;
          }
          .docMetaTitle,
          .docMetaLabel,
          .docMetaValue {
            text-align: left;
          }
          .orc-imp-clientGrid {
            grid-template-columns: 1fr;
          }
        }

        .orc-imp-titleSmall {
          font-size: 11px;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: #222;
          font-weight: 700;
        }

        .orc-imp-title {
          font-size: 18px;
          font-weight: 900;
          letter-spacing: 0.02em;
        }

        .orc-imp-muted {
          color: #222;
          font-size: 11px;
        }

        .orc-imp-kv {
          display: grid;
          grid-template-columns: 140px 1fr;
          gap: 6px 10px;
          align-items: baseline;
        }

        .orc-imp-clientGrid {
          display: grid;
          grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
          gap: 6px 28px;
          align-items: start;
        }

        .orc-imp-clientColumn,
        .orc-imp-clientAddress {
          display: grid;
          grid-template-columns: 140px 1fr;
          gap: 6px 10px;
          align-items: baseline;
        }

        .orc-imp-clientAddress {
          margin-top: 6px;
        }

        .orc-imp-k {
          color: #222;
          font-size: 11px;
        }

        .orc-imp-v {
          font-weight: 700;
        }

        .orc-imp-spacer {
          height: 10px;
        }

        .orc-imp-items {
          width: 100%;
          border-collapse: collapse;
          table-layout: fixed;
          font-size: 11px;
          break-inside: auto;
          page-break-inside: auto;
        }

        .orc-imp-items thead {
          display: table-header-group;
        }

        .orc-imp-items tbody {
          break-inside: auto;
          page-break-inside: auto;
        }

        .orc-imp-items th {
          text-align: left;
          font-weight: 900;
          padding: 8px 8px;
          border-bottom: 1px solid #666;
          background: #e9e9e9;
          white-space: nowrap;
          color: #111;
        }

        .orc-imp-items td {
          padding: 7px 8px;
          border-bottom: 1px solid #c7c7c7;
          vertical-align: top;
          white-space: nowrap;
          color: #111;
        }

        .orc-imp-items tbody tr:nth-child(even) {
          background: #f5f5f5;
        }

        .orc-imp-right {
          text-align: right;
          font-variant-numeric: tabular-nums;
        }

        .orc-imp-wrap {
          white-space: normal !important;
          word-break: break-word;
        }

        .orc-imp-items tr {
          break-inside: avoid;
          page-break-inside: avoid;
        }

        .orc-imp-footerGrid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 10px;
          align-items: stretch;
        }

        .orc-imp-rightAlignedCard {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 10px;
          align-items: stretch;
        }

        .orc-imp-rightAlignedCard > .orc-imp-card {
          grid-column: 2;
        }

        .orc-imp-totalRow {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 12px;
          padding: 4px 0;
        }

        .orc-imp-totalLabel {
          font-size: 11px;
          color: #222;
        }

        .orc-imp-totalValue {
          font-weight: 900;
          font-variant-numeric: tabular-nums;
        }

      `}</style>

      <div className="orc-imp-toolbar">
        <div className="orc-imp-muted">
          {orc?.codigo ? (
            <>
              Proposta: <strong>{orc.codigo}</strong>
            </>
          ) : (
            "Impressao do orcamento"
          )}
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <Link className="orc-imp-btn" href={`/comercial/orcamentos/${encodeURIComponent(String(orc?.codigo || idParam))}`}>
            Voltar
          </Link>
          <button type="button" className="orc-imp-btn" onClick={() => void handleDownloadPdf()} disabled={loading || !!err || downloadingPdf}>
            {downloadingPdf ? "Gerando PDF..." : "Baixar PDF"}
          </button>
          <button type="button" className="orc-imp-btn orc-imp-btnPrimary" onClick={() => window.print()} disabled={loading || !!err || downloadingPdf}>
            Imprimir
          </button>
        </div>
      </div>
      {pdfErr ? (
        <div className="orc-imp-muted" style={{ padding: "8px 14px 0 14px", color: "#991b1b" }}>
          {pdfErr}
        </div>
      ) : null}

      <div className="orc-imp-sheet">
        {err ? (
          <div className="orc-imp-muted" style={{ padding: 14 }}>
            {err}
          </div>
        ) : loading || !orc ? (
          <div className="orc-imp-muted" style={{ padding: 14 }}>
            Carregando...
          </div>
        ) : (
          <>
            <div className="headerTopLine">
              <div>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img className="companyLogo" src="/Segau2.png" alt="SEGAU" />
              </div>
              <div className="headerCenterTitle">
                {joinNonEmpty([upperTrim(orc.codigo), upperTrim(orc.titulo) || "ORCAMENTO"], " - ")}
              </div>
              <div className="headerRightMeta">
                <div className="headerRightMetaLabel">Pagina:</div>
                <div className="headerRightMetaValue">1</div>
                <div className="headerRightMetaLabel">Data:</div>
                <div className="headerRightMetaValue">{formatDateBR(orc.emissao_date)}</div>
              </div>
            </div>

            <div className="headerCard">
              <div className="headerTopGrid">
                <div className="companyBlock">
                  <div style={{ minWidth: 0 }}>
                    <h1 className="companyTitle">{empresa?.razao_social ?? "SEGAU"}</h1>
                    <div className="companySub" style={{ marginTop: 3 }}>
                      {orc.codigo ? <span>{orc.codigo}</span> : null}
                    </div>
                    <div className="companySub">
                      {joinNonEmpty([empresa?.cnpj ? `CNPJ: ${empresa.cnpj}` : null, empresa?.ie ? `IE: ${empresa.ie}` : null], " | ") || "-"}
                    </div>
                    <div className="companySub">Usuario: {vendedor?.nome ?? vendedor?.email ?? orc.vendedor_usuario_id}</div>
                    <div className="companySub">Data: {formatDateBR(orc.emissao_date)}</div>
                  </div>
                </div>

                <div className="docMetaBlock">
                  <div className="docMetaTitle">Dados da Proposta</div>
                  <div className="docMetaGrid">
                    <div className="docMetaLabel">Codigo/Numero</div>
                    <div className="docMetaValue">{joinNonEmpty([orc.codigo, orc.numero ? `N${orc.numero}` : null], " | ") || "-"}</div>

                    <div className="docMetaLabel">Validade</div>
                    <div className="docMetaValue">{validade}</div>

                    <div className="docMetaLabel">Condicao</div>
                    <div className="docMetaValue">{condicaoNome ?? "(sem)"}</div>

                    <div className="docMetaLabel">Garantia</div>
                    <div className="docMetaValue">{garantia}</div>

                    <div className="docMetaLabel">Ult. alteracao</div>
                    <div className="docMetaValue">{formatDateBR(orc.updated_at)}</div>
                  </div>
                </div>
              </div>

              <div className="headerBottomLine">
                {joinNonEmpty(
                  [
                    empresa?.endereco,
                    joinNonEmpty([empresa?.cidade, empresa?.uf], " - "),
                    vendedor?.email ? `Contato comercial: ${vendedor.email}` : null,
                  ],
                  " | "
                ) || "-"}
              </div>
            </div>

            <div className="orc-imp-spacer" />

            <div className="orc-imp-card">
              <div style={{ fontWeight: 900, marginBottom: 6 }}>Cliente</div>
              <div className="orc-imp-clientGrid">
                <div className="orc-imp-clientColumn">
                  <div className="orc-imp-k">Razao/Nome</div>
                  <div className="orc-imp-v">{cliente ? upperTrim(cliente.razao_social || cliente.nome) : "-"}</div>

                  <div className="orc-imp-k">CPF/CNPJ</div>
                  <div className="orc-imp-v">{cliente?.documento ?? "-"}</div>

                  <div className="orc-imp-k">Contato</div>
                  <div className="orc-imp-v">{clienteContatoPrint.nome}</div>
                </div>

                <div className="orc-imp-clientColumn">
                  <div className="orc-imp-k">Setor</div>
                  <div className="orc-imp-v">{clienteContatoPrint.setor}</div>

                  <div className="orc-imp-k">E-mail</div>
                  <div className="orc-imp-v">{clienteContatoPrint.email}</div>

                  <div className="orc-imp-k">Telefone</div>
                  <div className="orc-imp-v">{clienteContatoPrint.telefone}</div>
                </div>
              </div>

              <div className="orc-imp-clientAddress">
                <div className="orc-imp-k">Endereco</div>
                <div className="orc-imp-v">{formatEnderecoCliente(cliente)}</div>
              </div>
            </div>

            <div className="orc-imp-spacer" />

            <div className="orc-imp-card orc-imp-tableCard">
              <table className="orc-imp-items">
                <thead>
                  <tr>
                    <th style={{ width: 90 }}>Codigo</th>
                    <th>Produto/Servico</th>
                    <th style={{ width: 120 }}>Marca</th>
                    <th style={{ width: 52 }}>Unid</th>
                    <th style={{ width: 70 }}>NCM</th>
                    <th style={{ width: 62 }} className="orc-imp-right">
                      Qtd
                    </th>
                    <th style={{ width: 88 }} className="orc-imp-right">
                      Valor Unit.
                    </th>
                    <th style={{ width: 92 }} className="orc-imp-right">
                      Valor Total
                    </th>
                    <th style={{ width: 110 }}>Prazo</th>
                  </tr>
                </thead>
                <tbody>
                  {itens.length === 0 ? (
                    <tr>
                      <td colSpan={9} className="orc-imp-muted">
                        Nenhum item no orcamento.
                      </td>
                    </tr>
                  ) : (
                    itens.map((it) => {
                      const meta = itemMetaById[Number(it.item_id)];
                      const codigo =
                        upperTrim(String(it.item_codigo_interno ?? "")) || upperTrim(String(meta?.codigo_interno ?? "")) || "-";
                      const marca = upperTrim(String(meta?.fabricante ?? "")) || "-";
                      const ncm = upperTrim(String(meta?.ncm ?? "")) || "-";
                      const unid = upperTrim(String(it.unidade ?? "")) || upperTrim(String(meta?.unidade_medida ?? "")) || "UN";
                      const itemId = Number(it.item_id);
                      const qtdSolicitada = n(it.quantidade);
                      const estoqueAtual = Number(estoqueByItemId[itemId] ?? 0);
                      const prazoLinha =
                        Number.isFinite(itemId) && Number.isFinite(qtdSolicitada) && estoqueAtual >= qtdSolicitada
                          ? "ENTREGA IMEDIATA"
                          : "A CONFIRMAR";
                      return (
                        <tr key={it.id}>
                          <td>{codigo}</td>
                          <td className="orc-imp-wrap">{it.item_nome}</td>
                          <td className="orc-imp-wrap">{marca}</td>
                          <td>{unid}</td>
                          <td>{ncm}</td>
                          <td className="orc-imp-right">{formatDecimalBR(n(it.quantidade))}</td>
                          <td className="orc-imp-right">{formatMoneyBR(n(it.valor_unitario_liquido))}</td>
                          <td className="orc-imp-right">{formatMoneyBR(n(it.valor_total))}</td>
                          <td>{prazoLinha}</td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>

            <div className="orc-imp-spacer" />

            <div className="orc-imp-footerGrid">
              <div className="orc-imp-card">
                <div style={{ fontWeight: 900, marginBottom: 6 }}>Observacoes</div>
                <div className="orc-imp-v orc-imp-wrap">{upperTrim(String(orc.observacoes ?? "")) || "-"}</div>
              </div>

              <div className="orc-imp-card">
                <div className="orc-imp-totalRow">
                  <span className="orc-imp-totalLabel">Valor total dos produtos</span>
                  <span className="orc-imp-totalValue">{formatMoneyBR(totalProdutos)}</span>
                </div>
                <div className="orc-imp-totalRow">
                  <span className="orc-imp-totalLabel">Valor mao de obra</span>
                  <span className="orc-imp-totalValue">{formatMoneyBR(totalMaoDeObra)}</span>
                </div>
                <div className="orc-imp-totalRow">
                  <span className="orc-imp-totalLabel">Frete</span>
                  <span className="orc-imp-totalValue">{formatMoneyBR(frete)}</span>
                </div>
                <div className="orc-imp-totalRow" style={{ borderTop: "1px solid #c7c7c7", marginTop: 6, paddingTop: 8 }}>
                  <span className="orc-imp-totalLabel" style={{ fontWeight: 900 }}>
                    Total proposta
                  </span>
                  <span className="orc-imp-totalValue" style={{ fontSize: 14 }}>
                    {formatMoneyBR(totalProposta)}
                  </span>
                </div>
                <div className="orc-imp-muted" style={{ marginTop: 8 }}>
                  Impostos inclusos.
                </div>
              </div>
            </div>

          </>
        )}
      </div>
    </div>
  );
}
