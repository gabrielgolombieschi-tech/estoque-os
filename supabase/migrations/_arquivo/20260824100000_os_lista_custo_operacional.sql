-- Total operacional da lista de OS.
-- Mantém a fórmula da tela de detalhe em um único ponto autorizado,
-- evitando que RLS nas tabelas componentes produza totais parciais no browser.

create or replace function public.get_os_lista_custos_operacionais(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_os_ids integer[]
)
returns table (
  os_id integer,
  custo_total numeric
)
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_papel text := a.fn_current_empresa_papel(p_tenant_id, p_empresa_id);
begin
  if auth.uid() is null
     or p_tenant_id is null
     or p_empresa_id is null
     or coalesce(array_length(p_os_ids, 1), 0) = 0
     or public.current_tenant_id() is distinct from p_tenant_id
     or public.current_empresa_id__by_tenant(p_tenant_id) is distinct from p_empresa_id
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or coalesce(v_papel, '') not in (
       'ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO', 'COORDENACAO',
       'COMPRAS', 'ALMOXARIFADO', 'TECNICO', 'APONTAMENTO_RH'
     ) then
    raise exception 'os_cost_list_access_denied';
  end if;

  return query
  with os_base as (
    select os.id, os.orcado, os.tipo_pedido, coalesce(os.usa_relatorio_hh, false) as usa_relatorio_hh
    from public.ordens_servico as os
    where os.id = any(p_os_ids)
      and os.tenant_id = p_tenant_id
      and os.empresa_id = p_empresa_id
  ),
  itens_por_os as (
    select
      os_item.os_id,
      coalesce(sum(os_item.valor_total) filter (
        where not (
          os_item.item_id between 1 and 99
          or lower(coalesce(item.tipo, '')) = 'despesa'
        )
        and item.tipo = 'produto'
      ), 0)::numeric as materiais,
      coalesce(sum(os_item.valor_total) filter (
        where os_item.item_id between 1 and 99
           or lower(coalesce(item.tipo, '')) = 'despesa'
      ), 0)::numeric as despesas
    from public.os_itens as os_item
    join os_base as os on os.id = os_item.os_id
    left join public.itens as item
      on item.id = os_item.item_id
     and item.tenant_id = os_item.tenant_id
     and item.empresa_id = os_item.empresa_id
    where os_item.tenant_id = p_tenant_id
      and os_item.empresa_id = p_empresa_id
    group by os_item.os_id
  ),
  mao_obra_por_os as (
    select custo.os_id, coalesce(custo.custo_mao_obra, 0)::numeric as mao_obra
    from public.vw_custo_mao_obra_os as custo
    join os_base as os on os.id = custo.os_id
  ),
  hh_horas_efetivas as (
    select
      hh.os_id,
      hh.valor_hora,
      hh.valor_total,
      hh.percentual_aplicado,
      hh.tem_extra_50,
      hh.tem_extra_100,
      hh.horas_extra_50,
      hh.horas_extra_100,
      case
        when periodo.entrada_1 is not null
         and periodo.saida_1 is not null
         and periodo.entrada_2 is not null
         and periodo.saida_2 is not null
          then round((
            case when periodo.saida_1 >= periodo.entrada_1
              then extract(epoch from (periodo.saida_1 - periodo.entrada_1)) / 3600
              else 24 + extract(epoch from (periodo.saida_1 - periodo.entrada_1)) / 3600
            end
            + case when periodo.saida_2 >= periodo.entrada_2
              then extract(epoch from (periodo.saida_2 - periodo.entrada_2)) / 3600
              else 24 + extract(epoch from (periodo.saida_2 - periodo.entrada_2)) / 3600
            end
          )::numeric, 2)
        when periodo.entrada_1 is not null and periodo.saida_1 is not null
          then round((case when periodo.saida_1 >= periodo.entrada_1
            then extract(epoch from (periodo.saida_1 - periodo.entrada_1)) / 3600
            else 24 + extract(epoch from (periodo.saida_1 - periodo.entrada_1)) / 3600
          end)::numeric, 2)
        else coalesce(hh.horas_trabalhadas, 0)::numeric
      end as horas_efetivas
    from public.hh_lancamentos as hh
    join os_base as os on os.id = hh.os_id
    cross join lateral (
      select
        coalesce(hh.entrada_1, hh.hora_entrada) as entrada_1,
        coalesce(hh.saida_1, hh.hora_saida) as saida_1,
        hh.entrada_2 as entrada_2,
        hh.saida_2 as saida_2
    ) as periodo
    where hh.tenant_id = p_tenant_id
      and hh.empresa_id = p_empresa_id
  ),
  pedido_hh_por_os as (
    select hh.os_id, round(coalesce(sum(
      case
        when (
          coalesce(hh.tem_extra_50, false)
          or coalesce(hh.tem_extra_100, false)
          or coalesce(hh.horas_extra_50, 0) > 0
          or coalesce(hh.horas_extra_100, 0) > 0
          or coalesce(hh.percentual_aplicado, 0) in (50, 100)
        ) and coalesce(hh.valor_total, 0) > 0 then hh.valor_total
        when coalesce(hh.valor_hora, 0) > 0 and hh.horas_efetivas > 0 then
          case
            when coalesce(hh.tem_extra_50, false)
              or coalesce(hh.tem_extra_100, false)
              or coalesce(hh.horas_extra_50, 0) > 0
              or coalesce(hh.horas_extra_100, 0) > 0
              then greatest(0, hh.horas_efetivas - coalesce(hh.horas_extra_50, 0) - coalesce(hh.horas_extra_100, 0)) * hh.valor_hora
                   + coalesce(hh.horas_extra_50, 0) * hh.valor_hora * 1.5
                   + coalesce(hh.horas_extra_100, 0) * hh.valor_hora * 2
            when coalesce(hh.percentual_aplicado, 0) = 50 then hh.horas_efetivas * hh.valor_hora * 1.5
            when coalesce(hh.percentual_aplicado, 0) = 100 then hh.horas_efetivas * hh.valor_hora * 2
            else hh.horas_efetivas * hh.valor_hora
          end
        else coalesce(hh.valor_total, 0)
      end
    ), 0)::numeric, 2) as pedido_hh
    from hh_horas_efetivas as hh
    group by hh.os_id
  )
  select
    os.id,
    case
      when os.usa_relatorio_hh then
        coalesce(pedido_hh.pedido_hh, 0)
        + coalesce(itens.materiais, 0)
        + coalesce(itens.despesas, 0)
        + coalesce(mao_obra.mao_obra, 0)
      else
        coalesce(itens.materiais, 0)
        + coalesce(itens.despesas, 0)
        + coalesce(mao_obra.mao_obra, 0)
        + case
            when os.tipo_pedido = 'material' then coalesce(os.orcado, 0) * 0.27
            else coalesce(os.orcado, 0) * 0.15
          end
    end::numeric as custo_total
  from os_base as os
  left join itens_por_os as itens on itens.os_id = os.id
  left join mao_obra_por_os as mao_obra on mao_obra.os_id = os.id
  left join pedido_hh_por_os as pedido_hh on pedido_hh.os_id = os.id;
end;
$$;

revoke all on function public.get_os_lista_custos_operacionais(uuid, uuid, integer[]) from public, anon;
grant execute on function public.get_os_lista_custos_operacionais(uuid, uuid, integer[]) to authenticated, service_role;

comment on function public.get_os_lista_custos_operacionais(uuid, uuid, integer[]) is
  'Retorna o custo operacional total de uma lista de OS usando a mesma fórmula da tela de detalhe.';

notify pgrst, 'reload schema';
