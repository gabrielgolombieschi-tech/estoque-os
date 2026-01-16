-- =====================================================================
-- PARTE 5: SIMPLIFICAR RLS DE EMPRESA_MEMBERSHIPS
-- =====================================================================
-- O erro 500 em empresa_memberships indica problema de RLS
-- Vamos simplificar para permitir que usuário veja seus próprios dados
-- =====================================================================

begin;

-- ====================================================================
-- 1. Remover políticas antigas de empresa_memberships
-- ====================================================================

drop policy if exists empresa_memberships_select on public.empresa_memberships;
drop policy if exists empresa_memberships_insert on public.empresa_memberships;
drop policy if exists empresa_memberships_update on public.empresa_memberships;
drop policy if exists empresa_memberships_delete on public.empresa_memberships;

-- ====================================================================
-- 2. Criar política SUPER SIMPLES para SELECT
-- ====================================================================

-- Usuário vê APENAS seus próprios empresa_memberships
create policy empresa_memberships_select on public.empresa_memberships
  for select
  using (user_id = auth.uid());

-- Admin pode inserir/atualizar/deletar
create policy empresa_memberships_insert on public.empresa_memberships
  for insert
  with check (
    user_id = auth.uid()  -- Permitir auto-criação
    or exists (
      select 1 from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = empresa_memberships.tenant_id
        and tm.role = 'admin'
        and tm.status = 'active'
    )
  );

create policy empresa_memberships_update on public.empresa_memberships
  for update
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = empresa_memberships.tenant_id
        and tm.role = 'admin'
        and tm.status = 'active'
    )
  );

create policy empresa_memberships_delete on public.empresa_memberships
  for delete
  using (
    exists (
      select 1 from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = empresa_memberships.tenant_id
        and tm.role = 'admin'
        and tm.status = 'active'
    )
  );

commit;

-- ====================================================================
-- SUCESSO! Agora empresa_memberships deve carregar sem erro 500
-- ====================================================================
