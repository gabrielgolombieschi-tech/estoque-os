import { NextRequest, NextResponse } from "next/server";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";

export const runtime = "nodejs";

function jerr(status: number, error: string) {
  return NextResponse.json({ error }, { status });
}

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function normalizeDigits(value: string | null | undefined): string {
  return String(value ?? "").replace(/\D/g, "");
}

function normalizeDocumento(value: string | null | undefined): string | null {
  const digits = normalizeDigits(value);
  if (digits.length === 14) return digits; // CNPJ
  return null;
}

function normalizeText(value: unknown, maxLen: number): string | null {
  const v = String(value ?? "")
    .replace(/\s+/g, " ")
    .trim()
    .toUpperCase();
  if (!v) return null;
  return v.slice(0, maxLen);
}

function isDuplicateKeyError(error: { message?: string; code?: string } | null | undefined): boolean {
  if (!error) return false;
  if (String(error.code ?? "") === "23505") return true;
  const msg = String(error.message ?? "").toLowerCase();
  return msg.includes("duplicate key") || msg.includes("violates unique constraint");
}

type Body = {
  tenantId?: string;
  empresaId?: string;
  documento?: string;
  nome?: string;
  razao_social?: string;
  nome_fantasia?: string;
  inscricao_estadual?: string;
  inscricao_municipal?: string;
  email?: string;
  telefone?: string;
  telefone2?: string;
  email_financeiro?: string;
  cep?: string;
  logradouro?: string;
  numero_endereco?: string;
  complemento?: string;
  bairro?: string;
  cidade?: string;
  uf?: string;
  pais?: string;
};

export async function POST(req: NextRequest) {
  try {
    const authorization = req.headers.get("authorization");
    if (!authorization) return jerr(401, "Não autenticado.");

    const supabase = supabaseFromAuthHeader(req);
    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData.user) return jerr(401, "Não autenticado.");

    const body = (await req.json()) as Body;

    const tenantHint = String(body.tenantId ?? "").trim();
    const empresaHint = String(body.empresaId ?? "").trim();

    // Best-effort: set DB context (some environments rely on current_* RPCs).
    if (tenantHint && UUID_REGEX.test(tenantHint)) {
      try {
        await supabase.rpc("set_current_tenant", { p_tenant_id: tenantHint });
      } catch {
        // ignore
      }
    }
    if (empresaHint && UUID_REGEX.test(empresaHint)) {
      try {
        await supabase.rpc("set_current_empresa", { p_empresa_id: empresaHint });
      } catch {
        // ignore
      }
    }

    const tenantId = tenantHint && UUID_REGEX.test(tenantHint) ? tenantHint : null;
    const empresaId = empresaHint && UUID_REGEX.test(empresaHint) ? empresaHint : null;
    if (!tenantId) return jerr(400, "tenantId é obrigatório.");
    if (!empresaId) return jerr(400, "empresaId é obrigatório.");

    // Allow either client write permission OR xml import permission (feature is tied to import).
    const [{ data: canClientes }, { data: canXml }, { data: canXmlFaturamento }] = await Promise.all([
      supabase.rpc("can", { p_resource: "cad_clientes", p_action: "write" }),
      supabase.rpc("can", { p_resource: "xml_import", p_action: "execute" }),
      supabase.rpc("can", { p_resource: "xml_import_faturamento", p_action: "execute" }),
    ]);

    if (!canClientes && !canXml && !canXmlFaturamento) {
      return jerr(403, "Sem permissão para cadastrar/atualizar clientes.");
    }

    const documento = normalizeDocumento(body.documento);
    if (!documento) return jerr(422, "Documento (CNPJ/CPF) inválido ou ausente no XML.");

    const nome = normalizeText(body.nome, 255) ?? normalizeText(body.razao_social, 255) ?? "CLIENTE";

    const payload: Record<string, unknown> = {
      tenant_id: tenantId,
      empresa_id: empresaId,
      nome,
      documento,
      email: normalizeText(body.email, 120),
      telefone: normalizeText(body.telefone, 30),
      razao_social: normalizeText(body.razao_social, 255),
      nome_fantasia: normalizeText(body.nome_fantasia, 255),
      inscricao_estadual: normalizeText(body.inscricao_estadual, 30),
      inscricao_municipal: normalizeText(body.inscricao_municipal, 30),
      cep: normalizeText(body.cep, 10),
      logradouro: normalizeText(body.logradouro, 255),
      numero_endereco: normalizeText(body.numero_endereco, 30),
      complemento: normalizeText(body.complemento, 120),
      bairro: normalizeText(body.bairro, 120),
      cidade: normalizeText(body.cidade, 120),
      uf: normalizeText(body.uf, 2),
      pais: normalizeText(body.pais, 60),
      telefone2: normalizeText(body.telefone2, 30),
      email_financeiro: normalizeText(body.email_financeiro, 120),
      atualizado_em: new Date().toISOString(),
      ativo: true,
    };

    const { data, error } = await supabase
      .from("clientes")
      .upsert(payload, {
        // Requires unique index (tenant_id, empresa_id, documento_norm)
        // where documento_norm is not null.
        onConflict: "tenant_id,empresa_id,documento_norm",
      })
      .select("id,nome,documento")
      .single();

    if (error) {
      // If the DB enforces a unique index but PostgREST didn't treat it as a conflict target,
      // we can still recover by selecting the existing row and updating it.
      if (isDuplicateKeyError(error)) {
        const { data: existing, error: qErr } = await supabase
          .from("clientes")
          .select("id")
          .eq("tenant_id", tenantId)
          .eq("empresa_id", empresaId)
          .eq("documento_norm", documento)
          .order("id", { ascending: true })
          .maybeSingle();

        if (qErr) return jerr(400, String(qErr.message ?? "Erro ao localizar cliente existente."));

        if (existing?.id) {
          const { data: upd, error: updErr } = await supabase
            .from("clientes")
            .update(payload)
            .eq("id", existing.id)
            .select("id,nome,documento")
            .single();

          if (updErr) return jerr(400, String(updErr.message ?? "Erro ao atualizar cliente existente."));
          return NextResponse.json({ ok: true, cliente_id: upd.id, cliente: upd, action: "updated" });
        }
      }

      // Fallback: if the unique index is not present yet, do a best-effort select+update/insert.
      const message = String(error.message ?? "");
      const isConflictTargetMissing = message.toLowerCase().includes("there is no unique or exclusion constraint") ||
        message.toLowerCase().includes("no unique constraint matching") ||
        message.toLowerCase().includes("on conflict");

      if (!isConflictTargetMissing) {
        return jerr(400, message || "Erro ao salvar cliente.");
      }

      const { data: existing, error: qErr } = await supabase
        .from("clientes")
        .select("id")
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId)
        .eq("documento_norm", documento)
        .maybeSingle();

      if (qErr) return jerr(400, String(qErr.message ?? "Erro ao localizar cliente."));

      if (existing?.id) {
        const { data: upd, error: updErr } = await supabase
          .from("clientes")
          .update(payload)
          .eq("id", existing.id)
          .select("id,nome,documento")
          .single();

        if (updErr) return jerr(400, String(updErr.message ?? "Erro ao atualizar cliente."));
        return NextResponse.json({ ok: true, cliente_id: upd.id, cliente: upd, action: "updated" });
      }

      const { data: ins, error: insErr } = await supabase
        .from("clientes")
        .insert(payload)
        .select("id,nome,documento")
        .single();

      if (insErr) return jerr(400, String(insErr.message ?? "Erro ao criar cliente."));
      return NextResponse.json({ ok: true, cliente_id: ins.id, cliente: ins, action: "created" });
    }

    return NextResponse.json({ ok: true, cliente_id: data.id, cliente: data, action: "upserted" });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Erro inesperado.";
    return jerr(500, message);
  }
}
