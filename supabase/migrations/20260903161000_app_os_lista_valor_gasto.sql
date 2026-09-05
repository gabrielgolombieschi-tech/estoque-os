begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

-- Expoe valor_gasto (custo operacional) na lista de OS do app, no grupo por
-- cliente e em cada OS dentro do grupo. O calculo vem de
-- public.fn_os_custo_operacional_unscoped (20260903160000_app_os_valor_gasto.sql),
-- o mesmo nucleo que alimenta o "consumido" da tela web.
--
-- No agrupamento o custo e resolvido em uma unica chamada com o array de todas
-- as OS filtradas, para nao repetir as CTEs pesadas por linha.

drop function if exists public.app_os_agrupado_cliente(text[], text);

create function public.app_os_agrupado_cliente(
  p_status text[] default array['em_andamento']::text[],
  p_busca text default null
)
returns table (
  cliente_id integer,
  cliente_nome text,
  quantidade_os integer,
  quantidade_sem_oc integer,
  responsaveis text[],
  quantidade_faturadas integer,
  total_horas numeric,
  valor_total numeric,
  valor_faturado numeric,
  valor_gasto numeric,
  pode_ver_valores boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a, f, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_pode_ver_valores boolean;
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  v_papel := a.fn_current_empresa_papel(v_tenant_id, v_empresa_id);
  if v_papel is null or v_papel = 'PAINEL_TV' then
    raise exception 'Sem permissao para consultar ordens de servico no app.';
  end if;

  if exists (
    select 1 from unnest(coalesce(p_status, '{}'::text[])) as filtro(status)
    where lower(filtro.status) not in ('em_andamento', 'concluida', 'faturada')
  ) then
    raise exception 'Filtro de status invalido.';
  end if;

  v_pode_ver_valores := public.app_mobile_pode_ver_valores_os(v_tenant_id, v_empresa_id);

  return query
  with os_filtradas as (
    select
      os.id,
      os.cliente_id,
      coalesce(nullif(btrim(cliente.nome), ''), nullif(btrim(os.cliente_nome), ''), 'Cliente nao informado')::text as cliente_nome,
      os.pedido_compra,
      coalesce(nullif(lower(os.status_fluxo), ''), public.mapear_status_legado_para_fluxo(os.status)) as status_fluxo,
      coalesce(horas.total_horas, 0)::numeric as total_horas,
      coalesce(nullif(btrim(perfil.nome), ''), nullif(btrim(usuario.nome), ''), nullif(btrim(colaborador.nome), ''))::text as responsavel_nome,
      case
        when coalesce(os.usa_relatorio_hh, false) then coalesce(valor_hh.total_hh, 0)
        else coalesce(os.orcado, 0)
      end::numeric as valor_pedido,
      coalesce(documentos.valor_faturado, 0)::numeric as valor_faturado
    from public.ordens_servico as os
    left join public.clientes as cliente
      on cliente.id = os.cliente_id
     and cliente.tenant_id = v_tenant_id
     and cliente.empresa_id = v_empresa_id
    left join public.profiles as perfil on perfil.id = os.responsavel_aprovacao_id
    left join a.usuario as usuario
      on usuario.auth_user_id = os.responsavel_aprovacao_id
     and usuario.ativo is true
     and usuario.deleted_at is null
    left join public.colaboradores as colaborador
      on colaborador.user_id = os.responsavel_aprovacao_id
     and colaborador.tenant_id = v_tenant_id
     and colaborador.empresa_id = v_empresa_id
     and colaborador.ativo is true
    left join lateral (
      select coalesce(sum(apontamento.horas), 0)::numeric as total_horas
      from public.apontamentos_horas as apontamento
      where apontamento.os_id = os.id
        and apontamento.tenant_id = v_tenant_id
        and apontamento.empresa_id = v_empresa_id
    ) as horas on true
    left join lateral (
      select coalesce(sum(resumo.total_hh), 0)::numeric as total_hh
      from public.vw_hh_total_os as resumo
      where resumo.os_id = os.id
        and resumo.tenant_id = v_tenant_id
        and resumo.empresa_id = v_empresa_id
    ) as valor_hh on true
    left join lateral (
      select coalesce(sum(documento.valor_total), 0)::numeric as valor_faturado
      from f.documento_fiscal as documento
      where documento.tenant_id = v_tenant_id
        and documento.empresa_id = v_empresa_id
        and documento.os_id_import = os.id
        and documento.operacao = 'SAIDA'
        and documento.deleted_at is null
        and (
          (upper(coalesce(documento.modelo, '')) = 'NFSE' and upper(coalesce(documento.nfse_status, '')) = 'EMITIDA')
          or (
            upper(coalesce(documento.modelo, '')) <> 'NFSE'
            and (nullif(btrim(documento.nfe_status), '') is null or upper(documento.nfe_status) = 'EMITIDA')
          )
        )
    ) as documentos on true
    where os.tenant_id = v_tenant_id
      and os.empresa_id = v_empresa_id
      and coalesce(os.tipo_documento, 'OS') = 'OS'
      and public.app_mobile_status_os_compativel(os.status_fluxo, os.status, p_status)
      and (
        v_busca is null
        or os.numero_os ilike '%' || v_busca || '%'
        or os.os_num::text ilike '%' || v_busca || '%'
        or os.cliente_nome ilike '%' || v_busca || '%'
        or cliente.nome ilike '%' || v_busca || '%'
        or os.descricao_servico ilike '%' || v_busca || '%'
      )
  ),
  ids_filtrados as (
    select coalesce(array_agg(os_filtrada.id), '{}'::integer[]) as lista
    from os_filtradas as os_filtrada
  ),
  custos as (
    select custo.os_id, custo.custo_total
    from ids_filtrados,
         public.fn_os_custo_operacional_unscoped(v_tenant_id, v_empresa_id, ids_filtrados.lista) as custo
  )
  select
    filtrada.cliente_id,
    filtrada.cliente_nome,
    count(*)::integer as quantidade_os,
    count(*) filter (where nullif(btrim(filtrada.pedido_compra), '') is null)::integer as quantidade_sem_oc,
    coalesce(
      array_agg(distinct filtrada.responsavel_nome order by filtrada.responsavel_nome)
        filter (where filtrada.responsavel_nome is not null),
      '{}'::text[]
    ) as responsaveis,
    count(*) filter (where filtrada.status_fluxo = 'faturada')::integer as quantidade_faturadas,
    sum(filtrada.total_horas)::numeric as total_horas,
    case when v_pode_ver_valores then sum(filtrada.valor_pedido)::numeric else null::numeric end as valor_total,
    case when v_pode_ver_valores then sum(filtrada.valor_faturado)::numeric else null::numeric end as valor_faturado,
    case when v_pode_ver_valores then sum(coalesce(custo.custo_total, 0))::numeric else null::numeric end as valor_gasto,
    v_pode_ver_valores as pode_ver_valores
  from os_filtradas as filtrada
  left join custos as custo on custo.os_id = filtrada.id
  group by filtrada.cliente_id, filtrada.cliente_nome
  order by lower(filtrada.cliente_nome), filtrada.cliente_id nulls last;
end;
$$;

drop function if exists public.app_os_do_cliente(integer, text[]);

create function public.app_os_do_cliente(
  p_cliente_id integer,
  p_status text[] default array['em_andamento']::text[]
)
returns table (
  id integer,
  numero_os character varying,
  os_num bigint,
  cliente_id integer,
  cliente_nome text,
  descricao_servico text,
  status_legado character varying,
  status_fluxo text,
  usa_relatorio_hh boolean,
  total_horas numeric,
  responsavel_nome text,
  situacao_margem text,
  pedido_compra text,
  pendencias_aprovacao integer,
  garantia_motivo text,
  faturado_em timestamptz,
  faturada_presumida_legado boolean,
  pode_concluir boolean,
  pode_faturar boolean,
  pode_reabrir_garantia boolean,
  pode_concluir_garantia boolean,
  valor_total numeric,
  valor_faturado numeric,
  valor_gasto numeric,
  pode_ver_valores boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a, f, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_pode_ver_valores boolean;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  v_papel := a.fn_current_empresa_papel(v_tenant_id, v_empresa_id);
  if v_papel is null or v_papel = 'PAINEL_TV' then
    raise exception 'Sem permissao para consultar ordens de servico no app.';
  end if;

  if exists (
    select 1 from unnest(coalesce(p_status, '{}'::text[])) as filtro(status)
    where lower(filtro.status) not in ('em_andamento', 'concluida', 'faturada')
  ) then
    raise exception 'Filtro de status invalido.';
  end if;

  v_pode_ver_valores := public.app_mobile_pode_ver_valores_os(v_tenant_id, v_empresa_id);

  return query
  select
    os.id,
    os.numero_os,
    os.os_num,
    os.cliente_id,
    coalesce(nullif(btrim(os.cliente_nome), ''), nullif(btrim(cliente.nome), ''), 'Cliente nao informado')::text,
    os.descricao_servico,
    os.status,
    coalesce(nullif(lower(os.status_fluxo), ''), public.mapear_status_legado_para_fluxo(os.status))::text,
    coalesce(os.usa_relatorio_hh, false),
    coalesce(horas.total_horas, 0)::numeric,
    coalesce(nullif(btrim(perfil.nome), ''), nullif(btrim(usuario.nome), ''), nullif(btrim(colaborador.nome), ''))::text,
    null::text,
    os.pedido_compra::text,
    coalesce(pendencias.quantidade, 0)::integer,
    os.garantia_motivo,
    os.faturado_em,
    os.faturada_presumida_legado,
    v_papel in ('ADMIN', 'DIRETOR', 'COORDENACAO'),
    v_papel = 'FINANCEIRO' and documentos.valor_faturado > 0,
    v_papel in ('COORDENACAO', 'FINANCEIRO')
      and os.status_fluxo = 'faturada'
      and not coalesce(os.faturada_presumida_legado, false)
      and os.faturado_em is not null
      and os.faturado_em >= now() - interval '6 months',
    v_papel = 'COORDENACAO',
    case
      when v_pode_ver_valores then
        case when coalesce(os.usa_relatorio_hh, false) then coalesce(valor_hh.total_hh, 0) else coalesce(os.orcado, 0) end
      else null::numeric
    end::numeric,
    case when v_pode_ver_valores then documentos.valor_faturado else null::numeric end::numeric,
    case when v_pode_ver_valores then coalesce(custo.custo_total, 0) else null::numeric end::numeric,
    v_pode_ver_valores
  from public.ordens_servico as os
  left join public.clientes as cliente
    on cliente.id = os.cliente_id
   and cliente.tenant_id = v_tenant_id
   and cliente.empresa_id = v_empresa_id
  left join public.profiles as perfil on perfil.id = os.responsavel_aprovacao_id
  left join a.usuario as usuario
    on usuario.auth_user_id = os.responsavel_aprovacao_id
   and usuario.ativo is true
   and usuario.deleted_at is null
  left join public.colaboradores as colaborador
    on colaborador.user_id = os.responsavel_aprovacao_id
   and colaborador.tenant_id = v_tenant_id
   and colaborador.empresa_id = v_empresa_id
   and colaborador.ativo is true
  left join lateral (
    select coalesce(sum(apontamento.horas), 0)::numeric as total_horas
    from public.apontamentos_horas as apontamento
    where apontamento.os_id = os.id
      and apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
  ) as horas on true
  left join lateral (
    select count(*)::integer as quantidade
    from public.apontamentos_horas as apontamento
    where apontamento.os_id = os.id
      and apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
      and apontamento.status_aprovacao = 'pendente'
  ) as pendencias on true
  left join lateral (
    select coalesce(sum(resumo.total_hh), 0)::numeric as total_hh
    from public.vw_hh_total_os as resumo
    where resumo.os_id = os.id
      and resumo.tenant_id = v_tenant_id
      and resumo.empresa_id = v_empresa_id
  ) as valor_hh on true
  left join lateral (
    select coalesce(sum(documento.valor_total), 0)::numeric as valor_faturado
    from f.documento_fiscal as documento
    where documento.tenant_id = v_tenant_id
      and documento.empresa_id = v_empresa_id
      and documento.os_id_import = os.id
      and documento.operacao = 'SAIDA'
      and documento.deleted_at is null
      and (
        (upper(coalesce(documento.modelo, '')) = 'NFSE' and upper(coalesce(documento.nfse_status, '')) = 'EMITIDA')
        or (
          upper(coalesce(documento.modelo, '')) <> 'NFSE'
          and (nullif(btrim(documento.nfe_status), '') is null or upper(documento.nfe_status) = 'EMITIDA')
        )
      )
  ) as documentos on true
  left join lateral (
    select item.custo_total
    from public.fn_os_custo_operacional_unscoped(v_tenant_id, v_empresa_id, array[os.id]) as item
    limit 1
  ) as custo on true
  where os.tenant_id = v_tenant_id
    and os.empresa_id = v_empresa_id
    and coalesce(os.tipo_documento, 'OS') = 'OS'
    and (os.cliente_id = p_cliente_id or (os.cliente_id is null and p_cliente_id is null))
    and public.app_mobile_status_os_compativel(os.status_fluxo, os.status, p_status)
  order by os.data_abertura desc nulls last, os.id desc;
end;
$$;

revoke all on function public.app_os_agrupado_cliente(text[], text) from public, anon, authenticated;
revoke all on function public.app_os_do_cliente(integer, text[]) from public, anon, authenticated;
grant execute on function public.app_os_agrupado_cliente(text[], text) to authenticated, service_role;
grant execute on function public.app_os_do_cliente(integer, text[]) to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
