begin;

-- O papel FINANCEIRO pode consultar custos e totais das ordens de servico.
-- A policy restritiva adicionada em 20260810120000 passou a exigir
-- apontamentos.read e, sem esta capacidade, as horas existentes eram
-- silenciosamente filtradas pelo RLS. Mantemos escrita e exclusao restritas.
create or replace function public.get_full_permissions(
  p_tenant_id uuid,
  p_empresa_id uuid
)
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

  if v_empresa_papel = 'FINANCEIRO'
     and not coalesce(
       jsonb_typeof(v_negadas) = 'object'
       and v_negadas ? 'apontamentos.read',
       false
     ) then
    v_result := v_result || jsonb_build_object('apontamentos.read', true);
  end if;

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

create or replace function public.can(
  p_resource text,
  p_action text,
  p_tenant_id uuid
)
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

  if v_empresa_papel = 'FINANCEIRO'
     and lower(coalesce(p_resource, '')) = 'apontamentos'
     and lower(coalesce(p_action, '')) = 'read' then
    return coalesce(
      public.get_full_permissions(p_tenant_id, v_empresa_id)
        @> jsonb_build_object('apontamentos.read', true),
      false
    );
  end if;

  return public.can_unscoped_20260810(p_resource, p_action, p_tenant_id);
end;
$$;

revoke all on function public.get_full_permissions(uuid, uuid) from public, anon;
grant execute on function public.get_full_permissions(uuid, uuid) to authenticated, service_role;
revoke all on function public.can(text, text, uuid) from public, anon;
grant execute on function public.can(text, text, uuid) to authenticated, service_role;

do $assertions$
begin
  if position(
    'apontamentos.read'
    in pg_get_functiondef('public.get_full_permissions(uuid,uuid)'::regprocedure)
  ) = 0 then
    raise exception 'financeiro_apontamentos_read_permission_not_installed';
  end if;

  if position(
    'v_empresa_papel = ''FINANCEIRO'''
    in pg_get_functiondef('public.can(text,text,uuid)'::regprocedure)
  ) = 0 then
    raise exception 'financeiro_apontamentos_read_gate_not_installed';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
