-- O agrupamento de orcamentos ganha as duas portas que a listagem ja tem.
--
-- A 20260910280000 criou o agregado so na porta do mobile (public.app_*, que resolve
-- tenant/empresa do contexto e passa por app_orcamento_assert_acesso). A web nao entra
-- por ali: ela chama m.fn_orcamento_listar com p_tenant_id/p_empresa_id explicitos e um
-- modelo de permissao proprio. Usar a porta do mobile na web barraria, em
-- app_mobile_pode_ver_valores_os, gente que enxerga a lista sem problema.
--
-- Entao a implementacao desce para m.fn_orcamento_agrupado_cliente /
-- m.fn_orcamento_do_cliente, com tenant e empresa explicitos, e a porta do mobile vira
-- casca: valida o acesso dela e delega. Uma regra de agrupamento so, duas maneiras de
-- provar quem e — a mesma divisao que ja existe entre app_orcamento_listar e
-- m.fn_orcamento_listar.
--
-- p_statuses e array, como em m.fn_orcamento_listar, porque a web tem o filtro "TODOS"
-- e mapeia status canonico para varios valores gravados.

create or replace function m.fn_orcamento_agrupado_cliente(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_statuses text[] default null,
  p_busca text default null
)
returns table (
  cliente_id integer,
  cliente_nome text,
  quantidade_orcamentos integer,
  quantidade_itens integer,
  valor_total numeric,
  ultima_emissao date,
  vendedores text[]
)
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'm', 'a'
set row_security to 'off'
as $function$
  select
    o.cliente_id,
    coalesce(nullif(btrim(c.nome), ''), 'Cliente não informado') as cliente_nome,
    count(*)::integer,
    coalesce(sum((
      select count(*) from m.orcamento_item i
      where i.orcamento_id = o.id and i.deleted_at is null
    )), 0)::integer,
    coalesce(sum(o.total_liquido), 0)::numeric,
    max(o.emissao_date),
    coalesce(
      array_agg(distinct nullif(btrim(u.nome), ''))
        filter (where nullif(btrim(u.nome), '') is not null),
      '{}'::text[]
    )
  from m.orcamento o
  left join public.clientes c on c.id = o.cliente_id and c.tenant_id = o.tenant_id
  left join a.usuario u on u.id = o.vendedor_usuario_id
  where o.tenant_id = p_tenant_id
    and o.empresa_id = p_empresa_id
    and o.deleted_at is null
    and (p_statuses is null or o.status = any (p_statuses))
    and (
      nullif(btrim(p_busca), '') is null
      or o.codigo ilike '%' || btrim(p_busca) || '%'
      or o.titulo ilike '%' || btrim(p_busca) || '%'
      or c.nome ilike '%' || btrim(p_busca) || '%'
    )
  group by o.cliente_id, coalesce(nullif(btrim(c.nome), ''), 'Cliente não informado')
  order by coalesce(nullif(btrim(c.nome), ''), 'Cliente não informado');
$function$;

create or replace function m.fn_orcamento_do_cliente(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_cliente_id integer,
  p_statuses text[] default null,
  p_busca text default null
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'm', 'a'
set row_security to 'off'
as $function$
  select coalesce((
    select jsonb_agg(linha order by linha->>'emissao_date' desc, linha->>'codigo' desc)
    from (
      select jsonb_build_object(
        'id', o.id,
        'codigo', o.codigo,
        'titulo', o.titulo,
        'status', o.status,
        'emissao_date', o.emissao_date,
        'cliente_id', o.cliente_id,
        'cliente_nome', coalesce(nullif(btrim(c.nome), ''), 'Cliente não informado'),
        'vendedor_nome', nullif(btrim(u.nome), ''),
        'total_liquido', o.total_liquido,
        'itens', (
          select count(*) from m.orcamento_item i
          where i.orcamento_id = o.id and i.deleted_at is null
        )
      ) as linha
      from m.orcamento o
      left join public.clientes c on c.id = o.cliente_id and c.tenant_id = o.tenant_id
      left join a.usuario u on u.id = o.vendedor_usuario_id
      where o.tenant_id = p_tenant_id
        and o.empresa_id = p_empresa_id
        and o.deleted_at is null
        and o.cliente_id is not distinct from p_cliente_id
        and (p_statuses is null or o.status = any (p_statuses))
        and (
          nullif(btrim(p_busca), '') is null
          or o.codigo ilike '%' || btrim(p_busca) || '%'
          or o.titulo ilike '%' || btrim(p_busca) || '%'
          or c.nome ilike '%' || btrim(p_busca) || '%'
        )
      order by o.emissao_date desc, o.numero desc
    ) as linhas
  ), '[]'::jsonb);
$function$;

-- Porta do mobile: valida o acesso proprio e delega.
create or replace function public.app_orcamento_agrupado_cliente(
  p_busca text default null,
  p_status text default 'ANDAMENTO'
)
returns table (
  cliente_id integer,
  cliente_nome text,
  quantidade_orcamentos integer,
  quantidade_itens integer,
  valor_total numeric,
  ultima_emissao date,
  vendedores text[]
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'm', 'a'
set row_security to 'off'
as $function$
declare
  v_scope record;
  v_status text := nullif(btrim(upper(p_status)), '');
begin
  select * into v_scope from public.app_orcamento_assert_acesso();
  return query
  select * from m.fn_orcamento_agrupado_cliente(
    v_scope.tenant_id,
    v_scope.empresa_id,
    case when v_status is null then null else array[v_status] end,
    p_busca
  );
end;
$function$;

create or replace function public.app_orcamento_do_cliente(
  p_cliente_id integer,
  p_busca text default null,
  p_status text default 'ANDAMENTO'
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'm', 'a'
set row_security to 'off'
as $function$
declare
  v_scope record;
  v_status text := nullif(btrim(upper(p_status)), '');
begin
  select * into v_scope from public.app_orcamento_assert_acesso();
  return m.fn_orcamento_do_cliente(
    v_scope.tenant_id,
    v_scope.empresa_id,
    p_cliente_id,
    case when v_status is null then null else array[v_status] end,
    p_busca
  );
end;
$function$;

revoke all on function m.fn_orcamento_agrupado_cliente(uuid, uuid, text[], text) from public;
revoke all on function m.fn_orcamento_do_cliente(uuid, uuid, integer, text[], text) from public;
grant execute on function m.fn_orcamento_agrupado_cliente(uuid, uuid, text[], text) to authenticated, service_role;
grant execute on function m.fn_orcamento_do_cliente(uuid, uuid, integer, text[], text) to authenticated, service_role;

comment on function m.fn_orcamento_agrupado_cliente(uuid, uuid, text[], text) is
  'Um cartao por cliente com os totais dos orcamentos do filtro. Tenant e empresa explicitos, como m.fn_orcamento_listar.';
comment on function m.fn_orcamento_do_cliente(uuid, uuid, integer, text[], text) is
  'Orcamentos de um cliente, para abrir o cartao dele na visao "Por cliente".';
