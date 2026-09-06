/**
 * Gera a planilha de acessos por usuario e por papel a partir da medicao real
 * feita por scripts/medir-acessos-usuarios.mjs (impersonacao somente leitura).
 *
 *   node scripts/gerar-planilha-permissoes.mjs <acessos.txt> <usuarios.txt> <saida.xlsx>
 *
 * acessos.txt : usuario|email|papel_tenant|empresa|papel_empresa|grupo|rotulo|permissao|rls|rpc|menu
 * usuarios.txt: nome|email|papel_tenant|empresa|papel_empresa|vinculo|usuario_ativo
 */
import fs from "node:fs";
import path from "node:path";
import * as XLSX from "xlsx";

const [, , acessosPath, usuariosPath, saidaPath] = process.argv;
if (!acessosPath || !usuariosPath || !saidaPath) {
  console.error("Uso: node scripts/gerar-planilha-permissoes.mjs <acessos.txt> <usuarios.txt> <saida.xlsx>");
  process.exit(1);
}

const linhasAcesso = fs.readFileSync(acessosPath, "utf8").trim().split(/\r?\n/);
const cabecalho = linhasAcesso.shift().split("|");
const acessos = linhasAcesso.map((l) => Object.fromEntries(l.split("|").map((v, i) => [cabecalho[i], v])));

const usuarios = fs.readFileSync(usuariosPath, "utf8").trim().split(/\r?\n/).map((l) => {
  const [nome, email, papelTenant, empresa, papelEmpresa, vinculo, ativo] = l.split("|");
  return { nome, email, papelTenant, empresa, papelEmpresa, vinculo, ativo: ativo === "SIM" };
});

const bool = (v) => v === "true";
const papeis = (r) => `${r.papel_tenant} / ${r.papel_empresa}`;
const combos = [...new Set(acessos.map(papeis))];
const permissoes = [...new Map(acessos.map((r) => [r.permissao, { grupo: r.grupo, rotulo: r.rotulo, permissao: r.permissao }])).values()];
const porCombo = new Map();
for (const r of acessos) porCombo.set(`${papeis(r)}::${r.permissao}`, r);

// A verdade do acesso ao dado e o RLS (guarda as tabelas). O portao de RPC e
// o mapa do menu entram como ressalva quando divergem.
// SIM  = acessa o dado e o menu mostra o caminho
// SIM- = acessa o dado, mas o menu nao mostra o atalho
// NAO* = o menu mostra o caminho, mas o banco recusa (a tela dá erro)
// NAO  = bloqueado
function celula(combo, permissao) {
  const r = porCombo.get(`${combo}::${permissao}`);
  if (!r) return "—";
  const rls = bool(r.rls);
  const menu = bool(r.menu);
  if (rls && menu) return "SIM";
  if (rls && !menu) return "SIM-";
  if (!rls && menu) return "NÃO*";
  return "NÃO";
}

const totalRls = (combo) => permissoes.filter((p) => bool(porCombo.get(`${combo}::${p.permissao}`)?.rls)).length;

function resumo(combo) {
  const tem = (k) => bool(porCombo.get(`${combo}::${k}`)?.rls);
  if (totalRls(combo) === 0) return combo.endsWith("APONTADOR") ? "Nenhum acesso ao sistema web (usa só o aplicativo)" : "Nenhum acesso ao sistema web";
  const partes = [];
  if (tem("os.write")) partes.push("OS"); else if (tem("os.read")) partes.push("OS (só ver)");
  if (tem("estoque.write")) partes.push("estoque"); else if (tem("estoque.read")) partes.push("estoque (só ver)");
  if (tem("compras.write") || tem("compras.approve")) partes.push("compras");
  if (tem("financeiro.write") && tem("financeiro.read")) partes.push("financeiro");
  else if (tem("financeiro.write")) partes.push("financeiro (lança, mas não vê a tela)");
  else if (tem("financeiro.read")) partes.push("financeiro (só ver)");
  if (tem("faturamento.write")) partes.push("faturamento e notas");
  else if (tem("faturamento.read")) partes.push("faturamento (só ver)");
  if (tem("apontamentos.write")) partes.push("apontamentos");
  else if (tem("apontamentos.read")) partes.push("apontamentos (só ver)");
  if (tem("nf_entrada.import")) partes.push("entrada de notas");
  if (tem("admin.manage_users")) partes.push("gerenciar usuários");
  const texto = partes.join(", ");
  return texto.charAt(0).toUpperCase() + texto.slice(1);
}

const wb = XLSX.utils.book_new();
const addSheet = (nome, linhas, larguras) => {
  const ws = XLSX.utils.aoa_to_sheet(linhas);
  ws["!cols"] = larguras.map((w) => ({ wch: w }));
  XLSX.utils.book_append_sheet(wb, ws, nome);
};

// ------------------------------------------------------------------- Aba 1
const linhasUsuarios = [
  ["Usuário", "E-mail", "Papel no sistema", "Empresa", "Papel na empresa", "Vínculo", "Ativo", "O que essa pessoa acessa hoje", "Ações liberadas (de 35)"],
  ...usuarios.map((u) => {
    const combo = `${u.papelTenant} / ${u.papelEmpresa}`;
    const semAcesso = u.vinculo !== "ATIVO" || !u.ativo;
    const medido = porCombo.has(`${combo}::os.read`);
    return [
      u.nome, u.email, u.papelTenant, u.empresa, u.papelEmpresa, u.vinculo === "ATIVO" ? "Ativo" : "Inativo", u.ativo ? "Sim" : "Não",
      semAcesso ? "Sem acesso: o vínculo com esta empresa está inativo" : (medido ? resumo(combo) : "Combinação não medida"),
      semAcesso ? 0 : (medido ? totalRls(combo) : ""),
    ];
  }),
];
addSheet("Usuários", linhasUsuarios, [20, 32, 17, 9, 17, 9, 7, 60, 20]);

// ------------------------------------------------------------------- Aba 2
const linhasMatriz = [
  ["Módulo", "O que a pessoa faz", "Chave técnica", ...combos],
  ...permissoes.map((p) => [p.grupo, p.rotulo, p.permissao, ...combos.map((c) => celula(c, p.permissao))]),
  [],
  ["Total de ações liberadas", "", "", ...combos.map((c) => totalRls(c))],
  [],
  ["Legenda", "SIM = tem acesso · SIM- = tem acesso, mas sem atalho no menu · NÃO* = o menu mostra o caminho e o banco recusa (a tela dá erro) · NÃO = bloqueado"],
];
addSheet("Matriz por papel", linhasMatriz, [18, 38, 30, ...combos.map(() => 22)]);

// ------------------------------------------------------------------- Aba 3
const ativos = usuarios.filter((u) => u.vinculo === "ATIVO" && u.ativo && porCombo.has(`${u.papelTenant} / ${u.papelEmpresa}::os.read`));
// Quem tem vinculo ativo em duas empresas ganha o nome da empresa na coluna.
const repetidos = new Set(ativos.map((u) => u.nome).filter((n, i, a) => a.indexOf(n) !== i));
const linhasPorUsuario = [
  ["Módulo", "O que a pessoa faz", ...ativos.map((u) => (repetidos.has(u.nome) ? `${u.nome} · ${u.empresa}` : u.nome))],
  ["", "Papel na empresa", ...ativos.map((u) => u.papelEmpresa)],
  ["", "Papel no sistema", ...ativos.map((u) => u.papelTenant)],
  ["", "Empresa", ...ativos.map((u) => u.empresa)],
  ...permissoes.map((p) => [p.grupo, p.rotulo, ...ativos.map((u) => celula(`${u.papelTenant} / ${u.papelEmpresa}`, p.permissao))]),
  [],
  ["Total de ações liberadas", "", ...ativos.map((u) => totalRls(`${u.papelTenant} / ${u.papelEmpresa}`))],
];
addSheet("Matriz por usuário", linhasPorUsuario, [18, 38, ...ativos.map(() => 16)]);

// ------------------------------------------------------------------- Aba 4
addSheet("Papéis", [
  ["Tipo", "Papel", "O que significa hoje", "Quem está assim"],
  ["Sistema", "OWNER", "Acesso total a tudo, em qualquer empresa, e pode gerenciar usuários.", quem(usuarios, (u) => u.papelTenant === "OWNER")],
  ["Sistema", "ADMIN", "Acesso total a tudo e pode gerenciar usuários.", quem(usuarios, (u) => u.papelTenant === "ADMIN")],
  ["Sistema", "DIRETOR", "Acesso total a tudo, mas nunca gerencia usuários.", quem(usuarios, (u) => u.papelTenant === "DIRETOR")],
  ["Sistema", "CONTADOR", "Não dá acesso sozinho: vale o papel na empresa.", quem(usuarios, (u) => u.papelTenant === "CONTADOR")],
  ["Sistema", "GESTOR", "Não dá acesso sozinho: vale o papel na empresa.", quem(usuarios, (u) => u.papelTenant === "GESTOR")],
  [],
  ["Empresa", "ADMIN", "Tudo dentro da empresa.", quem(usuarios, (u) => u.papelEmpresa === "ADMIN" && u.vinculo === "ATIVO")],
  ["Empresa", "DIRETOR", "Tudo dentro da empresa, menos gerenciar usuários.", quem(usuarios, (u) => u.papelEmpresa === "DIRETOR" && u.vinculo === "ATIVO")],
  ["Empresa", "FINANCEIRO", "Financeiro, faturamento, compras, estoque, OS e apontamentos.", quem(usuarios, (u) => u.papelEmpresa === "FINANCEIRO" && u.vinculo === "ATIVO")],
  ["Empresa", "FATURAMENTO", "Faturamento e fiscal completos, OS, estoque, compras e apontamentos. Não vê o menu Financeiro.", quem(usuarios, (u) => u.papelEmpresa === "FATURAMENTO" && u.vinculo === "ATIVO")],
  ["Empresa", "COORDENACAO", "OS, estoque, compras, apontamentos, cadastros e entrada de notas.", quem(usuarios, (u) => u.papelEmpresa === "COORDENACAO" && u.vinculo === "ATIVO")],
  ["Empresa", "COMPRAS", "Compras e estoque. Vê OS, mas não grava.", quem(usuarios, (u) => u.papelEmpresa === "COMPRAS" && u.vinculo === "ATIVO")],
  ["Empresa", "ALMOXARIFADO", "Estoque, cadastros, entrada de notas e OS.", quem(usuarios, (u) => u.papelEmpresa === "ALMOXARIFADO" && u.vinculo === "ATIVO")],
  ["Empresa", "APONTAMENTO_RH", "Estoque, cadastros, entrada de notas, OS e apontamentos.", quem(usuarios, (u) => u.papelEmpresa === "APONTAMENTO_RH" && u.vinculo === "ATIVO")],
  ["Empresa", "TECNICO", "Nenhuma regra cita este papel: não libera nada no sistema web.", quem(usuarios, (u) => u.papelEmpresa === "TECNICO" && u.vinculo === "ATIVO")],
  ["Empresa", "PAINEL_TV", "Só enxerga a lista de OS do painel de TV. Nada mais.", quem(usuarios, (u) => u.papelEmpresa === "PAINEL_TV" && u.vinculo === "ATIVO")],
  ["Empresa", "APONTADOR", "Bloqueado no sistema web por regra explícita. É o papel do aplicativo de apontamento.", quem(usuarios, (u) => u.papelEmpresa === "APONTADOR" && u.vinculo === "ATIVO")],
  [],
  ["Como os dois papéis se combinam", "", "", ""],
  ["1", "OWNER, ADMIN e DIRETOR no sistema liberam tudo, qualquer que seja o papel na empresa.", "", ""],
  ["2", "Para GESTOR e CONTADOR, quem manda é o papel na empresa.", "", ""],
  ["3", "APONTADOR na empresa bloqueia tudo no web, mesmo com papel alto no sistema.", "", ""],
  ["4", "Gerenciar usuários exige OWNER ou ADMIN no sistema e não ser DIRETOR na empresa.", "", ""],
  ["5", "Vínculo inativo na empresa remove todo o acesso àquela empresa.", "", ""],
], [12, 18, 78, 46]);

function quem(lista, filtro) {
  const nomes = [...new Set(lista.filter(filtro).map((u) => u.nome))];
  return nomes.length ? nomes.join(", ") : "ninguém";
}

// ------------------------------------------------------------------- Aba 5
const divergencias = [];
for (const c of combos) {
  for (const p of permissoes) {
    const r = porCombo.get(`${c}::${p.permissao}`);
    if (!r) continue;
    const rls = bool(r.rls); const rpc = bool(r.rpc); const menu = bool(r.menu);
    if (rls === rpc && rls === menu) continue;
    divergencias.push([
      c, p.grupo, p.rotulo, p.permissao,
      rls ? "Sim" : "Não", rpc ? "Sim" : "Não", menu ? "Sim" : "Não",
      !rls && menu ? "O menu mostra o caminho e o banco recusa: a pessoa vê a opção e recebe erro."
        : rls && !rpc ? "A tela abre e os dados aparecem, mas algumas ações por botão podem recusar."
        : rls && !menu ? "A pessoa tem o acesso, mas precisa chegar por outra tela: não há atalho no menu."
        : "Divergência entre as três camadas; conferir caso a caso.",
    ]);
  }
}
addSheet("Onde as camadas divergem", [
  ["Papéis", "Módulo", "O que a pessoa faz", "Chave técnica", "Banco libera (RLS)", "Ação por botão (RPC)", "Menu mostra", "Efeito prático"],
  ...divergencias,
], [26, 16, 36, 28, 18, 20, 13, 80]);

// ------------------------------------------------------------------- Aba 6
const acessoTotal = [...new Map(
  usuarios
    .filter((u) => u.vinculo === "ATIVO" && u.ativo && totalRls(`${u.papelTenant} / ${u.papelEmpresa}`) >= 34)
    .map((u) => [u.nome, u]),
).values()];
const sguAtivos = [...new Set(usuarios.filter((u) => u.empresa === "SGU" && u.vinculo === "ATIVO" && u.ativo).map((u) => u.nome))];
const coordenacao = quem(usuarios, (u) => u.papelEmpresa === "COORDENACAO" && u.vinculo === "ATIVO");
addSheet("Pontos de atenção", [
  ["#", "O que foi encontrado", "Quem é afetado", "Sugestão"],
  [1, `${acessoTotal.length} pessoas têm acesso praticamente total ao sistema, incluindo financeiro e faturamento.`,
    acessoTotal.map((u) => `${u.nome} (${u.papelTenant}/${u.papelEmpresa})`).join(", "),
    "Confirmar se todas precisam desse nível. O papel no sistema (OWNER/ADMIN/DIRETOR) libera tudo e ignora o papel da empresa."],
  [2, "Um usuário de teste tem acesso total e está ativo.", "gabriel teste (gabrielgolombieschi@gmail.com)",
    "Desativar se não estiver em uso."],
  [3, "A COORDENACAO lança no financeiro, mas não consegue abrir a tela do financeiro.", coordenacao,
    "Decidir: ou liberar a leitura, ou tirar a escrita. Hoje a permissão é incoerente."],
  [4, "COMPRAS e PAINEL_TV veem 'criar/editar OS' no menu e o banco recusa a gravação.", quem(usuarios, (u) => ["COMPRAS", "PAINEL_TV"].includes(u.papelEmpresa) && u.vinculo === "ATIVO"),
    "Tirar o item do menu para esses papéis, ou liberar de verdade."],
  [5, "O menu de Imobilizado aparece para papéis que o banco recusa.", quem(usuarios, (u) => ["COORDENACAO", "COMPRAS", "ALMOXARIFADO", "APONTAMENTO_RH"].includes(u.papelEmpresa) && u.vinculo === "ATIVO"),
    "Alinhar o menu com a permissão real do imobilizado."],
  [6, "Parte do acesso da COORDENACAO vem do modelo antigo de permissões (tenant_memberships), não do papel escolhido na tela de usuários.", coordenacao,
    "Migrar essas permissões para o papel da empresa, senão mudar o papel na tela não muda o acesso real."],
  [7, "TECNICO não libera nada no sistema web.", quem(usuarios, (u) => u.papelEmpresa === "TECNICO"),
    "Se esse papel deveria dar algum acesso, ele precisa ser definido; hoje é equivalente a não ter papel."],
  [8, `Na SGU AUTOMAÇÃO só ${sguAtivos.length} vínculos estão ativos; o resto do time está inativo lá.`, sguAtivos.join(", "),
    "Confirmar se essa é a intenção: quem está inativo não enxerga nada da SGU."],
], [5, 86, 46, 66]);

// ------------------------------------------------------------------- Aba 7
addSheet("Como foi medido", [
  ["Item", "Detalhe"],
  ["Data da medição", new Date().toLocaleDateString("pt-BR")],
  ["Origem", "Banco de produção do ERP, projeto Supabase vinculado."],
  ["Método", "Cada usuário foi impersonado em transação READ ONLY e as 35 ações foram consultadas uma a uma. Nenhuma escrita foi feita."],
  ["Banco libera (RLS)", "public.can__legacy_40734 — é o que guarda as tabelas. Se diz não, a pessoa não vê nem grava o dado."],
  ["Ação por botão (RPC)", "public.can — guarda funções e Edge Functions (emitir nota, executar ações da OS)."],
  ["Menu mostra", "public.get_full_permissions — mapa que o navegador recebe para montar o menu."],
  ["Ressalva 1", "O papel PAINEL_TV tem uma regra própria que deixa ver a lista de OS do painel; isso não aparece nas 35 ações medidas."],
  ["Ressalva 2", "Usuários com vínculo inativo em uma empresa não têm nenhum acesso àquela empresa, qualquer que seja o papel gravado."],
  ["Ressalva 3", "Parte do acesso da COORDENACAO vem do modelo antigo de permissões (tenant_memberships), não do papel da empresa."],
  ["Reproduzir", "node scripts/medir-acessos-usuarios.mjs > acessos.txt && node scripts/gerar-planilha-permissoes.mjs acessos.txt usuarios.txt saida.xlsx"],
], [24, 118]);

fs.mkdirSync(path.dirname(path.resolve(saidaPath)), { recursive: true });
XLSX.writeFile(wb, path.resolve(saidaPath));
console.log("Planilha:", path.resolve(saidaPath));
console.log(`${usuarios.length} vínculos · ${combos.length} combinações de papel · ${permissoes.length} ações · ${divergencias.length} divergências`);
