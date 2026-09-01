begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- A busca direta em public.itens reavaliava as policies para cada linha.
-- Em perfis comerciais sem privilegio administrativo isso podia atingir o
-- statement_timeout. Esta RPC valida o acesso uma vez e consulta apenas a
-- empresa ativa, mantendo saldo e ultima entrada no mesmo round-trip.
create or replace function public.search_orcamento_itens(
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
  estoque_atual numeric
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
  if auth.uid() is null
     or p_tenant_id is null
     or p_empresa_id is null
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or not c.has_comercial_access(p_tenant_id, p_empresa_id) then
    raise exception 'orcamento_item_search_access_denied';
  end if;

  return query
  select
    i.id,
    i.codigo_interno::text,
    i.nome::text,
    i.fabricante::text,
    i.preco_unitario,
    i.custo_ultima_compra,
    f.nome::text as fornecedor,
    mov.data_movimentacao as ultima_entrada,
    e.quantidade_atual as estoque_atual
  from public.itens i
  left join public.fornecedores f
    on f.tenant_id = i.tenant_id
   and f.empresa_id = i.empresa_id
   and f.id = i.fornecedor_id
  left join public.estoque e
    on e.tenant_id = i.tenant_id
   and e.empresa_id = i.empresa_id
   and e.item_id = i.id
  left join lateral (
    select m.data_movimentacao
    from public.movimentacoes m
    where m.tenant_id = i.tenant_id
      and m.empresa_id = i.empresa_id
      and m.item_id = i.id
      and m.tipo = 'entrada'
    order by m.data_movimentacao desc nulls last, m.id desc
    limit 1
  ) mov on true
  where i.tenant_id = p_tenant_id
    and i.empresa_id = p_empresa_id
    and i.ativo is true
    and (
      v_term is null
      or (
        v_codigo_exato
        and (
          i.codigo_interno = v_term
          or i.codigo_barras = v_term
          or i.id::text = v_term
        )
      )
      or (
        not v_codigo_exato
        and (
          i.nome ilike '%' || v_term || '%'
          or i.codigo_interno ilike '%' || v_term || '%'
          or i.fabricante ilike '%' || v_term || '%'
        )
      )
    )
    and (v_fornecedor is null or f.nome ilike '%' || v_fornecedor || '%')
  order by i.nome asc, i.id asc
  limit v_limit;
end;
$$;

revoke all on function public.search_orcamento_itens(uuid, uuid, text, text, integer) from public, anon;
grant execute on function public.search_orcamento_itens(uuid, uuid, text, text, integer) to authenticated, service_role;

comment on function public.search_orcamento_itens(uuid, uuid, text, text, integer) is
  'Busca itens do orcamento apos validar uma unica vez o acesso comercial ao tenant e empresa.';

notify pgrst, 'reload schema';

commit;
