begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- APONTADOR e um papel operacional de empresa. O papel de tenant permanece
-- GESTOR: as guardas abaixo impedem qualquer heranca desse papel de tenant.
alter table a.usuario_empresa
  add constraint ck_usuario_empresa__papel_v2
  check (papel = any (array[
    'ADMIN','DIRETOR','FINANCEIRO','FATURAMENTO','COORDENACAO','COMPRAS',
    'ALMOXARIFADO','TECNICO','APONTAMENTO_RH','PAINEL_TV','APONTADOR'
  ]::text[]))
  not valid;

alter table a.usuario_empresa
  validate constraint ck_usuario_empresa__papel_v2;

alter table a.usuario_empresa
  drop constraint ck_usuario_empresa__papel;

alter table a.usuario_empresa
  rename constraint ck_usuario_empresa__papel_v2 to ck_usuario_empresa__papel;

-- Evita que futuros fluxos administrativos normalizem APONTADOR para ADMIN
-- ou para o fallback operacional de estoque.
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
      'ALMOXARIFADO','TECNICO','APONTAMENTO_RH','PAINEL_TV','APONTADOR'
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
    when 'APONTADOR' then 'apontador'
    else 'estoque'
  end;
$$;

-- Matriz declarativa para auditoria e compatibilidade com o modelo legado.
-- As tres guardas abaixo sao a fonte de autorizacao efetiva para APONTADOR.
insert into public.role_permissions (role, permission)
select 'apontador', v.permission
from (values
  ('os.read'),
  ('apontamentos.read'),
  ('apontamentos.write'),
  ('colaboradores.read'),
  ('tipos_horas.read')
) as v(permission)
where not exists (
  select 1
  from public.role_permissions rp
  where rp.role = 'apontador'
    and rp.permission = v.permission
);

insert into public.roles (tenant_id, name, description)
select t.id, 'APONTADOR', 'Apontamento operacional sem acesso a valores financeiros.'
from public.tenants t
where t.ativo is true
  and not exists (
    select 1
    from public.roles r
    where r.tenant_id = t.id
      and r.name = 'APONTADOR'
  );

insert into public.role_access_rules (role_id, resource, action)
select r.id, v.resource, v.action
from public.roles r
cross join (values
  ('os', 'read'),
  ('apontamentos', 'read'),
  ('apontamentos', 'write'),
  ('colaboradores', 'read'),
  ('tipos_horas', 'read')
) as v(resource, action)
where r.name = 'APONTADOR'
  and not exists (
    select 1
    from public.role_access_rules ar
    where ar.role_id = r.id
      and ar.resource = v.resource
      and ar.action = v.action
  );

-- A funcao continua identica a partir da montagem da base. Apenas a leitura
-- do papel de empresa foi antecipada para que APONTADOR saia antes de herdar
-- qualquer permissao do papel de tenant.
do $patch_get_full_permissions$
declare
  v_definition text;
  v_needle text := $needle$
  if v_tenant_papel is null then
    return '{}'::jsonb;
  end if;

  select jsonb_object_agg(rp.permission, true)
    into base_perms
  from public.role_permissions rp
  where rp.role = a.fn_map_papel_tenant_to_role(v_tenant_papel);

  base_perms := coalesce(base_perms, '{}'::jsonb);

  select ue.papel, ue.permissoes_extra, ue.permissoes_negadas
    into v_empresa_papel, v_perm_extra, v_perm_negadas
  from a.usuario_empresa ue
  where ue.usuario_id = v_usuario_id
    and ue.empresa_id = p_empresa_id
    and ue.ativo = true
    and ue.deleted_at is null
  limit 1;

  if v_empresa_papel is null then
    return base_perms;
  end if;
$needle$;
  v_replacement text := $replacement$
  if v_tenant_papel is null then
    return '{}'::jsonb;
  end if;

  select ue.papel, ue.permissoes_extra, ue.permissoes_negadas
    into v_empresa_papel, v_perm_extra, v_perm_negadas
  from a.usuario_empresa ue
  where ue.usuario_id = v_usuario_id
    and ue.empresa_id = p_empresa_id
    and ue.ativo = true
    and ue.deleted_at is null
  limit 1;

  if upper(coalesce(v_empresa_papel, '')) = 'APONTADOR' then
    return jsonb_build_object(
      'os.read', true,
      'apontamentos.read', true,
      'apontamentos.write', true,
      'colaboradores.read', true,
      'tipos_horas.read', true
    );
  end if;

  select jsonb_object_agg(rp.permission, true)
    into base_perms
  from public.role_permissions rp
  where rp.role = a.fn_map_papel_tenant_to_role(v_tenant_papel);

  base_perms := coalesce(base_perms, '{}'::jsonb);

  if v_empresa_papel is null then
    return base_perms;
  end if;
$replacement$;
begin
  select pg_get_functiondef('public.get_full_permissions_unscoped_20260810(uuid,uuid)'::regprocedure)
    into v_definition;

  if position(v_needle in v_definition) = 0 then
    raise exception 'apontador_get_full_permissions_patch_token_not_found';
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$patch_get_full_permissions$;

-- A consulta do papel de empresa ocorre antes do retorno antecipado de
-- OWNER/ADMIN/DIRETOR. O restante da funcao e preservado literalmente.
do $patch_can_unscoped$
declare
  v_definition text;
  v_needle text := $needle$
  if v_papel_tenant is null then
    return false;
  end if;

  if v_papel_tenant in ('ADMIN','DIRETOR','OWNER') then
$needle$;
  v_replacement text := $replacement$
  if v_papel_tenant is null then
    return false;
  end if;

  v_empresa_id := public.current_empresa_id();

  if v_empresa_id is not null then
    select upper(coalesce(ue.papel, ''))
      into v_papel_empresa
    from a.usuario_empresa ue
    where ue.usuario_id = v_usuario_id
      and ue.empresa_id = v_empresa_id
      and ue.ativo = true
      and ue.deleted_at is null
    limit 1;
  end if;

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

  if v_papel_tenant in ('ADMIN','DIRETOR','OWNER') then
$replacement$;
begin
  select pg_get_functiondef('public.can_unscoped_20260810(text,text,uuid)'::regprocedure)
    into v_definition;

  if position(v_needle in v_definition) = 0 then
    raise exception 'apontador_can_unscoped_patch_token_not_found';
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$patch_can_unscoped$;

-- O fallback legado nunca pode reabrir uma permissao que a guarda canonica
-- recusou para APONTADOR.
do $patch_can_legacy$
declare
  v_definition text;
  v_declare_needle text := $needle$
  v_empresa_id uuid;
begin
$needle$;
  v_declare_replacement text := $replacement$
  v_empresa_id uuid;
  v_papel_empresa text;
begin
$replacement$;
  v_fallback_needle text := $needle$
  return exists (
    select 1
    from public.tenant_memberships tm
$needle$;
  v_fallback_replacement text := $replacement$
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

  return exists (
    select 1
    from public.tenant_memberships tm
$replacement$;
begin
  select pg_get_functiondef('public.can__legacy_40734(text,text)'::regprocedure)
    into v_definition;

  if position(v_declare_needle in v_definition) = 0
     or position(v_fallback_needle in v_definition) = 0 then
    raise exception 'apontador_can_legacy_patch_token_not_found';
  end if;

  v_definition := replace(v_definition, v_declare_needle, v_declare_replacement);
  v_definition := replace(v_definition, v_fallback_needle, v_fallback_replacement);
  execute v_definition;
end;
$patch_can_legacy$;

do $apontador_assertions$
declare
  v_constraint text;
  v_permissions jsonb;
begin
  select pg_get_constraintdef(c.oid)
    into v_constraint
  from pg_constraint c
  where c.conrelid = 'a.usuario_empresa'::regclass
    and c.conname = 'ck_usuario_empresa__papel'
    and c.contype = 'c'
    and c.convalidated;

  if v_constraint is null or position('APONTADOR' in v_constraint) = 0 then
    raise exception 'apontador_constraint_not_installed';
  end if;

  if a.fn_map_papel_empresa('APONTADOR') <> 'APONTADOR'
     or a.fn_map_papel_empresa_to_role('APONTADOR') <> 'apontador' then
    raise exception 'apontador_role_mapping_invalid';
  end if;

  select jsonb_object_agg(rp.permission, true)
    into v_permissions
  from public.role_permissions rp
  where rp.role = 'apontador';

  if coalesce(v_permissions, '{}'::jsonb) <> jsonb_build_object(
    'os.read', true,
    'apontamentos.read', true,
    'apontamentos.write', true,
    'colaboradores.read', true,
    'tipos_horas.read', true
  ) then
    raise exception 'apontador_permission_matrix_invalid';
  end if;

  if position('APONTADOR' in pg_get_functiondef('public.get_full_permissions_unscoped_20260810(uuid,uuid)'::regprocedure)) = 0
     or position('APONTADOR' in pg_get_functiondef('public.can_unscoped_20260810(text,text,uuid)'::regprocedure)) = 0
     or position('APONTADOR' in pg_get_functiondef('public.can__legacy_40734(text,text)'::regprocedure)) = 0 then
    raise exception 'apontador_guard_not_installed';
  end if;
end;
$apontador_assertions$;

notify pgrst, 'reload schema';

commit;
