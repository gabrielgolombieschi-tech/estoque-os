begin;

drop function if exists public.app_consultar_estoque(text, boolean, integer, integer);

create function public.app_consultar_estoque(
  p_busca text default null,
  p_apenas_disponiveis boolean default true,
  p_limite integer default 60,
  p_offset integer default 0
)
returns table (
  item_id integer,
  codigo_interno text,
  nome text,
  unidade_medida text,
  quantidade_disponivel numeric,
  localizacao text,
  preco_unitario numeric,
  pode_ver_preco boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_pode_ver_preco boolean;
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
  v_limite integer := greatest(1, least(coalesce(p_limite, 60), 100));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  v_papel := a.fn_current_empresa_papel(v_tenant_id, v_empresa_id);
  if v_papel is null or v_papel = 'PAINEL_TV' then
    raise exception 'Sem permissao para consultar o estoque no app.';
  end if;

  v_pode_ver_preco := v_papel not in ('TECNICO', 'APONTAMENTO_RH', 'APONTADOR');

  return query
  select
    item.id,
    item.codigo_interno::text,
    coalesce(nullif(btrim(item.nome), ''), nullif(btrim(item.descricao), ''), 'Item sem nome')::text,
    coalesce(nullif(btrim(item.unidade_medida), ''), 'un')::text,
    coalesce(estoque.quantidade_atual, 0)::numeric,
    estoque.localizacao::text,
    case
      when v_pode_ver_preco then coalesce(
        nullif(item.preco_unitario, 0),
        nullif(item.custo_medio, 0),
        nullif(item.custo_ultima_compra, 0),
        0
      )::numeric
      else null::numeric
    end,
    v_pode_ver_preco
  from public.itens as item
  left join public.estoque as estoque
    on estoque.item_id = item.id
   and estoque.tenant_id = v_tenant_id
   and estoque.empresa_id = v_empresa_id
  where item.tenant_id = v_tenant_id
    and item.empresa_id = v_empresa_id
    and item.ativo is true
    and item.tipo = 'produto'
    and item.controla_estoque is true
    and (not coalesce(p_apenas_disponiveis, true) or coalesce(estoque.quantidade_atual, 0) > 0)
    and (
      v_busca is null
      or item.id::text = v_busca
      or item.codigo_interno ilike '%' || v_busca || '%'
      or item.codigo_barras ilike '%' || v_busca || '%'
      or item.nome ilike '%' || v_busca || '%'
      or item.descricao ilike '%' || v_busca || '%'
      or item.fabricante ilike '%' || v_busca || '%'
    )
  order by lower(coalesce(item.nome, item.descricao)), item.id
  limit v_limite
  offset v_offset;
end;
$$;

revoke all on function public.app_consultar_estoque(text, boolean, integer, integer)
  from public, anon;
grant execute on function public.app_consultar_estoque(text, boolean, integer, integer)
  to authenticated, service_role;

comment on function public.app_consultar_estoque(text, boolean, integer, integer) is
  'Consulta somente leitura do estoque no app; preco fica nulo para perfis de apontamento em campo.';

commit;
