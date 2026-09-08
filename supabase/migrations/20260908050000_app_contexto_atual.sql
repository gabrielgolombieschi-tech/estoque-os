-- Contexto da sessao para o aplicativo.
--
-- A rota /api/admin/invite-user exige tenantId no corpo e o id da empresa em
-- empresaVinculos. O app nao guardava esses ids em lugar nenhum — so o web
-- tinha esse contexto. Em vez de o aplicativo montar isso somando chamadas de
-- current_tenant_id e current_empresa_id e ainda buscar o nome da empresa a
-- parte, uma funcao devolve tudo de uma vez.
--
-- Sem portao de papel: e apenas quem a pessoa e e onde ela esta, informacao que
-- toda sessao autenticada ja pode ver sobre si mesma.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

create or replace function public.app_contexto_atual()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'c', 'a'
set row_security to 'off'
as $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_empresa_nome text;
  v_papel text;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  select coalesce(nullif(btrim(empresa.nome_fantasia), ''), empresa.razao_social)
    into v_empresa_nome
  from c.empresa as empresa
  where empresa.id = v_empresa_id
    and empresa.tenant_id = v_tenant_id;

  v_papel := a.fn_current_empresa_papel(v_tenant_id, v_empresa_id);

  return jsonb_build_object(
    'tenant_id', v_tenant_id,
    'empresa_id', v_empresa_id,
    'empresa_nome', coalesce(v_empresa_nome, 'Empresa'),
    'papel', v_papel,
    'pode_criar_usuario', coalesce(public.can('admin', 'manage_users', v_tenant_id), false)
  );
end;
$function$;

revoke all on function public.app_contexto_atual() from public, anon;
grant execute on function public.app_contexto_atual() to authenticated;

notify pgrst, 'reload schema';

commit;
