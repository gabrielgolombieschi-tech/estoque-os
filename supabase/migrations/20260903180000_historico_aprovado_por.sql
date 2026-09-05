begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

-- Histórico do app passa a devolver quem aprovou a hora, como já acontece na
-- listagem de apontamentos da OS (20260903170000).
--
-- O nome segue a mesma regra de privacidade que a função já aplica à autoria:
-- perfis de apontamento em campo continuam sem ver nomes internos.
-- Material não tem aprovação, então vem nulo nesse ramo.

drop function if exists public.app_historico_lancamentos(text, date, date, uuid, integer, integer, text);

create function public.app_historico_lancamentos(
  p_tipo text default 'tudo',
  p_de date default null,
  p_ate date default null,
  p_colaborador_id uuid default null,
  p_os_id integer default null,
  p_limite integer default 40,
  p_cursor text default null
)
returns table (
  tipo text,
  origem_id text,
  criado_em timestamptz,
  data_lancamento date,
  os_id integer,
  numero_os text,
  cliente_nome text,
  descricao text,
  quantidade numeric,
  unidade text,
  status text,
  nao_cobrado boolean,
  autor_id uuid,
  autor_nome text,
  pode_ver_autoria boolean,
  aprovado_por_nome text,
  cursor text
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
  v_colaborador_id uuid;
  v_apontador boolean;
  v_tipo text := lower(coalesce(nullif(btrim(p_tipo), ''), 'tudo'));
  v_de date := coalesce(p_de, current_date - 29);
  v_ate date := coalesce(p_ate, current_date);
  v_limite integer := greatest(1, least(coalesce(p_limite, 40), 100));
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  v_papel := a.fn_current_empresa_papel(v_tenant_id, v_empresa_id);
  if v_papel is null or v_papel = 'PAINEL_TV' then
    raise exception 'Sem permissao para consultar o historico do app.';
  end if;

  if v_tipo not in ('tudo', 'horas', 'materiais') then
    raise exception 'Tipo de historico invalido.';
  end if;
  if v_de > v_ate then
    raise exception 'Periodo de historico invalido.';
  end if;

  select colaborador.id
    into v_colaborador_id
  from public.colaboradores as colaborador
  where colaborador.user_id = v_auth_uid
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo is true
  limit 1;

  v_apontador := v_papel in ('TECNICO', 'APONTAMENTO_RH', 'APONTADOR');
  if v_apontador and v_colaborador_id is null then
    raise exception 'Seu usuario nao esta vinculado a um colaborador ativo nesta empresa.';
  end if;

  return query
  with lancamentos as (
    select
      'hora'::text as tipo,
      apontamento.id::text as origem_id,
      apontamento.criado_em::timestamptz as criado_em,
      apontamento.data as data_lancamento,
      os.id as os_id,
      coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text)::text as numero_os,
      coalesce(nullif(btrim(os.cliente_nome), ''), 'Cliente nao informado')::text as cliente_nome,
      coalesce(nullif(btrim(os.descricao_servico), ''), nullif(btrim(apontamento.descricao), ''), 'Apontamento de horas')::text as descricao,
      apontamento.horas::numeric as quantidade,
      'h'::text as unidade,
      coalesce(nullif(btrim(apontamento.status_aprovacao), ''), nullif(btrim(apontamento.status), ''), 'pendente')::text as status,
      false as nao_cobrado,
      apontamento.colaborador_id as autor_id,
      colaborador.nome::text as autor_nome,
      case
        when apontamento.aprovado_automaticamente_em is not null and apontamento.aprovado_por is null
          then 'Aprovação automática'
        else coalesce(
          nullif(btrim(perfil.nome), ''),
          nullif(btrim(aprovador.nome), ''),
          nullif(btrim(colaborador_aprovador.nome), '')
        )
      end::text as aprovado_por_nome
    from public.apontamentos_horas as apontamento
    join public.ordens_servico as os
      on os.id = apontamento.os_id
     and os.tenant_id = v_tenant_id
     and os.empresa_id = v_empresa_id
     and coalesce(os.tipo_documento, 'OS') = 'OS'
    join public.colaboradores as colaborador
      on colaborador.id = apontamento.colaborador_id
     and colaborador.tenant_id = v_tenant_id
     and colaborador.empresa_id = v_empresa_id
    left join public.profiles as perfil on perfil.id = apontamento.aprovado_por
    left join a.usuario as aprovador
      on aprovador.auth_user_id = apontamento.aprovado_por
     and aprovador.ativo is true
     and aprovador.deleted_at is null
    left join public.colaboradores as colaborador_aprovador
      on colaborador_aprovador.user_id = apontamento.aprovado_por
     and colaborador_aprovador.tenant_id = v_tenant_id
     and colaborador_aprovador.empresa_id = v_empresa_id
    where apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
      and apontamento.data between v_de and v_ate
      and v_tipo in ('tudo', 'horas')
      and (p_os_id is null or apontamento.os_id = p_os_id)
      and (
        case when v_apontador then apontamento.colaborador_id = v_colaborador_id
             else p_colaborador_id is null or apontamento.colaborador_id = p_colaborador_id end
      )

    union all

    select
      'material'::text,
      movimentacao.id::text,
      coalesce(movimentacao.created_at, movimentacao.data_movimentacao)::timestamptz,
      movimentacao.data_movimentacao::date,
      os.id,
      coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text)::text,
      coalesce(nullif(btrim(os.cliente_nome), ''), 'Cliente nao informado')::text,
      (coalesce(nullif(btrim(item.nome), ''), nullif(btrim(item.descricao), ''), 'Material')
        || case when nullif(btrim(item.codigo_interno), '') is not null then ' - cod. ' || item.codigo_interno else '' end)::text,
      movimentacao.quantidade::numeric,
      coalesce(nullif(btrim(item.unidade_medida), ''), 'un')::text,
      'baixado'::text,
      coalesce(item_os.nao_cobrado, false),
      autor.id,
      autor.nome::text,
      null::text
    from public.movimentacoes as movimentacao
    join public.ordens_servico as os
      on os.id = movimentacao.origem_os_id
     and os.tenant_id = v_tenant_id
     and os.empresa_id = v_empresa_id
     and coalesce(os.tipo_documento, 'OS') = 'OS'
    join public.itens as item
      on item.id = movimentacao.item_id
     and item.tenant_id = v_tenant_id
     and item.empresa_id = v_empresa_id
    left join lateral (
      select
        colaborador.id,
        colaborador.nome
      from public.colaboradores as colaborador
      where colaborador.tenant_id = v_tenant_id
        and colaborador.empresa_id = v_empresa_id
        and colaborador.ativo is true
        and (
          colaborador.user_id::text = movimentacao.realizado_por
          or lower(coalesce(colaborador.email, '')) = lower(coalesce(movimentacao.realizado_por, ''))
        )
      order by case when colaborador.user_id::text = movimentacao.realizado_por then 0 else 1 end
      limit 1
    ) as autor on true
    left join lateral (
      select public.os_lancamento_nao_cobrado(
        v_tenant_id,
        v_empresa_id,
        item_lancado.os_id,
        item_lancado.criado_em
      ) as nao_cobrado
      from public.os_itens as item_lancado
      where item_lancado.tenant_id = v_tenant_id
        and item_lancado.empresa_id = v_empresa_id
        and item_lancado.os_id = movimentacao.origem_os_id
        and item_lancado.item_id = movimentacao.item_id
        and abs(extract(epoch from (item_lancado.criado_em - movimentacao.data_movimentacao))) <= 600
      order by abs(extract(epoch from (item_lancado.criado_em - movimentacao.data_movimentacao))), item_lancado.id desc
      limit 1
    ) as item_os on true
    where movimentacao.tenant_id = v_tenant_id
      and movimentacao.empresa_id = v_empresa_id
      and movimentacao.tipo = 'saida'
      and movimentacao.motivo like 'Material lançado pelo app na OS %'
      and movimentacao.data_movimentacao::date between v_de and v_ate
      and v_tipo in ('tudo', 'materiais')
      and (p_os_id is null or movimentacao.origem_os_id = p_os_id)
      and (
        case when v_apontador then autor.id = v_colaborador_id
             else p_colaborador_id is null or autor.id = p_colaborador_id end
      )
  ), com_cursor as (
    select
      lancamento.*,
      to_char(lancamento.criado_em at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US')
        || '|' || lancamento.tipo || '|' || lancamento.origem_id as chave_cursor
    from lancamentos as lancamento
  )
  select
    lancamento.tipo,
    lancamento.origem_id,
    lancamento.criado_em,
    lancamento.data_lancamento,
    lancamento.os_id,
    lancamento.numero_os,
    lancamento.cliente_nome,
    lancamento.descricao,
    lancamento.quantidade,
    lancamento.unidade,
    lancamento.status,
    lancamento.nao_cobrado,
    case when v_apontador then null::uuid else lancamento.autor_id end,
    case when v_apontador then null::text else lancamento.autor_nome end,
    not v_apontador,
    case when v_apontador then null::text else lancamento.aprovado_por_nome end,
    lancamento.chave_cursor
  from com_cursor as lancamento
  where p_cursor is null or lancamento.chave_cursor < p_cursor
  order by lancamento.chave_cursor desc
  limit v_limite;
end;
$$;

revoke all on function public.app_historico_lancamentos(text, date, date, uuid, integer, integer, text) from public, anon;
grant execute on function public.app_historico_lancamentos(text, date, date, uuid, integer, integer, text) to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
