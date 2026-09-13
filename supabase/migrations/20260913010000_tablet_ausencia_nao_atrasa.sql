-- =====================================================================================
-- O tablet parava de chamar folga e férias de "atrasada".
--
-- A Parte 6 da 20260912220000 tirou isso de fn_tarefas_linhas e de
-- tv_colaboradores_tarefas, mas app_tablet_tarefas tem a PRÓPRIA conta de atraso,
-- inline, e ficou de fora. Resultado, visto na tela do tablet: a folga de quatro
-- horas do colaborador aparecia como "07/09 Segunda-feira ATRASADA · Folga".
--
-- Atrasada é cobrança de TRABALHO. Ninguém conclui férias, então ausência com data
-- no passado apenas terminou — e cobrar isso da pessoa no tablet é errado.
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

CREATE OR REPLACE FUNCTION public.app_tablet_tarefas(p_sessao_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET row_security TO 'off'
AS $function$
declare
  v_sessao public.tablet_sessoes;
  v_hoje date := public.fn_tablet_data_hoje();
  v_colaborador_nome text;
  v_agendadas jsonb;
  v_sem_data jsonb;
  v_concluidas_hoje jsonb;
begin
  v_sessao := public.fn_tablet_validar_sessao(p_sessao_token);
  if v_sessao.id is null then
    return public.fn_tablet_erro_sessao();
  end if;

  select colab.nome into v_colaborador_nome from public.colaboradores as colab where colab.id = v_sessao.colaborador_id;

  with tarefas_do_colaborador as (
    select t.id,
           t.tipo,
           t.data,
           -- A situacao que interessa ao tablet e a DELE, nao a da tarefa toda.
           case when part.concluida_em is not null then 'concluida' else t.situacao end as situacao,
           t.descricao,
           part.concluida_em,
           t.criado_em,
           t.categoria,
           t.medida,
           t.dias,
           t.horas,
           case when t.data is null then null
                else (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date end as data_fim,
           (select count(*)::integer from public.tarefas_participantes as tp where tp.tarefa_id = t.id) as participantes,
           case when t.categoria = 'os'
                then coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text) end as numero_os,
           case when t.categoria = 'os'
                then coalesce(nullif(btrim(os.cliente_nome), ''), 'Cliente não informado') end as cliente_nome,
           case when t.categoria = 'os' then os.descricao_servico end as os_descricao,
           (t.categoria = 'os' and t.situacao = 'pendente' and part.concluida_em is null and t.data is not null
             and (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date < v_hoje) as atrasada,
           (t.data is not null and v_hoje between t.data and (t.data + (greatest(coalesce(t.dias, 1), 1) - 1))::date) as hoje
    from public.tarefas as t
    join public.tarefas_participantes as part
      on part.tarefa_id = t.id and part.colaborador_id = v_sessao.colaborador_id
    left join public.ordens_servico as os on os.id = t.os_id
    where t.tenant_id = v_sessao.tenant_id
      and t.empresa_id = v_sessao.empresa_id
      and ((t.situacao = 'pendente' and part.concluida_em is null)
           or (part.concluida_em is not null and (part.concluida_em at time zone 'America/Sao_Paulo')::date = v_hoje))
  )
  select
    coalesce((select jsonb_agg(to_jsonb(x) order by x.data, x.criado_em) from tarefas_do_colaborador as x where x.situacao = 'pendente' and x.tipo = 'agendada'), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(x) order by x.criado_em) from tarefas_do_colaborador as x where x.situacao = 'pendente' and x.tipo = 'sem_data'), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(x) order by x.concluida_em desc) from tarefas_do_colaborador as x where x.situacao = 'concluida'), '[]'::jsonb)
    into v_agendadas, v_sem_data, v_concluidas_hoje;

  return jsonb_build_object(
    'sucesso', true,
    'colaborador_id', v_sessao.colaborador_id,
    'colaborador_nome', v_colaborador_nome,
    'hoje', v_hoje,
    'agendadas', v_agendadas,
    'sem_data', v_sem_data,
    'concluidas_hoje', v_concluidas_hoje
  );
end;
$function$;

revoke all on function public.app_tablet_tarefas(text) from public, anon;
grant execute on function public.app_tablet_tarefas(text) to authenticated;

do $assertions$
begin
  if pg_get_functiondef('public.app_tablet_tarefas(text)'::regprocedure)
     not like '%t.categoria = ''os'' and t.situacao = ''pendente''%' then
    raise exception 'app_tablet_tarefas ainda marca ausencia como atrasada';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
