import { NextRequest, NextResponse } from "next/server";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";

function jerr(status: number, error: string) {
  return NextResponse.json({ error }, { status });
}

export const runtime = "nodejs";
const isDev = process.env.NODE_ENV !== "production";

type Origem = "XML_PRODUTO";
type AplicaEm = "PRODUTO" | "SERVICO" | "AMBOS";

type MotivoRow = {
  id: string;
  codigo: string | null;
  nome: string | null;
  requires_text: boolean | null;
  requires_os: boolean | null;
  aplica_em: AplicaEm | null;
  ativo: boolean | null;
  deleted_at: string | null;
};

export async function GET(req: NextRequest) {
  try {
    const authorization = req.headers.get("authorization");
    if (!authorization) return jerr(401, "Nao autenticado.");

    const supabase = supabaseFromAuthHeader(req);
    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData.user) return jerr(401, "Nao autenticado.");

    const origem = String(req.nextUrl.searchParams.get("origem") ?? "").trim().toUpperCase() as Origem | "";

    // Always resolve tenant from DB-side context (no tenantId in URL).
    let tenantId: string | null = null;
    try {
      const { data: t, error: tErr } = await supabase.rpc("current_tenant_id");
      if (tErr) return jerr(400, tErr.message ?? "Falha ao resolver tenant.");
      tenantId = t ? String(t) : null;
    } catch {
      tenantId = null;
    }
    if (!tenantId) return jerr(400, "Tenant nao carregado.");

    // Read using the authenticated user + RLS (roles are enforced in DB policy).
    let q = supabase
      .schema("f")
      .from("motivo_compra")
      .select("id,codigo,nome,requires_text,requires_os,aplica_em,ativo,deleted_at")
      .eq("tenant_id", tenantId)
      .eq("ativo", true)
      .is("deleted_at", null)
      .order("codigo", { ascending: true });

    if (origem === "XML_PRODUTO") {
      q = q.in("aplica_em", ["PRODUTO", "AMBOS"]);
    }

    const { data, error } = await q.returns<MotivoRow[]>();

    if (error) {
      const msg = String(error.message ?? "");
      if (msg.toLowerCase().includes("permission denied")) {
        return jerr(403, msg);
      }
      return jerr(400, msg || "Erro ao carregar motivos.");
    }

    if (isDev) {
      let curEmpresa: string | null = null;
      try {
        const { data: e } = await supabase.rpc("current_empresa_id");
        curEmpresa = e ? String(e) : null;
      } catch {
        curEmpresa = null;
      }
      const count = Array.isArray(data) ? data.length : 0;
      const preview = Array.isArray(data)
        ? data.slice(0, 3).map((r) => ({ id: r.id, codigo: r.codigo, nome: r.nome, aplica_em: r.aplica_em }))
        : [];
      console.log("[motivos-compra] loaded", { tenantId, curEmpresa, origem: origem || null, count, preview });
    }

    const motivos = (data ?? [])
      .map((r) => ({
        id: String(r.id),
        codigo: String(r.codigo ?? ""),
        nome: String(r.nome ?? ""),
        requires_text: Boolean(r.requires_text),
        requires_os: Boolean(r.requires_os),
        aplica_em: (r.aplica_em ? String(r.aplica_em) : "AMBOS") as AplicaEm,
      }))
      .filter((m) => m.id && m.codigo && m.nome);

    return NextResponse.json({ motivos });
  } catch (e: unknown) {
    const message = e instanceof Error ? e.message : "Erro inesperado.";
    return jerr(500, message);
  }
}
