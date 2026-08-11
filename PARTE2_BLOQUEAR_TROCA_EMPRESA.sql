-- OBSOLETO E BLOQUEADO: este script forca todos para uma empresa fixa e
-- viola a fronteira definida na SGU. Nao executar.
do $script_obsoleto$
begin
  raise exception 'SCRIPT OBSOLETO: a empresa atual depende do vinculo ativo na SGU';
end;
$script_obsoleto$;

-- =====================================================================
-- PARTE 2: BLOQUEAR TROCA DE EMPRESA (SEMPRE ELÉTRICA SEGAU)
-- =====================================================================
-- Esta migration força que:
-- 1. A função current_empresa_id() SEMPRE retorna Elétrica Segau
-- 2. set_current_empresa ignora tentativas de mudar (ou aceita silenciosamente)
-- 3. get_default_empresa_id sempre retorna Elétrica Segau
-- =====================================================================

begin;

-- ====================================================================
-- 1. Forçar current_empresa_id() a sempre retornar Elétrica Segau
-- ====================================================================

create or replace function public.current_empresa_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
begin
  -- Sempre retorna a empresa Elétrica Segau para o tenant do usuário
  
  -- Pegar tenant do usuário
  v_tenant_id := public.current_tenant_id();
  
  if v_tenant_id is null then
    -- Fallback: tentar via config
    return nullif(current_setting('app.current_empresa_id', true), '')::uuid;
  end if;
  
  -- Buscar Elétrica Segau
  select id into v_empresa_id
  from public.empresas
  where tenant_id = v_tenant_id
    and (
      razao_social ilike '%segau%'
      or nome_fantasia ilike '%segau%'
    )
    and ativo = true
  limit 1;
  
  if v_empresa_id is not null then
    return v_empresa_id;
  end if;
  
  -- Fallback: primeira empresa ativa do tenant
  select id into v_empresa_id
  from public.empresas
  where tenant_id = v_tenant_id
    and ativo = true
  order by criado_em asc nulls last
  limit 1;
  
  return v_empresa_id;
end;
$$;

-- ====================================================================
-- 2. Forçar get_default_empresa_id() a sempre retornar Elétrica Segau
-- ====================================================================

create or replace function public.get_default_empresa_id(p_tenant_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_empresa_id uuid;
begin
  -- Sempre retorna Elétrica Segau
  select id into v_empresa_id
  from public.empresas
  where tenant_id = p_tenant_id
    and (
      razao_social ilike '%segau%'
      or nome_fantasia ilike '%segau%'
    )
    and ativo = true
  limit 1;
  
  if v_empresa_id is not null then
    return v_empresa_id;
  end if;
  
  -- Fallback: primeira empresa ativa
  select id into v_empresa_id
  from public.empresas
  where tenant_id = p_tenant_id
    and ativo = true
  order by criado_em asc nulls last
  limit 1;
  
  return v_empresa_id;
end;
$$;

-- ====================================================================
-- 3. Modificar set_current_empresa para aceitar mas não fazer nada
--    (evita erros no frontend quando tenta trocar empresa)
-- ====================================================================

create or replace function public.set_current_empresa(p_empresa_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
  v_segau_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Tenant atual nao definido';
  end if;

  -- Buscar Elétrica Segau
  select id into v_segau_id
  from public.empresas
  where tenant_id = v_tenant
    and (
      razao_social ilike '%segau%'
      or nome_fantasia ilike '%segau%'
    )
    and ativo = true
  limit 1;

  -- SEMPRE usar Elétrica Segau, independente do que foi passado
  if v_segau_id is null then
    raise exception 'Empresa Elétrica Segau não encontrada para este tenant';
  end if;

  -- Atualizar contexto SEMPRE para Elétrica Segau
  insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
  values (auth.uid(), v_tenant, v_segau_id)
  on conflict (user_id, tenant_id) do update
    set empresa_id = v_segau_id,
        updated_at = now();

  perform set_config('app.current_empresa_id', v_segau_id::text, true);
end;
$$;

commit;

-- ====================================================================
-- SUCESSO! Agora:
-- - current_empresa_id() SEMPRE retorna Elétrica Segau
-- - get_default_empresa_id() SEMPRE retorna Elétrica Segau  
-- - set_current_empresa() aceita qualquer ID mas SEMPRE usa Elétrica Segau
-- - Impossível trocar de empresa via frontend
-- ====================================================================
