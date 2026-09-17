import { getAllowedEmpresas } from "@/lib/auth/empresa";
import { supabaseAdmin } from "@/lib/supabase/admin";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";

export const runtime = "nodejs";

/**
 * Anexos da importacao por remessa expressa (GNRE, nota de debito do courier, invoice, DIR).
 * O arquivo vai para o bucket privado nfe-documentos (so a service role escreve nele), no mesmo
 * caminho das notas: {tenant}/{empresa}/IMPORTACAO-{importacao}/{tipo}-{arquivo}. O registro
 * (f.importacao_remessa_anexo) e feito pela RPC com o token do usuario, que confere o acesso.
 *
 * POST multipart: importacao_id, tenant_id, empresa_id, tipo, arquivo.
 * GET ?anexo_id=...: URL assinada (10 minutos) para abrir o arquivo.
 */

const TIPOS = new Set(["DIR_XML", "GNRE", "NOTA_DEBITO", "INVOICE", "DANFE", "XML_NFE", "OUTRO"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TAMANHO_MAXIMO = 15 * 1024 * 1024;

function erro(status: number, mensagem: string) {
  return Response.json({ error: mensagem }, { status });
}

function nomeSeguro(nome: string) {
  const base = nome.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^A-Za-z0-9._-]+/g, "_").replace(/^_+|_+$/g, "");
  return (base || "arquivo").slice(0, 120);
}

async function usuarioDaSessao(request: Request) {
  const authorization = request.headers.get("authorization") ?? "";
  const token = authorization.match(/^Bearer\s+(.+)$/i)?.[1]?.trim() ?? "";
  if (!token) return { erro: erro(401, "Sessão ausente. Recarregue a página e tente novamente.") };
  const supabase = supabaseFromAuthHeader(request);
  const { data: authUserId, error: authError } = await supabase.rpc("current_auth_user_id");
  if (authError || !authUserId) return { erro: erro(401, "Sessão expirada ou recusada. Entre novamente e tente de novo.") };
  return { supabase, authUserId: String(authUserId) };
}

export async function POST(request: Request) {
  try {
    const sessao = await usuarioDaSessao(request);
    if ("erro" in sessao) return sessao.erro;
    const { supabase, authUserId } = sessao;

    const form = await request.formData();
    const arquivo = form.get("arquivo");
    const importacaoId = String(form.get("importacao_id") ?? "").trim();
    const tenantId = String(form.get("tenant_id") ?? "").trim();
    const empresaId = String(form.get("empresa_id") ?? "").trim();
    const tipo = String(form.get("tipo") ?? "").trim().toUpperCase();
    if (!(arquivo instanceof File) || !arquivo.size) return erro(400, "Selecione o arquivo.");
    if (arquivo.size > TAMANHO_MAXIMO) return erro(400, "Arquivo maior que 15 MB.");
    if (!UUID.test(importacaoId) || !UUID.test(tenantId) || !UUID.test(empresaId)) return erro(400, "Importação, tenant e empresa são obrigatórios.");
    if (!TIPOS.has(tipo)) return erro(400, "Tipo de anexo inválido.");

    const permitidas = await getAllowedEmpresas(supabase, tenantId, authUserId);
    if (!permitidas.some((empresa) => empresa.id === empresaId)) return erro(403, "Sem acesso à empresa.");

    // A importacao tem de ser da empresa (RLS de leitura ja limita ao tenant/empresa ativos).
    const { data: importacao, error: erroImportacao } = await supabase.schema("f").from("importacao_remessa")
      .select("id,tenant_id,empresa_id").eq("id", importacaoId).maybeSingle();
    if (erroImportacao) throw erroImportacao;
    const imp = importacao as { id: string; tenant_id: string; empresa_id: string } | null;
    if (!imp || imp.tenant_id !== tenantId || imp.empresa_id !== empresaId) return erro(404, "Importação não encontrada nesta empresa.");

    const nome = nomeSeguro(arquivo.name || "arquivo");
    const path = `${tenantId}/${empresaId}/IMPORTACAO-${importacaoId}/${tipo}-${Date.now()}-${nome}`;
    const contentType = arquivo.type || "application/octet-stream";
    const admin = supabaseAdmin();
    const bytes = new Uint8Array(await arquivo.arrayBuffer());
    const { error: erroUpload } = await admin.storage.from("nfe-documentos").upload(path, bytes, { contentType, upsert: false });
    if (erroUpload) throw new Error(`Não foi possível guardar o arquivo: ${erroUpload.message}`);

    const { data: anexoId, error: erroRegistro } = await supabase.schema("f").rpc("fn_importacao_remessa_anexo_registrar", {
      p_importacao_id: importacaoId,
      p_tipo: tipo,
      p_nome_arquivo: arquivo.name || nome,
      p_storage_path: path,
      p_content_type: contentType,
      p_tamanho_bytes: arquivo.size,
    });
    if (erroRegistro) {
      await admin.storage.from("nfe-documentos").remove([path]).catch(() => {});
      throw erroRegistro;
    }
    return Response.json({ ok: true, anexo_id: anexoId, storage_path: path, nome_arquivo: arquivo.name || nome, tipo });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Falha ao anexar o arquivo.";
    return erro(400, message);
  }
}

export async function GET(request: Request) {
  try {
    const sessao = await usuarioDaSessao(request);
    if ("erro" in sessao) return sessao.erro;
    const { supabase } = sessao;
    const url = new URL(request.url);
    const anexoId = String(url.searchParams.get("anexo_id") ?? "").trim();
    if (!UUID.test(anexoId)) return erro(400, "Anexo inválido.");
    // A leitura passa pela RLS do usuario: so anexo do tenant/empresa ativos com acesso financeiro.
    const { data, error } = await supabase.schema("f").from("importacao_remessa_anexo")
      .select("id,storage_path,nome_arquivo,content_type").eq("id", anexoId).is("deleted_at", null).maybeSingle();
    if (error) throw error;
    const anexo = data as { id: string; storage_path: string; nome_arquivo: string; content_type: string | null } | null;
    if (!anexo) return erro(404, "Anexo não encontrado.");
    const admin = supabaseAdmin();
    const { data: assinada, error: erroUrl } = await admin.storage.from("nfe-documentos").createSignedUrl(anexo.storage_path, 600, { download: anexo.nome_arquivo });
    if (erroUrl || !assinada?.signedUrl) throw new Error(erroUrl?.message ?? "Não foi possível gerar o link do anexo.");
    return Response.json({ url: assinada.signedUrl, nome_arquivo: anexo.nome_arquivo, content_type: anexo.content_type });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Falha ao abrir o anexo.";
    return erro(400, message);
  }
}
