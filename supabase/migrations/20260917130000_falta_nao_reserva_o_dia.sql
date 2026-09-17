-- Falta nao reserva o dia: quem ja tinha tarefa marcada e faltou continua podendo
-- ser marcado como falta.
--
-- Pedido do Gabriel em 16/09/2026, na tela "Marcar falta" do aplicativo: quem estava
-- reservado numa OS naquele dia aparecia travado e a falta nao saia ("Mesmo que esteja
-- agenda! Tem que liberar dar falta!"). Ate aqui a falta em dias inteiros reservava o dia
-- como qualquer ausencia, e o indice unico de uma reserva por pessoa e dia barrava a
-- segunda (colaborador_reservado).
--
-- Falta e registro do que aconteceu, nao agendamento: a pessoa tinha tarefa e nao veio.
-- Por isso ela deixa de reservar o dia (em dias ou em horas), a tarefa da OS continua na
-- agenda para a coordenacao reagendar ou tirar a pessoa, e a agenda passa a mostrar a
-- falta em dias pela propria tarefa, como ja fazia com a ausencia em horas.
--
-- Folga, ferias e outras ausencias em dias continuam reservando: elas sao planejadas e o
-- conflito com uma OS e real.

-- 1. Reservar: falta fica de fora (fn_tarefas_reservar_intervalo de 20260912220000).
create or replace function public.fn_tarefas_reservar_intervalo(
  p_tarefa public.tarefas, p_colaborador_id uuid, p_usuario_id uuid, p_auth_uid uuid, p_gestao boolean, p_colaborador_proprio uuid
)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_dia date;
  v_conflito jsonb;
  v_reservadas integer := 0;
begin
  -- Ausencia em horas nao reserva: a pessoa trabalha o resto do dia.
  -- Falta nao reserva: e o registro de quem nao veio, com ou sem tarefa marcada.
  if p_tarefa.tipo <> 'agendada' or p_tarefa.medida = 'horas'
     or p_tarefa.categoria in ('falta', 'falta_justificada') then
    return 0;
  end if;

  for v_dia in select * from public.fn_tarefas_dias(p_tarefa.data, p_tarefa.dias, p_tarefa.medida) loop
    perform pg_advisory_xact_lock(hashtextextended('tarefa-reserva:' || p_colaborador_id::text || ':' || v_dia::text, 0));
    if p_usuario_id is not null then
      perform pg_advisory_xact_lock(hashtextextended('tarefa-reserva-usuario:' || p_usuario_id::text || ':' || v_dia::text, 0));
    end if;

    v_conflito := public.fn_tarefas_conflito(
      p_tarefa.tenant_id, p_tarefa.empresa_id, p_colaborador_id, p_usuario_id, v_dia,
      p_tarefa.id, p_auth_uid, p_gestao, p_colaborador_proprio
    );
    if v_conflito is not null then
      raise exception using errcode = 'P0T01', message = 'colaborador_reservado', detail = v_conflito::text;
    end if;

    insert into public.tarefas_reservas (tenant_id, empresa_id, tarefa_id, colaborador_id, usuario_id, data, criado_por_user_id)
    values (p_tarefa.tenant_id, p_tarefa.empresa_id, p_tarefa.id, p_colaborador_id, p_usuario_id, v_dia, p_auth_uid);
    v_reservadas := v_reservadas + 1;
  end loop;

  return v_reservadas;
end;
$function$;

revoke all on function public.fn_tarefas_reservar_intervalo(public.tarefas, uuid, uuid, uuid, boolean, uuid) from public, anon, authenticated;

-- 2. Agenda: a falta em dias nao tem reserva para pendurar a linha; vem da tarefa,
--    dia a dia, como a ausencia em horas (20260913000000). reserva_dia continua
--    dizendo "toma o dia inteiro", que e o caso da falta em dias.
create or replace function public.app_tarefas_agenda(p_de date, p_ate date)
returns table(data date, colaborador_id uuid, colaborador_nome text, tarefa_id uuid, situacao text, detalhe_visivel boolean, numero_os text, cliente_nome text, descricao text, categoria text, reserva_dia boolean, horas numeric)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_ctx record;
begin
  select * into v_ctx from public.fn_tarefas_contexto();
  if p_de is null or p_ate is null or p_ate < p_de or p_ate - p_de > 92 then
    raise exception 'Informe um período de até 93 dias.';
  end if;

  return query
  -- 1. O que reserva o dia: trabalho e ausência medida em dias.
  select
    r.data,
    r.colaborador_id,
    colab.nome::text,
    r.tarefa_id,
    t.situacao,
    vis.visivel,
    case when vis.visivel and t.categoria = 'os'
         then coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text) end,
    case when vis.visivel and t.categoria = 'os'
         then coalesce(nullif(btrim(os.cliente_nome), ''), 'Cliente não informado')::text end,
    case when vis.visivel then t.descricao end,
    t.categoria,
    true,
    null::numeric
  from public.tarefas_reservas as r
  join public.tarefas as t on t.id = r.tarefa_id
  left join public.ordens_servico as os on os.id = t.os_id
  join public.colaboradores as colab on colab.id = r.colaborador_id
  cross join lateral (
    select (v_ctx.gestao
            or (t.categoria = 'os' and coalesce(os.responsavel_aprovacao_id = v_ctx.auth_uid, false))
            or (v_ctx.colaborador_id is not null and exists (
                  select 1 from public.tarefas_participantes as p
                  where p.tarefa_id = t.id and p.colaborador_id = v_ctx.colaborador_id))) as visivel
  ) as vis
  where r.liberada_em is null
    and r.tenant_id = v_ctx.tenant_id
    and r.empresa_id = v_ctx.empresa_id
    and r.data between p_de and p_ate
    and (v_ctx.pode_criar or (v_ctx.colaborador_id is not null and r.colaborador_id = v_ctx.colaborador_id))

  union all

  -- 2. O que nao tem reserva para pendurar a linha: a ausência em horas e a falta.
  --    Vem da tarefa, dia a dia (a falta pode ter mais de um dia). Falta antiga, de
  --    quando ainda reservava, ja saiu na parte 1 e fica de fora aqui.
  select
    dia.data,
    part.colaborador_id,
    colab.nome::text,
    t.id,
    t.situacao,
    vis.visivel,
    null::text,
    null::text,
    case when vis.visivel then t.descricao end,
    t.categoria,
    t.medida = 'dias',
    case when t.medida = 'horas' then t.horas end
  from public.tarefas as t
  join public.tarefas_participantes as part on part.tarefa_id = t.id
  join public.colaboradores as colab on colab.id = part.colaborador_id
  cross join lateral public.fn_tarefas_dias(t.data, t.dias, t.medida) as dia(data)
  cross join lateral (
    select (v_ctx.gestao
            or (v_ctx.colaborador_id is not null and part.colaborador_id = v_ctx.colaborador_id)) as visivel
  ) as vis
  where t.tenant_id = v_ctx.tenant_id
    and t.empresa_id = v_ctx.empresa_id
    and t.categoria <> 'os'
    and (t.medida = 'horas' or t.categoria in ('falta', 'falta_justificada'))
    and t.situacao <> 'cancelada'
    and t.data is not null
    and dia.data between p_de and p_ate
    and not exists (
      select 1 from public.tarefas_reservas as r
      where r.tarefa_id = t.id and r.colaborador_id = part.colaborador_id and r.liberada_em is null
    )
    and (v_ctx.pode_criar or (v_ctx.colaborador_id is not null and part.colaborador_id = v_ctx.colaborador_id))

  order by 1, 3, 11 desc;
end;
$function$;

comment on function public.app_tarefas_agenda(date, date) is
  'Agenda por dia e pessoa: reservas (trabalho e ausencia em dias) mais a ausencia em horas e a falta, que nao reservam o dia. reserva_dia = true toma o dia inteiro.';

revoke all on function public.app_tarefas_agenda(date, date) from public, anon;
grant execute on function public.app_tarefas_agenda(date, date) to authenticated;
