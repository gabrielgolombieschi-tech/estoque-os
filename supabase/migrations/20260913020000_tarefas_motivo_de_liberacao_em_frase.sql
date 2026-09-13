-- =====================================================================================
-- O histórico de reservas parava de mostrar código interno para a pessoa.
--
-- `tarefas_reservas.liberacao_motivo` guarda duas coisas na mesma coluna: o motivo
-- que uma pessoa digitou ("Terminou antes") e a marca de sistema que as RPCs
-- escrevem quando liberam por conta própria. O resultado chegava cru na tela, no
-- aplicativo e na web: "Liberado por Dario Diretor em 12/09/2026 às 21:33 ·
-- reagendada" e "· saiu_da_tarefa".
--
-- A tela não tem como distinguir uma coisa da outra — as duas são texto na mesma
-- coluna —, então quem traduz é o banco, na leitura. O que a pessoa digitou passa
-- inteiro; a marca de sistema vira frase.
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

create or replace function public.fn_tarefas_motivo_texto(p_motivo text)
returns text
language sql
immutable
set search_path to 'pg_catalog'
as $function$
  select case p_motivo
    when 'reagendada' then 'a tarefa foi reagendada'
    when 'passou_para_sem_data' then 'a tarefa passou para sem data'
    when 'troca_de_colaborador' then 'a pessoa foi trocada'
    when 'saiu_da_tarefa' then 'a pessoa saiu da tarefa'
    when 'cancelada' then 'a tarefa foi cancelada'
    when 'liberada_pela_gestao' then 'liberada pela gestão, sem motivo escrito'
    else p_motivo
  end;
$function$;

comment on function public.fn_tarefas_motivo_texto(text) is
  'Traduz a marca de sistema de tarefas_reservas.liberacao_motivo para frase. O motivo escrito por uma pessoa passa inteiro, porque a coluna guarda os dois.';

revoke all on function public.fn_tarefas_motivo_texto(text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_tarefas_linhas(p_tenant_id uuid, p_empresa_id uuid, p_auth_uid uuid, p_gestao boolean, p_colaborador_id uuid)
 RETURNS SETOF tarefa_linha
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET row_security TO 'off'
AS $function$
  with hoje as (select public.fn_tablet_data_hoje() as d)
  select
    t.id,
    t.tipo,
    t.data,
    t.situacao,
    part.colaborador_id,
    colab.nome::text,
    (p_colaborador_id is not null and part.colaborador_id = p_colaborador_id),
    t.os_id,
    case when t.categoria = 'os'
         then coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text) end,
    case when t.categoria = 'os' then os.cliente_id end,
    case when t.categoria = 'os'
         then coalesce(nullif(btrim(os.cliente_nome), ''), nullif(btrim(cli.nome), ''), 'Cliente não informado')::text end,
    case when t.categoria = 'os' then os.descricao_servico end,
    case when t.categoria = 'os'
         then coalesce(nullif(lower(os.status_fluxo), ''), public.mapear_status_legado_para_fluxo(os.status)) end,
    case when t.categoria = 'os' then coalesce(os.usa_relatorio_hh, false) end,
    case when t.categoria = 'os' then public.fn_tarefas_nome_usuario(os.responsavel_aprovacao_id) end,
    t.descricao,
    t.criado_em,
    public.fn_tarefas_nome_usuario(t.criado_por_user_id),
    t.atualizado_em,
    t.concluida_em,
    -- Quem fechou e quando: da PESSOA da linha, nao da tarefa inteira.
    case when part.concluida_em is null then null
         when part.concluida_por_sessao_id is not null then colab.nome::text || ' (pelo tablet)'
         else public.fn_tarefas_nome_usuario(part.concluida_por_user_id) end,
    part.concluida_por_sessao_id is not null,
    t.cancelada_em,
    public.fn_tarefas_nome_usuario(t.cancelada_por_user_id),
    t.cancelamento_motivo,
    reserva.ativa,
    ultima.liberada_em,
    public.fn_tarefas_nome_usuario(ultima.liberada_por_user_id),
    public.fn_tarefas_motivo_texto(ultima.liberacao_motivo),
    -- Atrasada e cobranca de TRABALHO. Ninguem conclui ferias, entao ausencia
    -- com data no passado nao fica vermelha: ela so terminou.
    (t.categoria = 'os' and t.situacao = 'pendente' and part.concluida_em is null
      and fim.data_fim is not null and fim.data_fim < hoje.d),
    (t.data is not null and hoje.d between t.data and fim.data_fim),
    gerir.pode,
    (t.situacao = 'pendente' and part.concluida_em is null
      and (gerir.pode or (p_colaborador_id is not null and part.colaborador_id = p_colaborador_id))),
    t.categoria,
    t.medida,
    t.dias,
    t.horas,
    fim.data_fim,
    (select count(*)::integer from public.tarefas_participantes as tp where tp.tarefa_id = t.id),
    part.concluida_em
  from public.tarefas as t
  join public.tarefas_participantes as part on part.tarefa_id = t.id
  join public.colaboradores as colab on colab.id = part.colaborador_id
  left join public.ordens_servico as os on os.id = t.os_id
  left join public.clientes as cli
    on cli.id = os.cliente_id and cli.tenant_id = t.tenant_id and cli.empresa_id = t.empresa_id
  cross join hoje
  cross join lateral (
    select case when t.data is null then null
                else (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date end as data_fim
  ) as fim
  cross join lateral (
    select (p_gestao or (t.categoria = 'os' and coalesce(os.responsavel_aprovacao_id = p_auth_uid, false))) as pode
  ) as gerir
  cross join lateral (
    select exists (
      select 1 from public.tarefas_reservas as r
      where r.tarefa_id = t.id and r.colaborador_id = part.colaborador_id and r.liberada_em is null
    ) as ativa
  ) as reserva
  left join lateral (
    select r.liberada_em, r.liberada_por_user_id, r.liberacao_motivo
    from public.tarefas_reservas as r
    where r.tarefa_id = t.id and r.colaborador_id = part.colaborador_id and r.liberada_em is not null
    order by r.liberada_em desc, r.ordem desc
    limit 1
  ) as ultima on true
  where t.tenant_id = p_tenant_id
    and t.empresa_id = p_empresa_id
    and (p_gestao
         or (t.categoria = 'os' and coalesce(os.responsavel_aprovacao_id = p_auth_uid, false))
         or (p_colaborador_id is not null and part.colaborador_id = p_colaborador_id));
$function$;

CREATE OR REPLACE FUNCTION public.app_tarefas_detalhe(p_tarefa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET row_security TO 'off'
AS $function$
declare
  v_ctx record;
  v_tarefa jsonb;
  v_reservas jsonb;
  v_participantes jsonb;
begin
  select * into v_ctx from public.fn_tarefas_contexto();
  v_tarefa := public.fn_tarefas_linha_json(p_tarefa_id, v_ctx.tenant_id, v_ctx.empresa_id, v_ctx.auth_uid, v_ctx.gestao, v_ctx.colaborador_id);
  if v_tarefa is null then
    return public.fn_tarefas_erro('tarefa_nao_encontrada', 'Tarefa não encontrada nesta empresa.');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id,
           'data', r.data,
           'colaborador_id', r.colaborador_id,
           'colaborador_nome', colab.nome,
           'criado_em', r.criado_em,
           'criado_por_nome', public.fn_tarefas_nome_usuario(r.criado_por_user_id),
           'ativa', r.liberada_em is null,
           'liberada_em', r.liberada_em,
           'liberada_por_nome', public.fn_tarefas_nome_usuario(r.liberada_por_user_id),
           'liberacao_motivo', public.fn_tarefas_motivo_texto(r.liberacao_motivo)
         ) order by r.ordem), '[]'::jsonb)
    into v_reservas
  from public.tarefas_reservas as r
  join public.colaboradores as colab on colab.id = r.colaborador_id
  where r.tarefa_id = p_tarefa_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'colaborador_id', p.colaborador_id,
           'nome', colab.nome,
           'concluida_em', p.concluida_em,
           'concluida_por_nome', case when p.concluida_em is null then null
                                      when p.concluida_por_sessao_id is not null then colab.nome::text || ' (pelo tablet)'
                                      else public.fn_tarefas_nome_usuario(p.concluida_por_user_id) end,
           'concluida_pelo_tablet', p.concluida_por_sessao_id is not null
         ) order by colab.nome), '[]'::jsonb)
    into v_participantes
  from public.tarefas_participantes as p
  join public.colaboradores as colab on colab.id = p.colaborador_id
  where p.tarefa_id = p_tarefa_id;

  return jsonb_build_object(
    'sucesso', true,
    'tarefa', v_tarefa,
    'participantes', v_participantes,
    'reservas', v_reservas
  );
end;
$function$;

revoke all on function public.fn_tarefas_linhas(uuid, uuid, uuid, boolean, uuid) from public, anon, authenticated;
revoke all on function public.app_tarefas_detalhe(uuid) from public, anon;
grant execute on function public.app_tarefas_detalhe(uuid) to authenticated;

do $assertions$
declare
  v_texto text;
begin
  -- As marcas de sistema viram frase.
  for v_texto in select unnest(array['reagendada', 'saiu_da_tarefa', 'passou_para_sem_data',
                                     'troca_de_colaborador', 'cancelada', 'liberada_pela_gestao'])
  loop
    if public.fn_tarefas_motivo_texto(v_texto) = v_texto then
      raise exception 'a marca % continua chegando crua na tela', v_texto;
    end if;
    if public.fn_tarefas_motivo_texto(v_texto) like '%\_%' then
      raise exception 'a frase de % ainda tem sublinhado: %', v_texto, public.fn_tarefas_motivo_texto(v_texto);
    end if;
  end loop;

  -- O que a pessoa escreveu passa inteiro, inclusive nulo.
  if public.fn_tarefas_motivo_texto('Terminou antes') <> 'Terminou antes' then
    raise exception 'o motivo escrito por uma pessoa foi alterado';
  end if;
  if public.fn_tarefas_motivo_texto(null) is not null then
    raise exception 'motivo nulo devia continuar nulo';
  end if;

  -- E as duas leituras usam a traducao.
  if pg_get_functiondef('public.fn_tarefas_linhas(uuid, uuid, uuid, boolean, uuid)'::regprocedure)
     not like '%fn_tarefas_motivo_texto%' then
    raise exception 'fn_tarefas_linhas nao traduz o motivo';
  end if;
  if pg_get_functiondef('public.app_tarefas_detalhe(uuid)'::regprocedure)
     not like '%fn_tarefas_motivo_texto%' then
    raise exception 'app_tarefas_detalhe nao traduz o motivo';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
