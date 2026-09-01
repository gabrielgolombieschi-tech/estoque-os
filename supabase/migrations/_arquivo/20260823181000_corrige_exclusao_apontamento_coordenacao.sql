-- Coordenadores operam apontamentos da empresa sem precisar estar vinculados a um colaborador.
-- A obrigatoriedade do vínculo permanece exclusivamente para o perfil APONTADOR.

create or replace function public.app_excluir_apontamento(p_apontamento_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, a, c
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_colaborador_proprio_id uuid;
  v_papel_empresa text;
  v_colaborador_id uuid;
  v_status text;
  v_gerado_por_hh boolean;
  v_erros jsonb := '[]'::jsonb;
  v_avisos jsonb := '[]'::jsonb;
begin
  if v_auth_uid is null then
    raise exception 'Autenticação obrigatória para excluir apontamentos.';
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();
  if v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Não foi possível identificar um tenant e uma empresa ativos para este usuário.';
  end if;

  select ue.papel into v_papel_empresa
  from a.usuario u
  join a.usuario_empresa ue
    on ue.usuario_id = u.id
   and ue.empresa_id = v_empresa_id
   and ue.ativo is true
   and ue.deleted_at is null
  where u.auth_user_id = v_auth_uid
    and u.ativo is true
    and u.deleted_at is null
  limit 1;
  if v_papel_empresa is null then
    raise exception 'Não foi possível identificar o papel deste usuário na empresa atual.';
  end if;

  if upper(v_papel_empresa) = 'APONTADOR' then
    select c.id into v_colaborador_proprio_id
    from public.colaboradores c
    where c.user_id = v_auth_uid
      and c.tenant_id = v_tenant_id
      and c.empresa_id = v_empresa_id
      and c.ativo is true;
    if v_colaborador_proprio_id is null then
      raise exception 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.';
    end if;
  end if;

  select ah.colaborador_id, ah.status, ah.gerado_por_hh
    into v_colaborador_id, v_status, v_gerado_por_hh
  from public.apontamentos_horas ah
  where ah.id = p_apontamento_id
    and ah.tenant_id = v_tenant_id
    and ah.empresa_id = v_empresa_id;
  if not found then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', v_avisos, 'erros', jsonb_build_array(jsonb_build_object('tipo', 'apontamento', 'mensagem', 'O apontamento informado não existe ou não pertence à empresa atual.')));
  end if;

  if coalesce(v_gerado_por_hh, false) then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'hh', 'mensagem', 'Este apontamento é um espelho de HH e deve ser excluído no módulo HH.'));
  elsif lower(coalesce(v_status, '')) = 'fechado' then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'status', 'mensagem', 'Este apontamento está fechado e não pode ser excluído.'));
  elsif lower(coalesce(v_status, '')) = 'aprovado' then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'status', 'mensagem', 'Este apontamento está aprovado e não pode ser excluído.'));
  end if;

  if upper(v_papel_empresa) = 'APONTADOR' and v_colaborador_id <> v_colaborador_proprio_id then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'permissao', 'mensagem', 'O perfil APONTADOR só pode excluir o próprio apontamento.'));
  end if;

  if jsonb_array_length(v_erros) > 0 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', v_avisos, 'erros', v_erros);
  end if;

  delete from public.apontamentos_horas
  where id = p_apontamento_id
    and tenant_id = v_tenant_id
    and empresa_id = v_empresa_id;

  return jsonb_build_object('sucesso', true, 'gravados', 1, 'avisos', v_avisos, 'erros', v_erros);
end;
$$;

revoke all on function public.app_excluir_apontamento(uuid) from public, anon, authenticated, service_role;
grant execute on function public.app_excluir_apontamento(uuid) to authenticated;
