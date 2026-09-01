-- RPCs seguras para o lançamento HH pelo aplicativo móvel.
-- Não retornam valores financeiros e deixam o espelho de apontamentos a cargo das triggers de hh_lancamentos.

create or replace function public.app_listar_especialidades_hh(
  p_os_id integer,
  p_colaborador_id uuid
)
returns table(id bigint, descricao text)
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
  v_papel_empresa text;
  v_colaborador_proprio_id uuid;
  v_cliente_id bigint;
begin
  if v_auth_uid is null then
    raise exception 'Autenticação obrigatória para consultar especialidades HH.';
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
    select colaborador.id into v_colaborador_proprio_id
    from public.colaboradores colaborador
    where colaborador.user_id = v_auth_uid
      and colaborador.tenant_id = v_tenant_id
      and colaborador.empresa_id = v_empresa_id
      and colaborador.ativo is true;
    if v_colaborador_proprio_id is null then
      raise exception 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.';
    end if;
    if p_colaborador_id is distinct from v_colaborador_proprio_id then
      raise exception 'O perfil APONTADOR só pode consultar as próprias especialidades HH.';
    end if;
  end if;

  select os.cliente_id into v_cliente_id
  from public.ordens_servico os
  where os.id = p_os_id
    and os.tenant_id = v_tenant_id
    and os.empresa_id = v_empresa_id
    and coalesce(os.usa_relatorio_hh, false) is true;
  if v_cliente_id is null then
    raise exception 'A OS HH informada não existe, não pertence à empresa atual ou não possui cliente.';
  end if;

  return query
  select
    servico.id,
    coalesce(nullif(btrim(servico.descricao), ''), servico.nome, 'Especialidade HH')::text
  from public.cliente_hh_servicos servico
  join public.colaborador_cliente_funcao vinculo
    on vinculo.hh_servico_id = servico.id
   and vinculo.tenant_id = v_tenant_id
   and vinculo.empresa_id = v_empresa_id
   and vinculo.cliente_id = v_cliente_id
   and vinculo.colaborador_id = p_colaborador_id
   and vinculo.ativo is true
  where servico.tenant_id = v_tenant_id
    and servico.empresa_id = v_empresa_id
    and servico.cliente_id = v_cliente_id
    and servico.ativo is true
  order by coalesce(nullif(btrim(servico.descricao), ''), servico.nome), servico.id;
end;
$$;

create or replace function public.app_lancar_hh(
  p_os_id integer,
  p_colaborador_id uuid,
  p_data date,
  p_hh_servico_id bigint,
  p_entrada_1 time,
  p_saida_1 time,
  p_entrada_2 time default null,
  p_saida_2 time default null,
  p_percentual_manual smallint default null,
  p_horas_extra_50 numeric default 0,
  p_horas_extra_100 numeric default 0,
  p_observacao text default null
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
  v_papel_empresa text;
  v_colaborador_proprio_id uuid;
  v_cliente_id bigint;
  v_os_status text;
  v_colaborador_nome text;
  v_percentual smallint;
  v_codigo_tipo text;
  v_hh_tipo_id bigint;
  v_preco_aplicavel numeric;
  v_horas_efetivas numeric(10,2);
  v_horas_extra_50 numeric(10,2) := coalesce(p_horas_extra_50, 0);
  v_horas_extra_100 numeric(10,2) := coalesce(p_horas_extra_100, 0);
  v_conflito text;
  v_lancamento_id bigint;
  v_erros jsonb := '[]'::jsonb;
begin
  if v_auth_uid is null then
    raise exception 'Autenticação obrigatória para lançar HH.';
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
    select colaborador.id into v_colaborador_proprio_id
    from public.colaboradores colaborador
    where colaborador.user_id = v_auth_uid
      and colaborador.tenant_id = v_tenant_id
      and colaborador.empresa_id = v_empresa_id
      and colaborador.ativo is true;
    if v_colaborador_proprio_id is null then
      raise exception 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.';
    end if;
    if p_colaborador_id is distinct from v_colaborador_proprio_id then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'permissao', 'mensagem', 'O perfil APONTADOR só pode lançar HH para o próprio colaborador vinculado.'));
    end if;
  end if;

  if p_data is null then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'data', 'mensagem', 'Informe a data do lançamento HH.'));
  elsif p_data > current_date then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'data_futura', 'mensagem', 'Não é permitido lançar HH em data futura.'));
  end if;

  select os.cliente_id, os.status into v_cliente_id, v_os_status
  from public.ordens_servico os
  where os.id = p_os_id
    and os.tenant_id = v_tenant_id
    and os.empresa_id = v_empresa_id
    and coalesce(os.usa_relatorio_hh, false) is true;
  if not found then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'os', 'mensagem', 'A OS informada não existe, não pertence à empresa atual ou não é uma OS HH.'));
  elsif lower(coalesce(v_os_status, '')) <> 'em_andamento' then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'os_status', 'mensagem', 'Só é permitido lançar HH em OS com status em andamento.'));
  elsif v_cliente_id is null then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'cliente', 'mensagem', 'A OS HH não possui cliente identificado.'));
  end if;

  select colaborador.nome into v_colaborador_nome
  from public.colaboradores colaborador
  where colaborador.id = p_colaborador_id
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo is true;
  if v_colaborador_nome is null then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'colaborador', 'mensagem', 'O colaborador informado não existe, está inativo ou não pertence à empresa atual.'));
  end if;

  if p_entrada_1 is null or p_saida_1 is null then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'horario', 'mensagem', 'Informe entrada e saída do primeiro período.'));
  elsif p_entrada_1 >= p_saida_1 then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'horario', 'mensagem', 'A entrada do primeiro período deve ser anterior à saída.'));
  end if;

  if (p_entrada_2 is null) <> (p_saida_2 is null) then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'horario', 'mensagem', 'Informe entrada e saída do segundo período ou deixe ambos vazios.'));
  elsif p_entrada_2 is not null and p_saida_2 is not null then
    if p_entrada_2 >= p_saida_2 then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'horario', 'mensagem', 'A entrada do segundo período deve ser anterior à saída.'));
    elsif p_saida_1 is not null and p_saida_1 > p_entrada_2 then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'horario', 'mensagem', 'O segundo período não pode sobrepor o primeiro.'));
    end if;
  end if;

  if v_horas_extra_50 < 0 or v_horas_extra_100 < 0 then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'extras', 'mensagem', 'As horas extras não podem ser negativas.'));
  end if;

  if p_percentual_manual is not null and p_percentual_manual not in (0, 50, 100) then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'percentual', 'mensagem', 'O tipo HH manual deve ser normal, extra 50% ou extra 100%.'));
  end if;

  if jsonb_array_length(v_erros) > 0 then
    return jsonb_build_object('sucesso', false, 'lancamento_id', null, 'horas', null, 'erros', v_erros);
  end if;

  v_horas_efetivas := round(
    extract(epoch from (p_saida_1 - p_entrada_1)) / 3600
    + case when p_entrada_2 is not null then extract(epoch from (p_saida_2 - p_entrada_2)) / 3600 else 0 end,
    2
  );
  if v_horas_efetivas <= 0 then
    return jsonb_build_object('sucesso', false, 'lancamento_id', null, 'horas', null, 'erros', jsonb_build_array(jsonb_build_object('tipo', 'horario', 'mensagem', 'Os horários informados não resultam em horas trabalhadas válidas.')));
  end if;
  if v_horas_extra_50 + v_horas_extra_100 > v_horas_efetivas then
    return jsonb_build_object('sucesso', false, 'lancamento_id', null, 'horas', null, 'erros', jsonb_build_array(jsonb_build_object('tipo', 'extras', 'mensagem', 'A soma das horas extras não pode ultrapassar as horas efetivamente trabalhadas.')));
  end if;

  if p_percentual_manual is not null then
    v_percentual := p_percentual_manual;
  elsif extract(dow from p_data) = 0 then
    v_percentual := 100;
  elsif extract(dow from p_data) = 6 then
    v_percentual := 50;
  else
    v_percentual := 0;
  end if;
  v_codigo_tipo := case v_percentual when 50 then 'EXTRA_50' when 100 then 'EXTRA_100' else 'NORMAL' end;

  select hm.hh_tipo_id into v_hh_tipo_id
  from public.hh_tipos_mapping hm
  join public.tipos_horas th on th.id = hm.tipo_hora_id
  where hm.tenant_id = v_tenant_id
    and hm.ativo is true
    and th.tenant_id = v_tenant_id
    and th.ativo is true
    and th.codigo = v_codigo_tipo
  limit 1;
  if v_hh_tipo_id is null then
    return jsonb_build_object('sucesso', false, 'lancamento_id', null, 'horas', null, 'erros', jsonb_build_array(jsonb_build_object('tipo', 'configuracao_hh', 'mensagem', 'Não existe configuração ativa para o tipo HH desta data.')));
  end if;

  if not exists (
    select 1
    from public.cliente_hh_tabelas tabela
    where tabela.tenant_id = v_tenant_id
      and tabela.empresa_id = v_empresa_id
      and tabela.cliente_id = v_cliente_id
      and tabela.ativo is true
      and p_data between tabela.vigencia_inicio and tabela.vigencia_fim
  ) then
    return jsonb_build_object('sucesso', false, 'lancamento_id', null, 'horas', null, 'erros', jsonb_build_array(jsonb_build_object('tipo', 'tabela_hh', 'mensagem', 'Não há tabela HH ativa e vigente para este cliente na data informada.')));
  end if;

  select case v_percentual
           when 50 then servico.preco_50
           when 100 then servico.preco_100
           else servico.preco_base
         end
    into v_preco_aplicavel
  from public.cliente_hh_servicos servico
  where servico.id = p_hh_servico_id
    and servico.tenant_id = v_tenant_id
    and servico.empresa_id = v_empresa_id
    and servico.cliente_id = v_cliente_id
    and servico.ativo is true
    and exists (
      select 1
      from public.colaborador_cliente_funcao vinculo
      where vinculo.tenant_id = v_tenant_id
        and vinculo.empresa_id = v_empresa_id
        and vinculo.cliente_id = v_cliente_id
        and vinculo.colaborador_id = p_colaborador_id
        and vinculo.hh_servico_id = servico.id
        and vinculo.ativo is true
    );
  if v_preco_aplicavel is null then
    return jsonb_build_object('sucesso', false, 'lancamento_id', null, 'horas', null, 'erros', jsonb_build_array(jsonb_build_object('tipo', 'especialidade', 'mensagem', 'A especialidade não está ativa ou não possui vínculo ativo para este colaborador e cliente.')));
  end if;
  if v_preco_aplicavel <= 0 then
    return jsonb_build_object('sucesso', false, 'lancamento_id', null, 'horas', null, 'erros', jsonb_build_array(jsonb_build_object('tipo', 'preco_hh', 'mensagem', 'A especialidade não possui preço HH válido para o tipo de dia informado. Ajuste a configuração no sistema web.')));
  end if;

  select format('OS %s, %s-%s', coalesce(os.numero_os, hl.os_id::text), to_char(intervalo.inicio, 'HH24:MI'), to_char(intervalo.fim, 'HH24:MI'))
    into v_conflito
  from public.hh_lancamentos hl
  join public.ordens_servico os
    on os.id = hl.os_id
   and os.tenant_id = hl.tenant_id
   and os.empresa_id = hl.empresa_id
  cross join lateral (
    select hl.entrada_1 as inicio, hl.saida_1 as fim
    where hl.entrada_1 is not null and hl.saida_1 is not null
    union all
    select hl.entrada_2, hl.saida_2
    where hl.entrada_2 is not null and hl.saida_2 is not null
    union all
    select hl.hora_entrada, hl.hora_saida
    where hl.entrada_1 is null and hl.hora_entrada is not null and hl.hora_saida is not null
  ) intervalo
  cross join lateral (
    select p_entrada_1 as inicio, p_saida_1 as fim
    union all
    select p_entrada_2, p_saida_2
    where p_entrada_2 is not null and p_saida_2 is not null
  ) novo_intervalo
  where hl.tenant_id = v_tenant_id
    and hl.empresa_id = v_empresa_id
    and hl.colaborador_id = p_colaborador_id
    and hl.data = p_data
    and novo_intervalo.inicio < intervalo.fim
    and novo_intervalo.fim > intervalo.inicio
  order by hl.criado_em, hl.id
  limit 1;
  if v_conflito is not null then
    return jsonb_build_object('sucesso', false, 'lancamento_id', null, 'horas', null, 'erros', jsonb_build_array(jsonb_build_object('tipo', 'sobreposicao', 'mensagem', format('Há sobreposição com lançamento HH já existente na %s.', v_conflito))));
  end if;

  insert into public.hh_lancamentos (
    tenant_id,
    empresa_id,
    os_id,
    colaborador_id,
    hh_tipo_id,
    hh_servico_id,
    data,
    hora_entrada,
    hora_saida,
    horas_trabalhadas,
    percentual_aplicado,
    tem_extra_50,
    horas_extra_50,
    tem_extra_100,
    horas_extra_100,
    observacao,
    criado_por,
    entrada_1,
    saida_1,
    entrada_2,
    saida_2
  ) values (
    v_tenant_id,
    v_empresa_id,
    p_os_id,
    p_colaborador_id,
    v_hh_tipo_id,
    p_hh_servico_id,
    p_data,
    p_entrada_1,
    coalesce(p_saida_2, p_saida_1),
    v_horas_efetivas,
    v_percentual,
    v_horas_extra_50 > 0,
    v_horas_extra_50,
    v_horas_extra_100 > 0,
    v_horas_extra_100,
    nullif(btrim(p_observacao), ''),
    nullif(auth.jwt() ->> 'email', ''),
    case when p_entrada_2 is null then null else p_entrada_1 end,
    case when p_saida_2 is null then null else p_saida_1 end,
    p_entrada_2,
    p_saida_2
  )
  returning id into v_lancamento_id;

  return jsonb_build_object('sucesso', true, 'lancamento_id', v_lancamento_id, 'horas', v_horas_efetivas, 'erros', '[]'::jsonb);
end;
$$;

revoke all on function public.app_listar_especialidades_hh(integer, uuid) from public, anon, authenticated, service_role;
grant execute on function public.app_listar_especialidades_hh(integer, uuid) to authenticated;

revoke all on function public.app_lancar_hh(integer, uuid, date, bigint, time, time, time, time, smallint, numeric, numeric, text) from public, anon, authenticated, service_role;
grant execute on function public.app_lancar_hh(integer, uuid, date, bigint, time, time, time, time, smallint, numeric, numeric, text) to authenticated;
