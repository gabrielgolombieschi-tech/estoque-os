begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

-- Nucleo unico da regra comercial. Nao acessa tabelas nem faz autorizacao;
-- os wrappers de Comercial e Financeiro validam o modulo antes de chama-lo.
create or replace function public.fn_preco_venda_item_valores(
  p_custo_ultima_compra numeric,
  p_preco_unitario numeric,
  p_aliquota_ipi numeric,
  p_margem_percent numeric
)
returns numeric
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when base <= 0 then 0::numeric
    else round(
      base
      * (1 + greatest(coalesce(p_aliquota_ipi, 0), 0) / 100.0)
      * (1 + greatest(coalesce(p_margem_percent, 53), 0) / 100.0),
      2
    )
  end
  from (
    select case
      when coalesce(p_custo_ultima_compra, 0) > 0 then p_custo_ultima_compra
      else greatest(coalesce(p_preco_unitario, 0), 0)
    end as base
  ) x;
$$;

revoke all on function public.fn_preco_venda_item_valores(numeric,numeric,numeric,numeric)
  from public, anon, authenticated;

create or replace function public.fn_preco_venda_item_unscoped(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_item_id integer
)
returns numeric
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_preco numeric;
begin
  select public.fn_preco_venda_item_valores(
           i.custo_ultima_compra,
           i.preco_unitario,
           i.aliquota_ipi,
           coalesce(cfg.margem_lucro_padrao_percent, 53)
         )
    into v_preco
  from public.itens i
  left join lateral (
    select c.margem_lucro_padrao_percent
    from a.config_orcamento c
    where c.tenant_id = p_tenant_id
      and c.empresa_id = p_empresa_id
      and c.deleted_at is null
    order by c.updated_at desc nulls last, c.created_at desc
    limit 1
  ) cfg on true
  where i.id = p_item_id
    and i.tenant_id = p_tenant_id
    and i.empresa_id = p_empresa_id;

  return coalesce(v_preco, 0);
end;
$$;

revoke all on function public.fn_preco_venda_item_unscoped(uuid,uuid,integer)
  from public, anon, authenticated, service_role;

create or replace function m.fn_orcamento_preco_sugerido_item_por_id(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_item_id integer
)
returns numeric
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if auth.uid() is null
     or p_empresa_id is distinct from public.current_empresa_id__by_tenant(p_tenant_id)
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or not c.has_comercial_access(p_tenant_id, p_empresa_id) then
    raise exception 'orcamento_preco_access_denied';
  end if;

  return public.fn_preco_venda_item_unscoped(p_tenant_id, p_empresa_id, p_item_id);
end;
$$;

revoke all on function m.fn_orcamento_preco_sugerido_item_por_id(uuid,uuid,integer)
  from public, anon;
grant execute on function m.fn_orcamento_preco_sugerido_item_por_id(uuid,uuid,integer)
  to authenticated, service_role;

create or replace function f.fn_venda_credito_preco_item_por_id(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_item_id integer
)
returns numeric
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if auth.uid() is null
     or p_empresa_id is distinct from public.current_empresa_id__by_tenant(p_tenant_id)
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or not f.has_cobranca_access(p_tenant_id, p_empresa_id) then
    raise exception 'venda_credito_preco_access_denied';
  end if;

  return public.fn_preco_venda_item_unscoped(p_tenant_id, p_empresa_id, p_item_id);
end;
$$;

revoke all on function f.fn_venda_credito_preco_item_por_id(uuid,uuid,integer)
  from public, anon;
grant execute on function f.fn_venda_credito_preco_item_por_id(uuid,uuid,integer)
  to authenticated, service_role;

-- Mantem a assinatura antiga para compatibilidade, mas centraliza o nucleo.
-- Sem item_id nao existe como descobrir o IPI; consumidores novos usam _por_id.
create or replace function m.fn_orcamento_preco_sugerido_item(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_custo_ultima_compra numeric,
  p_preco_unitario numeric
)
returns numeric
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_margem numeric := 53;
begin
  if p_empresa_id is distinct from public.current_empresa_id__by_tenant(p_tenant_id)
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or not c.has_comercial_access(p_tenant_id, p_empresa_id) then
    raise exception 'not_allowed';
  end if;

  select coalesce(c.margem_lucro_padrao_percent, 53)
    into v_margem
  from a.config_orcamento c
  where c.tenant_id = p_tenant_id
    and c.empresa_id = p_empresa_id
    and c.deleted_at is null
  order by c.updated_at desc nulls last, c.created_at desc
  limit 1;

  return public.fn_preco_venda_item_valores(
    p_custo_ultima_compra, p_preco_unitario, 0, coalesce(v_margem, 53)
  );
end;
$$;

create or replace function m.fn_orcamento_adicionar_conjunto(
  p_orcamento_id uuid,
  p_conjunto_id uuid,
  p_quantidade numeric default 1
)
returns table(conjunto_instancia_id uuid, itens_inseridos integer, total_estimado numeric)
language plpgsql
security definer
set search_path = 'm', 'c', 'public', 'a'
set row_security = off
as $$
declare
  v_orc m.orcamento%rowtype;
  v_conj c.conjunto%rowtype;
  v_inst uuid := gen_random_uuid();
  v_count integer := 0;
  v_total numeric(15,6) := 0;
  r record;
begin
  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'Quantidade do conjunto deve ser > 0';
  end if;

  select * into v_orc
  from m.orcamento o
  where o.id = p_orcamento_id and o.deleted_at is null;

  if not found then raise exception 'Orcamento nao encontrado'; end if;
  if not c.has_comercial_access(v_orc.tenant_id, v_orc.empresa_id) then
    raise exception 'Sem permissao comercial para este tenant/empresa';
  end if;

  select * into v_conj
  from c.conjunto cj
  where cj.id = p_conjunto_id
    and cj.tenant_id = v_orc.tenant_id
    and cj.empresa_id = v_orc.empresa_id
    and cj.ativo is true and cj.deleted_at is null;

  if not found then raise exception 'Conjunto invalido para este tenant/empresa'; end if;

  for r in
    select ci.item_id, ci.quantidade as qtd_base, ci.ordem,
           public.fn_preco_venda_item_unscoped(v_orc.tenant_id, v_orc.empresa_id, i.id) as preco_sugerido
    from c.conjunto_item ci
    join public.itens i on i.id = ci.item_id
    where ci.conjunto_id = v_conj.id
      and ci.deleted_at is null
      and i.tenant_id = v_orc.tenant_id
      and i.empresa_id = v_orc.empresa_id
      and i.ativo is true
      and i.tipo in ('produto','servico')
    order by ci.ordem, ci.created_at
  loop
    insert into m.orcamento_item (
      orcamento_id, item_id, quantidade, valor_unitario,
      desconto_item_percent, conjunto_id, conjunto_instancia_id,
      conjunto_codigo, conjunto_nome
    ) values (
      v_orc.id, r.item_id, r.qtd_base * p_quantidade,
      coalesce(r.preco_sugerido,0)::numeric(15,4), 0,
      v_conj.id, v_inst, v_conj.codigo, v_conj.nome
    );
    v_count := v_count + 1;
    v_total := v_total + coalesce(r.preco_sugerido,0) * (r.qtd_base * p_quantidade);
  end loop;

  return query select v_inst, v_count, round(v_total,2);
end;
$$;

create or replace view r.r_orcamento_catalogo_busca
with (security_invoker = true)
as
select
  'ITEM'::text as origem,
  i.tenant_id,
  i.empresa_id,
  i.id::text as ref_id,
  i.id as item_id,
  null::uuid as conjunto_id,
  upper(btrim(i.codigo_interno)) as codigo,
  upper(btrim(i.nome)) as nome,
  upper(btrim(coalesce(i.unidade_medida, 'UN'))) as unidade,
  case when lower(i.tipo)='produto' then 'PRODUTO'
       when lower(i.tipo)='servico' then 'SERVICO'
       else upper(i.tipo) end as tipo,
  m.fn_orcamento_preco_sugerido_item_por_id(i.tenant_id, i.empresa_id, i.id)::numeric(15,2) as preco_sugerido
from public.itens i
where i.ativo is true and i.tipo in ('produto','servico')
union all
select
  'CONJUNTO'::text,
  c.tenant_id,
  c.empresa_id,
  c.id::text,
  null::integer,
  c.id,
  c.codigo,
  c.nome,
  'CJ'::text,
  'CONJUNTO'::text,
  case when c.precificacao='PRECO_FIXO' then c.preco_fixo
       else coalesce(sum(ci.quantidade * m.fn_orcamento_preco_sugerido_item_por_id(c.tenant_id,c.empresa_id,i.id)),0)::numeric(15,2)
  end
from c.conjunto c
left join c.conjunto_item ci on ci.conjunto_id=c.id and ci.deleted_at is null
left join public.itens i on i.id=ci.item_id and i.tenant_id=c.tenant_id and i.empresa_id=c.empresa_id and i.ativo is true
where c.deleted_at is null and c.ativo is true
group by c.id;

grant select on r.r_orcamento_catalogo_busca to authenticated;

drop function if exists public.search_orcamento_itens(uuid,uuid,text,text,integer);
create function public.search_orcamento_itens(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_term text default null,
  p_fornecedor text default null,
  p_limit integer default 150
)
returns table (
  id integer,
  codigo_interno text,
  nome text,
  fabricante text,
  preco_unitario numeric,
  custo_ultima_compra numeric,
  fornecedor text,
  ultima_entrada timestamp without time zone,
  estoque_atual numeric,
  preco_sugerido numeric
)
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_term text := nullif(btrim(coalesce(p_term, '')), '');
  v_fornecedor text := nullif(btrim(coalesce(p_fornecedor, '')), '');
  v_limit integer := greatest(1, least(coalesce(p_limit, 150), 200));
  v_codigo_exato boolean := v_term ~ '^[0-9]+$';
begin
  if auth.uid() is null or p_tenant_id is null or p_empresa_id is null
     or not public.has_active_empresa_access(p_tenant_id,p_empresa_id)
     or not c.has_comercial_access(p_tenant_id,p_empresa_id) then
    raise exception 'orcamento_item_search_access_denied';
  end if;

  return query
  select i.id, i.codigo_interno::text, i.nome::text, i.fabricante::text,
         i.preco_unitario, i.custo_ultima_compra, f.nome::text,
         mov.data_movimentacao, e.quantidade_atual,
         public.fn_preco_venda_item_unscoped(p_tenant_id,p_empresa_id,i.id)
  from public.itens i
  left join public.fornecedores f on f.tenant_id=i.tenant_id and f.empresa_id=i.empresa_id and f.id=i.fornecedor_id
  left join public.estoque e on e.tenant_id=i.tenant_id and e.empresa_id=i.empresa_id and e.item_id=i.id
  left join lateral (
    select m.data_movimentacao from public.movimentacoes m
    where m.tenant_id=i.tenant_id and m.empresa_id=i.empresa_id and m.item_id=i.id and m.tipo='entrada'
    order by m.data_movimentacao desc nulls last, m.id desc limit 1
  ) mov on true
  where i.tenant_id=p_tenant_id and i.empresa_id=p_empresa_id and i.ativo is true
    and (
      v_term is null
      or (v_codigo_exato and (i.codigo_interno=v_term or i.codigo_barras=v_term or i.id::text=v_term))
      or (not v_codigo_exato and (i.nome ilike '%'||v_term||'%' or i.codigo_interno ilike '%'||v_term||'%' or i.fabricante ilike '%'||v_term||'%'))
    )
    and (v_fornecedor is null or f.nome ilike '%'||v_fornecedor||'%')
  order by i.nome, i.id
  limit v_limit;
end;
$$;

revoke all on function public.search_orcamento_itens(uuid,uuid,text,text,integer) from public, anon;
grant execute on function public.search_orcamento_itens(uuid,uuid,text,text,integer) to authenticated, service_role;

comment on function public.fn_preco_venda_item_valores(numeric,numeric,numeric,numeric) is
  'Regra canonica: base de custo, IPI por fora e margem configurada.';

notify pgrst, 'reload schema';

commit;
