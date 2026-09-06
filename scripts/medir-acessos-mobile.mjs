/**
 * Mede o que cada papel enxerga no aplicativo mobile, impersonando um usuario
 * real de cada papel e chamando as RPCs do app em transacao READ ONLY.
 * Nenhuma escrita e feita: as RPCs de lancamento nao sao chamadas; para elas
 * vale a regra de papel lida do proprio codigo (coluna "regra").
 *
 *   node scripts/medir-acessos-mobile.mjs > mobile.txt
 */
import { execFileSync, execSync } from "node:child_process";

const dryRun = execSync("supabase db dump --data-only -s public --dry-run", { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
const cred = (nome) => {
  const m = dryRun.match(new RegExp(`export ${nome}="([^"]*)"`));
  if (!m) throw new Error(`Nao encontrei ${nome} na saida do supabase CLI.`);
  return m[1];
};
// Uma conexao por papel (o pooler derruba conexoes se abrirmos uma por consulta).
// stderr entra no stdout para que a mensagem de recusa fique junto do marcador.
function psql(sql, comErros = false) {
  const cmd = `psql -h ${cred("PGHOST")} -p ${cred("PGPORT")} -U ${cred("PGUSER")} -d ${cred("PGDATABASE")} -X -q -t -A -f -${comErros ? " 2>&1" : ""}`;
  return execFileSync("docker", [
    "run", "--rm", "-i", "-e", `PGPASSWORD=${cred("PGPASSWORD")}`, "postgres:16-alpine", "sh", "-c", cmd,
  ], { encoding: "utf8", maxBuffer: 32 * 1024 * 1024, input: sql });
}

// Telas e acoes do app. "chamada" nula = acao de escrita, medida pela regra de
// papel lida do codigo (nao chamamos para nao gravar nada).
const ITENS = [
  ["Aba OS", "Abrir a lista de OS", "select count(*) from public.app_listar_os_fluxo(null, null)", null],
  ["Aba OS", "Ver OS agrupadas por cliente", "select count(*) from public.app_os_agrupado_cliente(null, null)", null],
  ["Aba OS", "Ver valores da OS (orçado, faturado, gasto)", "select public.app_mobile_pode_ver_valores_os(public.current_tenant_id(), public.current_empresa_id())::text", null],
  ["Aba OS", "Ver apontamentos de horas da OS", "select count(*) from public.app_listar_apontamentos(null, null, null, null)", null],
  ["Aba OS", "Ver materiais lançados na OS", "select count(*) from public.app_listar_materiais_os((select id from public.app_listar_os_fluxo(null, null) limit 1))", null],
  ["Aba Estoque", "Consultar o estoque", "select count(*) from public.app_consultar_estoque(null, true, 5, 0)", null],
  ["Aba Estoque", "Ver preço e custo do item", null, "TELA: escondido para TECNICO, APONTAMENTO_RH e APONTADOR"],
  ["Aba Histórico", "Ver o próprio histórico de lançamentos", "select count(*) from public.app_historico_lancamentos('horas', null, null, null, null, 5, null)", null],
  ["Aba Histórico", "Ver o histórico de toda a equipe", null, "RPC: TECNICO, APONTAMENTO_RH e APONTADOR veem só os próprios lançamentos"],
  ["Aba Aprovações", "Abrir a aba de aprovações", "select count(*) from public.app_listar_aprovacoes_pendentes()", null],
  ["Aba Aprovações", "Aprovar horas da equipe", null, "TELA: aba escondida para TECNICO, APONTAMENTO_RH e APONTADOR"],
  ["Aba Perfil", "Ver minhas horas do mês e do ano", "select count(*) from public.app_minhas_horas_mes(extract(year from current_date)::int, extract(month from current_date)::int)", null],
  ["Aba Perfil", "Ver o resumo do mês", "select count(*) from public.app_resumo_mes()", null],
  ["Aba Perfil", "Ver notificações", "select count(*) from public.app_listar_notificacoes(5, null)", null],
  ["Cadastros", "Ver a lista de colaboradores", "select count(*) from public.app_listar_colaboradores()", null],
  ["Cadastros", "Ver clientes de HH", "select count(*) from public.app_listar_clientes_hh()", null],
  ["Cadastros", "Ver os tipos de hora", "select count(*) from public.app_listar_tipos_horas()", null],
  ["Lançar", "Lançar horas na OS", null, "RPC: ADMIN, DIRETOR, COORDENACAO, TECNICO, APONTAMENTO_RH e APONTADOR"],
  ["Lançar", "Lançar horas para outra pessoa", null, "RPC: APONTAMENTO_RH e APONTADOR lançam só para si"],
  ["Lançar", "Lançar HH (entrada e saída)", null, "RPC: ADMIN, DIRETOR, COORDENACAO, TECNICO, APONTAMENTO_RH e APONTADOR"],
  ["Lançar", "Lançar material na OS", null, "RPC: qualquer papel com acesso à OS; a OS precisa estar em andamento"],
  ["Lançar", "Corrigir ou remover material", null, "RPC: só quem lançou, e só o que foi lançado pelo app"],
  ["Lançar", "Criar OS de HH pelo app", null, "RPC: bloqueado para APONTAMENTO_RH e APONTADOR"],
  ["Editar", "Editar apontamento antes da aprovação", null, "TELA: só o próprio colaborador"],
  ["Editar", "Editar apontamento depois de aprovado", null, "TELA: ADMIN, DIRETOR e COORDENACAO"],
  ["Editar", "Cancelar ou restaurar apontamento", null, "RPC: ADMIN, DIRETOR e COORDENACAO"],
];

const usuariosSql = `set role postgres;
select distinct on (upper(ue.papel))
       upper(ue.papel) || '|' || u.nome || '|' || u.auth_user_id
from a.usuario u
join a.usuario_tenant ut on ut.usuario_id = u.id and ut.ativo and ut.deleted_at is null
join a.usuario_empresa ue on ue.usuario_id = u.id and ue.ativo and ue.deleted_at is null
where u.ativo and u.deleted_at is null and u.auth_user_id is not null
order by upper(ue.papel), u.nome;`;

const papeis = psql(usuariosSql).split(/\r?\n/).map((l) => l.trim()).filter((l) => l.includes("|")).map((l) => {
  const [papel, nome, authId] = l.split("|");
  return { papel, nome, authId };
});

console.log("papel|representante|grupo|item|resultado|detalhe");
for (const p of papeis) {
  const chamadas = ITENS.map((it, i) => [i, it]).filter(([, it]) => it[2]);
  const preparo = `begin;\nset transaction read only;\nset local role postgres;\nselect set_config('request.jwt.claim.sub','${p.authId}',true), set_config('request.jwt.claim.role','authenticated',true), set_config('request.jwt.claims','{"sub":"${p.authId}","role":"authenticated"}',true);\nset local role authenticated;`;
  const sql = ["\\set ON_ERROR_STOP off", ...chamadas.map(([i, it]) => `\\echo @@${i}\n${preparo}\n${it[2]};\ncommit;`)].join("\n");
  let saida = "";
  try { saida = psql(sql, true); } catch (cause) { saida = String(cause.stdout ?? "") + String(cause.stderr ?? ""); }

  // A saida vem em blocos separados por @@<indice>; dentro de cada bloco fica o
  // valor devolvido ou a mensagem de recusa.
  const blocos = new Map();
  let atual = null;
  for (const linha of saida.split(/\r?\n/)) {
    const marca = linha.match(/^@@(\d+)\s*$/);
    if (marca) { atual = Number(marca[1]); blocos.set(atual, []); continue; }
    if (atual !== null && linha.trim()) blocos.get(atual).push(linha.trim());
  }

  for (const [indice, [grupo, item, chamada, regra]] of ITENS.map((it, i) => [i, it])) {
    if (!chamada) { console.log([p.papel, p.nome, grupo, item, "REGRA", regra].join("|")); continue; }
    const linhas = (blocos.get(indice) ?? []).filter((l) => !/^(SET|BEGIN|COMMIT|ROLLBACK)$/.test(l) && !/^set_config/.test(l) && !l.includes("|t|"));
    const erro = linhas.find((l) => /^psql:.*ERROR:|^ERROR:/.test(l));
    const valor = [...linhas].reverse().find((l) => !/^(CONTEXT|DETAIL|HINT|LINE|PL\/pgSQL|SQL statement|\s)/.test(l) && !/ERROR:/.test(l)) ?? "";
    let resultado;
    let detalhe = "";
    if (erro) {
      const msg = erro.replace(/^.*ERROR:\s*/, "").trim();
      // Duas causas bem diferentes: a regra do papel recusa, ou falta ligar o
      // usuario a um colaborador ativo (condicao de cadastro, nao de papel).
      resultado = /colaborador/i.test(msg) ? "FALTA VÍNCULO" : "NÃO";
      detalhe = msg.slice(0, 120);
    } else if (valor === "true") { resultado = "SIM"; }
    else if (valor === "false") { resultado = "NÃO"; detalhe = "a função respondeu não"; }
    else if (/^\d+$/.test(valor)) { resultado = "SIM"; detalhe = `${valor} registros`; }
    else if (valor === "") { resultado = "?"; detalhe = "sem resposta"; }
    else { resultado = "SIM"; detalhe = valor.slice(0, 60); }
    console.log([p.papel, p.nome, grupo, item, resultado, detalhe].join("|"));
  }
}
