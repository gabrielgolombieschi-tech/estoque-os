-- O job enviar-push-notificacoes-1min mandava Authorization: Bearer com o
-- segredo proprio da Function (push_dispatch_token). O gateway das Edge
-- Functions valida o formato do JWT antes de entregar a requisicao, entao um
-- token que nao e JWT parava em 401 UNAUTHORIZED_INVALID_JWT_FORMAT e a
-- Function nunca era executada.
--
-- Passa a usar service_role_key, igual aos jobs de NF-e (nfe-reconciliar), que
-- e um JWT valido para o gateway. A Function continua conferindo o header
-- contra a propria SUPABASE_SERVICE_ROLE_KEY, entao o JWT do aplicativo segue
-- sem acesso a fila.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

select cron.alter_job(
  job_id := (select jobid from cron.job where jobname = 'enviar-push-notificacoes-1min'),
  command := $job$
      select net.http_post(
        url := project_url.decrypted_secret || '/functions/v1/enviar-push-notificacoes',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || service_key.decrypted_secret
        ),
        body := '{}'::jsonb
      )
      from vault.decrypted_secrets project_url
      join vault.decrypted_secrets service_key on service_key.name = 'service_role_key'
      where project_url.name = 'project_url';
    $job$
);

do $assert$
begin
  if not exists (
    select 1
    from cron.job
    where jobname = 'enviar-push-notificacoes-1min'
      and active
      and command like '%service_role_key%'
      and command not like '%push_dispatch_token%'
  ) then
    raise exception 'push_cron_nao_atualizado';
  end if;
end;
$assert$;

commit;
