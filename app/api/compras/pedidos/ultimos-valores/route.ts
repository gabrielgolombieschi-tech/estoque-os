import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveTenantEmpresa } from "../../_lib";

export const runtime = "nodejs";

type ReqRow = {
  pendencia_id: string;
  item_id?: number | null;
  item_nome?: string | null;
  unidade?: string | null;
};

function normText(v: unknown) {
  return String(v ?? "").trim().toUpperCase();
}

function parseItemId(v: unknown): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  if (!Number.isFinite(n) || n <= 0) return null;
  return n;
}

function isMissingItensDeletedAt(err: unknown) {
  const msg = String((err as { message?: string } | null)?.message ?? err ?? "").toLowerCase();
  return msg.includes("itens.deleted_at") && msg.includes("does not exist");
}

export async function POST(req: NextRequest) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;

  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const ctx = await resolveTenantEmpresa(supabase, body, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");
  if (!(await canCompras(supabase, "read"))) return jsonError(403, "Sem permissao (compras.read).");

  const fornecedorId = Number(body.fornecedorId ?? body.fornecedor_id ?? 0);
  if (!Number.isFinite(fornecedorId) || fornecedorId <= 0) return jsonError(400, "fornecedorId invalido.");

  const rows = (Array.isArray(body.rows) ? body.rows : []) as ReqRow[];
  if (!rows.length) return Response.json({ data: {} });

  const pedidoRank = new Map<string, number>();
  type LastVal = { rank: number; valor: number };
  const byItemId = new Map<number, LastVal>();
  const byNomeUnid = new Map<string, LastVal>();

  const { data: pedidos, error: pedidosErr } = await supabase
    .schema("m")
    .from("pedido_compra")
    .select("id,created_at,status")
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .eq("fornecedor_id", fornecedorId)
    .is("deleted_at", null)
    .neq("status", "CANCELADO")
    .order("created_at", { ascending: false })
    .limit(300);
  if (pedidosErr && !isMissingItensDeletedAt(pedidosErr)) return jsonError(400, pedidosErr.message);

  const pedidoIds = (pedidos ?? []).map((p) => String((p as { id?: unknown }).id ?? "")).filter(Boolean);
  for (let i = 0; i < pedidoIds.length; i++) pedidoRank.set(pedidoIds[i], i);

  if (pedidoIds.length > 0) {
    const { data: itens, error: itensErr } = await supabase
      .schema("m")
      .from("pedido_compra_item")
      .select("pedido_compra_id,item_id,item_nome,unidade,valor_unitario,created_at")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .is("deleted_at", null)
      .in("pedido_compra_id", pedidoIds)
      .order("created_at", { ascending: false })
      .limit(5000);
    if (itensErr && !isMissingItensDeletedAt(itensErr)) return jsonError(400, itensErr.message);
    if (itensErr && isMissingItensDeletedAt(itensErr)) {
      // Ambiente com schema legado/policy inconsistente: ignora historico e segue fallback.
    }

    for (const it of ((itens ?? []) as Array<{
      pedido_compra_id?: unknown;
      item_id?: unknown;
      item_nome?: unknown;
      unidade?: unknown;
      valor_unitario?: unknown;
    }>)) {
      const pedidoId = String(it.pedido_compra_id ?? "");
      const rank = pedidoRank.get(pedidoId);
      if (rank == null) continue;
      const valor = Number(it.valor_unitario ?? 0);
      if (!Number.isFinite(valor) || valor < 0) continue;

      const itemIdNum = parseItemId(it.item_id);
      if (itemIdNum != null) {
        const cur = byItemId.get(itemIdNum);
        if (!cur || rank < cur.rank) byItemId.set(itemIdNum, { rank, valor });
      } else {
        const key = `${normText(it.item_nome)}|${normText(it.unidade || "UN")}`;
        if (!key || key === "|UN") continue;
        const cur = byNomeUnid.get(key);
        if (!cur || rank < cur.rank) byNomeUnid.set(key, { rank, valor });
      }
    }
  }

  const result: Record<string, number> = {};
  const unresolvedItemIds = new Set<number>();
  for (const r of rows) {
    const pendenciaId = String(r.pendencia_id ?? "").trim();
    if (!pendenciaId) continue;
    const itemIdNum = parseItemId(r.item_id);
    if (itemIdNum != null && byItemId.has(itemIdNum)) {
      result[pendenciaId] = byItemId.get(itemIdNum)!.valor;
      continue;
    }
    const key = `${normText(r.item_nome)}|${normText(r.unidade || "UN")}`;
    const byText = byNomeUnid.get(key);
    if (byText) {
      result[pendenciaId] = byText.valor;
      continue;
    }
    if (itemIdNum != null) unresolvedItemIds.add(itemIdNum);
  }

  // Fallback: usa preco_unitario cadastrado do item quando nao existe historico de compra.
  if (unresolvedItemIds.size > 0) {
    const ids = Array.from(unresolvedItemIds);
    const { data: itensCad, error: itensCadErr } = await supabase
      .from("itens")
      .select("id,preco_unitario,fornecedor_id")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .eq("fornecedor_id", fornecedorId)
      .in("id", ids);
    if (itensCadErr && !isMissingItensDeletedAt(itensCadErr)) return jsonError(400, itensCadErr.message);
    if (itensCadErr && isMissingItensDeletedAt(itensCadErr)) {
      return Response.json({ data: result });
    }

    const priceByItemId = new Map<number, number>();
    for (const it of (itensCad ?? []) as Array<{ id?: unknown; preco_unitario?: unknown }>) {
      const id = parseItemId(it.id);
      if (id == null) continue;
      const preco = Number(it.preco_unitario ?? 0);
      if (!Number.isFinite(preco) || preco < 0) continue;
      priceByItemId.set(id, preco);
    }

    for (const r of rows) {
      const pendenciaId = String(r.pendencia_id ?? "").trim();
      if (!pendenciaId || result[pendenciaId] != null) continue;
      const itemIdNum = parseItemId(r.item_id);
      if (itemIdNum == null) continue;
      const preco = priceByItemId.get(itemIdNum);
      if (preco != null) result[pendenciaId] = preco;
    }
  }

  return Response.json({ data: result });
}
