begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- a.usuario e global. Uma administracao feita em um tenant nao pode alterar
-- perfil/status refletido em outro tenant ativo sem uma operacao global propria.
create or replace function a.assert_global_user_profile_scope(
  p_tenant_id uuid,
  p_target_usuario_id uuid,
  p_check_nome boolean,
  p_nome text,
  p_check_email boolean,
  p_email text,
  p_check_telefone boolean,
  p_telefone text,
  p_check_ativo boolean,
  p_ativo boolean
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_nome text;
  v_email text;
  v_telefone text;
  v_ativo boolean;
  v_deleted_at timestamptz;
  v_next_nome text;
  v_next_email text;
  v_next_telefone text;
  v_shared_elsewhere boolean;
begin
  if p_target_usuario_id is null then
    return;
  end if;

  select
    nullif(trim(coalesce(u.nome, '')), ''),
    nullif(lower(trim(coalesce(u.email, ''))), ''),
    nullif(regexp_replace(coalesce(u.telefone, ''), '\D', '', 'g'), ''),
    u.ativo,
    u.deleted_at
    into v_nome, v_email, v_telefone, v_ativo, v_deleted_at
  from a.usuario u
  where u.id = p_target_usuario_id;

  if not found then
    return;
  end if;

  v_shared_elsewhere := exists (
    select 1
    from a.usuario_tenant ut
    join public.tenants t on t.id = ut.tenant_id
    where ut.usuario_id = p_target_usuario_id
      and ut.tenant_id <> p_tenant_id
      and ut.ativo is true
      and ut.deleted_at is null
      and t.ativo is true
  );

  if not v_shared_elsewhere then
    return;
  end if;

  if v_deleted_at is not null then
    raise exception 'global_user_shared_across_tenants';
  end if;

  v_next_nome := nullif(trim(coalesce(p_nome, '')), '');
  v_next_email := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_next_telefone := nullif(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), '');

  if (p_check_nome and v_nome is distinct from v_next_nome)
     or (p_check_email and v_email is distinct from v_next_email)
     or (p_check_telefone and v_telefone is distinct from v_next_telefone)
     or (p_check_ativo and v_ativo is distinct from p_ativo) then
    raise exception 'global_user_shared_across_tenants';
  end if;
end;
$$;

revoke all on function a.assert_global_user_profile_scope(
  uuid, uuid, boolean, text, boolean, text, boolean, text, boolean, boolean
) from public, anon, authenticated, service_role;

create or replace function a.admin_upsert_auth_profile_locked(
  p_tenant_id uuid,
  p_target_auth_user_id uuid,
  p_nome text,
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
declare
  v_usuario_id uuid;
  v_usuario_deleted_at timestamptz;
  v_canonical_nome text;
  v_current_nome text;
  v_next_nome text := nullif(trim(coalesce(p_nome, '')), '');
  v_profile_exists boolean;
  v_shared_elsewhere boolean;
begin
  if p_target_auth_user_id is null or v_next_nome is null then
    raise exception 'invalid_user_payload';
  end if;

  perform 1
  from public.tenants t
  where t.id = p_tenant_id
    and t.ativo is true
  for update;
  if not found then
    raise exception 'tenant_not_found_or_inactive';
  end if;

  if auth.uid() is null
     or not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;

  perform 1
  from auth.users au
  where au.id = p_target_auth_user_id
  for update;
  if not found then
    raise exception 'auth_user_not_found';
  end if;

  select u.id, u.deleted_at, nullif(trim(coalesce(u.nome, '')), '')
    into v_usuario_id, v_usuario_deleted_at, v_canonical_nome
  from a.usuario u
  where u.auth_user_id = p_target_auth_user_id
  for update;

  if v_usuario_deleted_at is not null then
    raise exception 'canonical_user_deleted';
  end if;

  if not a.fn_admin_can_manage_target(
    p_tenant_id,
    v_usuario_id,
    p_requested_role,
    p_require_target
  ) then
    raise exception 'role_hierarchy_violation';
  end if;

  select nullif(trim(coalesce(up.nome, '')), '')
    into v_current_nome
  from public.user_profiles up
  where up.user_id = p_target_auth_user_id
  for update;
  v_profile_exists := found;

  v_shared_elsewhere := exists (
    select 1
    from a.usuario_tenant ut
    join public.tenants t on t.id = ut.tenant_id
    where ut.usuario_id = v_usuario_id
      and ut.tenant_id <> p_tenant_id
      and ut.ativo is true
      and ut.deleted_at is null
      and t.ativo is true
  ) or exists (
    select 1
    from public.tenant_memberships tm
    join public.tenants t on t.id = tm.tenant_id
    where tm.user_id = p_target_auth_user_id
      and tm.tenant_id <> p_tenant_id
      and tm.status in ('active', 'ativo')
      and t.ativo is true
  );

  if v_shared_elsewhere
     and (
       (
         v_profile_exists
         and v_current_nome is not null
         and v_current_nome is distinct from v_next_nome
       )
       or (
         (not v_profile_exists or v_current_nome is null)
         and (v_usuario_id is null or v_canonical_nome is distinct from v_next_nome)
       )
     ) then
    raise exception 'global_user_shared_across_tenants';
  end if;

  insert into public.user_profiles (user_id, nome)
  values (p_target_auth_user_id, v_next_nome)
  on conflict (user_id)
  do update set nome = excluded.nome;
end;
$$;

revoke all on function a.admin_upsert_auth_profile_locked(uuid, uuid, text, text, boolean)
  from public, anon, authenticated, service_role;

create or replace function public.admin_update_auth_profile(
  p_tenant_id uuid,
  p_target_auth_user_id uuid,
  p_nome text
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  perform a.admin_upsert_auth_profile_locked(
    p_tenant_id,
    p_target_auth_user_id,
    p_nome,
    null,
    true
  );
end;
$$;

revoke all on function public.admin_update_auth_profile(uuid, uuid, text)
  from public, anon, authenticated, service_role;

create or replace function a.fn_can_manage_legacy_role_assignments(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select auth.uid() is not null
     and public.has_active_tenant_access(p_tenant_id)
     and exists (
       select 1
       from a.usuario u
       join a.usuario_tenant ut on ut.usuario_id = u.id
       join public.tenants t on t.id = ut.tenant_id
       where u.auth_user_id = auth.uid()
         and u.ativo is true
         and u.deleted_at is null
         and ut.tenant_id = p_tenant_id
         and ut.papel in ('OWNER', 'ADMIN')
         and ut.ativo is true
         and ut.deleted_at is null
         and t.ativo is true
     );
$$;

revoke all on function a.fn_can_manage_legacy_role_assignments(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.admin_can_assign_legacy_roles(
  p_tenant_id uuid,
  p_role_ids uuid[]
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role_ids uuid[] := coalesce(p_role_ids, array[]::uuid[]);
begin
  if not a.fn_can_manage_legacy_role_assignments(p_tenant_id) then
    return false;
  end if;

  if cardinality(v_role_ids) <> (
    select count(distinct requested.role_id)::integer
    from unnest(v_role_ids) requested(role_id)
    where requested.role_id is not null
  ) then
    return false;
  end if;

  return not exists (
    select 1
    from unnest(v_role_ids) requested(role_id)
    left join public.roles r
      on r.id = requested.role_id
     and r.tenant_id = p_tenant_id
    where r.id is null
  );
end;
$$;

create or replace function public.admin_replace_membership_roles(
  p_tenant_id uuid,
  p_target_auth_user_id uuid,
  p_role_ids uuid[]
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_membership_id uuid;
  v_target_usuario_id uuid;
  v_target_deleted_at timestamptz;
  v_role_ids uuid[] := coalesce(p_role_ids, array[]::uuid[]);
begin
  perform 1
  from public.tenants t
  where t.id = p_tenant_id
    and t.ativo is true
  for update;
  if not found then
    raise exception 'tenant_not_found_or_inactive';
  end if;

  if not a.fn_can_manage_legacy_role_assignments(p_tenant_id) then
    raise exception 'role_hierarchy_violation';
  end if;

  perform 1
  from auth.users au
  where au.id = p_target_auth_user_id
  for update;
  if not found then
    raise exception 'auth_user_not_found';
  end if;

  select u.id, u.deleted_at
    into v_target_usuario_id, v_target_deleted_at
  from a.usuario u
  where u.auth_user_id = p_target_auth_user_id
  for update;

  if v_target_deleted_at is not null then
    raise exception 'canonical_user_deleted';
  end if;

  if v_target_usuario_id is not null
     and not a.fn_admin_can_manage_target(
       p_tenant_id,
       v_target_usuario_id,
       null,
       true
     ) then
    raise exception 'role_hierarchy_violation';
  end if;

  select tm.id
    into v_membership_id
  from public.tenant_memberships tm
  where tm.user_id = p_target_auth_user_id
    and tm.tenant_id = p_tenant_id
  for update;
  if not found then
    raise exception 'membership_not_found_in_tenant';
  end if;

  if not public.admin_can_assign_legacy_roles(p_tenant_id, v_role_ids) then
    raise exception 'invalid_or_out_of_scope_role_ids';
  end if;

  perform 1
  from public.roles r
  where r.id = any(v_role_ids)
    and r.tenant_id = p_tenant_id
  order by r.id
  for update;

  if cardinality(v_role_ids) <> (
    select count(*)::integer
    from public.roles r
    where r.id = any(v_role_ids)
      and r.tenant_id = p_tenant_id
  ) then
    raise exception 'invalid_or_out_of_scope_role_ids';
  end if;

  delete from public.membership_roles mr
  where mr.membership_id = v_membership_id;

  insert into public.membership_roles (membership_id, role_id)
  select v_membership_id, requested.role_id
  from unnest(v_role_ids) requested(role_id);
end;
$$;

revoke all on function public.admin_can_assign_legacy_roles(uuid, uuid[]) from public, anon;
revoke all on function public.admin_replace_membership_roles(uuid, uuid, uuid[])
  from public, anon, authenticated, service_role;
grant execute on function public.admin_can_assign_legacy_roles(uuid, uuid[])
  to authenticated, service_role;

create or replace function public.admin_set_auth_user_tenant_status(
  p_tenant_id uuid,
  p_target_auth_user_id uuid,
  p_ativo boolean
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_usuario_id uuid;
  v_papel text;
begin
  if p_ativo is null then
    raise exception 'active_flag_required';
  end if;

  perform 1
  from public.tenants t
  where t.id = p_tenant_id
    and t.ativo is true
  for update;
  if not found then
    raise exception 'tenant_not_found_or_inactive';
  end if;

  select u.id, ut.papel
    into v_usuario_id, v_papel
  from a.usuario u
  join a.usuario_tenant ut on ut.usuario_id = u.id
  where u.auth_user_id = p_target_auth_user_id
    and u.deleted_at is null
    and ut.tenant_id = p_tenant_id
    and ut.deleted_at is null
  for update of u, ut;
  if not found then
    raise exception 'user_not_in_tenant';
  end if;

  perform public.admin_set_user_tenant_role(
    p_tenant_id,
    v_usuario_id,
    v_papel,
    p_ativo
  );
end;
$$;

revoke all on function public.admin_set_auth_user_tenant_status(uuid, uuid, boolean)
  from public, anon, authenticated, service_role;

create or replace function public.admin_update_legacy_user(
  p_tenant_id uuid,
  p_target_auth_user_id uuid,
  p_update_nome boolean,
  p_nome text,
  p_update_status boolean,
  p_status text,
  p_update_roles boolean,
  p_role_ids uuid[]
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role_ids uuid[] := coalesce(p_role_ids, array[]::uuid[]);
  v_status text := lower(trim(coalesce(p_status, '')));
begin
  perform 1
  from public.tenants t
  where t.id = p_tenant_id
    and t.ativo is true
  for update;
  if not found then
    raise exception 'tenant_not_found_or_inactive';
  end if;

  perform 1
  from auth.users au
  where au.id = p_target_auth_user_id
  for update;
  if not found then
    raise exception 'auth_user_not_found';
  end if;

  perform 1
  from a.usuario u
  where u.auth_user_id = p_target_auth_user_id
    and u.deleted_at is null
  for update;
  if not found then
    raise exception 'canonical_user_not_found';
  end if;

  if not public.admin_can_manage_auth_user(
    p_tenant_id,
    p_target_auth_user_id
  ) then
    raise exception 'role_hierarchy_violation';
  end if;

  if coalesce(p_update_nome, false)
     and nullif(trim(coalesce(p_nome, '')), '') is null then
    raise exception 'user_name_required';
  end if;

  if coalesce(p_update_status, false)
     and v_status not in ('active', 'inactive') then
    raise exception 'invalid_status';
  end if;

  if coalesce(p_update_roles, false)
     and not public.admin_can_assign_legacy_roles(p_tenant_id, v_role_ids) then
    raise exception 'invalid_or_out_of_scope_role_ids';
  end if;

  if coalesce(p_update_nome, false) then
    perform public.admin_update_auth_profile(
      p_tenant_id,
      p_target_auth_user_id,
      p_nome
    );
  end if;

  if coalesce(p_update_status, false) then
    perform public.admin_set_auth_user_tenant_status(
      p_tenant_id,
      p_target_auth_user_id,
      v_status = 'active'
    );
  end if;

  if coalesce(p_update_roles, false) then
    perform public.admin_replace_membership_roles(
      p_tenant_id,
      p_target_auth_user_id,
      v_role_ids
    );
  end if;
end;
$$;

create or replace function public.admin_finalize_legacy_user(
  p_tenant_id uuid,
  p_auth_user_id uuid,
  p_email text,
  p_nome text,
  p_role_ids uuid[]
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role_ids uuid[] := coalesce(p_role_ids, array[]::uuid[]);
  v_usuario_id uuid;
  v_existing_membership_id uuid;
  v_existing_membership_status text;
  v_has_existing_roles boolean := false;
  v_can_manage_roles boolean;
begin
  perform 1
  from public.tenants t
  where t.id = p_tenant_id
    and t.ativo is true
  for update;
  if not found then
    raise exception 'tenant_not_found_or_inactive';
  end if;

  perform 1
  from auth.users au
  where au.id = p_auth_user_id
  for update;
  if not found then
    raise exception 'auth_user_not_found';
  end if;

  select u.id
    into v_usuario_id
  from a.usuario u
  where u.auth_user_id = p_auth_user_id
    and u.deleted_at is null
  for update;

  if v_usuario_id is not null and exists (
    select 1
    from a.usuario_tenant ut
    where ut.usuario_id = v_usuario_id
      and ut.tenant_id = p_tenant_id
      and ut.ativo is true
      and ut.deleted_at is null
  ) then
    raise exception 'user_already_active_in_tenant';
  end if;

  select tm.id, tm.status
    into v_existing_membership_id, v_existing_membership_status
  from public.tenant_memberships tm
  where tm.user_id = p_auth_user_id
    and tm.tenant_id = p_tenant_id
  for update;

  if v_existing_membership_status in ('active', 'ativo') then
    raise exception 'user_already_active_in_tenant';
  end if;

  if v_existing_membership_id is not null then
    v_has_existing_roles := exists (
      select 1
      from public.membership_roles mr
      where mr.membership_id = v_existing_membership_id
    );
  end if;

  v_can_manage_roles := a.fn_can_manage_legacy_role_assignments(p_tenant_id);

  if (cardinality(v_role_ids) > 0 or v_has_existing_roles)
     and not v_can_manage_roles then
    raise exception 'role_hierarchy_violation';
  end if;

  if v_can_manage_roles
     and not public.admin_can_assign_legacy_roles(p_tenant_id, v_role_ids) then
    raise exception 'invalid_or_out_of_scope_role_ids';
  end if;

  v_usuario_id := public.admin_finalize_invited_user(
    p_tenant_id,
    p_auth_user_id,
    p_email,
    p_nome,
    null,
    'GESTOR',
    '[]'::jsonb
  );

  if v_can_manage_roles then
    perform public.admin_replace_membership_roles(
      p_tenant_id,
      p_auth_user_id,
      v_role_ids
    );
  end if;

  return v_usuario_id;
end;
$$;

revoke all on function public.admin_update_legacy_user(
  uuid, uuid, boolean, text, boolean, text, boolean, uuid[]
) from public, anon;
revoke all on function public.admin_finalize_legacy_user(uuid, uuid, text, text, uuid[])
  from public, anon;
grant execute on function public.admin_update_legacy_user(
  uuid, uuid, boolean, text, boolean, text, boolean, uuid[]
) to authenticated, service_role;
grant execute on function public.admin_finalize_legacy_user(uuid, uuid, text, text, uuid[])
  to authenticated, service_role;

-- O perfil publico e global por auth user. Escritas diretas contornariam os
-- locks e as validacoes acima; leituras continuam regidas por RLS.
revoke insert, update, delete, truncate, references, trigger
  on table public.user_profiles
  from public, anon, authenticated;
grant all on table public.user_profiles to service_role;

create or replace function a.assert_legacy_role_reactivation_scope(
  p_tenant_id uuid,
  p_target_auth_user_id uuid,
  p_next_user_active boolean,
  p_next_tenant_active boolean
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_usuario_id uuid;
  v_current_user_active boolean := false;
  v_current_tenant_active boolean := false;
  v_membership_id uuid;
  v_current_projection_active boolean := false;
  v_next_user_active boolean;
  v_next_tenant_active boolean;
begin
  if p_target_auth_user_id is null then
    return;
  end if;

  select
    u.id,
    (u.ativo is true and u.deleted_at is null)
    into v_usuario_id, v_current_user_active
  from a.usuario u
  where u.auth_user_id = p_target_auth_user_id;

  if v_usuario_id is not null then
    select (ut.ativo is true and ut.deleted_at is null)
      into v_current_tenant_active
    from a.usuario_tenant ut
    where ut.usuario_id = v_usuario_id
      and ut.tenant_id = p_tenant_id
    order by (ut.deleted_at is null) desc, ut.updated_at desc nulls last
    limit 1;
  end if;

  v_next_user_active := coalesce(p_next_user_active, v_current_user_active, false);
  v_next_tenant_active := coalesce(p_next_tenant_active, v_current_tenant_active, false);
  if not (v_next_user_active and v_next_tenant_active) then
    return;
  end if;

  select tm.id, tm.status in ('active', 'ativo')
    into v_membership_id, v_current_projection_active
  from public.tenant_memberships tm
  where tm.user_id = p_target_auth_user_id
    and tm.tenant_id = p_tenant_id
  for update;

  if v_membership_id is null
     or (v_current_user_active
         and v_current_tenant_active
         and v_current_projection_active) then
    return;
  end if;

  if not exists (
    select 1
    from public.membership_roles mr
    where mr.membership_id = v_membership_id
  ) then
    return;
  end if;

  if not a.fn_can_manage_legacy_role_assignments(p_tenant_id) then
    raise exception 'legacy_role_reactivation_requires_owner_or_admin';
  end if;
end;
$$;

revoke all on function a.assert_legacy_role_reactivation_scope(
  uuid, uuid, boolean, boolean
) from public, anon, authenticated, service_role;

create or replace function a.trg_guard_legacy_role_projection_reactivation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if auth.uid() is null then
    return new;
  end if;

  if new.status in ('active', 'ativo')
     and coalesce(old.status, '') not in ('active', 'ativo')
     and exists (
       select 1
       from public.membership_roles mr
       where mr.membership_id = new.id
     )
     and not a.fn_can_manage_legacy_role_assignments(new.tenant_id) then
    raise exception 'legacy_role_reactivation_requires_owner_or_admin';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_legacy_role_projection_reactivation
  on public.tenant_memberships;
create trigger trg_guard_legacy_role_projection_reactivation
before update of status on public.tenant_memberships
for each row
execute function a.trg_guard_legacy_role_projection_reactivation();

revoke all on function a.trg_guard_legacy_role_projection_reactivation()
  from public, anon, authenticated, service_role;

create or replace function public.admin_save_user_access(
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
declare
  v_target_auth_user_id uuid;
begin
  perform a.assert_admin_hierarchy_locked(
    p_tenant_id,
    p_usuario_id,
    p_tenant_papel,
    true
  );
  select u.auth_user_id
    into v_target_auth_user_id
  from a.usuario u
  where u.id = p_usuario_id;
  perform a.assert_legacy_role_reactivation_scope(
    p_tenant_id,
    v_target_auth_user_id,
    p_usuario_ativo,
    p_tenant_ativo
  );
  perform a.assert_global_user_profile_scope(
    p_tenant_id,
    p_usuario_id,
    true,
    p_nome,
    false,
    null,
    true,
    p_telefone,
    true,
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

create or replace function public.admin_finalize_invited_user(
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

  perform 1
  from auth.users au
  where au.id = p_auth_user_id
  for update;
  if not found then
    raise exception 'auth_user_not_found';
  end if;

  select u.id
    into v_usuario_id
  from a.usuario u
  where u.auth_user_id = p_auth_user_id
  for update;

  perform a.assert_admin_hierarchy_locked(
    p_tenant_id,
    v_usuario_id,
    p_tenant_papel,
    false
  );
  perform a.assert_legacy_role_reactivation_scope(
    p_tenant_id,
    p_auth_user_id,
    true,
    true
  );
  perform a.assert_global_user_profile_scope(
    p_tenant_id,
    v_usuario_id,
    true,
    p_nome,
    true,
    p_email,
    true,
    p_telefone,
    true,
    true
  );
  perform a.admin_upsert_auth_profile_locked(
    p_tenant_id,
    p_auth_user_id,
    p_nome,
    p_tenant_papel,
    false
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

create or replace function public.admin_update_user(
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
declare
  v_target_auth_user_id uuid;
begin
  perform a.assert_admin_hierarchy_locked(p_tenant_id, p_usuario_id, null, true);
  select u.auth_user_id
    into v_target_auth_user_id
  from a.usuario u
  where u.id = p_usuario_id;
  perform a.assert_legacy_role_reactivation_scope(
    p_tenant_id,
    v_target_auth_user_id,
    p_ativo,
    null
  );
  perform a.assert_global_user_profile_scope(
    p_tenant_id,
    p_usuario_id,
    true,
    p_nome,
    false,
    null,
    true,
    p_telefone,
    true,
    p_ativo
  );
  perform public.admin_update_user_impl_20260811(
    p_tenant_id,
    p_usuario_id,
    p_nome,
    p_telefone,
    p_ativo
  );
end;
$$;

create or replace function public.admin_set_user_tenant_role(
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
declare
  v_target_auth_user_id uuid;
begin
  perform a.assert_admin_hierarchy_locked(
    p_tenant_id,
    p_usuario_id,
    p_papel,
    true
  );
  select u.auth_user_id
    into v_target_auth_user_id
  from a.usuario u
  where u.id = p_usuario_id;
  perform a.assert_legacy_role_reactivation_scope(
    p_tenant_id,
    v_target_auth_user_id,
    null,
    p_ativo
  );
  perform public.admin_set_user_tenant_role_impl_20260811(
    p_tenant_id,
    p_usuario_id,
    p_papel,
    p_ativo
  );
end;
$$;

create or replace function public.admin_set_user_empresa(
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
declare
  v_target_auth_user_id uuid;
begin
  perform a.assert_admin_hierarchy_locked(
    p_tenant_id,
    p_usuario_id,
    null,
    true
  );
  select u.auth_user_id
    into v_target_auth_user_id
  from a.usuario u
  where u.id = p_usuario_id;
  perform a.assert_legacy_role_reactivation_scope(
    p_tenant_id,
    v_target_auth_user_id,
    null,
    null
  );
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

do $shared_profile_assertions$
declare
  v_signature regprocedure;
  v_definition text;
begin
  foreach v_signature in array array[
    'public.admin_save_user_access(uuid,uuid,text,text,boolean,text,boolean,jsonb)'::regprocedure,
    'public.admin_finalize_invited_user(uuid,uuid,text,text,text,text,jsonb)'::regprocedure,
    'public.admin_update_user(uuid,uuid,text,text,boolean)'::regprocedure
  ]
  loop
    if position('assert_global_user_profile_scope' in pg_get_functiondef(v_signature)) = 0 then
      raise exception 'shared_profile_guard_missing: %', v_signature;
    end if;
  end loop;

  foreach v_signature in array array[
    'public.admin_save_user_access(uuid,uuid,text,text,boolean,text,boolean,jsonb)'::regprocedure,
    'public.admin_finalize_invited_user(uuid,uuid,text,text,text,text,jsonb)'::regprocedure,
    'public.admin_update_user(uuid,uuid,text,text,boolean)'::regprocedure,
    'public.admin_set_user_tenant_role(uuid,uuid,text,boolean)'::regprocedure,
    'public.admin_set_user_empresa(uuid,uuid,uuid,text,boolean)'::regprocedure
  ]
  loop
    if position('assert_legacy_role_reactivation_scope' in pg_get_functiondef(v_signature)) = 0 then
      raise exception 'legacy_role_reactivation_guard_missing: %', v_signature;
    end if;
  end loop;

  v_definition := pg_get_functiondef(
    'public.admin_finalize_invited_user(uuid,uuid,text,text,text,text,jsonb)'::regprocedure
  );
  if position('from auth.users' in lower(v_definition)) = 0
     or position('admin_upsert_auth_profile_locked' in v_definition) = 0 then
    raise exception 'invited_user_global_lock_or_profile_guard_missing';
  end if;

  v_definition := pg_get_functiondef(
    'a.fn_can_manage_legacy_role_assignments(uuid)'::regprocedure
  );
  if position('diretor' in lower(v_definition)) > 0
     or position('owner' in lower(v_definition)) = 0
     or position('admin' in lower(v_definition)) = 0 then
    raise exception 'legacy_role_matrix_controller_invalid';
  end if;

  foreach v_signature in array array[
    'public.admin_can_assign_legacy_roles(uuid,uuid[])'::regprocedure,
    'public.admin_update_legacy_user(uuid,uuid,boolean,text,boolean,text,boolean,uuid[])'::regprocedure,
    'public.admin_finalize_legacy_user(uuid,uuid,text,text,uuid[])'::regprocedure
  ]
  loop
    if has_function_privilege('anon', v_signature, 'execute')
       or not has_function_privilege('authenticated', v_signature, 'execute') then
      raise exception 'legacy_admin_rpc_acl_invalid: %', v_signature;
    end if;
  end loop;

  if has_table_privilege('authenticated', 'public.user_profiles', 'INSERT')
     or has_table_privilege('authenticated', 'public.user_profiles', 'UPDATE')
     or has_table_privilege('authenticated', 'public.user_profiles', 'DELETE') then
    raise exception 'global_profile_direct_dml_still_exposed';
  end if;

  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid = 'a.usuario_tenant'::regclass
      and c.conname = 'ck_usuario_tenant__papel'
      and c.convalidated is true
      and position('DIRETOR' in pg_get_constraintdef(c.oid)) > 0
  ) then
    raise exception 'diretor_constraint_not_validated';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'a.usuario_empresa'::regclass
      and t.tgname = 'trg_guard_usuario_empresa_hierarchy'
      and t.tgenabled <> 'D'
      and not t.tgisinternal
  ) then
    raise exception 'usuario_empresa_hierarchy_trigger_missing';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'public.tenant_memberships'::regclass
      and t.tgname = 'trg_guard_legacy_role_projection_reactivation'
      and t.tgenabled <> 'D'
      and not t.tgisinternal
  ) then
    raise exception 'legacy_role_projection_guard_trigger_missing';
  end if;

  foreach v_signature in array array[
    'a.admin_upsert_auth_profile_locked(uuid,uuid,text,text,boolean)'::regprocedure,
    'a.fn_can_manage_legacy_role_assignments(uuid)'::regprocedure,
    'a.assert_legacy_role_reactivation_scope(uuid,uuid,boolean,boolean)'::regprocedure,
    'a.trg_guard_legacy_role_projection_reactivation()'::regprocedure,
    'public.admin_update_auth_profile(uuid,uuid,text)'::regprocedure,
    'public.admin_replace_membership_roles(uuid,uuid,uuid[])'::regprocedure,
    'public.admin_set_auth_user_tenant_status(uuid,uuid,boolean)'::regprocedure,
    'public.admin_save_user_access_impl_20260811(uuid,uuid,text,text,boolean,text,boolean,jsonb)'::regprocedure,
    'public.admin_finalize_invited_user_impl_20260811(uuid,uuid,text,text,text,text,jsonb)'::regprocedure,
    'public.admin_update_user_impl_20260811(uuid,uuid,text,text,boolean)'::regprocedure,
    'public.admin_set_user_tenant_role_impl_20260811(uuid,uuid,text,boolean)'::regprocedure,
    'public.admin_set_user_empresa_impl_20260811(uuid,uuid,uuid,text,boolean)'::regprocedure
  ]
  loop
    if has_function_privilege('authenticated', v_signature, 'execute')
       or has_function_privilege('anon', v_signature, 'execute') then
      raise exception 'internal_admin_impl_exposed: %', v_signature;
    end if;
  end loop;
end;
$shared_profile_assertions$;

comment on function a.assert_global_user_profile_scope(
  uuid, uuid, boolean, text, boolean, text, boolean, text, boolean, boolean
) is 'Impede alteracao de perfil/status global por um unico tenant quando o usuario esta ativo em outro tenant.';
comment on function public.admin_update_auth_profile(uuid, uuid, text) is
  'Atualiza atomicamente o perfil publico de um usuario do tenant, respeitando hierarquia e compartilhamento global.';
comment on function public.admin_replace_membership_roles(uuid, uuid, uuid[]) is
  'Substitui roles legadas de um usuario no tenant; controle restrito a OWNER/ADMIN e role_ids do mesmo tenant.';

notify pgrst, 'reload schema';

commit;
