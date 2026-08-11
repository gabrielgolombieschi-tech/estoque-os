-- OBSOLETO E BLOQUEADO: este script concede uma empresa padrao a todos os
-- usuarios e viola a fronteira definida na SGU. Nao executar.
do $script_obsoleto$
begin
  raise exception 'SCRIPT OBSOLETO: use as migrations versionadas de acesso por empresa';
end;
$script_obsoleto$;

-- =====================================================================
-- INSTRUÇÕES DE USO:
-- =====================================================================
-- 1. Acesse: https://supabase.com/dashboard/project/ptybnreejbkqwwozvhzb/sql/new
-- 2. Cole TODO este SQL abaixo
-- 3. Clique em "Run" ou pressione Ctrl+Enter
-- 4. Verifique os logs de sucesso
-- =====================================================================

-- COPIE TUDO ABAIXO DESTA LINHA:
-- =====================================================================

begin;

do $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_user_count int;
  v_membership_count int;
begin
  -- ====================================================================
  -- PASSO 1: Identificar o tenant padrão (o mais antigo)
  -- ====================================================================
  select id into v_tenant_id
  from public.tenants
  where ativo = true
  order by created_at asc nulls last
  limit 1;

  if v_tenant_id is null then
    raise exception 'Nenhum tenant ativo encontrado. Crie um tenant primeiro.';
  end if;

  raise notice 'Tenant identificado: %', v_tenant_id;

  -- ====================================================================
  -- PASSO 2: Buscar ou criar empresa "Elétrica Segau"
  -- ====================================================================
  select id into v_empresa_id
  from public.empresas
  where tenant_id = v_tenant_id
    and (
      razao_social ilike '%eletrica%segau%'
      or razao_social ilike '%segau%'
      or nome_fantasia ilike '%segau%'
    )
  limit 1;

  if v_empresa_id is null then
    -- Criar empresa se não existir
    insert into public.empresas (
      tenant_id,
      cnpj,
      razao_social,
      nome_fantasia,
      ativo,
      habilita_servico_hh
    ) values (
      v_tenant_id,
      '00.000.000/0001-00', -- CNPJ placeholder
      'ELÉTRICA SEGAU LTDA',
      'Elétrica Segau',
      true,
      true -- habilita HH
    )
    returning id into v_empresa_id;

    raise notice 'Empresa "Elétrica Segau" criada: %', v_empresa_id;
  else
    -- Atualizar para garantir que está ativa
    update public.empresas
    set ativo = true,
        habilita_servico_hh = true
    where id = v_empresa_id;

    raise notice 'Empresa "Elétrica Segau" encontrada: %', v_empresa_id;
  end if;

  -- ====================================================================
  -- PASSO 3: Vincular TODOS os usuários existentes à empresa
  -- ====================================================================
  
  -- Contar usuários existentes
  select count(*) into v_user_count
  from auth.users
  where deleted_at is null;

  raise notice 'Total de usuários ativos: %', v_user_count;

  -- Criar memberships para todos os usuários que ainda não têm
  insert into public.empresa_memberships (
    tenant_id,
    empresa_id,
    user_id,
    role,
    status
  )
  select
    v_tenant_id,
    v_empresa_id,
    u.id,
    'user', -- role padrão
    'active'
  from auth.users u
  where u.deleted_at is null
    and not exists (
      select 1
      from public.empresa_memberships em
      where em.user_id = u.id
        and em.tenant_id = v_tenant_id
        and em.empresa_id = v_empresa_id
    );

  get diagnostics v_membership_count = row_count;
  raise notice 'Novos memberships criados: %', v_membership_count;

  -- ====================================================================
  -- PASSO 4: Definir empresa padrão no contexto de TODOS os usuários
  -- ====================================================================
  
  insert into public.user_empresa_context (
    user_id,
    tenant_id,
    empresa_id,
    updated_at
  )
  select
    u.id,
    v_tenant_id,
    v_empresa_id,
    now()
  from auth.users u
  where u.deleted_at is null
  on conflict (user_id, tenant_id) do update
    set empresa_id = excluded.empresa_id,
        updated_at = now();

  raise notice 'Contexto de empresa atualizado para todos os usuários';

  -- ====================================================================
  -- PASSO 5: Garantir tenant_memberships para todos também
  -- ====================================================================
  
  insert into public.tenant_memberships (
    tenant_id,
    user_id,
    status,
    role
  )
  select
    v_tenant_id,
    u.id,
    'active',
    'admin' -- todos são admin por padrão
  from auth.users u
  where u.deleted_at is null
    and not exists (
      select 1
      from public.tenant_memberships tm
      where tm.user_id = u.id
        and tm.tenant_id = v_tenant_id
    );

  raise notice 'Tenant memberships verificados';

  -- ====================================================================
  -- RELATÓRIO FINAL
  -- ====================================================================
  raise notice '===========================================================';
  raise notice 'CONFIGURAÇÃO CONCLUÍDA COM SUCESSO!';
  raise notice '===========================================================';
  raise notice 'Tenant ID: %', v_tenant_id;
  raise notice 'Empresa ID (Elétrica Segau): %', v_empresa_id;
  raise notice 'Total de usuários: %', v_user_count;
  raise notice 'Novos memberships criados: %', v_membership_count;
  raise notice '===========================================================';
  raise notice 'TODOS OS USUÁRIOS AGORA ESTÃO VINCULADOS À ELÉTRICA SEGAU';
  raise notice '===========================================================';

end$$;

-- ====================================================================
-- TRIGGER: Vincular automaticamente novos usuários à Elétrica Segau
-- ====================================================================

create or replace function public.auto_assign_empresa_segau()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
begin
  -- Pegar tenant padrão
  select id into v_tenant_id
  from public.tenants
  where ativo = true
  order by created_at asc nulls last
  limit 1;

  if v_tenant_id is null then
    return NEW;
  end if;

  -- Pegar empresa Elétrica Segau
  select id into v_empresa_id
  from public.empresas
  where tenant_id = v_tenant_id
    and (
      razao_social ilike '%segau%'
      or nome_fantasia ilike '%segau%'
    )
    and ativo = true
  limit 1;

  if v_empresa_id is null then
    return NEW;
  end if;

  -- Criar tenant membership
  insert into public.tenant_memberships (
    tenant_id,
    user_id,
    status,
    role
  ) values (
    v_tenant_id,
    NEW.id,
    'active',
    'admin'
  )
  on conflict do nothing;

  -- Criar empresa membership
  insert into public.empresa_memberships (
    tenant_id,
    empresa_id,
    user_id,
    role,
    status
  ) values (
    v_tenant_id,
    v_empresa_id,
    NEW.id,
    'user',
    'active'
  )
  on conflict do nothing;

  -- Definir contexto padrão
  insert into public.user_empresa_context (
    user_id,
    tenant_id,
    empresa_id
  ) values (
    NEW.id,
    v_tenant_id,
    v_empresa_id
  )
  on conflict (user_id, tenant_id) do update
    set empresa_id = excluded.empresa_id,
        updated_at = now();

  return NEW;
end;
$$;

-- Remover trigger antigo se existir
drop trigger if exists on_auth_user_created_assign_empresa on auth.users;

-- Criar trigger para novos usuários
create trigger on_auth_user_created_assign_empresa
  after insert on auth.users
  for each row
  execute function public.auto_assign_empresa_segau();

commit;

-- ====================================================================
-- FIM DO SCRIPT - VERIFIQUE OS LOGS ACIMA
-- ====================================================================
