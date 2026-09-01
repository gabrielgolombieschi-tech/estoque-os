begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- A politica criada na separacao de empresas chamava funcoes de contexto com
-- colunas da propria linha. Isso impedia o PostgreSQL de calcula-las uma unica
-- vez e multiplicava o custo de autorizacao pelo numero de registros lidos.
do $$
declare
  r record;
  v_using text;
begin
  for r in
    select
      n.nspname as schema_name,
      cls.relname as table_name,
      empresa_col.attnotnull as empresa_not_null
    from pg_class cls
    join pg_namespace n on n.oid = cls.relnamespace
    join pg_attribute tenant_col
      on tenant_col.attrelid = cls.oid
     and tenant_col.attname = 'tenant_id'
     and tenant_col.attnum > 0
     and not tenant_col.attisdropped
    join pg_attribute empresa_col
      on empresa_col.attrelid = cls.oid
     and empresa_col.attname = 'empresa_id'
     and empresa_col.attnum > 0
     and not empresa_col.attisdropped
    where cls.relkind in ('r', 'p')
      and cls.relrowsecurity is true
      and n.nspname in ('public', 'c', 'f', 'm')
      and not (n.nspname = 'public' and cls.relname in (
        'empresa_memberships', 'user_empresa_context'
      ))
  loop
    if r.schema_name = 'f'
       and r.table_name = 'credito_fiscal_manual_regra'
       and not r.empresa_not_null then
      v_using :=
        'tenant_id = (select public.current_tenant_id()) '
        || 'and ((empresa_id is null and (select public.has_any_active_empresa_access(public.current_tenant_id()))) '
        || 'or (empresa_id = (select public.current_empresa_id()) '
        || 'and (select public.has_active_empresa_access(public.current_tenant_id(), public.current_empresa_id()))))';
    else
      v_using :=
        'tenant_id = (select public.current_tenant_id()) '
        || 'and empresa_id = (select public.current_empresa_id()) '
        || 'and (select public.has_active_empresa_access(public.current_tenant_id(), public.current_empresa_id()))';
    end if;

    execute format(
      'drop policy if exists enforce_active_empresa_scope on %I.%I',
      r.schema_name,
      r.table_name
    );
    execute format(
      'create policy enforce_active_empresa_scope on %I.%I as restrictive for all to authenticated using (%s) with check (%s)',
      r.schema_name,
      r.table_name,
      v_using,
      v_using
    );
  end loop;
end;
$$;

create index if not exists ix_user_empresa_context_user_tenant
  on public.user_empresa_context (user_id, tenant_id);

create or replace function public.search_relatorio_estoque(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_busca text default null,
  p_fornecedor text default null,
  p_finalidade text default null,
  p_localizacao text default null,
  p_abaixo_minimo boolean default false,
  p_sem_fornecedor boolean default false,
  p_page integer default 1,
  p_page_size integer default 50,
  p_sort_key text default 'nome',
  p_sort_dir text default 'asc'
)
returns table (
  total_count bigint,
  item_id integer,
  codigo_interno text,
  item_nome text,
  unidade_medida text,
  quantidade_atual numeric,
  preco_unitario numeric,
  custo_medio numeric,
  estoque_minimo numeric,
  estoque_ideal numeric,
  estoque_maximo numeric,
  fornecedor_id integer,
  fornecedor_nome text,
  localizacao text,
  finalidade text,
  controla_estoque boolean,
  abaixo_minimo boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
  v_fornecedor text := nullif(btrim(coalesce(p_fornecedor, '')), '');
  v_finalidade text := nullif(btrim(coalesce(p_finalidade, '')), '');
  v_localizacao text := nullif(btrim(coalesce(p_localizacao, '')), '');
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
    raise exception 'estoque_report_access_denied';
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
      i.codigo_interno::text as codigo_interno,
      i.nome::text as item_nome,
      i.unidade_medida::text as unidade_medida,
      coalesce(e.quantidade_atual, 0)::numeric as quantidade_atual,
      i.preco_unitario::numeric as preco_unitario,
      i.custo_medio::numeric as custo_medio,
      i.estoque_minimo::numeric as estoque_minimo,
      i.estoque_ideal::numeric as estoque_ideal,
      i.estoque_maximo::numeric as estoque_maximo,
      i.fornecedor_id,
      f.nome::text as fornecedor_nome,
      e.localizacao::text as localizacao,
      i.finalidade::text as finalidade,
      i.controla_estoque,
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
      and (
        v_busca is null
        or i.codigo_interno ilike '%' || v_busca || '%'
        or i.codigo_barras ilike '%' || v_busca || '%'
        or i.nome ilike '%' || v_busca || '%'
      )
      and (v_finalidade is null or i.finalidade::text = v_finalidade)
      and (v_localizacao is null or e.localizacao ilike '%' || v_localizacao || '%')
      and (
        (v_fornecedor is null and not coalesce(p_sem_fornecedor, false))
        or (v_fornecedor is null and coalesce(p_sem_fornecedor, false) and i.fornecedor_id is null)
        or (v_fornecedor is not null and f.nome ilike '%' || v_fornecedor || '%')
        or (v_fornecedor is not null and coalesce(p_sem_fornecedor, false) and i.fornecedor_id is null)
      )
      and (
        coalesce(p_abaixo_minimo, false)
        or coalesce(e.quantidade_atual, 0) > 0
      )
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
    counted.codigo_interno,
    counted.item_nome,
    counted.unidade_medida,
    counted.quantidade_atual,
    counted.preco_unitario,
    counted.custo_medio,
    counted.estoque_minimo,
    counted.estoque_ideal,
    counted.estoque_maximo,
    counted.fornecedor_id,
    counted.fornecedor_nome,
    counted.localizacao,
    counted.finalidade,
    counted.controla_estoque,
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

revoke all on function public.search_relatorio_estoque(
  uuid, uuid, text, text, text, text, boolean, boolean, integer, integer, text, text
) from public, anon;
grant execute on function public.search_relatorio_estoque(
  uuid, uuid, text, text, text, text, boolean, boolean, integer, integer, text, text
) to authenticated, service_role;

create or replace function public.get_os_detail_operacional(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_os_id integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_papel text := a.fn_current_empresa_papel(p_tenant_id, p_empresa_id);
  v_os public.ordens_servico%rowtype;
  v_result jsonb;
begin
  if auth.uid() is null
     or p_tenant_id is null
     or p_empresa_id is null
     or p_os_id is null
     or public.current_tenant_id() is distinct from p_tenant_id
     or public.current_empresa_id__by_tenant(p_tenant_id) is distinct from p_empresa_id
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or coalesce(v_papel, '') not in (
       'ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO', 'COORDENACAO',
       'COMPRAS', 'ALMOXARIFADO', 'TECNICO', 'APONTAMENTO_RH'
     ) then
    raise exception 'os_detail_access_denied';
  end if;

  select os.*
    into v_os
  from public.ordens_servico os
  where os.id = p_os_id
    and os.tenant_id = p_tenant_id
    and os.empresa_id = p_empresa_id;

  if not found then
    raise exception 'os_not_found';
  end if;

  select jsonb_build_object(
    'os', jsonb_build_object(
      'id', v_os.id,
      'numero_os', v_os.numero_os,
      'cliente_nome', v_os.cliente_nome,
      'cliente_id', v_os.cliente_id,
      'status', v_os.status,
      'descricao_servico', v_os.descricao_servico,
      'valor_total', v_os.valor_total,
      'data_abertura', v_os.data_abertura,
      'orcado', v_os.orcado,
      'tipo_pedido', v_os.tipo_pedido,
      'tem_gestao', v_os.tem_gestao,
      'pedido_compra', v_os.pedido_compra,
      'vendedor', v_os.vendedor,
      'usa_relatorio_hh', v_os.usa_relatorio_hh
    ),
    'cliente_habilita_hh', coalesce((
      select c.habilita_hh
      from public.clientes c
      where c.id = v_os.cliente_id
        and c.tenant_id = p_tenant_id
        and c.empresa_id = p_empresa_id
    ), false) or coalesce(v_os.usa_relatorio_hh, false),
    'itens', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', oi.id,
          'item_id', oi.item_id,
          'quantidade', oi.quantidade,
          'valor_unitario', oi.valor_unitario,
          'valor_total', oi.valor_total,
          'desconto_percentual', oi.desconto_percentual,
          'desconto_valor', oi.desconto_valor,
          'baixa_estoque', oi.baixa_estoque,
          'quantidade_baixada', oi.quantidade_baixada,
          'criado_em', oi.criado_em,
          'registrado_em', oi.registrado_em,
          'registrado_por_nome', oi.registrado_por_nome,
          'itens', case when i.id is null then null else jsonb_build_object(
            'nome', i.nome,
            'codigo_interno', i.codigo_interno,
            'tipo', i.tipo
          ) end
        ) order by oi.id desc
      )
      from public.os_itens oi
      left join public.itens i
        on i.id = oi.item_id
       and i.tenant_id = oi.tenant_id
       and i.empresa_id = oi.empresa_id
      where oi.os_id = p_os_id
        and oi.tenant_id = p_tenant_id
        and oi.empresa_id = p_empresa_id
    ), '[]'::jsonb),
    'custo_mao_obra', coalesce((
      select v.custo_mao_obra
      from public.vw_custo_mao_obra_os v
      where v.os_id = p_os_id
      limit 1
    ), 0),
    'total_hh', coalesce((
      select v.total_hh
      from public.vw_hh_total_os v
      where v.os_id = p_os_id
      limit 1
    ), 0),
    'hh_lancamentos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'entrada_1', h.entrada_1,
        'saida_1', h.saida_1,
        'entrada_2', h.entrada_2,
        'saida_2', h.saida_2,
        'hora_entrada', h.hora_entrada,
        'hora_saida', h.hora_saida,
        'horas_trabalhadas', h.horas_trabalhadas,
        'percentual_aplicado', h.percentual_aplicado,
        'tem_extra_50', h.tem_extra_50,
        'horas_extra_50', h.horas_extra_50,
        'tem_extra_100', h.tem_extra_100,
        'horas_extra_100', h.horas_extra_100,
        'valor_hora', h.valor_hora,
        'valor_total', h.valor_total
      ))
      from public.hh_lancamentos h
      where h.os_id = p_os_id
        and h.tenant_id = p_tenant_id
        and h.empresa_id = p_empresa_id
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_os_detail_operacional(uuid, uuid, integer) from public, anon;
grant execute on function public.get_os_detail_operacional(uuid, uuid, integer) to authenticated, service_role;

comment on function public.search_relatorio_estoque(
  uuid, uuid, text, text, text, text, boolean, boolean, integer, integer, text, text
) is 'Relatorio de saldo consolidado, sempre escopado ao tenant e empresa ativos.';
comment on function public.get_os_detail_operacional(uuid, uuid, integer) is
  'Carrega o detalhe operacional de uma OS em uma unica consulta escopada e autorizada.';

notify pgrst, 'reload schema';

commit;
