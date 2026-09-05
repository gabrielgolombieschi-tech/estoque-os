begin;

create or replace function f.fn_nfe_configurar_agendador(
  p_project_url text,
  p_service_role_key text
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
    raise exception using errcode = '42501', message = 'Somente service_role pode configurar o agendador.';
  end if;
  if p_project_url !~ '^https://[a-z0-9-]+\.supabase\.co$' then
    raise exception using errcode = '22023', message = 'URL do projeto Supabase invalida.';
  end if;
  if nullif(btrim(p_service_role_key), '') is null then
    raise exception using errcode = '22023', message = 'Service role key ausente.';
  end if;

  select id into v_id from vault.secrets where name = 'project_url' order by created_at desc limit 1;
  if v_id is null then
    perform vault.create_secret(p_project_url, 'project_url', 'URL usada pelo cron da reconciliacao NF-e');
  else
    perform vault.update_secret(v_id, p_project_url, 'project_url', 'URL usada pelo cron da reconciliacao NF-e');
  end if;

  select id into v_id from vault.secrets where name = 'service_role_key' order by created_at desc limit 1;
  if v_id is null then
    perform vault.create_secret(p_service_role_key, 'service_role_key', 'Credencial usada pelo cron da reconciliacao NF-e');
  else
    perform vault.update_secret(v_id, p_service_role_key, 'service_role_key', 'Credencial usada pelo cron da reconciliacao NF-e');
  end if;

  return jsonb_build_object(
    'configurado', true,
    'project_url', p_project_url,
    'service_role_key_armazenada', true
  );
end;
$$;

revoke all on function f.fn_nfe_configurar_agendador(text, text) from public, anon, authenticated;
grant execute on function f.fn_nfe_configurar_agendador(text, text) to service_role;

commit;
