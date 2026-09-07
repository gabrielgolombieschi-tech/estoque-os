-- Correcao da 20260907190000: o painel de orcamentos passa a usar a data REAL
-- do fechamento e da perda, e nao mais a safra de emissao.
--
-- Na primeira versao eu disse que nao havia como saber quando um orcamento
-- fechou, porque m.fn_orcamento_atualizar_status so grava status, observacoes,
-- valor_fechado, os_id e updated_at. Isso e verdade sobre a tabela, mas eu nao
-- tinha olhado a public.audit_log: ela registra cada UPDATE de m.orcamento com
-- old_data e new_data desde 12/02/2026, entao a transicao de status esta la,
-- com data e hora.
--
-- Conferido antes de mexer: os 131 FECHADO e os 26 PERDIDO da ELETRICA SEGAU
-- tem 100% de evento de transicao, espalhados pelos dias (nao e carga em lote).
-- E a diferenca importa: cerca de METADE dos orcamentos fecha em mes diferente
-- do que foi emitido — em julho, 12 dos 24; em agosto, 10 dos 27. Pela safra,
-- esses valores caiam no mes errado.
--
-- Agora sao tres series independentes:
--   orcado  = por emissao_date
--   fechado = pela data em que virou FECHADO
--   perdido = pela data em que virou PERDIDO
--
-- Sobre custo: audit_log tem 787 MB e nao ha indice por row_pk, mas existe
-- (table_name, created_at). Filtrar table_name = 'orcamento' reduz para poucos
-- milhares de linhas, varridas uma vez so na CTE — nao ha subconsulta por
-- orcamento.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

create or replace function public.app_orcamento_painel(p_ano integer, p_mes integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'm'
set row_security to 'off'
as $function$
declare
  v_scope record;
  v_ano integer := coalesce(p_ano, extract(year from current_date)::integer);
  v_mes integer := coalesce(p_mes, extract(month from current_date)::integer);
  v_meses jsonb;
  v_clientes jsonb;
  v_orcado_ano numeric;
  v_fechado_ano numeric;
  v_orcado_mes numeric;
  v_fechado_mes numeric;
  v_perdido_mes numeric;
  v_qtd_orcada integer;
  v_qtd_fechada integer;
begin
  select * into v_scope from public.app_orcamento_assert_acesso();

  if v_mes < 1 or v_mes > 12 then
    raise exception 'Mês inválido.';
  end if;

  with desfecho as (
    -- Ultima transicao para FECHADO ou PERDIDO de cada orcamento.
    select distinct on (evento.row_pk)
      evento.row_pk,
      evento.new_data->>'status' as status_final,
      (evento.created_at at time zone 'America/Sao_Paulo')::date as data_desfecho
    from public.audit_log as evento
    where evento.table_name = 'orcamento'
      and evento.tenant_id = v_scope.tenant_id
      and evento.old_data is not null
      and evento.old_data->>'status' is distinct from evento.new_data->>'status'
      and evento.new_data->>'status' in ('FECHADO', 'PERDIDO')
    order by evento.row_pk, evento.created_at desc
  ),
  base as (
    select
      orcamento.cliente_id,
      coalesce(nullif(btrim(cliente.nome), ''), 'Cliente não informado')::text as cliente_nome,
      orcamento.total_liquido,
      orcamento.emissao_date,
      -- So vale como desfecho se bater com o status atual: um orcamento que
      -- fechou e voltou para andamento nao conta como fechado.
      case when desfecho.status_final = orcamento.status then desfecho.data_desfecho end as data_desfecho,
      case when desfecho.status_final = orcamento.status then desfecho.status_final end as status_desfecho
    from m.orcamento as orcamento
    left join public.clientes as cliente
      on cliente.id = orcamento.cliente_id
     and cliente.tenant_id = orcamento.tenant_id
    left join desfecho
      on desfecho.row_pk = orcamento.id::text
    where orcamento.tenant_id = v_scope.tenant_id
      and orcamento.empresa_id = v_scope.empresa_id
      and orcamento.deleted_at is null
      -- Entra quem foi emitido no ano OU teve desfecho no ano: um orcamento de
      -- dezembro que fecha em janeiro precisa aparecer nos dois lugares certos.
      and (
        (orcamento.emissao_date >= make_date(v_ano, 1, 1) and orcamento.emissao_date < make_date(v_ano + 1, 1, 1))
        or (
          desfecho.status_final = orcamento.status
          and desfecho.data_desfecho >= make_date(v_ano, 1, 1)
          and desfecho.data_desfecho < make_date(v_ano + 1, 1, 1)
        )
      )
  ),
  emitido as (
    select
      extract(month from base.emissao_date)::integer as mes,
      base.total_liquido,
      base.cliente_id,
      base.cliente_nome
    from base
    where extract(year from base.emissao_date)::integer = v_ano
  ),
  encerrado as (
    select
      extract(month from base.data_desfecho)::integer as mes,
      base.status_desfecho,
      base.total_liquido,
      base.cliente_id,
      base.cliente_nome
    from base
    where base.data_desfecho is not null
      and extract(year from base.data_desfecho)::integer = v_ano
  ),
  por_mes as (
    select
      serie.mes,
      coalesce((select sum(e.total_liquido) from emitido e where e.mes = serie.mes), 0)::numeric as orcado,
      coalesce((select sum(f.total_liquido) from encerrado f where f.mes = serie.mes and f.status_desfecho = 'FECHADO'), 0)::numeric as fechado,
      coalesce((select sum(p.total_liquido) from encerrado p where p.mes = serie.mes and p.status_desfecho = 'PERDIDO'), 0)::numeric as perdido,
      coalesce((select count(*) from emitido e where e.mes = serie.mes), 0)::integer as qtd_orcada,
      coalesce((select count(*) from encerrado f where f.mes = serie.mes and f.status_desfecho = 'FECHADO'), 0)::integer as qtd_fechada
    from generate_series(1, 12) as serie(mes)
  ),
  -- Um cliente pode so ter orcado no mes, so ter fechado (proposta de mes
  -- anterior) ou as duas coisas. A chave e coalesce(cliente_id, -1) para o
  -- "sem cliente" casar por igualdade — FULL JOIN nao aceita
  -- "is not distinct from".
  cliente_orcado as (
    select coalesce(cliente_id, -1) as chave, min(cliente_nome) as nome, sum(total_liquido) as orcado
    from emitido where mes = v_mes group by 1
  ),
  cliente_fechado as (
    select coalesce(cliente_id, -1) as chave, min(cliente_nome) as nome, sum(total_liquido) as fechado
    from encerrado where mes = v_mes and status_desfecho = 'FECHADO' group by 1
  ),
  clientes_mes as (
    select
      nullif(coalesce(e.chave, f.chave), -1) as cliente_id,
      coalesce(e.nome, f.nome) as nome,
      coalesce(e.orcado, 0) as orcado,
      coalesce(f.fechado, 0) as fechado
    from cliente_orcado e
    full outer join cliente_fechado f on f.chave = e.chave
    order by greatest(coalesce(e.orcado, 0), coalesce(f.fechado, 0)) desc
    limit 15
  )
  select
    (select jsonb_agg(jsonb_build_object('mes', mes, 'orcado', orcado, 'fechado', fechado, 'perdido', perdido) order by mes) from por_mes),
    (select coalesce(sum(orcado), 0) from por_mes),
    (select coalesce(sum(fechado), 0) from por_mes),
    (select coalesce(sum(orcado), 0) from por_mes where mes = v_mes),
    (select coalesce(sum(fechado), 0) from por_mes where mes = v_mes),
    (select coalesce(sum(perdido), 0) from por_mes where mes = v_mes),
    (select coalesce(sum(qtd_orcada), 0)::integer from por_mes where mes = v_mes),
    (select coalesce(sum(qtd_fechada), 0)::integer from por_mes where mes = v_mes),
    (
      select coalesce(jsonb_agg(jsonb_build_object(
        'cliente_id', cliente_id,
        'nome', nome,
        'orcado', orcado,
        'fechado', fechado
      )), '[]'::jsonb)
      from clientes_mes
    )
    into v_meses, v_orcado_ano, v_fechado_ano, v_orcado_mes, v_fechado_mes,
         v_perdido_mes, v_qtd_orcada, v_qtd_fechada, v_clientes;

  return jsonb_build_object(
    'ano', v_ano,
    'mes', v_mes,
    'orcado_ano', coalesce(v_orcado_ano, 0),
    'fechado_ano', coalesce(v_fechado_ano, 0),
    'orcado_mes', coalesce(v_orcado_mes, 0),
    'fechado_mes', coalesce(v_fechado_mes, 0),
    'perdido_mes', coalesce(v_perdido_mes, 0),
    'quantidade_mes', coalesce(v_qtd_orcada, 0),
    'quantidade_fechada_mes', coalesce(v_qtd_fechada, 0),
    'meses', coalesce(v_meses, '[]'::jsonb),
    'clientes', coalesce(v_clientes, '[]'::jsonb)
  );
end;
$function$;

revoke all on function public.app_orcamento_painel(integer, integer) from public, anon;
grant execute on function public.app_orcamento_painel(integer, integer) to authenticated;

notify pgrst, 'reload schema';

commit;
