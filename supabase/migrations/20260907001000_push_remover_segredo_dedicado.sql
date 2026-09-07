-- O despacho de push passou a usar service_role_key (20260906235500), igual aos
-- jobs de NF-e. O segredo dedicado push_dispatch_token, criado na tentativa
-- anterior, nao e mais lido por ninguem — sai do vault para nao ficar um
-- segredo orfao rodando junto dos que valem.
-- O par dele nos secrets da Edge Function sai por
-- `supabase secrets unset PUSH_DISPATCH_TOKEN`.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

delete from vault.secrets where name = 'push_dispatch_token';

do $assert$
begin
  if exists (select 1 from vault.secrets where name = 'push_dispatch_token') then
    raise exception 'push_dispatch_token_ainda_existe';
  end if;
  if not exists (select 1 from vault.secrets where name = 'service_role_key') then
    raise exception 'service_role_key_ausente';
  end if;
end;
$assert$;

commit;
