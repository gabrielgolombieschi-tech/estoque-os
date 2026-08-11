begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- DIRETOR e um papel canonico distinto, mas herda o role operacional admin.
-- O CHECK novo e validado antes de substituir o anterior.
alter table a.usuario_tenant
  add constraint ck_usuario_tenant__papel_v2
  check (papel = any (array['OWNER','ADMIN','DIRETOR','CONTADOR','GESTOR']::text[]))
  not valid;

alter table a.usuario_tenant
  validate constraint ck_usuario_tenant__papel_v2;

alter table a.usuario_tenant
  drop constraint ck_usuario_tenant__papel;

alter table a.usuario_tenant
  rename constraint ck_usuario_tenant__papel_v2 to ck_usuario_tenant__papel;

create or replace function a.fn_map_papel_tenant(p text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when p is null then 'GESTOR'
    when upper(p) in ('OWNER','ADMIN','DIRETOR','CONTADOR','GESTOR') then upper(p)
    when upper(p) in (
      'FINANCEIRO','COMPRAS','ALMOXARIFADO','TECNICO',
      'COORDENACAO','APONTAMENTO_RH','PAINEL_TV'
    ) then 'GESTOR'
    else 'GESTOR'
  end;
$$;

create or replace function a.fn_map_papel_tenant_to_role(p_papel text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case upper(coalesce(p_papel, ''))
    when 'OWNER' then 'admin'
    when 'ADMIN' then 'admin'
    when 'DIRETOR' then 'admin'
    when 'CONTADOR' then 'fiscal'
    when 'GESTOR' then 'projetos'
    when 'FINANCEIRO' then 'financeiro'
    else 'estoque'
  end;
$$;

create or replace function a.fn_map_papel_empresa(p text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when p is null then 'ADMIN'
    when upper(p) in (
      'ADMIN','FINANCEIRO','FATURAMENTO','COORDENACAO','COMPRAS','ALMOXARIFADO',
      'TECNICO','APONTAMENTO_RH','PAINEL_TV'
    ) then upper(p)
    when upper(p) in ('OWNER','DIRETOR','CONTADOR','GESTOR') then 'ADMIN'
    else 'ADMIN'
  end;
$$;

-- Helpers usados em RLS precisam considerar tambem o estado global do usuario
-- e do tenant; apenas ampliar a lista antiga deixaria usuario inativo passar.
create or replace function a.fn_is_tenant_admin(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select public.has_active_tenant_access(p_tenant_id)
    and exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut on ut.usuario_id = u.id
      join public.tenants t on t.id = ut.tenant_id
      where u.auth_user_id = auth.uid()
        and u.ativo is true
        and u.deleted_at is null
        and ut.tenant_id = p_tenant_id
        and ut.ativo is true
        and ut.deleted_at is null
        and ut.papel in ('OWNER','ADMIN','DIRETOR')
        and t.ativo is true
    );
$$;

create or replace function a.fn_is_admin_of_same_tenant(p_other_usuario_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select exists (
    select 1
    from a.usuario me
    join a.usuario_tenant ut_me on ut_me.usuario_id = me.id
    join a.usuario_tenant ut_other
      on ut_other.tenant_id = ut_me.tenant_id
     and ut_other.usuario_id = p_other_usuario_id
    join public.tenants t on t.id = ut_me.tenant_id
    where me.auth_user_id = auth.uid()
      and me.ativo is true
      and me.deleted_at is null
      and ut_me.ativo is true
      and ut_me.deleted_at is null
      and ut_me.papel in ('OWNER','ADMIN','DIRETOR')
      and ut_other.ativo is true
      and ut_other.deleted_at is null
      and t.ativo is true
  );
$$;

-- Somente estes gates possuem listas literais de papel e representam acesso
-- efetivo. A lista e fechada para nao alterar fallbacks de auditoria OWNER-only.
do $diretor_gate_patch$
declare
  v_signature regprocedure;
  v_definition text;
  v_patched text;
begin
  foreach v_signature in array array[
    'public.can_unscoped_20260810(text,text,uuid)'::regprocedure,
    'public.can__legacy_56548(text,text,uuid)'::regprocedure,
    'c.has_comercial_access_unscoped_20260810(uuid,uuid)'::regprocedure,
    'c.has_compras_access_unscoped_20260810(uuid,uuid)'::regprocedure,
    'c.has_imobilizado_access_unscoped_20260810(uuid,uuid)'::regprocedure,
    'f.has_finance_access_unscoped_20260810(uuid,uuid)'::regprocedure,
    'public.set_fornecedor_import_defaults(integer,public.item_finalidade,uuid)'::regprocedure
  ]
  loop
    select pg_get_functiondef(v_signature) into v_definition;
    v_patched := v_definition;

    v_patched := replace(
      v_patched,
      '(''OWNER'',''ADMIN'',''GESTOR'')',
      '(''OWNER'',''ADMIN'',''DIRETOR'',''GESTOR'')'
    );
    v_patched := replace(
      v_patched,
      '(''OWNER'', ''ADMIN'', ''GESTOR'')',
      '(''OWNER'', ''ADMIN'', ''DIRETOR'', ''GESTOR'')'
    );
    v_patched := replace(
      v_patched,
      '(''OWNER'',''ADMIN'')',
      '(''OWNER'',''ADMIN'',''DIRETOR'')'
    );
    v_patched := replace(
      v_patched,
      '(''OWNER'', ''ADMIN'')',
      '(''OWNER'', ''ADMIN'', ''DIRETOR'')'
    );
    v_patched := replace(
      v_patched,
      '(''ADMIN'',''OWNER'')',
      '(''ADMIN'',''DIRETOR'',''OWNER'')'
    );
    v_patched := replace(
      v_patched,
      '(''ADMIN'', ''OWNER'')',
      '(''ADMIN'', ''DIRETOR'', ''OWNER'')'
    );

    if v_patched = v_definition then
      raise exception 'diretor_gate_token_not_found: %', v_signature;
    end if;

    execute v_patched;
  end loop;
end;
$diretor_gate_patch$;

-- Diversas policies antigas ainda chamam este ABI de dois argumentos. Ele
-- passa primeiro pela fronteira canonica e pelo can() atual, mas preserva as
-- regras legadas para usuarios que ainda possuem membership_roles.
create or replace function public.can__legacy_40734(
  p_resource text,
  p_action text
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid;
begin
  if v_tenant_id is null then
    return false;
  end if;

  v_empresa_id := public.current_empresa_id__by_tenant(v_tenant_id);

  if p_resource = 'admin' and p_action = 'manage_users' then
    return public.admin_can_manage_users(v_tenant_id);
  end if;

  if not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    return false;
  end if;

  if public.can(p_resource, p_action, v_tenant_id) then
    return true;
  end if;

  if p_resource = 'os'
     and p_action in ('read','write')
     and exists (
       select 1
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
         and upper(ue.papel) in ('ADMIN','COORDENACAO','APONTAMENTO_RH')
     ) then
    return true;
  end if;

  return exists (
    select 1
    from public.tenant_memberships tm
    join public.membership_roles mr on mr.membership_id = tm.id
    join public.roles r on r.id = mr.role_id
    join public.role_access_rules ar on ar.role_id = r.id
    where tm.user_id = auth.uid()
      and tm.tenant_id = v_tenant_id
      and tm.status in ('active', 'ativo')
      and (r.tenant_id is null or r.tenant_id = tm.tenant_id)
      and ar.resource = p_resource
      and ar.action = p_action
  );
end;
$$;

revoke all on function public.can__legacy_40734(text, text) from public, anon;
grant execute on function public.can__legacy_40734(text, text) to authenticated, service_role;

create or replace function a.fn_tenant_role_rank(p_papel text)
returns integer
language sql
immutable
set search_path = pg_catalog
as $$
  select case upper(trim(coalesce(p_papel, '')))
    when 'OWNER' then 400
    when 'ADMIN' then 300
    when 'DIRETOR' then 200
    when 'CONTADOR' then 100
    when 'GESTOR' then 100
    else -1
  end;
$$;

create or replace function public.admin_can_manage_users(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select public.has_active_tenant_access(p_tenant_id)
    and exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut on ut.usuario_id = u.id
      where u.auth_user_id = auth.uid()
        and u.ativo is true
        and u.deleted_at is null
        and ut.tenant_id = p_tenant_id
        and ut.papel in ('OWNER','ADMIN','DIRETOR')
        and ut.ativo is true
        and ut.deleted_at is null
    );
$$;

create or replace function a.fn_admin_can_manage_target(
  p_tenant_id uuid,
  p_target_usuario_id uuid,
  p_requested_role text,
  p_require_target boolean
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_actor_role text;
  v_target_role text;
  v_requested_role text := case
    when p_requested_role is null then null
    else upper(trim(p_requested_role))
  end;
begin
  if not public.has_active_tenant_access(p_tenant_id) then
    return false;
  end if;

  select upper(trim(ut.papel))
    into v_actor_role
  from a.usuario u
  join a.usuario_tenant ut on ut.usuario_id = u.id
  where u.auth_user_id = auth.uid()
    and u.ativo is true
    and u.deleted_at is null
    and ut.tenant_id = p_tenant_id
    and ut.ativo is true
    and ut.deleted_at is null
  limit 1;

  if v_actor_role is null or v_actor_role not in ('OWNER','ADMIN','DIRETOR') then
    return false;
  end if;

  if v_requested_role is not null
     and v_requested_role not in ('OWNER','ADMIN','DIRETOR','CONTADOR','GESTOR') then
    return false;
  end if;

  if p_target_usuario_id is not null then
    select upper(trim(ut.papel))
      into v_target_role
    from a.usuario_tenant ut
    where ut.usuario_id = p_target_usuario_id
      and ut.tenant_id = p_tenant_id
      and ut.deleted_at is null
    limit 1;
  end if;

  if p_require_target and v_target_role is null then
    return false;
  end if;

  if v_actor_role = 'OWNER' then
    return true;
  end if;

  if v_actor_role = 'ADMIN' then
    return coalesce(v_target_role <> 'OWNER', true)
       and coalesce(v_requested_role <> 'OWNER', true);
  end if;

  -- DIRETOR fica abaixo de ADMIN e nao administra pares.
  return coalesce(v_target_role in ('CONTADOR','GESTOR'), true)
     and coalesce(v_requested_role in ('CONTADOR','GESTOR'), true);
end;
$$;

create or replace function a.assert_admin_hierarchy_locked(
  p_tenant_id uuid,
  p_target_usuario_id uuid,
  p_requested_role text,
  p_require_target boolean
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  perform 1
  from public.tenants t
  where t.id = p_tenant_id
    and t.ativo is true
  for update;
  if not found then
    raise exception 'tenant_not_found_or_inactive';
  end if;

  if p_target_usuario_id is not null then
    perform 1
    from a.usuario u
    where u.id = p_target_usuario_id
      and u.deleted_at is null
    for update;
  end if;

  perform 1
  from a.usuario_tenant ut
  where ut.usuario_id = p_target_usuario_id
    and ut.tenant_id = p_tenant_id
    and ut.deleted_at is null
  for update;

  if not a.fn_admin_can_manage_target(
    p_tenant_id,
    p_target_usuario_id,
    p_requested_role,
    p_require_target
  ) then
    raise exception 'role_hierarchy_violation';
  end if;
end;
$$;

create or replace function a.assert_global_user_active_scope(
  p_tenant_id uuid,
  p_target_usuario_id uuid,
  p_requested_active boolean
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_current_active boolean;
begin
  if p_target_usuario_id is null or p_requested_active is null then
    return;
  end if;

  select u.ativo
    into v_current_active
  from a.usuario u
  where u.id = p_target_usuario_id
    and u.deleted_at is null;

  if not found or v_current_active is not distinct from p_requested_active then
    return;
  end if;

  if exists (
    select 1
    from a.usuario_tenant ut
    join public.tenants t on t.id = ut.tenant_id
    where ut.usuario_id = p_target_usuario_id
      and ut.tenant_id <> p_tenant_id
      and ut.ativo is true
      and ut.deleted_at is null
      and t.ativo is true
  ) then
    raise exception 'global_user_shared_across_tenants';
  end if;
end;
$$;

revoke all on function a.fn_tenant_role_rank(text) from public, anon, authenticated;
revoke all on function a.fn_admin_can_manage_target(uuid, uuid, text, boolean) from public, anon, authenticated, service_role;
revoke all on function a.assert_admin_hierarchy_locked(uuid, uuid, text, boolean) from public, anon, authenticated, service_role;
revoke all on function a.assert_global_user_active_scope(uuid, uuid, boolean) from public, anon, authenticated, service_role;

revoke all on function public.admin_can_manage_users(uuid) from public, anon;
grant execute on function public.admin_can_manage_users(uuid) to authenticated, service_role;

create or replace function public.admin_can_assign_tenant_role(
  p_tenant_id uuid,
  p_requested_role text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select a.fn_admin_can_manage_target(
    p_tenant_id,
    null,
    p_requested_role,
    false
  );
$$;

create or replace function public.admin_can_manage_auth_user(
  p_tenant_id uuid,
  p_target_auth_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select coalesce((
    select a.fn_admin_can_manage_target(p_tenant_id, u.id, null, true)
    from a.usuario u
    where u.auth_user_id = p_target_auth_user_id
      and u.deleted_at is null
    limit 1
  ), false);
$$;

create or replace function public.admin_can_manage_invited_user(
  p_tenant_id uuid,
  p_target_auth_user_id uuid,
  p_requested_role text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select a.fn_admin_can_manage_target(
    p_tenant_id,
    (
      select u.id
      from a.usuario u
      where u.auth_user_id = p_target_auth_user_id
        and u.deleted_at is null
      limit 1
    ),
    p_requested_role,
    false
  );
$$;

revoke all on function public.admin_can_assign_tenant_role(uuid, text) from public, anon;
revoke all on function public.admin_can_manage_auth_user(uuid, uuid) from public, anon;
revoke all on function public.admin_can_manage_invited_user(uuid, uuid, text) from public, anon;
grant execute on function public.admin_can_assign_tenant_role(uuid, text) to authenticated, service_role;
grant execute on function public.admin_can_manage_auth_user(uuid, uuid) to authenticated, service_role;
grant execute on function public.admin_can_manage_invited_user(uuid, uuid, text) to authenticated, service_role;

-- As implementacoes atuais continuam sendo usadas, mas ficam internas. Antes
-- de renomear, ampliamos somente a validacao de papel para aceitar DIRETOR.
do $diretor_admin_validation_patch$
declare
  v_signature regprocedure;
  v_definition text;
  v_patched text;
  v_token constant text := '(''OWNER'',''ADMIN'',''CONTADOR'',''GESTOR'')';
begin
  foreach v_signature in array array[
    'public.admin_save_user_access(uuid,uuid,text,text,boolean,text,boolean,jsonb)'::regprocedure,
    'public.admin_finalize_invited_user(uuid,uuid,text,text,text,text,jsonb)'::regprocedure,
    'public.admin_set_user_tenant_role(uuid,uuid,text,boolean)'::regprocedure
  ]
  loop
    select pg_get_functiondef(v_signature) into v_definition;
    if position(v_token in v_definition) = 0 then
      raise exception 'diretor_admin_validation_token_not_found: %', v_signature;
    end if;

    v_patched := replace(
      v_definition,
      v_token,
      '(''OWNER'',''ADMIN'',''DIRETOR'',''CONTADOR'',''GESTOR'')'
    );
    execute v_patched;
  end loop;
end;
$diretor_admin_validation_patch$;

alter function public.admin_save_user_access(uuid, uuid, text, text, boolean, text, boolean, jsonb)
  rename to admin_save_user_access_impl_20260811;
alter function public.admin_finalize_invited_user(uuid, uuid, text, text, text, text, jsonb)
  rename to admin_finalize_invited_user_impl_20260811;
alter function public.admin_update_user(uuid, uuid, text, text, boolean)
  rename to admin_update_user_impl_20260811;
alter function public.admin_set_user_tenant_role(uuid, uuid, text, boolean)
  rename to admin_set_user_tenant_role_impl_20260811;
alter function public.admin_set_user_empresa(uuid, uuid, uuid, text, boolean)
  rename to admin_set_user_empresa_impl_20260811;

revoke all on function public.admin_save_user_access_impl_20260811(uuid, uuid, text, text, boolean, text, boolean, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.admin_finalize_invited_user_impl_20260811(uuid, uuid, text, text, text, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.admin_update_user_impl_20260811(uuid, uuid, text, text, boolean)
  from public, anon, authenticated, service_role;
revoke all on function public.admin_set_user_tenant_role_impl_20260811(uuid, uuid, text, boolean)
  from public, anon, authenticated, service_role;
revoke all on function public.admin_set_user_empresa_impl_20260811(uuid, uuid, uuid, text, boolean)
  from public, anon, authenticated, service_role;

create function public.admin_save_user_access(
  p_tenant_id uuid,
  p_usuario_id uuid,
  p_nome text,
  p_telefone text,
  p_usuario_ativo boolean,
  p_tenant_papel text,
  p_tenant_ativo boolean,
  p_empresa_vinculos jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  perform a.assert_admin_hierarchy_locked(
    p_tenant_id,
    p_usuario_id,
    p_tenant_papel,
    true
  );
  perform a.assert_global_user_active_scope(
    p_tenant_id,
    p_usuario_id,
    p_usuario_ativo
  );
  perform public.admin_save_user_access_impl_20260811(
    p_tenant_id,
    p_usuario_id,
    p_nome,
    p_telefone,
    p_usuario_ativo,
    p_tenant_papel,
    p_tenant_ativo,
    p_empresa_vinculos
  );
end;
$$;

create function public.admin_finalize_invited_user(
  p_tenant_id uuid,
  p_auth_user_id uuid,
  p_email text,
  p_nome text,
  p_telefone text,
  p_tenant_papel text,
  p_empresa_vinculos jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_usuario_id uuid;
  v_result uuid;
begin
  perform 1
  from public.tenants t
  where t.id = p_tenant_id
    and t.ativo is true
  for update;
  if not found then
    raise exception 'tenant_not_found_or_inactive';
  end if;

  select u.id
    into v_usuario_id
  from a.usuario u
  where u.auth_user_id = p_auth_user_id
    and u.deleted_at is null
  for update;

  perform a.assert_admin_hierarchy_locked(
    p_tenant_id,
    v_usuario_id,
    p_tenant_papel,
    false
  );
  perform a.assert_global_user_active_scope(
    p_tenant_id,
    v_usuario_id,
    true
  );

  v_result := public.admin_finalize_invited_user_impl_20260811(
    p_tenant_id,
    p_auth_user_id,
    p_email,
    p_nome,
    p_telefone,
    p_tenant_papel,
    p_empresa_vinculos
  );
  return v_result;
end;
$$;

create function public.admin_update_user(
  p_tenant_id uuid,
  p_usuario_id uuid,
  p_nome text,
  p_telefone text,
  p_ativo boolean
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  perform a.assert_admin_hierarchy_locked(p_tenant_id, p_usuario_id, null, true);
  perform a.assert_global_user_active_scope(p_tenant_id, p_usuario_id, p_ativo);
  perform public.admin_update_user_impl_20260811(
    p_tenant_id,
    p_usuario_id,
    p_nome,
    p_telefone,
    p_ativo
  );
end;
$$;

create function public.admin_set_user_tenant_role(
  p_tenant_id uuid,
  p_usuario_id uuid,
  p_papel text,
  p_ativo boolean
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  perform a.assert_admin_hierarchy_locked(p_tenant_id, p_usuario_id, p_papel, true);
  perform public.admin_set_user_tenant_role_impl_20260811(
    p_tenant_id,
    p_usuario_id,
    p_papel,
    p_ativo
  );
end;
$$;

create function public.admin_set_user_empresa(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_usuario_id uuid,
  p_papel text,
  p_ativo boolean
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  perform a.assert_admin_hierarchy_locked(p_tenant_id, p_usuario_id, null, true);
  perform public.admin_set_user_empresa_impl_20260811(
    p_tenant_id,
    p_empresa_id,
    p_usuario_id,
    p_papel,
    p_ativo
  );
end;
$$;

revoke all on function public.admin_save_user_access(uuid, uuid, text, text, boolean, text, boolean, jsonb)
  from public, anon;
revoke all on function public.admin_finalize_invited_user(uuid, uuid, text, text, text, text, jsonb)
  from public, anon;
revoke all on function public.admin_update_user(uuid, uuid, text, text, boolean)
  from public, anon;
revoke all on function public.admin_set_user_tenant_role(uuid, uuid, text, boolean)
  from public, anon;
revoke all on function public.admin_set_user_empresa(uuid, uuid, uuid, text, boolean)
  from public, anon;

grant execute on function public.admin_save_user_access(uuid, uuid, text, text, boolean, text, boolean, jsonb)
  to authenticated, service_role;
grant execute on function public.admin_finalize_invited_user(uuid, uuid, text, text, text, text, jsonb)
  to authenticated, service_role;
grant execute on function public.admin_update_user(uuid, uuid, text, text, boolean)
  to authenticated, service_role;
grant execute on function public.admin_set_user_tenant_role(uuid, uuid, text, boolean)
  to authenticated, service_role;
grant execute on function public.admin_set_user_empresa(uuid, uuid, uuid, text, boolean)
  to authenticated, service_role;

-- Bloqueia mutacao direta da identidade e da hierarquia. Os fluxos publicados
-- ja usam as RPCs acima. usuario_empresa mantem INSERT/UPDATE por compatibilidade,
-- mas recebe uma barreira de hierarquia no trigger a seguir.
revoke insert, update, delete on table a.usuario from public, anon, authenticated;
revoke insert, update, delete on table a.usuario_tenant from public, anon, authenticated;
revoke delete on table a.usuario_empresa from public, anon, authenticated;

create or replace function a.trg_guard_usuario_empresa_hierarchy()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_tenant_id uuid;
  v_old_tenant_id uuid;
  v_target_usuario_id uuid;
begin
  if auth.uid() is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'UPDATE'
     and (
       old.usuario_id is distinct from new.usuario_id
       or old.empresa_id is distinct from new.empresa_id
     ) then
    select e.tenant_id
      into v_old_tenant_id
    from c.empresa e
    where e.id = old.empresa_id
      and e.deleted_at is null;

    if v_old_tenant_id is null
       or not a.fn_admin_can_manage_target(
         v_old_tenant_id,
         old.usuario_id,
         null,
         true
       ) then
      raise exception 'role_hierarchy_violation';
    end if;
  end if;

  v_target_usuario_id := case when tg_op = 'DELETE' then old.usuario_id else new.usuario_id end;

  select e.tenant_id
    into v_tenant_id
  from c.empresa e
  where e.id = case when tg_op = 'DELETE' then old.empresa_id else new.empresa_id end
    and e.deleted_at is null;

  if v_tenant_id is null
     or not a.fn_admin_can_manage_target(
       v_tenant_id,
       v_target_usuario_id,
       null,
       true
     ) then
    raise exception 'role_hierarchy_violation';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists trg_guard_usuario_empresa_hierarchy on a.usuario_empresa;
create trigger trg_guard_usuario_empresa_hierarchy
before insert or update or delete on a.usuario_empresa
for each row execute function a.trg_guard_usuario_empresa_hierarchy();

revoke all on function a.trg_guard_usuario_empresa_hierarchy() from public, anon, authenticated;

-- A matriz de autorizacao nao faz parte do acesso operacional de DIRETOR.
revoke insert, update, delete, truncate, references, trigger
  on table public.permissions,
           public.role_permissions,
           public.membership_roles,
           public.role_access_rules,
           public.roles
  from public, anon, authenticated;

grant all
  on table public.permissions,
           public.role_permissions,
           public.membership_roles,
           public.role_access_rules,
           public.roles
  to service_role;

do $diretor_assertions$
declare
  v_constraint text;
  v_signature regprocedure;
begin
  select pg_get_constraintdef(c.oid)
    into v_constraint
  from pg_constraint c
  where c.conrelid = 'a.usuario_tenant'::regclass
    and c.conname = 'ck_usuario_tenant__papel'
    and c.contype = 'c';

  if v_constraint is null or position('DIRETOR' in v_constraint) = 0 then
    raise exception 'diretor_constraint_not_installed';
  end if;

  if a.fn_map_papel_tenant('DIRETOR') <> 'DIRETOR'
     or a.fn_map_papel_tenant_to_role('DIRETOR') <> 'admin'
     or a.fn_map_papel_empresa('DIRETOR') <> 'ADMIN'
     or a.fn_map_papel_empresa('FATURAMENTO') <> 'FATURAMENTO' then
    raise exception 'diretor_role_mapping_invalid';
  end if;

  foreach v_signature in array array[
    'a.fn_is_admin_of_same_tenant(uuid)'::regprocedure,
    'a.fn_is_tenant_admin(uuid)'::regprocedure,
    'public.can_unscoped_20260810(text,text,uuid)'::regprocedure,
    'c.has_comercial_access_unscoped_20260810(uuid,uuid)'::regprocedure,
    'c.has_compras_access_unscoped_20260810(uuid,uuid)'::regprocedure,
    'c.has_imobilizado_access_unscoped_20260810(uuid,uuid)'::regprocedure,
    'f.has_finance_access_unscoped_20260810(uuid,uuid)'::regprocedure
  ]
  loop
    if position('DIRETOR' in pg_get_functiondef(v_signature)) = 0 then
      raise exception 'diretor_gate_not_installed: %', v_signature;
    end if;
  end loop;

  if has_function_privilege(
       'anon',
       'public.admin_save_user_access(uuid,uuid,text,text,boolean,text,boolean,jsonb)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.admin_save_user_access_impl_20260811(uuid,uuid,text,text,boolean,text,boolean,jsonb)',
       'execute'
     ) then
    raise exception 'diretor_admin_rpc_acl_invalid';
  end if;

  if has_table_privilege('authenticated', 'a.usuario', 'UPDATE')
     or has_table_privilege('authenticated', 'a.usuario_tenant', 'UPDATE')
     or has_table_privilege('authenticated', 'public.role_permissions', 'UPDATE')
     or has_table_privilege('authenticated', 'public.membership_roles', 'INSERT') then
    raise exception 'diretor_control_plane_acl_invalid';
  end if;
end;
$diretor_assertions$;

comment on function a.fn_tenant_role_rank(text) is
  'Hierarquia canonica: OWNER > ADMIN > DIRETOR > CONTADOR/GESTOR.';
comment on function public.admin_can_manage_users(uuid) is
  'Autoriza OWNER, ADMIN e DIRETOR ativos; mutacoes ainda respeitam a hierarquia canonica.';

notify pgrst, 'reload schema';

commit;
