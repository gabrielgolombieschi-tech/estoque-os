begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

create or replace function public.search_estoque_itens(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_busca_geral text default null,
  p_codigo text default null,
  p_nome text default null,
  p_fornecedor text default null,
  p_item_id integer default null,
  p_ativo_only boolean default false,
  p_finalidade text default null,
  p_abaixo_minimo boolean default false,
  p_sem_fornecedor boolean default false,
  p_saldo_positivo boolean default false,
  p_page integer default 1,
  p_page_size integer default 50,
  p_sort_key text default 'nome',
  p_sort_dir text default 'asc'
)
returns table (
  total_count bigint,
  item_id integer,
  estoque_id integer,
  codigo_interno text,
  codigo_barras text,
  item_nome text,
  tipo text,
  unidade_medida text,
  quantidade_atual numeric,
  preco_unitario numeric,
  custo_medio numeric,
  estoque_minimo numeric,
  estoque_ideal numeric,
  estoque_maximo numeric,
  fornecedor_id integer,
  fornecedor_nome text,
  finalidade text,
  controla_estoque boolean,
  ativo boolean,
  atualizado_em timestamp without time zone,
  localizacao text,
  abaixo_minimo boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca_geral, '')), '');
  v_codigo text := nullif(btrim(coalesce(p_codigo, '')), '');
  v_nome text := nullif(btrim(coalesce(p_nome, '')), '');
  v_fornecedor text := nullif(btrim(coalesce(p_fornecedor, '')), '');
  v_finalidade text := nullif(btrim(coalesce(p_finalidade, '')), '');
  v_page integer := greatest(1, coalesce(p_page, 1));
  v_page_size integer := greatest(1, least(coalesce(p_page_size, 50), 500));
  v_sort_key text := lower(coalesce(p_sort_key, 'nome'));
  v_sort_dir text := lower(coalesce(p_sort_dir, 'asc'));
begin
  if auth.uid() is null
     or p_tenant_id is null
     or p_empresa_id is null
     or public.current_tenant_id() is distinct from p_tenant_id
     or public.current_empresa_id__by_tenant(p_tenant_id) is distinct from p_empresa_id
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or not (
       public.can('estoque', 'read', p_tenant_id)
       or public.can('estoque', 'write', p_tenant_id)
     ) then
    raise exception 'estoque_search_access_denied';
  end if;

  if v_sort_key not in ('id', 'codigo', 'nome') then
    v_sort_key := 'nome';
  end if;
  if v_sort_dir not in ('asc', 'desc') then
    v_sort_dir := 'asc';
  end if;

  return query
  with filtered as (
    select
      i.id as item_id,
      e.id as estoque_id,
      i.codigo_interno::text as codigo_interno,
      i.codigo_barras::text as codigo_barras,
      i.nome::text as item_nome,
      i.tipo::text as tipo,
      i.unidade_medida::text as unidade_medida,
      coalesce(e.quantidade_atual, 0)::numeric as quantidade_atual,
      i.preco_unitario::numeric as preco_unitario,
      i.custo_medio::numeric as custo_medio,
      i.estoque_minimo::numeric as estoque_minimo,
      i.estoque_ideal::numeric as estoque_ideal,
      i.estoque_maximo::numeric as estoque_maximo,
      i.fornecedor_id,
      f.nome::text as fornecedor_nome,
      i.finalidade::text as finalidade,
      i.controla_estoque,
      i.ativo,
      e.atualizado_em,
      e.localizacao::text as localizacao,
      (coalesce(e.quantidade_atual, 0) < coalesce(i.estoque_minimo, 0)) as abaixo_minimo
    from public.itens i
    left join public.estoque e
      on e.tenant_id = i.tenant_id
     and e.empresa_id = i.empresa_id
     and e.item_id = i.id
    left join public.fornecedores f
      on f.tenant_id = i.tenant_id
     and f.empresa_id = i.empresa_id
     and f.id = i.fornecedor_id
    where i.tenant_id = p_tenant_id
      and i.empresa_id = p_empresa_id
      and i.tipo = 'produto'
      and i.controla_estoque is true
      and (not coalesce(p_ativo_only, false) or i.ativo is true)
      and (p_item_id is null or i.id = p_item_id)
      and (
        v_busca is null
        or i.codigo_interno ilike '%' || v_busca || '%'
        or i.codigo_barras ilike '%' || v_busca || '%'
        or i.nome ilike '%' || v_busca || '%'
      )
      and (
        v_codigo is null
        or i.codigo_interno ilike '%' || v_codigo || '%'
        or i.codigo_barras ilike '%' || v_codigo || '%'
      )
      and (v_nome is null or i.nome ilike '%' || v_nome || '%')
      and (v_finalidade is null or i.finalidade::text = v_finalidade)
      and (
        (v_fornecedor is null and not coalesce(p_sem_fornecedor, false))
        or (v_fornecedor is null and coalesce(p_sem_fornecedor, false) and i.fornecedor_id is null)
        or (v_fornecedor is not null and f.nome ilike '%' || v_fornecedor || '%')
        or (v_fornecedor is not null and coalesce(p_sem_fornecedor, false) and i.fornecedor_id is null)
      )
      and (not coalesce(p_saldo_positivo, false) or coalesce(e.quantidade_atual, 0) > 0)
      and (
        not coalesce(p_abaixo_minimo, false)
        or coalesce(e.quantidade_atual, 0) < coalesce(i.estoque_minimo, 0)
      )
  ), counted as (
    select count(*) over () as total_count, filtered.*
    from filtered
  )
  select
    counted.total_count,
    counted.item_id,
    counted.estoque_id,
    counted.codigo_interno,
    counted.codigo_barras,
    counted.item_nome,
    counted.tipo,
    counted.unidade_medida,
    counted.quantidade_atual,
    counted.preco_unitario,
    counted.custo_medio,
    counted.estoque_minimo,
    counted.estoque_ideal,
    counted.estoque_maximo,
    counted.fornecedor_id,
    counted.fornecedor_nome,
    counted.finalidade,
    counted.controla_estoque,
    counted.ativo,
    counted.atualizado_em,
    counted.localizacao,
    counted.abaixo_minimo
  from counted
  order by
    case when v_sort_key = 'id' and v_sort_dir = 'asc' then counted.item_id end asc,
    case when v_sort_key = 'id' and v_sort_dir = 'desc' then counted.item_id end desc,
    case when v_sort_key = 'codigo' and v_sort_dir = 'asc' then lower(counted.codigo_interno) end asc,
    case when v_sort_key = 'codigo' and v_sort_dir = 'desc' then lower(counted.codigo_interno) end desc,
    case when v_sort_key = 'nome' and v_sort_dir = 'asc' then lower(counted.item_nome) end asc,
    case when v_sort_key = 'nome' and v_sort_dir = 'desc' then lower(counted.item_nome) end desc,
    counted.item_id asc
  offset ((v_page - 1) * v_page_size)
  limit v_page_size;
end;
$$;

revoke all on function public.search_estoque_itens(
  uuid, uuid, text, text, text, text, integer, boolean, text, boolean,
  boolean, boolean, integer, integer, text, text
) from public, anon;
grant execute on function public.search_estoque_itens(
  uuid, uuid, text, text, text, text, integer, boolean, text, boolean,
  boolean, boolean, integer, integer, text, text
) to authenticated, service_role;

do $$
begin
  if has_function_privilege(
       'anon',
       'public.search_estoque_itens(uuid,uuid,text,text,text,text,integer,boolean,text,boolean,boolean,boolean,integer,integer,text,text)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'public.search_estoque_itens(uuid,uuid,text,text,text,text,integer,boolean,text,boolean,boolean,boolean,integer,integer,text,text)',
       'execute'
     ) then
    raise exception 'search_estoque_itens_installation_invalid';
  end if;
end;
$$;

comment on function public.search_estoque_itens(
  uuid, uuid, text, text, text, text, integer, boolean, text, boolean,
  boolean, boolean, integer, integer, text, text
) is 'Busca itens de estoque por codigo, barras ou nome apos validar o contexto e a permissao de estoque.';

notify pgrst, 'reload schema';

commit;
