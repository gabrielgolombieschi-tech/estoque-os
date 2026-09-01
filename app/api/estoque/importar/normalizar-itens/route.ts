import { readFile } from "node:fs/promises";
import path from "node:path";
import { NextRequest, NextResponse } from "next/server";
import { getAuthSupabase, jsonError, resolveTenantEmpresa } from "@/app/api/compras/_lib";
import { supabaseAdmin } from "@/lib/supabase/admin";
import {
  aplicarCorrecoesExatas,
  erroTabelaCorrecaoAusente,
  normalizarDescricaoAprendizado,
  type CorrecaoDescricaoAgente,
} from "@/lib/nfe/descricaoCorrecaoIa";

export const runtime = "nodejs";

type ItemEntrada = {
  codigo: string;
  descricao_nf: string;
  ncm?: string | null;
  unidade?: string | null;
  informacoes_adicionais?: string | null;
};

type GrupoRow = {
  id: number;
  codigo: string | null;
  nome: string | null;
  grupo_pai_id: number | null;
};

type CorrecaoDescricaoRow = CorrecaoDescricaoAgente & {
  updated_at: string;
};

type SugestaoModelo = {
  codigo: string;
  descricao_padronizada: string;
  grupo_id: number | null;
  novo_grupo: NovoGrupoModelo | null;
  justificativa: string;
  dados_pendentes: string[];
  confianca: "alta" | "media" | "baixa";
};

type NovoGrupoModelo = {
  codigo: string;
  nome: string;
  grupo_pai_id: number | null;
  justificativa: string;
};

let catalogoCache: string | null = null;

function normalizarCodigo(value: unknown) {
  return String(value ?? "")
    .trim()
    .replace(/^0+(?=\d)/, "")
    .toUpperCase();
}

function normalizarCodigoGrupo(value: unknown) {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 80);
}

function texto(value: unknown, max = 800): string | null {
  const result = String(value ?? "").trim().replace(/\s+/g, " ");
  return result ? result.slice(0, max) : null;
}

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function correcoesLocais(value: unknown): CorrecaoDescricaoAgente[] {
  return (Array.isArray(value) ? value : [])
    .slice(0, 100)
    .map((raw): CorrecaoDescricaoAgente | null => {
      const row = record(raw);
      const descricaoOrigem = texto(row?.descricao_origem, 500);
      const descricaoCorrigida = texto(row?.descricao_corrigida, 300);
      const descricaoOrigemNormalizada = normalizarDescricaoAprendizado(descricaoOrigem);
      if (!descricaoOrigem || !descricaoCorrigida || !descricaoOrigemNormalizada) return null;
      return {
        descricao_origem: descricaoOrigem,
        descricao_origem_normalizada: descricaoOrigemNormalizada,
        descricao_corrigida: descricaoCorrigida,
      };
    })
    .filter((row): row is CorrecaoDescricaoAgente => Boolean(row));
}

function extrairTextoResposta(value: unknown): string {
  const body = record(value);
  if (!body) return "";
  if (typeof body.output_text === "string") return body.output_text;

  const partes: string[] = [];
  for (const output of Array.isArray(body.output) ? body.output : []) {
    const outputRecord = record(output);
    for (const content of Array.isArray(outputRecord?.content) ? outputRecord.content : []) {
      const contentRecord = record(content);
      if (typeof contentRecord?.text === "string") partes.push(contentRecord.text);
    }
  }
  return partes.join("\n").trim();
}

async function catalogoNormalizacao() {
  if (catalogoCache) return catalogoCache;
  const arquivo = path.join(process.cwd(), "docs", "padroes-cadastro", "catalogo-paineis-eletricos.yaml");
  const yaml = await readFile(arquivo, "utf8");
  const inicioHistorico = yaml.indexOf("\nhistorico_decisoes:");
  catalogoCache = inicioHistorico >= 0 ? yaml.slice(0, inicioHistorico) : yaml;
  return catalogoCache;
}

function schemaResposta() {
  return {
    type: "object",
    additionalProperties: false,
    required: ["sugestoes"],
    properties: {
      sugestoes: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["codigo", "descricao_padronizada", "grupo_id", "novo_grupo", "justificativa", "dados_pendentes", "confianca"],
          properties: {
            codigo: { type: "string" },
            descricao_padronizada: { type: "string" },
            grupo_id: { type: ["integer", "null"] },
            novo_grupo: {
              anyOf: [
                { type: "null" },
                {
                  type: "object",
                  additionalProperties: false,
                  required: ["codigo", "nome", "grupo_pai_id", "justificativa"],
                  properties: {
                    codigo: { type: "string" },
                    nome: { type: "string" },
                    grupo_pai_id: { type: ["integer", "null"] },
                    justificativa: { type: "string" },
                  },
                },
              ],
            },
            justificativa: { type: "string" },
            dados_pendentes: { type: "array", items: { type: "string" } },
            confianca: { type: "string", enum: ["alta", "media", "baixa"] },
          },
        },
      },
    },
  };
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
    if (!podeCadastrar) return jsonError(403, "Sem permissao para cadastrar itens.");

    const itens = (Array.isArray(body.itens) ? body.itens : [])
      .map((raw): ItemEntrada | null => {
        const item = record(raw);
        const codigo = normalizarCodigo(item?.codigo);
        const descricaoNf = texto(item?.descricao_nf);
        if (!codigo || !descricaoNf) return null;
        return {
          codigo,
          descricao_nf: descricaoNf,
          ncm: texto(item?.ncm, 20),
          unidade: texto(item?.unidade, 30),
          informacoes_adicionais: texto(item?.informacoes_adicionais),
        };
      })
      .filter((item): item is ItemEntrada => Boolean(item));

    if (itens.length === 0) return jsonError(400, "Informe ao menos um item valido para normalizar.");
    if (itens.length > 20) return jsonError(400, "Envie no maximo 20 itens por solicitacao.");

    const admin = supabaseAdmin();
    const { data: gruposData, error: gruposError } = await admin
      .from("item_grupos")
      .select("id,codigo,nome,grupo_pai_id")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .order("nome", { ascending: true });
    if (gruposError) return jsonError(400, gruposError.message);

    const grupos = (gruposData ?? []) as GrupoRow[];
    if (grupos.length === 0) return jsonError(422, "Nao ha grupos cadastrados para esta empresa.");

    const { data: correcoesData, error: correcoesError } = await admin
      .from("parametro_importacao_xml_descricao_ia")
      .select("descricao_origem,descricao_origem_normalizada,descricao_corrigida,updated_at")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .eq("ativo", true)
      .is("deleted_at", null)
      .order("updated_at", { ascending: false })
      .limit(100);
    const tabelaCorrecaoAusente = erroTabelaCorrecaoAusente(correcoesError);
    if (correcoesError && !tabelaCorrecaoAusente) return jsonError(400, correcoesError.message);
    const correcoesBanco = ((correcoesData ?? []) as CorrecaoDescricaoRow[]).filter(
      (correcao) =>
        Boolean(correcao.descricao_origem_normalizada) && Boolean(String(correcao.descricao_corrigida ?? "").trim())
    );
    const correcoesPorOrigem = new Map<string, CorrecaoDescricaoAgente>();
    for (const correcao of correcoesBanco) correcoesPorOrigem.set(correcao.descricao_origem_normalizada, correcao);
    for (const correcao of correcoesLocais(body.correcoes_descricao_locais)) {
      correcoesPorOrigem.set(correcao.descricao_origem_normalizada, correcao);
    }
    const correcoes = [...correcoesPorOrigem.values()];

    const porId = new Map(grupos.map((grupo) => [Number(grupo.id), grupo]));
    const gruposParaAgente = grupos.map((grupo) => {
      const pai = grupo.grupo_pai_id ? porId.get(Number(grupo.grupo_pai_id)) : null;
      return {
        id: Number(grupo.id),
        codigo: String(grupo.codigo ?? ""),
        nome: String(grupo.nome ?? ""),
        caminho: pai ? `${pai.nome ?? ""} > ${grupo.nome ?? ""}` : String(grupo.nome ?? ""),
      };
    });

    const apiKey = String(process.env.OPENAI_API_KEY ?? process.env.ASSISTENTE_IA_OPENAI_API_KEY ?? "").trim();
    if (!apiKey) return jsonError(503, "OPENAI_API_KEY nao configurada para o agente de cadastro.");
    const model = String(process.env.ASSISTENTE_IA_OPENAI_MODEL ?? "gpt-5.4-mini").trim();

    const catalogo = await catalogoNormalizacao();
    const system = [
      "Você é o Agente de Normalização de Cadastro de Produtos do ERP.",
      "Sua função é sugerir cadastro de itens vindos de NF-e. Você nunca cadastra no banco e nunca decide sozinho: a pessoa usuária confirma a sugestão antes da gravação.",
      "Interprete o material tecnicamente; não copie automaticamente a descrição da nota.",
      "Não invente especificações. Quando faltar informação, registre em dados_pendentes e reduza a confiança.",
      "Nunca inclua fabricante, marca, código do produto ou modelo na descrição padronizada. Exceção: uma família técnica pode aparecer somente quando for indispensável para compatibilidade e estiver explícita na NF.",
      "Mantenha número e unidade juntos, como 24VCC, 400A, 500VCA e 6kA.",
      "Escolha grupo_id exclusivamente dentre os grupos recebidos quando existir grupo funcional adequado. Não use um grupo apenas parecido: cabo de rede não é conector, módulo SFP não é switch e conector não é cabo.",
      "Quando não houver grupo funcional adequado, use grupo_id nulo e preencha novo_grupo com um grupo simples, reutilizável e tecnicamente claro. O codigo do novo grupo deve ter apenas A-Z, 0-9 e _. grupo_pai_id deve ser um id de grupo existente, preferencialmente o grupo raiz funcional. Não proponha grupo novo se um grupo existente já servir.",
      "O novo grupo é somente uma sugestão e será criado apenas após confirmação humana. Nunca altere código ou fabricante do item.",
      "As correções humanas aprovadas recebidas são exemplos exclusivamente para a descrição padronizada. Use-as para reconhecer vocabulário equivalente em novas descrições, mas nunca copie delas grupo, NCM, dados fiscais ou qualquer outro atributo.",
      "Quando a descrição de origem for exatamente igual a uma correção aprovada, preserve a descrição final humana.",
      "Retorne exclusivamente o JSON estruturado solicitado.",
    ].join(" ");

    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        store: false,
        input: [
          { role: "system", content: system },
          {
            role: "user",
            content: JSON.stringify({
              catalogo_padrao_aprovado: catalogo,
              grupos_disponiveis: gruposParaAgente,
              correcoes_descricao_aprovadas: correcoes.map((correcao) => ({
                descricao_nf: correcao.descricao_origem,
                descricao_final: correcao.descricao_corrigida,
              })),
              itens_nf: itens,
            }),
          },
        ],
        text: {
          format: {
            type: "json_schema",
            name: "sugestoes_normalizacao_cadastro",
            strict: true,
            schema: schemaResposta(),
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
      const error = record(record(responseJson)?.error);
      return jsonError(502, texto(error?.message, 300) ?? "Erro ao consultar o agente de cadastro.");
    }

    const respostaTexto = extrairTextoResposta(responseJson);
    const resposta = record(JSON.parse(respostaTexto));
    const porCodigo = new Map(itens.map((item) => [normalizarCodigo(item.codigo), item]));
    const correcoesExatas = aplicarCorrecoesExatas(itens, correcoes);
    const sugestoesRecebidas = Array.isArray(resposta?.sugestoes) ? resposta.sugestoes : [];
    const sugestoes = sugestoesRecebidas
      .map((raw): SugestaoModelo | null => {
        const sugestao = record(raw);
        const codigo = normalizarCodigo(sugestao?.codigo);
        const itemOrigem = porCodigo.get(codigo);
        if (!itemOrigem) return null;
        const descricaoCorrigida = correcoesExatas.get(normalizarDescricaoAprendizado(itemOrigem.descricao_nf));
        const grupoId = sugestao?.grupo_id == null ? null : Number(sugestao.grupo_id);
        const grupo = grupoId && Number.isFinite(grupoId) ? porId.get(grupoId) : null;
        const novoGrupoRaw = record(sugestao?.novo_grupo);
        const novoGrupoPaiId = novoGrupoRaw?.grupo_pai_id == null ? null : Number(novoGrupoRaw.grupo_pai_id);
        const novoGrupoPai = novoGrupoPaiId && Number.isFinite(novoGrupoPaiId) ? porId.get(novoGrupoPaiId) : null;
        const novoGrupoCodigo = normalizarCodigoGrupo(novoGrupoRaw?.codigo);
        const novoGrupoNome = texto(novoGrupoRaw?.nome, 120);
        const novoGrupo =
          !grupo && novoGrupoCodigo && novoGrupoNome
            ? {
                codigo: novoGrupoCodigo,
                nome: novoGrupoNome,
                grupo_pai_id: novoGrupoPai?.id ?? null,
                justificativa: texto(novoGrupoRaw?.justificativa, 350) ?? "Grupo sugerido pelo agente para esta função técnica.",
              }
            : null;
        return {
          codigo,
          descricao_padronizada: descricaoCorrigida ?? texto(sugestao?.descricao_padronizada, 300) ?? "",
          grupo_id: grupo ? grupo.id : null,
          novo_grupo: novoGrupo,
          justificativa: descricaoCorrigida
            ? "Descrição reaplicada de uma correção humana aprovada para esta empresa."
            : texto(sugestao?.justificativa, 500) ?? "Revisar sugestão antes de cadastrar.",
          dados_pendentes: Array.isArray(sugestao?.dados_pendentes)
            ? sugestao.dados_pendentes.map((value) => texto(value, 160)).filter((value): value is string => Boolean(value))
            : [],
          confianca: sugestao?.confianca === "alta" || sugestao?.confianca === "media" ? sugestao.confianca : "baixa",
        };
      })
      .filter((sugestao): sugestao is SugestaoModelo => Boolean(sugestao));

    const existentes = new Set(sugestoes.map((sugestao) => sugestao.codigo));
    for (const item of itens) {
      if (existentes.has(item.codigo)) continue;
      const descricaoCorrigida = correcoesExatas.get(normalizarDescricaoAprendizado(item.descricao_nf));
      sugestoes.push({
        codigo: item.codigo,
        descricao_padronizada: descricaoCorrigida ?? "",
        grupo_id: null,
        novo_grupo: null,
        justificativa: descricaoCorrigida
          ? "Descrição reaplicada de uma correção humana aprovada para esta empresa."
          : "O agente não retornou uma sugestão utilizável para este item.",
        dados_pendentes: ["Revisar manualmente a classificação e a descrição técnica."],
        confianca: "baixa",
      });
    }

    return NextResponse.json({
      model,
      sugestoes: sugestoes.map((sugestao) => {
        const grupo = sugestao.grupo_id ? porId.get(sugestao.grupo_id) : null;
        const pai = grupo?.grupo_pai_id ? porId.get(Number(grupo.grupo_pai_id)) : null;
        return {
          ...sugestao,
          grupo_nome: grupo?.nome ?? null,
          grupo_caminho: grupo ? (pai ? `${pai.nome ?? ""} > ${grupo.nome ?? ""}` : grupo.nome) : null,
        };
      }),
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Erro inesperado ao normalizar itens.";
    return jsonError(500, message);
  }
}
