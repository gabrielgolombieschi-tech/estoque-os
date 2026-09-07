import fs from "node:fs";
import { createClient } from "@supabase/supabase-js";
import { tenantId, empresaId, diretorio, validarEscopo, situacaoRevisao } from "./lib/controle-revisoes.mjs";

// Consulta remota somente leitura; --save atualiza apenas relatórios locais.
const legado = JSON.parse(fs.readFileSync(`${diretorio}/historico-recuperado.json`, "utf8"));
validarEscopo(legado);
const informado = JSON.parse(fs.readFileSync(`${diretorio}/historico-informado-grupos.json`, "utf8"));
validarEscopo(informado);
const eventos = fs.readdirSync(diretorio).filter((n) => /^eventos-.*\.json$/.test(n)).flatMap((n) => JSON.parse(fs.readFileSync(`${diretorio}/${n}`, "utf8")));
eventos.forEach(validarEscopo);
const env = Object.fromEntries(fs.readFileSync(".env.local", "utf8").split(/\r?\n/).filter((l) => l.includes("=") && !l.trim().startsWith("#")).map((l) => {
  const i = l.indexOf("="); return [l.slice(0, i).trim(), l.slice(i + 1).trim().replace(/^(["'])(.*)\1$/, "$2")];
}));
const db = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const itens = [];
for (let inicio = 0; ; inicio += 1000) {
  const { data, error } = await db.from("itens").select("*").eq("tenant_id", tenantId).eq("empresa_id", empresaId).order("id").range(inicio, inicio + 999);
  if (error) throw new Error(error.message);
  itens.push(...data);
  if (data.length < 1000) break;
}
const registros = itens.map((i) => ({ id: i.id, codigo: i.codigo_interno, nome: i.nome, ativo: i.ativo, tipo: i.tipo, finalidade: i.finalidade, status: situacaoRevisao(i, eventos, legado.itens, informado.itens) }));
const contagens = Object.fromEntries(["aprovado", "pendente", "reavaliar", "historico_recuperado", "historico_informado", "nao_revisado"].map((s) => [s, registros.filter((i) => i.status === s).length]));
const campanha = JSON.parse(fs.readFileSync(`${diretorio}/campanha-itens-agrupados.json`, "utf8"));
validarEscopo(campanha);
const campanhaAtual = campanha.itens.map((i) => ({ ...i, status: registros.find((r) => r.id === i.id && r.codigo === i.codigo)?.status ?? "fora_do_recorte" }));
const lotesAplicados = [...new Set(eventos.map((e) => e.lote))].map((lote) => {
  const lista = eventos.filter((e) => e.lote === lote);
  return { lote, avaliados: lista.length, aprovados: lista.filter((e) => e.status === "aprovado").length, pendentes: lista.filter((e) => e.status === "pendente").length };
});
const resultado = { consultado_em: new Date().toISOString(), tenant_id: tenantId, empresa_id: empresaId,
  total: registros.length, ativos: registros.filter((i) => i.ativo).length,
  materias_primas: registros.filter((i) => i.finalidade === "materia_prima").length,
  contagens, avaliados_minimo_sem_duplicidade: registros.filter((i) => !["nao_revisado", "historico_informado"].includes(i.status)).length,
  campanha_agrupados: { total: campanhaAtual.length, aprovados: campanhaAtual.filter((i) => i.status === "aprovado").length, restantes: campanhaAtual.filter((i) => i.status !== "aprovado").length, registros: campanhaAtual },
  lotes_aplicados: lotesAplicados,
  historico_documentado_ou_informado_sem_duplicidade: registros.filter((i) => i.status !== "nao_revisado").length,
  observacao: "Histórico recuperado não é aprovação no critério atual. Pendentes aguardam fonte/decisão, não entram em repetição automática. Relatório é uma fotografia; executar novamente para detectar mudanças técnicas.",
  registros };
console.log(JSON.stringify({ ...resultado, campanha_agrupados: { ...resultado.campanha_agrupados, registros: undefined }, registros: undefined }, null, 2));
if (process.argv.includes("--save")) {
  fs.writeFileSync(`${diretorio}/andamento.json`, JSON.stringify(resultado, null, 2));
  const recentes = registros.filter((i) => eventos.some((e) => e.item_id === i.id));
  const linhas = recentes.map((i) => `| ${i.id} | ${i.codigo} | ${i.status} | ${i.nome.replace(/\|/g, "/")} |`);
  fs.writeFileSync(`${diretorio}/andamento.md`, [
    "# Andamento da revisão de cadastros", "", `Consulta: ${resultado.consultado_em}. Tenant: ${tenantId}; empresa: ${empresaId}.`, "",
    `Base: ${resultado.total} itens; ${resultado.ativos} ativos; ${resultado.materias_primas} matérias-primas.`, "",
    "| Situação | Itens únicos |", "| --- | ---: |", ...Object.entries(contagens).map(([s, n]) => `| ${s} | ${n} |`), "",
    `Mínimo com evidência individualizada de avaliação: ${resultado.avaliados_minimo_sem_duplicidade}. Não equivale a cadastros tecnicamente completos.`, "",
    `Incluindo alterações anteriores informadas pelo usuário: ${resultado.historico_documentado_ou_informado_sem_duplicidade} IDs únicos. Histórico informado é separado de aprovação técnica e não aumenta a contagem documental.`, "",
    `Campanha dos itens agrupados: ${resultado.campanha_agrupados.aprovados}/${resultado.campanha_agrupados.total} aprovados; ${resultado.campanha_agrupados.restantes} ainda a tratar ou pendentes. Lista original fixa em campanha-itens-agrupados.json.`, "",
    "## Lotes verificados", "", ...lotesAplicados.map((l) => `- ${l.lote}: ${l.avaliados} avaliados, ${l.aprovados} aprovados, ${l.pendentes} pendentes no fechamento do lote.`), "",
    "## Sequência aprovada", "", "1. Disjuntores e contatores — em andamento.",
    "2. CLPs, remotas e cartões — próximo bloco após a etapa 1.", "3. Sensores.", "4. Painéis.", "",
    "## Itens do controle novo", "", "| ID | Código | Situação atual | Descrição atual |", "| ---: | --- | --- | --- |", ...linhas, "",
    "## Rastreabilidade e retomada", "",
    "- `eventos-*.json`: data, responsável, fonte, pendências, critério por família e impressão técnica de cada avaliação. Eventos só são emitidos após conferência remota.",
    "- `historico-recuperado.json`: 338 IDs antigos, preservados separadamente; não são aprovados automaticamente.",
    "- `historico-informado-grupos.json`: recorte dos 1.193 itens com grupo em 05/09/2026, reconhecidos pelo usuário como alterações anteriores. Não estender essa indicação a itens agrupados futuramente nem chamar histórico informado de aprovação técnica.",
    "- `andamento.json`: relação completa por ID, incluindo não revisados; contagens deduplicadas no tenant/empresa.",
    "- Aprovado no mesmo critério e com dados técnicos iguais: não revisar novamente. Mudança técnica ou critério da família: reavaliar. Mudança de preço/saldo/data: não reabre.",
    "- Pendentes 795 e 1540: conferir associação de colunas nos PDFs oficiais indicados no manifesto; não inferir dados de similares ou predecessores.",
    "- Na próxima seleção, atualizar este relatório; conferir primeiro os alertas dos itens com histórico recuperado/informado, reaproveitando o que já foi feito. Histórico informado não volta a ser tratado como nunca alterado. Os demais estados de fila são `nao_revisado` e `reavaliar`. Pendentes só voltam com nova evidência ou decisão explícita.",
    "", "Atualizar: `node scripts/andamento-revisoes.mjs --save`. Controle local versionável; não há nova tela ou tabela no ERP.", ""
  ].join("\n"));
}
