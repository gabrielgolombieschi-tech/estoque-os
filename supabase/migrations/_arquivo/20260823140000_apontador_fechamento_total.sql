begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- APONTADOR deixa de possuir matriz declarativa. O aplicativo movel tera
-- superficie exclusiva via RPC security definer em rodada posterior.
delete from public.role_access_rules ar
using public.roles r
where r.id = ar.role_id
  and r.name = 'APONTADOR';

delete from public.role_permissions
where role = 'apontador';

-- A guarda em get_full_permissions sai antes da base herdada do tenant.
do $patch_get_full_permissions_apontador_vazio$
declare
  v_definition text;
  v_needle text := $needle$
  if upper(coalesce(v_empresa_papel, '')) = 'APONTADOR' then
    return jsonb_build_object(
      'os.read', true,
      'apontamentos.read', true,
      'apontamentos.write', true,
      'colaboradores.read', true,
      'tipos_horas.read', true
    );
  end if;
$needle$;
  v_replacement text := $replacement$
  if upper(coalesce(v_empresa_papel, '')) = 'APONTADOR' then
    return '{}'::jsonb;
  end if;
$replacement$;
begin
  select pg_get_functiondef('public.get_full_permissions_unscoped_20260810(uuid,uuid)'::regprocedure)
    into v_definition;

  if position(v_needle in v_definition) = 0 then
    raise exception 'apontador_empty_get_full_permissions_patch_token_not_found';
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$patch_get_full_permissions_apontador_vazio$;

-- A guarda do can unscoped deixa de permitir qualquer par recurso/acao.
do $patch_can_unscoped_apontador_vazio$
declare
  v_definition text;
  v_needle text := $needle$
  if v_papel_empresa = 'APONTADOR' then
    return (p_resource, p_action) in (
      values
        ('os', 'read'),
        ('apontamentos', 'read'),
        ('apontamentos', 'write'),
        ('colaboradores', 'read'),
        ('tipos_horas', 'read')
    );
  end if;
$needle$;
  v_replacement text := $replacement$
  if v_papel_empresa = 'APONTADOR' then
    return false;
  end if;
$replacement$;
begin
  select pg_get_functiondef('public.can_unscoped_20260810(text,text,uuid)'::regprocedure)
    into v_definition;

  if position(v_needle in v_definition) = 0 then
    raise exception 'apontador_empty_can_unscoped_patch_token_not_found';
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$patch_can_unscoped_apontador_vazio$;

-- O can publico possui excecoes antes de chamar can_unscoped. A guarda extra
-- fecha tambem essas excecoes sem alterar o fluxo dos demais papeis.
do $patch_can_apontador_vazio$
declare
  v_definition text;
  v_needle text := $needle$
  if auth.uid() is null or p_tenant_id is null then
    return false;
  end if;

  -- Usuario e qualquer alias equivalente permanecem exclusivos de OWNER/ADMIN.
$needle$;
  v_replacement text := $replacement$
  if auth.uid() is null or p_tenant_id is null then
    return false;
  end if;

  v_empresa_id := public.current_empresa_id__by_tenant(p_tenant_id);
  v_empresa_papel := a.fn_current_empresa_papel(p_tenant_id, v_empresa_id);
  if upper(coalesce(v_empresa_papel, '')) = 'APONTADOR' then
    return false;
  end if;

  -- Usuario e qualquer alias equivalente permanecem exclusivos de OWNER/ADMIN.
$replacement$;
begin
  select pg_get_functiondef('public.can(text,text,uuid)'::regprocedure)
    into v_definition;

  if position(v_needle in v_definition) = 0 then
    raise exception 'apontador_empty_can_patch_token_not_found';
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$patch_can_apontador_vazio$;

-- A versao legada precisa sair antes de admin_can_manage_users, can() e
-- role_access_rules para nenhum caminho reabrir uma capability.
do $patch_can_legacy_apontador_vazio$
declare
  v_definition text;
  v_needle text := $needle$
  v_empresa_id := public.current_empresa_id__by_tenant(v_tenant_id);

  if p_resource = 'admin' and p_action = 'manage_users' then
$needle$;
  v_replacement text := $replacement$
  v_empresa_id := public.current_empresa_id__by_tenant(v_tenant_id);

  select upper(coalesce(ue.papel, ''))
    into v_papel_empresa
  from a.usuario u
  join a.usuario_tenant ut on ut.usuario_id = u.id
  join a.usuario_empresa ue on ue.usuario_id = u.id
  where u.auth_user_id = auth.uid()
    and u.ativo is true
    and u.deleted_at is null
    and ut.tenant_id = v_tenant_id
    and ut.ativo is true
    and ut.deleted_at is null
    and ue.empresa_id = v_empresa_id
    and ue.ativo is true
    and ue.deleted_at is null
  limit 1;

  if v_papel_empresa = 'APONTADOR' then
    return false;
  end if;

  if p_resource = 'admin' and p_action = 'manage_users' then
$replacement$;
begin
  select pg_get_functiondef('public.can__legacy_40734(text,text)'::regprocedure)
    into v_definition;

  if position(v_needle in v_definition) = 0 then
    raise exception 'apontador_empty_can_legacy_patch_token_not_found';
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$patch_can_legacy_apontador_vazio$;

-- A projeção para as memberships antigas e propositalmente interrompida para
-- APONTADOR. O bloco vem antes de toda inserção/atualização legada; os outros
-- papeis seguem pelo corpo original sem qualquer mudança.
do $patch_sync_projection_apontador$
declare
  v_definition text;
  v_needle text := $needle$
  if v_auth_user_id is null then
    return;
  end if;

  if exists (
$needle$;
  v_replacement text := $replacement$
  if v_auth_user_id is null then
    return;
  end if;

  if exists (
    select 1
    from a.usuario u
    join a.usuario_tenant ut on ut.usuario_id = u.id
    join a.usuario_empresa ue on ue.usuario_id = u.id
    join c.empresa ce on ce.id = ue.empresa_id
    where u.id = p_usuario_id
      and u.ativo is true
      and u.deleted_at is null
      and ut.tenant_id = ce.tenant_id
      and ut.ativo is true
      and ut.deleted_at is null
      and ue.ativo is true
      and ue.deleted_at is null
      and upper(ue.papel) = 'APONTADOR'
  ) then
    delete from public.tenant_memberships tm
    where tm.user_id = v_auth_user_id;

    delete from public.empresa_memberships em
    where em.user_id = v_auth_user_id;

    delete from public.user_tenant_context utc
    where utc.user_id = v_auth_user_id;

    delete from public.user_empresa_context uec
    where uec.user_id = v_auth_user_id;

    return;
  end if;

  if exists (
$replacement$;
begin
  select pg_get_functiondef('a.sync_usuario_access_projection(uuid)'::regprocedure)
    into v_definition;

  if position(v_needle in v_definition) = 0 then
    raise exception 'apontador_sync_projection_patch_token_not_found';
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$patch_sync_projection_apontador$;

-- Caso algum APONTADOR tenha sido criado antes desta migration, remove toda
-- projeção legada residual agora. Nao existe nenhum no estado atual.
delete from public.tenant_memberships tm
where exists (
  select 1
  from a.usuario u
  join a.usuario_empresa ue on ue.usuario_id = u.id
  where u.auth_user_id = tm.user_id
    and u.ativo is true
    and u.deleted_at is null
    and ue.ativo is true
    and ue.deleted_at is null
    and upper(ue.papel) = 'APONTADOR'
);

delete from public.empresa_memberships em
where exists (
  select 1
  from a.usuario u
  join a.usuario_empresa ue on ue.usuario_id = u.id
  where u.auth_user_id = em.user_id
    and u.ativo is true
    and u.deleted_at is null
    and ue.ativo is true
    and ue.deleted_at is null
    and upper(ue.papel) = 'APONTADOR'
);

do $apontador_fechamento_assertions$
declare
  v_permissions jsonb;
begin
  select jsonb_object_agg(permission, true)
    into v_permissions
  from public.role_permissions
  where role = 'apontador';

  if coalesce(v_permissions, '{}'::jsonb) <> '{}'::jsonb then
    raise exception 'apontador_permission_matrix_not_empty';
  end if;

  if exists (
    select 1
    from public.role_access_rules ar
    join public.roles r on r.id = ar.role_id
    where r.name = 'APONTADOR'
  ) then
    raise exception 'apontador_legacy_access_rules_not_empty';
  end if;

  if exists (
    select 1
    from a.usuario_empresa ue
    where ue.ativo is true
      and ue.deleted_at is null
      and upper(ue.papel) = 'APONTADOR'
  ) then
    raise exception 'apontador_user_exists_before_rls_round';
  end if;

  if position($needle$return '{}'::jsonb;$needle$
      in pg_get_functiondef('public.get_full_permissions_unscoped_20260810(uuid,uuid)'::regprocedure)) = 0
     or position($needle$if v_papel_empresa = 'APONTADOR' then
    return false;$needle$
      in pg_get_functiondef('public.can_unscoped_20260810(text,text,uuid)'::regprocedure)) = 0
     or position($needle$if v_papel_empresa = 'APONTADOR' then
    return false;$needle$
      in pg_get_functiondef('public.can__legacy_40734(text,text)'::regprocedure)) = 0
     or position($needle$delete from public.tenant_memberships tm
    where tm.user_id = v_auth_user_id;$needle$
      in pg_get_functiondef('a.sync_usuario_access_projection(uuid)'::regprocedure)) = 0 then
    raise exception 'apontador_guard_not_fully_installed';
  end if;
end;
$apontador_fechamento_assertions$;

notify pgrst, 'reload schema';

commit;
