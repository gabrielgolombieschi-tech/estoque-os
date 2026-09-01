import { NextRequest, NextResponse } from "next/server";
import { getAuthSupabase, jsonError, resolveTenantEmpresa } from "@/app/api/compras/_lib";
import { supabaseAdmin } from "@/lib/supabase/admin";
import { erroTabelaCorrecaoAusente, normalizarDescricaoAprendizado } from "@/lib/nfe/descricaoCorrecaoIa";

export const runtime = "nodejs";

function texto(value: unknown, max: number) {
  const result = String(value ?? "").trim().replace(/\s+/g, " ");
  return result ? result.slice(0, max) : null;
}

export async function POST(req: NextRequest) {
  try {
    const auth = await getAuthSupabase(req);
    if ("error" in auth) return auth.error;

    const body = (await req.json().catch(() => null)) as Record<string, unknown> | null;
    if (!body) return jsonError(400, "Corpo da solicitacao invalido.");

    const ctx = await resolveTenantEmpresa(auth.supabase, body);
    if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");

    const { data: podeCadastrar } = await auth.supabase.rpc("can", {
      p_resource: "cad_itens",
      p_action: "write",
    });
    if (!podeCadastrar) return jsonError(403, "Sem permissao para corrigir a descricao do cadastro.");

    const descricaoOrigem = texto(body.descricao_origem, 500);
    const descricaoSugerida = texto(body.descricao_sugerida, 300);
    const descricaoCorrigida = texto(body.descricao_corrigida, 300);
    const codigoItem = texto(body.codigo_item, 120);
    const descricaoOrigemNormalizada = normalizarDescricaoAprendizado(descricaoOrigem);

    if (!descricaoOrigem || !descricaoOrigemNormalizada) {
      return jsonError(400, "Descricao original do XML nao informada.");
    }
    if (!descricaoCorrigida) return jsonError(400, "Informe a descricao final do item.");

    const admin = supabaseAdmin();
    const agora = new Date().toISOString();
    const { data, error } = await admin
      .from("parametro_importacao_xml_descricao_ia")
      .upsert(
        {
          tenant_id: ctx.tenantId,
          empresa_id: ctx.empresaId,
          descricao_origem: descricaoOrigem,
          descricao_origem_normalizada: descricaoOrigemNormalizada,
          descricao_sugerida_ia: descricaoSugerida,
          descricao_corrigida: descricaoCorrigida,
          codigo_item: codigoItem,
          corrigido_por_auth: auth.user.id,
          ativo: true,
          deleted_at: null,
          updated_at: agora,
        },
        { onConflict: "tenant_id,empresa_id,descricao_origem_normalizada" }
      )
      .select("id,descricao_corrigida,updated_at")
      .single();

    if (error && erroTabelaCorrecaoAusente(error)) {
      return NextResponse.json(
        {
          ok: true,
          persisted: false,
          pendingMigration: true,
          correcao: {
            descricao_origem: descricaoOrigem,
            descricao_origem_normalizada: descricaoOrigemNormalizada,
            descricao_corrigida: descricaoCorrigida,
          },
        },
        { status: 202 }
      );
    }
    if (error) return jsonError(400, error.message);

    return NextResponse.json({ ok: true, persisted: true, correcao: data });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Erro inesperado ao salvar a correcao de descricao.";
    return jsonError(500, message);
  }
}
