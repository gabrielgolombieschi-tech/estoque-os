import { NextRequest, NextResponse } from "next/server";
import type { SupabaseClient } from "@supabase/supabase-js";
import { getAuthSupabase, jsonError, resolveTenantEmpresa } from "@/app/api/compras/_lib";
import {
  asRecord,
  buscarCotacaoCambioPtax,
  calcularPesquisaPreco,
  catalogoNormalizacao,
  caminhoGrupo,
  chaveCodigoCatalogo,
  criarTokenCotacaoAssinada,
  eCodigoComProdutoNaDescricao,
  extrairFontesWeb,
  extrairTextoResposta,
  finalidade,
  fiscalDaLinhaDeNota,
  fiscalDeItemENota,
  grupoParaResposta,
  inteiro,
  normalizarCodigo,
  normalizarQuantidade,
  notaFiscalReferencia,
  padraoCodigoEmDescricaoNota,
  padraoCodigoNotaFiscal,
  parseRespostaJson,
  promptSistemaAgenteCadastro,
  schemaRespostaAgente,
  sanitizarFiscal,
  sanitizarSugestaoModelo,
  selecionarSimilarComConsenso,
  similarDoMesmoCodigo,
  texto,
  tokensFortesDescricao,
  type ConsensoNcm,
  type FiscalSugerido,
  type FonteWeb,
  type FornecedorRow,
  type GrupoRow,
  type NotaFiscalReferencia,
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

type NotaEntradaDbRow = {
  id: number;
  numero: string | null;
  serie: string | null;
  data_emissao: string | null;
  emitente_nome: string | null;
  fornecedor_id: number | null;
  deleted_at: string | null;
};

type NotaItemDbRow = {
  id: number;
  nf_entrada_id: number | null;
  item_id: number | null;
  codigo_fornecedor: string | null;
  descricao: string | null;
  ncm: string | null;
  cfop: string | null;
  aliq_icms: number | null;
  aliq_ipi: number | null;
  aliq_pis: number | null;
  aliq_cofins: number | null;
};

const SELECT_ITEM_SIMILAR =
  "id,codigo_interno,nome,descricao,fornecedor_id,grupo_id,finalidade,motivo_compra_id,preco_unitario,margem_lucro_percentual";

const SELECT_FISCAL_ITEM =
  "ncm,cest,origem,cfop_padrao,cst_icms,cst_pis,cst_cofins,aliq_icms,aliq_ipi,aliq_pis,aliq_cofins,credita_icms,ipi_entra_no_custo,credita_pis,credita_cofins";

// Sem "embed": nf_entrada_itens tem duas chaves estrangeiras para nf_entrada
// (por tenant e por tenant+empresa), e o PostgREST recusa o vínculo ambíguo.
// A nota vem em uma segunda consulta, pelos ids que a primeira devolver.
const SELECT_LINHA_NOTA =
  "id,nf_entrada_id,item_id,codigo_fornecedor,descricao,ncm,cfop,aliq_icms,aliq_ipi,aliq_pis,aliq_cofins";

const SELECT_NOTA = "id,numero,serie,data_emissao,emitente_nome,fornecedor_id,deleted_at";

/** Teto por consulta na nota: o código é seletivo e a rota já espera a IA. */
const LIMITE_LINHAS_NOTA = 40;
/**
 * Teto de candidatos por consulta. O maior grupo da empresa tem 240 itens, e a
 * média é 9: 240 cobre o grupo inteiro sem risco de cortar o melhor candidato.
 */
const LIMITE_CANDIDATOS_SIMILAR = 240;
/** Teto por palavra na varredura do catálogo, para uma palavra genérica não tomar tudo. */
const LIMITE_POR_TOKEN = 80;

// Marketplace generico e otimo para item de consumo e pessimo para material
// eletrico industrial: disjuntor Siemens, borne WAGO ou fonte Phoenix quase nao
// tem anuncio no Mercado Livre nem no eBay, e a pesquisa voltava sem preco. Por
// isso a lista abaixo tem duas partes — os marketplaces, que continuam valendo
// para o que e vendido la, e os distribuidores industriais, que sao onde esse
// tipo de peca realmente aparece com preco publicado.
const DOMINIOS_MARKETPLACE = [
  "mercadolivre.com.br",
  "ebay.com",
  "ebay.com.br",
  "ebay.co.uk",
  "ebay.de",
  "ebay.ca",
  "ebay.com.au",
];

const DOMINIOS_DISTRIBUIDOR_INDUSTRIAL = [
  // Brasil
  "lojaeletrica.com.br",
  "casadoeletricista.com.br",
  "kalatec.com.br",
  "acaotecnica.com.br",
  "eletrozem.com.br",
  "soumaquina.com.br",
  // Distribuidores tecnicos internacionais, onde codigo de fabricante aparece
  // com preco publicado.
  "digikey.com",
  "digikey.com.br",
  "mouser.com",
  "br.mouser.com",
  "rs-online.com",
  "br.rsdelivers.com",
  "farnell.com",
  "newark.com",
  "automation24.com",
  "radwell.com",
];

const DOMINIOS_PESQUISA_MARKETPLACE = [...DOMINIOS_MARKETPLACE, ...DOMINIOS_DISTRIBUIDOR_INDUSTRIAL];

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
      // Sem enum de proposito: agora tambem vale distribuidor tecnico, e o
      // servidor reescreve este campo a partir do dominio da URL
      // (marketplaceDaFonte). O que o modelo escreve aqui e so indicativo.
      marketplace: { type: ["string", "null"] },
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

function hostDaUrl(url: string | null): string {
  if (!url) return "";
  try {
    return new URL(url).hostname.toLowerCase();
  } catch {
    return "";
  }
}

/**
 * Fonte que publica preco de venda, em oposicao a pagina tecnica do fabricante.
 * Antes so valia Mercado Livre e eBay, e por isso peca industrial voltava sem
 * preco: distribuidor tecnico nao era aceito nem quando trazia o codigo exato
 * com valor na tela. A checagem e pelo host da URL, que o servidor ja resolve,
 * e nao pelo nome que o modelo escreveu.
 */
function eFonteDePreco(pesquisa: Pick<PesquisaPreco, "marketplace" | "fonte_url">): boolean {
  if (pesquisa.marketplace === "Mercado Livre" || pesquisa.marketplace === "eBay") return true;
  const host = hostDaUrl(pesquisa.fonte_url);
  if (!host) return false;
  return DOMINIOS_DISTRIBUIDOR_INDUSTRIAL.some((dominio) => host === dominio || host.endsWith(`.${dominio}`));
}

function devePesquisarMarketplaces(pesquisa: PesquisaPreco): boolean {
  return pesquisa.status !== "encontrado" || !eFonteDePreco(pesquisa);
}

function deveUsarPesquisaMarketplace(atual: PesquisaPreco, candidata: PesquisaPreco): boolean {
  if (candidata.preco_origem == null || !candidata.fonte_url) return false;
  if (atual.preco_origem == null || !atual.fonte_url) return true;
  if (candidata.status === "encontrado" && atual.status !== "encontrado") return true;
  if (candidata.tipo_correspondencia === "exato" && atual.tipo_correspondencia !== "exato") return true;
  return candidata.status === "encontrado" && eFonteDePreco(candidata) && !eFonteDePreco(atual);
}

async function complementarCotacaoComPtax(input: {
  pesquisa: PesquisaPreco;
  pesquisaBruta: PesquisaPrecoBruta;
  fontes: FonteWeb[];
}): Promise<{ pesquisa: PesquisaPrecoBruta; fontes: FonteWeb[] } | null> {
  if (
    !eFonteDePreco(input.pesquisa) ||
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
              "Você é o pesquisador de preço do ERP. Use obrigatoriamente a pesquisa web e procure o código exato primeiro no Mercado Livre Brasil e no eBay e, para material elétrico e de automação industrial, também nos distribuidores técnicos liberados (Digi-Key, Mouser, RS, Farnell, Newark, Automation24, Radwell e as lojas elétricas brasileiras). Peça industrial raramente tem anúncio em marketplace de consumo: nesses casos o distribuidor técnico é a fonte esperada. Faça consultas com o código informado e com o código normalizado; só use item similar quando o código exato não retornar anúncio. Uma página técnica do fabricante não é fonte de preço. Se houver anúncio de marketplace com preço visível, ele deve ser preferido. Retorne somente um JSON estruturado. fonte_url deve ser a URL exata de uma fonte devolvida pela ferramenta; preco_origem deve ser o número visto no anúncio, sem conversão. marketplace deve identificar a loja da fonte (Mercado Livre, eBay ou o distribuidor técnico); o servidor confere pelo domínio da URL. Não pesquise nem estime câmbio nesta etapa: quando a moeda não for BRL, mantenha preco_origem e moeda do anúncio e preencha taxa_cambio_brl, fonte_cambio_url e data_cambio com null. O servidor consulta a PTAX do Banco Central separadamente. Sem anúncio com preço visível, use preco_origem null e explique em observacao.",
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

type CadastroExistente = {
  status: "ativo" | "inativo";
  item: { id: number; codigo_interno: string; nome: string; ativo: boolean; fornecedor_id: number | null };
};

function escolherCadastro(rows: ItemDuplicado[], codigo: string): CadastroExistente | null {
  const ativo = rows.find((row) => row.ativo !== false) ?? null;
  const item = ativo ?? rows.find((row) => row.ativo === false) ?? null;
  if (!item) return null;
  return {
    status: ativo ? "ativo" : "inativo",
    item: {
      id: Number(item.id),
      codigo_interno: String(item.codigo_interno ?? codigo),
      nome: String(item.nome ?? ""),
      ativo: item.ativo !== false,
      fornecedor_id: item.fornecedor_id == null ? null : Number(item.fornecedor_id),
    },
  };
}

/**
 * Procura o código já cadastrado, em qualquer fornecedor.
 *
 * O bloqueio continua valendo só para o mesmo fornecedor com o mesmo código,
 * como antes. Em outro fornecedor o cadastro não bloqueia: ele aparece como
 * aviso, porque a pessoa está recadastrando o catálogo e precisa ver que a
 * peça já existe — e, de quebra, é a melhor referência fiscal possível.
 *
 * A comparação é normalizada (chaveCodigoCatalogo), porque o mesmo código está
 * na base com e sem separador: "CP1H-EX40DT-D" e "CP1HEX40DTD".
 */
async function localizarCadastroExistente(input: {
  supabase: SupabaseClient;
  tenantId: string;
  empresaId: string;
  fornecedorId: number;
  codigo: string;
}): Promise<{ duplicidade: CadastroExistente | null; outroFornecedor: CadastroExistente | null }> {
  const chave = chaveCodigoCatalogo(input.codigo);
  const padrao = padraoCodigoNotaFiscal(chave);
  if (!padrao) return { duplicidade: null, outroFornecedor: null };

  const { data, error } = await input.supabase
    .from("itens")
    .select("id,codigo_interno,nome,ativo,fornecedor_id")
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .regexIMatch("codigo_interno", padrao)
    .order("ativo", { ascending: false })
    .limit(20);
  if (error) throw new Error(error.message);
  const rows = ((data ?? []) as unknown as ItemDuplicado[]).filter(
    (row) => chaveCodigoCatalogo(row.codigo_interno) === chave
  );

  return {
    duplicidade: escolherCadastro(
      rows.filter((row) => Number(row.fornecedor_id) === input.fornecedorId),
      input.codigo
    ),
    outroFornecedor: escolherCadastro(
      rows.filter((row) => Number(row.fornecedor_id) !== input.fornecedorId),
      input.codigo
    ),
  };
}

async function nomeDoFornecedor(input: {
  supabase: SupabaseClient;
  tenantId: string;
  empresaId: string;
  fornecedorId: number | null;
}): Promise<string | null> {
  if (!input.fornecedorId) return null;
  const { data, error } = await input.supabase
    .from("fornecedores")
    .select("nome")
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .eq("id", input.fornecedorId)
    .maybeSingle();
  if (error) return null;
  return texto((data as { nome?: unknown } | null)?.nome, 160);
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

type ContextoBusca = {
  supabase: SupabaseClient;
  tenantId: string;
  empresaId: string;
};

/**
 * Linhas de nota de entrada cujo texto bate com o padrão do código.
 *
 * O padrão vem de chaveCodigoCatalogo, então tolera zeros à esquerda e
 * separadores; a conferência exata continua no JavaScript, porque o SQL aqui
 * serve só para reduzir as linhas trazidas. Um perfil sem leitura de nota
 * fiscal simplesmente não recebe linha nenhuma, e a sugestão segue sem isso.
 */
async function linhasDeNotaPorPadrao(
  input: ContextoBusca & { coluna: "codigo_fornecedor" | "descricao"; padrao: string }
): Promise<NotaItemDbRow[]> {
  const { data, error } = await input.supabase
    .from("nf_entrada_itens")
    .select(SELECT_LINHA_NOTA)
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .regexIMatch(input.coluna, input.padrao)
    .order("id", { ascending: false })
    .limit(LIMITE_LINHAS_NOTA);
  if (error) return [];
  return (data ?? []) as unknown as NotaItemDbRow[];
}

/** Notas de entrada ainda válidas, indexadas por id. */
async function carregarNotas(input: ContextoBusca & { ids: number[] }): Promise<Map<number, NotaEntradaDbRow>> {
  if (input.ids.length === 0) return new Map();
  const { data, error } = await input.supabase
    .from("nf_entrada")
    .select(SELECT_NOTA)
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .in("id", input.ids)
    .is("deleted_at", null);
  if (error) return new Map();
  const notas = new Map<number, NotaEntradaDbRow>();
  for (const row of (data ?? []) as unknown as NotaEntradaDbRow[]) notas.set(Number(row.id), row);
  return notas;
}

/** NCM já cadastrado de cada item, para reforçar a escolha e medir o consenso. */
async function ncmPorItem(input: ContextoBusca & { ids: number[] }): Promise<Map<number, string>> {
  if (input.ids.length === 0) return new Map();
  const { data, error } = await input.supabase
    .from("fiscal_itens")
    .select("item_id,ncm")
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .in("item_id", input.ids)
    .not("ncm", "is", null);
  if (error) return new Map();
  const mapa = new Map<number, string>();
  for (const row of (data ?? []) as unknown as { item_id: number; ncm: string | null }[]) {
    const ncm = texto(row.ncm, 12);
    if (ncm) mapa.set(Number(row.item_id), ncm);
  }
  return mapa;
}

async function itensComFiscalNcm(input: ContextoBusca & { ids: number[] }): Promise<Set<number>> {
  return new Set((await ncmPorItem(input)).keys());
}

async function itensJaRecebidosPorNota(input: ContextoBusca & { ids: number[] }): Promise<Set<number>> {
  if (input.ids.length === 0) return new Set();
  const { data, error } = await input.supabase
    .from("nf_entrada_itens")
    .select("item_id")
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .in("item_id", input.ids)
    .limit(1000);
  if (error) return new Set();
  return new Set((data ?? []).map((row) => Number((row as { item_id: number }).item_id)));
}

/**
 * Procura o mesmo código do fabricante nas notas de entrada já importadas.
 *
 * É a correspondência mais forte do agente: se o código já entrou por nota, o
 * NCM e os impostos daquela linha são os do produto, e não uma aproximação por
 * palavras. A descrição da nota é só o segundo caminho, para o emitente que
 * não preenche o código do produto.
 */
async function buscarLinhaDeNotaPorCodigo(
  input: ContextoBusca & { codigo: string }
): Promise<{ linha: NotaItemDbRow; nota: NotaFiscalReferencia } | null> {
  const chave = chaveCodigoCatalogo(input.codigo);
  const padraoCodigo = padraoCodigoNotaFiscal(chave);
  if (!padraoCodigo) return null;

  const contexto = { supabase: input.supabase, tenantId: input.tenantId, empresaId: input.empresaId };
  let candidatas = (await linhasDeNotaPorPadrao({ ...contexto, coluna: "codigo_fornecedor", padrao: padraoCodigo }))
    .filter((linha) => chaveCodigoCatalogo(linha.codigo_fornecedor) === chave);

  if (candidatas.length === 0) {
    const padraoDescricao = padraoCodigoEmDescricaoNota(chave);
    if (padraoDescricao) {
      candidatas = (await linhasDeNotaPorPadrao({ ...contexto, coluna: "descricao", padrao: padraoDescricao }))
        .filter((linha) => eCodigoComProdutoNaDescricao(chave, String(linha.descricao ?? "")));
    }
  }
  if (candidatas.length === 0) return null;

  // Nota excluída não vale como referência fiscal.
  const notas = await carregarNotas({
    ...contexto,
    ids: [...new Set(candidatas.map((linha) => inteiro(linha.nf_entrada_id)).filter((id): id is number => id !== null))],
  });
  candidatas = candidatas.filter((linha) => notas.has(Number(linha.nf_entrada_id)));
  if (candidatas.length === 0) return null;

  const idsDeItem = [...new Set(candidatas.map((linha) => inteiro(linha.item_id)).filter((id): id is number => id !== null))];
  const comFiscal = await itensComFiscalNcm({ ...contexto, ids: idsDeItem });
  // Preferência pedida: item que já tem fiscal cadastrado e, entre eles, a nota
  // mais recente. O id desempata porque é sequencial na importação.
  const peso = (linha: NotaItemDbRow) => (linha.item_id && comFiscal.has(Number(linha.item_id)) ? 2 : linha.item_id ? 1 : 0);
  const emissao = (linha: NotaItemDbRow) =>
    Date.parse(String(notas.get(Number(linha.nf_entrada_id))?.data_emissao ?? "")) || 0;
  const escolhida = [...candidatas].sort(
    (a, b) => peso(b) - peso(a) || emissao(b) - emissao(a) || Number(b.id) - Number(a.id)
  )[0];

  const nota = notas.get(Number(escolhida.nf_entrada_id)) ?? null;
  return {
    linha: escolhida,
    nota: notaFiscalReferencia({
      nfEntradaId: escolhida.nf_entrada_id ?? nota?.id,
      nfEntradaItemId: escolhida.id,
      numero: nota?.numero,
      serie: nota?.serie,
      dataEmissao: nota?.data_emissao,
      emitenteNome: nota?.emitente_nome,
      fornecedorId: nota?.fornecedor_id,
      codigoFornecedor: escolhida.codigo_fornecedor,
      descricao: escolhida.descricao,
      itemId: escolhida.item_id,
    }),
  };
}

async function carregarItemPorId(input: ContextoBusca & { itemId: number }) {
  const { data, error } = await input.supabase
    .from("itens")
    .select(`${SELECT_ITEM_SIMILAR},ativo`)
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .eq("id", input.itemId)
    .maybeSingle();
  if (error) return null;
  return (data ?? null) as unknown as (SimilarDbRow & { ativo: boolean | null }) | null;
}

async function carregarFiscalDoItem(input: ContextoBusca & { itemId: number }): Promise<FiscalDbRow | null> {
  const { data, error } = await input.supabase
    .from("fiscal_itens")
    .select(SELECT_FISCAL_ITEM)
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .eq("item_id", input.itemId)
    .maybeSingle();
  if (error) return null;
  return (data ?? null) as unknown as FiscalDbRow | null;
}

/** Itens ativos de um grupo — o grupo é a definição de "tipo de produto" do ERP. */
async function candidatosDoGrupo(input: ContextoBusca & { grupoId: number }): Promise<SimilarDbRow[]> {
  const { data, error } = await input.supabase
    .from("itens")
    .select(SELECT_ITEM_SIMILAR)
    .eq("tenant_id", input.tenantId)
    .eq("empresa_id", input.empresaId)
    .eq("ativo", true)
    .eq("grupo_id", input.grupoId)
    .limit(LIMITE_CANDIDATOS_SIMILAR);
  if (error) throw new Error(error.message);
  return (data ?? []) as unknown as SimilarDbRow[];
}

/**
 * Itens do mesmo tipo em TODO o catálogo da empresa, sem restringir fornecedor.
 *
 * Uma consulta por palavra forte, em paralelo, cada uma com teto próprio: assim
 * uma palavra genérica não consome sozinha o orçamento de linhas e o CLP Omron
 * novo enxerga o CLP Siemens já cadastrado. Trazer o catálogo inteiro seria
 * possível (são poucos milhares de itens), mas cresce sem limite e não é
 * necessário — a palavra do tipo do produto já reduz para dezenas.
 */
async function candidatosPorTokens(input: ContextoBusca & { tokensFortes: string[] }): Promise<SimilarDbRow[]> {
  if (input.tokensFortes.length === 0) return [];
  const buscas = input.tokensFortes.map(async (token) => {
    const { data, error } = await input.supabase
      .from("itens")
      .select(SELECT_ITEM_SIMILAR)
      .eq("tenant_id", input.tenantId)
      .eq("empresa_id", input.empresaId)
      .eq("ativo", true)
      .ilike("nome", `%${token.replace(/[%_\\]/g, "")}%`)
      .limit(LIMITE_POR_TOKEN);
    if (error) return [];
    return (data ?? []) as unknown as SimilarDbRow[];
  });
  return (await Promise.all(buscas)).flat();
}

/**
 * Item do mesmo tipo de produto, no catálogo inteiro da empresa.
 *
 * O grupo vem primeiro, porque é a classificação que a empresa mantém. Quando
 * o grupo é novo, ausente, ou nenhum item dele tem NCM, a busca se abre para o
 * catálogo pelas palavras fortes da descrição — é assim que um CLP de uma marca
 * copia o NCM de um CLP de outra marca.
 */
async function buscarSimilarPorDescricao(
  input: ContextoBusca & {
    fornecedorId: number;
    codigo: string;
    descricao: string;
    fabricante: string | null;
    grupoId: number | null;
  }
): Promise<{
  similar: SimilarInterno | null;
  consenso: ConsensoNcm | null;
  referenciaNcm: { id: number; codigo_interno: string } | null;
}> {
  const contexto = { supabase: input.supabase, tenantId: input.tenantId, empresaId: input.empresaId };
  const chaveCodigo = chaveCodigoCatalogo(input.codigo);
  const semOProprioItem = (linhas: SimilarDbRow[]) =>
    linhas.filter((row) => chaveCodigoCatalogo(row.codigo_interno) !== chaveCodigo);

  const porGrupo = input.grupoId
    ? semOProprioItem(await candidatosDoGrupo({ ...contexto, grupoId: input.grupoId }))
    : [];
  const ncmDoGrupo = await ncmPorItem({ ...contexto, ids: porGrupo.map((row) => Number(row.id)) });

  const candidatosPorId = new Map<number, SimilarDbRow>();
  for (const row of porGrupo) candidatosPorId.set(Number(row.id), row);
  const ncms = new Map(ncmDoGrupo);

  // Sem grupo, ou com um grupo que ainda não tem NCM nenhum, vale abrir para o
  // catálogo: o objetivo é achar de quem copiar o NCM.
  if (ncmDoGrupo.size === 0) {
    const porTokens = semOProprioItem(
      await candidatosPorTokens({ ...contexto, tokensFortes: tokensFortesDescricao(input.descricao, 3) })
    ).filter((row) => !candidatosPorId.has(Number(row.id)));
    for (const row of porTokens) candidatosPorId.set(Number(row.id), row);
    const ncmDosTokens = await ncmPorItem({ ...contexto, ids: porTokens.map((row) => Number(row.id)) });
    for (const [id, ncm] of ncmDosTokens) ncms.set(id, ncm);
  }

  const candidatos = [...candidatosPorId.values()];
  if (candidatos.length === 0) return { similar: null, consenso: null, referenciaNcm: null };

  const itensComNota = await itensJaRecebidosPorNota({ ...contexto, ids: candidatos.map((row) => Number(row.id)) });
  return selecionarSimilarComConsenso({
    descricao: input.descricao,
    grupoId: input.grupoId,
    fornecedorId: input.fornecedorId,
    candidatos,
    fabricante: input.fabricante,
    itensComNota,
    ncmPorItem: ncms,
  });
}

/**
 * Ordem de escolha:
 * 1. o próprio item já cadastrado com o mesmo código em outro fornecedor — é o
 *    produto, então o cadastro fiscal dele é o certo;
 * 2. mesmo código do fabricante já recebido por nota de entrada — o fiscal sai
 *    do item vinculado a essa linha e o que faltar vem da própria nota;
 * 3. sem código igual, um item do mesmo TIPO no catálogo inteiro da empresa
 *    (qualquer fornecedor), preferindo quem já tem NCM e o NCM em que os itens
 *    do tipo concordam.
 *
 * Em qualquer caminho, a linha de nota encontrada completa o que o cadastro
 * fiscal do item de referência não tiver.
 */
async function buscarSimilarEFiscal(input: {
  supabase: SupabaseClient;
  tenantId: string;
  empresaId: string;
  fornecedorId: number;
  codigo: string;
  descricao: string;
  fabricante: string | null;
  grupoId: number | null;
  podeFiscal: boolean;
  /** Item já cadastrado com o mesmo código em outro fornecedor, se houver. */
  cadastroEmOutroFornecedor: CadastroExistente | null;
  fornecedorDoCadastro: string | null;
}): Promise<{ similar: SimilarInterno | null; fiscal: FiscalSugerido | null }> {
  const contexto = { supabase: input.supabase, tenantId: input.tenantId, empresaId: input.empresaId };
  const referenciaNota = await buscarLinhaDeNotaPorCodigo({ ...contexto, codigo: input.codigo });

  const itemDaNota =
    referenciaNota?.linha.item_id != null
      ? await carregarItemPorId({ ...contexto, itemId: Number(referenciaNota.linha.item_id) })
      : null;
  const itemJaCadastrado = input.cadastroEmOutroFornecedor
    ? await carregarItemPorId({ ...contexto, itemId: input.cadastroEmOutroFornecedor.item.id })
    : null;

  // O mesmo código já cadastrado é a referência mais direta; a nota vem logo
  // atrás. Só um item ativo vira referência comercial, mas o cadastro fiscal de
  // um item inativo continua valendo para o mesmo código.
  const itemDoMesmoCodigo = itemJaCadastrado ?? itemDaNota;
  let similar: SimilarInterno | null = null;
  let consenso: ConsensoNcm | null = null;
  let referenciaNcm: { id: number; codigo_interno: string } | null = null;

  if (itemDoMesmoCodigo && itemDoMesmoCodigo.ativo !== false) {
    similar = itemJaCadastrado
      ? similarDoMesmoCodigo(itemJaCadastrado, {
          origem: "codigo_cadastrado",
          nota: referenciaNota?.nota ?? null,
          fornecedorNome: input.fornecedorDoCadastro,
        })
      : similarDoMesmoCodigo(itemDoMesmoCodigo, {
          origem: "codigo_nota_fiscal",
          nota: referenciaNota?.nota ?? null,
        });
  } else {
    const porTipo = await buscarSimilarPorDescricao({
      ...contexto,
      fornecedorId: input.fornecedorId,
      codigo: input.codigo,
      descricao: input.descricao,
      fabricante: input.fabricante,
      grupoId: input.grupoId,
    });
    similar = porTipo.similar;
    consenso = porTipo.consenso;
    referenciaNcm = porTipo.referenciaNcm;
  }

  if (!input.podeFiscal) return { similar, fiscal: null };

  // Item de referência do fiscal: o do mesmo código quando existe (mesmo
  // inativo), senão o item do mesmo tipo escolhido pela descrição.
  const itemFiscal = itemDoMesmoCodigo ?? null;
  const referenciaItemId = itemFiscal ? Number(itemFiscal.id) : similar?.id ?? null;
  const referenciaItemCodigo = itemFiscal?.codigo_interno ?? similar?.codigo_interno ?? null;
  const fiscalItem = referenciaItemId ? await carregarFiscalDoItem({ ...contexto, itemId: referenciaItemId }) : null;

  // Nenhum item virou referência fiscal, mas os itens do mesmo tipo concordam
  // num NCM: é o que a pessoa precisa ao recadastrar o catálogo. Só o NCM é
  // aproveitado — alíquotas dependem da operação e não se copiam por tipo.
  if (!sanitizarFiscal(fiscalItem) && !referenciaNota && consenso && referenciaNcm) {
    return {
      similar,
      fiscal: fiscalDeItemENota({
        fiscalItem: { ncm: consenso.ncm },
        referenciaItemId: referenciaNcm.id,
        referenciaItemCodigo: referenciaNcm.codigo_interno || null,
        consensoNcm: consenso,
        apenasNcmDoConsenso: true,
      }),
    };
  }

  if (!fiscalItem && !referenciaNota) return { similar, fiscal: null };

  return {
    similar,
    fiscal: fiscalDeItemENota({
      fiscalItem,
      referenciaItemId,
      referenciaItemCodigo: referenciaItemCodigo || null,
      linhaNota: referenciaNota ? fiscalDaLinhaDeNota(referenciaNota.linha) : undefined,
      nota: referenciaNota?.nota ?? null,
      consensoNcm: consenso,
    }),
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

    const { duplicidade, outroFornecedor } = await localizarCadastroExistente({
      supabase: auth.supabase,
      tenantId: ctx.tenantId,
      empresaId: ctx.empresaId,
      fornecedorId,
      codigo,
    });

    // O mesmo código em OUTRO fornecedor não bloqueia: a pessoa está
    // recadastrando o catálogo e precisa ver que a peça já existe para decidir.
    const fornecedorDoCadastro = await nomeDoFornecedor({
      supabase: auth.supabase,
      tenantId: ctx.tenantId,
      empresaId: ctx.empresaId,
      fornecedorId: outroFornecedor?.item.fornecedor_id ?? null,
    });
    const jaCadastradoEmOutroFornecedor = outroFornecedor
      ? {
          id: outroFornecedor.item.id,
          codigo: outroFornecedor.item.codigo_interno,
          nome: outroFornecedor.item.nome,
          ativo: outroFornecedor.item.ativo,
          status: outroFornecedor.status,
          fornecedor_id: outroFornecedor.item.fornecedor_id,
          fornecedor_nome: fornecedorDoCadastro,
          mensagem: `Esta peça já está cadastrada como ${outroFornecedor.item.codigo_interno}${
            fornecedorDoCadastro ? ` no fornecedor ${fornecedorDoCadastro}` : " em outro fornecedor"
          }${outroFornecedor.status === "inativo" ? " (cadastro inativo)" : ""}.`,
        }
      : null;

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
        ja_cadastrado_em_outro_fornecedor: jaCadastradoEmOutroFornecedor,
        sugestao: null,
        fontes: [],
        similar_interno: null,
        fiscal_sugerido: null,
        pode_editar_fiscal: false,
      });
    }

    const apiKey = String(process.env.OPENAI_API_KEY ?? process.env.ASSISTENTE_IA_OPENAI_API_KEY ?? "").trim();
    if (!apiKey) return jsonError(503, "OPENAI_API_KEY não configurada para o agente de cadastro.");
    // Variavel propria: o agente de cadastro justifica um modelo caro, porque a
    // descricao vai para o cadastro definitivo do item. O assistente de
    // orcamento roda em volume muito maior e continua na variavel dele — antes
    // as duas rotas liam ASSISTENTE_IA_OPENAI_MODEL e subir o modelo aqui
    // subia o custo la sem ninguem pedir.
    const model = String(
      process.env.AGENTE_CADASTRO_OPENAI_MODEL ?? process.env.ASSISTENTE_IA_OPENAI_MODEL ?? "gpt-5.4-mini"
    ).trim();

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
              "Protocolo obrigatório de pesquisa: antes de responder, reconheça tecnicamente o código em fonte técnica e pesquise também o mesmo código no Mercado Livre Brasil, no eBay e nos distribuidores técnicos liberados, que costumam ser a única fonte com preço para material industrial. Execute consultas com o código informado e com a forma normalizada, inclusive sem separadores visuais. Não encerre a cotação com apenas uma página do fabricante sem preço se a pesquisa retornar anúncio de marketplace. Para pesquisa_preco, priorize anúncio de código exato com preço visível; use similar somente quando o exato não existir e declare isso. fonte, titulo, fonte_url, moeda e preco_origem devem corresponder ao anúncio concreto retornado pela ferramenta. O marketplace é identificado pela URL e será validado pelo servidor. Em preço estrangeiro, pesquise uma cotação BRL verificável e informe taxa_cambio_brl, fonte_cambio_url e data_cambio em AAAA-MM-DD; não estime câmbio. A conversão e o acréscimo de importação do eBay são calculados exclusivamente pelo servidor.",
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
      fabricante: proposta.fabricante_sugerido,
      grupoId: proposta.grupo_id,
      podeFiscal,
      cadastroEmOutroFornecedor: outroFornecedor,
      fornecedorDoCadastro,
    });

    // Este fluxo inicia todo novo item como matéria-prima; a revisão humana pode alterar depois.
    const finalidadeFinal = "materia_prima";
    const motivoCompraId = fornecedor.motivo_compra_padrao_id ?? similar?.motivo_compra_id ?? null;
    const dadosPendentes = [...proposta.dados_pendentes];
    if (!proposta.descricao_padronizada) dadosPendentes.push("O agente não retornou uma descrição segura; revise antes de confirmar.");
    if (!proposta.grupo_id && !proposta.novo_grupo) dadosPendentes.push("Nenhum grupo adequado foi identificado; selecione ou proponha um grupo antes de confirmar.");
    if (pesquisaPreco.status !== "encontrado") dadosPendentes.push("A referência de preço ainda precisa de validação humana.");
    if (!podeFiscal) dadosPendentes.push("Você não possui permissão para gravar dados fiscais neste cadastro.");
    // O CFOP da nota é o da operação do emitente; serve de ponto de partida,
    // mas quem confirma precisa saber que aquele número não veio do cadastro.
    if (fiscal?.campos_da_nota.includes("cfop_padrao")) {
      dadosPendentes.push("O CFOP padrão foi copiado da nota de entrada (operação do emitente); confira antes de confirmar.");
    }
    if (jaCadastradoEmOutroFornecedor) dadosPendentes.push(jaCadastradoEmOutroFornecedor.mensagem);

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
      ja_cadastrado_em_outro_fornecedor: jaCadastradoEmOutroFornecedor,
      sugestao: {
        codigo,
        descricao_padronizada: proposta.descricao_padronizada,
        fabricante: proposta.fabricante_sugerido,
        modelo_referencia: proposta.modelo_referencia,
        unidade_medida: proposta.unidade_medida ?? "UN",
        unidade_compra: proposta.unidade_compra,
        fator_conversao_estoque: proposta.fator_conversao_estoque,
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
