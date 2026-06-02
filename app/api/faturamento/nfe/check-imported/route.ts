import { NextRequest, NextResponse } from "next/server";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";
import { applyTenantEmpresa } from "@/lib/db/scopes";

export const runtime = "nodejs";

function jerr(status: number, error: string, extra?: Record<string, unknown>) {
  return NextResponse.json({ error, ...(extra ?? {}) }, { status });
}

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function normalizeDigits(value: string | null | undefined): string {
  return String(value ?? "").replace(/\D/g, "");
}

type Body = {
  tenantId?: string;
  empresaId?: string;
  chave?: string;
};

export async function POST(req: NextRequest) {
  try {
    const authorization = req.headers.get("authorization");
    if (!authorization) return jerr(401, "Não autenticado.");

    const supabase = supabaseFromAuthHeader(req);
    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData.user) return jerr(401, "Não autenticado.");

    const body = (await req.json()) as Body;
    const tenantId = String(body.tenantId ?? "").trim();
    const empresaId = String(body.empresaId ?? "").trim();
    const chaveDigits = normalizeDigits(body.chave);

    if (!tenantId || !UUID_REGEX.test(tenantId)) return jerr(400, "tenantId inválido.");
    if (!empresaId || !UUID_REGEX.test(empresaId)) return jerr(400, "empresaId inválido.");
    if (!chaveDigits || chaveDigits.length !== 44) return jerr(422, "Chave de acesso inválida (esperado 44 dígitos).");

    // Best-effort set context (RLS filters by current_empresa_id in this project).
    try {
      await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
    } catch {
      // ignore
    }
    try {
      await supabase.rpc("set_current_empresa", { p_empresa_id: empresaId });
    } catch {
      // ignore
    }

    // Must have permission to import XML (same gate as import screen).
    const [{ data: canImport }, { data: canImportFaturamento }] = await Promise.all([
      supabase.rpc("can", { p_resource: "xml_import", p_action: "execute" }),
      supabase.rpc("can", { p_resource: "xml_import_faturamento", p_action: "execute" }),
    ]);
    if (!canImport && !canImportFaturamento) return jerr(403, "Sem permissão para importar XML.");

    const { data: existing } = await applyTenantEmpresa(
      supabase
        .schema("f")
        .from("documento_fiscal")
        .select("id")
        .eq("chave_acesso", chaveDigits)
        .is("deleted_at", null)
        .limit(1),
      tenantId,
      empresaId
    ).maybeSingle<{ id: string }>();

    if (existing?.id) {
      return NextResponse.json({ imported: true, documento_fiscal_id: String(existing.id), chave_acesso: chaveDigits });
    }

    return NextResponse.json({ imported: false, chave_acesso: chaveDigits });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Erro inesperado.";
    return jerr(500, message);
  }
}
