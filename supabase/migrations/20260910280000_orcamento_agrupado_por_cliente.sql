-- Orcamentos agrupados por cliente, como as ordens de servico ja sao.
--
-- A tela de OS tem o par app_os_agrupado_cliente + app_os_do_cliente: a primeira devolve
-- um cartao por cliente com os totais, a segunda devolve as OS daquele cliente quando o
-- cartao e aberto. A de orcamentos so tinha a lista corrida.
--
-- O agregado precisa ser do servidor, nao da tela. As duas listagens paginam
-- (app_orcamento_listar tem limite/offset; a web usa page/pageSize), entao somar em
-- memoria mostraria o total do que coube na pagina, nao o do cliente — um numero errado
-- com cara de certo.
--
-- Escopo, filtros e busca sao os mesmos de app_orcamento_listar, inclusive
-- app_orcamento_assert_acesso: quem nao ve a lista tambem nao ve o agrupamento.

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
  v_busca text := nullif(btrim(p_busca), '');
  v_status text := nullif(btrim(upper(p_status)), '');
begin
  select * into v_scope from public.app_orcamento_assert_acesso();

  return query
  select
    orcamento.cliente_id,
    coalesce(nullif(btrim(cliente.nome), ''), 'Cliente não informado') as cliente_nome,
    count(*)::integer as quantidade_orcamentos,
    coalesce(sum((
      select count(*)
      from m.orcamento_item as item
      where item.orcamento_id = orcamento.id
        and item.deleted_at is null
    )), 0)::integer as quantidade_itens,
    coalesce(sum(orcamento.total_liquido), 0)::numeric as valor_total,
    max(orcamento.emissao_date) as ultima_emissao,
    coalesce(
      array_agg(distinct nullif(btrim(vendedor.nome), ''))
        filter (where nullif(btrim(vendedor.nome), '') is not null),
      '{}'::text[]
    ) as vendedores
  from m.orcamento as orcamento
  left join public.clientes as cliente
    on cliente.id = orcamento.cliente_id
   and cliente.tenant_id = orcamento.tenant_id
  left join a.usuario as vendedor
    on vendedor.id = orcamento.vendedor_usuario_id
  where orcamento.tenant_id = v_scope.tenant_id
    and orcamento.empresa_id = v_scope.empresa_id
    and orcamento.deleted_at is null
    and (v_status is null or orcamento.status = v_status)
    and (
      v_busca is null
      or orcamento.codigo ilike '%' || v_busca || '%'
      or orcamento.titulo ilike '%' || v_busca || '%'
      or cliente.nome ilike '%' || v_busca || '%'
    )
  group by orcamento.cliente_id, coalesce(nullif(btrim(cliente.nome), ''), 'Cliente não informado')
  order by coalesce(nullif(btrim(cliente.nome), ''), 'Cliente não informado');
end;
$function$;

-- Os orcamentos de um cliente, para quando o cartao dele e aberto. Mesma forma de linha
-- de app_orcamento_listar, para as telas reaproveitarem o mesmo componente de item.
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
  v_busca text := nullif(btrim(p_busca), '');
  v_status text := nullif(btrim(upper(p_status)), '');
begin
  select * into v_scope from public.app_orcamento_assert_acesso();

  return coalesce((
    select jsonb_agg(linha order by linha->>'emissao_date' desc, linha->>'codigo' desc)
    from (
      select jsonb_build_object(
        'id', orcamento.id,
        'codigo', orcamento.codigo,
        'titulo', orcamento.titulo,
        'status', orcamento.status,
        'emissao_date', orcamento.emissao_date,
        'cliente_id', orcamento.cliente_id,
        'cliente_nome', coalesce(nullif(btrim(cliente.nome), ''), 'Cliente não informado'),
        'total_liquido', orcamento.total_liquido,
        'itens', (
          select count(*)
          from m.orcamento_item as item
          where item.orcamento_id = orcamento.id
            and item.deleted_at is null
        )
      ) as linha
      from m.orcamento as orcamento
      left join public.clientes as cliente
        on cliente.id = orcamento.cliente_id
       and cliente.tenant_id = orcamento.tenant_id
      where orcamento.tenant_id = v_scope.tenant_id
        and orcamento.empresa_id = v_scope.empresa_id
        and orcamento.deleted_at is null
        and orcamento.cliente_id is not distinct from p_cliente_id
        and (v_status is null or orcamento.status = v_status)
        and (
          v_busca is null
          or orcamento.codigo ilike '%' || v_busca || '%'
          or orcamento.titulo ilike '%' || v_busca || '%'
          or cliente.nome ilike '%' || v_busca || '%'
        )
      order by orcamento.emissao_date desc, orcamento.numero desc
    ) as linhas
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.app_orcamento_agrupado_cliente(text, text) from public;
revoke all on function public.app_orcamento_do_cliente(integer, text, text) from public;
grant execute on function public.app_orcamento_agrupado_cliente(text, text) to authenticated, service_role;
grant execute on function public.app_orcamento_do_cliente(integer, text, text) to authenticated, service_role;

comment on function public.app_orcamento_agrupado_cliente(text, text) is
  'Um cartao por cliente com os totais dos orcamentos do filtro, para a visao "Por cliente". Mesmo escopo, filtros e busca de app_orcamento_listar.';
comment on function public.app_orcamento_do_cliente(integer, text, text) is
  'Orcamentos de um cliente, na mesma forma de linha de app_orcamento_listar, para abrir o cartao do cliente.';
