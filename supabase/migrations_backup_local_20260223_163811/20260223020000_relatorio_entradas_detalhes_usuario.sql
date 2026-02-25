-- Entradas no periodo (detalhes): incluir usuario que realizou a movimentacao

drop function if exists public.rel_entradas_periodo_detalhes(
  uuid,
  uuid,
  date,
  date,
  integer,
  integer,
  text,
  boolean
);

create or replace function public.rel_entradas_periodo_detalhes(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_data_ini date,
  p_data_fim date,
  p_item_id integer,
  p_fornecedor_id integer default null,
  p_os_mode text default 'todos',
  p_com_nf boolean default false
)
returns table (
  movimentacao_id integer,
  data_movimentacao timestamp without time zone,
  nf text,
  quantidade numeric,
  os_id integer,
  tipo text,
  realizado_por text
)
language sql
stable
as $$
  select
    m.id as movimentacao_id,
    m.data_movimentacao,
    coalesce(nf.numero::text, '-') as nf,
    m.quantidade::numeric as quantidade,
    m.origem_os_id as os_id,
    case when m.origem_os_id is not null then 'DIRETO OS' else 'ENTRADA ESTOQUE' end as tipo,
    nullif(trim(m.realizado_por), '') as realizado_por
  from public.movimentacoes m
  join public.itens i
    on i.id = m.item_id
   and i.tenant_id = m.tenant_id
   and i.empresa_id = m.empresa_id
  left join public.nf_entrada nf
    on nf.id = m.origem_nf_entrada_id
   and nf.tenant_id = m.tenant_id
   and nf.empresa_id = m.empresa_id
  where m.tenant_id = p_tenant_id
    and m.empresa_id = p_empresa_id
    and m.tipo = 'entrada'
    and m.item_id = p_item_id
    and m.data_movimentacao::date between p_data_ini and p_data_fim
    and (
      (p_fornecedor_id is null and coalesce(nf.fornecedor_id::integer, i.fornecedor_id) is null)
      or coalesce(nf.fornecedor_id::integer, i.fornecedor_id) = p_fornecedor_id
    )
    and (
      p_os_mode = 'todos'
      or (p_os_mode = 'com_os' and m.origem_os_id is not null)
      or (p_os_mode = 'sem_os' and m.origem_os_id is null)
    )
    and (not p_com_nf or m.origem_nf_entrada_id is not null)
  order by m.data_movimentacao desc, m.id desc;
$$;
