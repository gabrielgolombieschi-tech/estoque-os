import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase/admin";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";
import { getAllowedEmpresas } from "@/lib/auth/empresa";

export const runtime = "nodejs";

function jerr(status: number, error: string) {
  return NextResponse.json({ error }, { status });
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
    if (canErr || !canImport) return jerr(403, "Sem permissao para importar XML.");

    // Validate empresa membership
    const allowed = await getAllowedEmpresas(supabase, tenantId);
    if (!allowed.some((e) => e.id === empresaId)) return jerr(403, "Sem acesso a esta empresa.");

    // Motivo obrigatório
    const motivoCompraId = String(body.motivoCompraId ?? "").trim();
    if (!motivoCompraId) return jerr(422, "Classificacao/Motivo obrigatorio.");
    if (!UUID_REGEX.test(motivoCompraId)) return jerr(400, "Motivo invalido.");

    // Solicitante (usuario) obrigatório
    const solicitanteUsuarioId = String(body.solicitanteUsuarioId ?? "").trim();
    if (!solicitanteUsuarioId) return jerr(422, "Solicitante (usuario) obrigatorio.");
    if (!UUID_REGEX.test(solicitanteUsuarioId)) return jerr(400, "Solicitante (usuario) invalido.");

    const admin = supabaseAdmin();
    const currentUsuarioId = await getCurrentUsuarioId({ authUserId: userData.user.id });
    const aprovadoPorUsuarioId = currentUsuarioId ?? solicitanteUsuarioId;

    // Ensure motivo exists + active + not NAO_CLASSIFICADO
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

    const finalidade = body.finalidade ?? null;
    const osId = typeof body.osId === "number" ? body.osId : null;
    const gerar = Boolean(body.gerarContasPagar);

    // Call import RPC using the user's auth context
    const { data: importData, error: importErr } = await supabase.rpc("import_nf_entrada", {
      p_empresa_id: empresaId,
      p_fornecedor_id: resolved.fornecedorId,
      p_finalidade_contexto: finalidade,
      p_itens_json: body.itensJson ?? null,
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

    if (!nfEntradaId) return jerr(500, "Importacao nao retornou nf_entrada_id.");

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

    const { error: updTituloErr } = await admin
      .schema("f")
      .from("titulo")
      .update({ motivo_compra_id: motivoCompraId })
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .eq("id", tituloId);
    if (updTituloErr) {
      return jerr(422, `Falha ao atualizar classificação do título AP (${tituloId}). Detalhe: ${updTituloErr.message}`);
    }

    const { data: updatedRows, error: updErr } = await admin
      .schema("f")
      .from("titulo_aprovacao")
      .update({ motivo_compra_id: motivoCompraId, os_id: osId, deleted_at: null })
      .eq("tenant_id", tenantId)
      .eq("titulo_id", tituloId)
      .select("id")
      .returns<{ id: string }[]>();
    if (updErr) {
      return jerr(422, `Falha ao atualizar aprovação do título AP (${tituloId}). Detalhe: ${updErr.message}`);
    }

    if ((updatedRows?.length ?? 0) === 0) {
      const { error: insErr } = await admin.schema("f").from("titulo_aprovacao").insert({
        tenant_id: tenantId,
        titulo_id: tituloId,
        motivo_compra_id: motivoCompraId,
        os_id: osId,
        aprovado_por: aprovadoPorUsuarioId,
      });
      if (insErr) {
        return jerr(422, `Falha ao inserir aprovação do título AP (${tituloId}). Detalhe: ${insErr.message}`);
      }
    }

    return NextResponse.json({ status, message, nf_entrada_id: nfEntradaId });
  } catch (e: unknown) {
    const message = e instanceof Error ? e.message : "Erro inesperado.";
    return jerr(500, message);
  }
}
