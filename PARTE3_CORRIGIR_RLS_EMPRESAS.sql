-- =====================================================================
-- PARTE 3: CORRIGIR POLÍTICAS RLS PARA EMPRESAS
-- =====================================================================
-- Problema: A política de SELECT em empresas pode estar bloqueando
-- porque depende de current_empresa_id(), criando loop infinito
-- =====================================================================

begin;

-- ====================================================================
-- 1. Remover políticas antigas da tabela empresas
-- ====================================================================

drop policy if exists empresas_select on public.empresas;
drop policy if exists empresas_insert on public.empresas;
drop policy if exists empresas_update on public.empresas;
drop policy if exists empresas_delete on public.empresas;
drop policy if exists tenant_empresa_select_empresas on public.empresas;
drop policy if exists tenant_empresa_insert_empresas on public.empresas;
drop policy if exists tenant_empresa_update_empresas on public.empresas;
drop policy if exists tenant_empresa_delete_empresas on public.empresas;

-- ====================================================================
-- 2. Criar políticas novas SEM depender de current_empresa_id()
-- ====================================================================

-- SELECT: Usuário vê empresas do seu tenant via empresa_memberships
create policy empresas_select on public.empresas
  for select
  using (
    tenant_id = public.current_tenant_id()
    OR exists (
      select 1
      from public.empresa_memberships em
      where em.empresa_id = empresas.id
        and em.user_id = auth.uid()
        and em.status = 'active'
    )
  );

-- INSERT: Apenas admin pode criar empresas
create policy empresas_insert on public.empresas
  for insert
  with check (
    tenant_id = public.current_tenant_id()
    and public.has_permission('admin.manage_users')
  );

-- UPDATE: Apenas admin pode atualizar empresas
create policy empresas_update on public.empresas
  for update
  using (
    tenant_id = public.current_tenant_id()
    and public.has_permission('admin.manage_users')
  )
  with check (
    tenant_id = public.current_tenant_id()
    and public.has_permission('admin.manage_users')
  );

-- DELETE: Apenas admin pode deletar empresas
create policy empresas_delete on public.empresas
  for delete
  using (
    tenant_id = public.current_tenant_id()
    and public.has_permission('admin.manage_users')
  );

commit;

-- ====================================================================
-- FIM - Agora empresas podem ser consultadas sem loop infinito
-- ====================================================================
