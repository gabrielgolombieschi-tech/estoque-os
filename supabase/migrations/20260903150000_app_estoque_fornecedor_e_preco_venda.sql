begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- Tela de estoque do app: passa a mostrar o fornecedor do item e troca o preco
-- de custo pelo preco de venda.
--
-- O preco sai da mesma regra do orcamento: o nucleo canonico
-- public.fn_preco_venda_item_valores (20260829110000_preco_venda_canonico.sql),
-- alimentado pela margem de a.config_orcamento. A margem e lida uma unica vez
-- por chamada, em vez de chamar fn_preco_venda_item_unscoped por linha, que
-- refaria a leitura de config e de itens a cada item da pagina.
--
-- A coluna muda de nome (preco_unitario -> preco_venda) de proposito: o valor
-- deixou de ser custo e nada mais deve le-lo como se fosse.

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
  fornecedor text,
  preco_venda numeric,
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
  v_margem numeric;
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

  -- Mesma leitura de margem de public.fn_preco_venda_item_unscoped.
  select cfg.margem_lucro_padrao_percent
    into v_margem
  from a.config_orcamento cfg
  where cfg.tenant_id = v_tenant_id
    and cfg.empresa_id = v_empresa_id
    and cfg.deleted_at is null
  order by cfg.updated_at desc nulls last, cfg.created_at desc
  limit 1;
  v_margem := coalesce(v_margem, 53);

  return query
  select
    item.id,
    item.codigo_interno::text,
    coalesce(nullif(btrim(item.nome), ''), nullif(btrim(item.descricao), ''), 'Item sem nome')::text,
    coalesce(nullif(btrim(item.unidade_medida), ''), 'un')::text,
    coalesce(estoque.quantidade_atual, 0)::numeric,
    estoque.localizacao::text,
    forn.nome::text,
    case
      when v_pode_ver_preco then public.fn_preco_venda_item_valores(
        item.custo_ultima_compra,
        item.preco_unitario,
        item.aliquota_ipi,
        v_margem
      )
      else null::numeric
    end,
    v_pode_ver_preco
  from public.itens as item
  left join public.estoque as estoque
    on estoque.item_id = item.id
   and estoque.tenant_id = v_tenant_id
   and estoque.empresa_id = v_empresa_id
  left join public.fornecedores as forn
    on forn.id = item.fornecedor_id
   and forn.tenant_id = item.tenant_id
   and forn.empresa_id = item.empresa_id
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
  'Consulta somente leitura do estoque no app, com fornecedor do item. O preco e o de venda (mesma regra do orcamento: fn_preco_venda_item_valores + margem de config_orcamento) e fica nulo para perfis de apontamento em campo.';

notify pgrst, 'reload schema';

commit;
