create or replace function m.fn_orcamento_preco_sugerido_item(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_custo_ultima_compra numeric,
  p_preco_unitario numeric
) returns numeric
language plpgsql
stable
security definer
set search_path = 'm', 'a', 'public'
set row_security = off
as $$
declare
  v_margem numeric := 53;
  v_base numeric := 0;
begin
  select coalesce(c.margem_lucro_padrao_percent, 53)
    into v_margem
  from a.config_orcamento c
  where c.tenant_id = p_tenant_id
    and c.empresa_id = p_empresa_id
    and c.deleted_at is null
  order by c.updated_at desc nulls last, c.created_at desc
  limit 1;

  v_margem := greatest(coalesce(v_margem, 53), 0);
  v_base := case
    when coalesce(p_custo_ultima_compra, 0) > 0 then coalesce(p_custo_ultima_compra, 0)
    else greatest(coalesce(p_preco_unitario, 0), 0)
  end;

  if v_base <= 0 then
    return 0;
  end if;

  return round(v_base * (1 + (v_margem / 100.0)), 2);
end;
$$;

grant execute on function m.fn_orcamento_preco_sugerido_item(uuid, uuid, numeric, numeric) to authenticated;
grant execute on function m.fn_orcamento_preco_sugerido_item(uuid, uuid, numeric, numeric) to service_role;

create or replace function m.fn_orcamento_adicionar_conjunto(
  p_orcamento_id uuid,
  p_conjunto_id uuid,
  p_quantidade numeric default 1
) returns table(conjunto_instancia_id uuid, itens_inseridos integer, total_estimado numeric)
language plpgsql
security definer
set search_path = 'm', 'c', 'public', 'a'
set row_security = off
as $$
declare
  v_orc m.orcamento%rowtype;
  v_conj c.conjunto%rowtype;
  v_inst uuid := gen_random_uuid();
  v_count int := 0;
  v_total numeric(15,6) := 0;
  r record;
begin
  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'Quantidade do conjunto deve ser > 0';
  end if;

  select *
    into v_orc
  from m.orcamento o
  where o.id = p_orcamento_id
    and o.deleted_at is null;

  if not found then
    raise exception 'Orcamento nao encontrado (orcamento_id=%)', p_orcamento_id;
  end if;

  if not c.has_comercial_access(v_orc.tenant_id, v_orc.empresa_id) then
    raise exception 'Sem permissao comercial para este tenant/empresa';
  end if;

  select *
    into v_conj
  from c.conjunto cj
  where cj.id = p_conjunto_id
    and cj.tenant_id = v_orc.tenant_id
    and cj.empresa_id = v_orc.empresa_id
    and cj.ativo = true
    and cj.deleted_at is null;

  if not found then
    raise exception 'Conjunto invalido para este tenant/empresa (conjunto_id=%)', p_conjunto_id;
  end if;

  for r in
    select
      ci.item_id,
      ci.quantidade as qtd_base,
      ci.ordem,
      m.fn_orcamento_preco_sugerido_item(
        v_orc.tenant_id,
        v_orc.empresa_id,
        i.custo_ultima_compra,
        i.preco_unitario
      ) as preco_sugerido,
      i.tipo
    from c.conjunto_item ci
    join public.itens i on i.id = ci.item_id
    where ci.conjunto_id = v_conj.id
      and ci.deleted_at is null
      and i.tenant_id = v_orc.tenant_id
      and i.empresa_id = v_orc.empresa_id
      and i.ativo = true
      and i.tipo in ('produto', 'servico')
    order by ci.ordem, ci.created_at
  loop
    insert into m.orcamento_item (
      orcamento_id,
      item_id,
      quantidade,
      valor_unitario,
      desconto_item_percent,
      conjunto_id,
      conjunto_instancia_id,
      conjunto_codigo,
      conjunto_nome
    ) values (
      v_orc.id,
      r.item_id,
      (r.qtd_base * p_quantidade),
      coalesce(r.preco_sugerido, 0)::numeric(15,4),
      0,
      v_conj.id,
      v_inst,
      v_conj.codigo,
      v_conj.nome
    );

    v_count := v_count + 1;
    v_total := v_total + (coalesce(r.preco_sugerido, 0)::numeric(15,6) * (r.qtd_base * p_quantidade));
  end loop;

  conjunto_instancia_id := v_inst;
  itens_inseridos := v_count;
  total_estimado := round(v_total, 2);

  return next;
end;
$$;

create or replace view r.r_orcamento_catalogo_busca as
select
  'ITEM'::text as origem,
  i.tenant_id,
  i.empresa_id,
  (i.id)::text as ref_id,
  i.id as item_id,
  null::uuid as conjunto_id,
  upper(trim(both from i.codigo_interno)) as codigo,
  upper(trim(both from i.nome)) as nome,
  upper(trim(both from coalesce(i.unidade_medida, 'UN'::character varying))) as unidade,
  case
    when lower((i.tipo)::text) = 'produto'::text then 'PRODUTO'::text
    when lower((i.tipo)::text) = 'servico'::text then 'SERVICO'::text
    else upper((i.tipo)::text)
  end as tipo,
  m.fn_orcamento_preco_sugerido_item(
    i.tenant_id,
    i.empresa_id,
    i.custo_ultima_compra,
    i.preco_unitario
  )::numeric(15,2) as preco_sugerido
from public.itens i
where i.ativo = true
  and (i.tipo)::text = any ((array['produto'::character varying, 'servico'::character varying])::text[])

union all

select
  'CONJUNTO'::text as origem,
  c.tenant_id,
  c.empresa_id,
  (c.id)::text as ref_id,
  null::integer as item_id,
  c.id as conjunto_id,
  c.codigo,
  c.nome,
  'CJ'::text as unidade,
  'CONJUNTO'::text as tipo,
  case
    when c.precificacao = 'PRECO_FIXO'::text then c.preco_fixo
    else coalesce(
      sum(
        ci.quantidade * m.fn_orcamento_preco_sugerido_item(
          c.tenant_id,
          c.empresa_id,
          i.custo_ultima_compra,
          i.preco_unitario
        )
      ),
      0
    )::numeric(15,2)
  end as preco_sugerido
from c.conjunto c
left join c.conjunto_item ci
  on ci.conjunto_id = c.id
 and ci.deleted_at is null
left join public.itens i
  on i.id = ci.item_id
 and i.tenant_id = c.tenant_id
 and i.empresa_id = c.empresa_id
 and i.ativo = true
where c.deleted_at is null
  and c.ativo = true
group by c.id;
