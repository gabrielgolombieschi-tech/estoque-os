import { NextRequest } from "next/server";
import { getAuthSupabase, jsonError } from "@/app/api/compras/_lib";
import { supabaseAdmin } from "@/lib/supabase/admin";

export const runtime = "nodejs";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const APPS_SCRIPT_TIMEOUT_MS = 20000;
const MAX_ERROR_LENGTH = 1500;
const NOT_CONFIGURED_ERROR = "Integra\u00e7\u00e3o Google Apps Script n\u00e3o configurada";
const ORCAMENTO_WRITE_EMPRESA_ROLES = new Set(["ADMIN", "FINANCEIRO", "COORDENACAO", "ALMOXARIFADO", "APONTAMENTO_RH", "FATURAMENTO"]);

type AuthResult = Awaited<ReturnType<typeof getAuthSupabase>>;
type AuthedSupabase = Extract<AuthResult, { supabase: unknown }>["supabase"];
type AdminClient = ReturnType<typeof supabaseAdmin>;

type OrcamentoDriveRow = {
  id: string;
  tenant_id: string;
  empresa_id: string;
  codigo: string | null;
  titulo: string | null;
  cliente_id: number | null;
  condicao_pagamento_id: string | null;
  solicitante_nome: string | null;
  solicitante_setor: string | null;
  solicitante_email: string | null;
  solicitante_telefone: string | null;
};

type ClienteRow = {
  id: number;
  nome: string | null;
};

type CondicaoPagamentoRow = {
  id: string;
  nome: string | null;
  codigo: string | null;
};

type EmpresaAccessRow = {
  id: string;
};

type UsuarioRow = {
  id: string;
  nome: string | null;
  email: string | null;
};

type UsuarioIdRow = {
  id: string;
};

type UsuarioTenantAccessRow = {
  papel: string | null;
};

type UsuarioEmpresaRow = {
  papel: string | null;
};

type UsuarioPayload = {
  nome: string | null;
  email: string | null;
  funcao: string | null;
};

type AppsScriptPayload = {
  token: string;
  orcamento_id: string;
  codigo: string | null;
  cliente: string | null;
  processo: string | null;
  pagamento: string | null;
  solicitante: string | null;
  setor: string | null;
  email: string | null;
  telefone: string | null;
  usuario_nome: string | null;
  usuario_email: string | null;
  usuario_funcao: string | null;
};

type AppsScriptResponse = {
  ok?: boolean | string;
  success?: boolean | string;
  status?: string;
  result?: string;
  error?: string;
  message?: string;
  mensagem?: string;
  folderId?: string;
  folder_id?: string;
  folderUrl?: string;
  folder_url?: string;
  docId?: string;
  doc_id?: string;
  documentId?: string;
  document_id?: string;
  docUrl?: string;
  doc_url?: string;
  documentUrl?: string;
  document_url?: string;
};

type TenantEmpresaContext = {
  tenantId: string;
  empresaId: string;
};

function trimToNull(value: unknown): string | null {
  const trimmed = String(value ?? "").trim();
  return trimmed ? trimmed : null;
}

function truncateError(value: unknown): string {
  const message =
    value instanceof Error
      ? value.message
      : typeof value === "object" && value !== null && "message" in value
        ? String((value as { message?: unknown }).message ?? "Erro desconhecido")
        : String(value ?? "Erro desconhecido");
  return message.slice(0, MAX_ERROR_LENGTH);
}

function appsScriptSuccess(value: AppsScriptResponse): boolean {
  const status = String(value.status ?? "").trim().toLowerCase();
  const result = String(value.result ?? "").trim().toLowerCase();
  const ok = String(value.ok ?? "").trim().toLowerCase();
  const success = String(value.success ?? "").trim().toLowerCase();
  const successValues = new Set(["true", "success", "created", "ok", "sucesso"]);
  return successValues.has(ok) || successValues.has(success) || successValues.has(status) || successValues.has(result);
}

function appsScriptError(value: AppsScriptResponse | null, fallback: string): string {
  return trimToNull(value?.error) ?? trimToNull(value?.message) ?? trimToNull(value?.mensagem) ?? fallback;
}

function pickResponseText(value: AppsScriptResponse, keys: Array<keyof AppsScriptResponse>): string | null {
  for (const key of keys) {
    const picked = trimToNull(value[key]);
    if (picked) return picked;
  }
  return null;
}

function readTenantEmpresaHint(body: Record<string, unknown>, query: URLSearchParams): TenantEmpresaContext | null {
  const tenantId = trimToNull(body.tenant_id) ?? trimToNull(body.tenantId) ?? trimToNull(query.get("tenant_id")) ?? trimToNull(query.get("tenantId"));
  const empresaId =
    trimToNull(body.empresa_id) ?? trimToNull(body.empresaId) ?? trimToNull(query.get("empresa_id")) ?? trimToNull(query.get("empresaId"));

  if (!tenantId || !empresaId || !UUID_RE.test(tenantId) || !UUID_RE.test(empresaId)) return null;
  return { tenantId, empresaId };
}

function normalizeRole(value: unknown): string {
  return String(value ?? "").trim().toUpperCase();
}

async function canWriteOrcamento(
  admin: AdminClient,
  supabase: AuthedSupabase,
  params: { authUserId: string; tenantId: string; empresaId: string }
): Promise<boolean> {
  await Promise.allSettled([
    supabase.rpc("set_current_tenant", { p_tenant_id: params.tenantId }),
    supabase.rpc("set_current_empresa", { p_empresa_id: params.empresaId }),
  ]);

  const { data: hasActiveEmpresaAccess, error: activeEmpresaAccessErr } = await supabase.rpc(
    "has_active_empresa_access",
    {
      p_tenant_id: params.tenantId,
      p_empresa_id: params.empresaId,
    }
  );
  if (activeEmpresaAccessErr || !hasActiveEmpresaAccess) return false;

  const checks = await Promise.allSettled([
    supabase.rpc("can", { p_resource: "financeiro", p_action: "write", p_tenant_id: params.tenantId }),
    supabase.rpc("can", { p_resource: "os", p_action: "write", p_tenant_id: params.tenantId }),
  ]);
  if (checks.some((result) => result.status === "fulfilled" && Boolean(result.value.data))) return true;

  const { data: usuario, error: usuarioErr } = await admin
    .schema("a")
    .from("usuario")
    .select("id")
    .eq("auth_user_id", params.authUserId)
    .eq("ativo", true)
    .is("deleted_at", null)
    .limit(1)
    .maybeSingle<UsuarioIdRow>();
  if (usuarioErr) throw usuarioErr;

  const usuarioId = trimToNull(usuario?.id);
  if (!usuarioId) return false;

  const { data: empresa, error: empresaErr } = await admin
    .schema("c")
    .from("empresa")
    .select("id")
    .eq("id", params.empresaId)
    .eq("tenant_id", params.tenantId)
    .eq("ativo", true)
    .is("deleted_at", null)
    .limit(1)
    .maybeSingle<EmpresaAccessRow>();
  if (empresaErr) throw empresaErr;
  if (!empresa?.id) return false;

  const [tenantAccess, empresaAccess] = await Promise.all([
    admin
      .schema("a")
      .from("usuario_tenant")
      .select("papel")
      .eq("usuario_id", usuarioId)
      .eq("tenant_id", params.tenantId)
      .eq("ativo", true)
      .is("deleted_at", null)
      .limit(1)
      .maybeSingle<UsuarioTenantAccessRow>(),
    admin
      .schema("a")
      .from("usuario_empresa")
      .select("papel")
      .eq("usuario_id", usuarioId)
      .eq("empresa_id", params.empresaId)
      .eq("ativo", true)
      .is("deleted_at", null)
      .limit(1)
      .maybeSingle<UsuarioEmpresaRow>(),
  ]);

  if (tenantAccess.error) throw tenantAccess.error;
  if (empresaAccess.error) throw empresaAccess.error;

  const empresaRole = normalizeRole(empresaAccess.data?.papel);
  if (!empresaRole) return false;

  const tenantRole = normalizeRole(tenantAccess.data?.papel);
  if (tenantRole === "OWNER" || tenantRole === "ADMIN" || tenantRole === "DIRETOR") return true;

  return ORCAMENTO_WRITE_EMPRESA_ROLES.has(empresaRole);
}

async function loadOrcamento(
  admin: AdminClient,
  params: { tenantId: string; empresaId: string; idOrCodigo: string }
): Promise<OrcamentoDriveRow | null> {
  const raw = params.idOrCodigo.trim();
  if (!raw) return null;

  let query = admin
    .schema("m")
    .from("orcamento")
    .select(
      [
        "id",
        "tenant_id",
        "empresa_id",
        "codigo",
        "titulo",
        "cliente_id",
        "condicao_pagamento_id",
        "solicitante_nome",
        "solicitante_setor",
        "solicitante_email",
        "solicitante_telefone",
      ].join(",")
    )
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId)
    .is("deleted_at", null)
    .limit(1);

  query = UUID_RE.test(raw) ? query.eq("id", raw) : query.eq("codigo", raw);

  const { data, error } = await query.maybeSingle<OrcamentoDriveRow>();
  if (error) throw error;
  return data?.id ? data : null;
}

async function loadClienteNome(
  admin: AdminClient,
  params: { tenantId: string; empresaId: string; clienteId: number | null }
): Promise<string | null> {
  const clienteId = Number(params.clienteId ?? null);
  if (!Number.isInteger(clienteId) || clienteId <= 0) return null;

  const { data, error } = await admin
    .from("clientes")
    .select("id,nome")
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId)
    .eq("id", clienteId)
    .maybeSingle<ClienteRow>();

  if (error) throw error;
  return trimToNull(data?.nome);
}

async function loadPagamentoNome(
  admin: AdminClient,
  params: { tenantId: string; empresaId: string; condicaoPagamentoId: string | null }
): Promise<string | null> {
  const condicaoPagamentoId = trimToNull(params.condicaoPagamentoId);
  if (!condicaoPagamentoId) return null;

  const { data, error } = await admin
    .schema("c")
    .from("condicao_pagamento")
    .select("id,nome,codigo")
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId)
    .eq("id", condicaoPagamentoId)
    .is("deleted_at", null)
    .maybeSingle<CondicaoPagamentoRow>();

  if (error) throw error;
  return trimToNull(data?.nome) ?? trimToNull(data?.codigo);
}

async function loadUsuarioPayload(
  admin: AdminClient,
  params: { authUserId: string; authEmail: string | null; empresaId: string }
): Promise<UsuarioPayload> {
  const authUserId = trimToNull(params.authUserId);
  if (!authUserId) {
    return { nome: null, email: trimToNull(params.authEmail), funcao: null };
  }

  const { data: usuario, error: usuarioErr } = await admin
    .schema("a")
    .from("usuario")
    .select("id,nome,email")
    .eq("auth_user_id", authUserId)
    .eq("ativo", true)
    .is("deleted_at", null)
    .maybeSingle<UsuarioRow>();

  if (usuarioErr) throw usuarioErr;

  const usuarioId = trimToNull(usuario?.id);
  let funcao: string | null = null;
  if (usuarioId) {
    const { data: usuarioEmpresa, error: usuarioEmpresaErr } = await admin
      .schema("a")
      .from("usuario_empresa")
      .select("papel")
      .eq("usuario_id", usuarioId)
      .eq("empresa_id", params.empresaId)
      .eq("ativo", true)
      .is("deleted_at", null)
      .maybeSingle<UsuarioEmpresaRow>();

    if (usuarioEmpresaErr) throw usuarioEmpresaErr;
    funcao = trimToNull(usuarioEmpresa?.papel);
  }

  const email = trimToNull(usuario?.email) ?? trimToNull(params.authEmail);
  return {
    nome: trimToNull(usuario?.nome) ?? email,
    email,
    funcao,
  };
}

async function updateDriveSuccess(
  admin: AdminClient,
  params: { orcamento: OrcamentoDriveRow; requestedAt: string; response: AppsScriptResponse }
): Promise<void> {
  const syncedAt = new Date().toISOString();
  const { error } = await admin
    .schema("m")
    .from("orcamento")
    .update({
      drive_folder_id: pickResponseText(params.response, ["folderId", "folder_id"]),
      drive_folder_url: pickResponseText(params.response, ["folderUrl", "folder_url"]),
      drive_doc_id: pickResponseText(params.response, ["docId", "doc_id", "documentId", "document_id"]),
      drive_doc_url: pickResponseText(params.response, ["docUrl", "doc_url", "documentUrl", "document_url"]),
      drive_sync_status: "created",
      drive_sync_error: null,
      drive_sync_requested_at: params.requestedAt,
      drive_synced_at: syncedAt,
    })
    .eq("id", params.orcamento.id)
    .eq("tenant_id", params.orcamento.tenant_id)
    .eq("empresa_id", params.orcamento.empresa_id);

  if (error) throw error;
}

async function updateDriveError(
  admin: AdminClient,
  params: { orcamento: OrcamentoDriveRow; requestedAt: string; message: string }
): Promise<void> {
  const { error } = await admin
    .schema("m")
    .from("orcamento")
    .update({
      drive_sync_status: "error",
      drive_sync_error: truncateError(params.message),
      drive_sync_requested_at: params.requestedAt,
      drive_synced_at: null,
    })
    .eq("id", params.orcamento.id)
    .eq("tenant_id", params.orcamento.tenant_id)
    .eq("empresa_id", params.orcamento.empresa_id);

  if (error) throw error;
}

async function postAppsScript(url: string, payload: AppsScriptPayload): Promise<AppsScriptResponse> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), APPS_SCRIPT_TIMEOUT_MS);

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });

    const bodyText = await response.text();
    let body: AppsScriptResponse | null = null;
    if (bodyText.trim()) {
      try {
        body = JSON.parse(bodyText) as AppsScriptResponse;
      } catch {
        body = null;
      }
    }

    if (!response.ok) {
      const detail = body ? appsScriptError(body, bodyText) : bodyText;
      throw new Error(`Apps Script HTTP ${response.status}: ${truncateError(detail)}`);
    }

    if (!body || !appsScriptSuccess(body)) {
      throw new Error(appsScriptError(body, "Apps Script retornou resposta sem sucesso."));
    }

    return body;
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      throw new Error("Timeout ao chamar Google Apps Script.");
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

export async function POST(req: NextRequest, context: { params: Promise<{ id?: string }> }) {
  try {
    const auth = await getAuthSupabase(req);
    if ("error" in auth) return auth.error;
    const { supabase, user } = auth;

    const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const ctx = readTenantEmpresaHint(body, req.nextUrl.searchParams);
    if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");

    const { id: rawId = "" } = await context.params;
    const idOrCodigo = decodeURIComponent(String(rawId ?? "")).trim();
    if (!idOrCodigo) return jsonError(400, "Orcamento invalido.");

    const requestedAt = new Date().toISOString();
    const admin = supabaseAdmin();
    if (!(await canWriteOrcamento(admin, supabase, { authUserId: user.id, tenantId: ctx.tenantId, empresaId: ctx.empresaId }))) {
      return jsonError(403, "Sem permissao para sincronizar orcamento.");
    }

    const orcamento = await loadOrcamento(admin, { tenantId: ctx.tenantId, empresaId: ctx.empresaId, idOrCodigo });
    if (!orcamento) return jsonError(404, "Orcamento nao encontrado.");

    const scriptUrl = trimToNull(process.env.GOOGLE_APPS_SCRIPT_ORCAMENTOS_URL);
    const scriptToken = trimToNull(process.env.GOOGLE_APPS_SCRIPT_ORCAMENTOS_TOKEN);
    if (!scriptUrl || !scriptToken) {
      await updateDriveError(admin, { orcamento, requestedAt, message: NOT_CONFIGURED_ERROR });
      console.warn("Integracao Google Apps Script nao configurada.");
      return Response.json({ ok: false, error: NOT_CONFIGURED_ERROR });
    }

    const codigo = trimToNull(orcamento.codigo);
    if (!codigo) {
      const message = "Codigo do orcamento nao encontrado para sincronizar com Drive.";
      await updateDriveError(admin, { orcamento, requestedAt, message });
      console.warn(message);
      return Response.json({ ok: false, error: message });
    }

    const [cliente, pagamento, usuario] = await Promise.all([
      loadClienteNome(admin, { tenantId: ctx.tenantId, empresaId: ctx.empresaId, clienteId: orcamento.cliente_id }),
      loadPagamentoNome(admin, {
        tenantId: ctx.tenantId,
        empresaId: ctx.empresaId,
        condicaoPagamentoId: orcamento.condicao_pagamento_id,
      }),
      loadUsuarioPayload(admin, { authUserId: user.id, authEmail: user.email ?? null, empresaId: ctx.empresaId }),
    ]);

    const payload: AppsScriptPayload = {
      token: scriptToken,
      orcamento_id: orcamento.id,
      codigo,
      cliente,
      processo: trimToNull(orcamento.titulo),
      pagamento,
      solicitante: trimToNull(orcamento.solicitante_nome),
      setor: trimToNull(orcamento.solicitante_setor),
      email: trimToNull(orcamento.solicitante_email),
      telefone: trimToNull(orcamento.solicitante_telefone),
      usuario_nome: usuario.nome,
      usuario_email: usuario.email,
      usuario_funcao: usuario.funcao,
    };

    try {
      const response = await postAppsScript(scriptUrl, payload);
      await updateDriveSuccess(admin, { orcamento, requestedAt, response });
      return Response.json({
        ok: true,
        folderId: pickResponseText(response, ["folderId", "folder_id"]),
        folderUrl: pickResponseText(response, ["folderUrl", "folder_url"]),
        docId: pickResponseText(response, ["docId", "doc_id", "documentId", "document_id"]),
        docUrl: pickResponseText(response, ["docUrl", "doc_url", "documentUrl", "document_url"]),
      });
    } catch (error) {
      const message = truncateError(error);
      await updateDriveError(admin, { orcamento, requestedAt, message });
      console.warn("Falha ao sincronizar orcamento com Drive via Apps Script.", error);
      return Response.json({ ok: false, error: message });
    }
  } catch (error) {
    const message = truncateError(error);
    console.warn("Erro inesperado na sincronizacao do orcamento com Drive.", error);
    return jsonError(500, message);
  }
}
