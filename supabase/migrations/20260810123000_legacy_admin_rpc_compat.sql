begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- Mantem compatibilidade com frontends ainda publicados que salvam usuario,
-- tenant e empresa em chamadas separadas. As invariantes de OWNER e escopo
-- continuam no banco; a tela nova usa admin_save_user_access atomicamente.
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
  v_old_user_ativo boolean;
  v_old_tenant_papel text;
  v_old_tenant_ativo boolean;
begin
  if not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;
  if p_ativo is null then
    raise exception 'active_flag_required';
  end if;
  if nullif(trim(coalesce(p_nome, '')), '') is null then
    raise exception 'user_name_required';
  end if;

  perform 1
  from public.tenants t
  where t.id = p_tenant_id
    and t.ativo is true
  for update;
  if not found then
    raise exception 'tenant_not_found_or_inactive';
  end if;

  select u.ativo
    into v_old_user_ativo
  from a.usuario u
  where u.id = p_usuario_id
    and u.deleted_at is null
  for update;
  if not found then
    raise exception 'user_not_found';
  end if;

  select ut.papel, ut.ativo
    into v_old_tenant_papel, v_old_tenant_ativo
  from a.usuario_tenant ut
  where ut.usuario_id = p_usuario_id
    and ut.tenant_id = p_tenant_id
    and ut.deleted_at is null
  for update;
  if not found then
    raise exception 'user_not_in_tenant';
  end if;

  if v_old_tenant_papel = 'OWNER'
     and v_old_tenant_ativo is true
     and v_old_user_ativo is true
     and p_ativo is false then
    if not public.admin_is_owner(p_tenant_id) then
      raise exception 'owner_change_requires_owner';
    end if;

    if not exists (
      select 1
      from a.usuario_tenant other_ut
      join a.usuario other_u on other_u.id = other_ut.usuario_id
      where other_ut.tenant_id = p_tenant_id
        and other_ut.usuario_id <> p_usuario_id
        and other_ut.papel = 'OWNER'
        and other_ut.ativo is true
        and other_ut.deleted_at is null
        and other_u.ativo is true
        and other_u.deleted_at is null
    ) then
      raise exception 'last_active_owner';
    end if;
  end if;

  update a.usuario
     set nome = trim(p_nome),
         telefone = nullif(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), ''),
         ativo = p_ativo,
         updated_at = now(),
         updated_by = auth.uid()
   where id = p_usuario_id
     and deleted_at is null;

  perform a.sync_usuario_access_projection(p_usuario_id);
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
  v_papel text := upper(trim(coalesce(p_papel, '')));
  v_user_ativo boolean;
  v_old_papel text;
  v_old_ativo boolean;
begin
  if not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;
  if p_ativo is null then
    raise exception 'active_flag_required';
  end if;
  if v_papel not in ('OWNER','ADMIN','CONTADOR','GESTOR') then
    raise exception 'invalid_tenant_role: %', v_papel;
  end if;

  perform 1
  from public.tenants t
  where t.id = p_tenant_id
    and t.ativo is true
  for update;
  if not found then
    raise exception 'tenant_not_found_or_inactive';
  end if;

  select u.ativo
    into v_user_ativo
  from a.usuario u
  where u.id = p_usuario_id
    and u.deleted_at is null
  for update;
  if not found then
    raise exception 'user_not_found';
  end if;

  select ut.papel, ut.ativo
    into v_old_papel, v_old_ativo
  from a.usuario_tenant ut
  where ut.usuario_id = p_usuario_id
    and ut.tenant_id = p_tenant_id
    and ut.deleted_at is null
  for update;
  if not found then
    raise exception 'user_not_in_tenant';
  end if;

  if (v_papel = 'OWNER' or v_old_papel = 'OWNER')
     and not public.admin_is_owner(p_tenant_id) then
    raise exception 'owner_change_requires_owner';
  end if;

  if v_old_papel = 'OWNER'
     and v_old_ativo is true
     and v_user_ativo is true
     and (v_papel <> 'OWNER' or p_ativo is false)
     and not exists (
       select 1
       from a.usuario_tenant other_ut
       join a.usuario other_u on other_u.id = other_ut.usuario_id
       where other_ut.tenant_id = p_tenant_id
         and other_ut.usuario_id <> p_usuario_id
         and other_ut.papel = 'OWNER'
         and other_ut.ativo is true
         and other_ut.deleted_at is null
         and other_u.ativo is true
         and other_u.deleted_at is null
     ) then
    raise exception 'last_active_owner';
  end if;

  update a.usuario_tenant
     set papel = v_papel,
         ativo = p_ativo,
         updated_at = now(),
         updated_by = auth.uid(),
         deleted_at = null
   where usuario_id = p_usuario_id
     and tenant_id = p_tenant_id
     and deleted_at is null;

  perform a.sync_usuario_access_projection(p_usuario_id);
end;
$$;

revoke all on function public.admin_update_user(uuid, uuid, text, text, boolean)
  from public, anon;
revoke all on function public.admin_set_user_tenant_role(uuid, uuid, text, boolean)
  from public, anon;
revoke all on function public.admin_set_user_empresa(uuid, uuid, uuid, text, boolean)
  from public, anon;

grant execute on function public.admin_update_user(uuid, uuid, text, text, boolean)
  to authenticated, service_role;
grant execute on function public.admin_set_user_tenant_role(uuid, uuid, text, boolean)
  to authenticated, service_role;
grant execute on function public.admin_set_user_empresa(uuid, uuid, uuid, text, boolean)
  to authenticated, service_role;

do $$
begin
  if has_function_privilege(
       'anon',
       'public.admin_update_user(uuid,uuid,text,text,boolean)',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.admin_set_user_tenant_role(uuid,uuid,text,boolean)',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.admin_set_user_empresa(uuid,uuid,uuid,text,boolean)',
       'execute'
     ) then
    raise exception 'legacy_admin_rpc_exposed_to_anon';
  end if;
end;
$$;

notify pgrst, 'reload schema';

commit;
