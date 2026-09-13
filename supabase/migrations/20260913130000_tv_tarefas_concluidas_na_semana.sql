-- =====================================================================================
-- O cartão da televisão passa a mostrar o que foi concluído NA SEMANA.
--
-- Decisão do Gabriel em 13/09/2026, olhando o cartão do colaborador: ele fala de
-- "1h semana" e "1h no mês", mas as tarefas concluídas só apareciam se tivessem
-- sido fechadas HOJE. Quem fechou três tarefas na segunda aparecia na quinta como
-- se não tivesse feito nada.
--
-- A janela das concluídas passa de hoje para a semana corrente, contada a partir
-- da segunda-feira — a mesma referência que tv_periodos usa para as horas, para o
-- cartão inteiro falar do mesmo período.
--
-- As pendentes não mudam: continuam vindo todas, com ou sem data.
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

CREATE OR REPLACE FUNCTION public.tv_colaboradores_tarefas(p_area text DEFAULT NULL::text)
 RETURNS SETOF tarefa_linha
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET row_security TO 'off'
AS $function$
declare
  v_ctx record;
  v_area text := public.fn_tv_area(p_area);
  v_hoje date := public.fn_tablet_data_hoje();
  -- Segunda-feira desta semana, a mesma referencia que tv_periodos usa para as
  -- horas. O cartao fala da semana inteira, entao as tarefas fechadas nela
  -- tambem contam.
  v_inicio_semana date := (date_trunc('week', public.fn_tablet_data_hoje()::timestamp))::date;
begin
  select * into v_ctx from public.fn_tv_contexto();

  return query
  select
    t.id,
    t.tipo,
    t.data,
    t.situacao,
    part.colaborador_id,
    colab.nome::text,
    false,
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
    case when part.concluida_em is null then null
         when part.concluida_por_sessao_id is not null then colab.nome::text || ' (pelo tablet)'
         else public.fn_tarefas_nome_usuario(part.concluida_por_user_id) end,
    part.concluida_por_sessao_id is not null,
    t.cancelada_em,
    public.fn_tarefas_nome_usuario(t.cancelada_por_user_id),
    t.cancelamento_motivo,
    exists (select 1 from public.tarefas_reservas as r
            where r.tarefa_id = t.id and r.colaborador_id = part.colaborador_id and r.liberada_em is null),
    null::timestamptz,
    null::text,
    null::text,
    -- Atrasada e cobranca de trabalho: ausencia so terminou.
    (t.categoria = 'os' and t.situacao = 'pendente' and part.concluida_em is null and t.data is not null
      and (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date < v_hoje),
    (t.data is not null and v_hoje between t.data and (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date),
    false,
    false,
    t.categoria,
    t.medida,
    t.dias,
    t.horas,
    case when t.data is null then null
         else (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date end,
    (select count(*)::integer from public.tarefas_participantes as tp where tp.tarefa_id = t.id),
    part.concluida_em
  from public.tarefas as t
  join public.tarefas_participantes as part on part.tarefa_id = t.id
  join public.colaboradores as colab
    on colab.id = part.colaborador_id
   and colab.ativo is true
  left join public.ordens_servico as os on os.id = t.os_id
  left join public.clientes as cli
    on cli.id = os.cliente_id and cli.tenant_id = t.tenant_id and cli.empresa_id = t.empresa_id
  where t.tenant_id = v_ctx.tenant_id
    and t.empresa_id = v_ctx.empresa_id
    and (v_area is null or colab.area = v_area)
    and ((t.situacao = 'pendente' and part.concluida_em is null)
         or (part.concluida_em is not null
             and (part.concluida_em at time zone 'America/Sao_Paulo')::date >= v_inicio_semana
             and (part.concluida_em at time zone 'America/Sao_Paulo')::date <= v_hoje))
  order by
    (t.categoria = 'os' and t.situacao = 'pendente' and part.concluida_em is null and t.data is not null
      and (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date < v_hoje) desc,
    t.data asc nulls last,
    colab.nome asc,
    t.criado_em asc;
end;
$function$;

revoke all on function public.tv_colaboradores_tarefas(text) from public, anon;
grant execute on function public.tv_colaboradores_tarefas(text) to authenticated;

do $assertions$
begin
  if pg_get_functiondef('public.tv_colaboradores_tarefas(text)'::regprocedure)
     not like '%v_inicio_semana%' then
    raise exception 'tv_colaboradores_tarefas continua olhando so o dia de hoje';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
