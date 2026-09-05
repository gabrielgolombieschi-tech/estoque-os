/* eslint-disable @typescript-eslint/no-require-imports */
/*
 * Corrige a linha Phoenix com base nas referências alfanuméricas preservadas
 * nas NF-e do mesmo tenant/empresa. Sem --apply, apenas diagnostica.
 */
const fs = require("fs");
const { createClient } = require("@supabase/supabase-js");

const TENANT_ID = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
const EMPRESA_ID = "f0e74f49-a127-46b4-901b-f7b37e43c690";
const FORNECEDOR_ID = 1;
const TOTAL_ESPERADO = 135;
const APPLY = process.argv.includes("--apply");

const env = {};
for (const line of fs.readFileSync(".env.local", "utf8").split(/\r?\n/)) {
  const i = line.indexOf("=");
  if (i <= 0) continue;
  env[line.slice(0, i).trim()] = line.slice(i + 1).trim().replace(/^['"]|['"]$/g, "");
}

const supabase = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const REFERENCIAS_FIXAS = new Map([
  ["3212064", "PTPOWER 35"],
  ["3212066", "PTPOWER 35-PE"],
  ["1407731", "HC-B16-I-PT-F"],
  ["1407732", "HC-B16-I-PT-M"],
  ["1424655", "SACC-M12FS-4PL M"],
]);

const NOMES_FIXOS = new Map([
  ["1085039", "SWITCH ETHERNET INDUSTRIAL NÃO GERENCIÁVEL FL SWITCH 1005N 5 PORTAS RJ45 10/100MBPS"],
  ["1085256", "SWITCH ETHERNET INDUSTRIAL NÃO GERENCIÁVEL FL SWITCH 1008N 8 PORTAS RJ45 10/100MBPS"],
  ["2702881", "SWITCH ETHERNET INDUSTRIAL GERENCIÁVEL COM NAT FL NAT 2008 8 PORTAS RJ45 10/100MBPS"],
  ["3209511", "BORNE DE PASSAGEM 2,5MM² COR AMARELA PT 2,5 YE"],
  ["1274118", "BATERIA PARA UPS CC 24VCC 7AH UPS-BAT/PB/24DC/7AH"],
  ["2906032", "DISJUNTOR ELETRÔNICO 24VCC 1-10A CBMC E4 24DC/1-10A NO"],
  ["1411182", "PRENSA-CABO METÁLICO G-INS-NPT3/8-S68L-NNES-S"],
  ["1407730", "INSERTO DE CONTATO PARA CONECTOR INDUSTRIAL MULTIPOLAR HC-B10-I-PT-M"],
  ["1411083", "BASE PARA CONECTOR INDUSTRIAL MULTIPOLAR HC-HPR-B10-BFH-EMR-BK"],
  ["2904601", "FONTE DE ALIMENTAÇÃO CHAVEADA 24VCC 10A ENTRADA MONOFÁSICA QUINT4-PS/1AC/24DC/10"],
  ["1159039", "FONTE DE ALIMENTAÇÃO CHAVEADA 24VCC 20A ENTRADA MONOFÁSICA TRIO3-PS/1AC/24DC/20"],
]);

function limparDescricaoOrigem(value) {
  return String(value ?? "")
    .replace(/\s+PEDIDO DE COMPRA:.*$/i, "")
    .replace(/\s+/g, " ")
    .trim();
}

function escolherDescricaoOrigem(descricoes) {
  return [...descricoes]
    .map(limparDescricaoOrigem)
    .filter((texto) => texto && !/^ITEM \d+$/i.test(texto))
    .sort((a, b) => Number(b.includes(" - ")) - Number(a.includes(" - ")) || b.length - a.length)[0] ?? "";
}

function extrairReferencia(origem, codigo) {
  const fixa = REFERENCIAS_FIXAS.get(codigo);
  if (fixa) return fixa;
  if (!origem) return "";
  if (origem.includes(" - ")) return origem.split(" - ").slice(1).join(" - ").trim();
  const sufixoGenerico = /\s+(?:M[ÓO]DULO|REL[ÉE]|FONTE|PERFIL|BLOCO|CONECTOR|DISJUNTOR|CANALETA|JUMPER|SUPORTE|FOLHA|FITA|CABO|INSERTO|BASE|PRENSA|TOMADA|CARCA[CÇ]A|ACUMULADOR|CONVERSOR|ETIQUETA|PORTA)\b.*$/i;
  return origem.replace(sufixoGenerico, "").trim();
}

function normalizarReferencia(value) {
  return String(value ?? "")
    .replace(/\s+/g, " ")
    .replace(/-\s+(?=[0-9])/g, "-")
    .replace(/\/\s+(?=[0-9A-Z])/g, "/")
    .replace(/\bM\s+(?=\d+(?:FS|FR|MS|MR)\b)/g, "M")
    .trim();
}

function formaComparavel(value) {
  return String(value ?? "").replace(/[^A-Z0-9]/gi, "").toUpperCase();
}

function nomeCaboSensorAtuador(referencia) {
  const match = referencia.match(/^SAC-(\d+)P-(\d+(?:,\d+)?)-(PVC|PUR)\/M(8|12)(FS|FR|MS|MR)$/i);
  if (!match) return null;
  const [, polos, comprimentoRaw, material, tamanho, terminacao] = match;
  const comprimento = Number(comprimentoRaw.replace(",", ".")).toLocaleString("pt-BR", { maximumFractionDigits: 1 });
  const genero = terminacao[0].toUpperCase() === "F" ? "FÊMEA" : "MACHO";
  const orientacao = terminacao[1].toUpperCase() === "R" ? "ANGULAR" : genero === "FÊMEA" ? "RETA" : "RETO";
  return `CABO PARA SENSOR/ATUADOR M${tamanho} ${genero} ${orientacao} ${polos} POLOS ${comprimento}M ${material.toUpperCase()} ${referencia}`;
}

function proporNome(item, referencia) {
  const fixo = NOMES_FIXOS.get(item.codigo_interno);
  if (fixo) return fixo;
  const cabo = nomeCaboSensorAtuador(referencia);
  if (cabo) return cabo;

  let nome = String(item.nome ?? "").trim();
  if (referencia && !formaComparavel(nome).includes(formaComparavel(referencia))) nome += ` ${referencia}`;
  return nome.replace(/\s+/g, " ").trim();
}

async function buscarDados() {
  const { data: itens, error: itensError } = await supabase
    .from("itens")
    .select("id,codigo_interno,nome,grupo_id,ativo")
    .eq("tenant_id", TENANT_ID)
    .eq("empresa_id", EMPRESA_ID)
    .eq("fornecedor_id", FORNECEDOR_ID)
    .order("id");
  if (itensError) throw itensError;

  const { data: grupos, error: gruposError } = await supabase
    .from("item_grupos")
    .select("id,codigo,nome")
    .eq("tenant_id", TENANT_ID)
    .eq("empresa_id", EMPRESA_ID)
    .eq("ativo", true);
  if (gruposError) throw gruposError;

  const ids = itens.map((item) => item.id);
  const notas = [];
  for (let offset = 0; offset < ids.length; offset += 100) {
    const { data, error } = await supabase
      .from("nf_entrada_itens")
      .select("item_id,descricao")
      .eq("tenant_id", TENANT_ID)
      .eq("empresa_id", EMPRESA_ID)
      .in("item_id", ids.slice(offset, offset + 100));
    if (error) throw error;
    notas.push(...data);
  }

  return { itens, grupos, notas };
}

async function atualizarEmLotes(alteracoes) {
  const tamanhoLote = 10;
  for (let offset = 0; offset < alteracoes.length; offset += tamanhoLote) {
    const lote = alteracoes.slice(offset, offset + tamanhoLote);
    const resultados = await Promise.all(lote.map(async (alteracao) => {
      const { data, error } = await supabase
        .from("itens")
        .update({
          nome: alteracao.nomeProposto,
          grupo_id: alteracao.grupoIdProposto,
          atualizado_em: new Date().toISOString(),
        })
        .eq("id", alteracao.id)
        .eq("tenant_id", TENANT_ID)
        .eq("empresa_id", EMPRESA_ID)
        .eq("fornecedor_id", FORNECEDOR_ID)
        .select("id")
        .single();
      if (error) throw new Error(`Item ${alteracao.id}: ${error.message}`);
      return data.id;
    }));
    if (resultados.length !== lote.length) throw new Error(`Lote incompleto a partir do índice ${offset}.`);
  }
}

async function main() {
  const { itens, grupos, notas } = await buscarDados();
  if (itens.length !== TOTAL_ESPERADO) {
    throw new Error(`Proteção de escopo: esperados ${TOTAL_ESPERADO} itens Phoenix, encontrados ${itens.length}.`);
  }

  const grupoPorCodigo = new Map(grupos.map((grupo) => [grupo.codigo, grupo]));
  const grupoCabos = grupoPorCodigo.get("CABOS_PARA_SENSORES");
  const grupoBornes = grupoPorCodigo.get("CONEXOES_BORNES_PASSAGEM");
  const grupoConectoresMultipolares = grupoPorCodigo.get("CONECTORES_INDUSTRIAIS_MULTIPOLARES");
  if (!grupoCabos || !grupoBornes || !grupoConectoresMultipolares) throw new Error("Grupos obrigatórios não encontrados no tenant/empresa.");

  const descricoesPorItem = new Map();
  for (const nota of notas) {
    if (!descricoesPorItem.has(nota.item_id)) descricoesPorItem.set(nota.item_id, new Set());
    descricoesPorItem.get(nota.item_id).add(String(nota.descricao ?? "").trim());
  }

  const propostas = itens.map((item) => {
    const origem = escolherDescricaoOrigem(descricoesPorItem.get(item.id) ?? []);
    const referencia = normalizarReferencia(extrairReferencia(origem, item.codigo_interno));
    const nomeProposto = proporNome(item, referencia);
    let grupoIdProposto = item.grupo_id;
    if (/^SAC-/i.test(referencia)) grupoIdProposto = grupoCabos.id;
    if (item.codigo_interno === "3209511") grupoIdProposto = grupoBornes.id;
    if (["1407730", "1411083"].includes(item.codigo_interno)) grupoIdProposto = grupoConectoresMultipolares.id;
    return { ...item, origem, referencia, nomeProposto, grupoIdProposto };
  });

  const semReferencia = propostas.filter((item) => !item.referencia);
  const codigosNaoNumericos = propostas.filter((item) => !/^\d+$/.test(item.codigo_interno));
  const switchesSemPortas = propostas.filter((item) => /^SWITCH\b/i.test(item.nomeProposto) && !/\b\d+ PORTAS?\b/i.test(item.nomeProposto));
  const nomesRepetidos = [...propostas.reduce((map, item) => {
    const key = item.nomeProposto.toUpperCase();
    map.set(key, (map.get(key) ?? 0) + 1);
    return map;
  }, new Map()).entries()].filter(([, quantidade]) => quantidade > 1);

  if (semReferencia.length || codigosNaoNumericos.length || switchesSemPortas.length || nomesRepetidos.length) {
    console.log(JSON.stringify({ semReferencia, codigosNaoNumericos, switchesSemPortas, nomesRepetidos }, null, 2));
    throw new Error("A pré-validação das propostas Phoenix falhou; nenhuma alteração foi aplicada.");
  }

  const alteracoes = propostas.filter((item) =>
    item.nomeProposto !== item.nome || Number(item.grupoIdProposto) !== Number(item.grupo_id)
  );
  const resumo = {
    modo: APPLY ? "APLICAR" : "DIAGNOSTICO",
    totalPhoenix: propostas.length,
    alteracoesNecessarias: alteracoes.length,
    nomesAlterados: alteracoes.filter((item) => item.nomeProposto !== item.nome).length,
    gruposAlterados: alteracoes.filter((item) => Number(item.grupoIdProposto) !== Number(item.grupo_id)).length,
    nomesRepetidosDepois: nomesRepetidos.length,
    switchesSemPortasDepois: switchesSemPortas.length,
    alteracoes: alteracoes.map((item) => ({
      id: item.id,
      codigo: item.codigo_interno,
      nomeAtual: item.nome,
      nomeProposto: item.nomeProposto,
      grupoAtual: item.grupo_id,
      grupoProposto: item.grupoIdProposto,
      referencia: item.referencia,
    })),
  };

  console.log(JSON.stringify(resumo, null, 2));
  if (!APPLY || alteracoes.length === 0) return;
  await atualizarEmLotes(alteracoes);
  console.log(JSON.stringify({ aplicado: true, itensAtualizados: alteracoes.length }, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
