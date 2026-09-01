-- Lançamento HH em lote para o aplicativo móvel. As validações são concluídas antes do insert.

create or replace function public.app_lancar_hh_lote(
  p_os_id integer,
  p_data date,
  p_entrada_1 time,
  p_saida_1 time,
  p_entrada_2 time default null,
  p_saida_2 time default null,
  p_percentual_manual smallint default null,
  p_observacao text default null,
  p_lancamentos jsonb default '[]'::jsonb
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
  v_percentual smallint;
  v_codigo_tipo text;
  v_hh_tipo_id bigint;
  v_horas_efetivas numeric(10,2);
  v_item jsonb;
  v_colaborador_id uuid;
  v_hh_servico_id bigint;
  v_nome_colaborador text;
  v_preco_aplicavel numeric;
  v_conflito text;
  v_colaborador_ids uuid[] := '{}'::uuid[];
  v_servico_ids bigint[] := '{}'::bigint[];
  v_erros jsonb := '[]'::jsonb;
  v_gravados integer := 0;
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

  if p_percentual_manual is not null and p_percentual_manual not in (0, 50, 100) then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'percentual', 'mensagem', 'O tipo HH manual deve ser normal, extra 50% ou extra 100%.'));
  end if;
  if p_lancamentos is null or jsonb_typeof(p_lancamentos) <> 'array' or jsonb_array_length(p_lancamentos) = 0 then
    v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'lancamentos', 'mensagem', 'Selecione ao menos um colaborador para o lançamento HH.'));
  end if;
  if jsonb_array_length(v_erros) > 0 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'horas', null, 'erros', v_erros);
  end if;

  v_horas_efetivas := round(
    extract(epoch from (p_saida_1 - p_entrada_1)) / 3600
    + case when p_entrada_2 is not null then extract(epoch from (p_saida_2 - p_entrada_2)) / 3600 else 0 end,
    2
  );
  if v_horas_efetivas <= 0 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'horas', null, 'erros', jsonb_build_array(jsonb_build_object('tipo', 'horario', 'mensagem', 'Os horários informados não resultam em horas trabalhadas válidas.')));
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
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'horas', null, 'erros', jsonb_build_array(jsonb_build_object('tipo', 'configuracao_hh', 'mensagem', 'Não existe configuração ativa para o tipo HH desta data.')));
  end if;

  if not exists (
    select 1 from public.cliente_hh_tabelas tabela
    where tabela.tenant_id = v_tenant_id
      and tabela.empresa_id = v_empresa_id
      and tabela.cliente_id = v_cliente_id
      and tabela.ativo is true
      and p_data between tabela.vigencia_inicio and tabela.vigencia_fim
  ) then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'horas', null, 'erros', jsonb_build_array(jsonb_build_object('tipo', 'tabela_hh', 'mensagem', 'Não há tabela HH ativa e vigente para este cliente na data informada.')));
  end if;

  for v_item in select value from jsonb_array_elements(p_lancamentos) loop
    begin
      v_colaborador_id := nullif(v_item->>'colaborador_id', '')::uuid;
    exception when others then
      v_colaborador_id := null;
    end;
    begin
      v_hh_servico_id := nullif(v_item->>'hh_servico_id', '')::bigint;
    exception when others then
      v_hh_servico_id := null;
    end;

    if v_colaborador_id is null or v_hh_servico_id is null then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'lancamentos', 'mensagem', 'Há um colaborador sem especialidade HH válida.'));
      continue;
    end if;
    if v_colaborador_id = any(v_colaborador_ids) then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'lancamentos', 'mensagem', 'O mesmo colaborador foi selecionado mais de uma vez.'));
      continue;
    end if;

    select colaborador.nome into v_nome_colaborador
    from public.colaboradores colaborador
    where colaborador.id = v_colaborador_id
      and colaborador.tenant_id = v_tenant_id
      and colaborador.empresa_id = v_empresa_id
      and colaborador.ativo is true;
    if v_nome_colaborador is null then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'colaborador', 'mensagem', format('O colaborador %s está inativo ou não pertence à empresa atual.', v_colaborador_id)));
      continue;
    end if;
    if upper(v_papel_empresa) = 'APONTADOR' and v_colaborador_id <> v_colaborador_proprio_id then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'permissao', 'mensagem', format('%s: o perfil APONTADOR só pode lançar HH para o próprio colaborador vinculado.', v_nome_colaborador)));
      continue;
    end if;

    select case v_percentual when 50 then servico.preco_50 when 100 then servico.preco_100 else servico.preco_base end
      into v_preco_aplicavel
    from public.cliente_hh_servicos servico
    where servico.id = v_hh_servico_id
      and servico.tenant_id = v_tenant_id
      and servico.empresa_id = v_empresa_id
      and servico.cliente_id = v_cliente_id
      and servico.ativo is true
      and exists (
        select 1 from public.colaborador_cliente_funcao vinculo
        where vinculo.tenant_id = v_tenant_id
          and vinculo.empresa_id = v_empresa_id
          and vinculo.cliente_id = v_cliente_id
          and vinculo.colaborador_id = v_colaborador_id
          and vinculo.hh_servico_id = servico.id
          and vinculo.ativo is true
      );
    if v_preco_aplicavel is null then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'especialidade', 'mensagem', format('%s: a especialidade não está ativa ou não possui vínculo ativo para este cliente.', v_nome_colaborador)));
      continue;
    end if;
    if v_preco_aplicavel <= 0 then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'preco_hh', 'mensagem', format('%s: a especialidade não possui preço HH válido para o tipo de dia informado. Ajuste a configuração no sistema web.', v_nome_colaborador)));
      continue;
    end if;

    select format('OS %s, %s-%s', coalesce(os.numero_os, hl.os_id::text), to_char(intervalo.inicio, 'HH24:MI'), to_char(intervalo.fim, 'HH24:MI'))
      into v_conflito
    from public.hh_lancamentos hl
    join public.ordens_servico os on os.id = hl.os_id and os.tenant_id = hl.tenant_id and os.empresa_id = hl.empresa_id
    cross join lateral (
      select hl.entrada_1 as inicio, hl.saida_1 as fim where hl.entrada_1 is not null and hl.saida_1 is not null
      union all select hl.entrada_2, hl.saida_2 where hl.entrada_2 is not null and hl.saida_2 is not null
      union all select hl.hora_entrada, hl.hora_saida where hl.entrada_1 is null and hl.hora_entrada is not null and hl.hora_saida is not null
    ) intervalo
    cross join lateral (
      select p_entrada_1 as inicio, p_saida_1 as fim
      union all select p_entrada_2, p_saida_2 where p_entrada_2 is not null and p_saida_2 is not null
    ) novo_intervalo
    where hl.tenant_id = v_tenant_id
      and hl.empresa_id = v_empresa_id
      and hl.colaborador_id = v_colaborador_id
      and hl.data = p_data
      and novo_intervalo.inicio < intervalo.fim
      and novo_intervalo.fim > intervalo.inicio
    order by hl.criado_em, hl.id
    limit 1;
    if v_conflito is not null then
      v_erros := v_erros || jsonb_build_array(jsonb_build_object('tipo', 'sobreposicao', 'mensagem', format('%s: há sobreposição com lançamento HH já existente na %s.', v_nome_colaborador, v_conflito)));
      continue;
    end if;

    v_colaborador_ids := array_append(v_colaborador_ids, v_colaborador_id);
    v_servico_ids := array_append(v_servico_ids, v_hh_servico_id);
  end loop;

  if jsonb_array_length(v_erros) > 0 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'horas', null, 'erros', v_erros);
  end if;

  insert into public.hh_lancamentos (
    tenant_id, empresa_id, os_id, colaborador_id, hh_tipo_id, hh_servico_id,
    data, hora_entrada, hora_saida, horas_trabalhadas, percentual_aplicado,
    tem_extra_50, horas_extra_50, tem_extra_100, horas_extra_100, observacao,
    criado_por, entrada_1, saida_1, entrada_2, saida_2
  )
  select
    v_tenant_id, v_empresa_id, p_os_id, v_colaborador_ids[i], v_hh_tipo_id, v_servico_ids[i],
    p_data, p_entrada_1, coalesce(p_saida_2, p_saida_1), v_horas_efetivas, v_percentual,
    false, 0, false, 0, nullif(btrim(p_observacao), ''), nullif(auth.jwt()->>'email', ''),
    case when p_entrada_2 is null then null else p_entrada_1 end,
    case when p_saida_2 is null then null else p_saida_1 end,
    p_entrada_2, p_saida_2
  from generate_subscripts(v_colaborador_ids, 1) i;
  get diagnostics v_gravados = row_count;

  return jsonb_build_object('sucesso', true, 'gravados', v_gravados, 'horas', v_horas_efetivas, 'erros', '[]'::jsonb);
end;
$$;

revoke all on function public.app_lancar_hh_lote(integer, date, time, time, time, time, smallint, text, jsonb) from public, anon, authenticated, service_role;
grant execute on function public.app_lancar_hh_lote(integer, date, time, time, time, time, smallint, text, jsonb) to authenticated;
