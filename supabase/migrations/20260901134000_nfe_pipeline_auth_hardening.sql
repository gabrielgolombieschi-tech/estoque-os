begin;

-- SECURITY DEFINER troca current_user pelo dono da funcao. A implementacao
-- privilegiada fica privada e um wrapper SECURITY INVOKER valida o chamador
-- real (JWT + tenant/empresa) antes de entrar nela.
alter function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text)
  rename to fn_faturar_documento_impl;

revoke all on function f.fn_faturar_documento_impl(uuid, uuid, integer, integer[], uuid, text, text)
  from public, anon, authenticated, service_role;

create function f.fn_faturar_documento(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_ov_id integer,
  p_os_item_ids integer[] default null,
  p_documento_fiscal_id uuid default gen_random_uuid(),
  p_ambiente text default 'HOMOLOGACAO',
  p_natureza_operacao text default 'VENDA_MERCADORIA_TERCEIROS'
)
returns table (
  documento_fiscal_id uuid,
  solicitacao_id uuid,
  referencia_externa text,
  status text,
  criado boolean
)
language plpgsql
security invoker
set search_path = pg_catalog
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
begin
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from p_tenant_id
    or public.current_empresa_id() is distinct from p_empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para faturar nesta empresa.';
  end if;

  return query
  select x.documento_fiscal_id, x.solicitacao_id, x.referencia_externa, x.status, x.criado
  from f.fn_faturar_documento_impl(
    p_tenant_id, p_empresa_id, p_ov_id, p_os_item_ids,
    p_documento_fiscal_id, p_ambiente, p_natureza_operacao
  ) x;
end;
$$;

alter function f.fn_nfe_contexto_emissao(uuid)
  rename to fn_nfe_contexto_emissao_impl;

revoke all on function f.fn_nfe_contexto_emissao_impl(uuid)
  from public, anon, authenticated, service_role;

create function f.fn_nfe_contexto_emissao(p_documento_fiscal_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog
stable
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_tenant_id uuid;
  v_empresa_id uuid;
begin
  select tenant_id, empresa_id into v_tenant_id, v_empresa_id
  from f.documento_fiscal_emissao
  where documento_fiscal_id = p_documento_fiscal_id;
  if not found then return null; end if;

  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_tenant_id
    or public.current_empresa_id() is distinct from v_empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar esta emissao.';
  end if;

  return f.fn_nfe_contexto_emissao_impl(p_documento_fiscal_id);
end;
$$;

create or replace function f.fn_nfe_configurar_agendador(
  p_project_url text,
  p_service_role_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_id uuid;
begin
  if coalesce(auth.jwt()->>'role', '') <> 'service_role' and session_user <> 'postgres' then
    raise exception using errcode = '42501', message = 'Somente service_role pode configurar o agendador.';
  end if;
  if p_project_url !~ '^https://[a-z0-9-]+\.supabase\.co$' then
    raise exception using errcode = '22023', message = 'URL do projeto Supabase invalida.';
  end if;
  if nullif(btrim(p_service_role_key), '') is null then
    raise exception using errcode = '22023', message = 'Service role key ausente.';
  end if;

  select id into v_id from vault.secrets where name = 'project_url' order by created_at desc limit 1;
  if v_id is null then
    perform vault.create_secret(p_project_url, 'project_url', 'URL usada pelo cron da reconciliacao NF-e');
  else
    perform vault.update_secret(v_id, p_project_url, 'project_url', 'URL usada pelo cron da reconciliacao NF-e');
  end if;

  select id into v_id from vault.secrets where name = 'service_role_key' order by created_at desc limit 1;
  if v_id is null then
    perform vault.create_secret(p_service_role_key, 'service_role_key', 'Credencial usada pelo cron da reconciliacao NF-e');
  else
    perform vault.update_secret(v_id, p_service_role_key, 'service_role_key', 'Credencial usada pelo cron da reconciliacao NF-e');
  end if;

  return jsonb_build_object(
    'configurado', true,
    'project_url', p_project_url,
    'service_role_key_armazenada', true
  );
end;
$$;

revoke all on function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text) from public, anon;
revoke all on function f.fn_nfe_contexto_emissao(uuid) from public, anon;
revoke all on function f.fn_nfe_configurar_agendador(text, text) from public, anon, authenticated;
grant execute on function f.fn_faturar_documento(uuid, uuid, integer, integer[], uuid, text, text) to authenticated, service_role;
grant execute on function f.fn_nfe_contexto_emissao(uuid) to authenticated, service_role;
grant execute on function f.fn_nfe_configurar_agendador(text, text) to service_role;

commit;
