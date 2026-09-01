begin;

do $$
begin
  if to_regclass('public.tenant_memberships') is not null then
    alter table public.tenant_memberships
      drop constraint if exists tenant_memberships_role_check;

    alter table public.tenant_memberships
      add constraint tenant_memberships_role_check
      check (role in ('admin', 'fiscal', 'estoque', 'projetos', 'financeiro', 'faturamento', 'guest', 'user'));
  end if;
end$$;

do $$
begin
  if to_regclass('a.usuario_empresa') is not null then
    alter table a.usuario_empresa
      drop constraint if exists ck_usuario_empresa__papel;

    alter table a.usuario_empresa
      add constraint ck_usuario_empresa__papel
      check (
        papel = any (
          array[
            'ADMIN'::text,
            'FINANCEIRO'::text,
            'FATURAMENTO'::text,
            'COORDENACAO'::text,
            'COMPRAS'::text,
            'ALMOXARIFADO'::text,
            'TECNICO'::text,
            'APONTAMENTO_RH'::text,
            'PAINEL_TV'::text
          ]
        )
      );
  end if;
end$$;

create or replace function a.fn_map_papel_empresa(p text)
returns text
language sql
as $$
  select case
    when p is null then 'ADMIN'
    when upper(p) in (
      'ADMIN',
      'FINANCEIRO',
      'FATURAMENTO',
      'COORDENACAO',
      'COMPRAS',
      'ALMOXARIFADO',
      'TECNICO',
      'APONTAMENTO_RH',
      'PAINEL_TV'
    ) then upper(p)
    when upper(p) in ('OWNER','CONTADOR','GESTOR') then 'ADMIN'
    else 'ADMIN'
  end;
$$;

create or replace function a.fn_map_papel_empresa_to_role(papel text)
returns text
language sql
immutable
as $$
  select case upper(coalesce(papel,''))
    when 'ADMIN' then 'admin'
    when 'FINANCEIRO' then 'financeiro'
    when 'FATURAMENTO' then 'faturamento'
    when 'COORDENACAO' then 'projetos'
    when 'TECNICO' then 'projetos'
    when 'COMPRAS' then 'estoque'
    when 'ALMOXARIFADO' then 'estoque'
    when 'APONTAMENTO_RH' then 'projetos'
    when 'PAINEL_TV' then 'projetos'
    else 'estoque'
  end
$$;

create or replace function a.fn_map_papel_tenant(p text)
returns text
language sql
as $$
  select case
    when p is null then 'GESTOR'
    when upper(p) in ('OWNER','ADMIN','CONTADOR','GESTOR') then upper(p)
    when upper(p) in (
      'FINANCEIRO',
      'FATURAMENTO',
      'COMPRAS',
      'ALMOXARIFADO',
      'TECNICO',
      'COORDENACAO',
      'APONTAMENTO_RH',
      'PAINEL_TV'
    ) then 'GESTOR'
    else 'GESTOR'
  end;
$$;

do $$
begin
  if to_regclass('public.role_permissions') is not null
    and exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'role_permissions'
        and column_name = 'role'
    )
    and exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'role_permissions'
        and column_name = 'permission'
    )
  then
    insert into public.role_permissions (role, permission)
    select 'faturamento', p.permission
    from (
      values
        ('os.read'),
        ('os.write'),
        ('os.delete'),
        ('os_itens.write'),
        ('os_gestao.write'),
        ('os_rpcs.execute'),
        ('estoque.read'),
        ('estoque.write'),
        ('estoque_custos.cost_read'),
        ('fiscal_nf.read'),
        ('fiscal_nf.write'),
        ('fiscal_nf.delete'),
        ('fiscal_itens.write'),
        ('xml_import.execute'),
        ('xml_import_faturamento.execute'),
        ('nf_entrada.import'),
        ('faturamento.read'),
        ('faturamento.write'),
        ('faturamento.nfe.import_xml'),
        ('imobilizado.read'),
        ('imobilizado.write'),
        ('apontamentos.read'),
        ('apontamentos.write'),
        ('apontamentos.delete'),
        ('apontamentos.config'),
        ('cad_clientes.write'),
        ('cad_fornecedores.write'),
        ('cad_itens.write'),
        ('compras.read'),
        ('compras.write'),
        ('compras.approve'),
        ('compras.receive')
    ) as p(permission)
    on conflict do nothing;
  end if;
end$$;

do $$
begin
  if to_regclass('public.roles') is not null and to_regclass('public.tenants') is not null then
    insert into public.roles (tenant_id, name)
    select t.id, 'FATURAMENTO'
    from public.tenants t
    where not exists (
      select 1
      from public.roles r
      where r.tenant_id = t.id
        and upper(trim(coalesce(r.name, ''))) = 'FATURAMENTO'
    );
  end if;

  if to_regclass('public.roles') is not null and to_regclass('public.role_access_rules') is not null then
    insert into public.role_access_rules (role_id, resource, action)
    select r.id, p.resource, p.action
    from public.roles r
    cross join (
      values
        ('os', 'read'),
        ('os', 'write'),
        ('os', 'delete'),
        ('os_itens', 'write'),
        ('os_gestao', 'write'),
        ('os_rpcs', 'execute'),
        ('estoque', 'read'),
        ('estoque', 'write'),
        ('estoque_custos', 'cost_read'),
        ('fiscal_nf', 'read'),
        ('fiscal_nf', 'write'),
        ('fiscal_nf', 'delete'),
        ('fiscal_itens', 'write'),
        ('xml_import', 'execute'),
        ('xml_import_faturamento', 'execute'),
        ('nf_entrada', 'import'),
        ('faturamento', 'read'),
        ('faturamento', 'write'),
        ('faturamento', 'nfe.import_xml'),
        ('imobilizado', 'read'),
        ('imobilizado', 'write'),
        ('apontamentos', 'read'),
        ('apontamentos', 'write'),
        ('apontamentos', 'delete'),
        ('apontamentos', 'config'),
        ('cad_clientes', 'write'),
        ('cad_fornecedores', 'write'),
        ('cad_itens', 'write'),
        ('compras', 'read'),
        ('compras', 'write'),
        ('compras', 'approve'),
        ('compras', 'receive')
    ) as p(resource, action)
    where upper(trim(coalesce(r.name, ''))) = 'FATURAMENTO'
    on conflict do nothing;
  end if;
end$$;

create or replace function public.get_full_permissions(p_tenant_id uuid, p_empresa_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'a'
as $$
declare
  v_usuario_id uuid;
  v_tenant_papel text;
  v_empresa_papel text;
  v_perm_extra jsonb;
  v_perm_negadas jsonb;
  v_empresa_papel_norm text;
  v_negadas text[];
  base_perms jsonb := '{}'::jsonb;
  extra_perms jsonb := '{}'::jsonb;
  result_perms jsonb;
begin
  select u.id
    into v_usuario_id
  from a.usuario u
  where u.auth_user_id = auth.uid()
    and u.deleted_at is null
  limit 1;

  if v_usuario_id is null then
    return '{}'::jsonb;
  end if;

  select ut.papel
    into v_tenant_papel
  from a.usuario_tenant ut
  where ut.usuario_id = v_usuario_id
    and ut.tenant_id = p_tenant_id
    and ut.ativo = true
    and ut.deleted_at is null
  limit 1;

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

  v_empresa_papel_norm := upper(coalesce(v_empresa_papel, ''));

  extra_perms := extra_perms || jsonb_build_object(
    'modulo_preferencial',
    case v_empresa_papel_norm
      when 'ADMIN' then 'admin'
      when 'FINANCEIRO' then 'financeiro'
      when 'FATURAMENTO' then 'faturamento'
      when 'COORDENACAO' then 'projetos'
      when 'COMPRAS' then 'estoque'
      when 'ALMOXARIFADO' then 'estoque'
      when 'APONTAMENTO_RH' then 'projetos'
      else null
    end
  );

  if v_empresa_papel_norm in ('ADMIN','COORDENACAO','FATURAMENTO') then
    extra_perms := extra_perms || jsonb_build_object(
      'os.read', true,
      'os.write', true,
      'os.delete', true,
      'os_itens.write', true,
      'os_gestao.write', true,
      'os_rpcs.execute', true
    );
  elsif v_empresa_papel_norm = 'APONTAMENTO_RH' then
    extra_perms := extra_perms || jsonb_build_object(
      'os.read', true,
      'os.write', true
    );
  end if;

  if v_empresa_papel_norm in ('ADMIN','FINANCEIRO') then
    extra_perms := extra_perms || jsonb_build_object(
      'financeiro.read', true,
      'financeiro.write', true,
      'faturamento.read', true,
      'faturamento.write', true,
      'faturamento.nfe.import_xml', true
    );
  end if;

  if v_empresa_papel_norm = 'FATURAMENTO' then
    extra_perms := extra_perms || jsonb_build_object(
      'faturamento.read', true,
      'faturamento.write', true,
      'faturamento.nfe.import_xml', true,
      'xml_import_faturamento.execute', true
    );
  end if;

  if v_empresa_papel_norm in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH','FATURAMENTO') then
    extra_perms := extra_perms || jsonb_build_object('estoque.read', true);
  end if;

  if v_empresa_papel_norm in ('ADMIN','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH','COORDENACAO','FATURAMENTO') then
    extra_perms := extra_perms || jsonb_build_object('estoque.write', true);
  end if;

  if v_empresa_papel_norm in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH','FATURAMENTO') then
    extra_perms := extra_perms || jsonb_build_object('imobilizado.read', true);
  end if;

  if v_empresa_papel_norm in ('ADMIN','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH','FATURAMENTO') then
    extra_perms := extra_perms || jsonb_build_object('imobilizado.write', true);
  end if;

  if v_empresa_papel_norm in ('ALMOXARIFADO','APONTAMENTO_RH','COORDENACAO','FINANCEIRO','FATURAMENTO') then
    extra_perms := extra_perms || jsonb_build_object(
      'xml_import.execute', true,
      'nf_entrada.import', true,
      'cad_fornecedores.write', true,
      'cad_itens.write', true
    );
  end if;

  if v_empresa_papel_norm = 'FATURAMENTO' then
    extra_perms := extra_perms || jsonb_build_object(
      'estoque_custos.cost_read', true,
      'fiscal_nf.read', true,
      'fiscal_nf.write', true,
      'fiscal_nf.delete', true,
      'fiscal_itens.write', true,
      'apontamentos.read', true,
      'apontamentos.write', true,
      'apontamentos.delete', true,
      'apontamentos.config', true,
      'cad_clientes.write', true,
      'compras.read', true,
      'compras.write', true,
      'compras.approve', true,
      'compras.receive', true
    );
  end if;

  if v_perm_extra is not null then
    extra_perms := extra_perms || v_perm_extra;
  end if;

  result_perms := base_perms || extra_perms;

  if v_perm_negadas is not null then
    select array_agg(key)
      into v_negadas
    from jsonb_object_keys(v_perm_negadas) as key;

    if v_negadas is not null then
      result_perms := result_perms - v_negadas;
    end if;
  end if;

  return coalesce(result_perms, '{}'::jsonb);
end;
$$;

create or replace function public.can(p_resource text, p_action text, p_tenant_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public', 'a', 'c'
as $$
declare
  v_auth_user_id uuid;
  v_usuario_id uuid;
  v_papel_tenant text;
  v_papel_empresa text;
  v_empresa_id uuid;
begin
  v_auth_user_id := auth.uid();
  if v_auth_user_id is null then
    return false;
  end if;

  select u.id
    into v_usuario_id
  from a.usuario u
  where u.auth_user_id = v_auth_user_id
    and u.ativo = true
    and u.deleted_at is null
  limit 1;

  if v_usuario_id is null then
    return false;
  end if;

  select ut.papel
    into v_papel_tenant
  from a.usuario_tenant ut
  where ut.usuario_id = v_usuario_id
    and ut.tenant_id = p_tenant_id
    and ut.ativo = true
    and ut.deleted_at is null
  order by ut.updated_at desc nulls last, ut.created_at desc nulls last
  limit 1;

  if v_papel_tenant is null then
    return false;
  end if;

  if v_papel_tenant in ('ADMIN','OWNER') then
    return true;
  end if;

  v_empresa_id := public.current_empresa_id();

  if v_empresa_id is not null then
    select ue.papel
      into v_papel_empresa
    from a.usuario_empresa ue
    where ue.usuario_id = v_usuario_id
      and ue.empresa_id = v_empresa_id
      and ue.ativo = true
      and ue.deleted_at is null
    limit 1;
  end if;

  v_papel_empresa := upper(coalesce(v_papel_empresa, ''));

  if v_papel_empresa = 'FATURAMENTO' then
    if p_resource = 'admin' and p_action = 'manage_users' then
      return false;
    end if;

    if (p_resource, p_action) in (
      values
        ('os', 'read'),
        ('os', 'write'),
        ('os', 'delete'),
        ('os_itens', 'write'),
        ('os_gestao', 'write'),
        ('os_rpcs', 'execute'),
        ('estoque', 'read'),
        ('estoque', 'write'),
        ('estoque_custos', 'cost_read'),
        ('fiscal_nf', 'read'),
        ('fiscal_nf', 'write'),
        ('fiscal_nf', 'delete'),
        ('fiscal_itens', 'write'),
        ('xml_import', 'execute'),
        ('xml_import_faturamento', 'execute'),
        ('nf_entrada', 'import'),
        ('faturamento', 'read'),
        ('faturamento', 'write'),
        ('faturamento', 'nfe.import_xml'),
        ('imobilizado', 'read'),
        ('imobilizado', 'write'),
        ('apontamentos', 'read'),
        ('apontamentos', 'write'),
        ('apontamentos', 'delete'),
        ('apontamentos', 'config'),
        ('cad_clientes', 'write'),
        ('cad_fornecedores', 'write'),
        ('cad_itens', 'write'),
        ('compras', 'read'),
        ('compras', 'write'),
        ('compras', 'approve'),
        ('compras', 'receive')
    ) then
      return true;
    end if;
  end if;

  if p_resource = 'xml_import' and p_action = 'execute' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COORDENACAO', 'FINANCEIRO', 'ADMIN') then
      return true;
    end if;
  end if;

  if p_resource = 'xml_import_faturamento' and p_action = 'execute' then
    if v_papel_empresa in ('FINANCEIRO', 'ADMIN') then
      return true;
    end if;
  end if;

  if p_resource = 'nf_entrada' and p_action = 'import' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COORDENACAO', 'FINANCEIRO', 'ADMIN') then
      return true;
    end if;
  end if;

  if p_resource = 'faturamento' and p_action in ('read', 'write', 'nfe.import_xml') then
    if v_papel_empresa in ('FINANCEIRO', 'ADMIN') then
      return true;
    end if;
  end if;

  if p_resource = 'financeiro' and p_action in ('write', 'config') then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'FINANCEIRO', 'COORDENACAO', 'ADMIN') then
      return true;
    end if;
  end if;

  if p_resource = 'estoque' and p_action = 'write' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COMPRAS', 'COORDENACAO', 'ADMIN') then
      return true;
    end if;
  end if;

  if p_resource = 'estoque' and p_action = 'read' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COMPRAS', 'FINANCEIRO', 'COORDENACAO', 'ADMIN') then
      return true;
    end if;
  end if;

  if p_resource = 'compras' and p_action = 'read' then
    if v_papel_empresa in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS') then
      return true;
    end if;
  end if;

  if p_resource = 'compras' and p_action = 'write' then
    if v_papel_empresa in ('ADMIN','COORDENACAO','COMPRAS') then
      return true;
    end if;
  end if;

  if p_resource = 'compras' and p_action = 'approve' then
    if v_papel_empresa in ('ADMIN','FINANCEIRO','COORDENACAO') then
      return true;
    end if;
  end if;

  if p_resource = 'compras' and p_action = 'receive' then
    if v_papel_empresa in ('ADMIN','COORDENACAO','COMPRAS') then
      return true;
    end if;
  end if;

  if p_resource = 'admin' and p_action = 'manage_users' then
    return false;
  end if;

  return false;
end;
$$;

create or replace function public.can(p_resource text, p_action text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select public.can(p_resource, p_action, public.current_tenant_id());
$$;

create or replace function public.can_many(p_pairs jsonb)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(
    jsonb_object_agg(key, val),
    '{}'::jsonb
  )
  from (
    select
      case
        when elem ? 'key' then elem->>'key'
        else (elem->>'resource') || '.' || (elem->>'action')
      end as key,
      public.can(elem->>'resource', elem->>'action') as val
    from jsonb_array_elements(coalesce(p_pairs, '[]'::jsonb)) elem
    where jsonb_typeof(elem) = 'object'
  ) s;
$$;

create or replace function f.has_finance_access(
  p_tenant uuid default public.current_tenant_id(),
  p_empresa uuid default public.current_empresa_id()
)
returns boolean
language sql
stable
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
  select
    exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut on ut.usuario_id = u.id
      where u.auth_user_id = auth.uid()
        and ut.tenant_id = p_tenant
        and ut.ativo = true
        and ut.deleted_at is null
        and ut.papel in ('OWNER','ADMIN')
        and u.deleted_at is null
    )
    or
    exists (
      select 1
      from a.usuario u
      join a.usuario_empresa ue on ue.usuario_id = u.id
      join c.empresa e on e.id = ue.empresa_id
      where u.auth_user_id = auth.uid()
        and ue.empresa_id = p_empresa
        and ue.ativo = true
        and ue.deleted_at is null
        and ue.papel in ('ADMIN','FINANCEIRO','FATURAMENTO')
        and e.deleted_at is null
        and e.tenant_id = p_tenant
        and u.deleted_at is null
    );
$$;

create or replace function f.has_motivo_compra_access(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'a', 'c', 'f'
set row_security to 'off'
as $$
  select exists (
    select 1
    from a.usuario u
    join a.usuario_empresa ue on ue.usuario_id = u.id
    join c.empresa e on e.id = ue.empresa_id
    where u.auth_user_id = auth.uid()
      and u.deleted_at is null
      and ue.ativo is true
      and ue.deleted_at is null
      and e.deleted_at is null
      and e.tenant_id = p_tenant_id
      and upper(trim(coalesce(ue.papel, ''))) in (
        'ADMIN',
        'FINANCEIRO',
        'FATURAMENTO',
        'COORDENACAO',
        'COMPRAS',
        'ALMOXARIFADO',
        'APONTAMENTO_RH'
      )
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
set search_path to 'c', 'public', 'a'
set row_security to 'off'
as $$
  select
    exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut on ut.usuario_id = u.id
      where u.auth_user_id = auth.uid()
        and ut.tenant_id = p_tenant
        and ut.ativo = true
        and ut.deleted_at is null
        and ut.papel in ('OWNER','ADMIN')
        and u.deleted_at is null
    )
    or
    exists (
      select 1
      from a.usuario u
      join a.usuario_empresa ue on ue.usuario_id = u.id
      join c.empresa e on e.id = ue.empresa_id
      where u.auth_user_id = auth.uid()
        and ue.empresa_id = p_empresa
        and ue.ativo = true
        and ue.deleted_at is null
        and ue.papel in ('ADMIN','FINANCEIRO','FATURAMENTO','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH')
        and e.deleted_at is null
        and e.tenant_id = p_tenant
        and u.deleted_at is null
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
set search_path to 'c', 'public', 'a'
set row_security to 'off'
as $$
  with me as (
    select coalesce(nullif(auth.jwt() ->> 'sub','')::uuid, auth.uid()) as auth_user_id
  )
  select
    me.auth_user_id is not null
    and (
      exists (
        select 1
        from a.usuario u
        join a.usuario_tenant ut on ut.usuario_id = u.id
        where u.auth_user_id = me.auth_user_id
          and ut.tenant_id = p_tenant
          and ut.ativo = true
          and ut.deleted_at is null
          and ut.papel in ('OWNER','ADMIN','GESTOR')
          and u.deleted_at is null
      )
      or exists (
        select 1
        from a.usuario u
        join a.usuario_empresa ue on ue.usuario_id = u.id
        join c.empresa e on e.id = ue.empresa_id
        where u.auth_user_id = me.auth_user_id
          and ue.empresa_id = p_empresa
          and ue.ativo = true
          and ue.deleted_at is null
          and ue.papel in ('ADMIN','COORDENACAO','COMPRAS','TECNICO','FINANCEIRO','FATURAMENTO')
          and e.deleted_at is null
          and e.tenant_id = p_tenant
          and u.deleted_at is null
      )
    )
  from me;
$$;

create or replace function c.has_compras_access(
  p_tenant uuid default public.current_tenant_id(),
  p_empresa uuid default public.current_empresa_id()
)
returns boolean
language sql
stable
security definer
set search_path to 'c', 'public', 'a'
set row_security to 'off'
as $$
  with me as (
    select coalesce(nullif(auth.jwt() ->> 'sub','')::uuid, auth.uid()) as auth_user_id
  )
  select
    me.auth_user_id is not null
    and (
      exists (
        select 1
        from a.usuario u
        join a.usuario_tenant ut on ut.usuario_id = u.id
        where u.auth_user_id = me.auth_user_id
          and ut.tenant_id = p_tenant
          and ut.ativo = true
          and ut.deleted_at is null
          and ut.papel in ('OWNER','ADMIN','GESTOR')
          and u.deleted_at is null
      )
      or exists (
        select 1
        from a.usuario u
        join a.usuario_empresa ue on ue.usuario_id = u.id
        join c.empresa e on e.id = ue.empresa_id
        where u.auth_user_id = me.auth_user_id
          and ue.empresa_id = p_empresa
          and ue.ativo = true
          and ue.deleted_at is null
          and ue.papel in ('ADMIN','FINANCEIRO','FATURAMENTO','COORDENACAO','COMPRAS')
          and e.deleted_at is null
          and e.tenant_id = p_tenant
          and u.deleted_at is null
      )
    )
  from me;
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
set search_path to 'public', 'a'
as $$
declare
  v_usuario_id uuid;
  v_tenant_papel text;
  v_item jsonb;
  v_empresa_id uuid;
  v_empresa_papel text;
  v_empresa_ativo boolean;
begin
  if not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;

  v_tenant_papel := upper(trim(coalesce(p_tenant_papel,'GESTOR')));
  if v_tenant_papel not in ('OWNER','ADMIN','CONTADOR','GESTOR') then
    raise exception 'invalid_tenant_role: %', v_tenant_papel;
  end if;

  insert into a.usuario (
    id, auth_user_id, nome, email, telefone, ativo,
    created_at, updated_at, created_by, updated_by, deleted_at
  )
  values (
    gen_random_uuid(),
    p_auth_user_id,
    nullif(trim(coalesce(p_nome,'')), ''),
    lower(trim(coalesce(p_email,''))),
    nullif(regexp_replace(coalesce(p_telefone,''), '\D', '', 'g'), ''),
    true,
    now(), now(), auth.uid(), auth.uid(), null
  )
  on conflict (auth_user_id)
  do update set
    nome = excluded.nome,
    email = excluded.email,
    telefone = excluded.telefone,
    ativo = true,
    updated_at = now(),
    updated_by = auth.uid(),
    deleted_at = null
  returning id into v_usuario_id;

  insert into a.usuario_tenant (
    id, usuario_id, tenant_id, papel, ativo,
    created_at, updated_at, created_by, updated_by, deleted_at
  )
  values (
    gen_random_uuid(), v_usuario_id, p_tenant_id, v_tenant_papel, true,
    now(), now(), auth.uid(), auth.uid(), null
  )
  on conflict (usuario_id, tenant_id) where deleted_at is null
  do update set
    papel = excluded.papel,
    ativo = true,
    updated_at = now(),
    updated_by = auth.uid(),
    deleted_at = null;

  if p_empresa_vinculos is not null and jsonb_typeof(p_empresa_vinculos) = 'array' then
    for v_item in select * from jsonb_array_elements(p_empresa_vinculos)
    loop
      v_empresa_id := (v_item->>'empresa_id')::uuid;
      v_empresa_papel := upper(trim(coalesce(v_item->>'papel','TECNICO')));
      v_empresa_ativo := coalesce((v_item->>'ativo')::boolean, true);

      if v_empresa_papel not in (
        'ADMIN','FINANCEIRO','FATURAMENTO','COORDENACAO','COMPRAS','ALMOXARIFADO','TECNICO','APONTAMENTO_RH','PAINEL_TV'
      ) then
        raise exception 'invalid_empresa_role: %', v_empresa_papel;
      end if;

      perform 1 from public.empresas e where e.id = v_empresa_id and e.tenant_id = p_tenant_id;
      if not found then
        raise exception 'empresa_not_in_tenant';
      end if;

      insert into a.usuario_empresa (
        id, usuario_id, empresa_id, papel, ativo,
        permissoes_extra, permissoes_negadas,
        created_at, updated_at, created_by, updated_by, deleted_at
      )
      values (
        gen_random_uuid(), v_usuario_id, v_empresa_id, v_empresa_papel, v_empresa_ativo,
        null, null,
        now(), now(), auth.uid(), auth.uid(), null
      )
      on conflict (usuario_id, empresa_id) where deleted_at is null
      do update set
        papel = excluded.papel,
        ativo = excluded.ativo,
        updated_at = now(),
        updated_by = auth.uid(),
        deleted_at = null;
    end loop;
  end if;

  return v_usuario_id;
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
set search_path to 'public', 'a'
as $$
declare
  v_empresa_tenant uuid;
  v_papel text;
begin
  if not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;

  select e.tenant_id
    into v_empresa_tenant
  from public.empresas e
  where e.id = p_empresa_id;

  if v_empresa_tenant is null then
    raise exception 'empresa_not_found';
  end if;

  if v_empresa_tenant <> p_tenant_id then
    raise exception 'empresa_not_in_tenant';
  end if;

  v_papel := upper(trim(coalesce(p_papel, 'TECNICO')));

  if v_papel not in (
    'ADMIN',
    'FINANCEIRO',
    'FATURAMENTO',
    'COORDENACAO',
    'COMPRAS',
    'ALMOXARIFADO',
    'TECNICO',
    'APONTAMENTO_RH',
    'PAINEL_TV'
  ) then
    raise exception 'invalid_empresa_role: %', v_papel;
  end if;

  insert into a.usuario_empresa (
    id, usuario_id, empresa_id, papel, ativo,
    permissoes_extra, permissoes_negadas,
    created_at, updated_at, created_by, updated_by, deleted_at
  )
  values (
    gen_random_uuid(), p_usuario_id, p_empresa_id, v_papel, coalesce(p_ativo,true),
    null, null,
    now(), now(), auth.uid(), auth.uid(), null
  )
  on conflict (usuario_id, empresa_id) where deleted_at is null
  do update set
    papel = excluded.papel,
    ativo = excluded.ativo,
    updated_at = now(),
    updated_by = auth.uid(),
    deleted_at = null;
end;
$$;

grant execute on function public.get_full_permissions(uuid, uuid) to anon, authenticated, service_role;
grant execute on function public.can(text, text) to anon, authenticated, service_role;
grant execute on function public.can(text, text, uuid) to anon, authenticated, service_role;
grant execute on function public.can_many(jsonb) to anon, authenticated, service_role;
grant execute on function f.has_finance_access(uuid, uuid) to authenticated, service_role;
grant execute on function f.has_motivo_compra_access(uuid) to authenticated, service_role;
grant execute on function c.has_imobilizado_access(uuid, uuid) to authenticated, service_role;
grant execute on function c.has_comercial_access(uuid, uuid) to authenticated, service_role;
grant execute on function c.has_compras_access(uuid, uuid) to authenticated, service_role;
grant execute on function public.admin_finalize_invited_user(uuid, uuid, text, text, text, text, jsonb) to authenticated, service_role;
grant execute on function public.admin_set_user_empresa(uuid, uuid, uuid, text, boolean) to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
