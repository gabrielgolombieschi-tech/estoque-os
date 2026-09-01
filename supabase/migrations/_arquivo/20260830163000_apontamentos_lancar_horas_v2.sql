begin;

-- A tela passou a tratar repetição como aviso explícito. O banco continua
-- preservando a integridade relacional, mas não impede dois trabalhos reais
-- do mesmo tipo, na mesma OS e data.
drop trigger if exists trg_apontamento_bloquear_duplicidade on public.apontamentos_horas;

-- OS encerrada só recebe lançamento quando a função web registra a confirmação
-- na transação. Mobile e inserts diretos continuam bloqueados.
create or replace function public.fn_validar_apontamento_horas()
returns trigger
language plpgsql
set search_path = pg_catalog, public, a, c, f, m, r, auth, extensions
as $$
declare
  v_status_legado text;
  v_status_fluxo text;
  v_tem_taxa boolean;
  v_permitir_os_encerrada boolean := coalesce(current_setting('app.apontamento_permite_os_encerrada', true), '') = 'on';
begin
  select os.status, os.status_fluxo
    into v_status_legado, v_status_fluxo
  from public.ordens_servico as os
  where os.id = new.os_id
    and os.tenant_id = new.tenant_id
    and os.empresa_id = new.empresa_id;

  if v_status_legado is null then
    raise exception 'OS % não encontrada.', new.os_id;
  end if;
  if v_status_legado = 'cancelada' then
    raise exception 'Não é permitido lançar horas: OS % está cancelada.', new.os_id;
  end if;

  v_status_fluxo := coalesce(v_status_fluxo, public.mapear_status_legado_para_fluxo(v_status_legado));
  if v_status_fluxo not in ('em_andamento', 'em_andamento_garantia') then
    if not (
      v_permitir_os_encerrada
      and v_status_fluxo in ('concluida', 'faturada', 'concluida_garantia')
    ) then
      raise exception 'Não é permitido lançar horas: a OS % não está em andamento.', new.os_id;
    end if;
  end if;

  if coalesce(new.gerado_por_hh, false) then
    return new;
  end if;

  select exists (
    select 1
    from public.colaborador_taxas as taxa
    where taxa.colaborador_id = new.colaborador_id
      and taxa.tenant_id = new.tenant_id
      and taxa.empresa_id = new.empresa_id
      and new.data >= taxa.vigencia_inicio
      and (taxa.vigencia_fim is null or new.data <= taxa.vigencia_fim)
  ) into v_tem_taxa;

  if not v_tem_taxa then
    raise exception 'Não é permitido lançar horas: colaborador % não possui taxa vigente em %.', new.colaborador_id, new.data;
  end if;
  return new;
end;
$$;

-- A competência já é o corte oficial do ERP. Apontamentos manuais não podem
-- ser inseridos, editados ou apagados depois do fechamento.
create or replace function public.fn_apontamento_bloquear_competencia_fechada()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_data date;
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_gerado_por_hh boolean;
begin
  if tg_op = 'DELETE' then
    v_data := old.data;
    v_tenant_id := old.tenant_id;
    v_empresa_id := old.empresa_id;
    v_gerado_por_hh := coalesce(old.gerado_por_hh, false);
  else
    v_data := new.data;
    v_tenant_id := new.tenant_id;
    v_empresa_id := new.empresa_id;
    v_gerado_por_hh := coalesce(new.gerado_por_hh, false);
  end if;

  -- Espelhos HH seguem a trava e o ciclo próprios do módulo de origem.
  if v_gerado_por_hh then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_op = 'UPDATE' and exists (
    select 1
    from public.competencias as competencia
    where competencia.tenant_id = old.tenant_id
      and competencia.empresa_id = old.empresa_id
      and competencia.ano = extract(year from old.data)::integer
      and competencia.mes = extract(month from old.data)::integer
      and competencia.status = 'fechada'
  ) then
    raise exception using
      errcode = '55000',
      message = format('A competência %s está fechada e este apontamento não pode ser alterado.', to_char(old.data, 'MM/YYYY'));
  end if;

  if exists (
    select 1
    from public.competencias as competencia
    where competencia.tenant_id = v_tenant_id
      and competencia.empresa_id = v_empresa_id
      and competencia.ano = extract(year from v_data)::integer
      and competencia.mes = extract(month from v_data)::integer
      and competencia.status = 'fechada'
  ) then
    raise exception using
      errcode = '55000',
      message = format(
        'A competência %s está fechada e não permite %s de apontamentos.',
        to_char(v_data, 'MM/YYYY'),
        case tg_op when 'INSERT' then 'inclusão' when 'DELETE' then 'exclusão' else 'alteração' end
      );
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists trg_apontamento_competencia_fechada on public.apontamentos_horas;
create trigger trg_apontamento_competencia_fechada
before insert or update or delete on public.apontamentos_horas
for each row execute function public.fn_apontamento_bloquear_competencia_fechada();

-- Registra autor e conteúdo anterior também nas exclusões. A audit_log possui
-- RLS própria e captura auth.uid()/email do usuário que chamou a RPC.
drop trigger if exists trg_apontamentos_horas_audit on public.apontamentos_horas;
create trigger trg_apontamentos_horas_audit
after insert or update or delete on public.apontamentos_horas
for each row execute function public.audit_trigger();

create or replace function public.web_validar_data_apontamento(p_data date)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_fechada boolean;
begin
  if auth.uid() is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação, tenant e empresa ativos são obrigatórios.';
  end if;
  if not public.can('apontamentos', 'read', v_tenant_id) then
    raise exception 'Sem permissão para consultar apontamentos.';
  end if;
  if p_data is null then raise exception 'Informe a data.'; end if;

  select exists (
    select 1
    from public.competencias as competencia
    where competencia.tenant_id = v_tenant_id
      and competencia.empresa_id = v_empresa_id
      and competencia.ano = extract(year from p_data)::integer
      and competencia.mes = extract(month from p_data)::integer
      and competencia.status = 'fechada'
  ) into v_fechada;

  return jsonb_build_object(
    'fechada', v_fechada,
    'motivo', case when v_fechada then format('Competência %s fechada: inclusão e edição estão bloqueadas.', to_char(p_data, 'MM/YYYY')) else null end
  );
end;
$$;

create or replace function public.web_listar_apontamentos_horas(
  p_data_inicio date,
  p_data_fim date,
  p_os_id integer default null,
  p_colaborador_id uuid default null,
  p_tipo_hora_id uuid default null,
  p_busca text default null,
  p_limite integer default 5000
)
returns table (
  id uuid,
  os_id integer,
  numero_os text,
  cliente_nome text,
  descricao_servico text,
  colaborador_id uuid,
  colaborador_nome text,
  data date,
  horas numeric,
  tipo_hora_id uuid,
  tipo_codigo text,
  tipo_descricao text,
  fator_aplicado numeric,
  descricao text,
  status text,
  status_aprovacao text,
  criado_em timestamptz,
  criado_por_user_id uuid,
  criado_por_nome text,
  gerado_por_hh boolean,
  hh_lancamento_id bigint,
  entrada_1 text,
  saida_1 text,
  entrada_2 text,
  saida_2 text
)
language plpgsql
security definer
set search_path = pg_catalog, public, a, auth
set row_security = off
as $$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_busca text := nullif(btrim(p_busca), '');
begin
  if auth.uid() is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação, tenant e empresa ativos são obrigatórios.';
  end if;
  if not public.can('apontamentos', 'read', v_tenant_id) then
    raise exception 'Sem permissão para consultar apontamentos.';
  end if;
  if p_data_inicio is null or p_data_fim is null or p_data_inicio > p_data_fim then
    raise exception 'Período inválido.';
  end if;

  return query
  select
    apontamento.id,
    apontamento.os_id,
    os.numero_os::text,
    os.cliente_nome::text,
    os.descricao_servico::text,
    apontamento.colaborador_id,
    colaborador.nome::text,
    apontamento.data,
    apontamento.horas,
    apontamento.tipo_hora_id,
    tipo.codigo::text,
    tipo.descricao::text,
    apontamento.fator_aplicado,
    apontamento.descricao,
    apontamento.status::text,
    apontamento.status_aprovacao::text,
    apontamento.criado_em,
    apontamento.criado_por_user_id,
    usuario.nome::text,
    coalesce(apontamento.gerado_por_hh, false),
    apontamento.hh_lancamento_id,
    to_char(apontamento.hora_entrada_1, 'HH24:MI'),
    to_char(apontamento.hora_saida_1, 'HH24:MI'),
    to_char(apontamento.hora_entrada_2, 'HH24:MI'),
    to_char(apontamento.hora_saida_2, 'HH24:MI')
  from public.apontamentos_horas as apontamento
  join public.ordens_servico as os
    on os.id = apontamento.os_id
   and os.tenant_id = apontamento.tenant_id
   and os.empresa_id = apontamento.empresa_id
  join public.colaboradores as colaborador
    on colaborador.id = apontamento.colaborador_id
   and colaborador.tenant_id = apontamento.tenant_id
   and colaborador.empresa_id = apontamento.empresa_id
  left join public.tipos_horas as tipo
    on tipo.id = apontamento.tipo_hora_id
   and tipo.tenant_id = apontamento.tenant_id
  left join a.usuario as usuario
    on usuario.auth_user_id = apontamento.criado_por_user_id
   and usuario.deleted_at is null
  where apontamento.tenant_id = v_tenant_id
    and apontamento.empresa_id = v_empresa_id
    and apontamento.data between p_data_inicio and p_data_fim
    and (p_os_id is null or apontamento.os_id = p_os_id)
    and (p_colaborador_id is null or apontamento.colaborador_id = p_colaborador_id)
    and (p_tipo_hora_id is null or apontamento.tipo_hora_id = p_tipo_hora_id)
    and (
      v_busca is null
      or os.numero_os ilike '%' || v_busca || '%'
      or os.cliente_nome ilike '%' || v_busca || '%'
      or os.descricao_servico ilike '%' || v_busca || '%'
      or apontamento.descricao ilike '%' || v_busca || '%'
      or colaborador.nome ilike '%' || v_busca || '%'
    )
  order by apontamento.data desc, apontamento.criado_em desc
  limit least(greatest(coalesce(p_limite, 5000), 1), 5000);
end;
$$;

-- Mantém a assinatura existente. A confirmação de OS encerrada viaja em cada
-- item do JSON; chamadas antigas continuam com o comportamento bloqueado.
create or replace function public.web_criar_apontamentos_horas(p_lancamentos jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_item jsonb;
  v_os_id integer;
  v_total integer := 0;
  v_papel text;
  v_colaborador_proprio_id uuid;
  v_status_fluxo text;
  v_confirmar_os_encerrada boolean;
  v_novo_id uuid;
  v_ids jsonb := '[]'::jsonb;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;
  select ue.papel into v_papel
  from a.usuario as u
  join a.usuario_empresa as ue on ue.usuario_id = u.id
  where u.auth_user_id = v_auth_uid
    and u.ativo and u.deleted_at is null
    and ue.empresa_id = v_empresa_id and ue.ativo and ue.deleted_at is null
  limit 1;
  if v_papel is null then raise exception 'Não foi possível identificar seu papel na empresa atual.'; end if;

  select colaborador.id into v_colaborador_proprio_id
  from public.colaboradores as colaborador
  where colaborador.user_id = v_auth_uid
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo;

  if p_lancamentos is null or jsonb_typeof(p_lancamentos) <> 'array' or jsonb_array_length(p_lancamentos) = 0 then
    raise exception 'Informe ao menos um apontamento.';
  end if;

  for v_item in select value from jsonb_array_elements(p_lancamentos) loop
    perform set_config('app.apontamento_permite_os_encerrada', 'off', true);
    v_os_id := nullif(v_item->>'os_id', '')::integer;
    v_confirmar_os_encerrada := coalesce((v_item->>'confirmar_os_encerrada')::boolean, false);

    if upper(v_papel) = 'APONTADOR'
       and (v_colaborador_proprio_id is null or nullif(v_item->>'colaborador_id', '')::uuid <> v_colaborador_proprio_id) then
      raise exception 'O perfil APONTADOR só pode lançar horas para o próprio colaborador.';
    end if;

    select coalesce(os.status_fluxo, public.mapear_status_legado_para_fluxo(os.status))
      into v_status_fluxo
    from public.ordens_servico as os
    where os.id = v_os_id
      and os.tenant_id = v_tenant_id
      and os.empresa_id = v_empresa_id;

    if v_status_fluxo in ('em_andamento', 'em_andamento_garantia') then
      null;
    elsif v_status_fluxo in ('concluida', 'faturada', 'concluida_garantia') and v_confirmar_os_encerrada then
      perform set_config('app.apontamento_permite_os_encerrada', 'on', true);
    else
      raise exception 'A OS % não está disponível para apontamentos.', v_os_id;
    end if;

    insert into public.apontamentos_horas (
      tenant_id, empresa_id, os_id, colaborador_id, data, horas,
      tipo_hora_id, fator_aplicado, descricao, status,
      hora_entrada_1, hora_saida_1, hora_entrada_2, hora_saida_2,
      gerado_por_hh, criado_por_user_id
    ) values (
      v_tenant_id, v_empresa_id, v_os_id,
      (v_item->>'colaborador_id')::uuid,
      (v_item->>'data')::date,
      nullif(v_item->>'horas', '')::numeric,
      nullif(v_item->>'tipo_hora_id', '')::uuid,
      nullif(v_item->>'fator_aplicado', '')::numeric,
      nullif(btrim(v_item->>'descricao'), ''),
      'lancado',
      nullif(v_item->>'hora_entrada_1', '')::time,
      nullif(v_item->>'hora_saida_1', '')::time,
      nullif(v_item->>'hora_entrada_2', '')::time,
      nullif(v_item->>'hora_saida_2', '')::time,
      false,
      v_auth_uid
    ) returning id into v_novo_id;

    v_ids := v_ids || jsonb_build_array(v_novo_id);
    v_total := v_total + 1;
  end loop;

  perform set_config('app.apontamento_permite_os_encerrada', 'off', true);
  return jsonb_build_object('sucesso', true, 'gravados', v_total, 'ids', v_ids);
end;
$$;

revoke all on function public.web_validar_data_apontamento(date) from public, anon, authenticated, service_role;
grant execute on function public.web_validar_data_apontamento(date) to authenticated;

revoke all on function public.web_listar_apontamentos_horas(date,date,integer,uuid,uuid,text,integer) from public, anon, authenticated, service_role;
grant execute on function public.web_listar_apontamentos_horas(date,date,integer,uuid,uuid,text,integer) to authenticated;

revoke all on function public.web_criar_apontamentos_horas(jsonb) from public, anon, authenticated, service_role;
grant execute on function public.web_criar_apontamentos_horas(jsonb) to authenticated;

comment on function public.web_listar_apontamentos_horas(date,date,integer,uuid,uuid,text,integer) is
  'Lista apontamentos por período e empresa, já enriquecidos para a tela web, incluindo o autor do lançamento.';

commit;

notify pgrst, 'reload schema';
