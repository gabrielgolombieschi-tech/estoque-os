-- Habilita o agendamento diário da aprovação automática por SLA.
-- pg_cron usa GMT neste projeto; 00:15 GMT equivale a 21:15 do dia anterior
-- em America/Sao_Paulo (UTC-3).

create extension if not exists pg_cron;

do $$
declare
  v_job_id bigint;
begin
  select jobid
    into v_job_id
  from cron.job
  where jobname = 'aprovacao-horas-sla-diaria';

  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;

  perform cron.schedule(
    'aprovacao-horas-sla-diaria',
    '15 0 * * *',
    'select public.aprovar_apontamentos_vencidos();'
  );
end;
$$;
