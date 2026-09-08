// PDF do orcamento, gerado no servidor.
//
// Existe para o aplicativo baixar exatamente o mesmo arquivo que o botao
// "Baixar PDF" da tela de impressao produz: os dois chamam
// lib/comercial/orcamentoPdf.ts com os dados de orcamentoPdfDados.ts.

import { NextRequest } from "next/server";

import { getAuthSupabase, jsonError, resolveTenantEmpresa } from "@/app/api/compras/_lib";
import { podeBaixarOrcamentoPdf } from "@/lib/auth/papeisRelatorios";
import { gerarOrcamentoPdf } from "@/lib/comercial/orcamentoPdf";
import { carregarDadosOrcamentoPdf, nomeArquivoOrcamentoPdf } from "@/lib/comercial/orcamentoPdfDados";
import { carregarImagemNoServidor } from "@/lib/pdf/imagemPdfServidor";

export const runtime = "nodejs";
// Um orcamento com muitos itens gera varias paginas; o padrao de 10s aperta.
export const maxDuration = 60;

type ContextoAtual = { papel?: string | null };

export async function GET(req: NextRequest, context: { params: Promise<{ id?: string }> }) {
  try {
    const auth = await getAuthSupabase(req);
    if ("error" in auth) return auth.error;
    const { supabase } = auth;

    const { id } = await context.params;
    const idParam = String(id ?? "").trim();
    if (!idParam) return jsonError(400, "Orcamento invalido.");

    const escopo = await resolveTenantEmpresa(supabase, null, req.nextUrl.searchParams);
    if (!escopo) return jsonError(400, "Contexto de tenant/empresa nao definido.");

    const { data: contextoData, error: contextoErro } = await supabase.rpc("app_contexto_atual");
    if (contextoErro) return jsonError(403, "Nao foi possivel confirmar o perfil.");

    const contexto = (contextoData ?? {}) as ContextoAtual;
    if (!podeBaixarOrcamentoPdf(contexto.papel)) {
      return jsonError(403, "Seu perfil nao pode baixar o PDF do orcamento.");
    }

    const dados = await carregarDadosOrcamentoPdf(supabase, {
      tenantId: escopo.tenantId,
      empresaId: escopo.empresaId,
      idOrCodigo: idParam,
    });

    const bytes = await gerarOrcamentoPdf(dados, { carregarImagem: carregarImagemNoServidor });
    const nomeArquivo = nomeArquivoOrcamentoPdf(dados.orcamento, idParam);

    return new Response(bytes as BodyInit, {
      status: 200,
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": `attachment; filename="${nomeArquivo}"`,
        "Content-Length": String(bytes.byteLength),
        "Cache-Control": "no-store",
      },
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Erro ao gerar o PDF.";
    return jsonError(500, message);
  }
}
