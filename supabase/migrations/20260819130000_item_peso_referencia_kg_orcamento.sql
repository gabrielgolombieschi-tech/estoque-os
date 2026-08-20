begin;

-- Itens vendidos por peso (unidade_medida = 'KG', ex.: chapas de aco/inox)
-- passam a poder registrar quanto pesa a unidade cadastrada. O orcamento usa
-- esse valor para sugerir a quantidade em kg ao inves de assumir "1", que hoje
-- faz a pessoa digitar de cabeca o peso da chapa (ou esquecer de ajustar).
--
-- Reaproveita a coluna publica.itens.peso_liquido, que ja existe no schema
-- desde a base original mas nunca foi exposta em nenhuma tela nem preenchida
-- por nenhum fluxo do app.

comment on column public.itens.peso_liquido is
  'Peso de referencia (kg) de uma unidade cadastrada deste item. Usado para sugerir a quantidade em kg no orcamento quando unidade_medida = KG (ex.: peso de uma chapa especifica). Opcional; null quando nao se aplica ou nao foi informado.';

drop function if exists public.search_cadastro_itens(uuid, uuid, integer, text, text, text, text, text, boolean, integer, integer, text, text);

create function public.search_cadastro_itens(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_item_id integer default null,
  p_codigo text default null,
  p_produto text default null,
  p_fornecedor text default null,
  p_tipo text default null,
  p_finalidade text default null,
  p_ativo_only boolean default false,
  p_page integer default 1,
  p_page_size integer default 100,
  p_sort_key text default 'nome',
  p_sort_dir text default 'asc'
)
returns table (
  total_count bigint,
  id integer,
  codigo_interno text,
  codigo_barras text,
  nome text,
  descricao text,
  tipo text,
  categoria text,
  subcategoria text,
  fabricante text,
  finalidade text,
  motivo_compra_id uuid,
  unidade_medida text,
  peso_liquido numeric,
  controla_estoque boolean,
  estoque_minimo numeric,
  estoque_maximo numeric,
  estoque_ideal numeric,
  custo_ultima_compra numeric,
  custo_medio numeric,
  preco_unitario numeric,
  fornecedor_id integer,
  fornecedor_nome text,
  ativo boolean,
  criado_em timestamp without time zone,
  criado_por text,
  atualizado_em timestamp without time zone,
  atualizado_por text
)
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_codigo text := nullif(btrim(coalesce(p_codigo, '')), '');
  v_produto text := nullif(btrim(coalesce(p_produto, '')), '');
  v_fornecedor text := nullif(btrim(coalesce(p_fornecedor, '')), '');
  v_tipo text := nullif(btrim(coalesce(p_tipo, '')), '');
  v_finalidade text := nullif(btrim(coalesce(p_finalidade, '')), '');
  v_page integer := greatest(1, coalesce(p_page, 1));
  v_page_size integer := greatest(1, least(coalesce(p_page_size, 100), 200));
  v_sort_key text := lower(coalesce(p_sort_key, 'nome'));
  v_sort_dir text := lower(coalesce(p_sort_dir, 'asc'));
  v_codigo_exato boolean := v_codigo ~ '^[0-9]+$';
  v_papel text := a.fn_current_empresa_papel(p_tenant_id, p_empresa_id);
begin
  if auth.uid() is null
     or p_tenant_id is null
     or p_empresa_id is null
     or public.current_tenant_id() is distinct from p_tenant_id
     or public.current_empresa_id__by_tenant(p_tenant_id) is distinct from p_empresa_id
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or coalesce(v_papel, '') not in (
       'ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO', 'COORDENACAO',
       'COMPRAS', 'ALMOXARIFADO', 'TECNICO', 'APONTAMENTO_RH'
     ) then
    raise exception 'cadastro_item_search_access_denied';
  end if;

  if v_sort_key not in ('id', 'codigo_interno', 'nome', 'tipo', 'finalidade', 'fornecedor', 'ativo') then
    v_sort_key := 'nome';
  end if;
  if v_sort_dir not in ('asc', 'desc') then
    v_sort_dir := 'asc';
  end if;

  return query
  with filtered as (
    select
      i.id,
      i.codigo_interno::text,
      i.codigo_barras::text,
      i.nome::text,
      i.descricao,
      i.tipo::text,
      i.categoria::text,
      i.subcategoria::text,
      i.fabricante::text,
      i.finalidade::text,
      i.motivo_compra_id,
      i.unidade_medida::text,
      i.peso_liquido,
      i.controla_estoque,
      i.estoque_minimo::numeric,
      i.estoque_maximo::numeric,
      i.estoque_ideal::numeric,
      i.custo_ultima_compra,
      i.custo_medio,
      i.preco_unitario,
      i.fornecedor_id,
      f.nome::text as fornecedor_nome,
      i.ativo,
      i.criado_em,
      i.criado_por::text,
      i.atualizado_em,
      i.atualizado_por::text
    from public.itens i
    left join public.fornecedores f
      on f.tenant_id = i.tenant_id
     and f.empresa_id = i.empresa_id
     and f.id = i.fornecedor_id
    where i.tenant_id = p_tenant_id
      and i.empresa_id = p_empresa_id
      and (p_item_id is null or i.id = p_item_id)
      and (
        v_codigo is null
        or (v_codigo_exato and (i.codigo_interno = v_codigo or i.codigo_barras = v_codigo))
        or (not v_codigo_exato and (i.codigo_interno ilike '%' || v_codigo || '%' or i.codigo_barras ilike '%' || v_codigo || '%'))
      )
      and (v_produto is null or i.nome ilike '%' || v_produto || '%')
      and (v_fornecedor is null or f.nome ilike '%' || v_fornecedor || '%')
      and (v_tipo is null or i.tipo::text = v_tipo)
      and (v_finalidade is null or i.finalidade::text = v_finalidade)
      and (not coalesce(p_ativo_only, false) or i.ativo is true)
  ), counted as (
    select count(*) over () as total_count, filtered.*
    from filtered
  )
  select counted.*
  from counted
  order by
    case when v_sort_key = 'id' and v_sort_dir = 'asc' then counted.id end asc,
    case when v_sort_key = 'id' and v_sort_dir = 'desc' then counted.id end desc,
    case when v_sort_key = 'codigo_interno' and v_sort_dir = 'asc' then lower(counted.codigo_interno) end asc,
    case when v_sort_key = 'codigo_interno' and v_sort_dir = 'desc' then lower(counted.codigo_interno) end desc,
    case when v_sort_key = 'nome' and v_sort_dir = 'asc' then lower(counted.nome) end asc,
    case when v_sort_key = 'nome' and v_sort_dir = 'desc' then lower(counted.nome) end desc,
    case when v_sort_key = 'tipo' and v_sort_dir = 'asc' then lower(counted.tipo) end asc,
    case when v_sort_key = 'tipo' and v_sort_dir = 'desc' then lower(counted.tipo) end desc,
    case when v_sort_key = 'finalidade' and v_sort_dir = 'asc' then lower(counted.finalidade) end asc,
    case when v_sort_key = 'finalidade' and v_sort_dir = 'desc' then lower(counted.finalidade) end desc,
    case when v_sort_key = 'fornecedor' and v_sort_dir = 'asc' then lower(counted.fornecedor_nome) end asc,
    case when v_sort_key = 'fornecedor' and v_sort_dir = 'desc' then lower(counted.fornecedor_nome) end desc,
    case when v_sort_key = 'ativo' and v_sort_dir = 'asc' then counted.ativo end asc,
    case when v_sort_key = 'ativo' and v_sort_dir = 'desc' then counted.ativo end desc,
    counted.id desc
  offset ((v_page - 1) * v_page_size)
  limit v_page_size;
end;
$$;

revoke all on function public.search_cadastro_itens(uuid, uuid, integer, text, text, text, text, text, boolean, integer, integer, text, text) from public, anon;
grant execute on function public.search_cadastro_itens(uuid, uuid, integer, text, text, text, text, text, boolean, integer, integer, text, text) to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
