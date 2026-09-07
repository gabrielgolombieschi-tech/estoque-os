import fs from "node:fs";
import { createClient } from "@supabase/supabase-js";
import { tenantId, empresaId, diretorio, validarEscopo, situacaoRevisao } from "./lib/controle-revisoes.mjs";
import { normalizarNomeCadastro } from "../lib/itens/normalizacaoNome.ts";
import { pendenciasDescricaoTecnica } from "../lib/itens/qualidadeDescricao.ts";

// Diagnóstico somente leitura no banco; --save gera relatório local por ID.
const env = Object.fromEntries(fs.readFileSync(".env.local", "utf8").split(/\r?\n/).filter((l) => l.includes("=") && !l.trim().startsWith("#")).map((l) => {
  const p = l.indexOf("="); return [l.slice(0, p).trim(), l.slice(p + 1).trim().replace(/^(["'])(.*)\1$/, "$2")];
}));
const db = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const scope = (q) => q.eq("tenant_id", tenantId).eq("empresa_id", empresaId);
const legado = JSON.parse(fs.readFileSync(`${diretorio}/historico-recuperado.json`, "utf8"));
validarEscopo(legado);
const eventos = fs.readdirSync(diretorio).filter((n) => /^eventos-.*\.json$/.test(n)).flatMap((n) => JSON.parse(fs.readFileSync(`${diretorio}/${n}`, "utf8")));
eventos.forEach(validarEscopo);
const { data: grupos, error: erroGrupos } = await scope(db.from("item_grupos").select("id,codigo,nome,ativo"));
if (erroGrupos) throw new Error(erroGrupos.message);
const itens = [];
for (let inicio = 0; ; inicio += 1000) {
  const { data, error } = await scope(db.from("itens").select("*")).not("grupo_id", "is", null).order("id").range(inicio, inicio + 999);
  if (error) throw new Error(error.message);
  itens.push(...data);
  if (data.length < 1000) break;
}
const registros = itens.map((i) => {
  const grupo = grupos.find((g) => g.id === i.grupo_id);
  const nome = i.nome ?? "";
  const texto = nome.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toUpperCase();
  const alertas = pendenciasDescricaoTecnica({ descricao: nome, codigo: i.codigo_interno, grupoCodigo: grupo?.codigo });
  if (normalizarNomeCadastro(nome) !== nome) alertas.push("Padronização textual: conferir unidades/espaços/referências de pedido no nome.");
  // Somente contatores de potência AC-3; não aplicar atributos a auxiliares/acessórios.
  if (/^CONTATOR\b.*AC-3\b/.test(texto)) {
    if (!/\b\dP\b/.test(texto)) alertas.push("Contator: polos não explícitos no nome.");
    if (!/\bBOBINA\b/.test(texto)) alertas.push("Contator: tensão da bobina não identificada explicitamente no nome.");
    if (!/\bEM\s+\d+(?:[.,]\d+)?VCA\b/.test(texto)) alertas.push("Contator: conferir tensão de referência da corrente AC-3.");
    if (!/CONEXAO|PARAFUSO|MOLA|PUSH.IN/.test(texto)) alertas.push("Contator: conexão não explícita no nome.");
  }
  if (!grupo) alertas.push("Grupo não encontrado no mesmo tenant/empresa.");
  else if (!grupo.ativo) alertas.push("Grupo inativo.");
  return { id: i.id, codigo: i.codigo_interno, nome, descricao_complementar: i.descricao, grupo_id: i.grupo_id, grupo: grupo?.nome ?? null,
    ativo: i.ativo, finalidade: i.finalidade, situacao_documentada: situacaoRevisao(i, eventos, legado.itens).replace("nao_revisado", "sem_registro_documental"),
    historico_informado_pelo_usuario: true, alertas: [...new Set(alertas)] };
});
const resultado = { tenant_id: tenantId, empresa_id: empresaId, consultado_em: new Date().toISOString(),
  origem: "Usuário informou que os itens com grupo são os que já alteramos; recorte registrado nesta consulta, não aprovação técnica automática.",
  limite: "Passada de triagem textual e cruzamento de histórico, não nova pesquisa técnica de todos os itens. Alertas são candidatos a conferir, inclusive na descrição complementar. Ausência de alerta não certifica completude, identidade ou correção do grupo. Cobertura automática limitada às famílias implementadas.",
  total: registros.length, ativos: registros.filter((i) => i.ativo).length,
  materias_primas: registros.filter((i) => i.finalidade === "materia_prima").length,
  com_alertas: registros.filter((i) => i.alertas.length).length,
  ativos_com_alertas: registros.filter((i) => i.ativo && i.alertas.length).length,
  situacoes_documentadas: Object.fromEntries([...new Set(registros.map((i) => i.situacao_documentada))].map((s) => [s, registros.filter((i) => i.situacao_documentada === s).length])),
  por_grupo: [...new Set(registros.map((i) => i.grupo_id))].map((id) => {
    const lista = registros.filter((i) => i.grupo_id === id);
    return { id, nome: lista[0].grupo, total: lista.length, com_alertas: lista.filter((i) => i.alertas.length).length };
  }).sort((a, b) => b.total - a.total), registros };
console.log(JSON.stringify({ ...resultado, por_grupo: resultado.por_grupo.filter((g) => g.com_alertas), registros: undefined }, null, 2));
if (process.argv.includes("--save")) {
  fs.writeFileSync(`${diretorio}/triagem-itens-com-grupo.json`, JSON.stringify(resultado, null, 2));
  const limpar = (v) => String(v ?? "").replace(/\|/g, "/").replace(/[\r\n]+/g, " ");
  fs.writeFileSync(`${diretorio}/triagem-itens-com-grupo.md`, [
    "# Passada nos itens com grupo", "", `Consulta: ${resultado.consultado_em}. Tenant: ${tenantId}; empresa: ${empresaId}.`, "", resultado.origem, "", resultado.limite, "",
    `Itens com grupo: ${resultado.total}; ativos: ${resultado.ativos}; matérias-primas: ${resultado.materias_primas}. Com alertas textuais: ${resultado.com_alertas} (${resultado.ativos_com_alertas} ativos).`, "",
    "Nenhum cadastro foi alterado por esta triagem. Histórico informado pelo usuário é separado de evidência documental recuperada e de aprovação no critério atual.", "",
    "| Grupo | Itens | Com alertas |", "| --- | ---: | ---: |", ...resultado.por_grupo.map((g) => `| ${limpar(g.nome)} | ${g.total} | ${g.com_alertas} |`), "",
    "## Relação individual", "", "| ID | Código | Grupo | Histórico documentado | Nome atual | Conferir |", "| ---: | --- | --- | --- | --- | --- |",
    ...registros.map((i) => `| ${i.id} | ${limpar(i.codigo)} | ${limpar(i.grupo)} | ${i.situacao_documentada} | ${limpar(i.nome)} | ${limpar(i.alertas.join("; ") || "Sem alerta nas regras executadas; não equivale a aprovação")} |`), ""
  ].join("\n"));
}
