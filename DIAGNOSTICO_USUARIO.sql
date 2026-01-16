-- =====================================================================
-- DIAGNÓSTICO E CORREÇÃO FINAL
-- =====================================================================
-- Verificar se usuário tem dados de tenant/empresa e corrigir problemas
-- =====================================================================

begin;

-- ====================================================================
-- 1. DIAGNÓSTICO: Ver estado atual do usuário logado
-- ====================================================================

-- Listar todos os usuários
select 
  id,
  email,
  created_at
from auth.users
where deleted_at is null
order by created_at desc
limit 5;

-- Ver tenant_memberships
select 
  tm.user_id,
  tm.tenant_id,
  tm.status,
  tm.role,
  t.nome as tenant_nome,
  u.email
from public.tenant_memberships tm
join auth.users u on u.id = tm.user_id
left join public.tenants t on t.id = tm.tenant_id
where u.deleted_at is null
order by tm.created_at desc
limit 10;

-- Ver empresa_memberships
select 
  em.user_id,
  em.tenant_id,
  em.empresa_id,
  em.status,
  e.razao_social,
  u.email
from public.empresa_memberships em
join auth.users u on u.id = em.user_id
left join public.empresas e on e.id = em.empresa_id
where u.deleted_at is null
order by em.criado_em desc
limit 10;

-- Ver user_empresa_context
select 
  uec.user_id,
  uec.tenant_id,
  uec.empresa_id,
  e.razao_social,
  u.email
from public.user_empresa_context uec
join auth.users u on u.id = uec.user_id
left join public.empresas e on e.id = uec.empresa_id
where u.deleted_at is null
limit 10;

commit;

-- ====================================================================
-- INSTRUÇÕES:
-- ====================================================================
-- 1. Execute este script no Supabase SQL Editor
-- 2. Copie os resultados (especialmente emails e IDs)
-- 3. Me envie os resultados para análise
-- 4. Vou criar um script de correção específico
-- ====================================================================
