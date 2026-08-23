-- RPCs de escrita do app móvel. Não expõem valores financeiros.

create or replace function public.app_listar_tipos_horas()
returns table (
  id uuid,
  nome character varying
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a, c
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_colaborador_id uuid;
begin
  if v_auth_uid is null then
    raise exception 'Autenticação obrigatória para consultar tipos de hora.';
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();

  if v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Não foi possível identificar um tenant e uma empresa ativos para este usuário.';
  end if;

  select colaborador.id
    into v_colaborador_id
  from public.colaboradores as colaborador
  where colaborador.user_id = v_auth_uid
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo is true;

  if v_colaborador_id is null then
    raise exception 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.';
  end if;

  return query
  select tipo_hora.id, tipo_hora.descricao
  from public.tipos_horas as tipo_hora
  where tipo_hora.tenant_id = v_tenant_id
    and tipo_hora.ativo is true
  order by tipo_hora.descricao;
end;
$$;

create or replace function public.app_lancar_apontamentos_lote(
  p_os_id integer,
  p_data date,
  p_tipo_hora_id uuid,
  p_lancamentos jsonb,
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
  v_os_status text;
  v_os_hh boolean;
  v_tipo_nome text;
  v_descricao text := nullif(btrim(p_descricao), '');
  v_erros jsonb := '[]'::jsonb;
  v_avisos jsonb := '[]'::jsonb;
  v_item jsonb;
  v_colaborador_id uuid;
  v_horas numeric;
  v_colaborador_ids uuid[] := '{}'::uuid[];
  v_horas_lancadas numeric[] := '{}'::numeric[];
  v_nomes_colaboradores text[] := '{}'::text[];
  v_nome_colaborador text;
  v_colaborador_ativo boolean;
  v_total_dia numeric;
  v_duplicidades text;
  v_indice integer;
  v_gravados integer;
begin
  if v_auth_uid is null then
    raise exception 'Autenticação obrigatória para lançar apontamentos.';
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();

  if v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Não foi possível identificar um tenant e uma empresa ativos para este usuário.';
  end if;

  select colaborador.id
    into v_colaborador_proprio_id
  from public.colaboradores as colaborador
  where colaborador.user_id = v_auth_uid
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo is true;

  if v_colaborador_proprio_id is null then
    raise exception 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.';
  end if;

  select usuario_empresa.papel
    into v_papel_empresa
  from a.usuario as usuario
  join a.usuario_empresa as usuario_empresa
    on usuario_empresa.usuario_id = usuario.id
   and usuario_empresa.empresa_id = v_empresa_id
   and usuario_empresa.ativo is true
   and usuario_empresa.deleted_at is null
  where usuario.auth_user_id = v_auth_uid
    and usuario.ativo is true
    and usuario.deleted_at is null
  limit 1;

  if v_papel_empresa is null then
    raise exception 'Não foi possível identificar o papel deste usuário na empresa atual.';
  end if;

  if p_data is null then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object(
      'tipo', 'data',
      'mensagem', 'Informe a data do apontamento.'
    ));
  elsif p_data > current_date then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object(
      'tipo', 'data_futura',
      'mensagem', 'Não é permitido lançar apontamentos em data futura.'
    ));
  end if;

  select os.status, coalesce(os.usa_relatorio_hh, false)
    into v_os_status, v_os_hh
  from public.ordens_servico as os
  where os.id = p_os_id
    and os.tenant_id = v_tenant_id
    and os.empresa_id = v_empresa_id;

  if not found then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object(
      'tipo', 'os',
      'mensagem', 'A OS informada não existe ou não pertence à empresa atual.'
    ));
  elsif lower(v_os_status) = 'cancelada' then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object(
      'tipo', 'os_cancelada',
      'mensagem', 'Não é permitido lançar apontamentos em uma OS cancelada.'
    ));
  elsif v_os_hh then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object(
      'tipo', 'os_hh',
      'mensagem', 'Esta é uma OS de HH. Use o lançamento por horários, que será disponibilizado em uma função própria.'
    ));
  elsif lower(v_os_status) = 'concluida' and v_descricao is null then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object(
      'tipo', 'descricao_garantia',
      'mensagem', 'Informe a descrição do serviço para lançar horas em uma OS concluída (garantia).'
    ));
  end if;

  select tipo_hora.descricao
    into v_tipo_nome
  from public.tipos_horas as tipo_hora
  where tipo_hora.id = p_tipo_hora_id
    and tipo_hora.tenant_id = v_tenant_id
    and tipo_hora.ativo is true;

  if v_tipo_nome is null then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object(
      'tipo', 'tipo_hora',
      'mensagem', 'O tipo de hora informado não existe ou está inativo.'
    ));
  elsif lower(v_tipo_nome) ~ '(espera|improdutiv|parada|deslocamento)'
        and v_descricao is null then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object(
      'tipo', 'descricao_obrigatoria',
      'mensagem', format('Informe a descrição para o tipo de hora "%s".', v_tipo_nome)
    ));
  end if;

  if p_lancamentos is null or jsonb_typeof(p_lancamentos) <> 'array' then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object(
      'tipo', 'lancamentos',
      'mensagem', 'Envie uma lista de lançamentos válida.'
    ));
  elsif jsonb_array_length(p_lancamentos) = 0 then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object(
      'tipo', 'lancamentos',
      'mensagem', 'Informe ao menos um colaborador para o lançamento.'
    ));
  else
    for v_item in select value from jsonb_array_elements(p_lancamentos)
    loop
      if jsonb_typeof(v_item) <> 'object' then
        v_erros := v_erros || jsonb_build_array(jsonb_build_object(
          'tipo', 'lancamentos',
          'mensagem', 'Cada lançamento deve informar colaborador e horas.'
        ));
        continue;
      end if;

      begin
        v_colaborador_id := nullif(v_item ->> 'colaborador_id', '')::uuid;
      exception when others then
        v_colaborador_id := null;
      end;

      begin
        v_horas := (v_item ->> 'horas')::numeric;
      exception when others then
        v_horas := null;
      end;

      if v_colaborador_id is null then
        v_erros := v_erros || jsonb_build_array(jsonb_build_object(
          'tipo', 'colaborador',
          'mensagem', 'Há um lançamento sem um colaborador válido.'
        ));
        continue;
      end if;

      if v_horas is null or v_horas <= 0 or v_horas > 24 then
        v_erros := v_erros || jsonb_build_array(jsonb_build_object(
          'tipo', 'horas',
          'mensagem', format('Informe entre 0 e 24 horas para o colaborador %s.', v_colaborador_id)
        ));
        continue;
      end if;

      if v_colaborador_id = any(v_colaborador_ids) then
        v_erros := v_erros || jsonb_build_array(jsonb_build_object(
          'tipo', 'lote_duplicado',
          'mensagem', format('O colaborador %s foi informado mais de uma vez no mesmo lote.', v_colaborador_id)
        ));
        continue;
      end if;

      v_colaborador_ids := array_append(v_colaborador_ids, v_colaborador_id);
      v_horas_lancadas := array_append(v_horas_lancadas, v_horas);
    end loop;
  end if;

  if jsonb_array_length(v_erros) > 0 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', v_avisos, 'erros', v_erros);
  end if;

  for v_indice in array_lower(v_colaborador_ids, 1)..array_upper(v_colaborador_ids, 1)
  loop
    select colaborador.nome, colaborador.ativo
      into v_nome_colaborador, v_colaborador_ativo
    from public.colaboradores as colaborador
    where colaborador.id = v_colaborador_ids[v_indice]
      and colaborador.tenant_id = v_tenant_id
      and colaborador.empresa_id = v_empresa_id;

    if not found then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object(
        'tipo', 'colaborador',
        'mensagem', format('O colaborador %s não pertence à empresa atual.', v_colaborador_ids[v_indice])
      ));
      v_nomes_colaboradores := array_append(v_nomes_colaboradores, v_colaborador_ids[v_indice]::text);
    elsif not v_colaborador_ativo then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object(
        'tipo', 'colaborador_inativo',
        'mensagem', format('O colaborador %s está inativo e não pode receber apontamentos.', v_nome_colaborador)
      ));
      v_nomes_colaboradores := array_append(v_nomes_colaboradores, v_nome_colaborador);
    elsif upper(v_papel_empresa) = 'APONTADOR'
          and v_colaborador_ids[v_indice] <> v_colaborador_proprio_id then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object(
        'tipo', 'colaborador',
        'mensagem', 'O perfil APONTADOR só pode lançar horas para o próprio colaborador vinculado.'
      ));
      v_nomes_colaboradores := array_append(v_nomes_colaboradores, v_nome_colaborador);
    else
      v_nomes_colaboradores := array_append(v_nomes_colaboradores, v_nome_colaborador);
    end if;
  end loop;

  if jsonb_array_length(v_erros) > 0 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', v_avisos, 'erros', v_erros);
  end if;

  select string_agg(
           format('%s (%s h)', colaborador.nome, apontamento.horas::text),
           '; ' order by colaborador.nome
         )
    into v_duplicidades
  from public.apontamentos_horas as apontamento
  join public.colaboradores as colaborador
    on colaborador.id = apontamento.colaborador_id
  where apontamento.tenant_id = v_tenant_id
    and apontamento.empresa_id = v_empresa_id
    and apontamento.os_id = p_os_id
    and apontamento.data = p_data
    and apontamento.tipo_hora_id = p_tipo_hora_id
    and apontamento.gerado_por_hh is false
    and apontamento.colaborador_id = any(v_colaborador_ids);

  if v_duplicidades is not null then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object(
      'tipo', 'duplicidade',
      'mensagem', format('Já existe lançamento nesta OS, data e tipo de hora para: %s. Edite o lançamento existente em vez de criar outro.', v_duplicidades)
    ));
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', v_avisos, 'erros', v_erros);
  end if;

  if p_data < current_date - 7 then
    v_avisos := v_avisos || jsonb_build_array(jsonb_build_object(
      'tipo', 'retroativo',
      'mensagem', format('Este apontamento é retroativo: a data %s tem mais de 7 dias.', to_char(p_data, 'DD/MM/YYYY'))
    ));
  end if;

  for v_indice in array_lower(v_colaborador_ids, 1)..array_upper(v_colaborador_ids, 1)
  loop
    select coalesce(sum(apontamento.horas), 0)
      into v_total_dia
    from public.apontamentos_horas as apontamento
    where apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
      and apontamento.colaborador_id = v_colaborador_ids[v_indice]
      and apontamento.data = p_data;

    v_total_dia := v_total_dia + v_horas_lancadas[v_indice];

    if v_total_dia > 9 then
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object(
        'tipo', 'jornada_maior_que_9h',
        'mensagem', format('%s ficará com %s h apontadas em %s. Verifique se o intervalo de almoço foi descontado.', v_nomes_colaboradores[v_indice], v_total_dia::text, to_char(p_data, 'DD/MM/YYYY'))
      ));
    end if;
  end loop;

  if jsonb_array_length(v_avisos) > 0 and not p_confirmar_avisos then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', v_avisos, 'erros', v_erros);
  end if;

  if lower(v_os_status) = 'concluida' then
    perform set_config('app.permitir_lancamento_garantia', 'true', true);
  end if;

  insert into public.apontamentos_horas (
    os_id,
    colaborador_id,
    data,
    horas,
    tipo_hora_id,
    descricao,
    status,
    tenant_id,
    empresa_id,
    gerado_por_hh,
    criado_por_user_id
  )
  select
    p_os_id,
    v_colaborador_ids[indice],
    p_data,
    v_horas_lancadas[indice],
    p_tipo_hora_id,
    v_descricao,
    'lancado',
    v_tenant_id,
    v_empresa_id,
    false,
    v_auth_uid
  from generate_subscripts(v_colaborador_ids, 1) as indice;

  get diagnostics v_gravados = row_count;

  return jsonb_build_object('sucesso', true, 'gravados', v_gravados, 'avisos', v_avisos, 'erros', v_erros);
end;
$$;

-- A garantia em OS concluída só é permitida pela RPC acima, que exige descrição.
-- Para os demais fluxos, o bloqueio histórico é preservado.
create or replace function public.fn_validar_apontamento_horas()
returns trigger
language plpgsql
set search_path = pg_catalog, public, a, c, f, m, r, auth, extensions
as $$
declare
  v_status text;
  v_tem_taxa boolean;
begin
  select status into v_status
  from public.ordens_servico
  where id = new.os_id;

  if v_status is null then
    raise exception 'OS % não encontrada.', new.os_id;
  end if;

  if v_status = 'cancelada' then
    raise exception 'Não é permitido lançar horas: OS % está com status "%".', new.os_id, v_status;
  end if;

  if v_status = 'concluida'
     and coalesce(current_setting('app.permitir_lancamento_garantia', true), '') <> 'true' then
    raise exception 'Não é permitido lançar horas: OS % está com status "%".', new.os_id, v_status;
  end if;

  if coalesce(new.gerado_por_hh, false) then
    return new;
  end if;

  select exists (
    select 1
    from public.colaborador_taxas as taxa
    where taxa.colaborador_id = new.colaborador_id
      and new.data >= taxa.vigencia_inicio
      and (taxa.vigencia_fim is null or new.data <= taxa.vigencia_fim)
  ) into v_tem_taxa;

  if not v_tem_taxa then
    raise exception
      'Não é permitido lançar horas: colaborador % não possui taxa vigente em %.',
      new.colaborador_id, new.data;
  end if;

  return new;
end;
$$;

revoke all on function public.app_listar_tipos_horas() from public, anon, authenticated, service_role;
revoke all on function public.app_lancar_apontamentos_lote(integer, date, uuid, jsonb, text, boolean) from public, anon, authenticated, service_role;

grant execute on function public.app_listar_tipos_horas() to authenticated;
grant execute on function public.app_lancar_apontamentos_lote(integer, date, uuid, jsonb, text, boolean) to authenticated;
