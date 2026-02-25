begin;

-- Root fix: ensure XML import permission matrix includes COMPRAS and
-- post-import fiscal document flow accepts xml_import.execute users.

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
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'FINANCEIRO', 'COORDENACAO', 'ADMIN') then return true; end if;
  end if;
  if p_resource = 'estoque' and p_action = 'write' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COMPRAS', 'COORDENACAO', 'ADMIN') then return true; end if;
  end if;
  if p_resource = 'estoque' and p_action = 'read' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COMPRAS', 'FINANCEIRO', 'COORDENACAO', 'ADMIN') then return true; end if;
  end if;

  if p_resource = 'compras' and p_action = 'read' then
    if v_papel_empresa in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS') then return true; end if;
  end if;
  if p_resource = 'compras' and p_action = 'write' then
    if v_papel_empresa in ('ADMIN','COORDENACAO','COMPRAS') then return true; end if;
  end if;
  if p_resource = 'compras' and p_action = 'approve' then
    if v_papel_empresa in ('ADMIN','FINANCEIRO','COORDENACAO') then return true; end if;
  end if;
  if p_resource = 'compras' and p_action = 'receive' then
    if v_papel_empresa in ('ADMIN','COORDENACAO','COMPRAS') then return true; end if;
  end if;

  if p_resource = 'admin' and p_action = 'manage_users' then return false; end if;
  return false;
end;
$$;

create or replace function f.fn_find_documento_fiscal_from_import(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_nf_entrada_id bigint,
  p_chave_acesso text
)
returns uuid
language plpgsql
security definer
set search_path = f, public, a, c, extensions
set row_security to off
as $$
declare
  v_nf public.nf_entrada%rowtype;
  v_doc_id uuid;
  v_competencia date;
  v_xml_hash text;
begin
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  if p_nf_entrada_id is null and (p_chave_acesso is null or length(trim(p_chave_acesso)) = 0) then
    raise exception 'Informe p_nf_entrada_id ou p_chave_acesso';
  end if;

  if p_nf_entrada_id is not null then
    select * into v_nf
    from public.nf_entrada
    where id = p_nf_entrada_id;
  else
    select * into v_nf
    from public.nf_entrada
    where chave = p_chave_acesso
    limit 1;
  end if;

  if not found then
    raise exception 'NF entrada nao encontrada';
  end if;

  if p_tenant_id is not null and v_nf.tenant_id <> p_tenant_id then
    raise exception 'Tenant mismatch';
  end if;

  if p_empresa_id is not null and v_nf.empresa_id <> p_empresa_id then
    raise exception 'Empresa mismatch';
  end if;

  -- Allow finance users OR xml import executors.
  if auth.uid() is not null then
    if not f.has_finance_access(v_nf.tenant_id, v_nf.empresa_id)
       and not public.can('xml_import', 'execute', v_nf.tenant_id)
    then
      raise exception 'Sem permissao para importacao XML';
    end if;
  end if;

  v_competencia := date_trunc(
    'month',
    coalesce((v_nf.data_emissao at time zone 'America/Sao_Paulo')::date, current_date)
  )::date;

  insert into f.documento_fiscal (
    tenant_id, empresa_id, source_nf_entrada_id,
    fornecedor_id, chave_acesso,
    modelo, serie, numero,
    emissao_date, competencia_date,
    valor_total, valor_produtos, valor_frete, valor_seguro, valor_desconto, valor_outros,
    finalidade_import, os_id_import,
    pagamento_import_json
  )
  values (
    v_nf.tenant_id, v_nf.empresa_id, v_nf.id,
    v_nf.fornecedor_id::int, v_nf.chave,
    null, v_nf.serie, v_nf.numero,
    (v_nf.data_emissao at time zone 'America/Sao_Paulo')::date,
    v_competencia,
    coalesce(v_nf.valor_total, 0),
    coalesce(v_nf.valor_produtos, 0),
    coalesce(v_nf.valor_frete, 0),
    coalesce(v_nf.valor_seguro, 0),
    coalesce(v_nf.valor_desconto, 0),
    coalesce(v_nf.valor_outros, 0),
    v_nf.finalidade_contexto,
    v_nf.os_id,
    null
  )
  on conflict (tenant_id, source_nf_entrada_id)
  do update set
    empresa_id = excluded.empresa_id,
    fornecedor_id = excluded.fornecedor_id,
    chave_acesso = excluded.chave_acesso,
    serie = excluded.serie,
    numero = excluded.numero,
    emissao_date = excluded.emissao_date,
    competencia_date = excluded.competencia_date,
    valor_total = excluded.valor_total,
    valor_produtos = excluded.valor_produtos,
    valor_frete = excluded.valor_frete,
    valor_seguro = excluded.valor_seguro,
    valor_desconto = excluded.valor_desconto,
    valor_outros = excluded.valor_outros,
    finalidade_import = excluded.finalidade_import,
    os_id_import = excluded.os_id_import,
    updated_at = now(),
    updated_by = a.fn_current_usuario_id()
  returning id into v_doc_id;

  if v_nf.xml_raw is not null and length(v_nf.xml_raw) > 0 then
    v_xml_hash := encode(extensions.digest(convert_to(v_nf.xml_raw, 'utf8'), 'sha256'), 'hex');

    insert into f.documento_fiscal_xml (tenant_id, documento_fiscal_id, chave_acesso, xml_raw, xml_hash)
    values (v_nf.tenant_id, v_doc_id, v_nf.chave, v_nf.xml_raw, v_xml_hash)
    on conflict (tenant_id, documento_fiscal_id) do update set
      xml_raw = excluded.xml_raw,
      xml_hash = excluded.xml_hash;
  end if;

  return v_doc_id;
end;
$$;

revoke all on function f.fn_find_documento_fiscal_from_import(uuid, uuid, bigint, text) from public;
grant execute on function f.fn_find_documento_fiscal_from_import(uuid, uuid, bigint, text) to authenticated;

with roles_norm as (
  select
    id,
    lower(coalesce(name, '')) as name_norm
  from public.roles
),
target_roles as (
  select id
  from roles_norm
  where name_norm like 'admin%'
     or name_norm like 'financeir%'
     or name_norm like 'coord%'
     or name_norm like 'coorden%'
     or name_norm like 'compras%'
     or name_norm like 'almox%'
     or name_norm like 'estoque%'
),
rules(resource, action) as (
  values
    ('xml_import', 'execute'),
    ('nf_entrada', 'import')
)
insert into public.role_access_rules (role_id, resource, action)
select tr.id, r.resource, r.action
from target_roles tr
cross join rules r
on conflict do nothing;

commit;
