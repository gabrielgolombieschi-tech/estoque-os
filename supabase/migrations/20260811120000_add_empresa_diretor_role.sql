begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- DIRETOR e um papel da empresa: possui a mesma alçada operacional de ADMIN,
-- mas nao participa do plano de controle de usuarios.
alter table a.usuario_empresa
  add constraint ck_usuario_empresa__papel_v2
  check (papel = any (array[
    'ADMIN','DIRETOR','FINANCEIRO','FATURAMENTO','COORDENACAO','COMPRAS',
    'ALMOXARIFADO','TECNICO','APONTAMENTO_RH','PAINEL_TV'
  ]::text[]))
  not valid;

alter table a.usuario_empresa
  validate constraint ck_usuario_empresa__papel_v2;

alter table a.usuario_empresa
  drop constraint ck_usuario_empresa__papel;

alter table a.usuario_empresa
  rename constraint ck_usuario_empresa__papel_v2 to ck_usuario_empresa__papel;

create or replace function a.fn_map_papel_empresa(p text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when p is null then 'ADMIN'
    when upper(p) in (
      'ADMIN','DIRETOR','FINANCEIRO','FATURAMENTO','COORDENACAO','COMPRAS',
      'ALMOXARIFADO','TECNICO','APONTAMENTO_RH','PAINEL_TV'
    ) then upper(p)
    when upper(p) in ('OWNER','CONTADOR','GESTOR') then 'ADMIN'
    else 'ADMIN'
  end;
$$;

create or replace function a.fn_map_papel_empresa_to_role(papel text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case upper(coalesce(papel, ''))
    when 'ADMIN' then 'admin'
    when 'DIRETOR' then 'admin'
    when 'FINANCEIRO' then 'financeiro'
    when 'FATURAMENTO' then 'faturamento'
    when 'COORDENACAO' then 'projetos'
    when 'TECNICO' then 'projetos'
    when 'COMPRAS' then 'estoque'
    when 'ALMOXARIFADO' then 'estoque'
    when 'APONTAMENTO_RH' then 'projetos'
    when 'PAINEL_TV' then 'projetos'
    else 'estoque'
  end;
$$;

create or replace function a.fn_current_empresa_papel(
  p_tenant_id uuid,
  p_empresa_id uuid
)
returns text
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select upper(trim(ue.papel))
  from a.usuario u
  join a.usuario_tenant ut on ut.usuario_id = u.id
  join a.usuario_empresa ue on ue.usuario_id = u.id
  join c.empresa ce on ce.id = ue.empresa_id
  where u.auth_user_id = auth.uid()
    and u.ativo is true
    and u.deleted_at is null
    and ut.tenant_id = p_tenant_id
    and ut.ativo is true
    and ut.deleted_at is null
    and ue.empresa_id = p_empresa_id
    and ue.ativo is true
    and ue.deleted_at is null
    and ce.tenant_id = p_tenant_id
    and ce.ativo is true
    and ce.deleted_at is null
    and public.has_active_empresa_access(p_tenant_id, p_empresa_id)
  limit 1;
$$;

revoke all on function a.fn_current_empresa_papel(uuid, uuid) from public, anon, authenticated, service_role;

create or replace function public.get_full_permissions(p_tenant_id uuid, p_empresa_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_result jsonb;
  v_admin jsonb;
  v_empresa_papel text;
  v_tenant_papel text;
  v_negadas jsonb;
  v_negadas_keys text[];
begin
  if not public.has_active_empresa_access(p_tenant_id, p_empresa_id) then
    return '{}'::jsonb;
  end if;

  v_result := coalesce(
    public.get_full_permissions_unscoped_20260810(p_tenant_id, p_empresa_id),
    '{}'::jsonb
  );

  select upper(trim(ut.papel)), upper(trim(ue.papel)), ue.permissoes_negadas
    into v_tenant_papel, v_empresa_papel, v_negadas
  from a.usuario u
  join a.usuario_tenant ut on ut.usuario_id = u.id
  join a.usuario_empresa ue on ue.usuario_id = u.id
  where u.auth_user_id = auth.uid()
    and u.ativo is true
    and u.deleted_at is null
    and ut.tenant_id = p_tenant_id
    and ut.ativo is true
    and ut.deleted_at is null
    and ue.empresa_id = p_empresa_id
    and ue.ativo is true
    and ue.deleted_at is null
  limit 1;

  if v_empresa_papel = 'DIRETOR' then
    select coalesce(jsonb_object_agg(rp.permission, true), '{}'::jsonb)
      into v_admin
    from public.role_permissions rp
    where rp.role = 'admin';

    v_result := v_result || v_admin || jsonb_build_object('modulo_preferencial', 'admin');

    if jsonb_typeof(v_negadas) = 'object' then
      select array_agg(k) into v_negadas_keys
      from jsonb_object_keys(v_negadas) k;
      if v_negadas_keys is not null then
        v_result := v_result - v_negadas_keys;
      end if;
    end if;
  end if;

  -- O DIRETOR, antigo ou novo, nunca recebe gestao de identidades.
  if v_empresa_papel = 'DIRETOR' or v_tenant_papel = 'DIRETOR' then
    v_result := v_result - array['admin.manage_users','admin.users.manage'];
  end if;

  return coalesce(v_result, '{}'::jsonb);
end;
$$;

create or replace function public.can(p_resource text, p_action text, p_tenant_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_empresa_id uuid;
  v_empresa_papel text;
begin
  if auth.uid() is null or p_tenant_id is null then
    return false;
  end if;

  -- Usuario e qualquer alias equivalente permanecem exclusivos de OWNER/ADMIN.
  if lower(coalesce(p_resource, '')) = 'admin'
     and lower(coalesce(p_action, '')) in ('manage_users','users.manage') then
    return public.admin_can_manage_users(p_tenant_id);
  end if;

  if public.current_tenant_id() is distinct from p_tenant_id then
    return false;
  end if;

  v_empresa_id := public.current_empresa_id__by_tenant(p_tenant_id);
  if not public.has_active_empresa_access(p_tenant_id, v_empresa_id) then
    return false;
  end if;

  v_empresa_papel := a.fn_current_empresa_papel(p_tenant_id, v_empresa_id);
  if v_empresa_papel = 'DIRETOR' then
    return true;
  end if;

  return public.can_unscoped_20260810(p_resource, p_action, p_tenant_id);
end;
$$;

create or replace function public.has_permission(p_code text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select coalesce(
    public.get_full_permissions(
      public.current_tenant_id(),
      public.current_empresa_id()
    ) @> jsonb_build_object(p_code, true),
    false
  );
$$;

create or replace function f.has_finance_access(
  p_tenant uuid default public.current_tenant_id(),
  p_empresa uuid default public.current_empresa_id()
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select public.has_active_empresa_access(p_tenant, p_empresa)
     and (
       a.fn_current_empresa_papel(p_tenant, p_empresa) = 'DIRETOR'
       or f.has_finance_access_unscoped_20260810(p_tenant, p_empresa)
     );
$$;

create or replace function c.has_imobilizado_access(
  p_tenant uuid default public.current_tenant_id(),
  p_empresa uuid default public.current_empresa_id()
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select public.has_active_empresa_access(p_tenant, p_empresa)
     and (
       a.fn_current_empresa_papel(p_tenant, p_empresa) = 'DIRETOR'
       or c.has_imobilizado_access_unscoped_20260810(p_tenant, p_empresa)
     );
$$;

create or replace function c.has_comercial_access(
  p_tenant uuid default public.current_tenant_id(),
  p_empresa uuid default public.current_empresa_id()
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select public.has_active_empresa_access(p_tenant, p_empresa)
     and (
       a.fn_current_empresa_papel(p_tenant, p_empresa) = 'DIRETOR'
       or c.has_comercial_access_unscoped_20260810(p_tenant, p_empresa)
     );
$$;

create or replace function c.has_compras_access(
  p_tenant uuid default public.current_tenant_id(),
  p_empresa uuid default public.current_empresa_id()
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select public.has_active_empresa_access(p_tenant, p_empresa)
     and (
       a.fn_current_empresa_papel(p_tenant, p_empresa) = 'DIRETOR'
       or c.has_compras_access_unscoped_20260810(p_tenant, p_empresa)
     );
$$;

create or replace function f.has_motivo_compra_access(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select exists (
    select 1
    from a.usuario u
    join a.usuario_empresa ue on ue.usuario_id = u.id
    join c.empresa ce on ce.id = ue.empresa_id
    where u.auth_user_id = auth.uid()
      and u.ativo is true
      and u.deleted_at is null
      and ue.empresa_id = public.current_empresa_id__by_tenant(p_tenant_id)
      and ue.ativo is true
      and ue.deleted_at is null
      and ce.tenant_id = p_tenant_id
      and public.has_active_empresa_access(p_tenant_id, ue.empresa_id)
      and upper(trim(coalesce(ue.papel, ''))) in (
        'ADMIN','DIRETOR','FINANCEIRO','FATURAMENTO','COORDENACAO',
        'COMPRAS','ALMOXARIFADO','APONTAMENTO_RH'
      )
  );
$$;

drop policy if exists clientes_delete on public.clientes;
create policy clientes_delete
on public.clientes
for delete to authenticated
using (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
  and public.has_active_empresa_access(tenant_id, empresa_id)
  and a.fn_current_empresa_papel(tenant_id, empresa_id) in ('ADMIN','DIRETOR')
);

-- DIRETOR no tenant continua operacional por compatibilidade, mas nao e mais
-- considerado administrador de usuarios ou do plano de controle.
create or replace function public.admin_can_manage_users(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select public.has_active_tenant_access(p_tenant_id)
    and coalesce(
      a.fn_current_empresa_papel(
        p_tenant_id,
        public.current_empresa_id__by_tenant(p_tenant_id)
      ),
      ''
    ) <> 'DIRETOR'
    and exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut on ut.usuario_id = u.id
      where u.auth_user_id = auth.uid()
        and u.ativo is true
        and u.deleted_at is null
        and ut.tenant_id = p_tenant_id
        and ut.papel in ('OWNER','ADMIN')
        and ut.ativo is true
        and ut.deleted_at is null
    );
$$;

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
        and ut.papel in ('OWNER','ADMIN')
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
      and ut_me.papel in ('OWNER','ADMIN')
      and ut_other.ativo is true
      and ut_other.deleted_at is null
      and t.ativo is true
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
  if not public.admin_can_manage_users(p_tenant_id) then
    return false;
  end if;

  select upper(trim(ut.papel)) into v_actor_role
  from a.usuario u
  join a.usuario_tenant ut on ut.usuario_id = u.id
  where u.auth_user_id = auth.uid()
    and u.ativo is true
    and u.deleted_at is null
    and ut.tenant_id = p_tenant_id
    and ut.ativo is true
    and ut.deleted_at is null
  limit 1;

  if v_actor_role is null or v_actor_role not in ('OWNER','ADMIN') then
    return false;
  end if;

  if v_requested_role is not null
     and v_requested_role not in ('OWNER','ADMIN','DIRETOR','CONTADOR','GESTOR') then
    return false;
  end if;

  if p_target_usuario_id is not null then
    select upper(trim(ut.papel)) into v_target_role
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

  return coalesce(v_target_role <> 'OWNER', true)
     and coalesce(v_requested_role <> 'OWNER', true);
end;
$$;

-- Payloads administrativos passam a aceitar o novo papel canonico.
do $diretor_payload_patch$
declare
  v_definition text;
  v_patched text;
begin
  select pg_get_functiondef('a.validate_empresa_vinculos_payload(uuid,jsonb)'::regprocedure)
    into v_definition;
  v_patched := replace(
    v_definition,
    '''ADMIN'',''FINANCEIRO'',''FATURAMENTO''',
    '''ADMIN'',''DIRETOR'',''FINANCEIRO'',''FATURAMENTO'''
  );
  if v_patched = v_definition then
    raise exception 'empresa_diretor_payload_token_not_found';
  end if;
  execute v_patched;
end;
$diretor_payload_patch$;

revoke all on function public.admin_can_manage_users(uuid) from public, anon;
grant execute on function public.admin_can_manage_users(uuid) to authenticated, service_role;
revoke all on function public.get_full_permissions(uuid, uuid) from public, anon;
grant execute on function public.get_full_permissions(uuid, uuid) to authenticated, service_role;
revoke all on function public.can(text, text, uuid) from public, anon;
grant execute on function public.can(text, text, uuid) to authenticated, service_role;
revoke all on function public.has_permission(text) from public, anon;
grant execute on function public.has_permission(text) to authenticated, service_role;

do $empresa_diretor_assertions$
declare
  v_constraint text;
begin
  select pg_get_constraintdef(c.oid) into v_constraint
  from pg_constraint c
  where c.conrelid = 'a.usuario_empresa'::regclass
    and c.conname = 'ck_usuario_empresa__papel'
    and c.contype = 'c'
    and c.convalidated;

  if v_constraint is null or position('DIRETOR' in v_constraint) = 0 then
    raise exception 'empresa_diretor_constraint_not_installed';
  end if;

  if a.fn_map_papel_empresa('DIRETOR') <> 'DIRETOR'
     or a.fn_map_papel_empresa_to_role('DIRETOR') <> 'admin'
     or a.fn_map_papel_empresa('FATURAMENTO') <> 'FATURAMENTO' then
    raise exception 'empresa_diretor_mapping_invalid';
  end if;

  if position('DIRETOR' in pg_get_functiondef('a.validate_empresa_vinculos_payload(uuid,jsonb)'::regprocedure)) = 0 then
    raise exception 'empresa_diretor_payload_not_installed';
  end if;

  if has_function_privilege('anon', 'public.admin_can_manage_users(uuid)', 'execute')
     or has_function_privilege('anon', 'public.can(text,text,uuid)', 'execute')
     or has_function_privilege('authenticated', 'a.fn_current_empresa_papel(uuid,uuid)', 'execute') then
    raise exception 'empresa_diretor_acl_invalid';
  end if;
end;
$empresa_diretor_assertions$;

comment on function public.admin_can_manage_users(uuid) is
  'Gestao de usuarios e exclusiva de OWNER e ADMIN ativos; DIRETOR e somente operacional.';
comment on function a.fn_current_empresa_papel(uuid, uuid) is
  'Retorna o papel canonico ativo do usuario autenticado na empresa informada.';

notify pgrst, 'reload schema';

commit;
