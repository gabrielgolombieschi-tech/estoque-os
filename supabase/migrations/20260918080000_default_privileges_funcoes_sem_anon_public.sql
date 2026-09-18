-- Funcao nova criada pelo postgres (migrations, SQL editor) nos schemas expostos pela API
-- (public, f, m, c, a) nasce sem EXECUTE para anon e para PUBLIC; authenticated e service_role
-- continuam. Pedido do Gabriel em 18/09/2026.
--
-- ANTES (online, pg_default_acl do postgres para funcoes):
--   public : {postgres=X, anon=X, authenticated=X, service_role=X}   (padrao Supabase)
--   m      : {authenticated=X}
--   f, c, a: sem entrada -> padrao embutido do PostgreSQL (PUBLIC=X, anon incluso)
--   storage: {postgres=X, anon=X, authenticated=X, service_role=X}   (padrao Supabase, fica)
--   global : sem entrada
--
-- Por que o revoke e global: ALTER DEFAULT PRIVILEGES ... IN SCHEMA so soma ao padrao global e
-- nao consegue tirar o PUBLIC do padrao embutido ("Per-schema REVOKE is only useful to reverse
-- the effects of a previous per-schema GRANT", doc do PostgreSQL). Experimento no banco local
-- em 18/09/2026: revoke por schema em f + create function -> proacl NULL, anon executa.
-- Com o revoke global + grants por schema: f -> {postgres, authenticated, service_role};
-- public -> {postgres, authenticated, service_role}; m -> {postgres, authenticated, service_role}.
--
-- Efeito colateral assumido: funcao nova do postgres em schema sem entrada abaixo (r, vault,
-- net, ...) nasce so com o dono; a migration que a criar da o grant que precisar. As funcoes de
-- extensao instaladas pelo postgres (schema extensions: pgcrypto etc.) continuam publicas.
--
-- DEPOIS (esperado):
--   global    : {postgres=X}
--   public    : {postgres=X, authenticated=X, service_role=X}
--   f, m, c, a: {authenticated=X, service_role=X}  (+ dono)
--   extensions: {=X}  (PUBLIC, como hoje)
--   storage   : inalterado

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

alter default privileges for role postgres revoke execute on functions from public;

alter default privileges for role postgres in schema public revoke execute on functions from anon;
alter default privileges for role postgres in schema public grant execute on functions to authenticated, service_role;

alter default privileges for role postgres in schema f grant execute on functions to authenticated, service_role;
alter default privileges for role postgres in schema m grant execute on functions to authenticated, service_role;
alter default privileges for role postgres in schema c grant execute on functions to authenticated, service_role;
alter default privileges for role postgres in schema a grant execute on functions to authenticated, service_role;

alter default privileges for role postgres in schema extensions grant execute on functions to public;

-- Conferencia com funcoes descartaveis: anon nao executa, authenticated executa.
do $assert$
declare
  v_schema text;
  v_anon boolean;
  v_auth boolean;
  v_sr boolean;
begin
  foreach v_schema in array array['public', 'f', 'm', 'c', 'a'] loop
    execute format('create function %I.__acl_padrao_teste_20260918() returns integer language sql as $f$ select 1 $f$', v_schema);
    v_anon := has_function_privilege('anon', format('%I.__acl_padrao_teste_20260918()', v_schema), 'EXECUTE');
    v_auth := has_function_privilege('authenticated', format('%I.__acl_padrao_teste_20260918()', v_schema), 'EXECUTE');
    v_sr := has_function_privilege('service_role', format('%I.__acl_padrao_teste_20260918()', v_schema), 'EXECUTE');
    execute format('drop function %I.__acl_padrao_teste_20260918()', v_schema);
    raise notice 'default privileges em %: anon=% authenticated=% service_role=%', v_schema, v_anon, v_auth, v_sr;
    if v_anon or not v_auth or not v_sr then
      raise exception 'default privileges em % ficaram errados: anon=% authenticated=% service_role=%', v_schema, v_anon, v_auth, v_sr;
    end if;
  end loop;

  create function extensions.__acl_padrao_teste_20260918() returns integer language sql as $f$ select 1 $f$;
  v_auth := has_function_privilege('authenticated', 'extensions.__acl_padrao_teste_20260918()', 'EXECUTE');
  drop function extensions.__acl_padrao_teste_20260918();
  if not v_auth then
    raise exception 'default privileges em extensions deixaram de ser publicos';
  end if;
end;
$assert$;

commit;

-- Reversao: alter default privileges for role postgres grant execute on functions to public;
--           alter default privileges for role postgres in schema public grant execute on functions to anon;
--           e revoke das entradas por schema criadas acima (f, m, c, a, extensions).
