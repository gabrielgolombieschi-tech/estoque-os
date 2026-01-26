-- ============================================================================
-- DIAGNÓSTICO: Usuário Financeiro com permissões de Admin
-- ============================================================================
-- Execute este SQL no Supabase para identificar o problema
-- ============================================================================

-- 1) Verificar o papel do usuário no TENANT (usuario_tenant)
SELECT 
  ut.usuario_id,
  ut.tenant_id,
  ut.papel as papel_tenant,
  ut.ativo,
  u.nome,
  u.email
FROM a.usuario_tenant ut
JOIN a.usuario u ON u.id = ut.usuario_id
WHERE u.email = 'larissa@segau.com.br'
  AND ut.deleted_at IS NULL;

-- 2) Verificar o papel do usuário na EMPRESA (usuario_empresa)
SELECT 
  ue.usuario_id,
  ue.empresa_id,
  ue.papel as papel_empresa,
  ue.ativo,
  u.nome,
  u.email,
  e.nome_fantasia
FROM a.usuario_empresa ue
JOIN a.usuario u ON u.id = ue.usuario_id
JOIN c.empresa e ON e.id = ue.empresa_id
WHERE u.email = 'larissa@segau.com.br'
  AND ue.deleted_at IS NULL;

-- 3) Verificar ROLES atribuídas ao usuário via tenant_memberships + membership_roles
SELECT 
  u.email,
  tm.status,
  r.name as role_name,
  r.id as role_id
FROM public.tenant_memberships tm
JOIN auth.users au ON au.id = tm.user_id
JOIN a.usuario u ON u.auth_user_id = au.id
LEFT JOIN public.membership_roles mr ON mr.membership_id = tm.id
LEFT JOIN public.roles r ON r.id = mr.role_id
WHERE u.email = 'larissa@segau.com.br'
  AND tm.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';

-- 4) Verificar TODAS as permissões do usuário financeiro
SELECT * FROM public.get_my_permissions(
  '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid,
  'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
) 
ORDER BY permission;

-- 5) Filtrar APENAS permissões de admin
SELECT * FROM public.get_my_permissions(
  '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid,
  'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
) 
WHERE permission LIKE '%admin%';

-- 6) Verificar TODAS as permissões na tabela role_permissions (para entender a estrutura)
SELECT DISTINCT role, permission 
FROM public.role_permissions 
ORDER BY role, permission;

-- 7) Verificar permissões da role 'Financeiro' (se existir)
SELECT role, permission 
FROM public.role_permissions 
WHERE role ILIKE '%financeiro%'
ORDER BY permission;

-- ============================================================================
-- SOLUÇÃO IDENTIFICADA: papel_tenant = 'ADMIN' está dando acesso total
-- ============================================================================

-- CORREÇÃO: Alterar papel_tenant de ADMIN para GESTOR (ou NULL)
UPDATE a.usuario_tenant
SET papel = 'GESTOR'  -- ou NULL se preferir remover o papel no tenant
WHERE usuario_id = '46643ab1-122a-4d8f-8070-5c0a98f4344a'
  AND tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';

-- NOTA: O papel na EMPRESA (FINANCEIRO) está correto e será preservado.
-- Apenas o papel no TENANT será alterado de ADMIN → GESTOR.

-- ============================================================================
-- VALIDAÇÃO APÓS CORREÇÃO
-- ============================================================================

-- 1) Verificar se o papel foi alterado
SELECT 
  ut.papel as papel_tenant,
  u.nome,
  u.email
FROM a.usuario_tenant ut
JOIN a.usuario u ON u.id = ut.usuario_id
WHERE u.email = 'larissa@segau.com.br'
  AND ut.deleted_at IS NULL;

-- Resultado esperado: papel_tenant = 'GESTOR' (ou NULL)

-- 2) Verificar permissões após a correção (FAÇA LOGOUT/LOGIN ANTES!)
SELECT * FROM public.get_my_permissions(
  '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid,
  'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
) 
WHERE permission LIKE '%admin%';

-- Resultado esperado: NENHUMA linha (sem permissões admin)

-- 3) Verificar permissões de financeiro (devem estar presentes)
SELECT * FROM public.get_my_permissions(
  '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid,
  'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
) 
WHERE permission LIKE '%financeiro%';

-- Resultado esperado: financeiro.read, financeiro.write, financeiro.delete, financeiro.config

-- ============================================================================
-- RESULTADO ESPERADO
-- ============================================================================
-- Após a correção, o usuário larissa@segau.com.br deve ter:
-- - isAdminTenant: false
-- - can("admin.manage_users"): false
-- - shouldShowAdmin: false
-- - Menu Admin OCULTO
-- ============================================================================
