-- Ajuste: incluir coluna "motivo" no consolidado de entradas

drop function if exists public.rel_entradas_periodo_consolidado(
  uuid,
  uuid,
  date,
  date,
  text,
  text,
  text,
  boolean,
  boolean
);

create or replace function public.rel_entradas_periodo_consolidado(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_data_ini date,
  p_data_fim date,
  p_fornecedor_prefix text default null,
  p_busca_item text default null,
  p_os_mode text default 'todos',
  p_com_nf boolean default false,
  p_destacar_saldo_alto boolean default false
)
returns table (
  item_id integer,
  fornecedor_id integer,
  codigo_interno text,
  item_nome text,
  fornecedor_nome text,
  motivo text,
  unidade_medida text,
  qtd_comprada numeric,
  qtd_para_os numeric,
  qtd_para_estoque numeric,
  percentual_os numeric,
  saldo_atual numeric,
  estoque_ideal numeric,
  situacao text
)
language sql
stable
as $$
  with base as (
    select
      m.item_id,
      coalesce(nf.fornecedor_id::integer, i.fornecedor_id) as fornecedor_id,
      i.codigo_interno,
      i.nome as item_nome,
      i.unidade_medida,
      coalesce(e.quantidade_atual, 0)::numeric as saldo_atual,
      coalesce(i.estoque_ideal, 0)::numeric as estoque_ideal,
      m.quantidade::numeric as quantidade,
      m.origem_os_id,
      case
        when m.origem_nf_entrada_id is not null then 'NF ' || coalesce(nf.numero::text, '-')
        else 'MOV. MANUAL'
      end as motivo_linha
    from public.movimentacoes m
    join public.itens i
      on i.id = m.item_id
     and i.tenant_id = m.tenant_id
     and i.empresa_id = m.empresa_id
    left join public.nf_entrada nf
      on nf.id = m.origem_nf_entrada_id
     and nf.tenant_id = m.tenant_id
     and nf.empresa_id = m.empresa_id
    left join public.estoque e
      on e.item_id = m.item_id
     and e.tenant_id = m.tenant_id
     and e.empresa_id = m.empresa_id
    where m.tenant_id = p_tenant_id
      and m.empresa_id = p_empresa_id
      and m.tipo = 'entrada'
      and m.data_movimentacao::date between p_data_ini and p_data_fim
      and (
        p_os_mode = 'todos'
        or (p_os_mode = 'com_os' and m.origem_os_id is not null)
        or (p_os_mode = 'sem_os' and m.origem_os_id is null)
      )
      and (not p_com_nf or m.origem_nf_entrada_id is not null)
      and (
        coalesce(p_busca_item, '') = ''
        or i.nome ilike ('%' || p_busca_item || '%')
        or i.codigo_interno ilike ('%' || p_busca_item || '%')
      )
  ),
  agg as (
    select
      b.item_id,
      b.fornecedor_id,
      max(b.codigo_interno) as codigo_interno,
      max(b.item_nome) as item_nome,
      max(b.unidade_medida) as unidade_medida,
      string_agg(distinct b.motivo_linha, ' | ' order by b.motivo_linha) as motivo,
      sum(b.quantidade) as qtd_comprada,
      sum(case when b.origem_os_id is not null then b.quantidade else 0 end) as qtd_para_os,
      sum(case when b.origem_os_id is null then b.quantidade else 0 end) as qtd_para_estoque,
      max(b.saldo_atual) as saldo_atual,
      max(b.estoque_ideal) as estoque_ideal
    from base b
    group by b.item_id, b.fornecedor_id
  )
  select
    a.item_id,
    a.fornecedor_id,
    a.codigo_interno,
    a.item_nome,
    coalesce(f.nome, 'SEM FORNECEDOR') as fornecedor_nome,
    coalesce(a.motivo, 'MOV. MANUAL') as motivo,
    a.unidade_medida,
    a.qtd_comprada,
    a.qtd_para_os,
    a.qtd_para_estoque,
    case when a.qtd_comprada > 0 then (a.qtd_para_os / a.qtd_comprada) * 100 else 0 end as percentual_os,
    a.saldo_atual,
    a.estoque_ideal,
    case when a.saldo_atual > a.estoque_ideal then 'ALERTA' else 'OK' end as situacao
  from agg a
  left join public.fornecedores f
    on f.id = a.fornecedor_id
   and f.tenant_id = p_tenant_id
   and f.empresa_id = p_empresa_id
  where (
    coalesce(p_fornecedor_prefix, '') = ''
    or coalesce(f.nome, 'SEM FORNECEDOR') ilike (p_fornecedor_prefix || '%')
  )
    and (
      not p_destacar_saldo_alto
      or a.saldo_atual > a.estoque_ideal
    )
  order by coalesce(f.nome, 'SEM FORNECEDOR') asc, a.item_nome asc;
$$;
