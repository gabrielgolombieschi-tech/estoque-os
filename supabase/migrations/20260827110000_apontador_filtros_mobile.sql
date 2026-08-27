begin;

set local role postgres;

-- Exposicao minima do papel da empresa atual ao app mobile. Nao cria tabelas,
-- nao altera dados e nao permite escolher ou consultar o papel de terceiros.
create or replace function public.app_meu_papel_empresa()
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  select upper(ue.papel)
    into v_papel
  from a.usuario as u
  join a.usuario_empresa as ue
    on ue.usuario_id = u.id
   and ue.empresa_id = v_empresa_id
   and ue.ativo is true
   and ue.deleted_at is null
  where u.auth_user_id = v_auth_uid
    and u.ativo is true
    and u.deleted_at is null
  limit 1;

  if v_papel is null then
    raise exception 'Não foi possível identificar o papel deste usuário na empresa.';
  end if;

  return v_papel;
end;
$$;

revoke all on function public.app_meu_papel_empresa() from public, anon, authenticated, service_role;
grant execute on function public.app_meu_papel_empresa() to authenticated;

-- O app esconde os filtros fechados para APONTADOR. A mesma regra e aplicada
-- aqui para impedir que uma chamada manual ao endpoint contorne a interface.
do $patch_listar_os_fluxo_apontador$
declare
  v_definition text;
  v_needle text := $needle$
  end if;

  select c.id into v_colaborador_id
$needle$;
  v_replacement text := $replacement$
  end if;

  if upper(v_papel) = 'APONTADOR' and v_status <> 'em_andamento' then
    raise exception 'O perfil APONTADOR só pode consultar OS em andamento.';
  end if;

  select c.id into v_colaborador_id
$replacement$;
begin
  select pg_get_functiondef('public.app_listar_os_fluxo(text,text)'::regprocedure)
    into v_definition;

  if position(v_needle in v_definition) = 0 then
    raise exception 'apontador_filtro_os_patch_token_not_found';
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$patch_listar_os_fluxo_apontador$;

commit;
