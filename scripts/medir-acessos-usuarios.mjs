/**
 * Mede o acesso efetivo de cada usuario ativo, impersonando-o no banco em
 * modo somente leitura (nenhuma escrita; apenas set_config da sessao).
 *
 * Tres portoes medidos, porque nao sao o mesmo:
 *   rls   = public.can__legacy_40734  -> guarda as tabelas (RLS), o portao real
 *   rpc   = public.can                -> guarda RPCs e Edge Functions
 *   menu  = public.get_full_permissions -> mapa que o navegador recebe
 *
 *   node scripts/medir-acessos-usuarios.mjs > acessos.txt
 */
import { execFileSync, execSync } from "node:child_process";

// Credenciais do CLI ja autenticado, como em scripts/db-query.js: nunca lidas
// de .env nem impressas. Toda consulta roda em transacao READ ONLY, de modo que
// o proprio banco recusa qualquer escrita (garantia mais forte que um filtro de
// texto: o nome de acao "delete" aparece nas permissoes medidas).
const dryRun = execSync("supabase db dump --data-only -s public --dry-run", { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
const cred = (nome) => {
  const m = dryRun.match(new RegExp(`export ${nome}="([^"]*)"`));
  if (!m) throw new Error(`Nao encontrei ${nome} na saida do supabase CLI.`);
  return m[1];
};

const PROBES = [
  ["os", "read", "Ordens de serviço", "Ver OS"],
  ["os", "write", "Ordens de serviço", "Criar/editar OS"],
  ["os", "delete", "Ordens de serviço", "Excluir OS"],
  ["os_rpcs", "execute", "Ordens de serviço", "Executar ações da OS (itens, baixas)"],
  ["os_gestao", "write", "Ordens de serviço", "Gestão da OS (fluxo, cobrança)"],
  ["os_itens", "write", "Ordens de serviço", "Lançar itens na OS"],
  ["apontamentos", "read", "Apontamentos", "Ver apontamentos de horas"],
  ["apontamentos", "write", "Apontamentos", "Lançar/editar apontamentos"],
  ["apontamentos", "delete", "Apontamentos", "Excluir apontamentos"],
  ["apontamentos", "config", "Apontamentos", "Configurar apontamentos"],
  ["estoque", "read", "Estoque", "Ver estoque"],
  ["estoque", "write", "Estoque", "Movimentar/ajustar estoque"],
  ["estoque_custos", "cost_read", "Estoque", "Ver custos do estoque"],
  ["cad_itens", "write", "Cadastros", "Cadastrar/editar itens"],
  ["cad_clientes", "write", "Cadastros", "Cadastrar/editar clientes"],
  ["cad_fornecedores", "write", "Cadastros", "Cadastrar/editar fornecedores"],
  ["compras", "read", "Compras", "Ver pedidos de compra"],
  ["compras", "write", "Compras", "Criar/editar pedidos de compra"],
  ["compras", "approve", "Compras", "Aprovar pedidos de compra"],
  ["compras", "receive", "Compras", "Receber pedidos de compra"],
  ["financeiro", "read", "Financeiro", "Ver financeiro"],
  ["financeiro", "write", "Financeiro", "Lançar/baixar no financeiro"],
  ["faturamento", "read", "Faturamento", "Ver faturamento"],
  ["faturamento", "write", "Faturamento", "Emitir/cancelar notas"],
  ["faturamento", "nfe.import_xml", "Faturamento", "Importar XML no faturamento"],
  ["fiscal_nf", "read", "Fiscal", "Ver notas fiscais"],
  ["fiscal_nf", "write", "Fiscal", "Editar notas fiscais"],
  ["fiscal_nf", "delete", "Fiscal", "Excluir notas fiscais"],
  ["fiscal_itens", "write", "Fiscal", "Editar dados fiscais do item"],
  ["xml_import", "execute", "Fiscal", "Importar XML de entrada"],
  ["xml_import_faturamento", "execute", "Fiscal", "Importar XML pelo faturamento"],
  ["nf_entrada", "import", "Fiscal", "Importar NF de entrada"],
  ["imobilizado", "read", "Imobilizado", "Ver imobilizado e ferramentas"],
  ["imobilizado", "write", "Imobilizado", "Editar imobilizado e ferramentas"],
  ["admin", "manage_users", "Administração", "Gerenciar usuários e papéis"],
];

function consultar(sql) {
  return execFileSync("docker", [
    "run", "--rm", "-i", "-e", `PGPASSWORD=${cred("PGPASSWORD")}`, "postgres:16-alpine",
    "psql", "-h", cred("PGHOST"), "-p", cred("PGPORT"), "-U", cred("PGUSER"), "-d", cred("PGDATABASE"),
    "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-f", "-",
  ], { encoding: "utf8", maxBuffer: 32 * 1024 * 1024, input: `begin;\nset transaction read only;\n${sql}\ncommit;\n` });
}

function linhasPipe(saida) {
  return saida.split(/\r?\n/).map((l) => l.trim()).filter((l) => l.includes("|") && !/^-+\+|^\(\d+ rows?\)/.test(l) && !/^linha\s*$/.test(l));
}

const usuarios = linhasPipe(consultar(`set role postgres;
select u.nome || '|' || u.email || '|' || u.auth_user_id || '|' || upper(coalesce(ut.papel,'')) as linha
from a.usuario u
join a.usuario_tenant ut on ut.usuario_id = u.id and ut.ativo and ut.deleted_at is null
where u.ativo and u.deleted_at is null and u.auth_user_id is not null
  and exists (select 1 from a.usuario_empresa ue where ue.usuario_id = u.id and ue.ativo and ue.deleted_at is null)
order by u.nome;`)).map((l) => {
  const [nome, email, authId, papelTenant] = l.split("|").map((s) => s.trim());
  return { nome, email, authId, papelTenant };
});

const valores = PROBES.map(([r, a]) => `('${r}','${a}')`).join(",");
console.log("usuario|email|papel_tenant|empresa|papel_empresa|grupo|rotulo|permissao|rls|rpc|menu");

for (const u of usuarios) {
  const claims = `{"sub":"${u.authId}","role":"authenticated"}`;
  const sql = `set role postgres;
select set_config('request.jwt.claim.sub','${u.authId}',true) as a,
       set_config('request.jwt.claim.role','authenticated',true) as b,
       set_config('request.jwt.claims','${claims}',true) as c;
set role authenticated;
select coalesce(e.codigo,'?') || '|' || upper(coalesce(ue.papel,'?')) || '|' || p.resource || '.' || p.action
       || '|' || coalesce(public.can__legacy_40734(p.resource, p.action), false)::text
       || '|' || coalesce(public.can(p.resource, p.action, public.current_tenant_id()), false)::text
       || '|' || coalesce((public.get_full_permissions(public.current_tenant_id(), public.current_empresa_id()) ->> (p.resource || '.' || p.action))::boolean, false)::text as linha
from (values ${valores}) as p(resource, action)
left join c.empresa e on e.id = public.current_empresa_id()
left join a.usuario au on au.auth_user_id = '${u.authId}'::uuid
left join a.usuario_empresa ue on ue.usuario_id = au.id and ue.empresa_id = public.current_empresa_id() and ue.ativo and ue.deleted_at is null;`;
  let saida;
  try { saida = consultar(sql); } catch (cause) { console.error("falhou", u.nome, String(cause).slice(0, 200)); continue; }
  const linhas = linhasPipe(saida);
  for (const linha of linhas) {
    const partes = linha.split("|").map((s) => s.trim());
    if (partes.length !== 6) continue;
    const [empresa, papelEmpresa, permissao, rls, rpc, menu] = partes;
    const probe = PROBES.find(([r, a]) => `${r}.${a}` === permissao);
    if (!probe) continue;
    console.log([u.nome, u.email, u.papelTenant, empresa, papelEmpresa, probe[2], probe[3], permissao, rls, rpc, menu].join("|"));
  }
}
