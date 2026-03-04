import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase/admin";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";
import { getAllowedEmpresas } from "@/lib/auth/empresa";

export const runtime = "nodejs";

function jerr(status: number, error: string, details?: unknown) {
  return NextResponse.json({ error, ...(details !== undefined ? { details } : {}) }, { status });
}

function normalizeCnpj(value: string | null | undefined): string | null {
  const raw = String(value ?? "").trim();
  if (!raw) return null;
  const digits = raw.replace(/\D/g, "");
  if (!digits) return null;
  return digits.length === 14 ? digits : null;
}

function normalizeName(value: string | null | undefined): string {
  return String(value ?? "")
    .replace(/\s+/g, " ")
    .trim();
}

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type ImportBody = {
  tenantId?: string;
  empresaId?: string;
  finalidade?: string | null;
  osId?: number | null;
  pedidoCompraId?: string | null;
  motivoCompraId?: string | null;
  solicitanteUsuarioId?: string | null;

  fornecedorCnpj?: string | null;
  fornecedorNome?: string | null;

  nfJson?: unknown;
  itensJson?: unknown;
  xmlRaw?: string | null;

  gerarContasPagar?: boolean;
  parcelasJson?: unknown;
};

type FornecedorRow = { id: number; cnpj_norm: string | null; nome: string | null; ativo: boolean | null };

type RowWithId = { id?: unknown };
type NfEntradaItemRow = {
  id: number;
  codigo_fornecedor: string | null;
  descricao: string | null;
  qtd: number | null;
  v_unit: number | null;
  v_prod?: number | null;
  v_icms: number | null;
  v_ipi: number | null;
  v_pis: number | null;
  v_cofins: number | null;
  item_id: number | null;
};

type MovimentacaoExistRow = {
  item_id: number | null;
};

type PedidoCompraRow = {
  id: string;
  codigo: string | null;
  status: string | null;
  fornecedor_id: number | null;
  solicitante_usuario_id: string | null;
};

type PedidoCompraItemRow = {
  id: string;
  seq: number | null;
  item_id: number | null;
  item_codigo: string | null;
  item_nome: string | null;
  origem_os_id: number | null;
  quantidade: number | null;
  quantidade_recebida: number | null;
  valor_unitario: number | null;
};

type PedidoCompraItemOrigemRow = {
  pedido_compra_item_id: string | null;
  pendencia_id: string | null;
};

type CompraPendenciaOsRow = {
  id: string;
  origem_os_id: number | null;
  origem_tipo: string | null;
};

type CatalogItemRow = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
};

function toNum(value: unknown): number {
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? n : 0;
}

function readIdNumber(row: unknown): number | null {
  const r = row as RowWithId | null;
  if (!r?.id) return null;
  const n = typeof r.id === "number" ? r.id : Number(r.id);
  return Number.isFinite(n) ? n : null;
}

function readIdString(row: unknown): string | null {
  const r = row as RowWithId | null;
  if (!r?.id) return null;
  return String(r.id);
}

function normalizeText(value: string | null | undefined): string {
  return String(value ?? "")
    .replace(/\s+/g, " ")
    .trim()
    .toUpperCase();
}

function normalizeLookup(value: string | null | undefined): string {
  return normalizeText(value)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
}

function numKey(value: unknown): string {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) return "0";
  return n.toFixed(6);
}

function normalizeItemCode(value: string | null | undefined): string {
  const cleaned = String(value ?? "")
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9._/-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-+|-+$/g, "");
  return cleaned;
}

function moneyDiff(a: number, b: number): number {
  if (!Number.isFinite(a) || !Number.isFinite(b)) return Number.MAX_SAFE_INTEGER;
  return Math.abs(a - b);
}

function round6(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.round(value * 1_000_000) / 1_000_000;
}

function formatMoneyBr(value: number): string {
  const n = Number.isFinite(value) ? value : 0;
  return new Intl.NumberFormat("pt-BR", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(n);
}

function extractFirstXmlTagValue(xml: string, tag: string): string | null {
  const re = new RegExp(`<(?:\\w+:)?${tag}\\b[^>]*>([^<]*)<\\/(?:\\w+:)?${tag}>`, "i");
  const match = re.exec(xml);
  if (!match?.[1]) return null;
  const v = String(match[1]).trim();
  return v || null;
}

function extractXmlBlock(xml: string, tag: string): string | null {
  const re = new RegExp(`<(?:\\w+:)?${tag}\\b[^>]*>[\\s\\S]*?<\\/(?:\\w+:)?${tag}>`, "i");
  const match = re.exec(xml);
  return match?.[0] ?? null;
}

function parseXmlTaxContext(xmlRaw: string | null): {
  crt: string | null;
  idDest: string | null;
  emitUf: string | null;
  destUf: string | null;
} {
  const xml = String(xmlRaw ?? "").trim();
  if (!xml) {
    return { crt: null, idDest: null, emitUf: null, destUf: null };
  }

  const ideBlock = extractXmlBlock(xml, "ide");
  const emitBlock = extractXmlBlock(xml, "emit");
  const destBlock = extractXmlBlock(xml, "dest");

  const crt = extractFirstXmlTagValue(emitBlock ?? xml, "CRT");
  const idDest = extractFirstXmlTagValue(ideBlock ?? xml, "idDest");
  const emitUf = extractFirstXmlTagValue(emitBlock ?? xml, "UF");
  const destUf = extractFirstXmlTagValue(destBlock ?? xml, "UF");

  return {
    crt: crt ? crt.toUpperCase() : null,
    idDest: idDest ? idDest.toUpperCase() : null,
    emitUf: emitUf ? emitUf.toUpperCase() : null,
    destUf: destUf ? destUf.toUpperCase() : null,
  };
}

function applySimplesScIcmsCreditFallback(opts: { xmlRaw: string | null; itensJson: unknown }): {
  itensJson: unknown;
  applied: boolean;
  reason: string | null;
} {
  const items = Array.isArray(opts.itensJson)
    ? opts.itensJson.filter((v) => v && typeof v === "object").map((v) => ({ ...(v as Record<string, unknown>) }))
    : [];
  if (!items.length) return { itensJson: opts.itensJson, applied: false, reason: null };

  const taxCtx = parseXmlTaxContext(opts.xmlRaw);
  const isSimples = taxCtx.crt === "1";
  const isOperacaoInternaSc =
    taxCtx.emitUf === "SC" && (taxCtx.destUf === "SC" || taxCtx.idDest === "1");

  if (!isSimples || !isOperacaoInternaSc) {
    return { itensJson: opts.itensJson, applied: false, reason: null };
  }

  let changed = false;
  for (const rec of items) {
    const vProd = toNum(rec.v_prod ?? rec.total);
    const qtd = toNum(rec.qtd ?? rec.quantidade);
    const vUnit = toNum(rec.v_unit ?? rec.valor_unitario ?? rec.valorUnit);
    const base = vProd > 0 ? vProd : qtd > 0 && vUnit > 0 ? qtd * vUnit : 0;
    if (base <= 0) continue;

    // ICMS presumido 7% para Simples SC interno.
    if (toNum(rec.credito_icms) <= 0) {
      rec.credito_icms = round6(base * 0.07);
      changed = true;
    }
    if (toNum(rec.v_icms) <= 0) {
      rec.v_icms = round6(base * 0.07);
      changed = true;
    }
    if (toNum(rec.aliq_icms) <= 0) {
      rec.aliq_icms = 7;
      changed = true;
    }

    // PIS/COFINS de compra para contexto de crédito fiscal (regra operacional do projeto).
    if (toNum(rec.credito_pis) <= 0) {
      rec.credito_pis = round6(base * 0.0165);
      changed = true;
    }
    if (toNum(rec.v_pis) <= 0) {
      rec.v_pis = round6(base * 0.0165);
      changed = true;
    }
    if (toNum(rec.aliq_pis) <= 0) {
      rec.aliq_pis = 1.65;
      changed = true;
    }

    if (toNum(rec.credito_cofins) <= 0) {
      rec.credito_cofins = round6(base * 0.076);
      changed = true;
    }
    if (toNum(rec.v_cofins) <= 0) {
      rec.v_cofins = round6(base * 0.076);
      changed = true;
    }
    if (toNum(rec.aliq_cofins) <= 0) {
      rec.aliq_cofins = 7.6;
      changed = true;
    }
  }

  return {
    itensJson: changed ? items : opts.itensJson,
    applied: changed,
    reason: changed
      ? "XML Simples Nacional (CRT=1) com operacao interna SC: fallback de ICMS 7% e PIS/COFINS (1,65%/7,6%)."
      : null,
  };
}

async function resolvePedidoCompra(opts: {
  tenantId: string;
  empresaId: string;
  pedidoCompraRaw: string;
}): Promise<{ pedido: PedidoCompraRow | null; error?: string }> {
  const admin = supabaseAdmin();
  const raw = String(opts.pedidoCompraRaw ?? "").trim();
  if (!raw) return { pedido: null };

  let q = admin
    .schema("m")
    .from("pedido_compra")
    .select("id,codigo,status,fornecedor_id,solicitante_usuario_id")
    .eq("tenant_id", opts.tenantId)
    .eq("empresa_id", opts.empresaId)
    .is("deleted_at", null);

  if (UUID_REGEX.test(raw)) q = q.eq("id", raw);
  else q = q.eq("codigo", raw.toUpperCase());

  const { data, error } = await q.maybeSingle<PedidoCompraRow>();
  if (error) return { pedido: null, error: error.message };
  return { pedido: data ?? null };
}

async function ensureItemFromPedidoManual(opts: {
  tenantId: string;
  empresaId: string;
  fornecedorId: number | null;
  finalidade: string | null;
  pedidoItem: PedidoCompraItemRow;
  preferredCode: string | null;
  preferredName: string | null;
  dataMov: string | null;
}): Promise<number | null> {
  const admin = supabaseAdmin();
  const baseCode =
    normalizeItemCode(opts.preferredCode) ||
    normalizeItemCode(opts.pedidoItem.item_codigo) ||
    `PC-${String(opts.pedidoItem.seq ?? 0).padStart(3, "0")}`;

  const { data: existing } = await admin
    .from("itens")
    .select("id")
    .eq("tenant_id", opts.tenantId)
    .eq("empresa_id", opts.empresaId)
    .eq("codigo_interno", baseCode)
    .limit(1)
    .maybeSingle<RowWithId>();

  let finalCode = baseCode;
  if (existing?.id) {
    finalCode = `${baseCode}-${Date.now().toString().slice(-6)}`;
  }

  const nome = normalizeText(opts.preferredName || opts.pedidoItem.item_nome || finalCode);
  const valor = toNum(opts.pedidoItem.valor_unitario);
  const dataRef = opts.dataMov ?? new Date().toISOString();

  const { data: created, error } = await admin
    .from("itens")
    .insert({
      tenant_id: opts.tenantId,
      empresa_id: opts.empresaId,
      codigo_interno: finalCode,
      nome,
      tipo: "produto",
      controla_estoque: true,
      unidade_medida: "UN",
      custo_ultima_compra: valor,
      custo_medio: valor,
      preco_unitario: valor,
      fornecedor_id: opts.fornecedorId,
      data_atualizacao_preco: dataRef,
      data_ultima_compra: dataRef,
      margem_lucro_percentual: 52,
      finalidade: opts.finalidade ?? "consumo",
    })
    .select("id")
    .single<RowWithId>();
  if (error) return null;

  const createdId = readIdNumber(created);
  if (!createdId) return null;

  await admin
    .schema("m")
    .from("pedido_compra_item")
    .update({
      item_id: createdId,
      item_codigo: finalCode,
      item_nome: nome,
      updated_by: null,
    })
    .eq("tenant_id", opts.tenantId)
    .eq("empresa_id", opts.empresaId)
    .eq("id", opts.pedidoItem.id)
    .is("deleted_at", null);

  return createdId;
}

async function bindImportItemsFromPedido(opts: {
  tenantId: string;
  empresaId: string;
  pedidoCompraRaw: string;
  fornecedorId: number;
  fornecedorCnpj: string | null;
  finalidade: string | null;
  nfJson: unknown;
  itensJson: unknown;
}): Promise<{
  pedidoId: string | null;
  itensJson: unknown;
  recebimentoItens: Array<{ pedidoItemId: string; quantidade: number }>;
  osVinculos: Array<{ os_id: number; item_id: number; quantidade: number; valor_unitario: number }>;
  pedidoHasOsOrigem: boolean;
  solicitanteUsuarioId: string | null;
  documentoRef: string | null;
  warnings: string[];
}> {
  const admin = supabaseAdmin();
  const warnings: string[] = [];
  const parsedItems = Array.isArray(opts.itensJson)
    ? opts.itensJson.filter((v) => v && typeof v === "object").map((v) => ({ ...(v as Record<string, unknown>) }))
    : [];
  if (!parsedItems.length) {
    return {
      pedidoId: null,
      itensJson: opts.itensJson,
      recebimentoItens: [],
      osVinculos: [],
      pedidoHasOsOrigem: false,
      solicitanteUsuarioId: null,
      documentoRef: null,
      warnings,
    };
  }

  const resolvedPedido = await resolvePedidoCompra({
    tenantId: opts.tenantId,
    empresaId: opts.empresaId,
    pedidoCompraRaw: opts.pedidoCompraRaw,
  });
  if (resolvedPedido.error) {
    warnings.push(`Pedido nao vinculado: ${resolvedPedido.error}`);
    return {
      pedidoId: null,
      itensJson: parsedItems,
      recebimentoItens: [],
      osVinculos: [],
      pedidoHasOsOrigem: false,
      solicitanteUsuarioId: null,
      documentoRef: null,
      warnings,
    };
  }

  const pedido = resolvedPedido.pedido;
  if (!pedido) {
    warnings.push(`Pedido nao encontrado: ${opts.pedidoCompraRaw}`);
    return {
      pedidoId: null,
      itensJson: parsedItems,
      recebimentoItens: [],
      osVinculos: [],
      pedidoHasOsOrigem: false,
      solicitanteUsuarioId: null,
      documentoRef: null,
      warnings,
    };
  }
  if (pedido.fornecedor_id && Number(pedido.fornecedor_id) !== Number(opts.fornecedorId)) {
    const cnpjDigits = (value: string | null | undefined) => String(value ?? "").replace(/\D/g, "");
    const cnpjRoot = (value: string | null | undefined) => cnpjDigits(value).slice(0, 8);

    const [{ data: pedidoForn }, { data: nfForn }] = await Promise.all([
      admin
        .from("fornecedores")
        .select("cnpj")
        .eq("tenant_id", opts.tenantId)
        .eq("empresa_id", opts.empresaId)
        .eq("id", Number(pedido.fornecedor_id))
        .maybeSingle<{ cnpj: string | null }>(),
      admin
        .from("fornecedores")
        .select("cnpj")
        .eq("tenant_id", opts.tenantId)
        .eq("empresa_id", opts.empresaId)
        .eq("id", Number(opts.fornecedorId))
        .maybeSingle<{ cnpj: string | null }>(),
    ]);

    const pedidoRoot = cnpjRoot(pedidoForn?.cnpj ?? null);
    const nfRoot = cnpjRoot(nfForn?.cnpj ?? opts.fornecedorCnpj ?? null);
    const sameRoot = pedidoRoot.length === 8 && nfRoot.length === 8 && pedidoRoot === nfRoot;

    if (!sameRoot) {
      warnings.push("Pedido de compra tem fornecedor diferente da NF. Vinculo ignorado.");
      return {
        pedidoId: null,
        itensJson: parsedItems,
        recebimentoItens: [],
        osVinculos: [],
        pedidoHasOsOrigem: false,
        solicitanteUsuarioId: null,
        documentoRef: null,
        warnings,
      };
    }

    warnings.push("Fornecedor do pedido e NF em filiais diferentes (mesma raiz CNPJ). Vinculo permitido.");
  }

  const { data: pedidoItens, error: pedidoItensErr } = await admin
    .schema("m")
    .from("pedido_compra_item")
    .select("id,seq,item_id,item_codigo,item_nome,origem_os_id,quantidade,quantidade_recebida,valor_unitario")
    .eq("tenant_id", opts.tenantId)
    .eq("empresa_id", opts.empresaId)
    .eq("pedido_compra_id", pedido.id)
    .is("deleted_at", null)
    .order("seq", { ascending: true })
    .returns<PedidoCompraItemRow[]>();
  if (pedidoItensErr) {
    warnings.push(`Pedido sem itens acessiveis: ${pedidoItensErr.message}`);
    return {
      pedidoId: null,
      itensJson: parsedItems,
      recebimentoItens: [],
      osVinculos: [],
      pedidoHasOsOrigem: false,
      solicitanteUsuarioId: null,
      documentoRef: null,
      warnings,
    };
  }

  const pedidoRows = Array.isArray(pedidoItens) ? pedidoItens : [];
  if (!pedidoRows.length) {
    warnings.push("Pedido sem itens para vinculo.");
    return {
      pedidoId: null,
      itensJson: parsedItems,
      recebimentoItens: [],
      osVinculos: [],
      pedidoHasOsOrigem: false,
      solicitanteUsuarioId: null,
      documentoRef: null,
      warnings,
    };
  }

  // Alguns itens vinculados de pendencia OS podem nao ter origem_os_id preenchido direto no item.
  // Recupera OS a partir de pedido_compra_item_origem -> compra_pendencia.
  const origemOsByPedidoItemId = new Map<string, number>();
  const pedidoItemIdsSemOrigem = pedidoRows
    .filter((r) => !(Number(r.origem_os_id ?? 0) > 0))
    .map((r) => String(r.id))
    .filter(Boolean);
  if (pedidoItemIdsSemOrigem.length > 0) {
    const { data: origRows } = await admin
      .schema("m")
      .from("pedido_compra_item_origem")
      .select("pedido_compra_item_id,pendencia_id")
      .eq("tenant_id", opts.tenantId)
      .eq("empresa_id", opts.empresaId)
      .in("pedido_compra_item_id", pedidoItemIdsSemOrigem)
      .is("deleted_at", null)
      .returns<PedidoCompraItemOrigemRow[]>();

    const pendIds = Array.from(
      new Set(
        (Array.isArray(origRows) ? origRows : [])
          .map((r) => String(r.pendencia_id ?? "").trim())
          .filter(Boolean)
      )
    );

    if (pendIds.length > 0) {
      const { data: pendRows } = await admin
        .schema("m")
        .from("compra_pendencia")
        .select("id,origem_os_id,origem_tipo")
        .eq("tenant_id", opts.tenantId)
        .eq("empresa_id", opts.empresaId)
        .in("id", pendIds)
        .is("deleted_at", null)
        .returns<CompraPendenciaOsRow[]>();

      const osByPendId = new Map<string, number>();
      for (const p of Array.isArray(pendRows) ? pendRows : []) {
        const pendId = String(p.id ?? "").trim();
        const osId = Number(p.origem_os_id ?? 0);
        const origemTipo = String(p.origem_tipo ?? "").trim().toUpperCase();
        if (!pendId || osId <= 0) continue;
        if (origemTipo && origemTipo !== "OS") continue;
        osByPendId.set(pendId, osId);
      }

      for (const o of Array.isArray(origRows) ? origRows : []) {
        const itemId = String(o.pedido_compra_item_id ?? "").trim();
        const pendId = String(o.pendencia_id ?? "").trim();
        if (!itemId || !pendId) continue;
        if (origemOsByPedidoItemId.has(itemId)) continue;
        const osId = Number(osByPendId.get(pendId) ?? 0);
        if (osId > 0) origemOsByPedidoItemId.set(itemId, osId);
      }
    }
  }

  const itemIds = Array.from(
    new Set(pedidoRows.map((r) => Number(r.item_id ?? 0)).filter((n) => Number.isFinite(n) && n > 0))
  );
  const catalogById = new Map<number, CatalogItemRow>();
  if (itemIds.length > 0) {
    const { data: catRows } = await admin
      .from("itens")
      .select("id,codigo_interno,nome")
      .eq("tenant_id", opts.tenantId)
      .eq("empresa_id", opts.empresaId)
      .in("id", itemIds)
      .returns<CatalogItemRow[]>();
    for (const row of Array.isArray(catRows) ? catRows : []) {
      const id = Number(row.id ?? 0);
      if (id > 0) catalogById.set(id, row);
    }
  }

  const remainingByPedidoItemId = new Map<string, number>();
  for (const row of pedidoRows) {
    const rem = Math.max(0, toNum(row.quantidade) - toNum(row.quantidade_recebida));
    remainingByPedidoItemId.set(row.id, rem);
  }

  const recebimentoMap = new Map<string, number>();
  const osVinculosMap = new Map<string, { os_id: number; item_id: number; quantidade: number; valor_unitario: number }>();
  const dataMov = typeof (opts.nfJson as Record<string, unknown> | null)?.data_emissao === "string"
    ? String((opts.nfJson as Record<string, unknown>).data_emissao)
    : null;

  for (const rec of parsedItems) {
    const alreadyId = toNum(rec.item_id);

    const codigo = normalizeItemCode(String(rec.codigo_fornecedor ?? rec.codigo ?? ""));
    const descricao = normalizeLookup(String(rec.descricao ?? rec.nome ?? ""));
    const qtdXml = Math.max(0, toNum(rec.qtd ?? rec.quantidade));

    // Considera desconto por item quando vier no payload.
    // Se houver desconto, usa unitario liquido para casar pedido/OS.
    const valorUnitRaw = Math.max(0, toNum(rec.v_unit ?? rec.valor_unitario ?? rec.valorUnit));
    const vProd = Math.max(0, toNum(rec.v_prod ?? rec.total));
    const vDesc = Math.max(0, toNum(rec.v_desc ?? rec.vDesc ?? 0));
    const valorUnitLiq = qtdXml > 0 && vProd > 0 ? Math.max(0, (vProd - vDesc) / qtdXml) : 0;
    const valorUnit = valorUnitLiq > 0 ? valorUnitLiq : valorUnitRaw;

    // Um item do XML pode cobrir varias linhas do pedido (ex.: XML qtd=2 e pedido com 1 OS + 1 estoque).
    let qtdPendente = qtdXml;
    let guard = 0;
    while (guard < pedidoRows.length + 8) {
      guard += 1;

      let best: { row: PedidoCompraItemRow; score: number } | null = null;
      for (const row of pedidoRows) {
        const remaining = remainingByPedidoItemId.get(row.id) ?? 0;
        if (remaining <= 0) continue;

        const rowCode = normalizeItemCode(row.item_codigo ?? "");
        const rowDesc = normalizeLookup(row.item_nome ?? "");
        const rowItemId = Number(row.item_id ?? 0);
        const cat = rowItemId > 0 ? catalogById.get(rowItemId) ?? null : null;
        const catCode = normalizeItemCode(cat?.codigo_interno ?? "");
        const catDesc = normalizeLookup(cat?.nome ?? "");
        const rowValor = Math.max(0, toNum(row.valor_unitario));
        const sameResolvedItem = alreadyId > 0 && rowItemId > 0 && rowItemId === alreadyId;

        let score = 1000;
        // Quando o XML ja veio com item_id resolvido, prioriza casar com esse item do pedido.
        if (alreadyId > 0) {
          if (sameResolvedItem) score -= 3200;
          else if (rowItemId > 0 && rowItemId !== alreadyId) score += 1200;
        }
        if (codigo && (codigo === rowCode || codigo === catCode)) score -= 700;
        if (descricao && (descricao === rowDesc || descricao === catDesc)) score -= 250;
        // Fallback importante: quando item for manual/sem codigo, o valor unitario tende a ser a melhor chave.
        const diffUnit = moneyDiff(valorUnit, rowValor);
        if (valorUnit > 0 && rowValor > 0) {
          if (diffUnit <= 0.01) score -= 650;
          else if (diffUnit <= 0.05) score -= 450;
          else if (diffUnit <= 0.2) score -= 220;
        }
        // Quando item_id ja foi resolvido no XML e coincide com item do pedido,
        // o valor unitario pode divergir por desconto/acrescimo e nao deve bloquear o match.
        score += moneyDiff(valorUnit, rowValor) * (sameResolvedItem ? 2 : 50);
        const alvoQtd = qtdXml > 0 ? qtdPendente : remaining;
        score += Math.abs(alvoQtd - remaining);

        if (!best || score < best.score) best = { row, score };
      }

      if (!best) break;
      const threshold = 1100;
      if (best.score > threshold) break;

      const row = best.row;
      let itemId = toNum(row.item_id);
      if (itemId <= 0) {
        if (alreadyId > 0) {
          itemId = alreadyId;
          // Mantem o item manual do pedido vinculado ao item ja resolvido no XML.
          await admin
            .schema("m")
            .from("pedido_compra_item")
            .update({
              item_id: itemId,
              updated_by: null,
            })
            .eq("tenant_id", opts.tenantId)
            .eq("empresa_id", opts.empresaId)
            .eq("id", row.id)
            .is("deleted_at", null);
        }
      }
      if (itemId <= 0) {
        const created = await ensureItemFromPedidoManual({
          tenantId: opts.tenantId,
          empresaId: opts.empresaId,
          fornecedorId: opts.fornecedorId,
          finalidade: opts.finalidade,
          pedidoItem: row,
          preferredCode: codigo || normalizeItemCode(row.item_codigo),
          preferredName: String(rec.descricao ?? rec.nome ?? row.item_nome ?? ""),
          dataMov,
        });
        if (created && created > 0) itemId = created;
      }
      if (itemId <= 0) break;

      rec.item_id = itemId;
      if (!codigo) {
        const cat = catalogById.get(itemId);
        const fallbackCode = normalizeItemCode(row.item_codigo ?? cat?.codigo_interno ?? "");
        if (fallbackCode) rec.codigo = fallbackCode;
      }

      const remaining = remainingByPedidoItemId.get(row.id) ?? 0;
      const demanda = qtdXml > 0 ? qtdPendente : remaining;
      const qtdReceber = Math.max(0, Math.min(demanda || remaining, remaining));
      if (qtdReceber <= 0) break;

      recebimentoMap.set(row.id, (recebimentoMap.get(row.id) ?? 0) + qtdReceber);
      remainingByPedidoItemId.set(row.id, Math.max(0, remaining - qtdReceber));

      const osId = Number(row.origem_os_id ?? origemOsByPedidoItemId.get(String(row.id)) ?? 0);
      if (osId > 0 && itemId > 0) {
        const key = `${osId}:${itemId}`;
        const prev = osVinculosMap.get(key);
        osVinculosMap.set(key, {
          os_id: osId,
          item_id: itemId,
          quantidade: (prev?.quantidade ?? 0) + qtdReceber,
          valor_unitario: valorUnit > 0 ? valorUnit : prev?.valor_unitario ?? toNum(row.valor_unitario),
        });
      }

      if (qtdXml > 0) {
        qtdPendente = Math.max(0, qtdPendente - qtdReceber);
        if (qtdPendente <= 1e-9) break;
      } else {
        break;
      }
    }
  }

  const recebimentoItens = Array.from(recebimentoMap.entries())
    .map(([pedidoItemId, quantidade]) => ({ pedidoItemId, quantidade }))
    .filter((r) => r.quantidade > 0);
  const osVinculos = Array.from(osVinculosMap.values()).filter((r) => r.os_id > 0 && r.item_id > 0 && r.quantidade > 0);
  const pedidoHasOsOrigem =
    pedidoRows.some((r) => Number(r.origem_os_id ?? 0) > 0) || origemOsByPedidoItemId.size > 0;

  const nf = (opts.nfJson as Record<string, unknown> | null) ?? null;
  const documentoRef = String(nf?.chave ?? "").trim() || null;
  const solicitanteUsuarioId = String((pedido as Record<string, unknown>).solicitante_usuario_id ?? "").trim() || null;
  return {
    pedidoId: pedido.id,
    itensJson: parsedItems,
    recebimentoItens,
    osVinculos,
    pedidoHasOsOrigem,
    solicitanteUsuarioId,
    documentoRef,
    warnings,
  };
}

function mergeRecebimentoItens(
  base: Array<{ pedidoItemId: string; quantidade: number }>,
  extra: Array<{ pedidoItemId: string; quantidade: number }>
): Array<{ pedidoItemId: string; quantidade: number }> {
  const map = new Map<string, number>();
  for (const r of base) {
    const id = String(r.pedidoItemId ?? "").trim();
    if (!id) continue;
    map.set(id, (map.get(id) ?? 0) + Math.max(0, toNum(r.quantidade)));
  }
  for (const r of extra) {
    const id = String(r.pedidoItemId ?? "").trim();
    if (!id) continue;
    map.set(id, (map.get(id) ?? 0) + Math.max(0, toNum(r.quantidade)));
  }
  return Array.from(map.entries())
    .map(([pedidoItemId, quantidade]) => ({ pedidoItemId, quantidade }))
    .filter((r) => r.quantidade > 0);
}

function mergeRecebimentoItensByMax(
  base: Array<{ pedidoItemId: string; quantidade: number }>,
  extra: Array<{ pedidoItemId: string; quantidade: number }>
): Array<{ pedidoItemId: string; quantidade: number }> {
  const map = new Map<string, number>();
  for (const r of [...base, ...extra]) {
    const id = String(r.pedidoItemId ?? "").trim();
    if (!id) continue;
    const qtd = Math.max(0, toNum(r.quantidade));
    map.set(id, Math.max(map.get(id) ?? 0, qtd));
  }
  return Array.from(map.entries())
    .map(([pedidoItemId, quantidade]) => ({ pedidoItemId, quantidade }))
    .filter((r) => r.quantidade > 0);
}

async function registrarRecebimentoPedidoViaImportFallback(opts: {
  tenantId: string;
  empresaId: string;
  pedidoCompraId: string;
  recebimentoDate: string;
  documentoRef: string;
  observacoes: string;
  currentUsuarioId: string | null;
  recebimentoItens: Array<{ pedidoItemId: string; quantidade: number }>;
}) {
  const admin = supabaseAdmin();
  const itens = mergeRecebimentoItens([], opts.recebimentoItens);
  if (!itens.length) return;

  const { data: pedido, error: pedidoErr } = await admin
    .schema("m")
    .from("pedido_compra")
    .select("id,status")
    .eq("tenant_id", opts.tenantId)
    .eq("empresa_id", opts.empresaId)
    .eq("id", opts.pedidoCompraId)
    .is("deleted_at", null)
    .maybeSingle<Pick<PedidoCompraRow, "id" | "status">>();
  if (pedidoErr) throw new Error(pedidoErr.message);
  if (!pedido) throw new Error("Pedido nao encontrado para recebimento.");

  const pedidoItemIds = itens.map((r) => String(r.pedidoItemId)).filter(Boolean);
  const { data: pedidoItens, error: pedidoItensErr } = await admin
    .schema("m")
    .from("pedido_compra_item")
    .select("id,item_id,quantidade,quantidade_recebida")
    .eq("tenant_id", opts.tenantId)
    .eq("empresa_id", opts.empresaId)
    .eq("pedido_compra_id", opts.pedidoCompraId)
    .is("deleted_at", null)
    .in("id", pedidoItemIds)
    .returns<Array<Pick<PedidoCompraItemRow, "id" | "item_id" | "quantidade" | "quantidade_recebida">>>();
  if (pedidoItensErr) throw new Error(pedidoItensErr.message);

  const byId = new Map(
    (Array.isArray(pedidoItens) ? pedidoItens : []).map((row) => [String(row.id), row as Pick<PedidoCompraItemRow, "id" | "item_id" | "quantidade" | "quantidade_recebida">])
  );
  if (byId.size !== pedidoItemIds.length) {
    throw new Error("Pedido item nao encontrado para recebimento.");
  }

  const recebimentoRows: Array<{ pedido_compra_item_id: string; item_id: number | null; quantidade: number }> = [];
  const itemNovoRecebido = new Map<string, number>();
  for (const it of itens) {
    const pedidoItemId = String(it.pedidoItemId);
    const row = byId.get(pedidoItemId);
    if (!row) throw new Error("Pedido item nao encontrado para recebimento.");

    const qtd = Math.max(0, toNum(it.quantidade));
    if (qtd <= 0) continue;

    const qtdAtual = toNum(row.quantidade_recebida);
    const qtdTotal = toNum(row.quantidade);
    const saldo = Math.max(0, qtdTotal - qtdAtual);
    if (qtd - saldo > 1e-6) throw new Error("Quantidade excede saldo.");

    recebimentoRows.push({
      pedido_compra_item_id: pedidoItemId,
      item_id: Number.isFinite(Number(row.item_id)) ? Number(row.item_id) : null,
      quantidade: qtd,
    });
    itemNovoRecebido.set(pedidoItemId, qtdAtual + qtd);
  }
  if (!recebimentoRows.length) return;

  const { data: receb, error: recebErr } = await admin
    .schema("m")
    .from("pedido_compra_recebimento")
    .insert({
      tenant_id: opts.tenantId,
      empresa_id: opts.empresaId,
      pedido_compra_id: opts.pedidoCompraId,
      recebimento_date: opts.recebimentoDate,
      documento_ref: opts.documentoRef,
      observacoes: opts.observacoes,
      created_by: opts.currentUsuarioId,
      updated_by: opts.currentUsuarioId,
    })
    .select("id")
    .single<RowWithId>();
  if (recebErr) throw new Error(recebErr.message);

  const recebimentoId = readIdString(receb);
  if (!recebimentoId) throw new Error("Falha ao criar recebimento do pedido.");

  const { error: insItensErr } = await admin
    .schema("m")
    .from("pedido_compra_recebimento_item")
    .insert(
      recebimentoRows.map((r) => ({
        tenant_id: opts.tenantId,
        empresa_id: opts.empresaId,
        recebimento_id: recebimentoId,
        pedido_compra_item_id: r.pedido_compra_item_id,
        item_id: r.item_id,
        quantidade: r.quantidade,
        created_by: opts.currentUsuarioId,
      }))
    );
  if (insItensErr) throw new Error(insItensErr.message);

  for (const [pedidoItemId, novaQtd] of itemNovoRecebido.entries()) {
    const { error: updItemErr } = await admin
      .schema("m")
      .from("pedido_compra_item")
      .update({ quantidade_recebida: novaQtd, updated_by: opts.currentUsuarioId })
      .eq("tenant_id", opts.tenantId)
      .eq("empresa_id", opts.empresaId)
      .eq("pedido_compra_id", opts.pedidoCompraId)
      .eq("id", pedidoItemId)
      .is("deleted_at", null);
    if (updItemErr) throw new Error(updItemErr.message);
  }

  const { data: itensAtualizados, error: itensAtualizadosErr } = await admin
    .schema("m")
    .from("pedido_compra_item")
    .select("id,quantidade,quantidade_recebida")
    .eq("tenant_id", opts.tenantId)
    .eq("empresa_id", opts.empresaId)
    .eq("pedido_compra_id", opts.pedidoCompraId)
    .is("deleted_at", null)
    .returns<Array<Pick<PedidoCompraItemRow, "id" | "quantidade" | "quantidade_recebida">>>();
  if (itensAtualizadosErr) throw new Error(itensAtualizadosErr.message);

  const itensPedido = Array.isArray(itensAtualizados) ? itensAtualizados : [];
  const todosRecebidos =
    itensPedido.length > 0 &&
    itensPedido.every((r) => toNum(r.quantidade_recebida) + 1e-6 >= toNum(r.quantidade));
  const novoStatus = todosRecebidos ? "RECEBIDO" : "PARCIAL_RECEBIDO";
  const statusAnterior = String(pedido.status ?? "").trim().toUpperCase();

  const { error: updPedidoErr } = await admin
    .schema("m")
    .from("pedido_compra")
    .update({ status: novoStatus, updated_by: opts.currentUsuarioId })
    .eq("tenant_id", opts.tenantId)
    .eq("empresa_id", opts.empresaId)
    .eq("id", opts.pedidoCompraId)
    .is("deleted_at", null);
  if (updPedidoErr) throw new Error(updPedidoErr.message);

  await admin.schema("m").rpc("fn_pedido_compra_log_evento", {
    p_pedido_id: opts.pedidoCompraId,
    p_tipo: "RECEBIMENTO",
    p_status_de: statusAnterior || null,
    p_status_para: novoStatus,
    p_mensagem: opts.observacoes || "Recebimento",
  });

  const itensTotaisRecebidosIds = itensPedido
    .filter((r) => toNum(r.quantidade_recebida) + 1e-6 >= toNum(r.quantidade))
    .map((r) => String(r.id))
    .filter(Boolean);

  if (itensTotaisRecebidosIds.length > 0) {
    const { data: origens, error: origErr } = await admin
      .schema("m")
      .from("pedido_compra_item_origem")
      .select("pendencia_id")
      .eq("tenant_id", opts.tenantId)
      .eq("empresa_id", opts.empresaId)
      .in("pedido_compra_item_id", itensTotaisRecebidosIds)
      .is("deleted_at", null)
      .returns<PedidoCompraItemOrigemRow[]>();
    if (origErr) throw new Error(origErr.message);

    const pendenciaIds = Array.from(
      new Set(
        (Array.isArray(origens) ? origens : [])
          .map((r) => String(r.pendencia_id ?? "").trim())
          .filter(Boolean)
      )
    );

    if (pendenciaIds.length > 0) {
      const { error: pendErr } = await admin
        .schema("m")
        .from("compra_pendencia")
        .update({
          status: "CONCLUIDO",
          concluido_em: new Date().toISOString(),
          updated_by: opts.currentUsuarioId,
        })
        .eq("tenant_id", opts.tenantId)
        .eq("empresa_id", opts.empresaId)
        .eq("status", "EM_PEDIDO")
        .is("deleted_at", null)
        .in("id", pendenciaIds);
      if (pendErr) throw new Error(pendErr.message);
    }
  }
}

function mergeOsVinculos(
  base: Array<{ os_id: number; item_id: number; quantidade: number; valor_unitario: number }>,
  extra: Array<{ os_id: number; item_id: number; quantidade: number; valor_unitario: number }>
): Array<{ os_id: number; item_id: number; quantidade: number; valor_unitario: number }> {
  const map = new Map<string, { os_id: number; item_id: number; quantidade: number; valor_unitario: number }>();
  for (const row of [...base, ...extra]) {
    const osId = Number(row.os_id ?? 0);
    const itemId = Number(row.item_id ?? 0);
    const qtd = Math.max(0, toNum(row.quantidade));
    if (osId <= 0 || itemId <= 0 || qtd <= 0) continue;
    const key = `${osId}:${itemId}`;
    const prev = map.get(key);
    map.set(key, {
      os_id: osId,
      item_id: itemId,
      quantidade: (prev?.quantidade ?? 0) + qtd,
      valor_unitario: toNum(row.valor_unitario) > 0 ? toNum(row.valor_unitario) : prev?.valor_unitario ?? 0,
    });
  }
  return Array.from(map.values()).filter((r) => r.quantidade > 0);
}

function mergeOsVinculosByMax(
  base: Array<{ os_id: number; item_id: number; quantidade: number; valor_unitario: number }>,
  extra: Array<{ os_id: number; item_id: number; quantidade: number; valor_unitario: number }>
): Array<{ os_id: number; item_id: number; quantidade: number; valor_unitario: number }> {
  const map = new Map<string, { os_id: number; item_id: number; quantidade: number; valor_unitario: number }>();
  for (const row of [...base, ...extra]) {
    const osId = Number(row.os_id ?? 0);
    const itemId = Number(row.item_id ?? 0);
    const qtd = Math.max(0, toNum(row.quantidade));
    if (osId <= 0 || itemId <= 0 || qtd <= 0) continue;
    const key = `${osId}:${itemId}`;
    const prev = map.get(key);
    map.set(key, {
      os_id: osId,
      item_id: itemId,
      quantidade: Math.max(prev?.quantidade ?? 0, qtd),
      valor_unitario: toNum(row.valor_unitario) > 0 ? toNum(row.valor_unitario) : prev?.valor_unitario ?? 0,
    });
  }
  return Array.from(map.values()).filter((r) => r.quantidade > 0);
}

async function runStrictImportPreflight(opts: {
  tenantId: string;
  empresaId: string;
  pedidoCompraRaw: string;
  pedidoCompraIdVinculado: string | null;
  pedidoLinkWarnings: string[];
  pedidoRecebimentos: Array<{ pedidoItemId: string; quantidade: number }>;
  pedidoOsVinculos: Array<{ os_id: number; item_id: number; quantidade: number; valor_unitario: number }>;
  finalidadeNorm: string;
  osId: number | null;
  itensJsonToImport: unknown;
  documentoRef: string | null;
}): Promise<string[]> {
  const admin = supabaseAdmin();
  const issues: string[] = [];

  if (opts.pedidoCompraRaw) {
    if (!opts.pedidoCompraIdVinculado) {
      const reason =
        opts.pedidoLinkWarnings.find((w) => !w.toLowerCase().includes("filiais diferentes")) ??
        "nao foi possivel vincular XML ao pedido.";
      issues.push(`Pedido ${opts.pedidoCompraRaw}: ${reason}`);
    } else {
      const { data: pedido, error: pedidoErr } = await admin
        .schema("m")
        .from("pedido_compra")
        .select("id,codigo,status")
        .eq("tenant_id", opts.tenantId)
        .eq("empresa_id", opts.empresaId)
        .eq("id", opts.pedidoCompraIdVinculado)
        .is("deleted_at", null)
        .maybeSingle<{ id: string; codigo: string | null; status: string | null }>();
      if (pedidoErr) {
        issues.push(`Pedido ${opts.pedidoCompraIdVinculado}: erro ao validar pedido (${pedidoErr.message}).`);
      } else if (!pedido) {
        issues.push(`Pedido ${opts.pedidoCompraIdVinculado}: nao encontrado para esta empresa.`);
      } else {
        const st = String(pedido.status ?? "").trim().toUpperCase();
        if (st === "CANCELADO") issues.push(`Pedido ${pedido.codigo ?? pedido.id}: status CANCELADO.`);
      }

      const recebimentos = mergeRecebimentoItens([], opts.pedidoRecebimentos).filter((r) => toNum(r.quantidade) > 0);
      if (!recebimentos.length) {
        issues.push(`Pedido ${opts.pedidoCompraIdVinculado}: nenhum item da NF foi alocado para recebimento.`);
      } else {
        const ids = recebimentos.map((r) => String(r.pedidoItemId)).filter(Boolean);
        const { data: pedidoItens, error: pedidoItensErr } = await admin
          .schema("m")
          .from("pedido_compra_item")
          .select("id,quantidade,quantidade_recebida")
          .eq("tenant_id", opts.tenantId)
          .eq("empresa_id", opts.empresaId)
          .eq("pedido_compra_id", opts.pedidoCompraIdVinculado)
          .is("deleted_at", null)
          .in("id", ids)
          .returns<Array<Pick<PedidoCompraItemRow, "id" | "quantidade" | "quantidade_recebida">>>();

        if (pedidoItensErr) {
          issues.push(`Pedido ${opts.pedidoCompraIdVinculado}: erro ao validar itens (${pedidoItensErr.message}).`);
        } else {
          const byId = new Map(
            (Array.isArray(pedidoItens) ? pedidoItens : []).map((r) => [
              String(r.id),
              r as Pick<PedidoCompraItemRow, "id" | "quantidade" | "quantidade_recebida">,
            ])
          );
          for (const rec of recebimentos) {
            const itemId = String(rec.pedidoItemId ?? "").trim();
            const row = byId.get(itemId);
            if (!row) {
              issues.push(`Pedido ${opts.pedidoCompraIdVinculado}: item ${itemId} nao encontrado.`);
              continue;
            }
            const saldo = Math.max(0, toNum(row.quantidade) - toNum(row.quantidade_recebida));
            const qtd = Math.max(0, toNum(rec.quantidade));
            if (qtd <= 0) {
              issues.push(`Pedido ${opts.pedidoCompraIdVinculado}: quantidade invalida para item ${itemId}.`);
              continue;
            }
            if (qtd - saldo > 1e-6) {
              issues.push(`Pedido ${opts.pedidoCompraIdVinculado}: item ${itemId} sem saldo suficiente (saldo=${saldo}, NF=${qtd}).`);
            }
          }
        }
      }

      if (opts.documentoRef) {
        const { data: docExists, error: docExistsErr } = await admin
          .schema("m")
          .from("pedido_compra_recebimento")
          .select("id")
          .eq("tenant_id", opts.tenantId)
          .eq("empresa_id", opts.empresaId)
          .eq("pedido_compra_id", opts.pedidoCompraIdVinculado)
          .eq("documento_ref", opts.documentoRef)
          .is("deleted_at", null)
          .limit(1)
          .maybeSingle<RowWithId>();
        if (docExistsErr) {
          issues.push(`Pedido ${opts.pedidoCompraIdVinculado}: erro ao validar documento de recebimento (${docExistsErr.message}).`);
        } else if (readIdString(docExists)) {
          issues.push(`Pedido ${opts.pedidoCompraIdVinculado}: documento ${opts.documentoRef} ja recebido.`);
        }
      }
    }
  }

  const finalidade = String(opts.finalidadeNorm ?? "").trim().toLowerCase();
  const osVinculos = mergeOsVinculos([], opts.pedidoOsVinculos);

  if (finalidade === "materia_prima" && osVinculos.length > 0) {
    const osIds = Array.from(new Set(osVinculos.map((r) => Number(r.os_id)).filter((n) => Number.isFinite(n) && n > 0)));
    const itemIds = Array.from(new Set(osVinculos.map((r) => Number(r.item_id)).filter((n) => Number.isFinite(n) && n > 0)));

    const { data: osRows, error: osErr } = await admin
      .from("ordens_servico")
      .select("id,numero_os,os_num")
      .eq("tenant_id", opts.tenantId)
      .eq("empresa_id", opts.empresaId)
      .in("id", osIds)
      .returns<Array<{ id: number; numero_os: string | null; os_num: number | null }>>();
    if (osErr) {
      issues.push(`Erro ao validar OS vinculadas: ${osErr.message}`);
    } else {
      const osLabelById = new Map<number, string>();
      for (const os of Array.isArray(osRows) ? osRows : []) {
        const id = Number(os.id ?? 0);
        if (!Number.isFinite(id) || id <= 0) continue;
        const numeroOs = String(os.numero_os ?? "").trim();
        const osNum = Number(os.os_num ?? 0);
        const label = numeroOs || (Number.isFinite(osNum) && osNum > 0 ? String(osNum) : String(id));
        osLabelById.set(id, label);
      }

      for (const osId of osIds) {
        if (!osLabelById.has(osId)) issues.push(`OS ${osId} nao encontrada para vinculo da NF.`);
      }

      const { data: osItemRows, error: osItemErr } = await admin
        .from("os_itens")
        .select("os_id,item_id")
        .eq("tenant_id", opts.tenantId)
        .eq("empresa_id", opts.empresaId)
        .in("os_id", osIds)
        .in("item_id", itemIds)
        .returns<Array<{ os_id: number | null; item_id: number | null }>>();
      if (osItemErr) {
        issues.push(`Erro ao validar itens da OS: ${osItemErr.message}`);
      } else {
        const existing = new Set(
          (Array.isArray(osItemRows) ? osItemRows : [])
            .map((r) => `${Number(r.os_id ?? 0)}:${Number(r.item_id ?? 0)}`)
        );
        for (const v of osVinculos) {
          const k = `${Number(v.os_id)}:${Number(v.item_id)}`;
          if (existing.has(k)) continue;
          const osLabel = osLabelById.get(Number(v.os_id)) ?? String(v.os_id);
          issues.push(`OS ${osLabel} nao contem o item ${v.item_id} para baixa automatica.`);
        }
      }
    }
  }

  if (finalidade === "materia_prima" && (!osVinculos.length && Number.isFinite(opts.osId) && Number(opts.osId) > 0)) {
    const osId = Number(opts.osId);
    const itens = Array.isArray(opts.itensJsonToImport)
      ? opts.itensJsonToImport.filter((v) => v && typeof v === "object").map((v) => v as Record<string, unknown>)
      : [];
    const itemIds = Array.from(
      new Set(
        itens
          .map((r) => Number(r.item_id ?? 0))
          .filter((n) => Number.isFinite(n) && n > 0)
      )
    );

    const { data: osRow, error: osErr } = await admin
      .from("ordens_servico")
      .select("id")
      .eq("tenant_id", opts.tenantId)
      .eq("empresa_id", opts.empresaId)
      .eq("id", osId)
      .maybeSingle<{ id: number }>();
    if (osErr) issues.push(`Erro ao validar OS ${osId}: ${osErr.message}`);
    else if (!osRow?.id) issues.push(`OS ${osId} nao encontrada para importacao.`);

    if (itemIds.length === 0) {
      issues.push("Importacao com OS direta exige itens vinculados a cadastro (item_id).");
    } else if (osRow?.id) {
      const { data: osItems, error: osItemsErr } = await admin
        .from("os_itens")
        .select("item_id")
        .eq("tenant_id", opts.tenantId)
        .eq("empresa_id", opts.empresaId)
        .eq("os_id", osId)
        .in("item_id", itemIds)
        .returns<Array<{ item_id: number | null }>>();
      if (osItemsErr) {
        issues.push(`Erro ao validar itens da OS ${osId}: ${osItemsErr.message}`);
      } else {
        const osItemSet = new Set(
          (Array.isArray(osItems) ? osItems : [])
            .map((r) => Number(r.item_id ?? 0))
            .filter((n) => Number.isFinite(n) && n > 0)
        );
        for (const itemId of itemIds) {
          if (!osItemSet.has(itemId)) {
            issues.push(`OS ${osId} nao contem o item ${itemId} para baixa automatica.`);
          }
        }
      }
    }
  }

  return Array.from(new Set(issues));
}

async function reconcileNfEntradaItemIdsFromPayload(opts: {
  tenantId: string;
  empresaId: string;
  nfEntradaId: number;
  itensJson: unknown;
}) {
  const admin = supabaseAdmin();
  const { tenantId, empresaId, nfEntradaId } = opts;
  const itensPayload = Array.isArray(opts.itensJson) ? opts.itensJson : [];
  if (itensPayload.length === 0) return;

  const candidatosCodigo = new Map<string, number[]>();
  const candidatosCompostos = new Map<string, number[]>();
  const candidatosDescricao = new Map<string, number[]>();
  const codigosSemId = new Set<string>();
  const descricoesSemId = new Set<string>();

  for (const row of itensPayload) {
    if (!row || typeof row !== "object") continue;
    const rec = row as Record<string, unknown>;
    const itemIdRaw = rec.item_id;
    const itemId = typeof itemIdRaw === "number" ? itemIdRaw : Number(itemIdRaw);
    const codigo = normalizeLookup(String(rec.codigo_fornecedor ?? rec.codigo ?? ""));
    if (codigo) {
      if (Number.isFinite(itemId) && itemId > 0) {
        if (!candidatosCodigo.has(codigo)) candidatosCodigo.set(codigo, []);
        candidatosCodigo.get(codigo)?.push(itemId);
      } else {
        codigosSemId.add(codigo);
      }
    }

    const desc = normalizeLookup(String(rec.descricao ?? rec.nome ?? ""));
    if (!desc) {
      continue;
    }

    const qtd = numKey(rec.qtd ?? rec.quantidade);
    const vUnit = numKey(rec.v_unit ?? rec.valor_unitario ?? rec.valorUnit);
    const composto = `${desc}|${qtd}|${vUnit}`;

    if (Number.isFinite(itemId) && itemId > 0) {
      if (!candidatosCompostos.has(composto)) candidatosCompostos.set(composto, []);
      candidatosCompostos.get(composto)?.push(itemId);

      if (!candidatosDescricao.has(desc)) candidatosDescricao.set(desc, []);
      candidatosDescricao.get(desc)?.push(itemId);
    } else {
      descricoesSemId.add(desc);
    }
  }

  const { data: itensNf, error: itensNfErr } = await admin
    .from("nf_entrada_itens")
    .select("id,codigo_fornecedor,descricao,qtd,v_unit,v_icms,v_ipi,v_pis,v_cofins,item_id")
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .eq("nf_entrada_id", nfEntradaId)
    .returns<NfEntradaItemRow[]>();

  if (itensNfErr) return;

  // Fallback map from cadastro de itens quando payload nao trouxe item_id.
  const { data: itensCadastrados, error: itensCadastradosErr } = await admin
    .from("itens")
    .select("id,codigo_interno,nome,ativo")
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .eq("ativo", true)
    .returns<Array<{ id: number; codigo_interno: string | null; nome: string | null; ativo: boolean | null }>>();

  const codigoParaItemId = new Map<string, number>();
  const descParaItemId = new Map<string, number>();
  if (!itensCadastradosErr && Array.isArray(itensCadastrados)) {
    for (const it of itensCadastrados) {
      const id = Number(it.id ?? 0);
      if (!Number.isFinite(id) || id <= 0) continue;
      const cod = normalizeLookup(it.codigo_interno);
      if (cod && (codigosSemId.has(cod) || !codigoParaItemId.has(cod))) {
        codigoParaItemId.set(cod, id);
      }
      const desc = normalizeLookup(it.nome);
      if (desc && (descricoesSemId.has(desc) || !descParaItemId.has(desc))) {
        descParaItemId.set(desc, id);
      }
    }
  }

  const rows = Array.isArray(itensNf) ? itensNf : [];
  for (const row of rows) {
    if (row.item_id && Number(row.item_id) > 0) continue;

    const codigo = normalizeLookup(row.codigo_fornecedor);
    const desc = normalizeLookup(row.descricao);
    if (!codigo && !desc) continue;

    const filaCodigo = codigo ? candidatosCodigo.get(codigo) ?? [] : [];

    const composto = `${desc}|${numKey(row.qtd)}|${numKey(row.v_unit)}`;
    const filaComposta = candidatosCompostos.get(composto) ?? [];
    const filaDescricao = candidatosDescricao.get(desc) ?? [];
    const itemByCodigo = codigo ? codigoParaItemId.get(codigo) ?? null : null;
    const itemByDescricao = desc ? descParaItemId.get(desc) ?? null : null;

    const picked =
      filaCodigo.length > 0
        ? filaCodigo.shift()
        : filaComposta.length > 0
          ? filaComposta.shift()
          : filaDescricao.length > 0
            ? filaDescricao.shift()
            : itemByCodigo && itemByCodigo > 0
              ? itemByCodigo
              : itemByDescricao && itemByDescricao > 0
                ? itemByDescricao
            : null;
    if (!picked || picked <= 0) continue;

    try {
      await admin
        .from("nf_entrada_itens")
        .update({ item_id: picked })
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId)
        .eq("id", row.id);
    } catch {
      // best-effort
    }
  }
}

async function syncMovimentacoesFromNfEntradaFallback(opts: {
  tenantId: string;
  empresaId: string;
  nfEntradaId: number;
  realizadoPor: string | null;
}) {
  const admin = supabaseAdmin();
  const { tenantId, empresaId, nfEntradaId, realizadoPor } = opts;

  const { data: nfRow } = await admin
    .from("nf_entrada")
    .select("id,data_emissao,xml_raw")
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .eq("id", nfEntradaId)
    .maybeSingle<{ id: number; data_emissao: string | null; xml_raw: string | null }>();

  const dataMov = nfRow?.data_emissao ?? new Date().toISOString();
  const taxCtx = parseXmlTaxContext(nfRow?.xml_raw ?? null);
  const shouldUseSimplesScCreditoFallback =
    taxCtx.crt === "1" && taxCtx.emitUf === "SC" && (taxCtx.destUf === "SC" || taxCtx.idDest === "1");

  const { data: itensNf, error: itensErr } = await admin
    .from("nf_entrada_itens")
    .select("item_id,qtd,v_unit,v_prod,v_icms,v_ipi,v_pis,v_cofins")
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .eq("nf_entrada_id", nfEntradaId)
    .returns<NfEntradaItemRow[]>();

  if (itensErr) throw new Error(itensErr.message);

  const itens = Array.isArray(itensNf) ? itensNf : [];
  const agregados = new Map<number, NfEntradaItemRow>();

  for (const row of itens) {
    const itemId = Number(row.item_id ?? 0);
    const qtd = toNum(row.qtd);
    if (!Number.isFinite(itemId) || itemId <= 0 || qtd <= 0) continue;

    const prev = agregados.get(itemId);
    if (!prev) {
      agregados.set(itemId, {
        ...row,
        item_id: itemId,
        qtd,
      });
      continue;
    }

    agregados.set(itemId, {
      ...prev,
      qtd: toNum(prev.qtd) + qtd,
      v_icms: toNum(prev.v_icms) + toNum(row.v_icms),
      v_ipi: toNum(prev.v_ipi) + toNum(row.v_ipi),
      v_pis: toNum(prev.v_pis) + toNum(row.v_pis),
      v_cofins: toNum(prev.v_cofins) + toNum(row.v_cofins),
    });
  }

  if (agregados.size === 0) return { inserted: 0 };

  const itemIds = Array.from(agregados.keys());
  const { data: movExist, error: movErr } = await admin
    .from("movimentacoes")
    .select("item_id")
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .eq("origem_nf_entrada_id", nfEntradaId)
    .eq("tipo", "entrada")
    .in("item_id", itemIds)
    .returns<MovimentacaoExistRow[]>();

  if (movErr) throw new Error(movErr.message);

  const itensComMov = new Set(
    (Array.isArray(movExist) ? movExist : [])
      .map((r) => Number(r.item_id ?? 0))
      .filter((n) => Number.isFinite(n) && n > 0)
  );

  const inserts: Record<string, unknown>[] = [];
  const insertedQuantByItem = new Map<number, number>();
  for (const [itemId, row] of agregados.entries()) {
    if (itensComMov.has(itemId)) continue;
    const qtd = toNum(row.qtd);
    if (qtd <= 0) continue;
    insertedQuantByItem.set(itemId, qtd);
    const baseProd = toNum(row.v_prod);
    const baseCalculo = baseProd > 0 ? baseProd : qtd * toNum(row.v_unit);
    const vIcms = toNum(row.v_icms);
    const vPis = toNum(row.v_pis);
    const vCofins = toNum(row.v_cofins);
    const creditoIcms =
      vIcms > 0
        ? vIcms
        : shouldUseSimplesScCreditoFallback && baseCalculo > 0
          ? round6(baseCalculo * 0.07)
          : 0;
    const creditoPis =
      vPis > 0
        ? vPis
        : shouldUseSimplesScCreditoFallback && baseCalculo > 0
          ? round6(baseCalculo * 0.0165)
          : 0;
    const creditoCofins =
      vCofins > 0
        ? vCofins
        : shouldUseSimplesScCreditoFallback && baseCalculo > 0
          ? round6(baseCalculo * 0.076)
          : 0;
    inserts.push({
      tenant_id: tenantId,
      empresa_id: empresaId,
      item_id: itemId,
      tipo: "entrada",
      quantidade: qtd,
      motivo: `Backfill automatico da NF de entrada ${nfEntradaId}`,
      realizado_por: realizadoPor ?? "sistema",
      data_movimentacao: dataMov,
      custo_unitario_bruto: toNum(row.v_unit) || null,
      custo_unitario_real: toNum(row.v_unit) || null,
      v_ipi: toNum(row.v_ipi),
      v_icms: toNum(row.v_icms),
      v_pis: toNum(row.v_pis),
      v_cofins: toNum(row.v_cofins),
      v_frete_rateado: 0,
      credito_icms: creditoIcms,
      credito_pis: creditoPis,
      credito_cofins: creditoCofins,
      origem_nf_entrada_id: nfEntradaId,
    });
  }

  if (inserts.length === 0) return { inserted: 0 };

  const insertedItemIds = Array.from(insertedQuantByItem.keys());
  const { data: estoqueAntes } = await admin
    .from("estoque")
    .select("item_id,quantidade_atual")
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .in("item_id", insertedItemIds)
    .returns<Array<{ item_id: number; quantidade_atual: number | null }>>();

  const qtdAntes = new Map<number, number>();
  for (const row of Array.isArray(estoqueAntes) ? estoqueAntes : []) {
    const itemId = Number(row.item_id ?? 0);
    if (!Number.isFinite(itemId) || itemId <= 0) continue;
    qtdAntes.set(itemId, toNum(row.quantidade_atual));
  }

  const { error: insErr } = await admin.from("movimentacoes").insert(inserts);
  if (insErr) throw new Error(insErr.message);

  // Se trigger nao refletiu saldo, aplica ajuste manual idempotente por item.
  const { data: estoqueDepois } = await admin
    .from("estoque")
    .select("item_id,quantidade_atual")
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .in("item_id", insertedItemIds)
    .returns<Array<{ item_id: number; quantidade_atual: number | null }>>();

  const qtdDepois = new Map<number, number>();
  for (const row of Array.isArray(estoqueDepois) ? estoqueDepois : []) {
    const itemId = Number(row.item_id ?? 0);
    if (!Number.isFinite(itemId) || itemId <= 0) continue;
    qtdDepois.set(itemId, toNum(row.quantidade_atual));
  }

  const ajusteManual: Array<{ item_id: number; quantidade_atual: number; tenant_id: string; empresa_id: string }> = [];
  for (const itemId of insertedItemIds) {
    const antes = qtdAntes.get(itemId) ?? 0;
    const depois = qtdDepois.get(itemId) ?? 0;
    const esperadoMinimo = antes + (insertedQuantByItem.get(itemId) ?? 0);
    if (depois >= esperadoMinimo) continue;
    ajusteManual.push({
      tenant_id: tenantId,
      empresa_id: empresaId,
      item_id: itemId,
      quantidade_atual: esperadoMinimo,
    });
  }

  if (ajusteManual.length > 0) {
    const { error: estoqueUpsertErr } = await admin
      .from("estoque")
      .upsert(ajusteManual, { onConflict: "tenant_id,empresa_id,item_id" });
    if (estoqueUpsertErr) throw new Error(estoqueUpsertErr.message);
  }

  return { inserted: inserts.length };
}

async function syncDocumentoFiscalImpostosFromNfEntradaFallback(opts: {
  tenantId: string;
  empresaId: string;
  nfEntradaId: number;
}) {
  const admin = supabaseAdmin();

  const { data: nfRow, error: nfErr } = await admin
    .from("nf_entrada")
    .select("chave")
    .eq("tenant_id", opts.tenantId)
    .eq("empresa_id", opts.empresaId)
    .eq("id", opts.nfEntradaId)
    .maybeSingle<{ chave: string | null }>();
  if (nfErr) throw new Error(nfErr.message);

  // Usa função SECURITY DEFINER para evitar depender de grants diretos em f.documento_fiscal.
  let { data: documentoFiscalIdRaw, error: findErr } = await admin.schema("f").rpc("fn_find_documento_fiscal_from_import", {
    p_tenant_id: opts.tenantId,
    p_empresa_id: opts.empresaId,
    p_nf_entrada_id: opts.nfEntradaId,
    p_chave_acesso: String(nfRow?.chave ?? ""),
  });
  if (findErr) {
    // Compatibilidade com ambientes antigos (assinatura somente com p_nf_entrada_id).
    const legacy = await admin.schema("f").rpc("fn_find_documento_fiscal_from_import", {
      p_nf_entrada_id: opts.nfEntradaId,
    });
    documentoFiscalIdRaw = legacy.data;
    findErr = legacy.error;
  }
  if (findErr) throw new Error(findErr.message);

  const documentoFiscalId =
    typeof documentoFiscalIdRaw === "string" && UUID_REGEX.test(documentoFiscalIdRaw) ? documentoFiscalIdRaw : null;
  if (!documentoFiscalId) return { synced: false, documentoFiscalId: null as string | null };

  const { error: syncErr } = await admin.schema("f").rpc("nfe_sync_creditos_entrada_from_nf_itens", {
    p_documento_fiscal_id: documentoFiscalId,
  });
  if (syncErr) throw new Error(syncErr.message);

  return { synced: true, documentoFiscalId };
}

async function syncPedidoMateriaisToOs(opts: {
  tenantId: string;
  empresaId: string;
  nfEntradaId: number;
  realizadoPor: string | null;
  osVinculos: Array<{ os_id: number; item_id: number; quantidade: number; valor_unitario: number }>;
}) {
  const admin = supabaseAdmin();
  const rows = opts.osVinculos.filter((r) => r.os_id > 0 && r.item_id > 0 && r.quantidade > 0);
  if (!rows.length) return;

  for (const row of rows) {
    const { data: movExists } = await admin
      .from("movimentacoes")
      .select("id")
      .eq("tenant_id", opts.tenantId)
      .eq("empresa_id", opts.empresaId)
      .eq("tipo", "saida")
      .eq("origem_nf_entrada_id", opts.nfEntradaId)
      .eq("origem_os_id", row.os_id)
      .eq("item_id", row.item_id)
      .limit(1)
      .maybeSingle<{ id: number }>();

    const { data: existing } = await admin
      .from("os_itens")
      .select("id,quantidade,valor_unitario,valor_total,baixa_estoque")
      .eq("tenant_id", opts.tenantId)
      .eq("empresa_id", opts.empresaId)
      .eq("os_id", row.os_id)
      .eq("item_id", row.item_id)
      .limit(1)
      .maybeSingle<{
        id: number;
        quantidade: number | null;
        valor_unitario: number | null;
        valor_total: number | null;
        baixa_estoque: boolean | null;
      }>();

    if (existing?.id) {
      const qtdAtual = toNum(existing.quantidade);
      const valorUnitEntrada = toNum(row.valor_unitario);
      const valorUnitAtual = toNum(existing.valor_unitario);
      const valorUnitFinal = valorUnitAtual > 0 ? valorUnitAtual : valorUnitEntrada;

      const isRepairOnly =
        !movExists?.id &&
        qtdAtual >= row.quantidade &&
        (valorUnitAtual === 0 || Math.abs(valorUnitAtual - valorUnitEntrada) < 0.0001);

      const qtdAdicionar = movExists?.id ? 0 : isRepairOnly ? 0 : row.quantidade;
      const qtdNova = qtdAtual + qtdAdicionar;
      const incrementoTotal = qtdAdicionar * (valorUnitEntrada > 0 ? valorUnitEntrada : valorUnitFinal);
      const valorTotalAtual = toNum(existing.valor_total);
      const valorTotalNovo = valorTotalAtual > 0 ? valorTotalAtual + incrementoTotal : qtdNova * valorUnitFinal;
      await admin
        .from("os_itens")
        .update({
          quantidade: qtdNova,
          valor_unitario: Number.isFinite(valorUnitFinal) ? valorUnitFinal : 0,
          valor_total: Number.isFinite(valorTotalNovo) ? valorTotalNovo : 0,
          baixa_estoque: true,
        })
        .eq("tenant_id", opts.tenantId)
        .eq("empresa_id", opts.empresaId)
        .eq("id", existing.id);
    } else {
      const valorUnit = toNum(row.valor_unitario);
      const valorTotal = row.quantidade * valorUnit;
      await admin.from("os_itens").insert({
        tenant_id: opts.tenantId,
        empresa_id: opts.empresaId,
        os_id: row.os_id,
        item_id: row.item_id,
        quantidade: row.quantidade,
        valor_unitario: Number.isFinite(valorUnit) ? valorUnit : 0,
        valor_total: Number.isFinite(valorTotal) ? valorTotal : 0,
        baixa_estoque: true,
        criado_em: new Date().toISOString(),
      });
    }

    if (!movExists?.id) {
      const motivo = `Baixa automatica via XML NF ${opts.nfEntradaId} [OS ${row.os_id}]`;
      await admin.from("movimentacoes").insert({
        tenant_id: opts.tenantId,
        empresa_id: opts.empresaId,
        item_id: row.item_id,
        tipo: "saida",
        quantidade: row.quantidade,
        motivo,
        realizado_por: opts.realizadoPor ?? "sistema",
        data_movimentacao: new Date().toISOString(),
        origem_nf_entrada_id: opts.nfEntradaId,
        origem_os_id: row.os_id,
      });
    }
  }
}

async function buildDirectOsVinculosFromNfEntrada(opts: {
  tenantId: string;
  empresaId: string;
  nfEntradaId: number;
  osId: number;
}): Promise<Array<{ os_id: number; item_id: number; quantidade: number; valor_unitario: number }>> {
  const admin = supabaseAdmin();
  if (!Number.isFinite(opts.osId) || opts.osId <= 0) return [];

  const { data: nfItens, error: nfItensErr } = await admin
    .from("nf_entrada_itens")
    .select("item_id,qtd,v_unit")
    .eq("tenant_id", opts.tenantId)
    .eq("empresa_id", opts.empresaId)
    .eq("nf_entrada_id", opts.nfEntradaId)
    .returns<Array<{ item_id: number | null; qtd: number | null; v_unit: number | null }>>();
  if (nfItensErr) return [];

  const agregados = new Map<number, { quantidade: number; valor_unitario: number }>();
  for (const row of Array.isArray(nfItens) ? nfItens : []) {
    const itemId = Number(row.item_id ?? 0);
    const qtd = Math.max(0, toNum(row.qtd));
    const vUnit = Math.max(0, toNum(row.v_unit));
    if (!Number.isFinite(itemId) || itemId <= 0 || qtd <= 0) continue;
    const prev = agregados.get(itemId);
    agregados.set(itemId, {
      quantidade: (prev?.quantidade ?? 0) + qtd,
      valor_unitario: vUnit > 0 ? vUnit : prev?.valor_unitario ?? 0,
    });
  }
  if (agregados.size === 0) return [];

  const itemIds = Array.from(agregados.keys());
  const { data: osItensRows, error: osItensErr } = await admin
    .from("os_itens")
    .select("item_id")
    .eq("tenant_id", opts.tenantId)
    .eq("empresa_id", opts.empresaId)
    .eq("os_id", opts.osId)
    .in("item_id", itemIds)
    .returns<Array<{ item_id: number | null }>>();
  if (osItensErr) return [];

  const itemIdsPresentesNaOs = new Set(
    (Array.isArray(osItensRows) ? osItensRows : [])
      .map((r) => Number(r.item_id ?? 0))
      .filter((n) => Number.isFinite(n) && n > 0)
  );

  const vinculos: Array<{ os_id: number; item_id: number; quantidade: number; valor_unitario: number }> = [];
  for (const [itemId, agg] of agregados.entries()) {
    if (!itemIdsPresentesNaOs.has(itemId)) continue;
    vinculos.push({
      os_id: opts.osId,
      item_id: itemId,
      quantidade: agg.quantidade,
      valor_unitario: agg.valor_unitario,
    });
  }
  return vinculos;
}

async function getCurrentUsuarioId(opts: { authUserId: string }): Promise<string | null> {
  const admin = supabaseAdmin();
  const { data, error } = await admin
    .schema("a")
    .from("usuario")
    .select("id")
    .eq("auth_user_id", opts.authUserId)
    .is("deleted_at", null)
    .maybeSingle<{ id: string }>();

  if (error) return null;
  return readIdString(data);
}

async function mergeFornecedoresByIds(opts: {
  tenantId: string;
  empresaId: string;
  principalId: number;
  duplicateIds: number[];
}) {
  const admin = supabaseAdmin();
  const { tenantId, empresaId, principalId, duplicateIds } = opts;
  if (!duplicateIds.length) return;

  // Best-effort updates across known tables in this project.
  // Keep failures non-fatal to avoid blocking imports.
  const safeUpdate = async (fn: () => Promise<unknown>) => {
    try {
      await fn();
    } catch {
      // ignore
    }
  };

  await safeUpdate(async () => {
    await admin
      .from("nf_entrada")
      .update({ fornecedor_id: principalId })
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .in("fornecedor_id", duplicateIds);
  });

  await safeUpdate(async () => {
    await admin
      .from("itens")
      .update({ fornecedor_id: principalId })
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .in("fornecedor_id", duplicateIds);
  });

  await safeUpdate(async () => {
    await admin
      .schema("f")
      .from("documento_fiscal")
      .update({ fornecedor_id: principalId })
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .in("fornecedor_id", duplicateIds);
  });

  await safeUpdate(async () => {
    await admin
      .schema("f")
      .from("titulo")
      .update({ fornecedor_id: principalId })
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .in("fornecedor_id", duplicateIds);
  });

  // Deactivate duplicates (keep row for audit/history)
  await safeUpdate(async () => {
    await admin
      .from("fornecedores")
      .update({ ativo: false, atualizado_em: new Date().toISOString() })
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .in("id", duplicateIds);
  });
}

async function resolveFornecedorId(opts: {
  tenantId: string;
  empresaId: string;
  cnpj: string | null;
  nome: string | null;
}): Promise<{ fornecedorId: number; fornecedorSemCnpj: boolean } | { error: string; status: number }> {
  const admin = supabaseAdmin();
  const tenantId = opts.tenantId;
  const empresaId = opts.empresaId;

  const nomeNorm = normalizeName(opts.nome);
  const cnpjNorm = normalizeCnpj(opts.cnpj);

  if (cnpjNorm) {
    const { data, error } = await admin
      .from("fornecedores")
      .select("id,cnpj_norm,nome,ativo")
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .or(`cnpj_norm.eq.${cnpjNorm},documento_norm.eq.${cnpjNorm}`)
      .order("id", { ascending: true })
      .returns<FornecedorRow[]>();

    if (error) return { error: error.message, status: 400 };

    const rows = (data ?? []).filter((r) => r && typeof r.id === "number");
    if (rows.length > 1) {
      const principalId = rows[0].id;
      const duplicateIds = rows.slice(1).map((r) => r.id);
      await mergeFornecedoresByIds({ tenantId, empresaId, principalId, duplicateIds });
      return { fornecedorId: principalId, fornecedorSemCnpj: false };
    }

    if (rows.length === 1) {
      const fornecedorId = rows[0].id;
      // Best-effort: update name to latest from XML (don't blank existing)
      if (nomeNorm) {
        try {
          await admin
            .from("fornecedores")
            .update({ nome: nomeNorm })
            .eq("tenant_id", tenantId)
            .eq("empresa_id", empresaId)
            .eq("id", fornecedorId);
        } catch {
          // ignore
        }
      }
      return { fornecedorId, fornecedorSemCnpj: false };
    }

    // Not found: create
    const { data: created, error: insErr } = await admin
      .from("fornecedores")
      .insert({
        tenant_id: tenantId,
        empresa_id: empresaId,
        nome: nomeNorm || "Fornecedor NF",
        cnpj: cnpjNorm,
        documento: cnpjNorm,
        ativo: true,
      })
      .select("id")
      .single();

    if (insErr) {
      // If a concurrent import created it, re-select
      const { data: retry } = await admin
        .from("fornecedores")
        .select("id")
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId)
        .or(`cnpj_norm.eq.${cnpjNorm},documento_norm.eq.${cnpjNorm}`)
        .order("id", { ascending: true })
        .limit(1)
        .maybeSingle();

      const id = readIdNumber(retry);
      if (id) return { fornecedorId: id, fornecedorSemCnpj: false };
      return { error: insErr.message, status: 400 };
    }

    return { fornecedorId: readIdNumber(created) ?? 0, fornecedorSemCnpj: false };
  }

  // No CNPJ: allow provisional-by-name
  if (!nomeNorm) return { error: "Fornecedor sem CNPJ: nome do emitente ausente.", status: 422 };

  const { data: existing, error: exErr } = await admin
    .from("fornecedores")
    .select("id")
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .eq("nome", nomeNorm)
    .is("cnpj", null)
    .order("id", { ascending: true })
    .limit(1)
    .maybeSingle();

  if (exErr) return { error: exErr.message, status: 400 };

  const existingId = readIdNumber(existing);
  if (existingId) return { fornecedorId: existingId, fornecedorSemCnpj: true };

  const { data: created, error: insErr } = await admin
    .from("fornecedores")
    .insert({
      tenant_id: tenantId,
      empresa_id: empresaId,
      nome: nomeNorm,
      cnpj: null,
      documento: null,
      ativo: true,
    })
    .select("id")
    .single();

  if (insErr) return { error: insErr.message, status: 400 };
  return { fornecedorId: readIdNumber(created) ?? 0, fornecedorSemCnpj: true };
}

export async function POST(req: NextRequest) {
  try {
    const authorization = req.headers.get("authorization");
    if (!authorization) return jerr(401, "Nao autenticado.");

    const supabase = supabaseFromAuthHeader(req);
    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData.user) return jerr(401, "Nao autenticado.");

    const body = (await req.json()) as ImportBody;

    const tenantId = String(body.tenantId ?? "").trim();
    const empresaId = String(body.empresaId ?? "").trim();
    if (!tenantId) return jerr(400, "tenantId obrigatorio.");
    if (!empresaId) return jerr(400, "empresaId obrigatorio.");

    const xmlRaw = typeof body.xmlRaw === "string" ? body.xmlRaw : null;
    if (xmlRaw !== null && xmlRaw.trim().length === 0) {
      return jerr(422, "XML vazio/whitespace: envie o XML completo (xmlRaw).");
    }
    if (xmlRaw === null) {
      const itens = body.itensJson;
      if (!Array.isArray(itens) || itens.length === 0) {
        return jerr(422, "XML ausente: envie o XML completo ou informe itens completos para importar sem XML.");
      }
    }

    // Permission: xml import execute
    const { data: canImport, error: canErr } = await supabase.rpc("can", {
      p_resource: "xml_import",
      p_action: "execute",
    });
    const canImportXml = !canErr && Boolean(canImport);
    if (!canImportXml) return jerr(403, "Sem permissao para importar XML.");

    // Validate empresa membership
    const allowed = await getAllowedEmpresas(supabase, tenantId);
    if (!allowed.some((e) => e.id === empresaId)) return jerr(403, "Sem acesso a esta empresa.");

    // Motivo obrigatório
    const pedidoCompraRaw = String(body.pedidoCompraId ?? "").trim();
    const pedidoFlow = pedidoCompraRaw.length > 0;
    const motivoCompraRaw = String(body.motivoCompraId ?? "").trim();

    // Solicitante pode vir da tela ou do pedido de compra vinculado.
    let solicitanteUsuarioId = String(body.solicitanteUsuarioId ?? "").trim();
    if (solicitanteUsuarioId && !UUID_REGEX.test(solicitanteUsuarioId)) {
      return jerr(400, "Solicitante (usuario) invalido.");
    }

    const admin = supabaseAdmin();
    const currentUsuarioId = await getCurrentUsuarioId({ authUserId: userData.user.id });
    let aprovadoPorUsuarioId = currentUsuarioId ?? solicitanteUsuarioId;

    const resolved = await resolveFornecedorId({
      tenantId,
      empresaId,
      cnpj: body.fornecedorCnpj ?? null,
      nome: body.fornecedorNome ?? null,
    });

    if ("error" in resolved) return jerr(resolved.status, resolved.error);

    if (resolved.fornecedorSemCnpj) {
      console.warn("[XML_IMPORT] fornecedor sem CNPJ (provisorio)", {
        tenantId,
        empresaId,
        nome: normalizeName(body.fornecedorNome),
      });
    }

    let finalidade = body.finalidade ?? null;
    const osId = typeof body.osId === "number" ? body.osId : null;
    const gerar = Boolean(body.gerarContasPagar);
    const finalidadesComItemObrigatorio = new Set(["materia_prima", "revenda"]);

    let itensJsonToImport: unknown = body.itensJson ?? null;
    let pedidoCompraIdVinculado: string | null = null;
    let pedidoRecebimentos: Array<{ pedidoItemId: string; quantidade: number }> = [];
    let pedidoOsVinculos: Array<{ os_id: number; item_id: number; quantidade: number; valor_unitario: number }> = [];
    let pedidoHasOsOrigem = false;
    let pedidoLinkWarnings: string[] = [];
    let solicitanteFromPedido: string | null = null;
    let pedidoDocumentoRef: string | null = null;

    if (pedidoCompraRaw) {
      const linked = await bindImportItemsFromPedido({
        tenantId,
        empresaId,
        pedidoCompraRaw,
        fornecedorId: resolved.fornecedorId,
        fornecedorCnpj: body.fornecedorCnpj ?? null,
        finalidade,
        nfJson: body.nfJson ?? null,
        itensJson: itensJsonToImport,
      });
      itensJsonToImport = linked.itensJson;
      pedidoCompraIdVinculado = linked.pedidoId;
      pedidoRecebimentos = linked.recebimentoItens;
      pedidoOsVinculos = linked.osVinculos;
      pedidoHasOsOrigem = linked.pedidoHasOsOrigem;
      pedidoLinkWarnings = linked.warnings;
      solicitanteFromPedido = linked.solicitanteUsuarioId;
      pedidoDocumentoRef = linked.documentoRef;
      for (const w of linked.warnings) {
        console.warn("[XML_IMPORT][PEDIDO]", { tenantId, empresaId, pedidoCompraRaw, warning: w });
      }
    }

    const simplesCreditFallback = applySimplesScIcmsCreditFallback({
      xmlRaw,
      itensJson: itensJsonToImport,
    });
    itensJsonToImport = simplesCreditFallback.itensJson;
    if (simplesCreditFallback.applied && simplesCreditFallback.reason) {
      console.warn("[XML_IMPORT][ICMS_CREDITO_FALLBACK]", {
        tenantId,
        empresaId,
        reason: simplesCreditFallback.reason,
      });
    }

    if (!String(finalidade ?? "").trim() && pedidoFlow) {
      finalidade = pedidoOsVinculos.length > 0 ? "materia_prima" : "consumo";
    }
    const finalidadeNorm = String(finalidade ?? "").trim();

    let motivoCompraId = motivoCompraRaw;
    if (!motivoCompraId && pedidoFlow) {
      const { data: fornMotivo } = await admin
        .from("fornecedores")
        .select("motivo_compra_padrao_id")
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId)
        .eq("id", resolved.fornecedorId)
        .maybeSingle<{ motivo_compra_padrao_id: string | null }>();

      const fallback = String(fornMotivo?.motivo_compra_padrao_id ?? "").trim();
      if (fallback) motivoCompraId = fallback;

      // Fallback adicional para fluxo via pedido:
      // quando fornecedor nao tem motivo padrao, escolhe automaticamente um motivo ativo
      // coerente com a finalidade inferida do pedido.
      if (!motivoCompraId) {
        const prioridadePorFinalidade: Record<string, string[]> = {
          materia_prima: ["EST_MATERIA_PRIMA", "OS_MATERIAL_DIRETO", "ESTOQUE", "OS", "CONSUMO_GERAL", "OUTROS"],
          revenda: ["EST_REVENDA", "ESTOQUE", "OUTROS"],
          consumo: ["CONSUMO", "CONSUMO_GERAL", "OUTROS"],
          outros: ["OUTROS", "ESTOQUE", "CONSUMO_GERAL"],
          imobilizado: ["IMOB_AQUISICAO", "IMOB_MELHORIA", "OUTROS"],
        };
        const key = String(finalidadeNorm || "outros").toLowerCase();
        const prioridade = prioridadePorFinalidade[key] ?? prioridadePorFinalidade.outros;

        const { data: motivosPrioridade } = await admin
          .schema("f")
          .from("motivo_compra")
          .select("id,codigo")
          .eq("tenant_id", tenantId)
          .eq("ativo", true)
          .is("deleted_at", null)
          .in("codigo", prioridade)
          .returns<Array<{ id: string; codigo: string | null }>>();

        if (Array.isArray(motivosPrioridade) && motivosPrioridade.length > 0) {
          const byCodigo = new Map(
            motivosPrioridade.map((r) => [String(r.codigo ?? "").trim().toUpperCase(), String(r.id ?? "").trim()])
          );
          for (const cod of prioridade) {
            const id = byCodigo.get(cod);
            if (id) {
              motivoCompraId = id;
              break;
            }
          }
        }
      }

      // Ultimo fallback: primeiro motivo ativo que nao seja NAO_CLASSIFICADO.
      if (!motivoCompraId) {
        const { data: firstMotivo } = await admin
          .schema("f")
          .from("motivo_compra")
          .select("id,codigo")
          .eq("tenant_id", tenantId)
          .eq("ativo", true)
          .is("deleted_at", null)
          .neq("codigo", "NAO_CLASSIFICADO")
          .order("codigo", { ascending: true })
          .limit(1)
          .maybeSingle<{ id: string; codigo: string | null }>();
        const id = String(firstMotivo?.id ?? "").trim();
        if (id) motivoCompraId = id;
      }
    }

    if (!motivoCompraId) return jerr(422, "Classificacao/Motivo obrigatorio.");
    if (!UUID_REGEX.test(motivoCompraId)) return jerr(400, "Motivo invalido.");

    const { data: motivoRow, error: motivoErr } = await admin
      .schema("f")
      .from("motivo_compra")
      .select("id,codigo,ativo,deleted_at")
      .eq("tenant_id", tenantId)
      .eq("id", motivoCompraId)
      .eq("ativo", true)
      .is("deleted_at", null)
      .maybeSingle<{ id: string; codigo: string | null; ativo: boolean; deleted_at: string | null }>();

    if (motivoErr || !motivoRow) return jerr(422, "Motivo invalido ou inativo.");

    const codigo = String(motivoRow.codigo ?? "").trim().toUpperCase();
    if (!codigo || codigo === "NAO_CLASSIFICADO") {
      return jerr(422, "Selecione um motivo valido (nao pode ser NAO_CLASSIFICADO).");
    }

    if (!solicitanteUsuarioId && solicitanteFromPedido) {
      solicitanteUsuarioId = solicitanteFromPedido;
    }
    if (!solicitanteUsuarioId) return jerr(422, "Solicitante (usuario) obrigatorio.");
    if (!UUID_REGEX.test(solicitanteUsuarioId)) return jerr(400, "Solicitante (usuario) invalido.");
    aprovadoPorUsuarioId = currentUsuarioId ?? solicitanteUsuarioId;

    if (finalidadesComItemObrigatorio.has(finalidadeNorm)) {
      const itens = Array.isArray(itensJsonToImport) ? itensJsonToImport : [];
      const itensSemCadastro: string[] = [];

      for (const row of itens) {
        if (!row || typeof row !== "object") continue;
        const rec = row as Record<string, unknown>;
        const itemIdRaw = rec.item_id;
        const itemId = typeof itemIdRaw === "number" ? itemIdRaw : Number(itemIdRaw);
        if (Number.isFinite(itemId) && itemId > 0) continue;

        const codigo = String(rec.codigo ?? "").trim();
        itensSemCadastro.push(codigo || "(sem codigo)");
      }

      if (itensSemCadastro.length > 0) {
        return jerr(422, `Itens nao cadastrados: ${itensSemCadastro.join(", ")}`);
      }
    }

    const docRefPreflight =
      pedidoDocumentoRef ??
      (String((body.nfJson as Record<string, unknown> | null)?.chave ?? "").trim() || null);
    const preflightIssues = await runStrictImportPreflight({
      tenantId,
      empresaId,
      pedidoCompraRaw,
      pedidoCompraIdVinculado,
      pedidoLinkWarnings,
      pedidoRecebimentos,
      pedidoOsVinculos,
      finalidadeNorm,
      osId,
      itensJsonToImport,
      documentoRef: docRefPreflight,
    });
    if (preflightIssues.length > 0) {
      const issueText = preflightIssues.map((issue, idx) => `${idx + 1}) ${issue}`).join(" | ");
      return jerr(
        422,
        `Pre-validacao da importacao falhou: ${issueText}`,
        { issues: preflightIssues }
      );
    }

    // Call import RPC using the user's auth context
    const { data: importData, error: importErr } = await supabase.rpc("import_nf_entrada", {
      p_empresa_id: empresaId,
      p_fornecedor_id: resolved.fornecedorId,
      p_finalidade_contexto: finalidade,
      p_itens_json: itensJsonToImport ?? null,
      p_nf_json: body.nfJson ?? null,
      p_tenant_id: tenantId,
      p_xml_raw: xmlRaw,
      p_gerar_contas_pagar: gerar,
      p_parcelas_json: gerar ? (body.parcelasJson ?? null) : null,
      p_os_id: osId,
      p_baixar_os: false,
      p_motivo_compra_id: motivoCompraId,
      p_solicitante_usuario_id: solicitanteUsuarioId,
    });

    if (importErr) return jerr(400, importErr.message ?? "Erro ao importar NF.");

    const resultUnknown = Array.isArray(importData) ? (importData[0] as unknown) : (importData as unknown);
    const result = (resultUnknown ?? null) as { status?: unknown; message?: unknown; nf_entrada_id?: unknown; nf_id?: unknown } | null;
    const status = String(result?.status ?? "ok");
    const message = String(result?.message ?? "");
    const nfEntradaIdRaw = result?.nf_entrada_id ?? result?.nf_id ?? null;
    const nfEntradaId = nfEntradaIdRaw ? Number(nfEntradaIdRaw) || null : null;
    const postImportWarnings: Array<{ code: string; message: string; data?: Record<string, unknown> }> = [];

    if (!nfEntradaId) return jerr(500, "Importacao nao retornou nf_entrada_id.");

    await reconcileNfEntradaItemIdsFromPayload({
      tenantId,
      empresaId,
      nfEntradaId,
      itensJson: itensJsonToImport ?? null,
    });

    // Fallback de robustez: se o vinculo com pedido nao gerou recebimentos/OS no payload,
    // tenta novamente usando os itens efetivamente gravados na nf_entrada.
    const needsPedidoOsRelink =
      String(finalidadeNorm).toLowerCase() === "materia_prima" && pedidoHasOsOrigem && pedidoOsVinculos.length === 0;
    if (
      pedidoCompraRaw &&
      (!pedidoCompraIdVinculado ||
        pedidoRecebimentos.length === 0 ||
        needsPedidoOsRelink)
    ) {
      const { data: nfItensPersistidos, error: nfItensPersistidosErr } = await admin
        .from("nf_entrada_itens")
        .select("item_id,codigo_fornecedor,descricao,qtd,v_unit,v_icms,v_ipi,v_pis,v_cofins")
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId)
        .eq("nf_entrada_id", nfEntradaId)
        .returns<NfEntradaItemRow[]>();

      if (!nfItensPersistidosErr) {
        const itensFallback = (Array.isArray(nfItensPersistidos) ? nfItensPersistidos : []).map((r) => ({
          item_id: Number(r.item_id ?? 0) > 0 ? Number(r.item_id) : null,
          codigo_fornecedor: String(r.codigo_fornecedor ?? "").trim() || null,
          codigo: String(r.codigo_fornecedor ?? "").trim() || null,
          descricao: String(r.descricao ?? "").trim(),
          nome: String(r.descricao ?? "").trim(),
          qtd: toNum(r.qtd),
          quantidade: toNum(r.qtd),
          v_unit: toNum(r.v_unit),
          valor_unitario: toNum(r.v_unit),
          v_icms: toNum(r.v_icms),
          v_ipi: toNum(r.v_ipi),
          v_pis: toNum(r.v_pis),
          v_cofins: toNum(r.v_cofins),
        }));

        const relink = await bindImportItemsFromPedido({
          tenantId,
          empresaId,
          pedidoCompraRaw,
          fornecedorId: resolved.fornecedorId,
          fornecedorCnpj: body.fornecedorCnpj ?? null,
          finalidade,
          nfJson: body.nfJson ?? null,
          itensJson: itensFallback,
        });

        if (!pedidoCompraIdVinculado && relink.pedidoId) {
          pedidoCompraIdVinculado = relink.pedidoId;
        }
        pedidoHasOsOrigem = pedidoHasOsOrigem || relink.pedidoHasOsOrigem;
        pedidoRecebimentos = mergeRecebimentoItensByMax(pedidoRecebimentos, relink.recebimentoItens);
        pedidoOsVinculos = mergeOsVinculosByMax(pedidoOsVinculos, relink.osVinculos);
        for (const w of relink.warnings) {
          console.warn("[XML_IMPORT][PEDIDO][RELINK_FALLBACK]", {
            tenantId,
            empresaId,
            nfEntradaId,
            pedidoCompraRaw,
            warning: w,
          });
        }
      }
    }

    // Idempotent stock backfill to guarantee movement consistency both for new and already-imported NFs.
    // Prioriza o fallback local para preservar rastreabilidade de quem executou a operacao.
    const backfillActor = userData.user.email ?? userData.user.id ?? "sistema";
    let fallbackBackfillError: string | null = null;
    try {
      await syncMovimentacoesFromNfEntradaFallback({
        tenantId,
        empresaId,
        nfEntradaId,
        realizadoPor: backfillActor,
      });
    } catch (fallbackErr: unknown) {
      fallbackBackfillError = fallbackErr instanceof Error ? fallbackErr.message : "erro desconhecido";
      console.warn("[XML_IMPORT][MOV_BACKFILL] falha no fallback primario; tentando RPC com contexto do usuario", {
        tenantId,
        empresaId,
        nfEntradaId,
        error: fallbackBackfillError,
      });
    }

    if (fallbackBackfillError) {
      const { error: backfillMovErr } = await supabase.rpc("fn_backfill_movimentacoes_nf_entrada", {
        p_nf_entrada_id: nfEntradaId,
      });
      if (backfillMovErr) {
        return jerr(
          422,
          `NF importada, mas falhou ao sincronizar movimentacoes de estoque. nf_entrada_id=${nfEntradaId}. Fallback: ${fallbackBackfillError}. RPC: ${backfillMovErr.message}`
        );
      }
    }

    // Mandatory post-condition: import must end with AP title + parcelas consistent.
    const parcelasArray = Array.isArray(body.parcelasJson) ? body.parcelasJson : null;

    const { data: tituloIdRaw, error: ensureErr } = await admin.rpc("fn_ensure_titulo_ap_from_nf_entrada", {
      p_nf_entrada_id: nfEntradaId,
      p_force_regen_parcelas: false,
      p_parcelas_json: parcelasArray,
    });
    if (ensureErr) {
      return jerr(
        422,
        `NF importada, mas falhou ao garantir Contas a Pagar. nf_entrada_id=${nfEntradaId}. Detalhe: ${ensureErr.message}`
      );
    }

    const tituloId = typeof tituloIdRaw === "string" && UUID_REGEX.test(tituloIdRaw) ? tituloIdRaw : null;
    if (!tituloId) {
      return jerr(422, `NF importada, mas não foi possível localizar/gerar título AP. nf_entrada_id=${nfEntradaId}`);
    }

    const { error: syncErr } = await admin.rpc("fn_sync_titulo_aprovacao_from_nf_entrada", {
      p_nf_entrada_id: nfEntradaId,
      p_titulo_id: tituloId,
      p_motivo_compra_id: motivoCompraId,
      p_os_id: osId,
      p_aprovado_por: aprovadoPorUsuarioId,
    });
    if (syncErr) {
      return jerr(
        422,
        `NF importada e estoque sincronizado, mas falhou ao sincronizar classificacao/aprovacao do titulo AP (${tituloId}). Detalhe: ${syncErr.message}`
      );
    }

    try {
      await syncDocumentoFiscalImpostosFromNfEntradaFallback({
        tenantId,
        empresaId,
        nfEntradaId,
      });
    } catch (fiscalSyncErr) {
      console.warn("[XML_IMPORT][FISCAL_SYNC] falha nao-bloqueante ao sincronizar impostos para apuracao", {
        tenantId,
        empresaId,
        nfEntradaId,
        error: fiscalSyncErr instanceof Error ? fiscalSyncErr.message : "erro desconhecido",
      });
    }

    if (String(finalidadeNorm).toLowerCase() === "materia_prima" && pedidoOsVinculos.length > 0) {
      try {
        await syncPedidoMateriaisToOs({
          tenantId,
          empresaId,
          nfEntradaId,
          realizadoPor: userData.user.email ?? userData.user.id ?? "sistema",
          osVinculos: pedidoOsVinculos,
        });
      } catch (osSyncErr) {
        console.warn("[XML_IMPORT][OS] falha ao vincular materiais da NF na OS do pedido", {
          tenantId,
          empresaId,
          nfEntradaId,
          error: osSyncErr instanceof Error ? osSyncErr.message : "erro desconhecido",
        });
      }
    }

    // Fluxo direto para OS (sem pedido vinculado): garante baixa por movimentacao
    // para nao deixar saldo duplicado (entrada em estoque + consumo na OS).
    if (
      String(finalidadeNorm).toLowerCase() === "materia_prima" &&
      pedidoOsVinculos.length === 0 &&
      Number.isFinite(osId) &&
      Number(osId) > 0
    ) {
      try {
        const osVinculosDireto = await buildDirectOsVinculosFromNfEntrada({
          tenantId,
          empresaId,
          nfEntradaId,
          osId: Number(osId),
        });
        if (osVinculosDireto.length > 0) {
          await syncPedidoMateriaisToOs({
            tenantId,
            empresaId,
            nfEntradaId,
            realizadoPor: userData.user.email ?? userData.user.id ?? "sistema",
            osVinculos: osVinculosDireto,
          });
        }
      } catch (osDirectSyncErr) {
        console.warn("[XML_IMPORT][OS_DIRETO] falha ao sincronizar baixa da NF na OS informada", {
          tenantId,
          empresaId,
          nfEntradaId,
          osId,
          error: osDirectSyncErr instanceof Error ? osDirectSyncErr.message : "erro desconhecido",
        });
      }
    }

    if (pedidoCompraIdVinculado && pedidoRecebimentos.length > 0) {
      const docRef = pedidoDocumentoRef ?? `NF_ENTRADA_${nfEntradaId}`;
      const { data: recebExists } = await admin
        .schema("m")
        .from("pedido_compra_recebimento")
        .select("id")
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId)
        .eq("pedido_compra_id", pedidoCompraIdVinculado)
        .eq("documento_ref", docRef)
        .is("deleted_at", null)
        .limit(1)
        .maybeSingle<RowWithId>();

      if (!readIdString(recebExists)) {
        const emissao = String((body.nfJson as Record<string, unknown> | null)?.data_emissao ?? "")
          .trim()
          .slice(0, 10);
        const recebDate = /^\d{4}-\d{2}-\d{2}$/.test(emissao) ? emissao : new Date().toISOString().slice(0, 10);
        try {
          await registrarRecebimentoPedidoViaImportFallback({
            tenantId,
            empresaId,
            pedidoCompraId: pedidoCompraIdVinculado,
            recebimentoDate: recebDate,
            documentoRef: docRef,
            observacoes: `Recebimento automatico via XML (NF entrada ${nfEntradaId})`,
            currentUsuarioId,
            recebimentoItens: pedidoRecebimentos,
          });
        } catch (receberErr) {
          const detail = receberErr instanceof Error ? receberErr.message : "erro desconhecido";
          console.warn("[XML_IMPORT][PEDIDO] falha ao registrar recebimento via rotina dedicada", {
            tenantId,
            empresaId,
            pedidoCompraIdVinculado,
            nfEntradaId,
            detail,
          });
          return jerr(
            422,
            `NF importada e estoque/OS sincronizados, mas falhou ao baixar o pedido ${pedidoCompraIdVinculado}. Detalhe: ${detail}`
          );
        }
      }
    }

    // Aviso nao-bloqueante: divergencia entre total do pedido e total da NF.
    // Regra de negocio: importar deve seguir; a tela orienta ajuste/validacao manual quando houver diferenca.
    if (pedidoCompraIdVinculado) {
      try {
        const { data: pedidoItensTotalRows, error: pedidoItensTotalErr } = await admin
          .schema("m")
          .from("pedido_compra_item")
          .select("quantidade,valor_unitario")
          .eq("tenant_id", tenantId)
          .eq("empresa_id", empresaId)
          .eq("pedido_compra_id", pedidoCompraIdVinculado)
          .is("deleted_at", null)
          .returns<Array<{ quantidade: number | null; valor_unitario: number | null }>>();

        if (!pedidoItensTotalErr) {
          const pedidoTotal = (Array.isArray(pedidoItensTotalRows) ? pedidoItensTotalRows : []).reduce(
            (sum, row) => sum + toNum(row.quantidade) * toNum(row.valor_unitario),
            0
          );

          const { data: nfResumo, error: nfResumoErr } = await admin
            .from("nf_entrada")
            .select("numero,serie,valor_total,valor_produtos")
            .eq("tenant_id", tenantId)
            .eq("empresa_id", empresaId)
            .eq("id", nfEntradaId)
            .maybeSingle<{ numero: string | null; serie: string | null; valor_total: number | null; valor_produtos: number | null }>();

          if (!nfResumoErr && nfResumo) {
            const nfValorProdutos = toNum(nfResumo.valor_produtos);
            const nfValorTotal = toNum(nfResumo.valor_total);
            const diffTotal = nfValorTotal - pedidoTotal;

            if (Math.abs(diffTotal) >= 0.01) {
              const sinal = diffTotal >= 0 ? "+" : "-";
              postImportWarnings.push({
                code: "pedido_nota_total_divergente",
                message:
                  `Aviso: diferenca entre pedido e NF ${String(nfResumo.numero ?? "?")}/${String(nfResumo.serie ?? "?")}. ` +
                  `Pedido: R$ ${formatMoneyBr(pedidoTotal)} | ` +
                  `NF produtos: R$ ${formatMoneyBr(nfValorProdutos)} | ` +
                  `NF total: R$ ${formatMoneyBr(nfValorTotal)} | ` +
                  `Diferenca (NF total - pedido): ${sinal}R$ ${formatMoneyBr(Math.abs(diffTotal))}.`,
                data: {
                  pedido_total: round6(pedidoTotal),
                  nf_valor_produtos: round6(nfValorProdutos),
                  nf_valor_total: round6(nfValorTotal),
                  diferenca_nf_total_menos_pedido: round6(diffTotal),
                },
              });
            }
          }
        }
      } catch (warnErr) {
        console.warn("[XML_IMPORT][WARN_PEDIDO_VS_NF] falha ao calcular aviso de diferenca", {
          tenantId,
          empresaId,
          pedidoCompraIdVinculado,
          nfEntradaId,
          error: warnErr instanceof Error ? warnErr.message : "erro desconhecido",
        });
      }
    }

    return NextResponse.json({ status, message, nf_entrada_id: nfEntradaId, warnings: postImportWarnings });
  } catch (e: unknown) {
    const message = e instanceof Error ? e.message : "Erro inesperado.";
    return jerr(500, message);
  }
}
