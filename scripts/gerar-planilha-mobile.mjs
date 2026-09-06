/**
 * Planilha simples do aplicativo mobile: o que cada papel ve e o que cada
 * pessoa consegue fazer.
 *
 *   node scripts/gerar-planilha-mobile.mjs <mobile.txt> <colaboradores.txt> <saida.xlsx>
 *
 * mobile.txt       : papel|representante|grupo|item|resultado|detalhe (medido)
 * colaboradores.txt: nome|email|papel|vinculo_colaborador
 */
import fs from "node:fs";
import path from "node:path";
import * as XLSX from "xlsx";

const [, , mobilePath, pessoasPath, saidaPath] = process.argv;
if (!mobilePath || !pessoasPath || !saidaPath) {
  console.error("Uso: node scripts/gerar-planilha-mobile.mjs <mobile.txt> <colaboradores.txt> <saida.xlsx>");
  process.exit(1);
}

const linhas = fs.readFileSync(mobilePath, "utf8").trim().split(/\r?\n/);
const cab = linhas.shift().split("|");
const medido = linhas.map((l) => Object.fromEntries(l.split("|").map((v, i) => [cab[i], v])));

const pessoas = fs.readFileSync(pessoasPath, "utf8").trim().split(/\r?\n/).map((l) => {
  const [nome, email, papel, vinculo] = l.split("|");
  return { nome, email, papel, temColaborador: vinculo === "vinculado" };
});

const papeis = [...new Set(medido.map((r) => r.papel))].sort();
const HORAS = new Set(["ADMIN", "DIRETOR", "COORDENACAO", "TECNICO", "APONTAMENTO_RH", "APONTADOR"]);
const GESTAO = new Set(["ADMIN", "DIRETOR", "COORDENACAO"]);
const APONTADOR = new Set(["TECNICO", "APONTAMENTO_RH", "APONTADOR"]);

// Acoes de escrita e regras de tela: nao sao chamadas (nao gravamos nada);
// vem das regras de papel lidas do app e das RPCs.
const REGRAS = {
  // Itens que dependem da tela em que aparecem: se a tela não abre, o item some.
  "Ver preço e custo do item": (p, medidoDe) => (medidoDe("Consultar o estoque") !== "SIM" ? "NÃO" : APONTADOR.has(p) ? "NÃO" : "SIM"),
  "Ver o histórico de toda a equipe": (p, medidoDe) => (medidoDe("Ver o próprio histórico de lançamentos") === "NÃO" ? "NÃO" : APONTADOR.has(p) ? "SÓ O PRÓPRIO" : "SIM"),
  // A aba de aprovações é escondida na tela para os papéis de campo, ainda que
  // a função do banco responda para eles.
  "Abrir a aba de aprovações": (p, medidoDe) => (APONTADOR.has(p) ? "NÃO" : medidoDe("Abrir a aba de aprovações")),
  "Aprovar horas da equipe": (p) => (APONTADOR.has(p) ? "NÃO" : "SIM"),
  "Lançar horas na OS": (p) => (HORAS.has(p) ? "SIM" : "NÃO"),
  "Lançar horas para outra pessoa": (p) => (HORAS.has(p) && !["APONTAMENTO_RH", "APONTADOR"].includes(p) ? "SIM" : "NÃO"),
  "Lançar HH (entrada e saída)": (p) => (HORAS.has(p) ? "SIM" : "NÃO"),
  "Lançar material na OS": (p) => (p === "PAINEL_TV" ? "NÃO" : "SIM"),
  "Corrigir ou remover material": () => "SÓ O PRÓPRIO",
  "Criar OS de HH pelo app": (p) => (["APONTAMENTO_RH", "APONTADOR"].includes(p) ? "NÃO" : "SIM"),
  "Editar apontamento antes da aprovação": () => "SÓ O PRÓPRIO",
  "Editar apontamento depois de aprovado": (p) => (GESTAO.has(p) ? "SIM" : "NÃO"),
  "Cancelar ou restaurar apontamento": (p) => (GESTAO.has(p) ? "SIM" : "NÃO"),
};

const itens = [];
for (const r of medido) {
  if (!itens.some((i) => i.item === r.item)) itens.push({ grupo: r.grupo, item: r.item });
}
const valorMedido = new Map(medido.map((r) => [`${r.papel}::${r.item}`, r]));

function bruto(papel, item) {
  const r = valorMedido.get(`${papel}::${item}`);
  if (!r) return "—";
  return r.resultado;
}
function celula(papel, item) {
  if (REGRAS[item]) return REGRAS[item](papel, (outro) => bruto(papel, outro));
  return bruto(papel, item);
}

const wb = XLSX.utils.book_new();
const addSheet = (nome, linhas, larguras) => {
  const ws = XLSX.utils.aoa_to_sheet(linhas);
  ws["!cols"] = larguras.map((w) => ({ wch: w }));
  XLSX.utils.book_append_sheet(wb, ws, nome);
};

// ------------------------------------------------------------- Aba 1
addSheet("O que cada papel vê", [
  ["Onde", "O que a pessoa faz no app", ...papeis],
  ...itens.map((i) => [i.grupo, i.item, ...papeis.map((p) => celula(p, i.item))]),
  [],
  ["Legenda", "SIM = aparece e funciona · NÃO = bloqueado · SÓ O PRÓPRIO = só os lançamentos da própria pessoa · FALTA VÍNCULO = o papel permite, mas o usuário não está ligado a um colaborador ativo"],
], [16, 42, ...papeis.map(() => 16)]);

// ------------------------------------------------------------- Aba 2
const usaApp = (p) => {
  const total = itens.filter((i) => celula(p.papel, i.item) === "SIM").length;
  return total;
};
addSheet("Quem usa o app", [
  ["Pessoa", "E-mail", "Papel na empresa", "Ligado a um colaborador", "O que consegue fazer hoje", "Ações liberadas"],
  ...pessoas.map((p) => {
    const podeHoras = HORAS.has(p.papel);
    const bloqueado = p.papel === "PAINEL_TV";
    let situacao;
    if (bloqueado) situacao = "Praticamente nada: o app recusa estoque, histórico e OS por cliente";
    else if (!p.temColaborador && podeHoras) situacao = "Não consegue lançar nem ver horas: falta ligar o usuário a um colaborador ativo";
    else if (!p.temColaborador) situacao = "Vê OS e estoque; as telas de horas não abrem por falta de vínculo com colaborador";
    else if (GESTAO.has(p.papel)) situacao = "Tudo: lança horas e material, aprova, corrige e cancela lançamentos da equipe";
    else if (podeHoras) situacao = "Lança as próprias horas e material; não aprova nem vê preço no estoque";
    else situacao = "Vê OS, estoque e histórico; não lança horas";
    return [p.nome, p.email, p.papel, p.temColaborador ? "Sim" : "Não", situacao, usaApp(p)];
  }),
], [20, 32, 18, 22, 76, 15]);

// ------------------------------------------------------------- Aba 3
const semVinculo = pessoas.filter((p) => !p.temColaborador).map((p) => `${p.nome} (${p.papel})`);
const semVinculoHoras = pessoas.filter((p) => !p.temColaborador && HORAS.has(p.papel)).map((p) => `${p.nome} (${p.papel})`);
addSheet("Observações", [
  ["#", "Observação", "Quem"],
  [1, "O app é feito para quem trabalha na OS. Os três papéis de campo (APONTADOR, TECNICO e APONTAMENTO_RH) lançam horas e material, mas não veem preço no estoque, não aprovam horas e só enxergam os próprios lançamentos.",
    pessoas.filter((p) => APONTADOR.has(p.papel)).map((p) => p.nome).join(", ") || "ninguém hoje"],
  [2, "Quem não está ligado a um colaborador ativo não abre nenhuma tela de horas, por mais alto que seja o papel. O app mostra erro de vínculo.", semVinculo.join(", ")],
  [3, "Destes, os que deveriam lançar horas ficam travados de verdade: é o caso mais urgente de corrigir.", semVinculoHoras.join(", ") || "ninguém"],
  [4, "PAINEL_TV é bloqueado no app: não consulta estoque, nem histórico, nem OS por cliente.", pessoas.filter((p) => p.papel === "PAINEL_TV").map((p) => p.nome).join(", ")],
  [5, "Valores da OS (orçado, faturado, gasto) só aparecem para ADMIN, DIRETOR, FATURAMENTO, FINANCEIRO e COMERCIAL. Coordenação e campo não veem dinheiro.",
    pessoas.filter((p) => ["ADMIN", "DIRETOR", "FATURAMENTO", "FINANCEIRO"].includes(p.papel)).map((p) => p.nome).join(", ")],
  [6, "Antes da aprovação, cada um só edita o próprio lançamento. Depois de aprovado, só ADMIN, DIRETOR e COORDENACAO alteram.",
    pessoas.filter((p) => GESTAO.has(p.papel)).map((p) => p.nome).join(", ")],
  [7, "Material lançado pelo app só pode ser corrigido ou removido por quem lançou, e só enquanto a OS está em andamento.", "todos"],
  [8, "TECNICO não tem ninguém ativo hoje; a coluna vem das regras do app, não de uma medição.", "ninguém"],
  [9, "PAINEL_TV enxerga a fila de aprovações de horas e consegue criar OS de HH pelo app, embora não abra estoque nem histórico. Vale rever.",
    pessoas.filter((p) => p.papel === "PAINEL_TV").map((p) => p.nome).join(", ")],
  [10, "A aba de aprovações é escondida na tela para os papéis de campo, mas a função do banco responde a eles. Hoje não é um problema, porque a tela não existe para esses papéis.",
    pessoas.filter((p) => APONTADOR.has(p.papel)).map((p) => p.nome).join(", ") || "ninguém hoje"],
], [5, 104, 52]);

// ------------------------------------------------------------- Aba 4
addSheet("Como foi medido", [
  ["Item", "Detalhe"],
  ["Data", new Date().toLocaleDateString("pt-BR")],
  ["Aplicativo", "App mobile (Expo), pasta estoque-os-mobile."],
  ["Método", "Um usuário real de cada papel foi impersonado no banco de produção, em transação READ ONLY, e as telas de consulta do app foram chamadas de verdade."],
  ["O que não foi chamado", "As ações que gravam (lançar horas, lançar material, criar OS). Para elas vale a regra de papel lida do código do app e das funções do banco."],
  ["Vínculo com colaborador", "Ligação entre o usuário e um colaborador ativo, por e-mail. Sem ela, as telas de horas não abrem."],
  ["Reproduzir", "node scripts/medir-acessos-mobile.mjs > mobile.txt && node scripts/gerar-planilha-mobile.mjs mobile.txt colaboradores.txt saida.xlsx"],
], [26, 118]);

fs.mkdirSync(path.dirname(path.resolve(saidaPath)), { recursive: true });
XLSX.writeFile(wb, path.resolve(saidaPath));
console.log("Planilha:", path.resolve(saidaPath));
console.log(`${papeis.length} papéis · ${itens.length} itens do app · ${pessoas.length} pessoas`);
