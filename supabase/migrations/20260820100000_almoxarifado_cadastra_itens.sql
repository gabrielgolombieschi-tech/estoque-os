begin;

set local role postgres;

-- Almoxarifado ja pode dar entrada de NF e mexer em estoque, mas nao tinha
-- permissao de cad_itens.write: ao tentar usar o "Novo item com agente de
-- cadastro" a pessoa esbarrava em "Sem permissao para cadastrar itens.".
-- Como e o almoxarifado quem recebe material novo sem item correspondente no
-- cadastro, faz sentido esse papel poder cadastrar itens tambem.

create or replace function public.can_unscoped_20260810(p_resource text, p_action text, p_tenant_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public', 'a', 'c'
as $function$
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

  if v_papel_tenant in ('ADMIN','DIRETOR','OWNER') then
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

  if p_resource = 'cad_itens' and p_action = 'write' then
    if v_papel_empresa in ('ALMOXARIFADO', 'ADMIN') then
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
$function$;

notify pgrst, 'reload schema';

commit;
