-- Evita carregar todo o historico de movimentacoes ao exibir a ultima entrada
-- no localizador de itens do orcamento.
create index if not exists idx_movimentacoes_tenant_empresa_entrada_item_data
  on public.movimentacoes (tenant_id, empresa_id, item_id, data_movimentacao desc)
  where tipo = 'entrada';

drop function if exists public.ultima_entrada_por_itens(uuid, uuid, integer[]);

create function public.ultima_entrada_por_itens(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_item_ids integer[]
)
returns table (
  item_id integer,
  data_movimentacao timestamp without time zone
)
language sql
stable
security invoker
set search_path = public
as $$
  select distinct on (m.item_id)
    m.item_id,
    m.data_movimentacao
  from public.movimentacoes m
  where m.tenant_id = p_tenant_id
    and m.empresa_id = p_empresa_id
    and m.tipo = 'entrada'
    and m.item_id = any(coalesce(p_item_ids, array[]::integer[]))
  order by m.item_id, m.data_movimentacao desc nulls last, m.id desc;
$$;

revoke all on function public.ultima_entrada_por_itens(uuid, uuid, integer[]) from public, anon;
grant execute on function public.ultima_entrada_por_itens(uuid, uuid, integer[]) to authenticated, service_role;
