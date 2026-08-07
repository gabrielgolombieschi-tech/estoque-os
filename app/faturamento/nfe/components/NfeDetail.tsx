"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { formatMoneyBR } from "@/lib/decimal";
import type { CapabilityKey } from "@/lib/auth/capabilities";
import OsVinculoField from "@/app/faturamento/components/OsVinculoField";
import { fetchOsSelectionById, type OsSelection } from "@/lib/os-vinculo";
import {
  imprimirRelatorioDestinos,
  type RelatorioDestinoImportacao,
  type RelatorioDestinoItem,
} from "@/app/estoque/importar/relatorioDestinoPrint";

type DocumentoFiscalRow = {
  id: string;
  operacao: string;
  natureza: string;
  modelo: string | null;
  serie: string | null;
  numero: string | null;
  chave_acesso: string;
  emissao_date: string | null;
  valor_total: number | string | null;
  fornecedor_id: number | null;
  cliente_id: number | null;
  os_id_import?: number | null;
  created_at: string;
  source_nf_entrada_id?: number | null;
};

type ItemRow = {
  id: string;
  item_n: number;
  item_tipo: string;
  descricao: string;
  ncm: string | null;
  cfop: string | null;
  quantidade: number | string;
  valor_unitario: number | string;
  valor_total: number | string;
};

type NfEntradaItemRow = {
  id: number;
  item_id: number | string | null;
  descricao: string | null;
  ncm: string | null;
  cfop: string | null;
  qtd: number | string | null;
  v_unit: number | string | null;
  v_prod: number | string | null;
  codigo_fornecedor?: string | null;
  itens?: { nome: string | null; cfop_padrao: string | null; unidade_medida?: string | null; codigo_interno?: string | null } | null;
};

type ImpostoRow = {
  id: string;
  imposto: string;
  natureza: string;
  base_calculo: number | string;
  aliquota: number | string;
  valor_calculado: number | string;
  valor_ajustado: number | string | null;
};

type TituloRow = {
  id: string;
  tipo: string;
  status: string;
  valor_total: number | string;
  valor_aberto: number | string;
};

type ParcelaRow = {
  id: string;
  titulo_id: string;
  numero: string | null;
  vencimento_date: string;
  valor: number | string;
  valor_aberto: number | string;
};

type ClienteRow = { id: number; nome: string };
type FornecedorRow = { id: number; nome: string | null };
type MovimentacaoDestinoRow = {
  id: number | string;
  item_id: number | string | null;
  quantidade: number | string | null;
  origem_os_id: number | string | null;
};
type OsDestinoRow = { id: number; numero_os: string | null; os_num: number | null };
type PedidoRecebimentoRow = { id: string; pedido_compra_id: string | null };
type PedidoCompraRow = { id: string; codigo: string | null };
type PedidoRecebimentoItemRow = { recebimento_id: string; item_id: number | string | null };

function n(value: unknown): number {
  const num = typeof value === "number" ? value : Number(value);
  return Number.isFinite(num) ? num : 0;
}

function formatDateBR(iso?: string | null): string {
  if (!iso) return "";
  const d = new Date(`${iso}T00:00:00`);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleDateString("pt-BR");
}

function roundedQty(value: number): number {
  return Math.round(value * 1000) / 1000;
}

function osLabel(row: OsDestinoRow | null | undefined, fallbackId: number): string {
  const numeroOs = String(row?.numero_os ?? "").trim();
  if (numeroOs) return numeroOs;
  const osNum = Number(row?.os_num ?? 0);
  return Number.isFinite(osNum) && osNum > 0 ? String(osNum) : String(fallbackId);
}

function pedidoCodeLabel(codes: Set<string> | undefined): string | null {
  const values = Array.from(codes ?? []).map((code) => code.trim()).filter(Boolean);
  return values.length ? values.join(", ") : null;
}

async function loadPedidoCodesByItemId(opts: {
  supabase: ReturnType<typeof supabaseBrowser>;
  tenantId: string;
  empresaId: string;
  nfEntradaId: number;
  chaveAcesso: string | null;
}): Promise<Map<number, Set<string>>> {
  const refs = Array.from(
    new Set([String(opts.chaveAcesso ?? "").trim(), `NF_ENTRADA_${opts.nfEntradaId}`].filter(Boolean))
  );
  if (refs.length === 0) return new Map();

  try {
    const { data: recebimentos, error: recebErr } = await applyTenantEmpresa(
      opts.supabase
        .schema("m")
        .from("pedido_compra_recebimento")
        .select("id,pedido_compra_id")
        .in("documento_ref", refs)
        .is("deleted_at", null),
      opts.tenantId,
      opts.empresaId
    ).returns<PedidoRecebimentoRow[]>();
    if (recebErr) throw recebErr;

    const recebRows = Array.isArray(recebimentos) ? recebimentos : [];
    const recebimentoIds = recebRows.map((row) => String(row.id ?? "").trim()).filter(Boolean);
    const pedidoIds = Array.from(new Set(recebRows.map((row) => String(row.pedido_compra_id ?? "").trim()).filter(Boolean)));
    if (recebimentoIds.length === 0 || pedidoIds.length === 0) return new Map();

    const [{ data: pedidos, error: pedidosErr }, { data: recebItens, error: recebItensErr }] = await Promise.all([
      applyTenantEmpresa(
        opts.supabase
          .schema("m")
          .from("pedido_compra")
          .select("id,codigo")
          .in("id", pedidoIds)
          .is("deleted_at", null),
        opts.tenantId,
        opts.empresaId
      ).returns<PedidoCompraRow[]>(),
      applyTenantEmpresa(
        opts.supabase
          .schema("m")
          .from("pedido_compra_recebimento_item")
          .select("recebimento_id,item_id")
          .in("recebimento_id", recebimentoIds)
          .is("deleted_at", null),
        opts.tenantId,
        opts.empresaId
      ).returns<PedidoRecebimentoItemRow[]>(),
    ]);
    if (pedidosErr) throw pedidosErr;
    if (recebItensErr) throw recebItensErr;

    const pedidoCodigoById = new Map(
      (Array.isArray(pedidos) ? pedidos : []).map((row) => [String(row.id), String(row.codigo ?? row.id).trim()])
    );
    const pedidoIdByRecebimentoId = new Map(recebRows.map((row) => [String(row.id), String(row.pedido_compra_id ?? "")]));
    const codesByItemId = new Map<number, Set<string>>();

    for (const row of Array.isArray(recebItens) ? recebItens : []) {
      const itemId = Number(row.item_id ?? 0);
      if (!Number.isFinite(itemId) || itemId <= 0) continue;
      const pedidoId = pedidoIdByRecebimentoId.get(String(row.recebimento_id)) ?? "";
      const codigo = pedidoCodigoById.get(pedidoId) ?? "";
      if (!codigo) continue;
      const set = codesByItemId.get(itemId) ?? new Set<string>();
      set.add(codigo);
      codesByItemId.set(itemId, set);
    }

    return codesByItemId;
  } catch (e) {
    console.warn("[NFE_DETAIL][RELATORIO_DESTINO] nao foi possivel carregar pedidos vinculados", e);
    return new Map();
  }
}

async function buildRelatorioDestinoImportacao(opts: {
  supabase: ReturnType<typeof supabaseBrowser>;
  tenantId: string;
  empresaId: string;
  doc: DocumentoFiscalRow;
  emitenteNome: string;
}): Promise<RelatorioDestinoImportacao | null> {
  const nfEntradaId = Number(opts.doc.source_nf_entrada_id ?? 0);
  if (!Number.isFinite(nfEntradaId) || nfEntradaId <= 0) return null;

  const { data: nfItens, error: nfItensErr } = await applyTenantEmpresa(
    opts.supabase
      .schema("public")
      .from("nf_entrada_itens")
      .select("id,item_id,descricao,ncm,cfop,qtd,v_unit,v_prod,codigo_fornecedor,itens(nome,cfop_padrao,unidade_medida,codigo_interno)")
      .eq("nf_entrada_id", nfEntradaId)
      .order("id", { ascending: true }),
    opts.tenantId,
    opts.empresaId
  ).returns<NfEntradaItemRow[]>();
  if (nfItensErr) throw nfItensErr;

  const { data: movimentacoes, error: movErr } = await applyTenantEmpresa(
    opts.supabase
      .from("movimentacoes")
      .select("id,item_id,quantidade,origem_os_id")
      .eq("origem_nf_entrada_id", nfEntradaId)
      .eq("tipo", "saida")
      .not("origem_os_id", "is", null)
      .order("id", { ascending: true }),
    opts.tenantId,
    opts.empresaId
  ).returns<MovimentacaoDestinoRow[]>();
  if (movErr) throw movErr;

  const movRows = Array.isArray(movimentacoes) ? movimentacoes : [];
  const osIds = Array.from(
    new Set(movRows.map((row) => Number(row.origem_os_id ?? 0)).filter((id) => Number.isFinite(id) && id > 0))
  );
  const osById = new Map<number, OsDestinoRow>();
  if (osIds.length > 0) {
    const { data: osRows, error: osErr } = await applyTenantEmpresa(
      opts.supabase.from("ordens_servico").select("id,numero_os,os_num").in("id", osIds),
      opts.tenantId,
      opts.empresaId
    ).returns<OsDestinoRow[]>();
    if (osErr) throw osErr;
    for (const row of Array.isArray(osRows) ? osRows : []) {
      const osId = Number(row.id ?? 0);
      if (Number.isFinite(osId) && osId > 0) osById.set(osId, row);
    }
  }

  const pedidoCodesByItemId = await loadPedidoCodesByItemId({
    supabase: opts.supabase,
    tenantId: opts.tenantId,
    empresaId: opts.empresaId,
    nfEntradaId,
    chaveAcesso: opts.doc.chave_acesso,
  });

  const movimentosByItemId = new Map<number, MovimentacaoDestinoRow[]>();
  const movimentoRestante = new Map<string, number>();
  for (const mov of movRows) {
    const itemId = Number(mov.item_id ?? 0);
    const qtd = Math.max(0, n(mov.quantidade));
    const osId = Number(mov.origem_os_id ?? 0);
    if (!Number.isFinite(itemId) || itemId <= 0 || !Number.isFinite(osId) || osId <= 0 || qtd <= 0) continue;
    const key = String(mov.id);
    movimentoRestante.set(key, qtd);
    const rows = movimentosByItemId.get(itemId) ?? [];
    rows.push(mov);
    movimentosByItemId.set(itemId, rows);
  }

  const itensRelatorio: RelatorioDestinoItem[] = [];
  for (const [idx, item] of (Array.isArray(nfItens) ? nfItens : []).entries()) {
    const itemId = Number(item.item_id ?? 0);
    const quantidadeTotal = Math.max(0, n(item.qtd));
    let restante = quantidadeTotal;
    const codigo = String(item.codigo_fornecedor ?? item.itens?.codigo_interno ?? "").trim() || null;
    const descricao = String(item.descricao ?? item.itens?.nome ?? codigo ?? "").trim() || "-";
    const unidade = String(item.itens?.unidade_medida ?? "").trim() || null;
    const pedidoCodigo = itemId > 0 ? pedidoCodeLabel(pedidoCodesByItemId.get(itemId)) : null;
    const baseItem = {
      numero_item_xml: idx + 1,
      codigo,
      descricao,
      unidade,
      pedido_codigo: pedidoCodigo,
    };

    for (const mov of itemId > 0 ? movimentosByItemId.get(itemId) ?? [] : []) {
      if (restante <= 0.0005) break;
      const key = String(mov.id);
      const disponivel = movimentoRestante.get(key) ?? 0;
      if (disponivel <= 0.0005) continue;

      const quantidadeOs = Math.min(restante, disponivel);
      const osId = Number(mov.origem_os_id ?? 0);
      const label = osLabel(osById.get(osId), osId);
      itensRelatorio.push({
        ...baseItem,
        quantidade: roundedQty(quantidadeOs),
        destino_tipo: "OS",
        destino_label: `OS ${label}`,
        os_id: osId,
        os_numero: label,
      });
      restante = Math.max(0, restante - quantidadeOs);
      movimentoRestante.set(key, Math.max(0, disponivel - quantidadeOs));
    }

    if (restante > 0.0005 || quantidadeTotal <= 0) {
      itensRelatorio.push({
        ...baseItem,
        quantidade: roundedQty(restante),
        destino_tipo: "ESTOQUE",
        destino_label: "Estoque",
      });
    }
  }

  return {
    nf_entrada_id: nfEntradaId,
    chave: opts.doc.chave_acesso ?? null,
    numero: opts.doc.numero ?? null,
    serie: opts.doc.serie ?? null,
    emitente: opts.emitenteNome || null,
    data_emissao: opts.doc.emissao_date ?? null,
    itens: itensRelatorio,
  };
}

type AccessMode = "financeiro" | "estoque";

export default function NfeDetail({
  id,
  backHref = "/faturamento/nfe",
  access = "financeiro",
}: {
  id: string;
  backHref?: string;
  access?: AccessMode;
}) {
  const te = useTenantEmpresa();
  const router = useRouter();

  const empresaRole = useMemo(() => {
    const role = te.empresa?.papel ?? te.empresas.find((e) => e.id === te.empresaId)?.papel ?? null;
    return typeof role === "string" ? role.trim().toUpperCase() : "";
  }, [te.empresa?.papel, te.empresaId, te.empresas]);
  const isFinanceiroEmpresaRole = empresaRole === "FINANCEIRO" || empresaRole === "FATURAMENTO";

  const canAccess = useMemo(() => {
    const requireAny = (caps: CapabilityKey[]) => {
      const values = caps.map((c) => te.has(c));
      if (values.some((v) => v === undefined)) return undefined;
      return values.some(Boolean);
    };

    if (access === "estoque") {
      // Mesma lógica de acesso do /estoque/importar: importar XML ou cadastrar fornecedor/itens.
      return requireAny([
        "xml_import.execute",
        "xml_import_faturamento.execute",
        "cad_fornecedores.write",
        "cad_itens.write",
      ]);
    }

    // Default: financeiro
    if (isFinanceiroEmpresaRole) return true;
    return requireAny(["financeiro.read", "financeiro.write", "faturamento.read", "faturamento.write"]);
  }, [access, isFinanceiroEmpresaRole, te]);

  useEffect(() => {
    if (canAccess === false) router.replace("/forbidden");
  }, [canAccess, router]);

  const baseReady =
    typeof te.sessionUserId === "string" &&
    Boolean(te.tenantId) &&
    (Boolean(te.empresaId) || te.empresas.length === 1);

  // Permite carregar enquanto as permissões ainda estão "undefined" (caps loading),
  // mas bloqueia explicitamente quando canAccess === false.
  const ready = baseReady && canAccess !== false;

  const tenantId = te.tenantId ?? "";
  const empresaId = te.empresaId ?? te.empresas[0]?.id ?? "";

  const [doc, setDoc] = useState<DocumentoFiscalRow | null>(null);
  const [itens, setItens] = useState<ItemRow[]>([]);
  const [impostos, setImpostos] = useState<ImpostoRow[]>([]);
  const [titulos, setTitulos] = useState<TituloRow[]>([]);
  const [parcelas, setParcelas] = useState<ParcelaRow[]>([]);
  const [clienteNome, setClienteNome] = useState<string>("");
  const [fornecedorNome, setFornecedorNome] = useState<string>("");
  const [osSelection, setOsSelection] = useState<OsSelection | null>(null);
  const [relatorioDestino, setRelatorioDestino] = useState<RelatorioDestinoImportacao | null>(null);

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [osSaving, setOsSaving] = useState(false);
  const [osFeedback, setOsFeedback] = useState<string | null>(null);
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    if (!ready) return;
    if (!id) return;

    let cancelled = false;

    const run = async () => {
      setLoading(true);
      setError(null);
      setRelatorioDestino(null);
      try {
        const supabase = supabaseBrowser();

        const { data: docRow, error: docErr } = await applyTenantEmpresa(
          supabase
            .schema("f")
            .from("documento_fiscal")
            .select(
              "id,operacao,natureza,modelo,serie,numero,chave_acesso,emissao_date,valor_total,fornecedor_id,cliente_id,os_id_import,created_at,source_nf_entrada_id"
            )
            .eq("id", id)
            .is("deleted_at", null),
          tenantId,
          empresaId
        ).maybeSingle<DocumentoFiscalRow>();
        if (docErr) throw docErr;
        if (!docRow?.id) throw new Error("Documento fiscal não encontrado.");

        const [{ data: itensData, error: itensErr }, { data: impData, error: impErr }, { data: titData, error: titErr }] =
          await Promise.all([
            applyTenantEmpresa(
              supabase
                .schema("f")
                .from("documento_fiscal_item")
                .select("id,item_n,item_tipo,descricao,ncm,cfop,quantidade,valor_unitario,valor_total")
                .eq("documento_fiscal_id", id)
                .is("deleted_at", null)
                .order("item_n", { ascending: true }),
              tenantId,
              empresaId
            ).returns<ItemRow[]>(),
            applyTenantEmpresa(
              supabase
                .schema("f")
                .from("documento_fiscal_imposto")
                .select("id,imposto,natureza,base_calculo,aliquota,valor_calculado,valor_ajustado")
                .eq("documento_fiscal_id", id)
                .is("deleted_at", null)
                .order("imposto", { ascending: true }),
              tenantId,
              empresaId
            ).returns<ImpostoRow[]>(),
            applyTenantEmpresa(
              supabase
                .schema("f")
                .from("titulo")
                .select("id,tipo,status,valor_total,valor_aberto")
                .eq("documento_fiscal_id", id)
                .is("deleted_at", null)
                .order("created_at", { ascending: false }),
              tenantId,
              empresaId
            ).returns<TituloRow[]>(),
          ]);

        if (itensErr) throw itensErr;
        if (impErr) throw impErr;
        if (titErr) throw titErr;

        const tituloIds = (titData ?? []).map((t) => String(t.id)).filter(Boolean);
        const { data: parcData, error: parcErr } = tituloIds.length
          ? await applyTenantEmpresa(
              supabase
                .schema("f")
                .from("titulo_parcela")
                .select("id,titulo_id,numero,vencimento_date,valor,valor_aberto")
                .in("titulo_id", tituloIds)
                .is("deleted_at", null)
                .order("vencimento_date", { ascending: true }),
              tenantId,
              empresaId
            ).returns<ParcelaRow[]>()
          : { data: [] as ParcelaRow[], error: null };
        if (parcErr) throw parcErr;

        let cliNome = "";
        if (docRow.cliente_id) {
          const { data: cRow, error: cErr } = await applyTenantEmpresa(
            supabase.from("clientes").select("id,nome").eq("id", docRow.cliente_id),
            tenantId,
            empresaId
          ).maybeSingle<ClienteRow>();
          if (cErr) throw cErr;
          cliNome = cRow?.nome ? String(cRow.nome) : "";
        }

        let fornNome = "";
        if (docRow.fornecedor_id) {
          const { data: fRow, error: fErr } = await applyTenantEmpresa(
            supabase.from("fornecedores").select("id,nome").eq("id", docRow.fornecedor_id),
            tenantId,
            empresaId
          ).maybeSingle<FornecedorRow>();
          if (fErr) throw fErr;
          fornNome = fRow?.nome ? String(fRow.nome) : "";
        }

        let relatorioDestinoImportacao: RelatorioDestinoImportacao | null = null;
        if (access === "estoque") {
          try {
            relatorioDestinoImportacao = await buildRelatorioDestinoImportacao({
              supabase,
              tenantId,
              empresaId,
              doc: docRow,
              emitenteNome: fornNome || (docRow.fornecedor_id ? `ID ${docRow.fornecedor_id}` : ""),
            });
          } catch (relatorioErr) {
            console.warn("[NFE_DETAIL][RELATORIO_DESTINO] nao foi possivel montar o relatorio", relatorioErr);
          }
        }

        // Fallback: importador de NF-e (entrada/saída) grava itens em public.nf_entrada_itens.
        // f.documento_fiscal_item pode não existir para esses documentos.
        const osSelectionLoaded = await fetchOsSelectionById({
          supabase,
          tenantId,
          empresaId,
          osId: docRow.os_id_import ?? null,
        });

        let resolvedItens: ItemRow[] = itensData ?? [];
        if (!resolvedItens.length && docRow.source_nf_entrada_id) {
          const { data: nfItens, error: nfItensErr } = await applyTenantEmpresa(
            supabase
              .schema("public")
              .from("nf_entrada_itens")
              .select("id,item_id,descricao,ncm,cfop,qtd,v_unit,v_prod,codigo_fornecedor,itens(nome,cfop_padrao,unidade_medida,codigo_interno)")
              .eq("nf_entrada_id", docRow.source_nf_entrada_id)
              .order("id", { ascending: true }),
            tenantId,
            empresaId
          ).returns<NfEntradaItemRow[]>();
          if (nfItensErr) throw nfItensErr;

          resolvedItens = (nfItens ?? []).map((r, idx) => ({
            id: String(r.id),
            item_n: idx + 1,
            item_tipo: "IMPORT_XML",
            descricao: String(r.descricao ?? r.itens?.nome ?? r.codigo_fornecedor ?? "").trim() || "—",
            ncm: r.ncm ?? null,
            cfop: r.cfop ?? r.itens?.cfop_padrao ?? null,
            quantidade: r.qtd ?? 0,
            valor_unitario: r.v_unit ?? 0,
            valor_total: r.v_prod ?? 0,
          }));
        }

        const titulosVisiveis = (titData ?? []).filter((titulo) => {
          const isLegacyCancelledAp =
            docRow.operacao === "SAIDA" &&
            Boolean(docRow.source_nf_entrada_id) &&
            titulo.tipo === "AP" &&
            String(titulo.status ?? "").toUpperCase() === "CANCELADO";
          return !isLegacyCancelledAp;
        });

        const tituloIdsVisiveis = titulosVisiveis.map((t) => String(t.id)).filter(Boolean);
        const parcelasVisiveis = (parcData ?? []).filter((p) => tituloIdsVisiveis.includes(String(p.titulo_id)));

        if (cancelled) return;
        setDoc(docRow);
        setItens(resolvedItens);
        setImpostos(impData ?? []);
        setTitulos(titulosVisiveis);
        setParcelas(parcelasVisiveis);
        setClienteNome(cliNome);
        setFornecedorNome(fornNome);
        setOsSelection(osSelectionLoaded);
        setRelatorioDestino(relatorioDestinoImportacao);
      } catch (e: unknown) {
        if (cancelled) return;
        setError(e instanceof Error ? e.message : "Erro inesperado ao carregar NF-e.");
        setDoc(null);
        setItens([]);
        setImpostos([]);
        setTitulos([]);
        setParcelas([]);
        setClienteNome("");
        setFornecedorNome("");
        setOsSelection(null);
        setRelatorioDestino(null);
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    void run();
    return () => {
      cancelled = true;
    };
  }, [access, empresaId, id, ready, tenantId]);

  const parcelasByTitulo = useMemo(() => {
    const m = new Map<string, ParcelaRow[]>();
    for (const p of parcelas) {
      const key = String(p.titulo_id);
      const arr = m.get(key) ?? [];
      arr.push(p);
      m.set(key, arr);
    }
    return m;
  }, [parcelas]);

  const hasAR = useMemo(() => titulos.some((t) => String(t.tipo || "").toUpperCase() === "AR"), [titulos]);
  const hasAP = useMemo(() => titulos.some((t) => String(t.tipo || "").toUpperCase() === "AP"), [titulos]);
  const canEditOsLink = doc?.operacao === "SAIDA" && doc?.natureza === "PRODUTO";
  const isEntradaProduto =
    doc?.operacao === "ENTRADA" && doc?.natureza === "PRODUTO" && Number(doc?.source_nf_entrada_id ?? 0) > 0;
  const canDeleteDoc =
    access === "financeiro" &&
    doc?.natureza === "PRODUTO" &&
    (doc?.operacao === "SAIDA" || isEntradaProduto);

  const saveOsLink = async () => {
    if (!ready || !doc?.id || !canEditOsLink) return;

    setOsSaving(true);
    setOsFeedback(null);
    setError(null);

    try {
      const supabase = supabaseBrowser();
      const nowIso = new Date().toISOString();
      const { error: updErr } = await applyTenantEmpresa(
        supabase
          .schema("f")
          .from("documento_fiscal")
          .update({
            os_id_import: osSelection?.id ?? null,
            updated_at: nowIso,
          })
          .eq("id", doc.id)
          .eq("operacao", "SAIDA")
          .eq("natureza", "PRODUTO")
          .is("deleted_at", null),
        tenantId,
        empresaId
      );

      if (updErr) throw updErr;
      setDoc((prev) => (prev ? { ...prev, os_id_import: osSelection?.id ?? null } : prev));
      setOsFeedback(osSelection ? "OS vinculada atualizada." : "Vinculo com OS removido.");
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro inesperado ao salvar a OS vinculada.");
    } finally {
      setOsSaving(false);
    }
  };

  const removeDoc = async () => {
    if (!ready || !doc?.id || !canDeleteDoc) return;
    const confirmMessage = isEntradaProduto
      ? "Estornar esta NF-e de entrada, o estoque e os titulos financeiros vinculados? Depois sera possivel reimportar."
      : "Excluir esta NF-e e os titulos financeiros vinculados? Depois sera possivel reimportar.";
    if (typeof window !== "undefined" && !window.confirm(confirmMessage)) {
      return;
    }

    let motivoEstorno = `Exclusao solicitada no detalhe da NF-e ${doc.numero ?? doc.id}`;
    if (isEntradaProduto && typeof window !== "undefined") {
      const motivoInformado = window.prompt("Informe o motivo do estorno da NF-e:", "Lançamento importado incorretamente");
      if (motivoInformado === null) return;
      if (motivoInformado.trim().length < 5) {
        window.alert("Informe um motivo com pelo menos 5 caracteres.");
        return;
      }
      motivoEstorno = motivoInformado.trim();
    }

    setDeleting(true);
    setError(null);
    setOsFeedback(null);

    try {
      const supabase = supabaseBrowser();
      const { error: rpcErr } = isEntradaProduto
        ? await supabase.rpc("estornar_nf_entrada", {
            p_tenant_id: tenantId,
            p_empresa_id: empresaId,
            p_nf_entrada_id: Number(doc.source_nf_entrada_id),
            p_motivo: motivoEstorno,
          })
        : await supabase.rpc("faturamento_excluir_documento_saida", {
            p_tenant_id: tenantId,
            p_empresa_id: empresaId,
            p_documento_fiscal_id: doc.id,
          });
      if (rpcErr) throw rpcErr;

      router.replace("/faturamento/nfe");
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro inesperado ao excluir NF-e.");
    } finally {
      setDeleting(false);
    }
  };

  return (
    <div className="mx-auto max-w-6xl px-4 py-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold text-zinc-100">NF-e</h1>
          <div className="mt-1 flex flex-wrap items-center gap-2 text-sm text-zinc-400">
            <span>Detalhe (somente leitura)</span>
            {hasAR ? (
              <span className="inline-flex items-center rounded-full border border-emerald-900/60 bg-emerald-950/20 px-2 py-0.5 text-xs text-emerald-200">
                Contas a Receber gerado
              </span>
            ) : null}
            {hasAP ? (
              <span className="inline-flex items-center rounded-full border border-amber-900/60 bg-amber-950/20 px-2 py-0.5 text-xs text-amber-200">
                Contas a Pagar gerado
              </span>
            ) : null}
          </div>
        </div>
        <div className="flex items-center gap-2">
          {canDeleteDoc ? (
            <button
              type="button"
              onClick={() => void removeDoc()}
              disabled={loading || deleting || osSaving || !ready}
              className="rounded-md bg-rose-700 px-3 py-2 text-sm text-zinc-100 hover:bg-rose-600 disabled:opacity-50"
            >
              {deleting ? (isEntradaProduto ? "Estornando..." : "Excluindo...") : isEntradaProduto ? "Estornar" : "Excluir"}
            </button>
          ) : null}
          {access === "estoque" && relatorioDestino ? (
            <button
              type="button"
              onClick={() => imprimirRelatorioDestinos([relatorioDestino])}
              disabled={loading || deleting || osSaving || !ready}
              className="rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-900 disabled:opacity-50"
            >
              Imprimir destino
            </button>
          ) : null}
          <Link
            href={backHref}
            className="rounded-md bg-zinc-800 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-700"
          >
            Voltar
          </Link>
        </div>
      </div>

      {loading ? <div className="mt-4 text-sm text-zinc-400">Carregando...</div> : null}
      {error ? <div className="mt-4 rounded-md border border-rose-900/60 bg-rose-950/30 px-4 py-3 text-sm text-rose-200">{error}</div> : null}

      {doc ? (
        <div className="mt-6 grid gap-4">
          <div className="rounded-xl border border-zinc-800 bg-zinc-950">
            <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between">
              <div className="text-sm font-medium text-zinc-100">Cabeçalho</div>
              <div className="text-xs text-zinc-500">ID: {doc.id}</div>
            </div>
            <div className="p-4 grid gap-3 md:grid-cols-4">
              <div>
                <div className="text-xs text-zinc-500">Operação</div>
                <div className="mt-1 text-sm text-zinc-100">{String(doc.operacao ?? "").toUpperCase()}</div>
              </div>
              <div>
                <div className="text-xs text-zinc-500">Emissão</div>
                <div className="mt-1 text-sm text-zinc-100">{formatDateBR(doc.emissao_date) || "—"}</div>
              </div>
              <div>
                <div className="text-xs text-zinc-500">Modelo/Série/Número</div>
                <div className="mt-1 text-sm text-zinc-100">
                  {doc.modelo ?? "—"} / {doc.serie ?? "—"} / {doc.numero ?? "—"}
                </div>
              </div>
              <div>
                <div className="text-xs text-zinc-500">Valor total</div>
                <div className="mt-1 text-sm text-zinc-100 tabular-nums">{formatMoneyBR(n(doc.valor_total))}</div>
              </div>
              <div className="md:col-span-4">
                <div className="text-xs text-zinc-500">Chave de acesso</div>
                <div className="mt-1 text-sm text-zinc-100 font-mono break-all">{doc.chave_acesso}</div>
              </div>
              <div className="md:col-span-4">
                <div className="text-xs text-zinc-500">Parceiro</div>
                <div className="mt-1 text-sm text-zinc-100">
                  {doc.operacao === "ENTRADA"
                    ? fornecedorNome || (doc.fornecedor_id ? `ID ${doc.fornecedor_id}` : "—")
                    : clienteNome || (doc.cliente_id ? `ID ${doc.cliente_id}` : "—")}
                </div>
              </div>
            </div>
          </div>

          {canEditOsLink ? (
            <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
              <div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_auto] md:items-end">
                <OsVinculoField
                  tenantId={tenantId}
                  empresaId={empresaId}
                  value={osSelection}
                  onChange={(next) => {
                    setOsSelection(next);
                    setOsFeedback(null);
                  }}
                  disabled={loading || osSaving || deleting || !ready}
                  helperText="Opcional. O valor desta NF-e sera abatido da carteira da OS vinculada."
                />

                <button
                  type="button"
                  onClick={() => void saveOsLink()}
                  disabled={loading || osSaving || deleting || !ready}
                  className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-900 disabled:opacity-50"
                >
                  {osSaving ? "Salvando OS..." : "Salvar OS"}
                </button>
              </div>

              {osFeedback ? <div className="mt-3 text-sm text-emerald-300">{osFeedback}</div> : null}
            </div>
          ) : null}

          <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
            <div className="px-4 py-3 border-b border-zinc-800 text-sm font-medium text-zinc-100">Itens</div>
            <div className="overflow-x-auto">
              <table className="min-w-full text-sm">
                <thead className="bg-zinc-950/60 text-zinc-400">
                  <tr>
                    <th className="px-4 py-3 text-left font-medium">#</th>
                    <th className="px-4 py-3 text-left font-medium">Descrição</th>
                    <th className="px-4 py-3 text-left font-medium">NCM</th>
                    <th className="px-4 py-3 text-left font-medium">CFOP</th>
                    <th className="px-4 py-3 text-right font-medium">Qtd</th>
                    <th className="px-4 py-3 text-right font-medium">V. Unit</th>
                    <th className="px-4 py-3 text-right font-medium">Total</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-zinc-800">
                  {itens.length === 0 ? (
                    <tr>
                      <td className="px-4 py-6 text-center text-zinc-500" colSpan={7}>
                        Sem itens.
                      </td>
                    </tr>
                  ) : null}
                  {itens.map((it) => (
                    <tr key={it.id} className="hover:bg-zinc-900/40">
                      <td className="px-4 py-3 text-zinc-200 tabular-nums">{it.item_n}</td>
                      <td className="px-4 py-3 text-zinc-200">{it.descricao}</td>
                      <td className="px-4 py-3 text-zinc-200">{it.ncm ?? "—"}</td>
                      <td className="px-4 py-3 text-zinc-200">{it.cfop ?? "—"}</td>
                      <td className="px-4 py-3 text-right text-zinc-200 tabular-nums">{formatMoneyBR(n(it.quantidade))}</td>
                      <td className="px-4 py-3 text-right text-zinc-200 tabular-nums">{formatMoneyBR(n(it.valor_unitario))}</td>
                      <td className="px-4 py-3 text-right text-zinc-200 tabular-nums">{formatMoneyBR(n(it.valor_total))}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
            <div className="px-4 py-3 border-b border-zinc-800 text-sm font-medium text-zinc-100">Impostos</div>
            <div className="overflow-x-auto">
              <table className="min-w-full text-sm">
                <thead className="bg-zinc-950/60 text-zinc-400">
                  <tr>
                    <th className="px-4 py-3 text-left font-medium">Imposto</th>
                    <th className="px-4 py-3 text-left font-medium">Natureza</th>
                    <th className="px-4 py-3 text-right font-medium">Base</th>
                    <th className="px-4 py-3 text-right font-medium">Alíquota</th>
                    <th className="px-4 py-3 text-right font-medium">Calculado</th>
                    <th className="px-4 py-3 text-right font-medium">Ajustado</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-zinc-800">
                  {impostos.length === 0 ? (
                    <tr>
                      <td className="px-4 py-6 text-center text-zinc-500" colSpan={6}>
                        Sem impostos.
                      </td>
                    </tr>
                  ) : null}
                  {impostos.map((im) => (
                    <tr key={im.id} className="hover:bg-zinc-900/40">
                      <td className="px-4 py-3 text-zinc-200">{String(im.imposto || "").toUpperCase()}</td>
                      <td className="px-4 py-3 text-zinc-200">{String(im.natureza || "").toUpperCase()}</td>
                      <td className="px-4 py-3 text-right text-zinc-200 tabular-nums">{formatMoneyBR(n(im.base_calculo))}</td>
                      <td className="px-4 py-3 text-right text-zinc-200 tabular-nums">{n(im.aliquota).toFixed(4)}%</td>
                      <td className="px-4 py-3 text-right text-zinc-200 tabular-nums">{formatMoneyBR(n(im.valor_calculado))}</td>
                      <td className="px-4 py-3 text-right text-zinc-200 tabular-nums">
                        {im.valor_ajustado === null ? "—" : formatMoneyBR(n(im.valor_ajustado))}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
            <div className="px-4 py-3 border-b border-zinc-800 text-sm font-medium text-zinc-100">Títulos (Financeiro)</div>
            <div className="overflow-x-auto">
              <table className="min-w-full text-sm">
                <thead className="bg-zinc-950/60 text-zinc-400">
                  <tr>
                    <th className="px-4 py-3 text-left font-medium">Tipo</th>
                    <th className="px-4 py-3 text-left font-medium">Status</th>
                    <th className="px-4 py-3 text-right font-medium">Total</th>
                    <th className="px-4 py-3 text-right font-medium">Aberto</th>
                    <th className="px-4 py-3 text-left font-medium">1ª Parcela</th>
                    <th className="px-4 py-3 text-left font-medium">ID</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-zinc-800">
                  {titulos.length === 0 ? (
                    <tr>
                      <td className="px-4 py-6 text-center text-zinc-500" colSpan={6}>
                        Sem títulos gerados.
                      </td>
                    </tr>
                  ) : null}
                  {titulos.map((t) => {
                    const first = (parcelasByTitulo.get(String(t.id)) ?? [])[0] ?? null;
                    return (
                      <tr key={t.id} className="hover:bg-zinc-900/40">
                        <td className="px-4 py-3 text-zinc-200">{String(t.tipo || "").toUpperCase()}</td>
                        <td className="px-4 py-3 text-zinc-200">{String(t.status || "").toUpperCase()}</td>
                        <td className="px-4 py-3 text-right text-zinc-200 tabular-nums">{formatMoneyBR(n(t.valor_total))}</td>
                        <td className="px-4 py-3 text-right text-zinc-200 tabular-nums">{formatMoneyBR(n(t.valor_aberto))}</td>
                        <td className="px-4 py-3 text-zinc-200">
                          {first ? `${first.numero ?? ""} ${formatDateBR(first.vencimento_date)} (${formatMoneyBR(n(first.valor_aberto))})` : "—"}
                        </td>
                        <td className="px-4 py-3 text-zinc-200 font-mono text-xs">{t.id}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
