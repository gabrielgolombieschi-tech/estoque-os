-- =====================================================================
-- SOLUÇÃO FINAL: FORÇAR CONTEXTO NO LOGIN
-- =====================================================================
-- Criar função que seta tenant + empresa automaticamente no login
-- =====================================================================

begin;

-- ====================================================================
-- Função para auto-setar contexto após login
-- ====================================================================

create or replace function public.auto_set_context_on_login()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';  -- Tenant fixo
  v_empresa_id uuid := 'f0e74f49-a127-46b4-901b-f7b37e43c690'; -- Elétrica Segau
begin
  -- Setar tenant
  perform set_config('app.current_tenant_id', v_tenant_id::text, false);
  
  -- Setar empresa
  perform set_config('app.current_empresa_id', v_empresa_id::text, false);
  
  return NEW;
end;
$$;

-- Criar trigger no auth.users para setar contexto
drop trigger if exists on_auth_user_login_set_context on auth.users;

create trigger on_auth_user_login_set_context
  after update on auth.users
  for each row
  when (OLD.last_sign_in_at is distinct from NEW.last_sign_in_at)
  execute function public.auto_set_context_on_login();

commit;

-- ====================================================================
-- Agora toda vez que usuário faz login, contexto é setado automaticamente
-- ====================================================================
