begin;

create or replace function public.fn_usuario_pode_editar_apontamento(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_auth_uid uuid,
  p_apontamento_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, a
set row_security = off
as $$
  select coalesce((
    select case
      when coalesce(apontamento.gerado_por_hh, false) then false
      when lower(coalesce(apontamento.status, '')) = 'fechado' then false
      when coalesce(apontamento.status_aprovacao, 'pendente') = 'aprovado'
        then coalesce(acesso.papel, '') in ('ADMIN', 'DIRETOR', 'COORDENACAO')
      else colaborador.user_id = p_auth_uid
    end
    from public.apontamentos_horas as apontamento
    join public.colaboradores as colaborador
      on colaborador.id = apontamento.colaborador_id
     and colaborador.tenant_id = apontamento.tenant_id
     and colaborador.empresa_id = apontamento.empresa_id
    left join lateral (
      select upper(usuario_empresa.papel) as papel
      from a.usuario as usuario
      join a.usuario_empresa as usuario_empresa
        on usuario_empresa.usuario_id = usuario.id
       and usuario_empresa.empresa_id = p_empresa_id
       and usuario_empresa.ativo is true
       and usuario_empresa.deleted_at is null
      where usuario.auth_user_id = p_auth_uid
        and usuario.ativo is true
        and usuario.deleted_at is null
      limit 1
    ) as acesso on true
    where apontamento.id = p_apontamento_id
      and apontamento.tenant_id = p_tenant_id
      and apontamento.empresa_id = p_empresa_id
  ), false);
$$;

revoke all on function public.fn_usuario_pode_editar_apontamento(uuid, uuid, uuid, uuid)
  from public, anon, authenticated, service_role;

-- Inserções seguem a regra de aprovação por papel. Em edições, a decisão passa
-- a considerar quem está corrigindo: Coordenação, Diretor e Admin mantêm um
-- lançamento já aprovado como aprovado; a correção do dono continua pendente.
create or replace function public.fn_apontamento_preparar_aprovacao()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, a, auth
as $$
declare
  v_auth_regra uuid;
  v_papel_regra text;
  v_editou boolean := false;
  v_exige_aprovacao boolean;
begin
  if tg_op = 'INSERT' then
    new.criado_por_user_id := coalesce(new.criado_por_user_id, auth.uid());
    v_auth_regra := new.criado_por_user_id;
  else
    v_editou := row(
      new.data, new.horas, new.tipo_hora_id, new.fator_aplicado, new.descricao,
      new.hora_entrada_1, new.hora_saida_1, new.hora_entrada_2, new.hora_saida_2
    ) is distinct from row(
      old.data, old.horas, old.tipo_hora_id, old.fator_aplicado, old.descricao,
      old.hora_entrada_1, old.hora_saida_1, old.hora_entrada_2, old.hora_saida_2
    );

    if not v_editou then
      return new;
    end if;
    v_auth_regra := auth.uid();
  end if;

  select upper(usuario_empresa.papel)
    into v_papel_regra
  from a.usuario as usuario
  join a.usuario_empresa as usuario_empresa
    on usuario_empresa.usuario_id = usuario.id
   and usuario_empresa.empresa_id = new.empresa_id
   and usuario_empresa.ativo is true
   and usuario_empresa.deleted_at is null
  where usuario.auth_user_id = v_auth_regra
    and usuario.ativo is true
    and usuario.deleted_at is null
  limit 1;

  if tg_op = 'UPDATE'
     and old.status_aprovacao = 'aprovado'
     and coalesce(v_papel_regra, '') in ('ADMIN', 'DIRETOR', 'COORDENACAO') then
    new.status_aprovacao := 'aprovado';
    new.pendente_em := null;
    new.aprovado_por := v_auth_regra;
    new.aprovado_em := now();
    new.aprovado_automaticamente_em := null;
    new.rejeitado_em := null;
    new.motivo_devolucao := null;
    return new;
  end if;

  v_exige_aprovacao := coalesce(v_papel_regra, '') in ('TECNICO', 'APONTAMENTO_RH', 'APONTADOR')
    or v_papel_regra is null;

  if v_exige_aprovacao then
    new.status_aprovacao := 'pendente';
    new.pendente_em := case when tg_op = 'UPDATE' then now() else coalesce(new.pendente_em, now()) end;
    new.aprovado_por := null;
    new.aprovado_em := null;
    new.aprovado_automaticamente_em := null;
    new.rejeitado_em := null;
    new.motivo_devolucao := null;
  else
    new.status_aprovacao := 'aprovado';
    new.pendente_em := null;
    new.aprovado_por := v_auth_regra;
    new.aprovado_em := now();
    new.aprovado_automaticamente_em := case when tg_op = 'INSERT' then now() else null end;
    new.rejeitado_em := null;
    new.motivo_devolucao := null;
  end if;

  return new;
end;
$$;

create or replace function public.web_atualizar_apontamento_horas(
  p_apontamento_id uuid,
  p_dados jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;
  if not public.can('apontamentos', 'write', v_tenant_id) then
    raise exception 'Seu perfil não possui permissão para editar apontamentos.';
  end if;
  if not public.fn_usuario_pode_editar_apontamento(v_tenant_id, v_empresa_id, v_auth_uid, p_apontamento_id) then
    raise exception 'Antes da aprovação, somente o próprio colaborador pode alterar. Após a aprovação, somente Coordenação, Diretor ou Admin.';
  end if;

  update public.apontamentos_horas
  set data = coalesce(nullif(p_dados->>'data', '')::date, data),
      horas = case when p_dados ? 'horas' then nullif(p_dados->>'horas', '')::numeric else horas end,
      tipo_hora_id = case when p_dados ? 'tipo_hora_id' then nullif(p_dados->>'tipo_hora_id', '')::uuid else tipo_hora_id end,
      descricao = case when p_dados ? 'descricao' then nullif(p_dados->>'descricao', '') else descricao end,
      hora_entrada_1 = case when p_dados ? 'hora_entrada_1' then nullif(p_dados->>'hora_entrada_1', '')::time else hora_entrada_1 end,
      hora_saida_1 = case when p_dados ? 'hora_saida_1' then nullif(p_dados->>'hora_saida_1', '')::time else hora_saida_1 end,
      hora_entrada_2 = case when p_dados ? 'hora_entrada_2' then nullif(p_dados->>'hora_entrada_2', '')::time else hora_entrada_2 end,
      hora_saida_2 = case when p_dados ? 'hora_saida_2' then nullif(p_dados->>'hora_saida_2', '')::time else hora_saida_2 end
  where id = p_apontamento_id
    and tenant_id = v_tenant_id
    and empresa_id = v_empresa_id
    and not coalesce(gerado_por_hh, false);

  if not found then
    raise exception 'Apontamento não encontrado, fora da empresa atual ou gerado por HH.';
  end if;
  return jsonb_build_object('sucesso', true);
end;
$$;

create or replace function public.app_editar_apontamento(
  p_apontamento_id uuid,
  p_horas numeric,
  p_tipo_hora_id uuid,
  p_descricao text default null,
  p_confirmar_avisos boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, a, c
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_os_id integer;
  v_colaborador_id uuid;
  v_data date;
  v_gerado_por_hh boolean;
  v_status text;
  v_status_aprovacao text;
  v_tipo_existe boolean;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Não foi possível identificar autenticação, tenant e empresa ativos.';
  end if;
  if not public.can('apontamentos', 'write', v_tenant_id) then
    raise exception 'Seu perfil não possui permissão para editar apontamentos.';
  end if;
  if p_horas is null or p_horas <= 0 or p_horas > 24 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'horas', 'mensagem', 'Informe uma quantidade de horas entre 0 e 24.')));
  end if;

  select apontamento.os_id, apontamento.colaborador_id, apontamento.data, apontamento.gerado_por_hh,
         apontamento.status::text, apontamento.status_aprovacao
    into v_os_id, v_colaborador_id, v_data, v_gerado_por_hh, v_status, v_status_aprovacao
  from public.apontamentos_horas as apontamento
  where apontamento.id = p_apontamento_id
    and apontamento.tenant_id = v_tenant_id
    and apontamento.empresa_id = v_empresa_id;

  if not found then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'apontamento', 'mensagem', 'O apontamento informado não existe ou não pertence à empresa atual.')));
  end if;
  if coalesce(v_gerado_por_hh, false) then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'hh', 'mensagem', 'Este apontamento é um espelho de HH e deve ser alterado no módulo HH.')));
  end if;
  if lower(coalesce(v_status, '')) = 'fechado' then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'status', 'mensagem', 'Este apontamento está fechado e não pode ser alterado.')));
  end if;
  if not public.fn_usuario_pode_editar_apontamento(v_tenant_id, v_empresa_id, v_auth_uid, p_apontamento_id) then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'permissao',
        'mensagem', case
          when v_status_aprovacao = 'aprovado' then 'Após a aprovação, somente Coordenação, Diretor ou Admin pode alterar.'
          else 'Antes da aprovação, somente o próprio colaborador pode alterar.'
        end
      )));
  end if;

  select exists (
    select 1
    from public.tipos_horas as tipo
    where tipo.id = p_tipo_hora_id
      and tipo.tenant_id = v_tenant_id
      and tipo.ativo
  ) into v_tipo_existe;
  if not v_tipo_existe then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'tipo_hora', 'mensagem', 'O tipo de hora informado não existe ou está inativo.')));
  end if;
  if exists (
    select 1
    from public.apontamentos_horas as apontamento
    where apontamento.id <> p_apontamento_id
      and apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
      and apontamento.os_id = v_os_id
      and apontamento.colaborador_id = v_colaborador_id
      and apontamento.data = v_data
      and apontamento.tipo_hora_id = p_tipo_hora_id
      and not coalesce(apontamento.gerado_por_hh, false)
  ) then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'duplicidade', 'mensagem', 'Já existe outro apontamento para esta OS, colaborador, data e tipo de hora.')));
  end if;

  update public.apontamentos_horas
  set horas = p_horas,
      tipo_hora_id = p_tipo_hora_id,
      descricao = nullif(btrim(p_descricao), '')
  where id = p_apontamento_id
    and tenant_id = v_tenant_id
    and empresa_id = v_empresa_id;

  return jsonb_build_object('sucesso', true, 'gravados', 1, 'avisos', '[]'::jsonb, 'erros', '[]'::jsonb);
end;
$$;

revoke all on function public.web_atualizar_apontamento_horas(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.web_atualizar_apontamento_horas(uuid, jsonb)
  to authenticated;

revoke all on function public.app_editar_apontamento(uuid, numeric, uuid, text, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.app_editar_apontamento(uuid, numeric, uuid, text, boolean)
  to authenticated;

comment on function public.fn_usuario_pode_editar_apontamento(uuid, uuid, uuid, uuid) is
  'Regra central: antes da aprovação edita o próprio colaborador; aprovado edita Coordenação, Diretor ou Admin.';

notify pgrst, 'reload schema';

commit;
