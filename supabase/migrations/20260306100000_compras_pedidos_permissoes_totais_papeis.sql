begin;

-- Compras/Pedidos: liberar todas as acoes para os papeis
-- ADMIN, FINANCEIRO, COORDENACAO e COMPRAS.
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
  if v_auth_user_id is null then return false; end if;

  select u.id into v_usuario_id
  from a.usuario u
  where u.auth_user_id = v_auth_user_id
    and u.ativo = true
    and u.deleted_at is null
  limit 1;
  if v_usuario_id is null then return false; end if;

  select ut.papel into v_papel_tenant
  from a.usuario_tenant ut
  where ut.usuario_id = v_usuario_id
    and ut.tenant_id = p_tenant_id
    and ut.ativo = true
    and ut.deleted_at is null
  order by ut.updated_at desc nulls last, ut.created_at desc nulls last
  limit 1;
  if v_papel_tenant is null then return false; end if;

  if v_papel_tenant in ('ADMIN','OWNER') then return true; end if;

  v_empresa_id := public.current_empresa_id();
  if v_empresa_id is not null then
    select ue.papel into v_papel_empresa
    from a.usuario_empresa ue
    where ue.usuario_id = v_usuario_id
      and ue.empresa_id = v_empresa_id
      and ue.ativo = true
      and ue.deleted_at is null
    limit 1;
  end if;

  if p_resource = 'xml_import' and p_action = 'execute' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COORDENACAO', 'FINANCEIRO', 'COMPRAS', 'ADMIN') then return true; end if;
  end if;
  if p_resource = 'nf_entrada' and p_action = 'import' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COORDENACAO', 'FINANCEIRO', 'COMPRAS', 'ADMIN') then return true; end if;
  end if;
  if p_resource = 'financeiro' and p_action in ('write', 'config') then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'FINANCEIRO', 'COORDENACAO', 'COMPRAS', 'ADMIN') then return true; end if;
  end if;
  if p_resource = 'estoque' and p_action = 'write' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COMPRAS', 'COORDENACAO', 'ADMIN') then return true; end if;
  end if;
  if p_resource = 'estoque' and p_action = 'read' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COMPRAS', 'FINANCEIRO', 'COORDENACAO', 'ADMIN') then return true; end if;
  end if;

  if p_resource = 'compras' and p_action in ('read', 'write', 'approve', 'receive') then
    if v_papel_empresa in ('ADMIN', 'FINANCEIRO', 'COORDENACAO', 'COMPRAS') then return true; end if;
  end if;

  if p_resource = 'admin' and p_action = 'manage_users' then return false; end if;
  return false;
end;
$$;

commit;
