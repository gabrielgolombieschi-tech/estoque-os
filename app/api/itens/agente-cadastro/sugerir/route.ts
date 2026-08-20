import { NextRequest, NextResponse } from "next/server";
import type { SupabaseClient } from "@supabase/supabase-js";
import { getAuthSupabase, jsonError, resolveTenantEmpresa } from "@/app/api/compras/_lib";
import {
  asRecord,
  buscarCotacaoCambioPtax,
  calcularPesquisaPreco,
  catalogoNormalizacao,
  caminhoGrupo,
  criarTokenCotacaoAssinada,
  extrairFontesWeb,
  extrairTextoResposta,
  finalidade,
  fiscalComReferencia,
  grupoParaResposta,
  inteiro,
  normalizarCodigo,
  normalizarQuantidade,
  parseRespostaJson,
  promptSistemaAgenteCadastro,
  schemaRespostaAgente,
  sanitizarSugestaoModelo,
  selecionarSimilar,
  texto,
  type FiscalSugerido,
  type FonteWeb,
  type FornecedorRow,
  type GrupoRow,
  type PesquisaPreco,
  type SimilarInterno,
} from "../_lib";

export const runtime = "nodejs";
// A pesquisa técnica seguida da cotação em marketplace pode precisar de duas chamadas web.
export const maxDuration = 60;

type ItemDuplicado = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  ativo: boolean | null;
  fornecedor_id: number | null;
};

type SimilarDbRow = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  descricao: string | null;
  fornecedor_id: number | null;
  grupo_id: number | null;
  finalidade: "consumo" | "materia_prima" | "revenda" | "imobilizado" | "outros" | null;
  motivo_compra_id: string | null;
  preco_unitario: number | null;
  margem_lucro_percentual: number | null;
};

type FiscalDbRow = {
  ncm: string | null;
  cest: string | null;
  origem: number | null;
  cfop_padrao: string | null;
  cst_icms: string | null;
  cst_pis: string | null;
  cst_cofins: string | null;
  aliq_icms: number | null;
  aliq_ipi: number | null;
  aliq_pis: number | null;
  aliq_cofins: number | null;
  credita_icms: boolean | null;
  ipi_entra_no_custo: boolean | null;
  credita_pis: boolean | null;
  credita_cofins: boolean | null;
};

const DOMINIOS_PESQUISA_MARKETPLACE = [
  "mercadolivre.com.br",
  "ebay.com",
  "ebay.com.br",
  "ebay.co.uk",
  "ebay.de",
  "ebay.ca",
  "ebay.com.au",
];

type PesquisaPrecoBruta = {
  tipo_correspondencia: "exato" | "similar" | "nao_encontrado";
  fonte: string | null;
  titulo: string | null;
  fonte_url: string | null;
  moeda: string | null;
  preco_origem: number | null;
  taxa_cambio_brl: number | null;
  fonte_cambio_url: string | null;
  data_cambio: string | null;
  observacao: string | null;
};

function schemaRespostaPesquisaMarketplace() {
  return {
    type: "object",
    additionalProperties: false,
    required: [
      "tipo_correspondencia",
      "marketplace",
      "fonte",
      "titulo",
      "fonte_url",
      "moeda",
      "preco_origem",
      "taxa_cambio_brl",
      "fonte_cambio_url",
      "data_cambio",
      "observacao",
    ],
    properties: {
      tipo_correspondencia: { type: "string", enum: ["exato", "similar", "nao_encontrado"] },
      marketplace: { type: ["string", "null"], enum: ["Mercado Livre", "eBay", null] },
      fonte: { type: ["string", "null"] },
      titulo: { type: ["string", "null"] },
      fonte_url: { type: ["string", "null"] },
      moeda: { type: ["string", "null"] },
      preco_origem: { type: ["number", "null"] },
      taxa_cambio_brl: { type: ["number", "null"] },
      fonte_cambio_url: { type: ["string", "null"] },
      data_cambio: { type: ["string", "null"] },
      observacao: { type: ["string", "null"] },
    },
  };
}

function fontesUnicas(...listas: FonteWeb[][]): FonteWeb[] {
  const fontes = new Map<string, FonteWeb>();
  for (const lista of listas) {
    for (const fonte of lista) {
      const chave = fonte.url.trim().toLowerCase();
      if (chave && !fontes.has(chave)) fontes.set(chave, fonte);
    }
  }
  return [...fontes.values()];
}

function fontesDaCotacao(pesquisa: PesquisaPreco, fontes: FonteWeb[]): FonteWeb[] {
  const urls = new Set([pesquisa.fonte_url, pesquisa.fonte_cambio_url].filter((url): url is string => Boolean(url)));
  return fontes.filter((fonte) => urls.has(fonte.url)).slice(0, 3);
}

function eMarketplace(marketplace: string | null): boolean {
  return marketplace === "Mercado Livre" || marketplace === "eBay";
}

function devePesquisarMarketplaces(pesquisa: PesquisaPreco): boolean {
  return pesquisa.status !== "encontrado" || !eMarketplace(pesquisa.marketplace);
}

function deveUsarPesquisaMarketplace(atual: PesquisaPreco, candidata: PesquisaPreco): boolean {
  if (candidata.preco_origem == null || !candidata.fonte_url) return false;
  if (atual.preco_origem == null || !atual.fonte_url) return true;
  if (candidata.status === "encontrado" && atual.status !== "encontrado") return true;
  if (candidata.tipo_correspondencia === "exato" && atual.tipo_correspondencia !== "exato") return true;
  return candidata.status === "encontrado" && eMarketplace(candidata.marketplace) && !eMarketplace(atual.marketplace);
}

async function complementarCotacaoComPtax(input: {
  pesquisa: PesquisaPreco;
  pesquisaBruta: PesquisaPrecoBruta;
  fontes: FonteWeb[];
}): Promise<{ pesquisa: PesquisaPrecoBruta; fontes: FonteWeb[] } | null> {
  if (
    !eMarketplace(input.pesquisa.marketplace) ||
    input.pesquisa.preco_origem === null ||
    !input.pesquisa.moeda ||
    input.pesquisa.moeda === "BRL"
  ) {
    return null;
  }
  const cambio = await buscarCotacaoCambioPtax(input.pesquisa.moeda);
  if (!cambio) return null;
  return {
    pesquisa: {
      ...input.pesquisaBruta,
      taxa_cambio_brl: cambio.taxa_cambio_brl,
      fonte_cambio_url: cambio.fonte.url,
      data_cambio: cambio.data_cambio,
    },
    fontes: fontesUnicas(input.fontes, [cambio.fonte]),
  };
}

async function pesquisarPrecoEmMarketplaces(input: {
  apiKey: string;
  model: string;
  fornecedor: string;
  codigo: string;
  codigoInformado: string;
}): Promise<{ pesquisa: Record<string, unknown>; fontes: FonteWeb[] } | null> {
  try {
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: { Authorization: `Bearer ${input.apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: input.model,
        store: false,
        tool_choice: "required",
        tools: [
          {
            type: "web_search",
            search_context_size: "medium",
            filters: { allowed_domains: DOMINIOS_PESQUISA_MARKETPLACE },
          },
        ],
        include: ["web_search_call.action.sources"],
        input: [
          {
            role: "system",
            content:
              "Você é o pesquisador de preço do ERP. Use obrigatoriamente a pesquisa web e procure o código exato primeiro no Mercado Livre Brasil e no eBay. Faça consultas com o código informado e com o código normalizado; só use item similar quando o código exato não retornar anúncio. Uma página técnica do fabricante não é fonte de preço. Se houver anúncio de marketplace com preço visível, ele deve ser preferido. Retorne somente um JSON estruturado. fonte_url deve ser a URL exata de uma fonte devolvida pela ferramenta; preco_origem deve ser o número visto no anúncio, sem conversão. marketplace deve identificar Mercado Livre ou eBay. Não pesquise nem estime câmbio nesta etapa: quando a moeda não for BRL, mantenha preco_origem e moeda do anúncio e preencha taxa_cambio_brl, fonte_cambio_url e data_cambio com null. O servidor consulta a PTAX do Banco Central separadamente. Sem anúncio com preço visível, use preco_origem null e explique em observacao.",
          },
          {
            role: "user",
            content: JSON.stringify({
              fornecedor: input.fornecedor,
              codigo_informado: input.codigoInformado,
              codigo_normalizado: input.codigo,
              consultas_obrigatorias: [
                `site:mercadolivre.com.br ${input.codigoInformado}`,
                `site:ebay.com ${input.codigoInformado}`,
                `${input.fornecedor} ${input.codigo}`,
              ],
            }),
          },
        ],
        text: {
          format: {
            type: "json_schema",
            name: "pesquisa_preco_marketplace",
            strict: true,
            schema: schemaRespostaPesquisaMarketplace(),
          },
        },
      }),
    });

    const responseText = await response.text();
    let responseJson: unknown = null;
    try {
      responseJson = responseText ? JSON.parse(responseText) : null;
    } catch {
      responseJson = null;
    }
    if (!response.ok) return null;

    const pesquisa = asRecord(parseRespostaJson(extrairTextoResposta(responseJson)));
    if (!pesquisa) return null;
    return { pesquisa, fontes: extrairFontesWeb(responseJson) };
  } catch {
    // A proposta técnica continua útil mesmo que a pesquisa complementar de preço falhe.
    return null;
  }
}

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
    .select("id,codigo_interno,nome,ativo,fornecedor_id")
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
        item: {
          id: Number(item.id),
          codigo_interno: String(item.codigo_interno ?? input.codigo),
          nome: String(item.nome ?? ""),
          ativo: item.ativo !== false,
        },
      }
    : null;
}

async function carregarGrupos(input: { supabase: SupabaseClient; tenantId: string; empresaId: string }) {
  const { data, error } = await input.supabase
    .from("item_grupos")
    .select("id,codigo,nome,grupo_pai_id,ativo")
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .eq("ativo", true)
    .order("nome", { ascending: true });
  if (error) throw new Error(error.message);
  return (data ?? []).map((row) => ({
    id: Number(row.id),
    codigo: row.codigo == null ? null : String(row.codigo),
    nome: row.nome == null ? null : String(row.nome),
    grupo_pai_id: row.grupo_pai_id == null ? null : Number(row.grupo_pai_id),
    ativo: row.ativo == null ? true : Boolean(row.ativo),
  })) as GrupoRow[];
}

async function podeEditarFiscal(supabase: SupabaseClient): Promise<boolean> {
  const { data, error } = await supabase.rpc("can", {
    p_resource: "fiscal_itens",
    p_action: "write",
  });
  return !error && Boolean(data);
}

async function buscarSimilarEFiscal(input: {
  supabase: SupabaseClient;
  tenantId: string;
  empresaId: string;
  fornecedorId: number;
  codigo: string;
  descricao: string;
  grupoId: number | null;
  podeFiscal: boolean;
}): Promise<{ similar: SimilarInterno | null; fiscal: FiscalSugerido | null }> {
  let query = input.supabase
    .from("itens")
    .select(
      "id,codigo_interno,nome,descricao,fornecedor_id,grupo_id,finalidade,motivo_compra_id,preco_unitario,margem_lucro_percentual"
    )
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .eq("ativo", true)
    .neq("codigo_interno", input.codigo)
    .limit(120);

  if (input.grupoId) query = query.eq("grupo_id", input.grupoId);
  else query = query.eq("fornecedor_id", input.fornecedorId);

  const { data, error } = await query;
  if (error) throw new Error(error.message);
  const similar = selecionarSimilar({
    descricao: input.descricao,
    grupoId: input.grupoId,
    fornecedorId: input.fornecedorId,
    candidatos: (data ?? []) as unknown as SimilarDbRow[],
  });
  if (!similar || !input.podeFiscal) return { similar, fiscal: null };

  const { data: fiscalData, error: fiscalError } = await input.supabase
    .from("fiscal_itens")
    .select(
      "ncm,cest,origem,cfop_padrao,cst_icms,cst_pis,cst_cofins,aliq_icms,aliq_ipi,aliq_pis,aliq_cofins,credita_icms,ipi_entra_no_custo,credita_pis,credita_cofins"
    )
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .eq("item_id", similar.id)
    .maybeSingle();
  if (fiscalError) return { similar, fiscal: null };
  return {
    similar,
    fiscal: fiscalComReferencia(fiscalData as unknown as FiscalDbRow | null, similar.id),
  };
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
    const codigoInformado = texto(body.codigo, 120) ?? codigo;
    const quantidade = normalizarQuantidade(body.quantidade_referencia ?? body.quantidade);
    if (!fornecedorId) return jsonError(400, "Selecione um fornecedor cadastrado.");
    if (!codigo) return jsonError(400, "Informe o código do produto.");
    if (quantidade === null) return jsonError(400, "Informe uma quantidade válida (0 ou mais).");

    const fornecedor = await carregarFornecedor({
      supabase: auth.supabase,
      tenantId: ctx.tenantId,
      empresaId: ctx.empresaId,
      fornecedorId,
    });
    if (!fornecedor) return jsonError(422, "Fornecedor inválido para a empresa atual.");
    if (fornecedor.ativo === false) return jsonError(422, "O fornecedor selecionado está inativo.");

    const duplicidade = await localizarDuplicidade({
      supabase: auth.supabase,
      tenantId: ctx.tenantId,
      empresaId: ctx.empresaId,
      fornecedorId,
      codigo,
    });
    if (duplicidade) {
      return NextResponse.json({
        model: null,
        fornecedor: { id: fornecedor.id, nome: fornecedor.nome ?? "" },
        codigo,
        quantidade_referencia: quantidade,
        duplicidade: {
          id: duplicidade.item.id,
          codigo: duplicidade.item.codigo_interno,
          nome: duplicidade.item.nome,
          ativo: duplicidade.item.ativo,
          status: duplicidade.status,
          mensagem:
            duplicidade.status === "ativo"
              ? "Já existe um item ativo com este fornecedor e código."
              : "Existe um item inativo com este fornecedor e código; revise-o ou reative-o antes de cadastrar outro.",
        },
        sugestao: null,
        fontes: [],
        similar_interno: null,
        fiscal_sugerido: null,
        pode_editar_fiscal: false,
      });
    }

    const apiKey = String(process.env.OPENAI_API_KEY ?? process.env.ASSISTENTE_IA_OPENAI_API_KEY ?? "").trim();
    if (!apiKey) return jsonError(503, "OPENAI_API_KEY não configurada para o agente de cadastro.");
    const model = String(process.env.ASSISTENTE_IA_OPENAI_MODEL ?? "gpt-5.4-mini").trim();

    const grupos = await carregarGrupos({ supabase: auth.supabase, tenantId: ctx.tenantId, empresaId: ctx.empresaId });
    const gruposPorId = new Map(grupos.map((grupo) => [grupo.id, grupo]));
    const gruposParaAgente = grupos.map((grupo) => ({
      id: grupo.id,
      codigo: grupo.codigo ?? "",
      nome: grupo.nome ?? "",
      caminho: caminhoGrupo(grupo, gruposPorId),
    }));
    const catalogo = await catalogoNormalizacao();

    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        store: false,
        tool_choice: "required",
        tools: [{ type: "web_search", search_context_size: "high" }],
        include: ["web_search_call.action.sources"],
        input: [
          {
            role: "system",
            content: [
              promptSistemaAgenteCadastro(),
              "Protocolo obrigatório de pesquisa: antes de responder, reconheça tecnicamente o código em fonte técnica e pesquise também o mesmo código no Mercado Livre Brasil e no eBay. Execute consultas com o código informado e com a forma normalizada, inclusive sem separadores visuais. Não encerre a cotação com apenas uma página do fabricante sem preço se a pesquisa retornar anúncio de marketplace. Para pesquisa_preco, priorize anúncio de código exato com preço visível; use similar somente quando o exato não existir e declare isso. fonte, titulo, fonte_url, moeda e preco_origem devem corresponder ao anúncio concreto retornado pela ferramenta. O marketplace é identificado pela URL e será validado pelo servidor. Em preço estrangeiro, pesquise uma cotação BRL verificável e informe taxa_cambio_brl, fonte_cambio_url e data_cambio em AAAA-MM-DD; não estime câmbio. A conversão e o acréscimo de importação do eBay são calculados exclusivamente pelo servidor.",
            ].join(" "),
          },
          {
            role: "user",
            content: JSON.stringify({
              fornecedor: fornecedor.nome ?? "",
              codigo_informado: codigoInformado,
              codigo_produto: codigo,
              quantidade_referencia: quantidade,
              consultas_minimas_preco: [
                `site:mercadolivre.com.br ${codigoInformado}`,
                `site:ebay.com ${codigoInformado}`,
                `${fornecedor.nome ?? ""} ${codigo}`,
              ],
              catalogo_padrao_aprovado: catalogo,
              grupos_ativos_disponiveis: gruposParaAgente,
            }),
          },
        ],
        text: {
          format: {
            type: "json_schema",
            name: "proposta_cadastro_item_assistido",
            strict: true,
            schema: schemaRespostaAgente(),
          },
        },
      }),
    });

    const responseText = await response.text();
    let responseJson: unknown = null;
    try {
      responseJson = responseText ? JSON.parse(responseText) : null;
    } catch {
      responseJson = null;
    }
    if (!response.ok) {
      const error = asRecord(asRecord(responseJson)?.error);
      return jsonError(502, texto(error?.message, 350) ?? "Erro ao consultar o agente de cadastro.");
    }

    const resposta = parseRespostaJson(extrairTextoResposta(responseJson));
    if (!resposta) return jsonError(502, "O agente não retornou uma proposta estruturada válida.");
    let fontes = extrairFontesWeb(responseJson);
    let proposta = sanitizarSugestaoModelo({ resposta, codigo, gruposPorId, fontes });
    let pesquisaPreco = calcularPesquisaPreco({ pesquisa: proposta.pesquisa_preco, fontes });

    // Quando a pesquisa técnica não entrega uma referência comercial útil, repete a
    // busca em marketplaces. As fontes continuam passando pela mesma validação por URL.
    if (devePesquisarMarketplaces(pesquisaPreco)) {
      const pesquisaMarketplace = await pesquisarPrecoEmMarketplaces({
        apiKey,
        model,
        fornecedor: fornecedor.nome ?? "",
        codigo,
        codigoInformado,
      });
      if (pesquisaMarketplace) {
        const fontesCompletas = fontesUnicas(fontes, pesquisaMarketplace.fontes);
        const respostaComPrecoMarketplace = {
          ...(asRecord(resposta) ?? {}),
          pesquisa_preco: pesquisaMarketplace.pesquisa,
        };
        const propostaMarketplace = sanitizarSugestaoModelo({
          resposta: respostaComPrecoMarketplace,
          codigo,
          gruposPorId,
          fontes: fontesCompletas,
        });
        const precoMarketplace = calcularPesquisaPreco({
          pesquisa: propostaMarketplace.pesquisa_preco,
          fontes: fontesCompletas,
        });
        if (deveUsarPesquisaMarketplace(pesquisaPreco, precoMarketplace)) {
          fontes = fontesCompletas;
          proposta = propostaMarketplace;
          pesquisaPreco = precoMarketplace;
        }
      }
    }

    // A busca de marketplace devolve o preço original do anúncio. Para valores
    // estrangeiros, a taxa é buscada diretamente na PTAX, sem exigir que o
    // modelo encontre preço e câmbio na mesma execução de web_search.
    const complementoPtax = await complementarCotacaoComPtax({
      pesquisa: pesquisaPreco,
      pesquisaBruta: proposta.pesquisa_preco,
      fontes,
    });
    if (complementoPtax) {
      const propostaComPtax = {
        ...proposta,
        pesquisa_preco: complementoPtax.pesquisa,
      };
      const precoComPtax = calcularPesquisaPreco({
        pesquisa: propostaComPtax.pesquisa_preco,
        fontes: complementoPtax.fontes,
      });
      if (precoComPtax.status === "encontrado") {
        fontes = complementoPtax.fontes;
        proposta = propostaComPtax;
        pesquisaPreco = precoComPtax;
      }
    }

    const fontesCotacao = fontesDaCotacao(pesquisaPreco, fontes);
    const cotacaoToken = criarTokenCotacaoAssinada({
      tenant_id: ctx.tenantId,
      empresa_id: ctx.empresaId,
      usuario_id: String(auth.user.id ?? ""),
      fornecedor_id: fornecedorId,
      codigo,
      quantidade_referencia: quantidade,
      pesquisa_preco: pesquisaPreco,
      fontes: fontesCotacao,
    });
    if (!cotacaoToken) return jsonError(503, "Não foi possível selar a cotação do agente. Tente novamente.");

    const podeFiscal = await podeEditarFiscal(auth.supabase);
    const { similar, fiscal } = await buscarSimilarEFiscal({
      supabase: auth.supabase,
      tenantId: ctx.tenantId,
      empresaId: ctx.empresaId,
      fornecedorId,
      codigo,
      descricao: proposta.descricao_padronizada,
      grupoId: proposta.grupo_id,
      podeFiscal,
    });

    // Este fluxo inicia todo novo item como matéria-prima; a revisão humana pode alterar depois.
    const finalidadeFinal = "materia_prima";
    const motivoCompraId = fornecedor.motivo_compra_padrao_id ?? similar?.motivo_compra_id ?? null;
    const dadosPendentes = [...proposta.dados_pendentes];
    if (!proposta.descricao_padronizada) dadosPendentes.push("O agente não retornou uma descrição segura; revise antes de confirmar.");
    if (!proposta.grupo_id && !proposta.novo_grupo) dadosPendentes.push("Nenhum grupo adequado foi identificado; selecione ou proponha um grupo antes de confirmar.");
    if (pesquisaPreco.status !== "encontrado") dadosPendentes.push("A referência de preço ainda precisa de validação humana.");
    if (!podeFiscal) dadosPendentes.push("Você não possui permissão para gravar dados fiscais neste cadastro.");

    const novoGrupoResposta = proposta.novo_grupo
      ? {
          ...proposta.novo_grupo,
          grupo_pai_nome: proposta.novo_grupo.grupo_pai_id
            ? gruposPorId.get(proposta.novo_grupo.grupo_pai_id)?.nome ?? null
            : null,
        }
      : null;

    return NextResponse.json({
      model,
      fornecedor: { id: fornecedor.id, nome: fornecedor.nome ?? "" },
      codigo,
      quantidade_referencia: quantidade,
      duplicidade: null,
      sugestao: {
        codigo,
        descricao_padronizada: proposta.descricao_padronizada,
        fabricante: proposta.fabricante_sugerido,
        modelo_referencia: proposta.modelo_referencia,
        unidade_medida: proposta.unidade_medida ?? "UN",
        finalidade: finalidade(finalidadeFinal) ?? "materia_prima",
        motivo_compra_id: motivoCompraId,
        ...grupoParaResposta(proposta.grupo_id, gruposPorId),
        novo_grupo: novoGrupoResposta,
        justificativa: proposta.justificativa,
        dados_pendentes: [...new Set(dadosPendentes)],
        confianca: proposta.confianca,
        pesquisa_preco: pesquisaPreco,
      },
      cotacao_token: cotacaoToken,
      fontes: fontesCotacao,
      similar_interno: similar,
      fiscal_sugerido: fiscal,
      pode_editar_fiscal: podeFiscal,
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Erro inesperado ao gerar sugestão de cadastro.";
    return jsonError(500, message);
  }
}
