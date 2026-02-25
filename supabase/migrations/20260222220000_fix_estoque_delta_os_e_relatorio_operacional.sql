-- Corrige regra de delta de estoque para OS e ajusta saldo operacional do relatorio.

create or replace function public.fn_atualiza_estoque_por_mov()
returns trigger
language plpgsql
as $$
declare
  v_delta numeric;
  v_qtd numeric;
begin
  if new.empresa_id is null then
    raise exception 'empresa_id obrigatorio na movimentacao (tenant_id=%, item_id=%)', new.tenant_id, new.item_id;
  end if;

  v_delta :=
    case
      when new.tipo = 'entrada' then coalesce(new.quantidade, 0)
      when new.tipo = 'saida' then -coalesce(new.quantidade, 0)
      when new.tipo = 'ajuste' then coalesce(new.quantidade, 0)
      else null
    end;

  if v_delta is null then
    raise exception 'Tipo de movimentacao invalido: %', new.tipo;
  end if;

  insert into public.estoque (tenant_id, empresa_id, item_id, quantidade_atual, atualizado_em)
  values (new.tenant_id, new.empresa_id, new.item_id, 0, now())
  on conflict on constraint estoque_tenant_empresa_item_key do nothing;

  update public.estoque
     set quantidade_atual = quantidade_atual + v_delta,
         atualizado_em = now()
   where tenant_id = new.tenant_id
     and empresa_id = new.empresa_id
     and item_id = new.item_id
   returning quantidade_atual into v_qtd;

  if v_qtd < 0 then
    raise exception
      'Estoque nao pode ficar negativo (tenant_id=%, empresa_id=%, item_id=%, saldo=%)',
      new.tenant_id, new.empresa_id, new.item_id, v_qtd;
  end if;

  return new;
end;
$$;
create or replace function public.apply_movimentacao_estoque()
returns trigger
language plpgsql
as $$
declare
  v_delta numeric;
  v_saldo_anterior numeric;
  v_custo_medio numeric;
  v_custo_entrada numeric;
  v_novo_custo numeric;
begin
  if new.item_id is null then
    return new;
  end if;

  v_saldo_anterior := 0;
  select coalesce(e.quantidade_atual, 0)
    into v_saldo_anterior
  from public.estoque e
  where e.tenant_id = new.tenant_id
    and e.empresa_id = new.empresa_id
    and e.item_id = new.item_id
  limit 1;

  v_delta :=
    case
      when new.tipo = 'entrada' then coalesce(new.quantidade, 0)
      when new.tipo = 'saida' then -coalesce(new.quantidade, 0)
      when new.tipo = 'ajuste' then coalesce(new.quantidade, 0)
      else null
    end;

  if v_delta is null then
    raise exception 'Tipo de movimentacao invalido: %', new.tipo;
  end if;

  insert into public.estoque (tenant_id, empresa_id, item_id, quantidade_atual)
  values (new.tenant_id, new.empresa_id, new.item_id, v_delta)
  on conflict (tenant_id, empresa_id, item_id) do update
    set quantidade_atual = coalesce(public.estoque.quantidade_atual, 0) + v_delta;

  if new.tipo = 'entrada' and coalesce(new.quantidade, 0) > 0 then
    select coalesce(i.custo_medio, 0)
      into v_custo_medio
    from public.itens i
    where i.id = new.item_id
      and i.tenant_id = new.tenant_id
    limit 1;

    v_custo_entrada := coalesce(new.custo_unitario_real, new.custo_unitario_bruto, 0);
    v_novo_custo := case
      when (v_saldo_anterior + new.quantidade) > 0
        then ((v_saldo_anterior * v_custo_medio) + (new.quantidade * v_custo_entrada)) / (v_saldo_anterior + new.quantidade)
      else v_custo_entrada
    end;

    update public.itens
       set custo_ultima_compra = v_custo_entrada,
           custo_medio = v_novo_custo
     where id = new.item_id
       and tenant_id = new.tenant_id;
  end if;

  return new;
end;
$$;
-- Recalculo historico com regra normal de delta.
with saldo_calc as (
  select
    m.tenant_id,
    m.empresa_id,
    m.item_id,
    sum(
      case
        when m.tipo = 'entrada' then coalesce(m.quantidade, 0)
        when m.tipo = 'saida' then -coalesce(m.quantidade, 0)
        when m.tipo = 'ajuste' then coalesce(m.quantidade, 0)
        else 0
      end
    )::numeric(14,3) as saldo
  from public.movimentacoes m
  group by m.tenant_id, m.empresa_id, m.item_id
)
update public.estoque e
   set quantidade_atual = coalesce(s.saldo, 0),
       atualizado_em = now()
  from saldo_calc s
 where e.tenant_id = s.tenant_id
   and e.empresa_id = s.empresa_id
   and e.item_id = s.item_id;
update public.estoque e
   set quantidade_atual = 0,
       atualizado_em = now()
 where not exists (
   select 1
   from public.movimentacoes m
   where m.tenant_id = e.tenant_id
     and m.empresa_id = e.empresa_id
     and m.item_id = e.item_id
 );
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
  destino_os text,
  saldo_atual numeric,
  saldo_ajustado numeric,
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
      string_agg(distinct case when b.origem_os_id is not null then ('OS ' || b.origem_os_id::text) else null end, ' | ') as destino_os,
      max(b.saldo_atual) as saldo_atual,
      max(b.estoque_ideal) as estoque_ideal
    from base b
    group by b.item_id, b.fornecedor_id
  ),
  calc as (
    select
      a.*,
      case
        when a.saldo_atual < 0 then (a.saldo_atual + a.qtd_para_os)
        else a.saldo_atual
      end as saldo_ajustado_calc
    from agg a
  )
  select
    c.item_id,
    c.fornecedor_id,
    c.codigo_interno,
    c.item_nome,
    coalesce(f.nome, 'SEM FORNECEDOR') as fornecedor_nome,
    coalesce(c.motivo, 'MOV. MANUAL') as motivo,
    c.unidade_medida,
    c.qtd_comprada,
    c.qtd_para_os,
    c.qtd_para_estoque,
    case when c.qtd_comprada > 0 then (c.qtd_para_os / c.qtd_comprada) * 100 else 0 end as percentual_os,
    coalesce(c.destino_os, '-') as destino_os,
    c.saldo_atual,
    c.saldo_ajustado_calc as saldo_ajustado,
    c.estoque_ideal,
    case
      when c.saldo_ajustado_calc < 0 then 'ALERTA'
      when c.saldo_ajustado_calc > c.estoque_ideal then 'ALERTA'
      else 'OK'
    end as situacao
  from calc c
  left join public.fornecedores f
    on f.id = c.fornecedor_id
   and f.tenant_id = p_tenant_id
   and f.empresa_id = p_empresa_id
  where (
    coalesce(p_fornecedor_prefix, '') = ''
    or coalesce(f.nome, 'SEM FORNECEDOR') ilike (p_fornecedor_prefix || '%')
  )
    and (
      not p_destacar_saldo_alto
      or c.saldo_ajustado_calc > c.estoque_ideal
    )
  order by coalesce(f.nome, 'SEM FORNECEDOR') asc, c.item_nome asc;
$$;
