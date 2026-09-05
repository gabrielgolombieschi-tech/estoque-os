-- Agenda a Edge Function `enviar-push-notificacoes` para drenar a fila
-- `app_notificacoes_push_entregas` a cada minuto. Sem este job as notificacoes
-- ficam so na tela interna do app (sino) e nunca chegam na central do celular.
--
-- Segue o mesmo padrao do cron `nfe-reconciliar-processando`
-- (20260901132000_nfe_pipeline_homologacao.sql): o job fica instalado desde ja,
-- mas so dispara quando `project_url` e `push_dispatch_token` existirem no Vault.
-- Nenhuma credencial e versionada.
--
-- Configuracao unica (rodar depois do `supabase db push`):
--   1) npx supabase functions deploy enviar-push-notificacoes --no-verify-jwt
--   2) npx supabase secrets set PUSH_DISPATCH_TOKEN=<segredo-longo>
--   3) select public.fn_push_configurar_agendador(
--        'https://<ref>.supabase.co', '<mesmo-segredo-longo>');
-- O valor do passo 2 (runtime da Function) e do passo 3 (Vault, usado pelo cron)
-- precisam ser identicos.

begin;

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

-- Guarda `project_url` (compartilhada com os demais crons) e o segredo exclusivo
-- do disparo de push no Vault. Restrita a service_role; nunca aceita chamada do app.
create or replace function public.fn_push_configurar_agendador(
  p_project_url text,
  p_push_dispatch_token text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_id uuid;
begin
  if current_user <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente service_role pode configurar o agendador de push.';
  end if;
  if p_project_url !~ '^https://[a-z0-9-]+\.supabase\.co$' then
    raise exception using errcode = '22023', message = 'URL do projeto Supabase invalida.';
  end if;
  if nullif(btrim(p_push_dispatch_token), '') is null then
    raise exception using errcode = '22023', message = 'PUSH_DISPATCH_TOKEN ausente.';
  end if;

  select id into v_id from vault.secrets where name = 'project_url' order by created_at desc limit 1;
  if v_id is null then
    perform vault.create_secret(p_project_url, 'project_url', 'URL usada pelos jobs de cron do projeto');
  else
    perform vault.update_secret(v_id, p_project_url, 'project_url', 'URL usada pelos jobs de cron do projeto');
  end if;

  select id into v_id from vault.secrets where name = 'push_dispatch_token' order by created_at desc limit 1;
  if v_id is null then
    perform vault.create_secret(p_push_dispatch_token, 'push_dispatch_token', 'Segredo do cron que dispara a Edge Function enviar-push-notificacoes');
  else
    perform vault.update_secret(v_id, p_push_dispatch_token, 'push_dispatch_token', 'Segredo do cron que dispara a Edge Function enviar-push-notificacoes');
  end if;

  return jsonb_build_object(
    'configurado', true,
    'project_url', p_project_url,
    'push_dispatch_token_armazenado', true
  );
end;
$$;

revoke all on function public.fn_push_configurar_agendador(text, text) from public, anon, authenticated;
grant execute on function public.fn_push_configurar_agendador(text, text) to service_role;

do $$
begin
  perform cron.unschedule(jobid)
  from cron.job
  where jobname = 'enviar-push-notificacoes-1min';

  perform cron.schedule(
    'enviar-push-notificacoes-1min',
    '* * * * *',
    $job$
      select net.http_post(
        url := project_url.decrypted_secret || '/functions/v1/enviar-push-notificacoes',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || push_token.decrypted_secret
        ),
        body := '{}'::jsonb
      )
      from vault.decrypted_secrets project_url
      join vault.decrypted_secrets push_token on push_token.name = 'push_dispatch_token'
      where project_url.name = 'project_url';
    $job$
  );
end;
$$;

notify pgrst, 'reload schema';

commit;
