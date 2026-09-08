-- Fonte unica da meta de faturamento.
--
-- Hoje o numero existe em dois lugares: f.meta_faturamento, que o app le, e a
-- constante FATURAMENTO_TARGETS_BY_YEAR no cliente web
-- (app/faturamento/analitico/AnaliticoFaturamentoClient.tsx). Mudar a meta em
-- so um deles faz as duas telas discordarem sem ninguem perceber.
--
-- Esta funcao e o que faltava para o web tambem ler da tabela. A tabela esta
-- com RLS ligada e sem policy de proposito, entao o navegador nao le direto —
-- a leitura passa por aqui, com o mesmo portao do resto do analitico
-- (f.has_finance_access), empresa por empresa.
--
-- Devolve uma linha por empresa e ano pedidos. Empresa sem meta cadastrada
-- simplesmente nao aparece, e cabe a tela dizer isso ao usuario em vez de
-- assumir zero: hoje a SGU AUTOMACAO nao tem meta, e somar zero faria parecer
-- que a meta do grupo foi superada.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

create or replace function f.meta_faturamento_listar(
  p_empresa_ids uuid[],
  p_ano_de integer,
  p_ano_ate integer
)
returns table(empresa_id uuid, ano integer, valor_mensal numeric)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'f', 'public', 'c', 'a'
set row_security to 'off'
as $function$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_ids uuid[];
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Usuario nao autenticado';
  end if;
  if v_tenant_id is null then
    raise exception using errcode = '42501', message = 'Tenant nao carregado na sessao';
  end if;
  if p_empresa_ids is null or cardinality(p_empresa_ids) = 0 then
    raise exception using errcode = '22023', message = 'Informe ao menos uma empresa';
  end if;
  if p_ano_de is null or p_ano_ate is null or p_ano_ate < p_ano_de then
    raise exception using errcode = '22023', message = 'Periodo de anos invalido';
  end if;

  select array_agg(distinct pedido.empresa_id order by pedido.empresa_id)
    into v_empresa_ids
  from unnest(p_empresa_ids) as pedido(empresa_id)
  where pedido.empresa_id is not null;

  -- Mesma checagem que f.faturamento_analitico_documentos faz: a empresa
  -- precisa existir no tenant e o usuario precisa de acesso financeiro nela.
  if exists (
    select 1
    from unnest(v_empresa_ids) as pedido(empresa_id)
    left join c.empresa as empresa
      on empresa.id = pedido.empresa_id
     and empresa.tenant_id = v_tenant_id
     and empresa.deleted_at is null
    where empresa.id is null
       or not f.has_finance_access(v_tenant_id, pedido.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para uma ou mais empresas solicitadas';
  end if;

  return query
  select meta.empresa_id, meta.ano, meta.valor_mensal
  from f.meta_faturamento as meta
  where meta.tenant_id = v_tenant_id
    and meta.empresa_id = any(v_empresa_ids)
    and meta.ano between p_ano_de and p_ano_ate
  order by meta.empresa_id, meta.ano;
end;
$function$;

revoke all on function f.meta_faturamento_listar(uuid[], integer, integer) from public, anon;
grant execute on function f.meta_faturamento_listar(uuid[], integer, integer) to authenticated;

notify pgrst, 'reload schema';

commit;
