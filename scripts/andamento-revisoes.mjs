import fs from "node:fs";
import { createClient } from "@supabase/supabase-js";
import { tenantId, empresaId, diretorio, validarEscopo, situacaoRevisao, impressaoTecnica } from "./lib/controle-revisoes.mjs";

// Consulta remota somente leitura; --save atualiza apenas relatórios locais.
const legado = JSON.parse(fs.readFileSync(`${diretorio}/historico-recuperado.json`, "utf8"));
validarEscopo(legado);
const informado = JSON.parse(fs.readFileSync(`${diretorio}/historico-informado-grupos.json`, "utf8"));
validarEscopo(informado);
const eventos = fs.readdirSync(diretorio).filter((n) => /^eventos-.*\.json$/.test(n)).flatMap((n) => JSON.parse(fs.readFileSync(`${diretorio}/${n}`, "utf8")));
eventos.forEach(validarEscopo);
const arquivoExcecoes = `${diretorio}/excecoes-referencias-claras.json`;
const excecoesClaras = fs.existsSync(arquivoExcecoes) ? JSON.parse(fs.readFileSync(arquivoExcecoes,"utf8")) : null;
if (excecoesClaras) validarEscopo(excecoesClaras);
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
// Fila de aprovação é uma dimensão separada: não soma propostas aos aprovados.
const propostas = fs.readdirSync(diretorio).filter((n) => /^lote-.*\.json$/.test(n)).flatMap((n) => {
  const lote = JSON.parse(fs.readFileSync(`${diretorio}/${n}`, "utf8"));
  validarEscopo(lote);
  if (lote.autorizacao !== "aguardando_aprovacao_humana") return [];
  const numero = lote.numero;
  const arquivoLiberacao = `${diretorio}/liberacao-${numero}-referencias-claras.json`;
  const liberacao = fs.existsSync(arquivoLiberacao) ? JSON.parse(fs.readFileSync(arquivoLiberacao,"utf8")) : null;
  if (liberacao) validarEscopo(liberacao);
  return lote.itens.filter((i) => !eventos.some((e) => e.lote === lote.lote && e.item_id === i.id && e.status === "aprovado")).map((i) => {
    const atual = itens.find((a) => a.id === i.id);
    return { id: i.id, codigo: i.antes.codigo_interno, lote: lote.lote, antes: i.antes.nome, depois_proposto: i.nome,
      status: atual && impressaoTecnica(atual) === i.impressao_antes && atual.ativo === i.antes.ativo ? liberacao?.retidos.includes(i.id) ? "aguardando_esclarecimento_tecnico" : "aguardando_aprovacao" : "proposta_desatualizada" };
  });
});
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
  excecoes_referencias_claras: { total: excecoesClaras?.itens.length ?? 0, relatorio: "excecoes-referencias-claras.md", observacao: "Dimensão separada, não somar a aprovados nem duplicar os 22 retidos das propostas 011. Inclui conferência complementar; não classifica a fila ainda não pesquisada como dúvida técnica." },
  campanha_agrupados: { total: campanhaAtual.length, aprovados: campanhaAtual.filter((i) => i.status === "aprovado").length, restantes: campanhaAtual.filter((i) => i.status !== "aprovado").length, registros: campanhaAtual },
  lotes_aplicados: lotesAplicados,
  propostas_nao_aplicadas: { total_ids: new Set(propostas.map((p) => p.id)).size, aguardando_aprovacao: propostas.filter((p) => p.status === "aguardando_aprovacao").length, aguardando_esclarecimento_tecnico: propostas.filter(p=>p.status==="aguardando_esclarecimento_tecnico").length, desatualizadas: propostas.filter((p) => p.status === "proposta_desatualizada").length, registros: propostas },
  historico_documentado_ou_informado_sem_duplicidade: registros.filter((i) => i.status !== "nao_revisado").length,
  observacao: "Histórico recuperado não é aprovação no critério atual. Pendentes aguardam fonte/decisão, não entram em repetição automática. Relatório é uma fotografia; executar novamente para detectar mudanças técnicas.",
  registros };
console.log(JSON.stringify({ ...resultado, campanha_agrupados: { ...resultado.campanha_agrupados, registros: undefined }, propostas_nao_aplicadas: { ...resultado.propostas_nao_aplicadas, registros: undefined }, registros: undefined }, null, 2));
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
    "## Propostas não aplicadas", "",
    `${resultado.propostas_nao_aplicadas.aguardando_aprovacao} itens aguardam aprovação; ${resultado.propostas_nao_aplicadas.aguardando_esclarecimento_tecnico} aguardam esclarecimento técnico; ${resultado.propostas_nao_aplicadas.desatualizadas} propostas ficaram desatualizadas. D-047 permite aplicar referências claras sem aprovar novos lotes de 50; não permite resolver lacunas por suposição. São filas separadas, não revisões concluídas.`, "",
    `${resultado.excecoes_referencias_claras.total} exceções técnicas nesta rodada, incluindo os retidos do 011 e a conferência complementar. [Somente itens não claros](excecoes-referencias-claras.md). Fila ainda não pesquisada separada em fila-paineis-referencias-claras.json.`, "",
    ...[...new Set(propostas.map((p) => p.lote))].map((lote) => `[Antes/depois — lote ${lote}](lote-${lote}.md).`), "",
    "A campanha original de 104 alertas é um recorte de triagem, não o universo completo dos 1.193 itens agrupados. Outros agrupados também recebem revisão técnica por família.", "",
    "## Sequência aprovada", "", "1. Disjuntores e contatores — lotes 003 a 007 aplicados; pendências documentais separadas, etapa ainda não equivale a 100% da família.",
    "2. CLPs, remotas e cartões — lote 008 aplicado: 50 Siemens; pendências 2461/3628/3629 separadas, sem declarar a família concluída.", "3. Sensores — lote 009 aplicado: 50 SICK e acessórios relacionados, com ressalvas 1708/438; demais sensores ainda não equivalem a etapa concluída.", "4. Painéis — lote 010 aplicado: 47 comandos/sinalizadores/acessórios SIRIUS ACT + 3 chaves de segurança 3SE; ressalva 215 preservada. D-047: 28 claros do 011 e mais um relé no 012 aplicados; 36 exceções sem alteração. Demais marcas/famílias continuam na fila de pesquisa, sem declarar 100% do catálogo.", "",
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
