import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveTenantEmpresa } from "../_lib";
import { getAllowedEmpresas } from "@/lib/auth/empresa";
import { supabaseAdmin } from "@/lib/supabase/admin";

export const runtime = "nodejs";

const OS_LOOKUP_ALLOWED_ROLES = new Set([
  "ADMIN",
  "FINANCEIRO",
  "FATURAMENTO",
  "COORDENACAO",
  "COMPRAS",
  "ALMOXARIFADO",
  "APONTAMENTO_RH",
]);

type DbClient = ReturnType<typeof supabaseAdmin>;

type OsLookupRow = {
  id: number;
  numero_os: string | number | null;
  os_num: number | null;
  cliente_nome: string | null;
  descricao_servico: string | null;
  status: string | null;
};

function normalizeTerm(value: string | null): string {
  return String(value ?? "").trim();
}

function mergeRows(groups: OsLookupRow[][]): OsLookupRow[] {
  const seen = new Set<number>();
  const out: OsLookupRow[] = [];

  for (const rows of groups) {
    for (const row of rows) {
      const id = Number(row.id);
      if (!Number.isFinite(id) || seen.has(id)) continue;
      seen.add(id);
      out.push(row);
    }
  }

  return out.sort((a, b) => Number(b.id) - Number(a.id)).slice(0, 50);
}

async function searchTextColumn(
  db: DbClient,
  column: "numero_os" | "cliente_nome" | "descricao_servico",
  ctx: { tenantId: string; empresaId: string },
  term: string
) {
  const { data, error } = await db
    .from("ordens_servico")
    .select("id,numero_os,os_num,cliente_nome,descricao_servico,status")
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .ilike(column, `%${term}%`)
    .order("id", { ascending: false })
    .limit(50);

  if (error) throw error;
  return (data ?? []) as OsLookupRow[];
}

async function searchNumberColumn(db: DbClient, column: "id" | "os_num", ctx: { tenantId: string; empresaId: string }, value: number) {
  const { data, error } = await db
    .from("ordens_servico")
    .select("id,numero_os,os_num,cliente_nome,descricao_servico,status")
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .eq(column, value)
    .order("id", { ascending: false })
    .limit(50);

  if (error) throw error;
  return (data ?? []) as OsLookupRow[];
}

export async function GET(req: NextRequest) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;

  const ctx = await resolveTenantEmpresa(supabase, null, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");

  const canReadCompras = await canCompras(supabase, "read");
  const canWriteCompras = await canCompras(supabase, "write");
  let canLookupByRole = false;
  if (!canReadCompras && !canWriteCompras) {
    try {
      const allowed = await getAllowedEmpresas(supabase, ctx.tenantId);
      const empresa = allowed.find((e) => String(e.id) === ctx.empresaId);
      const role = String(empresa?.papel ?? "").trim().toUpperCase();
      canLookupByRole = OS_LOOKUP_ALLOWED_ROLES.has(role);
    } catch {
      canLookupByRole = false;
    }
  }

  if (!canReadCompras && !canWriteCompras && !canLookupByRole) {
    return jsonError(403, "Sem permissao (compras.read).");
  }

  const term = normalizeTerm(req.nextUrl.searchParams.get("q"));
  const db = canReadCompras || canWriteCompras ? supabase : supabaseAdmin();

  try {
    if (!term) {
      const { data, error } = await db
        .from("ordens_servico")
        .select("id,numero_os,os_num,cliente_nome,descricao_servico,status")
        .eq("tenant_id", ctx.tenantId)
        .eq("empresa_id", ctx.empresaId)
        .order("id", { ascending: false })
        .limit(50);

      if (error) throw error;
      return Response.json({ data: data ?? [] });
    }

    const numericTerm = /^\d+$/.test(term) ? Number(term) : null;
    const groups = await Promise.all([
      searchTextColumn(db, "numero_os", ctx, term),
      searchTextColumn(db, "cliente_nome", ctx, term),
      searchTextColumn(db, "descricao_servico", ctx, term),
      numericTerm && Number.isFinite(numericTerm) ? searchNumberColumn(db, "id", ctx, numericTerm) : Promise.resolve([]),
      numericTerm && Number.isFinite(numericTerm) ? searchNumberColumn(db, "os_num", ctx, numericTerm) : Promise.resolve([]),
    ]);

    return Response.json({ data: mergeRows(groups) });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Erro ao buscar OS.";
    return jsonError(400, message);
  }
}
