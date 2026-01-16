-- =====================================================================
-- PARTE 4: SIMPLIFICAR RLS DE TENANT_MEMBERSHIPS
-- =====================================================================
-- O erro 500 em tenant_memberships indica problema de RLS
-- Vamos simplificar para permitir que usuário veja seus próprios dados
-- =====================================================================

begin;

-- ====================================================================
-- 1. Remover políticas antigas de tenant_memberships
-- ====================================================================

drop policy if exists tenant_memberships_select on public.tenant_memberships;
drop policy if exists tenant_memberships_insert on public.tenant_memberships;
drop policy if exists tenant_memberships_update on public.tenant_memberships;
drop policy if exists tenant_memberships_delete on public.tenant_memberships;
drop policy if exists tenant_memberships_self on public.tenant_memberships;

-- ====================================================================
-- 2. Criar política SUPER SIMPLES para SELECT
-- ====================================================================

-- Usuário vê APENAS seus próprios tenant_memberships
create policy tenant_memberships_select on public.tenant_memberships
  for select
  using (user_id = auth.uid());

-- Admin pode inserir/atualizar/deletar
create policy tenant_memberships_insert on public.tenant_memberships
  for insert
  with check (
    exists (
      select 1 from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = tenant_memberships.tenant_id
        and tm.status = 'active'
    )
    or auth.uid() = user_id  -- Permitir auto-criação via trigger
  );

create policy tenant_memberships_update on public.tenant_memberships
  for update
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = tenant_memberships.tenant_id
        and tm.role = 'admin'
        and tm.status = 'active'
    )
  );

create policy tenant_memberships_delete on public.tenant_memberships
  for delete
  using (
    exists (
      select 1 from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = tenant_memberships.tenant_id
        and tm.role = 'admin'
        and tm.status = 'active'
    )
  );

commit;

-- ====================================================================
-- SUCESSO! Agora tenant_memberships deve carregar sem erro 500
-- ====================================================================
