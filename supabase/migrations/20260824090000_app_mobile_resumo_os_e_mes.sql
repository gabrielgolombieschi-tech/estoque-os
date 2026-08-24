-- Resumos operacionais para o app móvel.
-- A função calcula valores financeiros apenas internamente para produzir
-- um indicador textual; nenhum valor financeiro integra o retorno.

drop function if exists public.app_listar_os(boolean, text);

create function public.app_listar_os(
  p_incluir_fechadas boolean default false,
  p_busca text default null
)
returns table (
  id integer,
  numero_os character varying,
  os_num bigint,
  cliente_nome character varying,
  descricao_servico text,
  status character varying,
  usa_relatorio_hh boolean,
  data_abertura timestamp without time zone,
  sou_responsavel boolean,
  total_horas numeric,
  responsavel_nome text,
  situacao_margem text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a, c
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_colaborador_id uuid;
  v_papel_empresa text;
  v_busca text := nullif(btrim(p_busca), '');
begin
  if v_auth_uid is null then
    raise exception 'Autenticação obrigatória para consultar ordens de serviço.';
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();

  if v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Não foi possível identificar um tenant e uma empresa ativos para este usuário.';
  end if;

  select colaborador.id
    into v_colaborador_id
  from public.colaboradores as colaborador
  where colaborador.user_id = v_auth_uid
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo is true;

  if v_colaborador_id is null then
    raise exception 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.';
  end if;

  select usuario_empresa.papel
    into v_papel_empresa
  from a.usuario as usuario
  join a.usuario_empresa as usuario_empresa
    on usuario_empresa.usuario_id = usuario.id
   and usuario_empresa.empresa_id = v_empresa_id
   and usuario_empresa.ativo is true
   and usuario_empresa.deleted_at is null
  where usuario.auth_user_id = v_auth_uid
    and usuario.ativo is true
    and usuario.deleted_at is null
  limit 1;

  if v_papel_empresa is null then
    raise exception 'Não foi possível identificar o papel deste usuário na empresa atual.';
  end if;

  return query
  with os_base as (
    select os.*
    from public.ordens_servico as os
    where os.tenant_id = v_tenant_id
      and os.empresa_id = v_empresa_id
      and os.status in (
        'em_andamento',
        case when p_incluir_fechadas then 'concluida' else 'em_andamento' end
      )
      and (
        v_busca is null
        or os.numero_os ilike '%' || v_busca || '%'
        or os.os_num::text ilike '%' || v_busca || '%'
        or os.cliente_nome ilike '%' || v_busca || '%'
      )
  ),
  horas_por_os as (
    select apontamento.os_id, coalesce(sum(apontamento.horas), 0)::numeric as total_horas
    from public.apontamentos_horas as apontamento
    join os_base as os on os.id = apontamento.os_id
    where apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
      and (
        upper(v_papel_empresa) <> 'APONTADOR'
        or apontamento.colaborador_id = v_colaborador_id
      )
    group by apontamento.os_id
  ),
  materiais_por_os as (
    select os_item.os_id, coalesce(sum(os_item.valor_total), 0)::numeric as materiais
    from public.os_itens as os_item
    join os_base as os on os.id = os_item.os_id
    join public.itens as item
      on item.id = os_item.item_id
     and item.tenant_id = os_item.tenant_id
     and item.empresa_id = os_item.empresa_id
    where os_item.tenant_id = v_tenant_id
      and os_item.empresa_id = v_empresa_id
      and item.tipo = 'produto'
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
    where hh.tenant_id = v_tenant_id
      and hh.empresa_id = v_empresa_id
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
  ),
  financeiro_por_os as (
    select
      os.id,
      coalesce(materiais.materiais, 0)::numeric as materiais,
      coalesce(mao_obra.mao_obra, 0)::numeric as mao_obra,
      case
        when os.usa_relatorio_hh then coalesce(pedido_hh.pedido_hh, 0)::numeric
        else coalesce(os.orcado, 0)::numeric
      end as pedido,
      case
        when os.usa_relatorio_hh then coalesce(pedido_hh.pedido_hh, 0)::numeric * 0.15
        when os.tipo_pedido = 'material' then coalesce(os.orcado, 0)::numeric * 0.27
        else coalesce(os.orcado, 0)::numeric * 0.15
      end as impostos
    from os_base as os
    left join materiais_por_os as materiais on materiais.os_id = os.id
    left join mao_obra_por_os as mao_obra on mao_obra.os_id = os.id
    left join pedido_hh_por_os as pedido_hh on pedido_hh.os_id = os.id
  )
  select
    os.id,
    os.numero_os,
    os.os_num,
    os.cliente_nome,
    os.descricao_servico,
    os.status,
    os.usa_relatorio_hh,
    os.data_abertura,
    (os.responsavel_aprovacao_id is not distinct from v_auth_uid) as sou_responsavel,
    coalesce(horas.total_horas, 0)::numeric as total_horas,
    coalesce(
      nullif(perfil_responsavel.nome, ''),
      nullif(usuario_responsavel.nome, ''),
      nullif(colaborador_responsavel.nome, '')
    )::text as responsavel_nome,
    case
      when upper(v_papel_empresa) = 'APONTADOR' then null
      when (financeiro.materiais + financeiro.mao_obra + financeiro.impostos) <= 0 then 'ok'
      when (financeiro.pedido - (financeiro.materiais + financeiro.mao_obra + financeiro.impostos))
        / (financeiro.materiais + financeiro.mao_obra + financeiro.impostos) < 0 then 'prejuizo'
      when (financeiro.pedido - (financeiro.materiais + financeiro.mao_obra + financeiro.impostos))
        / (financeiro.materiais + financeiro.mao_obra + financeiro.impostos) < 0.15 then 'atencao'
      else 'ok'
    end::text as situacao_margem
  from os_base as os
  left join horas_por_os as horas on horas.os_id = os.id
  left join financeiro_por_os as financeiro on financeiro.id = os.id
  left join public.profiles as perfil_responsavel on perfil_responsavel.id = os.responsavel_aprovacao_id
  left join a.usuario as usuario_responsavel
    on usuario_responsavel.auth_user_id = os.responsavel_aprovacao_id
   and usuario_responsavel.ativo is true
   and usuario_responsavel.deleted_at is null
  left join public.colaboradores as colaborador_responsavel
    on colaborador_responsavel.user_id = os.responsavel_aprovacao_id
   and colaborador_responsavel.tenant_id = v_tenant_id
   and colaborador_responsavel.empresa_id = v_empresa_id
  order by os.data_abertura desc nulls last, os.id desc;
end;
$$;

create function public.app_resumo_mes()
returns table (
  nome_colaborador character varying,
  mes_referencia date,
  total_horas numeric
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a, c
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_colaborador_id uuid;
  v_nome_colaborador character varying;
  v_mes_referencia date := date_trunc('month', current_date)::date;
begin
  if v_auth_uid is null then
    raise exception 'Autenticação obrigatória para consultar o resumo mensal.';
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();

  if v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Não foi possível identificar um tenant e uma empresa ativos para este usuário.';
  end if;

  select colaborador.id, colaborador.nome
    into v_colaborador_id, v_nome_colaborador
  from public.colaboradores as colaborador
  where colaborador.user_id = v_auth_uid
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo is true;

  if v_colaborador_id is null then
    raise exception 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.';
  end if;

  return query
  select
    v_nome_colaborador,
    v_mes_referencia,
    coalesce(sum(apontamento.horas), 0)::numeric
  from public.apontamentos_horas as apontamento
  where apontamento.tenant_id = v_tenant_id
    and apontamento.empresa_id = v_empresa_id
    and apontamento.colaborador_id = v_colaborador_id
    and apontamento.data >= v_mes_referencia
    and apontamento.data < (v_mes_referencia + interval '1 month')::date;
end;
$$;

revoke all on function public.app_listar_os(boolean, text) from public, anon, authenticated, service_role;
revoke all on function public.app_resumo_mes() from public, anon, authenticated, service_role;

grant execute on function public.app_listar_os(boolean, text) to authenticated;
grant execute on function public.app_resumo_mes() to authenticated;
