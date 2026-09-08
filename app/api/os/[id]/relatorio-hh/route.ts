// PDF do relatorio de horas (HH) de uma OS, gerado no servidor.
//
// Existe para o aplicativo poder baixar exatamente o mesmo arquivo que o botao
// "Exportar PDF" da tela produz: os dois chamam lib/hh/relatorioHhPdf.ts com as
// linhas de lib/hh/relatorioHhDados.ts.

import { NextRequest } from "next/server";

import { getAuthSupabase, jsonError, resolveTenantEmpresa } from "@/app/api/compras/_lib";
import { podeBaixarRelatorioHhPdf } from "@/lib/auth/papeisRelatorios";
import {
  carregarLinhasRelatorioHh,
  carregarOsMetaRelatorioHh,
  periodoDoRelatorio,
} from "@/lib/hh/relatorioHhDados";
import { gerarRelatorioHhPdf, nomeArquivoRelatorioHh } from "@/lib/hh/relatorioHhPdf";
import { carregarImagemNoServidor } from "@/lib/pdf/imagemPdfServidor";

export const runtime = "nodejs";
// Uma OS com muitos lancamentos gera varias paginas; o padrao de 10s aperta.
export const maxDuration = 60;

type ContextoAtual = {
  empresa_nome?: string | null;
  papel?: string | null;
};

export async function GET(req: NextRequest, context: { params: Promise<{ id?: string }> }) {
  try {
    const auth = await getAuthSupabase(req);
    if ("error" in auth) return auth.error;
    const { supabase } = auth;

    const { id } = await context.params;
    const osId = Number(String(id ?? "").trim());
    if (!Number.isInteger(osId) || osId <= 0) {
      return jsonError(400, "OS invalida.");
    }

    const escopo = await resolveTenantEmpresa(supabase, null, req.nextUrl.searchParams);
    if (!escopo) return jsonError(400, "Contexto de tenant/empresa nao definido.");

    const { data: contextoData, error: contextoErro } = await supabase.rpc("app_contexto_atual");
    if (contextoErro) return jsonError(403, "Nao foi possivel confirmar o perfil.");

    const contexto = (contextoData ?? {}) as ContextoAtual;
    if (!podeBaixarRelatorioHhPdf(contexto.papel)) {
      return jsonError(403, "Seu perfil nao pode baixar o relatorio HH.");
    }

    const [linhas, osMeta] = await Promise.all([
      carregarLinhasRelatorioHh(supabase, osId, escopo.tenantId, escopo.empresaId),
      carregarOsMetaRelatorioHh(supabase, osId, escopo.tenantId),
    ]);

    if (linhas.length === 0) {
      return jsonError(404, "Esta OS nao tem lancamentos de HH.");
    }

    const bytes = await gerarRelatorioHhPdf(linhas, osId, {
      empresaNome: contexto.empresa_nome ?? undefined,
      clienteNome: osMeta.cliente_nome ?? undefined,
      numeroOS: osMeta.numero_os,
      osDescricao: osMeta.descricao_servico ?? undefined,
      periodoLabel: periodoDoRelatorio(linhas),
      emissaoLabel: new Date().toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" }),
    }, { carregarImagem: carregarImagemNoServidor });

    const nomeArquivo = nomeArquivoRelatorioHh(osId);

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
    const message = err instanceof Error ? err.message : "Erro ao gerar o relatorio.";
    return jsonError(500, message);
  }
}
