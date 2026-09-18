-- =====================================================================================
-- Falta e afastamento registrados pela propria pessoa no tablet do PIN.
--
-- Pedido do Gabriel em 18/09/2026: "que o proprio pessoal que falte ou que vai se afastar
-- por uma ou duas horas ja deixe registrado ali no app". Ate aqui a falta era registro
-- exclusivo da coordenacao (20260916100000) e o tablet so apontava hora em OS, hora
-- interna e concluia tarefa. Agora o tablet ganha "Falta ou afastamento": a pessoa
-- identificada pelo PIN registra a PROPRIA falta, do dia inteiro ou de algumas horas
-- (consulta, atraso, saida mais cedo), escolhendo o motivo numa lista curta.
--
-- O que nao muda: e sempre 'falta' (sem atestado). Atestado ou declaracao continua sendo
-- marcado pela coordenacao (app_tarefas_marcar_atestado). A falta continua nao reservando
-- o dia (20260917130000). Nao grava hora nenhuma: falta e ausencia, nao apontamento. A
-- coordenacao segue registrando pelo app e pelo web como antes.
--
-- Janela: hoje e os 15 dias anteriores (como a hora no tablet) mais 30 dias a frente,
-- porque o pedido inclui avisar antes ("vou me afastar").
--
-- Rastro: tarefas.criado_por_sessao_id guarda a sessao do PIN (como
-- concluida_por_sessao_id ja fazia na conclusao); criado_por_user_id fica com a conta do
-- tablet, como nas horas. Idempotencia pela chave em tarefas_operacoes (operacao
-- 'tablet_falta'), o mesmo mecanismo de app_tablet_tarefa_concluir.
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 1. Rastro da sessao do PIN na criacao ---------------------------------------------------

alter table public.tarefas
  add column if not exists criado_por_sessao_id uuid references public.tablet_sessoes(id) on delete set null;

comment on column public.tarefas.criado_por_sessao_id is
  'Sessao do PIN quando a tarefa (hoje: a falta) foi registrada pela propria pessoa no tablet. Nula quando veio do app ou do web.';

-- 2. Ausencias pendentes da pessoa na janela do tablet -------------------------------------
--
-- Serve para a tela mostrar "ja registrado" antes de a pessoa registrar de novo e para o
-- recibo depois. So as ausencias (categoria <> 'os') pendentes com dia dentro da janela.

create or replace function public.fn_tablet_ausencias_da_pessoa(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_colaborador_id uuid,
  p_de date,
  p_ate date
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $fn$
  select coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', t.id,
             'data', t.data,
             'data_fim', (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date,
             'categoria', t.categoria,
             'medida', t.medida,
             'dias', t.dias,
             'horas', t.horas,
             'descricao', t.descricao,
             'pelo_tablet', t.criado_por_sessao_id is not null
           ) order by t.data, t.criado_em)
    from public.tarefas as t
    join public.tarefas_participantes as part
      on part.tarefa_id = t.id and part.colaborador_id = p_colaborador_id
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.categoria <> 'os'
      and t.situacao = 'pendente'
      and t.data is not null
      and t.data <= p_ate
      and (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date >= p_de
  ), '[]'::jsonb);
$fn$;

revoke all on function public.fn_tablet_ausencias_da_pessoa(uuid, uuid, uuid, date, date) from public, anon, authenticated;

-- Nao e stable: fn_tablet_validar_sessao trava e atualiza a sessao.
create or replace function public.app_tablet_ausencias(p_sessao_token text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $fn$
declare
  v_sessao public.tablet_sessoes := public.fn_tablet_validar_sessao(p_sessao_token);
  v_hoje date := public.fn_tablet_data_hoje();
begin
  if v_sessao.id is null then
    return public.fn_tablet_erro_sessao();
  end if;
  return jsonb_build_object(
    'sucesso', true,
    'hoje', v_hoje,
    'janela', jsonb_build_object('de', v_hoje - 15, 'ate', v_hoje + 30, 'hoje', v_hoje),
    'registradas', public.fn_tablet_ausencias_da_pessoa(v_sessao.tenant_id, v_sessao.empresa_id, v_sessao.colaborador_id, v_hoje - 15, v_hoje + 30)
  );
end;
$fn$;

comment on function public.app_tablet_ausencias(text) is
  'Tablet do PIN: ausencias pendentes da pessoa identificada, de 15 dias atras a 30 dias a frente. Para a tela de falta mostrar o que ja existe.';

revoke all on function public.app_tablet_ausencias(text) from public, anon;
grant execute on function public.app_tablet_ausencias(text) to authenticated;

-- 3. Registrar a propria falta ---------------------------------------------------------------

create or replace function public.app_tablet_registrar_falta(
  p_sessao_token text,
  p_data date,
  p_medida text,
  p_horas integer default null,
  p_minutos integer default null,
  p_motivo text default null,
  p_chave uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'extensions'
set row_security to 'off'
as $fn$
declare
  v_sessao public.tablet_sessoes := public.fn_tablet_validar_sessao(p_sessao_token);
  v_hoje date := public.fn_tablet_data_hoje();
  v_medida text := lower(btrim(coalesce(p_medida, '')));
  v_motivo text := left(btrim(coalesce(p_motivo, '')), 200);
  v_colaborador record;
  v_existente record;
  v_minutos integer;
  v_horas numeric;
  v_tarefa public.tarefas;
  v_resultado jsonb;
begin
  if v_sessao.id is null then
    return public.fn_tablet_erro_sessao();
  end if;
  if p_chave is null then
    return public.fn_tablet_erro('chave', 'Chave de envio ausente. Tente novamente.');
  end if;

  -- Reenvio da mesma chave (rede caiu depois de gravar): devolve o que ja foi gravado.
  perform pg_advisory_xact_lock(hashtextextended('tarefa-op:' || p_chave::text, 0));
  select op.resultado into v_resultado
  from public.tarefas_operacoes as op
  where op.chave = p_chave and op.tenant_id = v_sessao.tenant_id;
  if found then
    return v_resultado || jsonb_build_object('repetido', true);
  end if;

  select colab.id, colab.nome, colab.ativo, colab.user_id into v_colaborador
  from public.colaboradores as colab
  where colab.id = v_sessao.colaborador_id
    and colab.tenant_id = v_sessao.tenant_id
    and colab.empresa_id = v_sessao.empresa_id;
  if not found or not coalesce(v_colaborador.ativo, false) then
    update public.tablet_sessoes set encerrada_em = now(), encerrada_motivo = 'colaborador_inativo' where id = v_sessao.id;
    return public.fn_tablet_erro('colaborador_inativo', 'Seu cadastro de colaborador está inativo. Procure a coordenação.');
  end if;

  if v_medida not in ('dias', 'horas') then
    return public.fn_tablet_erro('medida', 'Escolha: o dia inteiro ou algumas horas.');
  end if;

  if p_data is null then
    return public.fn_tablet_erro('data', 'Informe o dia da falta.');
  elsif p_data < v_hoje - 15 or p_data > v_hoje + 30 then
    return public.fn_tablet_erro('data_fora_da_janela',
      format('Só é possível registrar de %s a %s (15 dias para trás e 30 para a frente). Fora disso, procure a coordenação.',
        to_char(v_hoje - 15, 'DD/MM/YYYY'), to_char(v_hoje + 30, 'DD/MM/YYYY')))
      || jsonb_build_object('janela', jsonb_build_object('de', v_hoje - 15, 'ate', v_hoje + 30, 'hoje', v_hoje));
  end if;

  if v_medida = 'horas' then
    if p_horas is null or p_minutos is null or p_horas < 0 or p_horas > 24 or p_minutos < 0 or p_minutos > 59 then
      return public.fn_tablet_erro('duracao', 'Informe horas entre 0 e 24 e minutos entre 0 e 59.');
    end if;
    v_minutos := p_horas * 60 + p_minutos;
    if v_minutos <= 0 then
      return public.fn_tablet_erro('duracao', 'Informe quanto tempo você ficou (ou vai ficar) fora.');
    elsif v_minutos >= 24 * 60 then
      return public.fn_tablet_erro('duracao', 'Para o dia todo, escolha "O dia inteiro".');
    end if;
    v_horas := round(v_minutos / 60.0, 2);
  else
    v_minutos := null;
    v_horas := null;
  end if;

  if char_length(v_motivo) = 0 then
    v_motivo := 'Registrada pela própria pessoa no tablet';
  end if;

  -- O que a pessoa ja tem naquele dia. Dia inteiro em cima de qualquer coisa, ou qualquer
  -- coisa em cima de um dia inteiro, e registro em dobro: a coordenacao resolve. Duas
  -- saidas de algumas horas no mesmo dia (consulta de manha, saida mais cedo) podem.
  select t.categoria, t.medida, t.horas into v_existente
  from public.tarefas as t
  join public.tarefas_participantes as part
    on part.tarefa_id = t.id and part.colaborador_id = v_sessao.colaborador_id
  where t.tenant_id = v_sessao.tenant_id
    and t.empresa_id = v_sessao.empresa_id
    and t.categoria <> 'os'
    and t.situacao = 'pendente'
    and t.data is not null
    and p_data in (select d from public.fn_tarefas_dias(t.data, t.dias, t.medida) as d)
    and (t.medida = 'dias' or v_medida = 'dias')
  order by (t.medida = 'dias') desc, t.criado_em
  limit 1;
  if found then
    return public.fn_tablet_erro('ja_registrada',
      format('Você já tem %s registrada em %s%s. Para alterar, procure a coordenação.',
        case v_existente.categoria
          when 'folga' then 'folga'
          when 'ferias' then 'férias'
          when 'outro' then 'uma ausência'
          else 'uma falta'
        end,
        to_char(p_data, 'DD/MM/YYYY'),
        case when v_existente.medida = 'horas'
             then format(' (%s h)', replace(trim(trailing '.' from trim(trailing '0' from v_existente.horas::text)), '.', ','))
             else ' (dia inteiro)'
        end))
      || jsonb_build_object('registradas', public.fn_tablet_ausencias_da_pessoa(v_sessao.tenant_id, v_sessao.empresa_id, v_sessao.colaborador_id, v_hoje - 15, v_hoje + 30));
  end if;

  begin
    insert into public.tarefas (
      tenant_id, empresa_id, os_id, tipo, data, descricao, situacao,
      categoria, dias, medida, horas, criado_por_user_id, atualizado_por_user_id, criado_por_sessao_id
    )
    values (
      v_sessao.tenant_id, v_sessao.empresa_id, null, 'agendada', p_data, v_motivo, 'pendente',
      'falta', 1, v_medida, v_horas, auth.uid(), auth.uid(), v_sessao.id
    )
    returning * into v_tarefa;

    insert into public.tarefas_participantes (tarefa_id, colaborador_id, usuario_id, criado_por_user_id)
    values (v_tarefa.id, v_colaborador.id, v_colaborador.user_id, auth.uid());
    -- Falta nao reserva o dia (20260917130000): nada em tarefas_reservas.
  exception
    when others then
      return public.fn_tablet_erro('banco', sqlerrm);
  end;

  v_resultado := jsonb_build_object(
    'sucesso', true,
    'tarefa_id', v_tarefa.id,
    'colaborador_id', v_colaborador.id,
    'colaborador_nome', v_colaborador.nome,
    'data', p_data,
    'medida', v_medida,
    'horas', v_horas,
    'minutos', v_minutos,
    'motivo', v_motivo,
    'hoje', v_hoje,
    'registradas', public.fn_tablet_ausencias_da_pessoa(v_sessao.tenant_id, v_sessao.empresa_id, v_sessao.colaborador_id, v_hoje - 15, v_hoje + 30)
  );

  insert into public.tarefas_operacoes (chave, tenant_id, operacao, tarefa_id, resultado)
  values (p_chave, v_sessao.tenant_id, 'tablet_falta', v_tarefa.id, v_resultado)
  on conflict (chave) do nothing;

  return v_resultado;
end;
$fn$;

comment on function public.app_tablet_registrar_falta(text, date, text, integer, integer, text, uuid) is
  'Tablet do PIN: a propria pessoa registra falta (sem atestado) do dia inteiro (medida dias) ou de algumas horas (medida horas), de 15 dias atras a 30 a frente, com motivo curto. Nao reserva o dia; atestado continua com a coordenacao.';

revoke all on function public.app_tablet_registrar_falta(text, date, text, integer, integer, text, uuid) from public, anon;
grant execute on function public.app_tablet_registrar_falta(text, date, text, integer, integer, text, uuid) to authenticated;

-- 4. Conferencias ------------------------------------------------------------------------------

do $assertions$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'tarefas' and column_name = 'criado_por_sessao_id'
  ) then
    raise exception 'tarefas.criado_por_sessao_id nao foi criada';
  end if;
  if to_regprocedure('public.app_tablet_registrar_falta(text, date, text, integer, integer, text, uuid)') is null then
    raise exception 'app_tablet_registrar_falta nao existe';
  end if;
  if to_regprocedure('public.app_tablet_ausencias(text)') is null then
    raise exception 'app_tablet_ausencias nao existe';
  end if;
  -- A falta do tablet depende de a falta continuar sem reservar o dia.
  if pg_get_functiondef('public.fn_tarefas_reservar_intervalo(public.tarefas, uuid, uuid, uuid, boolean, uuid)'::regprocedure)
     not like '%categoria in (''falta'', ''falta_justificada'')%' then
    raise exception 'fn_tarefas_reservar_intervalo voltou a reservar a falta';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
