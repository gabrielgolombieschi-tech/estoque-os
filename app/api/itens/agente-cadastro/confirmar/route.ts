import { NextRequest, NextResponse } from "next/server";
import type { SupabaseClient } from "@supabase/supabase-js";
import { getAuthSupabase, jsonError, resolveTenantEmpresa } from "@/app/api/compras/_lib";
import { supabaseAdmin } from "@/lib/supabase/admin";
import {
  asRecord,
  eCodigoComProdutoNaDescricao,
  finalidade,
  inteiro,
  normalizarCodigo,
  normalizarCodigoGrupo,
  normalizarNome,
  normalizarQuantidade,
  normalizarUnidade,
  numero,
  sanitizarFiscal,
  texto,
  usuarioIdentificador,
  verificarTokenCotacaoAssinada,
  uuidOuNulo,
  type FiscalValores,
  type FornecedorRow,
  type GrupoRow,
  type PesquisaPreco,
} from "../_lib";

export const runtime = "nodejs";

type ItemDuplicado = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  ativo: boolean | null;
};

type SimilarComercial = {
  id: number;
  motivo_compra_id: string | null;
  margem_lucro_percentual: number | null;
};

type DbError = { message?: string; code?: string } | null;

async function carregarFornecedor(input: {
  supabase: SupabaseClient;
  tenantId: string;
  empresaId: string;
  fornecedorId: number;
}) {
  const { data, error } = await input.supabase
    .from("fornecedores")
    .select("id,nome,ativo,finalidade_padrao,motivo_compra_padrao_id")
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .eq("id", input.fornecedorId)
    .maybeSingle();
  if (error) throw new Error(error.message);
  return (data ?? null) as unknown as FornecedorRow | null;
}

async function localizarDuplicidade(input: {
  supabase: SupabaseClient;
  tenantId: string;
  empresaId: string;
  fornecedorId: number;
  codigo: string;
}) {
  const { data, error } = await input.supabase
    .from("itens")
    .select("id,codigo_interno,nome,ativo")
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .eq("fornecedor_id", input.fornecedorId)
    .eq("codigo_interno", input.codigo)
    .order("ativo", { ascending: false })
    .limit(10);
  if (error) throw new Error(error.message);
  const rows = (data ?? []) as unknown as ItemDuplicado[];
  const ativo = rows.find((row) => row.ativo !== false) ?? null;
  const inativo = rows.find((row) => row.ativo === false) ?? null;
  const item = ativo ?? inativo;
  return item
    ? {
        status: ativo ? ("ativo" as const) : ("inativo" as const),
        id: Number(item.id),
        codigo: String(item.codigo_interno ?? input.codigo),
        nome: String(item.nome ?? ""),
        ativo: item.ativo !== false,
      }
    : null;
}

async function carregarGrupo(input: {
  supabase: SupabaseClient;
  tenantId: string;
  empresaId: string;
  grupoId: number;
}) {
  const { data, error } = await input.supabase
    .from("item_grupos")
    .select("id,codigo,nome,grupo_pai_id,ativo")
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .eq("id", input.grupoId)
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!data) return null;
  return {
    id: Number(data.id),
    codigo: data.codigo == null ? null : String(data.codigo),
    nome: data.nome == null ? null : String(data.nome),
    grupo_pai_id: data.grupo_pai_id == null ? null : Number(data.grupo_pai_id),
    ativo: data.ativo == null ? true : Boolean(data.ativo),
  } as GrupoRow;
}

async function resolverGrupo(input: {
  supabase: SupabaseClient;
  tenantId: string;
  empresaId: string;
  sugestao: Record<string, unknown>;
  usuario: string;
}): Promise<{ grupo: GrupoRow; criadoAgora: boolean }> {
  const grupoId = inteiro(input.sugestao.grupo_id);
  if (grupoId) {
    const grupo = await carregarGrupo({ ...input, grupoId });
    if (!grupo || grupo.ativo === false) throw new Error("O grupo selecionado não está ativo para esta empresa.");
    return { grupo, criadoAgora: false };
  }

  const novoGrupo = asRecord(input.sugestao.novo_grupo);
  const codigo = normalizarCodigoGrupo(novoGrupo?.codigo);
  const nome = texto(novoGrupo?.nome, 120);
  if (!codigo || !nome) throw new Error("Selecione um grupo existente ou confirme um novo grupo válido.");

  const grupoPaiId = novoGrupo?.grupo_pai_id == null ? null : inteiro(novoGrupo.grupo_pai_id);
  if (grupoPaiId) {
    const pai = await carregarGrupo({ ...input, grupoId: grupoPaiId });
    if (!pai || pai.ativo === false) throw new Error("O grupo pai sugerido não está ativo para esta empresa.");
  }

  const { data: existentes, error: existentesError } = await input.supabase
    .from("item_grupos")
    .select("id,codigo,nome,grupo_pai_id,ativo")
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .eq("codigo", codigo)
    .limit(2);
  if (existentesError) throw new Error(existentesError.message);
  const existente = ((existentes ?? []) as unknown as GrupoRow[])[0] ?? null;
  if (existente) {
    if (existente.ativo === false) throw new Error("Já existe um grupo inativo com este código; reative-o ou escolha outro grupo.");
    return { grupo: existente, criadoAgora: false };
  }

  const { data, error } = await input.supabase
    .from("item_grupos")
    .insert({
      tenant_id: input.tenantId,
      empresa_id: input.empresaId,
      codigo,
      nome,
      descricao: texto(novoGrupo?.justificativa, 600),
      grupo_pai_id: grupoPaiId,
      ativo: true,
      criado_por: input.usuario,
      atualizado_por: input.usuario,
    })
    .select("id,codigo,nome,grupo_pai_id,ativo")
    .single();

  if (!error && data) {
    return {
      grupo: {
        id: Number(data.id),
        codigo: data.codigo == null ? null : String(data.codigo),
        nome: data.nome == null ? null : String(data.nome),
        grupo_pai_id: data.grupo_pai_id == null ? null : Number(data.grupo_pai_id),
        ativo: data.ativo == null ? true : Boolean(data.ativo),
      },
      criadoAgora: true,
    };
  }

  const dbError = error as DbError;
  if (dbError?.code !== "23505") throw new Error(dbError?.message ?? "Não foi possível criar o grupo sugerido.");
  const { data: concorrente, error: concorrenteError } = await input.supabase
    .from("item_grupos")
    .select("id,codigo,nome,grupo_pai_id,ativo")
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .eq("codigo", codigo)
    .maybeSingle();
  if (concorrenteError) throw new Error(concorrenteError.message);
  if (!concorrente || concorrente.ativo === false) throw new Error("Não foi possível confirmar o grupo criado simultaneamente.");
  return {
    grupo: {
      id: Number(concorrente.id),
      codigo: concorrente.codigo == null ? null : String(concorrente.codigo),
      nome: concorrente.nome == null ? null : String(concorrente.nome),
      grupo_pai_id: concorrente.grupo_pai_id == null ? null : Number(concorrente.grupo_pai_id),
      ativo: concorrente.ativo == null ? true : Boolean(concorrente.ativo),
    },
    criadoAgora: false,
  };
}

async function podeEditarFiscal(supabase: SupabaseClient): Promise<boolean> {
  const { data, error } = await supabase.rpc("can", {
    p_resource: "fiscal_itens",
    p_action: "write",
  });
  return !error && Boolean(data);
}

async function validarMotivoCompra(input: { supabase: SupabaseClient; tenantId: string; motivoId: string | null }) {
  if (!input.motivoId) return null;
  const { data, error } = await input.supabase
    .schema("f")
    .from("motivo_compra")
    .select("id")
    .eq("tenant_id", input.tenantId)
    .eq("id", input.motivoId)
    .eq("ativo", true)
    .is("deleted_at", null)
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!data) throw new Error("A classificação/motivo selecionado não é válida para este tenant.");
  return String(data.id);
}

async function carregarSimilarComercial(input: {
  supabase: SupabaseClient;
  tenantId: string;
  empresaId: string;
  itemId: number | null;
}): Promise<SimilarComercial | null> {
  if (!input.itemId) return null;
  const { data, error } = await input.supabase
    .from("itens")
    .select("id,motivo_compra_id,margem_lucro_percentual")
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .eq("id", input.itemId)
    .maybeSingle();
  if (error) throw new Error(error.message);
  return (data ?? null) as unknown as SimilarComercial | null;
}

async function rollbackItem(input: { supabase: SupabaseClient; tenantId: string; empresaId: string; itemId: number }) {
  await input.supabase
    .from("fiscal_itens")
    .delete()
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .eq("item_id", input.itemId);
  await input.supabase
    .from("itens")
    .delete()
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .eq("id", input.itemId);
}

function fiscalParaBanco(fiscal: FiscalValores, itemId: number, tenantId: string, empresaId: string) {
  return {
    tenant_id: tenantId,
    empresa_id: empresaId,
    item_id: itemId,
    ...fiscal,
    atualizado_em: new Date().toISOString(),
  };
}

async function registrarAuditoria(input: {
  tenantId: string;
  empresaId: string;
  itemId: number;
  fornecedorId: number;
  codigo: string;
  quantidade: number;
  precoConfirmado: number;
  sugestao: Record<string, unknown>;
  pesquisa: PesquisaPreco;
  fontes: unknown[];
  similarId: number | null;
  fiscal: FiscalValores | null;
  modelo: string;
  usuario: string;
}): Promise<number> {
  const agora = new Date().toISOString();
  const admin = supabaseAdmin();
  const { data, error } = await admin
    .from("item_cadastro_agente_sugestoes")
    .insert({
      tenant_id: input.tenantId,
      empresa_id: input.empresaId,
      item_id: input.itemId,
      fornecedor_id: input.fornecedorId,
      codigo_interno: input.codigo,
      quantidade_referencia: input.quantidade,
      sugestao_json: input.sugestao,
      pesquisa_precos_json: [
        ...input.fontes,
        {
          tipo_registro: "resumo_pesquisa",
          pesquisa: input.pesquisa,
        },
      ],
      preco_origem: input.pesquisa.preco_origem,
      preco_final: input.pesquisa.preco_final_brl,
      preco_confirmado: input.precoConfirmado,
      moeda_origem: input.pesquisa.moeda,
      regra_preco: input.pesquisa.regra_preco,
      multiplicador_preco: input.pesquisa.fator_importacao,
      item_similar_id: input.similarId,
      fiscal_sugerido_json: input.fiscal ?? {},
      modelo: input.modelo,
      confirmado_por: input.usuario,
      confirmado_em: agora,
      criado_em: agora,
    })
    .select("id")
    .single();
  if (error || !data) throw new Error(error?.message ?? "Falha ao registrar a auditoria da sugestão.");
  return Number(data.id);
}

async function registrarEstoqueInicial(input: {
  supabase: SupabaseClient;
  tenantId: string;
  empresaId: string;
  itemId: number;
  quantidade: number;
  precoConfirmado: number;
  usuario: string;
}): Promise<number | null> {
  const { data, error } = await input.supabase
    .from("movimentacoes")
    .insert({
      tenant_id: input.tenantId,
      empresa_id: input.empresaId,
      item_id: input.itemId,
      tipo: "entrada",
      quantidade: input.quantidade,
      custo_unitario_real: input.precoConfirmado,
      motivo: "Estoque inicial via agente de cadastro",
      realizado_por: input.usuario,
      data_movimentacao: new Date().toISOString(),
    })
    .select("id")
    .single();
  if (error || !data) return null;
  return Number(data.id);
}

export async function POST(req: NextRequest) {
  try {
    const auth = await getAuthSupabase(req);
    if ("error" in auth) return auth.error;

    const body = (await req.json().catch(() => null)) as Record<string, unknown> | null;
    if (!body) return jsonError(400, "Corpo da solicitação inválido.");
    const ctx = await resolveTenantEmpresa(auth.supabase, body);
    if (!ctx) return jsonError(400, "Tenant/empresa não carregados na sessão.");

    const { data: podeCadastrar, error: permissaoErro } = await auth.supabase.rpc("can", {
      p_resource: "cad_itens",
      p_action: "write",
    });
    if (permissaoErro) return jsonError(403, permissaoErro.message);
    if (!podeCadastrar) return jsonError(403, "Sem permissão para cadastrar itens.");

    const fornecedorId = inteiro(body.fornecedor_id);
    const codigo = normalizarCodigo(body.codigo);
    const quantidade = normalizarQuantidade(body.quantidade_referencia ?? body.quantidade);
    const sugestao = asRecord(body.sugestao);
    // A pessoa usuária pode ajustar o preço sugerido pela pesquisa ou informar um
    // preço que já conhece; o servidor apenas exige um valor positivo e plausível.
    const precoConfirmado = numero(body.preco_unitario_confirmado ?? body.preco_unitario, 0.01, 999999999);
    if (!fornecedorId) return jsonError(400, "Selecione um fornecedor cadastrado.");
    if (!codigo) return jsonError(400, "Informe o código do produto.");
    if (quantidade === null) return jsonError(400, "Informe uma quantidade válida (0 ou mais).");
    if (!sugestao) return jsonError(400, "A proposta do agente é obrigatória para confirmar o cadastro.");
    if (precoConfirmado === null) return jsonError(422, "Informe um preço unitário válido maior que zero antes de confirmar.");

    // A quantidade informada agora também define o estoque inicial do item; sem
    // permissão de estoque, a pessoa só pode cadastrar com quantidade zero.
    if (quantidade > 0) {
      const { data: podeMovimentarEstoque, error: permissaoEstoqueErro } = await auth.supabase.rpc("can", {
        p_resource: "estoque",
        p_action: "write",
      });
      if (permissaoEstoqueErro) return jsonError(403, permissaoEstoqueErro.message);
      if (!podeMovimentarEstoque) {
        return jsonError(403, "Sem permissão para gravar estoque. Informe quantidade 0 ou solicite acesso ao módulo de estoque.");
      }
    }

    const fornecedor = await carregarFornecedor({
      supabase: auth.supabase,
      tenantId: ctx.tenantId,
      empresaId: ctx.empresaId,
      fornecedorId,
    });
    if (!fornecedor) return jsonError(422, "Fornecedor inválido para a empresa atual.");
    if (fornecedor.ativo === false) return jsonError(422, "O fornecedor selecionado está inativo.");

    const cotacaoAssinada = verificarTokenCotacaoAssinada(body.cotacao_token);
    if (
      !cotacaoAssinada ||
      cotacaoAssinada.tenant_id !== ctx.tenantId ||
      cotacaoAssinada.empresa_id !== ctx.empresaId ||
      cotacaoAssinada.usuario_id !== String(auth.user.id ?? "") ||
      cotacaoAssinada.fornecedor_id !== fornecedorId ||
      cotacaoAssinada.codigo !== codigo ||
      cotacaoAssinada.quantidade_referencia !== quantidade
    ) {
      return jsonError(422, "A cotação expirou ou não confere com esta sugestão. Gere uma nova sugestão antes de confirmar.");
    }

    const duplicidade = await localizarDuplicidade({
      supabase: auth.supabase,
      tenantId: ctx.tenantId,
      empresaId: ctx.empresaId,
      fornecedorId,
      codigo,
    });
    if (duplicidade) {
      return jsonError(
        409,
        duplicidade.status === "ativo"
          ? "Já existe um item ativo com este fornecedor e código."
          : "Existe um item inativo com este fornecedor e código; revise-o ou reative-o antes de cadastrar outro.",
        { duplicidade }
      );
    }

    const nome = normalizarNome(sugestao.descricao_padronizada);
    if (!nome) return jsonError(422, "Informe uma descrição padronizada antes de confirmar.");
    if (eCodigoComProdutoNaDescricao(codigo, nome)) {
      return jsonError(422, "A descrição não deve repetir o código do produto. Mantenha o código no campo próprio.");
    }

    const usuario = usuarioIdentificador(auth.user);
    const grupoResolvido = await resolverGrupo({
      supabase: auth.supabase,
      tenantId: ctx.tenantId,
      empresaId: ctx.empresaId,
      sugestao,
      usuario,
    });
    const similarRaw = asRecord(body.similar_interno);
    const fiscalRaw = asRecord(body.fiscal_sugerido);
    const similarIdSolicitado = inteiro(similarRaw?.id) ?? inteiro(fiscalRaw?.referencia_item_id);
    const similar = await carregarSimilarComercial({
      supabase: auth.supabase,
      tenantId: ctx.tenantId,
      empresaId: ctx.empresaId,
      itemId: similarIdSolicitado,
    });
    const motivoSolicitado = uuidOuNulo(sugestao.motivo_compra_id) ?? fornecedor.motivo_compra_padrao_id ?? similar?.motivo_compra_id ?? null;
    const motivoCompraId = await validarMotivoCompra({
      supabase: auth.supabase,
      tenantId: ctx.tenantId,
      motivoId: motivoSolicitado,
    });
    // A proposta revisada pode escolher outra finalidade, mas o padrao de todo
    // novo cadastro assistido e materia-prima.
    const finalidadeItem = finalidade(sugestao.finalidade) ?? "materia_prima";

    // Valor e fontes comerciais vêm exclusivamente do token emitido pelo
    // servidor na sugestão; nunca do corpo editável enviado pelo navegador.
    const fontes = cotacaoAssinada.fontes;
    const pesquisa = cotacaoAssinada.pesquisa_preco;
    const fiscal = sanitizarFiscal(fiscalRaw);
    if (fiscal && !(await podeEditarFiscal(auth.supabase))) {
      return jsonError(403, "Sem permissão para gravar dados fiscais neste cadastro.");
    }

    const margemSimilar = similar?.margem_lucro_percentual == null ? null : Number(similar.margem_lucro_percentual);
    // A margem só é aproveitada quando um item interno semelhante a confirma.
    // Sem essa referência, o ERP aplica sua regra comercial padrão ao consultar
    // o preço sugerido; não inventamos uma margem para o novo cadastro.
    const margem = margemSimilar !== null && Number.isFinite(margemSimilar) && margemSimilar >= 0 && margemSimilar <= 100 ? margemSimilar : null;
    const agora = new Date().toISOString();
    const { data: itemCriado, error: itemErro } = await auth.supabase
      .from("itens")
      .insert({
        tenant_id: ctx.tenantId,
        empresa_id: ctx.empresaId,
        codigo_interno: codigo,
        nome,
        descricao: null,
        tipo: "produto",
        unidade_medida: normalizarUnidade(sugestao.unidade_medida),
        controla_estoque: true,
        estoque_minimo: 0,
        estoque_maximo: 0,
        estoque_ideal: 0,
        // O preço gravado no cadastro é o valor revisado e confirmado pela
        // pessoa usuária, não necessariamente o preço bruto da pesquisa.
        custo_ultima_compra: precoConfirmado,
        custo_medio: precoConfirmado,
        preco_unitario: precoConfirmado,
        data_atualizacao_preco: agora,
        margem_lucro_percentual: margem,
        fornecedor_id: fornecedorId,
        fabricante: texto(sugestao.fabricante, 150)?.toUpperCase() ?? null,
        finalidade: finalidadeItem,
        motivo_compra_id: motivoCompraId,
        grupo_id: grupoResolvido.grupo.id,
        ativo: true,
        criado_por: usuario,
        criado_em: agora,
        atualizado_por: usuario,
        atualizado_em: agora,
      })
      .select("id,codigo_interno,nome,grupo_id")
      .single();
    if (itemErro || !itemCriado) {
      const dbError = itemErro as DbError;
      if (dbError?.code === "23505") return jsonError(409, "O item foi cadastrado simultaneamente com este fornecedor e código.");
      return jsonError(400, dbError?.message ?? "Não foi possível cadastrar o item.");
    }

    const itemId = Number(itemCriado.id);
    if (fiscal) {
      const { error: fiscalErro } = await auth.supabase
        .from("fiscal_itens")
        .upsert(fiscalParaBanco(fiscal, itemId, ctx.tenantId, ctx.empresaId), {
          onConflict: "tenant_id,empresa_id,item_id",
        });
      if (fiscalErro) {
        await rollbackItem({ supabase: auth.supabase, tenantId: ctx.tenantId, empresaId: ctx.empresaId, itemId });
        return jsonError(400, `Não foi possível gravar os dados fiscais; o item não foi mantido. ${fiscalErro.message}`);
      }
    }

    const modelo = String(process.env.ASSISTENTE_IA_OPENAI_MODEL ?? "gpt-5.4-mini").trim();
    let auditoriaId: number;
    try {
      auditoriaId = await registrarAuditoria({
        tenantId: ctx.tenantId,
        empresaId: ctx.empresaId,
        itemId,
        fornecedorId,
        codigo,
        quantidade,
        precoConfirmado,
        sugestao: {
          ...sugestao,
          grupo_id: grupoResolvido.grupo.id,
          grupo_codigo: grupoResolvido.grupo.codigo,
          grupo_nome: grupoResolvido.grupo.nome,
        },
        pesquisa,
        fontes,
        similarId: similar?.id ?? null,
        fiscal,
        modelo,
        usuario,
      });
    } catch (auditoriaErro: unknown) {
      await rollbackItem({ supabase: auth.supabase, tenantId: ctx.tenantId, empresaId: ctx.empresaId, itemId });
      const message = auditoriaErro instanceof Error ? auditoriaErro.message : "Falha ao registrar a auditoria da sugestão.";
      return jsonError(500, `O cadastro não foi concluído porque a auditoria não pôde ser gravada. ${message}`);
    }

    // As movimentações de estoque são imutáveis (não podem ser apagadas), por
    // isso essa etapa fica por último: se falhar, o item e a auditoria já
    // gravados permanecem válidos, só sem o lançamento automático do estoque.
    let estoqueAviso: string | null = null;
    if (quantidade > 0) {
      const movimentacaoId = await registrarEstoqueInicial({
        supabase: auth.supabase,
        tenantId: ctx.tenantId,
        empresaId: ctx.empresaId,
        itemId,
        quantidade,
        precoConfirmado,
        usuario,
      });
      if (movimentacaoId) {
        const admin = supabaseAdmin();
        await admin
          .from("item_cadastro_agente_sugestoes")
          .update({ movimentacao_estoque_id: movimentacaoId })
          .eq("id", auditoriaId);
      } else {
        estoqueAviso =
          "O item foi cadastrado, mas não foi possível lançar o estoque inicial automaticamente. Registre a entrada manualmente em Estoque.";
      }
    }

    const mensagemEstoque =
      quantidade > 0
        ? estoqueAviso ?? `Estoque inicial de ${quantidade} ${normalizarUnidade(sugestao.unidade_medida)} lançado ao confirmar.`
        : "Nenhuma quantidade foi informada; o item foi cadastrado sem estoque inicial.";

    return NextResponse.json(
      {
        item_id: itemId,
        item: {
          id: itemId,
          codigo_interno: String(itemCriado.codigo_interno ?? codigo),
          nome: String(itemCriado.nome ?? nome),
          grupo_id: Number(itemCriado.grupo_id ?? grupoResolvido.grupo.id),
        },
        grupo_criado_agora: grupoResolvido.criadoAgora,
        pesquisa_preco: pesquisa,
        preco_confirmado: precoConfirmado,
        estoque_aviso: estoqueAviso,
        message: `Item cadastrado com a proposta revisada do agente. ${mensagemEstoque}`,
      },
      { status: 201 }
    );
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Erro inesperado ao confirmar o cadastro assistido.";
    return jsonError(500, message);
  }
}
