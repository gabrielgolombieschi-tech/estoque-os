import { NextRequest } from "next/server";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";
import { supabaseAdmin } from "@/lib/supabase/admin";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type AuthedSupabase = ReturnType<typeof supabaseFromAuthHeader>;
type SyncPedidoTotaisResult =
  | { error: string }
  | {
      data: {
        totalItens: number;
        totalIpi: number;
        totalGeral: number;
      };
    };
type ResolvedItemRow = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  descricao?: string | null;
  unidade_medida?: string | null;
  preco_unitario?: number | null;
  fornecedor_id?: number | null;
};
type ResolveItemByCodigoOuIdResult =
  | {
      data: ResolvedItemRow;
      matchedBy: "codigo" | "id";
    }
  | {
      error: string;
      status?: number;
    };

export function jsonError(status: number, error: string, details?: unknown) {
  return Response.json({ error, ...(details !== undefined ? { details } : {}) }, { status });
}

export async function getAuthSupabase(req: NextRequest) {
  const authorization = req.headers.get("authorization");
  if (!authorization) return { error: jsonError(401, "Nao autenticado.") } as const;

  const supabase = supabaseFromAuthHeader(req);
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) return { error: jsonError(401, "Nao autenticado.") } as const;

  return { supabase, user: data.user } as const;
}

type BodyLike = Record<string, unknown> | null | undefined;

export async function resolveTenantEmpresa(
  supabase: ReturnType<typeof supabaseFromAuthHeader>,
  body?: BodyLike,
  query?: URLSearchParams
) {
  const tenantHint = String(
    body?.tenant_id ??
      body?.tenantId ??
      query?.get("tenant_id") ??
      query?.get("tenantId") ??
      ""
  ).trim();
  const empresaHint = String(
    body?.empresa_id ??
      body?.empresaId ??
      query?.get("empresa_id") ??
      query?.get("empresaId") ??
      ""
  ).trim();

  let tenantId: string | null = null;
  let empresaId: string | null = null;

  try {
    const { data } = await supabase.rpc("current_tenant_id");
    tenantId = data ? String(data) : null;
  } catch {
    tenantId = null;
  }

  if (!tenantId && tenantHint && UUID_RE.test(tenantHint)) {
    try {
      await supabase.rpc("set_current_tenant", { p_tenant_id: tenantHint });
      const { data } = await supabase.rpc("current_tenant_id");
      tenantId = data ? String(data) : tenantHint;
    } catch {
      tenantId = null;
    }
  }

  try {
    const { data } = await supabase.rpc("current_empresa_id");
    empresaId = data ? String(data) : null;
  } catch {
    empresaId = null;
  }

  if (!empresaId && empresaHint && UUID_RE.test(empresaHint)) {
    try {
      await supabase.rpc("set_current_empresa", { p_empresa_id: empresaHint });
      const { data } = await supabase.rpc("current_empresa_id");
      empresaId = data ? String(data) : empresaHint;
    } catch {
      empresaId = null;
    }
  }

  if (!tenantId || !empresaId) return null;
  return { tenantId, empresaId };
}

export async function canCompras(
  supabase: ReturnType<typeof supabaseFromAuthHeader>,
  action: "read" | "write" | "approve" | "receive"
) {
  const { data } = await supabase.rpc("can", { p_resource: "compras", p_action: action });
  return Boolean(data);
}

type UsuarioIdRow = { id: string };
type UsuarioEmpresaAtivaRow = { usuario_id: string };
type CondicaoPagamentoLookupRow = { id: string; nome: string | null; codigo: string | null };
export type PedidoTransporteTipo = "CIF" | "FOB";

export function parsePedidoTransporteTipo(value: unknown): PedidoTransporteTipo | null | undefined {
  const raw = String(value ?? "").trim().toUpperCase();
  if (!raw) return null;
  if (raw === "CIF" || raw === "FOB") return raw;
  return undefined;
}

export function normalizeNullableText(value: unknown) {
  const raw = String(value ?? "").trim();
  return raw ? raw : null;
}

export function resolvePedidoTransporte(opts: {
  hasTransporteField?: boolean;
  hasTransportadoraField?: boolean;
  transporteTipo?: unknown;
  transportadoraNome?: unknown;
  currentTransporteTipo?: unknown;
  currentTransportadoraNome?: unknown;
}): { transporteTipo: PedidoTransporteTipo | null; transportadoraNome: string | null; error: string | null } {
  const currentTransporteParsed = parsePedidoTransporteTipo(opts.currentTransporteTipo);
  const nextTransporteParsed = parsePedidoTransporteTipo(opts.transporteTipo);
  if (nextTransporteParsed === undefined) {
    return { transporteTipo: null, transportadoraNome: null, error: "Transporte invalido. Use CIF ou FOB." };
  }

  const transporteTipo = opts.hasTransporteField
    ? (nextTransporteParsed ?? null)
    : currentTransporteParsed === undefined
      ? null
      : (currentTransporteParsed ?? null);

  let transportadoraNome = opts.hasTransportadoraField
    ? normalizeNullableText(opts.transportadoraNome)
    : normalizeNullableText(opts.currentTransportadoraNome);

  if (opts.hasTransportadoraField && transportadoraNome && transporteTipo !== "FOB") {
    return {
      transporteTipo,
      transportadoraNome,
      error: "Selecione transporte FOB para informar a transportadora.",
    };
  }

  if (transporteTipo !== "FOB") transportadoraNome = null;
  if (transporteTipo === "FOB" && !transportadoraNome) {
    return {
      transporteTipo,
      transportadoraNome,
      error: "Informe a transportadora quando o transporte for FOB.",
    };
  }

  return { transporteTipo, transportadoraNome, error: null };
}

async function usuarioAtivoNaEmpresa(admin: ReturnType<typeof supabaseAdmin>, empresaId: string, usuarioId: string) {
  const { data, error } = await admin
    .schema("a")
    .from("usuario_empresa")
    .select("usuario_id")
    .eq("empresa_id", empresaId)
    .eq("usuario_id", usuarioId)
    .eq("ativo", true)
    .is("deleted_at", null)
    .maybeSingle<UsuarioEmpresaAtivaRow>();

  if (error) throw error;
  return Boolean(data?.usuario_id);
}

export async function resolvePedidoSolicitanteUsuarioId(opts: {
  authUserId?: string | null;
  empresaId: string;
  requestedId?: string | null;
}): Promise<{ id: string | null; error: string | null }> {
  const admin = supabaseAdmin();
  const requestedId = String(opts.requestedId ?? "").trim();

  if (requestedId) {
    if (!UUID_RE.test(requestedId)) return { id: null, error: "Solicitante invalido." };
    const ativoNaEmpresa = await usuarioAtivoNaEmpresa(admin, opts.empresaId, requestedId);
    return ativoNaEmpresa
      ? { id: requestedId, error: null }
      : { id: null, error: "Solicitante invalido para esta empresa." };
  }

  const authUserId = String(opts.authUserId ?? "").trim();
  if (!UUID_RE.test(authUserId)) return { id: null, error: null };

  const { data: usuario, error: usuarioErr } = await admin
    .schema("a")
    .from("usuario")
    .select("id")
    .eq("auth_user_id", authUserId)
    .eq("ativo", true)
    .is("deleted_at", null)
    .maybeSingle<UsuarioIdRow>();

  if (usuarioErr) throw usuarioErr;
  const usuarioId = String(usuario?.id ?? "").trim();
  if (!UUID_RE.test(usuarioId)) return { id: null, error: null };

  const ativoNaEmpresa = await usuarioAtivoNaEmpresa(admin, opts.empresaId, usuarioId);
  return ativoNaEmpresa ? { id: usuarioId, error: null } : { id: null, error: null };
}

export async function resolveCondicaoPagamento(opts: {
  tenantId: string;
  empresaId: string;
  condicaoPagamentoId?: string | null;
  onlyActive?: boolean;
}): Promise<{ row: CondicaoPagamentoLookupRow | null; error: string | null }> {
  const condicaoPagamentoId = String(opts.condicaoPagamentoId ?? "").trim();
  if (!condicaoPagamentoId) return { row: null, error: null };
  if (!UUID_RE.test(condicaoPagamentoId)) return { row: null, error: "Condicao de pagamento invalida." };

  const admin = supabaseAdmin();
  let q = admin
    .schema("c")
    .from("condicao_pagamento")
    .select("id,nome,codigo")
    .eq("id", condicaoPagamentoId)
    .eq("tenant_id", opts.tenantId)
    .eq("empresa_id", opts.empresaId)
    .is("deleted_at", null);

  if (opts.onlyActive !== false) q = q.eq("ativo", true);

  const { data, error } = await q.maybeSingle<CondicaoPagamentoLookupRow>();
  if (error) throw error;
  if (!data?.id) return { row: null, error: "Condicao de pagamento invalida para esta empresa." };
  return { row: data, error: null };
}

function roundMoney(value: number) {
  if (!Number.isFinite(value)) return 0;
  return Math.round(value * 100) / 100;
}

async function loadItemExact(
  supabase: AuthedSupabase,
  tenantId: string,
  empresaId: string,
  field: "codigo_interno" | "id",
  value: string | number
) {
  const { data, error } = await supabase
    .from("itens")
    .select("id,codigo_interno,nome,descricao,unidade_medida,preco_unitario,fornecedor_id")
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .eq(field, value)
    .limit(1)
    .maybeSingle();

  if (error) return { error: error.message } as const;
  return { data: (data as ResolvedItemRow | null) ?? null } as const;
}

function itemResolveLabel(item: ResolvedItemRow) {
  const nome = String(item.nome ?? item.descricao ?? "").trim();
  return nome || String(item.codigo_interno ?? "").trim() || `ID ${item.id}`;
}

export async function resolveItemByCodigoOuId(
  supabase: AuthedSupabase,
  opts: {
    tenantId: string;
    empresaId: string;
    codigo: string;
    fornecedorId?: number | null;
  }
): Promise<ResolveItemByCodigoOuIdResult> {
  const codigo = String(opts.codigo ?? "").trim();
  if (!codigo) return { error: "codigo obrigatorio.", status: 400 } as const;

  const byCodigoRes = await loadItemExact(supabase, opts.tenantId, opts.empresaId, "codigo_interno", codigo);
  if ("error" in byCodigoRes && byCodigoRes.error) return { error: byCodigoRes.error, status: 400 } as const;

  let byId: ResolvedItemRow | null = null;
  const codigoAsId = Number(codigo);
  if (Number.isFinite(codigoAsId) && codigoAsId > 0) {
    const byIdRes = await loadItemExact(supabase, opts.tenantId, opts.empresaId, "id", codigoAsId);
    if ("error" in byIdRes && byIdRes.error) return { error: byIdRes.error, status: 400 } as const;
    byId = byIdRes.data ?? null;
  }

  const byCodigo = byCodigoRes.data ?? null;
  if (byCodigo && byId && Number(byCodigo.id) !== Number(byId.id)) {
    const fornecedorId = Number(opts.fornecedorId ?? 0);
    if (Number.isFinite(fornecedorId) && fornecedorId > 0) {
      const codigoMatchesFornecedor = Number(byCodigo.fornecedor_id ?? 0) === fornecedorId;
      const idMatchesFornecedor = Number(byId.fornecedor_id ?? 0) === fornecedorId;
      if (codigoMatchesFornecedor !== idMatchesFornecedor) {
        return {
          data: codigoMatchesFornecedor ? byCodigo : byId,
          matchedBy: codigoMatchesFornecedor ? "codigo" : "id",
        } as const;
      }
    }

    return {
      error:
        `Codigo ambiguo: ${codigo} corresponde ao codigo interno do item ${byCodigo.id} (${itemResolveLabel(byCodigo)}) ` +
        `e ao ID do item ${byId.id} (${itemResolveLabel(byId)}). Use a busca pelo item ou informe o codigo interno completo.`,
      status: 409,
    } as const;
  }

  if (byCodigo) return { data: byCodigo, matchedBy: "codigo" } as const;
  if (byId) return { data: byId, matchedBy: "id" } as const;
  return { error: `Codigo de item nao encontrado: ${codigo}`, status: 404 } as const;
}

export function calcPedidoItemValorTotal(
  quantidade: number,
  valorUnitario: number,
  valorIpiUnitario = 0,
  destacarIpi = false
) {
  const unitarioComIpi =
    (Number.isFinite(valorUnitario) ? valorUnitario : 0) +
    (destacarIpi && Number.isFinite(valorIpiUnitario) ? valorIpiUnitario : 0);
  return roundMoney((Number.isFinite(quantidade) ? quantidade : 0) * unitarioComIpi);
}

export async function syncPedidoTotais(
  supabase: AuthedSupabase,
  pedidoId: string,
  tenantId: string,
  empresaId: string
): Promise<SyncPedidoTotaisResult> {
  const { data: pedido, error: pedidoErr } = await supabase
    .schema("m")
    .from("pedido_compra")
    .select("id,total_frete,total_desconto")
    .eq("id", pedidoId)
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .is("deleted_at", null)
    .single();
  if (pedidoErr || !pedido) {
    return { error: pedidoErr?.message ?? "Pedido nao encontrado para recalculo." } as const;
  }

  const { data: itens, error: itensErr } = await supabase
    .schema("m")
    .from("pedido_compra_item")
    .select("valor_total,valor_ipi_total")
    .eq("pedido_compra_id", pedidoId)
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .is("deleted_at", null);
  if (itensErr) return { error: itensErr.message } as const;

  const totalItens = roundMoney(
    (Array.isArray(itens) ? itens : []).reduce((acc, row) => acc + Number((row as Record<string, unknown>).valor_total ?? 0), 0)
  );
  const totalIpi = roundMoney(
    (Array.isArray(itens) ? itens : []).reduce(
      (acc, row) => acc + Number((row as Record<string, unknown>).valor_ipi_total ?? 0),
      0
    )
  );
  const totalFrete = roundMoney(Number((pedido as Record<string, unknown>).total_frete ?? 0));
  const totalDesconto = roundMoney(Number((pedido as Record<string, unknown>).total_desconto ?? 0));
  const totalGeral = roundMoney(totalItens + totalFrete - totalDesconto);

  const { error: updErr } = await supabase
    .schema("m")
    .from("pedido_compra")
    .update({
      total_itens: totalItens,
      total_ipi: totalIpi,
      total_geral: totalGeral,
      updated_by: null,
    })
    .eq("id", pedidoId)
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .is("deleted_at", null);
  if (updErr) return { error: updErr.message } as const;

  return { data: { totalItens, totalIpi, totalGeral } } as const;
}
