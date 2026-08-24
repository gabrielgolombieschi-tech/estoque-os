-- Edição e exclusão de apontamentos pelo app móvel.
-- Nenhuma das funções lê ou retorna valores financeiros.

create or replace function public.app_editar_apontamento(
  p_apontamento_id uuid,
  p_horas numeric,
  p_tipo_hora_id uuid,
  p_descricao text default null,
  p_confirmar_avisos boolean default false
)
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
  v_os_id integer;
  v_data date;
  v_status text;
  v_gerado_por_hh boolean;
  v_os_status text;
  v_nome_colaborador text;
  v_tipo_nome text;
  v_descricao text := nullif(btrim(p_descricao), '');
  v_total_dia numeric;
  v_duplicidade text;
  v_erros jsonb := '[]'::jsonb;
  v_avisos jsonb := '[]'::jsonb;
begin
  if v_auth_uid is null then
    raise exception 'Autenticação obrigatória para editar apontamentos.';
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();
  if v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Não foi possível identificar um tenant e uma empresa ativos para este usuário.';
  end if;

  select c.id into v_colaborador_proprio_id
  from public.colaboradores c
  where c.user_id = v_auth_uid
    and c.tenant_id = v_tenant_id
    and c.empresa_id = v_empresa_id
    and c.ativo is true;
  if v_colaborador_proprio_id is null then
    raise exception 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.';
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

  select ah.colaborador_id, ah.os_id, ah.data, ah.status, ah.gerado_por_hh, os.status, c.nome
    into v_colaborador_id, v_os_id, v_data, v_status, v_gerado_por_hh, v_os_status, v_nome_colaborador
  from public.apontamentos_horas ah
  join public.ordens_servico os
    on os.id = ah.os_id
   and os.tenant_id = v_tenant_id
   and os.empresa_id = v_empresa_id
  join public.colaboradores c
    on c.id = ah.colaborador_id
   and c.tenant_id = v_tenant_id
   and c.empresa_id = v_empresa_id
  where ah.id = p_apontamento_id
    and ah.tenant_id = v_tenant_id
    and ah.empresa_id = v_empresa_id;
  if not found then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', v_avisos, 'erros', jsonb_build_array(jsonb_build_object('tipo', 'apontamento', 'mensagem', 'O apontamento informado não existe ou não pertence à empresa atual.')));
  end if;

  if coalesce(v_gerado_por_hh, false) then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'hh', 'mensagem', 'Este apontamento é um espelho de HH e deve ser alterado no módulo HH.'));
  elsif lower(coalesce(v_status, '')) = 'fechado' then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'status', 'mensagem', 'Este apontamento está fechado e não pode ser editado.'));
  elsif lower(coalesce(v_status, '')) = 'aprovado' then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'status', 'mensagem', 'Este apontamento está aprovado e não pode ser editado.'));
  end if;

  if upper(v_papel_empresa) = 'APONTADOR' and v_colaborador_id <> v_colaborador_proprio_id then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'permissao', 'mensagem', 'O perfil APONTADOR só pode editar o próprio apontamento.'));
  end if;

  if p_horas is null or p_horas <= 0 or p_horas > 24 then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'horas', 'mensagem', 'Informe uma quantidade de horas maior que zero e de no máximo 24 horas.'));
  end if;

  select th.descricao into v_tipo_nome
  from public.tipos_horas th
  where th.id = p_tipo_hora_id
    and th.tenant_id = v_tenant_id
    and th.ativo is true;
  if v_tipo_nome is null then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'tipo_hora', 'mensagem', 'O tipo de hora informado não existe ou está inativo.'));
  end if;

  if lower(coalesce(v_os_status, '')) = 'concluida' and v_descricao is null then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'descricao_garantia', 'mensagem', 'Informe a descrição do serviço para editar horas em uma OS concluída (garantia).'));
  end if;

  if jsonb_array_length(v_erros) > 0 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', v_avisos, 'erros', v_erros);
  end if;

  select string_agg(format('%s h (%s)', replace(ah.horas::text, '.', ','), coalesce(th.descricao, 'tipo de hora')), '; ' order by ah.criado_em)
    into v_duplicidade
  from public.apontamentos_horas ah
  left join public.tipos_horas th on th.id = ah.tipo_hora_id and th.tenant_id = v_tenant_id
  where ah.tenant_id = v_tenant_id
    and ah.empresa_id = v_empresa_id
    and ah.id <> p_apontamento_id
    and ah.os_id = v_os_id
    and ah.colaborador_id = v_colaborador_id
    and ah.data = v_data
    and ah.tipo_hora_id = p_tipo_hora_id
    and ah.gerado_por_hh is false;
  if v_duplicidade is not null then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'duplicidade', 'mensagem', format('Já existe outro apontamento de %s para este colaborador, OS, data e tipo de hora. Mantenha apenas um lançamento ou escolha outro tipo.', v_duplicidade)));
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', v_avisos, 'erros', v_erros);
  end if;

  select coalesce(sum(ah.horas), 0) + p_horas into v_total_dia
  from public.apontamentos_horas ah
  where ah.tenant_id = v_tenant_id
    and ah.empresa_id = v_empresa_id
    and ah.colaborador_id = v_colaborador_id
    and ah.data = v_data
    and ah.id <> p_apontamento_id;
  if v_total_dia > 9 then
    v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('tipo', 'jornada_maior_que_9h', 'mensagem', format('%s ficará com %s h apontadas em %s. Verifique se o intervalo de almoço foi descontado.', v_nome_colaborador, replace(v_total_dia::text, '.', ','), to_char(v_data, 'DD/MM/YYYY'))));
  end if;

  if jsonb_array_length(v_avisos) > 0 and not p_confirmar_avisos then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', v_avisos, 'erros', v_erros);
  end if;

  update public.apontamentos_horas
  set horas = p_horas,
      tipo_hora_id = p_tipo_hora_id,
      descricao = v_descricao
  where id = p_apontamento_id
    and tenant_id = v_tenant_id
    and empresa_id = v_empresa_id;

  return jsonb_build_object('sucesso', true, 'gravados', 1, 'avisos', v_avisos, 'erros', v_erros);
end;
$$;

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

  select c.id into v_colaborador_proprio_id
  from public.colaboradores c
  where c.user_id = v_auth_uid
    and c.tenant_id = v_tenant_id
    and c.empresa_id = v_empresa_id
    and c.ativo is true;
  if v_colaborador_proprio_id is null then
    raise exception 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.';
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

revoke all on function public.app_editar_apontamento(uuid, numeric, uuid, text, boolean) from public, anon, authenticated, service_role;
grant execute on function public.app_editar_apontamento(uuid, numeric, uuid, text, boolean) to authenticated;

revoke all on function public.app_excluir_apontamento(uuid) from public, anon, authenticated, service_role;
grant execute on function public.app_excluir_apontamento(uuid) to authenticated;
