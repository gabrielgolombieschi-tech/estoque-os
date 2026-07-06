-- A migration 20260705120000_cadastro_empresa_sgu_automacao.sql cadastrou a
-- SGU AUTOMACAO e copiou os vinculos em a.usuario_empresa, mas nao criou
-- linhas correspondentes em public.empresa_memberships. Essa tabela e a
-- fonte usada pelo contexto do usuario logado (TenantEmpresaProvider ->
-- te.empresas) para montar a lista de "Empresas" editaveis na tela
-- /admin/usuarios, entao a SGU nunca aparecia la para ninguem, mesmo com o
-- vinculo ativo em a.usuario_empresa (que so afeta o RLS/permissoes reais).
--
-- Cria as linhas de empresa_memberships apenas para os 4 usuarios que devem
-- ter acesso a SGU AUTOMACAO (mesmos da migration 20260706100000).
--
-- Idempotente: pode ser reaplicada sem duplicar dados (unique constraint em
-- tenant_id, empresa_id, user_id).

do $$
declare
  v_tenant_id uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'; -- tenant "Segau"
  v_sgu_empresa_id uuid;
  v_emails_com_acesso text[] := array[
    'gabriel@segau.com.br',
    'larissa@segau.com.br',
    'deyvison@segau.com.br',
    'vanessa@segau.com.br'
  ];
  v_inseridos int := 0;
begin
  select id into v_sgu_empresa_id
  from c.empresa
  where tenant_id = v_tenant_id and codigo = 'SGU' and deleted_at is null
  limit 1;

  if v_sgu_empresa_id is null then
    raise exception 'empresa SGU nao encontrada para o tenant % - abortando', v_tenant_id;
  end if;

  insert into public.empresa_memberships (tenant_id, empresa_id, user_id, role, status)
  select v_tenant_id, v_sgu_empresa_id, u.auth_user_id, 'user', 'active'
  from a.usuario u
  where lower(u.email) in (select lower(e) from unnest(v_emails_com_acesso) as e)
    and u.auth_user_id is not null
    and u.deleted_at is null
  on conflict (tenant_id, empresa_id, user_id) do nothing;

  get diagnostics v_inseridos = row_count;

  raise notice 'SGU empresa_memberships ok: empresa_id=%, inseridos=%',
    v_sgu_empresa_id, v_inseridos;
end $$;
