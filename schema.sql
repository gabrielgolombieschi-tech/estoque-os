--
-- PostgreSQL database dump
--

\restrict 9RnNqkTEEiOO1VweYj7VcVQi9yhrk1FZH35hLvA8L9wvmiYhytIYGl3jZqgEply

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: a; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA a;


--
-- Name: auth; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA auth;


--
-- Name: c; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA c;


--
-- Name: extensions; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA extensions;


--
-- Name: f; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA f;


--
-- Name: graphql; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA graphql;


--
-- Name: graphql_public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA graphql_public;


--
-- Name: pgbouncer; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA pgbouncer;


--
-- Name: r; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA r;


--
-- Name: realtime; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA realtime;


--
-- Name: storage; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA storage;


--
-- Name: vault; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA vault;


--
-- Name: pg_graphql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_graphql WITH SCHEMA graphql;


--
-- Name: EXTENSION pg_graphql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_graphql IS 'pg_graphql: GraphQL support';


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: supabase_vault; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;


--
-- Name: EXTENSION supabase_vault; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION supabase_vault IS 'Supabase Vault Extension';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: aal_level; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.aal_level AS ENUM (
    'aal1',
    'aal2',
    'aal3'
);


--
-- Name: code_challenge_method; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.code_challenge_method AS ENUM (
    's256',
    'plain'
);


--
-- Name: factor_status; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.factor_status AS ENUM (
    'unverified',
    'verified'
);


--
-- Name: factor_type; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.factor_type AS ENUM (
    'totp',
    'webauthn',
    'phone'
);


--
-- Name: oauth_authorization_status; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.oauth_authorization_status AS ENUM (
    'pending',
    'approved',
    'denied',
    'expired'
);


--
-- Name: oauth_client_type; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.oauth_client_type AS ENUM (
    'public',
    'confidential'
);


--
-- Name: oauth_registration_type; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.oauth_registration_type AS ENUM (
    'dynamic',
    'manual'
);


--
-- Name: oauth_response_type; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.oauth_response_type AS ENUM (
    'code'
);


--
-- Name: one_time_token_type; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.one_time_token_type AS ENUM (
    'confirmation_token',
    'reauthentication_token',
    'recovery_token',
    'email_change_token_new',
    'email_change_token_current',
    'phone_change_token'
);


--
-- Name: capability_pair; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.capability_pair AS (
	key text,
	resource text,
	action text
);


--
-- Name: item_finalidade; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.item_finalidade AS ENUM (
    'consumo',
    'materia_prima',
    'revenda',
    'imobilizado',
    'outros'
);


--
-- Name: os_gestao_area; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.os_gestao_area AS ENUM (
    'eletrico',
    'mecanico',
    'seguranca',
    'software'
);


--
-- Name: os_gestao_tipo; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.os_gestao_tipo AS ENUM (
    'projeto',
    'execucao'
);


--
-- Name: action; Type: TYPE; Schema: realtime; Owner: -
--

CREATE TYPE realtime.action AS ENUM (
    'INSERT',
    'UPDATE',
    'DELETE',
    'TRUNCATE',
    'ERROR'
);


--
-- Name: equality_op; Type: TYPE; Schema: realtime; Owner: -
--

CREATE TYPE realtime.equality_op AS ENUM (
    'eq',
    'neq',
    'lt',
    'lte',
    'gt',
    'gte',
    'in'
);


--
-- Name: user_defined_filter; Type: TYPE; Schema: realtime; Owner: -
--

CREATE TYPE realtime.user_defined_filter AS (
	column_name text,
	op realtime.equality_op,
	value text
);


--
-- Name: wal_column; Type: TYPE; Schema: realtime; Owner: -
--

CREATE TYPE realtime.wal_column AS (
	name text,
	type_name text,
	type_oid oid,
	value jsonb,
	is_pkey boolean,
	is_selectable boolean
);


--
-- Name: wal_rls; Type: TYPE; Schema: realtime; Owner: -
--

CREATE TYPE realtime.wal_rls AS (
	wal jsonb,
	is_rls_enabled boolean,
	subscription_ids uuid[],
	errors text[]
);


--
-- Name: buckettype; Type: TYPE; Schema: storage; Owner: -
--

CREATE TYPE storage.buckettype AS ENUM (
    'STANDARD',
    'ANALYTICS',
    'VECTOR'
);


--
-- Name: fn_can_manage_empresa(uuid); Type: FUNCTION; Schema: a; Owner: -
--

CREATE FUNCTION a.fn_can_manage_empresa(p_empresa_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'a', 'c', 'public'
    AS $$
  select a.fn_is_tenant_admin(a.fn_empresa_tenant_id(p_empresa_id));
$$;


--
-- Name: fn_current_usuario_id(); Type: FUNCTION; Schema: a; Owner: -
--

CREATE FUNCTION a.fn_current_usuario_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'a', 'c', 'public'
    AS $$
  select u.id
  from a.usuario u
  where u.auth_user_id = auth.uid()
    and u.deleted_at is null
  limit 1;
$$;


--
-- Name: fn_empresa_tenant_id(uuid); Type: FUNCTION; Schema: a; Owner: -
--

CREATE FUNCTION a.fn_empresa_tenant_id(p_empresa_id uuid) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'a', 'c', 'public'
    AS $$
  select e.tenant_id
  from c.empresa e
  where e.id = p_empresa_id
    and e.deleted_at is null
  limit 1;
$$;


--
-- Name: fn_is_admin_of_same_tenant(uuid); Type: FUNCTION; Schema: a; Owner: -
--

CREATE FUNCTION a.fn_is_admin_of_same_tenant(p_other_usuario_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'a', 'c', 'public'
    AS $$
  with me as (
    select u.id as usuario_id
    from a.usuario u
    where u.auth_user_id = auth.uid()
      and u.deleted_at is null
    limit 1
  )
  select exists (
    select 1
    from me
    join a.usuario_tenant ut_me
      on ut_me.usuario_id = me.usuario_id
    join a.usuario_tenant ut_other
      on ut_other.tenant_id = ut_me.tenant_id
     and ut_other.usuario_id = p_other_usuario_id
    where ut_me.deleted_at is null
      and ut_me.ativo = true
      and ut_me.papel in ('OWNER','ADMIN')
      and ut_other.deleted_at is null
      and ut_other.ativo = true
  );
$$;


--
-- Name: fn_is_tenant_admin(uuid); Type: FUNCTION; Schema: a; Owner: -
--

CREATE FUNCTION a.fn_is_tenant_admin(p_tenant_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'a', 'c', 'public'
    AS $$
  select exists (
    select 1
    from a.usuario u
    join a.usuario_tenant ut on ut.usuario_id = u.id
    where u.auth_user_id = auth.uid()
      and u.deleted_at is null
      and ut.deleted_at is null
      and ut.ativo = true
      and ut.tenant_id = p_tenant_id
      and ut.papel in ('OWNER','ADMIN')
  );
$$;


--
-- Name: fn_is_tenant_member(uuid); Type: FUNCTION; Schema: a; Owner: -
--

CREATE FUNCTION a.fn_is_tenant_member(p_tenant_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'a', 'c', 'public'
    AS $$
  select exists (
    select 1
    from a.usuario u
    join a.usuario_tenant ut on ut.usuario_id = u.id
    where u.auth_user_id = auth.uid()
      and u.deleted_at is null
      and ut.deleted_at is null
      and ut.ativo = true
      and ut.tenant_id = p_tenant_id
  );
$$;


--
-- Name: fn_map_papel_empresa(text); Type: FUNCTION; Schema: a; Owner: -
--

CREATE FUNCTION a.fn_map_papel_empresa(p text) RETURNS text
    LANGUAGE sql
    AS $$
  select case
    when p is null then 'ADMIN'
    when upper(p) in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','TECNICO','APONTAMENTO_RH','PAINEL_TV') then upper(p)
    when upper(p) in ('OWNER','CONTADOR','GESTOR') then 'ADMIN'
    else 'ADMIN'
  end;
$$;


--
-- Name: fn_map_papel_empresa_to_role(text); Type: FUNCTION; Schema: a; Owner: -
--

CREATE FUNCTION a.fn_map_papel_empresa_to_role(papel text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select case upper(coalesce(papel,''))
    when 'ADMIN' then 'admin'
    when 'FINANCEIRO' then 'financeiro'
    when 'COORDENACAO' then 'projetos'
    when 'TECNICO' then 'projetos'
    when 'COMPRAS' then 'estoque'
    when 'ALMOXARIFADO' then 'estoque'
    when 'APONTAMENTO_RH' then 'projetos'
    when 'PAINEL_TV' then 'projetos'
    else 'estoque'
  end
$$;


--
-- Name: fn_map_papel_tenant(text); Type: FUNCTION; Schema: a; Owner: -
--

CREATE FUNCTION a.fn_map_papel_tenant(p text) RETURNS text
    LANGUAGE sql
    AS $$
  select case
    when p is null then 'GESTOR'
    when upper(p) in ('OWNER','ADMIN','CONTADOR','GESTOR') then upper(p)
    when upper(p) in ('FINANCEIRO','COMPRAS','ALMOXARIFADO','TECNICO','COORDENACAO','APONTAMENTO_RH','PAINEL_TV') then 'GESTOR'
    else 'GESTOR'
  end;
$$;


--
-- Name: fn_map_papel_tenant_to_role(text); Type: FUNCTION; Schema: a; Owner: -
--

CREATE FUNCTION a.fn_map_papel_tenant_to_role(p_papel text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select case upper(coalesce(p_papel,''))
    when 'OWNER' then 'admin'
    when 'ADMIN' then 'admin'
    when 'CONTADOR' then 'fiscal'
    when 'GESTOR' then 'projetos'
    when 'FINANCEIRO' then 'financeiro'
    else 'estoque'
  end
$$;


--
-- Name: fn_set_updated_at(); Type: FUNCTION; Schema: a; Owner: -
--

CREATE FUNCTION a.fn_set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


--
-- Name: email(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.email() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;


--
-- Name: FUNCTION email(); Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON FUNCTION auth.email() IS 'Deprecated. Use auth.jwt() -> ''email'' instead.';


--
-- Name: jwt(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.jwt() RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$$;


--
-- Name: role(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.role() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;


--
-- Name: FUNCTION role(); Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON FUNCTION auth.role() IS 'Deprecated. Use auth.jwt() -> ''role'' instead.';


--
-- Name: uid(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.uid() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;


--
-- Name: FUNCTION uid(); Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON FUNCTION auth.uid() IS 'Deprecated. Use auth.jwt() -> ''sub'' instead.';


--
-- Name: current_empresa_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_empresa_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    SET row_security TO 'off'
    AS $$
  select coalesce(
    (
      select uec.empresa_id
      from public.user_empresa_context uec
      where uec.user_id = auth.uid()
        and uec.tenant_id = public.current_tenant_id()
      limit 1
    ),
    (
      select em.empresa_id
      from public.empresa_memberships em
      where em.user_id = auth.uid()
        and em.tenant_id = public.current_tenant_id()
        and em.status = 'active'
      order by em.criado_em asc
      limit 1
    ),
    (
      -- NOVO MODELO
      select ue.empresa_id
      from a.usuario u
      join a.usuario_empresa ue on ue.usuario_id = u.id
      join c.empresa e on e.id = ue.empresa_id
      where u.auth_user_id = auth.uid()
        and u.deleted_at is null
        and ue.deleted_at is null
        and ue.ativo = true
        and e.deleted_at is null
        and e.tenant_id = public.current_tenant_id()
      order by ue.created_at asc
      limit 1
    ),
    nullif(current_setting('app.current_empresa_id', true), '')::uuid
  );
$$;


--
-- Name: current_tenant_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_tenant_id() RETURNS uuid
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_tenant uuid;
begin
  -- contexto (se existir)
  begin
    select utc.tenant_id
      into v_tenant
    from public.user_tenant_context utc
    where utc.user_id = auth.uid()
    limit 1;

    if v_tenant is not null then
      return v_tenant;
    end if;
  exception when undefined_table then
    null;
  end;

  -- legacy memberships
  select tm.tenant_id
    into v_tenant
  from public.tenant_memberships tm
  where tm.user_id = auth.uid()
    and tm.status = 'active'
  order by tm.created_at asc nulls last
  limit 1;

  if v_tenant is not null then
    return v_tenant;
  end if;

  -- NOVO MODELO: a.usuario_tenant
  select ut.tenant_id
    into v_tenant
  from a.usuario u
  join a.usuario_tenant ut on ut.usuario_id = u.id
  where u.auth_user_id = auth.uid()
    and u.deleted_at is null
    and ut.deleted_at is null
    and ut.ativo = true
  order by ut.created_at asc
  limit 1;

  return v_tenant;
end;
$$;


--
-- Name: has_imobilizado_access(uuid, uuid); Type: FUNCTION; Schema: c; Owner: -
--

CREATE FUNCTION c.has_imobilizado_access(p_tenant uuid DEFAULT public.current_tenant_id(), p_empresa uuid DEFAULT public.current_empresa_id()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'c', 'public', 'a'
    SET row_security TO 'off'
    AS $$
  select
    -- ADMIN no TENANT (OWNER/ADMIN)
    exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut on ut.usuario_id = u.id
      where u.auth_user_id = auth.uid()
        and ut.tenant_id = p_tenant
        and ut.ativo = true
        and ut.deleted_at is null
        and ut.papel in ('OWNER','ADMIN')
    )
    or
    -- Papéis na EMPRESA (acessam imobilizado)
    exists (
      select 1
      from a.usuario u
      join a.usuario_empresa ue on ue.usuario_id = u.id
      join c.empresa e on e.id = ue.empresa_id
      where u.auth_user_id = auth.uid()
        and ue.empresa_id = p_empresa
        and ue.ativo = true
        and ue.deleted_at is null
        and ue.papel in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH')
        and e.deleted_at is null
        and e.tenant_id = p_tenant
    );
$$;


--
-- Name: i_ferramenta_gerar_codigo(uuid, uuid, uuid); Type: FUNCTION; Schema: c; Owner: -
--

CREATE FUNCTION c.i_ferramenta_gerar_codigo(p_tenant uuid, p_empresa uuid, p_categoria uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'c', 'public', 'a'
    SET row_security TO 'off'
    AS $$
declare
  v_prefixo text;
  v_num integer;
begin
  if p_categoria is null then
    raise exception 'categoria_id é obrigatório para gerar código automático';
  end if;

  select prefixo
    into v_prefixo
  from c.i_ferramenta_categoria
  where id = p_categoria
    and tenant_id = p_tenant
    and empresa_id = p_empresa
    and deleted_at is null
    and ativo = true;

  if v_prefixo is null then
    raise exception 'Categoria inválida/inativa para gerar código';
  end if;

  insert into c.i_ferramenta_codigo_seq (tenant_id, empresa_id, categoria_id, proximo_numero)
  values (p_tenant, p_empresa, p_categoria, 1)
  on conflict (tenant_id, empresa_id, categoria_id) do nothing;

  update c.i_ferramenta_codigo_seq
     set proximo_numero = proximo_numero + 1,
         updated_at = now()
   where tenant_id = p_tenant
     and empresa_id = p_empresa
     and categoria_id = p_categoria
   returning (proximo_numero - 1) into v_num;

  return upper(v_prefixo) || '-' || lpad(v_num::text, 6, '0');
end $$;


--
-- Name: trg_i_ferramenta_set_codigo(); Type: FUNCTION; Schema: c; Owner: -
--

CREATE FUNCTION c.trg_i_ferramenta_set_codigo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if tg_op = 'INSERT' then
    new.codigo := c.i_ferramenta_gerar_codigo(new.tenant_id, new.empresa_id, new.categoria_id);
  end if;

  new.codigo := upper(new.codigo);
  new.nome := upper(new.nome);

  return new;
end $$;


--
-- Name: grant_pg_cron_access(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.grant_pg_cron_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS (
    SELECT
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_cron'
  )
  THEN
    grant usage on schema cron to postgres with grant option;

    alter default privileges in schema cron grant all on tables to postgres with grant option;
    alter default privileges in schema cron grant all on functions to postgres with grant option;
    alter default privileges in schema cron grant all on sequences to postgres with grant option;

    alter default privileges for user supabase_admin in schema cron grant all
        on sequences to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on tables to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on functions to postgres with grant option;

    grant all privileges on all tables in schema cron to postgres with grant option;
    revoke all on table cron.job from postgres;
    grant select on table cron.job to postgres with grant option;
  END IF;
END;
$$;


--
-- Name: FUNCTION grant_pg_cron_access(); Type: COMMENT; Schema: extensions; Owner: -
--

COMMENT ON FUNCTION extensions.grant_pg_cron_access() IS 'Grants access to pg_cron';


--
-- Name: grant_pg_graphql_access(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.grant_pg_graphql_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
    func_is_graphql_resolve bool;
BEGIN
    func_is_graphql_resolve = (
        SELECT n.proname = 'resolve'
        FROM pg_event_trigger_ddl_commands() AS ev
        LEFT JOIN pg_catalog.pg_proc AS n
        ON ev.objid = n.oid
    );

    IF func_is_graphql_resolve
    THEN
        -- Update public wrapper to pass all arguments through to the pg_graphql resolve func
        DROP FUNCTION IF EXISTS graphql_public.graphql;
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language sql
        as $$
            select graphql.resolve(
                query := query,
                variables := coalesce(variables, '{}'),
                "operationName" := "operationName",
                extensions := extensions
            );
        $$;

        -- This hook executes when `graphql.resolve` is created. That is not necessarily the last
        -- function in the extension so we need to grant permissions on existing entities AND
        -- update default permissions to any others that are created after `graphql.resolve`
        grant usage on schema graphql to postgres, anon, authenticated, service_role;
        grant select on all tables in schema graphql to postgres, anon, authenticated, service_role;
        grant execute on all functions in schema graphql to postgres, anon, authenticated, service_role;
        grant all on all sequences in schema graphql to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on tables to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on functions to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on sequences to postgres, anon, authenticated, service_role;

        -- Allow postgres role to allow granting usage on graphql and graphql_public schemas to custom roles
        grant usage on schema graphql_public to postgres with grant option;
        grant usage on schema graphql to postgres with grant option;
    END IF;

END;
$_$;


--
-- Name: FUNCTION grant_pg_graphql_access(); Type: COMMENT; Schema: extensions; Owner: -
--

COMMENT ON FUNCTION extensions.grant_pg_graphql_access() IS 'Grants access to pg_graphql';


--
-- Name: grant_pg_net_access(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.grant_pg_net_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_net'
  )
  THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_roles
      WHERE rolname = 'supabase_functions_admin'
    )
    THEN
      CREATE USER supabase_functions_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION;
    END IF;

    GRANT USAGE ON SCHEMA net TO supabase_functions_admin, postgres, anon, authenticated, service_role;

    IF EXISTS (
      SELECT FROM pg_extension
      WHERE extname = 'pg_net'
      -- all versions in use on existing projects as of 2025-02-20
      -- version 0.12.0 onwards don't need these applied
      AND extversion IN ('0.2', '0.6', '0.7', '0.7.1', '0.8', '0.10.0', '0.11.0')
    ) THEN
      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;

      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;

      REVOKE ALL ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;
      REVOKE ALL ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;

      GRANT EXECUTE ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
      GRANT EXECUTE ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
    END IF;
  END IF;
END;
$$;


--
-- Name: FUNCTION grant_pg_net_access(); Type: COMMENT; Schema: extensions; Owner: -
--

COMMENT ON FUNCTION extensions.grant_pg_net_access() IS 'Grants access to pg_net';


--
-- Name: pgrst_ddl_watch(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.pgrst_ddl_watch() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN SELECT * FROM pg_event_trigger_ddl_commands()
  LOOP
    IF cmd.command_tag IN (
      'CREATE SCHEMA', 'ALTER SCHEMA'
    , 'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE'
    , 'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE'
    , 'CREATE VIEW', 'ALTER VIEW'
    , 'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW'
    , 'CREATE FUNCTION', 'ALTER FUNCTION'
    , 'CREATE TRIGGER'
    , 'CREATE TYPE', 'ALTER TYPE'
    , 'CREATE RULE'
    , 'COMMENT'
    )
    -- don't notify in case of CREATE TEMP table or other objects created on pg_temp
    AND cmd.schema_name is distinct from 'pg_temp'
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;


--
-- Name: pgrst_drop_watch(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.pgrst_drop_watch() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  obj record;
BEGIN
  FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
  LOOP
    IF obj.object_type IN (
      'schema'
    , 'table'
    , 'foreign table'
    , 'view'
    , 'materialized view'
    , 'function'
    , 'trigger'
    , 'type'
    , 'rule'
    )
    AND obj.is_temporary IS false -- no pg_temp objects
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;


--
-- Name: set_graphql_placeholder(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.set_graphql_placeholder() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $_$
    DECLARE
    graphql_is_dropped bool;
    BEGIN
    graphql_is_dropped = (
        SELECT ev.schema_name = 'graphql_public'
        FROM pg_event_trigger_dropped_objects() AS ev
        WHERE ev.schema_name = 'graphql_public'
    );

    IF graphql_is_dropped
    THEN
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language plpgsql
        as $$
            DECLARE
                server_version float;
            BEGIN
                server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);

                IF server_version >= 14 THEN
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql extension is not enabled.'
                            )
                        )
                    );
                ELSE
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql is only available on projects running Postgres 14 onwards.'
                            )
                        )
                    );
                END IF;
            END;
        $$;
    END IF;

    END;
$_$;


--
-- Name: FUNCTION set_graphql_placeholder(); Type: COMMENT; Schema: extensions; Owner: -
--

COMMENT ON FUNCTION extensions.set_graphql_placeholder() IS 'Reintroduces placeholder function for graphql_public.graphql';


--
-- Name: agendar_pagamento_ap(uuid, uuid, date, text, numeric, text, text); Type: FUNCTION; Schema: f; Owner: -
--

CREATE FUNCTION f.agendar_pagamento_ap(p_titulo_id uuid, p_conta_bancaria_id uuid, p_data_prevista date, p_forma_pagamento text, p_valor_previsto numeric, p_observacoes text DEFAULT NULL::text, p_change_reason text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'f', 'public', 'a', 'c'
    SET row_security TO 'off'
    AS $$
declare
  v_titulo f.titulo%rowtype;
  v_cb f.conta_bancaria%rowtype;

  v_user uuid;
begin
  if p_data_prevista is null then
    raise exception 'Data prevista obrigatoria';
  end if;

  if p_forma_pagamento is null or length(trim(p_forma_pagamento)) = 0 then
    raise exception 'Forma de pagamento obrigatoria';
  end if;

  if p_forma_pagamento not in ('PIX','BOLETO','TRANSFERENCIA','DINHEIRO','CARTAO','OUTROS') then
    raise exception 'Forma de pagamento invalida: %', p_forma_pagamento;
  end if;

  if p_valor_previsto is null or p_valor_previsto <= 0 then
    raise exception 'Valor previsto deve ser > 0';
  end if;

  -- auth: app ou SQL Editor (postgres/service_role)
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  -- carrega título
  select * into v_titulo
  from f.titulo
  where id = p_titulo_id
    and deleted_at is null;

  if not found then
    raise exception 'Titulo nao encontrado (id=%)', p_titulo_id;
  end if;

  if v_titulo.tipo <> 'AP' then
    raise exception 'Agendamento so permite titulo AP. Tipo atual=%', v_titulo.tipo;
  end if;

  if v_titulo.status not in ('PENDENTE','APROVADO','AGENDADO') then
    raise exception 'Titulo precisa estar PENDENTE/APROVADO/AGENDADO. Status atual=%', v_titulo.status;
  end if;

  if v_titulo.valor_aberto <= 0 then
    raise exception 'Titulo sem saldo em aberto';
  end if;

  -- permissão no app
  if auth.uid() is not null then
    if not f.has_finance_access(v_titulo.tenant_id, v_titulo.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();

  -- fallback SQL Editor
  if v_user is null then
    select ut.usuario_id into v_user
    from a.usuario_tenant ut
    where ut.tenant_id = v_titulo.tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
    order by ut.created_at nulls last
    limit 1;

    if v_user is null then
      raise exception 'Nao foi possivel determinar usuario executor. Execute pelo app.';
    end if;
  end if;

  -- conta bancária
  select * into v_cb
  from f.conta_bancaria
  where id = p_conta_bancaria_id
    and deleted_at is null;

  if not found then
    raise exception 'Conta bancaria nao encontrada (id=%)', p_conta_bancaria_id;
  end if;

  if v_cb.tenant_id <> v_titulo.tenant_id or v_cb.empresa_id <> v_titulo.empresa_id then
    raise exception 'Conta bancaria nao pertence ao mesmo tenant/empresa do titulo';
  end if;

  if round(p_valor_previsto,2) > round(v_titulo.valor_aberto,2) then
    raise exception 'Valor previsto (%) maior que saldo em aberto (%)', round(p_valor_previsto,2), round(v_titulo.valor_aberto,2);
  end if;

  -- upsert 1:1 por título
  insert into f.titulo_agendamento (
    tenant_id,
    titulo_id,
    conta_bancaria_id,
    data_prevista,
    forma_pagamento,
    valor_previsto,
    observacoes,
    change_reason,
    agendado_em,
    agendado_por,
    created_at, updated_at, created_by, updated_by
  )
  values (
    v_titulo.tenant_id,
    v_titulo.id,
    v_cb.id,
    p_data_prevista,
    p_forma_pagamento,
    round(p_valor_previsto,2),
    p_observacoes,
    p_change_reason,
    now(),
    v_user,
    now(), now(), v_user, v_user
  )
  on conflict (tenant_id, titulo_id) do update set
    conta_bancaria_id = excluded.conta_bancaria_id,
    data_prevista = excluded.data_prevista,
    forma_pagamento = excluded.forma_pagamento,
    valor_previsto = excluded.valor_previsto,
    observacoes = excluded.observacoes,
    change_reason = excluded.change_reason,
    agendado_em = now(),
    agendado_por = v_user,
    updated_at = now(),
    updated_by = v_user;

  -- status do título
  update f.titulo
     set status = 'AGENDADO',
         updated_at = now(),
         updated_by = v_user
   where id = v_titulo.id;

  -- evento
  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_titulo.tenant_id, v_titulo.empresa_id,
    'PAGAMENTO_AGENDADO',
    'f.titulo',
    v_titulo.id,
    jsonb_build_object(
      'conta_bancaria_id', v_cb.id,
      'data_prevista', p_data_prevista,
      'forma_pagamento', p_forma_pagamento,
      'valor_previsto', round(p_valor_previsto,2),
      'change_reason', p_change_reason
    ),
    now(), v_user
  );
end;
$$;


--
-- Name: aprovar_titulo_ap(uuid, uuid, integer, text, text); Type: FUNCTION; Schema: f; Owner: -
--

CREATE FUNCTION f.aprovar_titulo_ap(p_titulo_id uuid, p_motivo_compra_id uuid, p_os_id integer DEFAULT NULL::integer, p_motivo_outros_text text DEFAULT NULL::text, p_change_reason text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'f', 'public', 'a', 'c'
    SET row_security TO 'off'
    AS $$
declare
  v_titulo f.titulo%rowtype;
  v_motivo f.motivo_compra%rowtype;

  v_aprovador uuid;
begin
  -- permite SQL Editor (postgres/service_role); no app continua autenticado
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  -- carrega titulo
  select * into v_titulo
  from f.titulo
  where id = p_titulo_id
    and deleted_at is null;

  if not found then
    raise exception 'Titulo nao encontrado (id=%)', p_titulo_id;
  end if;

  if v_titulo.tipo <> 'AP' then
    raise exception 'Aprovacao so permite titulo AP. Tipo atual=%', v_titulo.tipo;
  end if;

  if v_titulo.status <> 'PENDENTE' then
    raise exception 'Titulo precisa estar PENDENTE para aprovar. Status atual=%', v_titulo.status;
  end if;

  -- permissão (somente ADMIN/FINANCEIRO no app)
  if auth.uid() is not null then
    if not f.has_finance_access(v_titulo.tenant_id, v_titulo.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  -- aprovador normal (app)
  v_aprovador := a.fn_current_usuario_id();

  -- ✅ fallback para SQL Editor: pega um OWNER/ADMIN do tenant
  if v_aprovador is null then
    select ut.usuario_id
      into v_aprovador
    from a.usuario_tenant ut
    where ut.tenant_id = v_titulo.tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
    order by ut.created_at nulls last
    limit 1;

    if v_aprovador is null then
      raise exception
        'Nao foi possivel determinar aprovador (a.fn_current_usuario_id() retornou null e nao existe OWNER/ADMIN no tenant). Execute pelo app.';
    end if;
  end if;

  -- =====================================================
  -- MOTIVO: busca por ID e realinha tenant se necessário
  -- =====================================================
  select * into v_motivo
  from f.motivo_compra
  where id = p_motivo_compra_id
    and deleted_at is null
    and ativo = true;

  if not found then
    raise exception 'Motivo de compra invalido/inativo (id=%)', p_motivo_compra_id;
  end if;

  if v_motivo.tenant_id <> v_titulo.tenant_id then
    if exists (
      select 1 from f.motivo_compra mc
      where mc.tenant_id = v_titulo.tenant_id
        and mc.codigo = v_motivo.codigo
        and mc.id <> v_motivo.id
        and mc.deleted_at is null
    ) then
      raise exception 'Conflito: ja existe motivo com codigo % no tenant do titulo', v_motivo.codigo;
    end if;

    if exists (
      select 1 from f.motivo_compra mc
      where mc.tenant_id = v_titulo.tenant_id
        and mc.nome = v_motivo.nome
        and mc.id <> v_motivo.id
        and mc.deleted_at is null
    ) then
      raise exception 'Conflito: ja existe motivo com nome % no tenant do titulo', v_motivo.nome;
    end if;

    update f.motivo_compra
       set tenant_id = v_titulo.tenant_id,
           updated_at = now(),
           updated_by = v_aprovador
     where id = v_motivo.id;

    select * into v_motivo
    from f.motivo_compra
    where id = p_motivo_compra_id
      and deleted_at is null
      and ativo = true;
  end if;

  -- validações do motivo
  if v_motivo.requires_os and p_os_id is null then
    raise exception 'Motivo "%" exige OS', v_motivo.nome;
  end if;

  if v_motivo.requires_text then
    if p_motivo_outros_text is null or length(trim(p_motivo_outros_text)) = 0 then
      raise exception 'Motivo "%" exige detalhamento em texto', v_motivo.nome;
    end if;
  end if;

  -- valida OS se informada
  if p_os_id is not null then
    if not exists (
      select 1
      from public.ordens_servico os
      where os.id = p_os_id
        and os.tenant_id = v_titulo.tenant_id
    ) then
      raise exception 'OS invalida (id=%) para este tenant', p_os_id;
    end if;
  end if;

  -- grava aprovação (upsert 1:1)
  insert into f.titulo_aprovacao (
    tenant_id,
    titulo_id,
    motivo_compra_id,
    motivo_outros_text,
    os_id,
    aprovado_em,
    aprovado_por,
    change_reason,
    created_at,
    updated_at,
    created_by,
    updated_by
  )
  values (
    v_titulo.tenant_id,
    v_titulo.id,
    v_motivo.id,
    p_motivo_outros_text,
    p_os_id,
    now(),
    v_aprovador,
    p_change_reason,
    now(),
    now(),
    v_aprovador,
    v_aprovador
  )
  on conflict (tenant_id, titulo_id) do update set
    motivo_compra_id = excluded.motivo_compra_id,
    motivo_outros_text = excluded.motivo_outros_text,
    os_id = excluded.os_id,
    aprovado_em = excluded.aprovado_em,
    aprovado_por = excluded.aprovado_por,
    change_reason = excluded.change_reason,
    updated_at = now(),
    updated_by = v_aprovador;

  -- status -> APROVADO
  update f.titulo
     set status = 'APROVADO',
         updated_at = now(),
         updated_by = v_aprovador
   where id = v_titulo.id;

  -- eventos
  insert into f.aprovacao_evento (
    tenant_id, empresa_id,
    acao, ref_table, ref_id,
    motivo, payload,
    created_at, created_by
  )
  values (
    v_titulo.tenant_id, v_titulo.empresa_id,
    'APROVOU', 'f.titulo', v_titulo.id,
    v_motivo.nome,
    jsonb_build_object(
      'motivo_compra_id', v_motivo.id,
      'motivo_codigo', v_motivo.codigo,
      'motivo_nome', v_motivo.nome,
      'os_id', p_os_id,
      'motivo_outros_text', p_motivo_outros_text,
      'change_reason', p_change_reason
    ),
    now(), v_aprovador
  );

  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_titulo.tenant_id, v_titulo.empresa_id,
    'TITULO_APROVADO',
    'f.titulo',
    v_titulo.id,
    jsonb_build_object(
      'status_anterior', 'PENDENTE',
      'status_novo', 'APROVADO',
      'motivo_compra_id', v_motivo.id,
      'os_id', p_os_id
    ),
    now(), v_aprovador
  );
end;
$$;


--
-- Name: cancelar_agendamento_ap(uuid, text); Type: FUNCTION; Schema: f; Owner: -
--

CREATE FUNCTION f.cancelar_agendamento_ap(p_titulo_id uuid, p_motivo text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'f', 'public', 'a', 'c'
    SET row_security TO 'off'
    AS $$
declare
  v_titulo f.titulo%rowtype;
  v_user uuid;

  v_tem_agendamento boolean;
begin
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_titulo
  from f.titulo
  where id = p_titulo_id
    and deleted_at is null;

  if not found then
    raise exception 'Titulo nao encontrado (id=%)', p_titulo_id;
  end if;

  if v_titulo.tipo <> 'AP' then
    raise exception 'Cancelamento so permite titulo AP. Tipo atual=%', v_titulo.tipo;
  end if;

  -- permissão no app
  if auth.uid() is not null then
    if not f.has_finance_access(v_titulo.tenant_id, v_titulo.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();

  -- fallback SQL Editor
  if v_user is null then
    select ut.usuario_id into v_user
    from a.usuario_tenant ut
    where ut.tenant_id = v_titulo.tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
    order by ut.created_at nulls last
    limit 1;

    if v_user is null then
      raise exception 'Nao foi possivel determinar usuario executor. Execute pelo app.';
    end if;
  end if;

  select exists(
    select 1
    from f.titulo_agendamento ta
    where ta.tenant_id = v_titulo.tenant_id
      and ta.titulo_id = v_titulo.id
      and ta.deleted_at is null
  ) into v_tem_agendamento;

  if not v_tem_agendamento then
    raise exception 'Nao existe agendamento ativo para este titulo';
  end if;

  -- soft delete do agendamento
  update f.titulo_agendamento
     set deleted_at = now(),
         updated_at = now(),
         updated_by = v_user
   where tenant_id = v_titulo.tenant_id
     and titulo_id = v_titulo.id
     and deleted_at is null;

  -- volta status: se tem saldo aberto, APROVADO; se não, PAGO
  update f.titulo
     set status = case when v_titulo.valor_aberto > 0 then 'APROVADO' else 'PAGO' end,
         updated_at = now(),
         updated_by = v_user
   where id = v_titulo.id;

  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_titulo.tenant_id, v_titulo.empresa_id,
    'PAGAMENTO_AGENDADO_CANCELADO',
    'f.titulo',
    v_titulo.id,
    jsonb_build_object(
      'motivo', p_motivo
    ),
    now(), v_user
  );
end;
$$;


--
-- Name: conciliar_pagamento_extrato(uuid, uuid, text, text, text); Type: FUNCTION; Schema: f; Owner: -
--

CREATE FUNCTION f.conciliar_pagamento_extrato(p_extrato_linha_id uuid, p_pagamento_id uuid, p_referencia text DEFAULT NULL::text, p_observacoes text DEFAULT NULL::text, p_change_reason text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'f', 'public', 'a', 'c'
    SET row_security TO 'off'
    AS $$
declare
  v_linha f.extrato_bancario_linha%rowtype;
  v_pag f.pagamento%rowtype;

  v_user uuid;
  v_conc_id uuid;

  v_valor_mov numeric(15,2);
  v_valor_pag numeric(15,2);
  v_dif numeric(15,2);
begin
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_linha
  from f.extrato_bancario_linha
  where id = p_extrato_linha_id
    and deleted_at is null;

  if not found then
    raise exception 'Extrato linha nao encontrada (id=%)', p_extrato_linha_id;
  end if;

  select * into v_pag
  from f.pagamento
  where id = p_pagamento_id
    and deleted_at is null;

  if not found then
    raise exception 'Pagamento nao encontrado/estornado (id=%)', p_pagamento_id;
  end if;

  if auth.uid() is not null then
    if not f.has_finance_access(v_pag.tenant_id, v_pag.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();

  if v_user is null then
    select ut.usuario_id into v_user
    from a.usuario_tenant ut
    where ut.tenant_id = v_pag.tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
    order by ut.created_at nulls last
    limit 1;

    if v_user is null then
      raise exception 'Nao foi possivel determinar usuario executor. Execute pelo app.';
    end if;
  end if;

  if v_linha.tenant_id <> v_pag.tenant_id then
    raise exception 'Tenant diferente entre extrato e pagamento';
  end if;

  if v_linha.conta_bancaria_id <> v_pag.conta_bancaria_id then
    raise exception 'Conta bancaria diferente entre extrato e pagamento';
  end if;

  -- MVP AP: extrato deve ser débito (negativo)
  if v_linha.valor >= 0 then
    raise exception 'Linha de extrato deve ser debito (valor negativo) para conciliar AP. Valor=%', v_linha.valor;
  end if;

  if v_linha.status <> 'PENDENTE' then
    raise exception 'Linha de extrato nao esta PENDENTE. Status atual=%', v_linha.status;
  end if;

  if v_pag.conciliado_at is not null then
    raise exception 'Pagamento ja conciliado (pagamento_id=%)', v_pag.id;
  end if;

  v_valor_mov := round(abs(v_linha.valor), 2);
  v_valor_pag := round(v_pag.valor, 2);
  v_dif := round(v_valor_mov - v_valor_pag, 2);

  insert into f.conciliacao_bancaria (
    tenant_id, empresa_id,
    conta_bancaria_id,
    extrato_linha_id,
    pagamento_id,
    referencia,
    status,
    valor_conciliado,
    diferenca,
    conciliado_em,
    conciliado_por,
    observacoes,
    change_reason,
    created_at, updated_at, created_by, updated_by
  )
  values (
    v_pag.tenant_id, v_pag.empresa_id,
    v_pag.conta_bancaria_id,
    v_linha.id,
    v_pag.id,
    p_referencia,
    'CONCILIADO',
    v_valor_pag,
    v_dif,
    now(),
    v_user,
    p_observacoes,
    p_change_reason,
    now(), now(), v_user, v_user
  )
  returning id into v_conc_id;

  update f.extrato_bancario_linha
     set status = 'CONCILIADO',
         updated_at = now(),
         updated_by = v_user
   where id = v_linha.id;

  update f.pagamento
     set conciliado_at = now(),
         conciliado_por = v_user,
         updated_at = now(),
         updated_by = v_user
   where id = v_pag.id;

  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_pag.tenant_id, v_pag.empresa_id,
    'PAGAMENTO_CONCILIADO',
    'f.conciliacao_bancaria',
    v_conc_id,
    jsonb_build_object(
      'extrato_linha_id', v_linha.id,
      'pagamento_id', v_pag.id,
      'valor_extrato', v_linha.valor,
      'valor_pagamento', v_pag.valor,
      'diferenca', v_dif,
      'referencia', p_referencia,
      'change_reason', p_change_reason
    ),
    now(), v_user
  );

  return v_conc_id;
end;
$$;


--
-- Name: conciliar_por_sugestao_ap(uuid, integer, text, text, text); Type: FUNCTION; Schema: f; Owner: -
--

CREATE FUNCTION f.conciliar_por_sugestao_ap(p_extrato_linha_id uuid, p_score_min integer DEFAULT 2, p_referencia text DEFAULT 'AUTO MATCH'::text, p_observacoes text DEFAULT 'CONCILIADO VIA SUGESTAO'::text, p_change_reason text DEFAULT 'AUTO-SUGESTAO'::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'f', 'public', 'a', 'c'
    SET row_security TO 'off'
    AS $$
declare
  v_status text;
  v_conc_id uuid;

  v_pagamento_id uuid;
  v_score integer;
begin
  -- 1) Se já está conciliado, devolve a conciliação ativa
  select el.status into v_status
  from f.extrato_bancario_linha el
  where el.id = p_extrato_linha_id
    and el.deleted_at is null;

  if v_status is null then
    raise exception 'Extrato linha nao encontrada (id=%)', p_extrato_linha_id;
  end if;

  if v_status = 'CONCILIADO' then
    select cb.id into v_conc_id
    from f.conciliacao_bancaria cb
    where cb.extrato_linha_id = p_extrato_linha_id
      and cb.deleted_at is null
    order by cb.created_at desc
    limit 1;

    if v_conc_id is null then
      raise exception 'Linha CONCILIADO mas sem conciliacao ativa (extrato_linha_id=%)', p_extrato_linha_id;
    end if;

    return v_conc_id;
  end if;

  if v_status = 'IGNORADO' then
    raise exception 'Linha do extrato esta IGNORADA. Desfaça/edite para conciliar (extrato_linha_id=%)', p_extrato_linha_id;
  end if;

  -- 2) PENDENTE: pega melhor sugestão
  select s.pagamento_id, s.score_data
    into v_pagamento_id, v_score
  from f.r_sugestoes_conciliacao_ap s
  where s.extrato_linha_id = p_extrato_linha_id
  order by s.score_data desc, s.data_pagamento desc
  limit 1;

  if v_pagamento_id is null then
    raise exception 'Nenhuma sugestao encontrada para extrato_linha_id=%', p_extrato_linha_id;
  end if;

  if v_score < coalesce(p_score_min, 0) then
    raise exception 'Melhor sugestao com score=% abaixo do minimo=%', v_score, p_score_min;
  end if;

  -- 3) Concilia de fato
  return f.conciliar_pagamento_extrato(
    p_extrato_linha_id,
    v_pagamento_id,
    p_referencia,
    p_observacoes,
    p_change_reason
  );
end;
$$;


--
-- Name: desconciliar_pagamento_extrato(uuid, text); Type: FUNCTION; Schema: f; Owner: -
--

CREATE FUNCTION f.desconciliar_pagamento_extrato(p_conciliacao_id uuid, p_motivo text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'f', 'public', 'a', 'c'
    SET row_security TO 'off'
    AS $$
declare
  v_conc f.conciliacao_bancaria%rowtype;
  v_user uuid;
begin
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_conc
  from f.conciliacao_bancaria
  where id = p_conciliacao_id
    and deleted_at is null;

  if not found then
    raise exception 'Conciliacao nao encontrada/ja desfeita (id=%)', p_conciliacao_id;
  end if;

  if auth.uid() is not null then
    if not f.has_finance_access(v_conc.tenant_id, v_conc.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();

  if v_user is null then
    select ut.usuario_id into v_user
    from a.usuario_tenant ut
    where ut.tenant_id = v_conc.tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
    order by ut.created_at nulls last
    limit 1;

    if v_user is null then
      raise exception 'Nao foi possivel determinar usuario executor. Execute pelo app.';
    end if;
  end if;

  -- desfaz conciliação (mantém histórico)
  update f.conciliacao_bancaria
     set status = 'DESCONCILIADO',
         deleted_at = now(),
         updated_at = now(),
         updated_by = v_user
   where id = v_conc.id;

  -- volta linha para pendente (se existir)
  update f.extrato_bancario_linha
     set status = 'PENDENTE',
         updated_at = now(),
         updated_by = v_user
   where id = v_conc.extrato_linha_id
     and deleted_at is null;

  -- limpa conciliação no pagamento (se existir)
  update f.pagamento
     set conciliado_at = null,
         conciliado_por = null,
         updated_at = now(),
         updated_by = v_user
   where id = v_conc.pagamento_id
     and deleted_at is null;

  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_conc.tenant_id, v_conc.empresa_id,
    'PAGAMENTO_DESCONCILIADO',
    'f.conciliacao_bancaria',
    v_conc.id,
    jsonb_build_object(
      'motivo', p_motivo,
      'extrato_linha_id', v_conc.extrato_linha_id,
      'pagamento_id', v_conc.pagamento_id
    ),
    now(), v_user
  );
end;
$$;


--
-- Name: estornar_pagamento_ap(uuid, text); Type: FUNCTION; Schema: f; Owner: -
--

CREATE FUNCTION f.estornar_pagamento_ap(p_pagamento_id uuid, p_motivo text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'f', 'public', 'a', 'c'
    SET row_security TO 'off'
    AS $$
declare
  v_pag f.pagamento%rowtype;
  v_user uuid;

  r record;

  v_titulo_id uuid;
  v_titulo f.titulo%rowtype;
  v_soma_aberto numeric(15,2);
begin
  -- auth: app ou SQL Editor (postgres/service_role)
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();

  -- carrega pagamento
  select * into v_pag
  from f.pagamento
  where id = p_pagamento_id
    and (deleted_at is null);

  if not found then
    raise exception 'Pagamento nao encontrado/ja estornado (id=%)', p_pagamento_id;
  end if;

  -- permissão no app
  if auth.uid() is not null then
    if not f.has_finance_access(v_pag.tenant_id, v_pag.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  -- fallback usuário (SQL Editor)
  if v_user is null then
    select ut.usuario_id
      into v_user
    from a.usuario_tenant ut
    where ut.tenant_id = v_pag.tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
    order by ut.created_at nulls last
    limit 1;

    if v_user is null then
      raise exception 'Nao foi possivel determinar usuario executor. Execute pelo app.';
    end if;
  end if;

  -- devolve valor para cada parcela vinculada
  for r in
    select pi.id as pagamento_item_id,
           pi.valor as valor_aplicado,
           tp.id as parcela_id,
           tp.titulo_id as titulo_id
    from f.pagamento_item pi
    join f.titulo_parcela tp on tp.id = pi.titulo_parcela_id
    where pi.pagamento_id = v_pag.id
      and pi.tenant_id = v_pag.tenant_id
      and (pi.deleted_at is null)
      and (tp.deleted_at is null)
  loop
    -- guarda um titulo_id para recalcular ao final (assumimos 1 título por pagamento, que é o padrão aqui)
    v_titulo_id := r.titulo_id;

    update f.titulo_parcela
       set valor_aberto = round(valor_aberto + r.valor_aplicado, 2),
           updated_at = now(),
           updated_by = v_user
     where id = r.parcela_id;

    -- soft delete no item
    update f.pagamento_item
       set deleted_at = now()
     where id = r.pagamento_item_id;
  end loop;

  if v_titulo_id is null then
    raise exception 'Pagamento sem itens vinculados (pagamento_id=%)', v_pag.id;
  end if;

  -- soft delete no pagamento
  update f.pagamento
     set deleted_at = now(),
         updated_at = now(),
         updated_by = v_user
   where id = v_pag.id;

  -- recalcula título
  select * into v_titulo
  from f.titulo
  where id = v_titulo_id
    and deleted_at is null;

  if not found then
    raise exception 'Titulo do pagamento nao encontrado (titulo_id=%)', v_titulo_id;
  end if;

  select coalesce(sum(valor_aberto),0)::numeric(15,2)
    into v_soma_aberto
  from f.titulo_parcela
  where tenant_id = v_titulo.tenant_id
    and titulo_id = v_titulo.id
    and deleted_at is null;

  update f.titulo
     set valor_aberto = v_soma_aberto,
         status = case
                   when v_soma_aberto = 0 then 'PAGO'
                   else 'APROVADO'
                 end,
         updated_at = now(),
         updated_by = v_user
   where id = v_titulo.id;

  -- eventos
  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_pag.tenant_id, v_pag.empresa_id,
    'PAGAMENTO_ESTORNADO',
    'f.pagamento',
    v_pag.id,
    jsonb_build_object(
      'motivo', p_motivo,
      'titulo_id', v_titulo.id,
      'saldo_titulo_pos', v_soma_aberto
    ),
    now(), v_user
  );

  insert into f.aprovacao_evento (
    tenant_id, empresa_id,
    acao, ref_table, ref_id,
    motivo, payload,
    created_at, created_by
  )
  values (
    v_pag.tenant_id, v_pag.empresa_id,
    'REPROVOU',              -- usamos esse "tipo" como evento administrativo/financeiro
    'f.pagamento',
    v_pag.id,
    'ESTORNO',
    jsonb_build_object(
      'motivo', p_motivo,
      'titulo_id', v_titulo.id,
      'pagamento_id', v_pag.id
    ),
    now(), v_user
  );

end;
$$;


--
-- Name: fn_pagamentos_aplicados(); Type: FUNCTION; Schema: f; Owner: -
--

CREATE FUNCTION f.fn_pagamentos_aplicados() RETURNS TABLE(tenant_id uuid, empresa_id uuid, conta_bancaria_id uuid, pagamento_id uuid, data_pagamento date, forma_pagamento text, valor_pagamento numeric, titulo_id uuid, titulo_parcela_id uuid, valor_aplicado numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'f', 'public'
    AS $_$
declare
  v_tbl text;
  v_col_parcela text;
  v_col_valor text;
  v_has_deleted_at boolean;
  v_sql text;
begin
  /*
    Detecta automaticamente a tabela de aplicação:
    - deve ter pagamento_id
    - deve ter (titulo_parcela_id OU parcela_id)
    - deve ter (valor_aplicado OU valor)
  */
  select x.table_name
    into v_tbl
  from (
    select t.table_name
    from information_schema.tables t
    where t.table_schema = 'f'
      and t.table_type = 'BASE TABLE'
      and exists (
        select 1 from information_schema.columns c
        where c.table_schema='f' and c.table_name=t.table_name and c.column_name='pagamento_id'
      )
      and exists (
        select 1 from information_schema.columns c
        where c.table_schema='f' and c.table_name=t.table_name and c.column_name in ('titulo_parcela_id','parcela_id')
      )
      and exists (
        select 1 from information_schema.columns c
        where c.table_schema='f' and c.table_name=t.table_name and c.column_name in ('valor_aplicado','valor')
      )
    order by
      case when t.table_name = 'pagamento_aplicacao' then 0 else 1 end,
      t.table_name
    limit 1
  ) x;

  if v_tbl is null then
    raise exception
      'Nao encontrei tabela de aplicacao pagamento->parcela no schema f. Preciso de uma tabela com: pagamento_id + (titulo_parcela_id/parcela_id) + (valor_aplicado/valor).';
  end if;

  -- qual coluna é a parcela?
  if exists (
    select 1 from information_schema.columns
    where table_schema='f' and table_name=v_tbl and column_name='titulo_parcela_id'
  ) then
    v_col_parcela := 'titulo_parcela_id';
  else
    v_col_parcela := 'parcela_id';
  end if;

  -- qual coluna é o valor aplicado?
  if exists (
    select 1 from information_schema.columns
    where table_schema='f' and table_name=v_tbl and column_name='valor_aplicado'
  ) then
    v_col_valor := 'valor_aplicado';
  else
    v_col_valor := 'valor';
  end if;

  -- tem deleted_at na tabela de aplicação?
  select exists(
    select 1 from information_schema.columns
    where table_schema='f' and table_name=v_tbl and column_name='deleted_at'
  ) into v_has_deleted_at;

  v_sql := format($fmt$
    select
      p.tenant_id,
      p.empresa_id,
      p.conta_bancaria_id,
      p.id as pagamento_id,
      p.data_pagamento,
      p.forma_pagamento::text as forma_pagamento,
      p.valor::numeric(15,2) as valor_pagamento,
      tp.titulo_id,
      pa.%1$I as titulo_parcela_id,
      pa.%2$I::numeric(15,2) as valor_aplicado
    from f.%3$I pa
    join f.pagamento p on p.id = pa.pagamento_id
    join f.titulo_parcela tp on tp.id = pa.%1$I
    where %4$s
      and p.deleted_at is null
      and tp.deleted_at is null
  $fmt$,
    v_col_parcela,
    v_col_valor,
    v_tbl,
    case when v_has_deleted_at then 'pa.deleted_at is null' else 'true' end
  );

  return query execute v_sql;
end;
$_$;


--
-- Name: fn_set_updated_by(); Type: FUNCTION; Schema: f; Owner: -
--

CREATE FUNCTION f.fn_set_updated_by() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_by := a.fn_current_usuario_id();
  return new;
end;
$$;


--
-- Name: gerar_ap_pendente_por_nf_entrada(bigint, boolean); Type: FUNCTION; Schema: f; Owner: -
--

CREATE FUNCTION f.gerar_ap_pendente_por_nf_entrada(p_nf_entrada_id bigint, p_force boolean DEFAULT false) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'f', 'public', 'a', 'c', 'extensions'
    SET row_security TO 'off'
    AS $$
declare
  v_nf public.nf_entrada%rowtype;
  v_doc_id uuid;
  v_titulo_id uuid;
  v_competencia date;
  v_xml_hash text;
begin
  -- ✅ permite SQL Editor (postgres/service_role), mas mantém segurança no app
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_nf
  from public.nf_entrada
  where id = p_nf_entrada_id;

  if not found then
    raise exception 'NF entrada nao encontrada (id=%)', p_nf_entrada_id;
  end if;

  -- permissão: no app continua exigindo ADMIN/FINANCEIRO
  if auth.uid() is not null then
    if not f.has_finance_access(v_nf.tenant_id, v_nf.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  v_competencia := date_trunc(
    'month',
    coalesce((v_nf.data_emissao at time zone 'America/Sao_Paulo')::date, current_date)
  )::date;

  select df.id into v_doc_id
  from f.documento_fiscal df
  where df.tenant_id = v_nf.tenant_id
    and df.source_nf_entrada_id = v_nf.id
    and df.deleted_at is null
  limit 1;

  if v_doc_id is not null and not p_force then
    return v_doc_id;
  end if;

  insert into f.documento_fiscal (
    tenant_id, empresa_id, source_nf_entrada_id,
    fornecedor_id, chave_acesso,
    modelo, serie, numero,
    emissao_date, competencia_date,
    valor_total, valor_produtos, valor_frete, valor_seguro, valor_desconto, valor_outros,
    finalidade_import, os_id_import,
    pagamento_import_json
  )
  values (
    v_nf.tenant_id, v_nf.empresa_id, v_nf.id,
    v_nf.fornecedor_id::int, v_nf.chave,
    null, v_nf.serie, v_nf.numero,
    (v_nf.data_emissao at time zone 'America/Sao_Paulo')::date,
    v_competencia,
    coalesce(v_nf.valor_total, 0),
    coalesce(v_nf.valor_produtos, 0),
    coalesce(v_nf.valor_frete, 0),
    coalesce(v_nf.valor_seguro, 0),
    coalesce(v_nf.valor_desconto, 0),
    coalesce(v_nf.valor_outros, 0),
    v_nf.finalidade_contexto,
    v_nf.os_id,
    null
  )
  on conflict (tenant_id, source_nf_entrada_id)
  do update set
    empresa_id = excluded.empresa_id,
    fornecedor_id = excluded.fornecedor_id,
    chave_acesso = excluded.chave_acesso,
    serie = excluded.serie,
    numero = excluded.numero,
    emissao_date = excluded.emissao_date,
    competencia_date = excluded.competencia_date,
    valor_total = excluded.valor_total,
    valor_produtos = excluded.valor_produtos,
    valor_frete = excluded.valor_frete,
    valor_seguro = excluded.valor_seguro,
    valor_desconto = excluded.valor_desconto,
    valor_outros = excluded.valor_outros,
    finalidade_import = excluded.finalidade_import,
    os_id_import = excluded.os_id_import,
    updated_at = now(),
    updated_by = a.fn_current_usuario_id()
  returning id into v_doc_id;

  if v_nf.xml_raw is not null and length(v_nf.xml_raw) > 0 then
    v_xml_hash := encode(extensions.digest(convert_to(v_nf.xml_raw, 'utf8'), 'sha256'), 'hex');

    insert into f.documento_fiscal_xml (tenant_id, documento_fiscal_id, chave_acesso, xml_raw, xml_hash)
    values (v_nf.tenant_id, v_doc_id, v_nf.chave, v_nf.xml_raw, v_xml_hash)
    on conflict (tenant_id, documento_fiscal_id) do update set
      xml_raw = excluded.xml_raw,
      xml_hash = excluded.xml_hash;
  end if;

  select t.id into v_titulo_id
  from f.titulo t
  where t.tenant_id = v_nf.tenant_id
    and t.empresa_id = v_nf.empresa_id
    and t.documento_fiscal_id = v_doc_id
    and t.deleted_at is null
  limit 1;

  if v_titulo_id is null then
    insert into f.titulo (
      tenant_id, empresa_id,
      tipo, status, origem,
      fornecedor_id, documento_fiscal_id,
      descricao,
      emissao_date, competencia_date,
      valor_total, valor_aberto
    )
    values (
      v_nf.tenant_id, v_nf.empresa_id,
      'AP', 'PENDENTE', 'XML',
      v_nf.fornecedor_id::int, v_doc_id,
      ('NF-e ' || coalesce(v_nf.numero,'') || '/' || coalesce(v_nf.serie,'') || ' - ' || coalesce(v_nf.emitente_nome,'EMITENTE')),
      (v_nf.data_emissao at time zone 'America/Sao_Paulo')::date,
      v_competencia,
      coalesce(v_nf.valor_total, 0),
      coalesce(v_nf.valor_total, 0)
    )
    returning id into v_titulo_id;

    insert into f.titulo_parcela (
      tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto
    )
    values (
      v_nf.tenant_id,
      v_titulo_id,
      '001',
      (v_nf.data_emissao at time zone 'America/Sao_Paulo')::date,
      coalesce(v_nf.valor_total, 0),
      coalesce(v_nf.valor_total, 0)
    );
  end if;

  return v_doc_id;
end;
$$;


--
-- Name: has_finance_access(uuid, uuid); Type: FUNCTION; Schema: f; Owner: -
--

CREATE FUNCTION f.has_finance_access(p_tenant uuid DEFAULT public.current_tenant_id(), p_empresa uuid DEFAULT public.current_empresa_id()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'f', 'public', 'a', 'c'
    SET row_security TO 'off'
    AS $$
  select
    -- ADMIN no TENANT (OWNER/ADMIN)
    exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut on ut.usuario_id = u.id
      where u.auth_user_id = auth.uid()
        and ut.tenant_id = p_tenant
        and ut.ativo = true
        and ut.deleted_at is null
        and ut.papel in ('OWNER','ADMIN')
    )
    or
    -- ADMIN/FINANCEIRO na EMPRESA
    exists (
      select 1
      from a.usuario u
      join a.usuario_empresa ue on ue.usuario_id = u.id
      join c.empresa e on e.id = ue.empresa_id
      where u.auth_user_id = auth.uid()
        and ue.empresa_id = p_empresa
        and ue.ativo = true
        and ue.deleted_at is null
        and ue.papel in ('ADMIN','FINANCEIRO')
        and e.deleted_at is null
        and e.tenant_id = p_tenant
    );
$$;


--
-- Name: has_motivo_compra_access(uuid); Type: FUNCTION; Schema: f; Owner: -
--

CREATE FUNCTION f.has_motivo_compra_access(p_tenant_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'a', 'c', 'f'
    SET row_security TO 'off'
    AS $$
  select exists (
    select 1
    from a.usuario u
    join a.usuario_empresa ue on ue.usuario_id = u.id
    join c.empresa e on e.id = ue.empresa_id
    where u.auth_user_id = auth.uid()
      and u.deleted_at is null
      and ue.ativo is true
      and ue.deleted_at is null
      and e.deleted_at is null
      and e.tenant_id = p_tenant_id
      and upper(trim(coalesce(ue.papel, ''))) in (
        'ADMIN',
        'FINANCEIRO',
        'COORDENACAO',
        'COMPRAS',
        'ALMOXARIFADO',
        'APONTAMENTO_RH'
      )
  );
$$;


--
-- Name: ignorar_extrato_linha(uuid, text); Type: FUNCTION; Schema: f; Owner: -
--

CREATE FUNCTION f.ignorar_extrato_linha(p_extrato_linha_id uuid, p_motivo text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'f', 'public', 'a', 'c'
    SET row_security TO 'off'
    AS $$
declare
  v_linha f.extrato_bancario_linha%rowtype;
  v_user uuid;
begin
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_linha
  from f.extrato_bancario_linha
  where id = p_extrato_linha_id
    and deleted_at is null;

  if not found then
    raise exception 'Extrato linha nao encontrada (id=%)', p_extrato_linha_id;
  end if;

  -- permissão
  if auth.uid() is not null then
    if not f.has_finance_access() then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();

  if v_user is null then
    select ut.usuario_id into v_user
    from a.usuario_tenant ut
    where ut.tenant_id = v_linha.tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
    order by ut.created_at nulls last
    limit 1;

    if v_user is null then
      raise exception 'Nao foi possivel determinar usuario executor. Execute pelo app.';
    end if;
  end if;

  if v_linha.status <> 'PENDENTE' then
    raise exception 'Somente linha PENDENTE pode ser ignorada. Status atual=%', v_linha.status;
  end if;

  update f.extrato_bancario_linha
     set status = 'IGNORADO',
         observacoes = coalesce(observacoes,'') ||
           case when p_motivo is null or length(trim(p_motivo))=0 then '' else (' | IGNORADO: ' || p_motivo) end,
         updated_at = now(),
         updated_by = v_user
   where id = v_linha.id;

  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_linha.tenant_id,
    (select eb.empresa_id from f.extrato_bancario eb where eb.id = v_linha.extrato_bancario_id),
    'EXTRATO_LINHA_IGNORADA',
    'f.extrato_bancario_linha',
    v_linha.id,
    jsonb_build_object(
      'motivo', p_motivo,
      'valor', v_linha.valor,
      'data_movimento', v_linha.data_movimento
    ),
    now(), v_user
  );
end;
$$;


--
-- Name: registrar_pagamento_ap(uuid, uuid, date, text, numeric, text, text); Type: FUNCTION; Schema: f; Owner: -
--

CREATE FUNCTION f.registrar_pagamento_ap(p_titulo_id uuid, p_conta_bancaria_id uuid, p_data_pagamento date, p_forma_pagamento text, p_valor numeric, p_observacoes text DEFAULT NULL::text, p_change_reason text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'f', 'public', 'a', 'c'
    SET row_security TO 'off'
    AS $$
declare
  v_titulo f.titulo%rowtype;
  v_cb f.conta_bancaria%rowtype;

  v_user uuid;
  v_pagamento_id uuid;

  v_restante numeric(15,2);
  v_alocar numeric(15,2);
  v_soma_aberto numeric(15,2);

  r record;
begin
  if p_valor is null or p_valor <= 0 then
    raise exception 'Valor de pagamento deve ser > 0';
  end if;

  if p_data_pagamento is null then
    raise exception 'Data de pagamento obrigatoria';
  end if;

  if p_forma_pagamento is null or length(trim(p_forma_pagamento)) = 0 then
    raise exception 'Forma de pagamento obrigatoria';
  end if;

  if p_forma_pagamento not in ('PIX','BOLETO','TRANSFERENCIA','DINHEIRO','CARTAO','OUTROS') then
    raise exception 'Forma de pagamento invalida: %', p_forma_pagamento;
  end if;

  -- auth: app ou SQL Editor (postgres/service_role)
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();

  -- fallback SQL Editor: pega um OWNER/ADMIN do tenant do título (depois que carregar título)
  -- (vamos carregar título antes de usar fallback)

  -- título
  select * into v_titulo
  from f.titulo
  where id = p_titulo_id
    and deleted_at is null;

  if not found then
    raise exception 'Titulo nao encontrado (id=%)', p_titulo_id;
  end if;

  if v_titulo.tipo <> 'AP' then
    raise exception 'Pagamento so permite titulo AP. Tipo atual=%', v_titulo.tipo;
  end if;

  if v_titulo.status not in ('APROVADO','AGENDADO','PAGO') then
    raise exception 'Titulo precisa estar APROVADO/AGENDADO/PAGO para pagar. Status atual=%', v_titulo.status;
  end if;

  if v_titulo.valor_aberto <= 0 then
    raise exception 'Titulo sem saldo em aberto';
  end if;

  -- permissão no app
  if auth.uid() is not null then
    if not f.has_finance_access(v_titulo.tenant_id, v_titulo.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  -- fallback para SQL Editor caso fn_current_usuario_id() retorne null
  if v_user is null then
    select ut.usuario_id
      into v_user
    from a.usuario_tenant ut
    where ut.tenant_id = v_titulo.tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
    order by ut.created_at nulls last
    limit 1;

    if v_user is null then
      raise exception 'Nao foi possivel determinar usuario executor. Execute pelo app.';
    end if;
  end if;

  -- conta bancária
  select * into v_cb
  from f.conta_bancaria
  where id = p_conta_bancaria_id
    and deleted_at is null;

  if not found then
    raise exception 'Conta bancaria nao encontrada (id=%)', p_conta_bancaria_id;
  end if;

  if v_cb.tenant_id <> v_titulo.tenant_id or v_cb.empresa_id <> v_titulo.empresa_id then
    raise exception 'Conta bancaria nao pertence ao mesmo tenant/empresa do titulo';
  end if;

  -- limita pagamento ao saldo aberto (proteção extra)
  if round(p_valor,2) > round(v_titulo.valor_aberto,2) then
    raise exception 'Pagamento (% ) maior que saldo em aberto do titulo (%)', round(p_valor,2), round(v_titulo.valor_aberto,2);
  end if;

  -- cria pagamento (cabeçalho)
  insert into f.pagamento (
    tenant_id, empresa_id,
    conta_bancaria_id,
    data_pagamento,
    forma_pagamento,
    valor,
    observacoes,
    pago_por,
    created_at, updated_at, created_by, updated_by
  )
  values (
    v_titulo.tenant_id, v_titulo.empresa_id,
    v_cb.id,
    p_data_pagamento,
    p_forma_pagamento,
    round(p_valor, 2),
    p_observacoes,
    v_user,
    now(), now(), v_user, v_user
  )
  returning id into v_pagamento_id;

  -- alocação: paga parcelas em aberto (ordem por vencimento)
  v_restante := round(p_valor, 2);

  for r in
    select id, valor_aberto
    from f.titulo_parcela
    where tenant_id = v_titulo.tenant_id
      and titulo_id = v_titulo.id
      and deleted_at is null
      and valor_aberto > 0
    order by vencimento_date asc, created_at asc
  loop
    exit when v_restante <= 0;

    v_alocar := least(r.valor_aberto, v_restante);

    insert into f.pagamento_item (
      tenant_id, pagamento_id, titulo_parcela_id, valor,
      created_at, created_by
    )
    values (
      v_titulo.tenant_id, v_pagamento_id, r.id, v_alocar,
      now(), v_user
    );

    update f.titulo_parcela
       set valor_aberto = round(valor_aberto - v_alocar, 2),
           updated_at = now(),
           updated_by = v_user
     where id = r.id;

    v_restante := round(v_restante - v_alocar, 2);
  end loop;

  if v_restante <> 0 then
    -- não deveria acontecer por causa do check contra saldo do título,
    -- mas mantém consistência
    raise exception 'Inconsistencia: restante=%', v_restante;
  end if;

  -- recalcula saldo do título
  select coalesce(sum(valor_aberto),0)::numeric(15,2)
    into v_soma_aberto
  from f.titulo_parcela
  where tenant_id = v_titulo.tenant_id
    and titulo_id = v_titulo.id
    and deleted_at is null;

  update f.titulo
     set valor_aberto = v_soma_aberto,
         status = case when v_soma_aberto = 0 then 'PAGO' else v_titulo.status end,
         updated_at = now(),
         updated_by = v_user
   where id = v_titulo.id;

  -- evento financeiro
  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_titulo.tenant_id, v_titulo.empresa_id,
    'PAGAMENTO_REGISTRADO',
    'f.pagamento',
    v_pagamento_id,
    jsonb_build_object(
      'titulo_id', v_titulo.id,
      'conta_bancaria_id', v_cb.id,
      'data_pagamento', p_data_pagamento,
      'forma_pagamento', p_forma_pagamento,
      'valor', round(p_valor,2),
      'saldo_titulo_pos', v_soma_aberto,
      'change_reason', p_change_reason
    ),
    now(), v_user
  );

  return v_pagamento_id;
end;
$$;


--
-- Name: seed_financeiro_defaults(uuid, uuid); Type: FUNCTION; Schema: f; Owner: -
--

CREATE FUNCTION f.seed_financeiro_defaults(p_tenant uuid, p_empresa uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'f', 'public', 'a', 'c'
    SET row_security TO 'off'
    AS $$
begin
  -- motivos padrão
  insert into f.motivo_compra (tenant_id, codigo, nome, requires_text, requires_os, ativo)
  values
    (p_tenant, 'OS', 'ORDEM DE SERVICO', false, true, true),
    (p_tenant, 'ESTOQUE', 'ESTOQUE', false, false, true),
    (p_tenant, 'INVESTIMENTO', 'INVESTIMENTO', false, false, true),
    (p_tenant, 'MANUTENCAO', 'MANUTENCAO', false, false, true),
    (p_tenant, 'EPI', 'EPI', false, false, true),
    (p_tenant, 'OUTROS', 'OUTROS', true, false, true)
  on conflict (tenant_id, codigo) do nothing;

  -- (opcional) garantir um fin_config por empresa
  insert into f.fin_config (tenant_id, empresa_id)
  values (p_tenant, p_empresa)
  on conflict (tenant_id, empresa_id) do nothing;
end;
$$;


--
-- Name: trg_titulo_require_motivo_compra(); Type: FUNCTION; Schema: f; Owner: -
--

CREATE FUNCTION f.trg_titulo_require_motivo_compra() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if new.tipo = 'AP' and coalesce(new.origem,'') = 'XML' then
    if new.motivo_compra_id is null then
      raise exception 'Classificação (motivo_compra_id) é obrigatória para título AP importado do XML.';
    end if;
  end if;
  return new;
end;
$$;


--
-- Name: get_auth(text); Type: FUNCTION; Schema: pgbouncer; Owner: -
--

CREATE FUNCTION pgbouncer.get_auth(p_usename text) RETURNS TABLE(username text, password text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
  BEGIN
      RAISE DEBUG 'PgBouncer auth request: %', p_usename;

      RETURN QUERY
      SELECT
          rolname::text,
          CASE WHEN rolvaliduntil < now()
              THEN null
              ELSE rolpassword::text
          END
      FROM pg_authid
      WHERE rolname=$1 and rolcanlogin;
  END;
  $_$;


--
-- Name: a_is_empresa_member(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.a_is_empresa_member(p_empresa_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'a'
    AS $$
  select exists (
    select 1
    from a.usuario_empresa ue
    join a.usuario u on u.id = ue.usuario_id
    where u.auth_user_id = auth.uid()
      and ue.empresa_id = p_empresa_id
      and ue.deleted_at is null
      and ue.ativo = true
  );
$$;


--
-- Name: a_is_tenant_admin(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.a_is_tenant_admin(p_tenant_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'a'
    AS $$
  select public.a_is_tenant_role(p_tenant_id, array['admin']);
$$;


--
-- Name: a_is_tenant_role(uuid, text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.a_is_tenant_role(p_tenant_id uuid, p_roles text[]) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'a'
    AS $$
  select exists (
    select 1
    from a.usuario_tenant ut
    join a.usuario u on u.id = ut.usuario_id
    where u.auth_user_id = auth.uid()
      and ut.tenant_id = p_tenant_id
      and ut.deleted_at is null
      and ut.ativo = true
      and a.fn_map_papel_tenant_to_role(ut.papel) = any (p_roles)
  );
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: os_itens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_itens (
    id integer NOT NULL,
    os_id integer NOT NULL,
    item_id integer NOT NULL,
    quantidade numeric(14,3) DEFAULT 0 NOT NULL,
    valor_unitario numeric(10,2) NOT NULL,
    valor_total numeric(12,2) NOT NULL,
    desconto_percentual numeric(5,2) DEFAULT 0,
    desconto_valor numeric(10,2) DEFAULT 0,
    baixa_estoque boolean DEFAULT false,
    observacoes text,
    criado_em timestamp without time zone DEFAULT now(),
    tenant_id uuid NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    CONSTRAINT chk_os_itens_quantidade_pos CHECK ((quantidade > (0)::numeric))
);


--
-- Name: add_os_item_baixa_imediata(integer, integer, numeric, numeric, numeric, numeric, boolean, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_os_item_baixa_imediata(p_os_id integer, p_item_id integer, p_quantidade numeric, p_valor_unitario numeric, p_desconto_percentual numeric DEFAULT 0, p_desconto_valor numeric DEFAULT 0, p_baixa_estoque boolean DEFAULT true, p_realizado_por text DEFAULT NULL::text, p_motivo text DEFAULT NULL::text) RETURNS public.os_itens
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select public.add_os_item_baixa_imediata(
    p_os_id,
    p_item_id,
    p_quantidade,
    p_valor_unitario,
    p_desconto_percentual,
    p_desconto_valor,
    p_baixa_estoque,
    p_realizado_por,
    p_motivo,
    null::uuid
  );
$$;


--
-- Name: add_os_item_baixa_imediata(integer, integer, numeric, numeric, numeric, numeric, boolean, text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_os_item_baixa_imediata(p_os_id integer, p_item_id integer, p_quantidade numeric, p_valor_unitario numeric, p_desconto_percentual numeric DEFAULT 0, p_desconto_valor numeric DEFAULT 0, p_baixa_estoque boolean DEFAULT true, p_realizado_por text DEFAULT NULL::text, p_motivo text DEFAULT NULL::text, p_empresa_id uuid DEFAULT NULL::uuid) RETURNS public.os_itens
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_item public.itens;
  v_total numeric;
  v_row public.os_itens;
  v_tenant uuid;
  v_realizado_por text;
  v_empresa uuid;
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Tenant atual nao definido';
  end if;

  if not public.can('os_rpcs','execute') then
    raise exception 'Sem permissao para executar operacao de OS';
  end if;

  v_empresa := coalesce(p_empresa_id, public.current_empresa_id());
  if v_empresa is null then
    raise exception 'Empresa atual nao definida. Informe p_empresa_id na chamada da RPC.';
  end if;

  perform public.set_current_empresa(v_empresa);

  v_realizado_por := coalesce(p_realizado_por, auth.uid()::text);

  if not exists (
    select 1
    from public.ordens_servico os
    where os.id = p_os_id
      and os.tenant_id = v_tenant
  ) then
    raise exception 'OS invalida ou fora do tenant atual';
  end if;

  select *
    into v_item
  from public.itens
  where id = p_item_id
    and tenant_id = v_tenant
    and ativo = true;

  if not found then
    raise exception 'Item invalido/inativo ou fora do tenant atual';
  end if;

  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'Quantidade invalida';
  end if;

  v_total := (p_quantidade * p_valor_unitario) - coalesce(p_desconto_valor, 0);

  insert into public.os_itens (
    tenant_id,
    os_id,
    item_id,
    quantidade,
    valor_unitario,
    valor_total,
    desconto_percentual,
    desconto_valor,
    baixa_estoque,
    criado_em
  )
  values (
    v_tenant,
    p_os_id,
    p_item_id,
    p_quantidade,
    p_valor_unitario,
    v_total,
    coalesce(p_desconto_percentual, 0),
    coalesce(p_desconto_valor, 0),
    coalesce(p_baixa_estoque, true),
    now()
  )
  returning * into v_row;

  if coalesce(p_baixa_estoque, true)
     and v_item.tipo = 'produto'
     and coalesce(v_item.controla_estoque, false) = true
  then
    if not (public.can('estoque','write') or public.can('os_rpcs','execute')) then
      raise exception 'Sem permissao para movimentar estoque';
    end if;

    insert into public.movimentacoes (
      tenant_id,
      empresa_id,
      item_id,
      tipo,
      quantidade,
      motivo,
      realizado_por,
      data_movimentacao,
      created_at
    )
    values (
      v_tenant,
      v_empresa,
      p_item_id,
      'saida',
      p_quantidade,
      coalesce(p_motivo, 'Baixa imediata via OS ' || p_os_id),
      v_realizado_por,
      now(),
      now()
    );
  end if;

  update public.ordens_servico os
  set valor_total = coalesce((
        select sum(oi.valor_total)
        from public.os_itens oi
        where oi.os_id = p_os_id
          and oi.tenant_id = v_tenant
      ), 0),
      atualizado_em = now()
  where os.id = p_os_id
    and os.tenant_id = v_tenant;

  return v_row;
end;
$$;


--
-- Name: admin_can_manage_users(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_can_manage_users(p_tenant_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'a'
    AS $$
  select exists (
    select 1
    from a.usuario u
    join a.usuario_tenant ut
      on ut.usuario_id = u.id
    where u.auth_user_id = auth.uid()
      and ut.tenant_id = p_tenant_id
      and ut.deleted_at is null
      and ut.ativo = true
      and (
        ut.papel = 'OWNER'
        or exists (
          select 1
          from public.role_permissions rp
          where rp.role = a.fn_map_papel_tenant_to_role(ut.papel)
            and rp.permission in ('admin.users.manage', 'admin.manage_users')
        )
      )
  );
$$;


--
-- Name: admin_finalize_invited_user(uuid, uuid, text, text, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_finalize_invited_user(p_tenant_id uuid, p_auth_user_id uuid, p_email text, p_nome text, p_telefone text, p_tenant_papel text, p_empresa_vinculos jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'a'
    AS $$
declare
  v_usuario_id uuid;
  v_tenant_papel text;
  v_item jsonb;
  v_empresa_id uuid;
  v_empresa_papel text;
  v_empresa_ativo boolean;
begin
  if not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;

  -- valida papel do tenant
  v_tenant_papel := upper(trim(coalesce(p_tenant_papel,'GESTOR')));
  if v_tenant_papel not in ('OWNER','ADMIN','CONTADOR','GESTOR') then
    raise exception 'invalid_tenant_role: %', v_tenant_papel;
  end if;

  -- upsert usuario (por auth_user_id)
  insert into a.usuario (
    id, auth_user_id, nome, email, telefone, ativo,
    created_at, updated_at, created_by, updated_by, deleted_at
  )
  values (
    gen_random_uuid(),
    p_auth_user_id,
    nullif(trim(coalesce(p_nome,'')), ''),
    lower(trim(coalesce(p_email,''))),
    nullif(regexp_replace(coalesce(p_telefone,''), '\D', '', 'g'), ''),
    true,
    now(), now(), auth.uid(), auth.uid(), null
  )
  on conflict (auth_user_id)
  do update set
    nome = excluded.nome,
    email = excluded.email,
    telefone = excluded.telefone,
    ativo = true,
    updated_at = now(),
    updated_by = auth.uid(),
    deleted_at = null
  returning id into v_usuario_id;

  -- tenant role
  insert into a.usuario_tenant (
    id, usuario_id, tenant_id, papel, ativo,
    created_at, updated_at, created_by, updated_by, deleted_at
  )
  values (
    gen_random_uuid(), v_usuario_id, p_tenant_id, v_tenant_papel, true,
    now(), now(), auth.uid(), auth.uid(), null
  )
  on conflict (usuario_id, tenant_id) where deleted_at is null
  do update set
    papel = excluded.papel,
    ativo = true,
    updated_at = now(),
    updated_by = auth.uid(),
    deleted_at = null;

  -- empresa vínculos (opcional)
  if p_empresa_vinculos is not null and jsonb_typeof(p_empresa_vinculos) = 'array' then
    for v_item in select * from jsonb_array_elements(p_empresa_vinculos)
    loop
      v_empresa_id := (v_item->>'empresa_id')::uuid;
      v_empresa_papel := upper(trim(coalesce(v_item->>'papel','TECNICO')));
      v_empresa_ativo := coalesce((v_item->>'ativo')::boolean, true);

      if v_empresa_papel not in (
        'ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','TECNICO','APONTAMENTO_RH','PAINEL_TV'
      ) then
        raise exception 'invalid_empresa_role: %', v_empresa_papel;
      end if;

      perform 1 from public.empresas e where e.id = v_empresa_id and e.tenant_id = p_tenant_id;
      if not found then
        raise exception 'empresa_not_in_tenant';
      end if;

      insert into a.usuario_empresa (
        id, usuario_id, empresa_id, papel, ativo,
        permissoes_extra, permissoes_negadas,
        created_at, updated_at, created_by, updated_by, deleted_at
      )
      values (
        gen_random_uuid(), v_usuario_id, v_empresa_id, v_empresa_papel, v_empresa_ativo,
        null, null,
        now(), now(), auth.uid(), auth.uid(), null
      )
      on conflict (usuario_id, empresa_id) where deleted_at is null
      do update set
        papel = excluded.papel,
        ativo = excluded.ativo,
        updated_at = now(),
        updated_by = auth.uid(),
        deleted_at = null;
    end loop;
  end if;

  return v_usuario_id;
end;
$$;


--
-- Name: admin_list_users(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_list_users(p_tenant_id uuid) RETURNS TABLE(usuario_id uuid, auth_user_id uuid, nome text, email text, telefone text, usuario_ativo boolean, tenant_papel text, tenant_ativo boolean, tenant_deleted_at timestamp with time zone, empresas jsonb, usuario_created_at timestamp with time zone, usuario_updated_at timestamp with time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'a'
    AS $$
  -- autorização
  select
    u.id as usuario_id,
    u.auth_user_id,
    u.nome,
    u.email,
    u.telefone,
    u.ativo as usuario_ativo,
    ut.papel as tenant_papel,
    ut.ativo as tenant_ativo,
    ut.deleted_at as tenant_deleted_at,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', ue.id,
            'empresa_id', ue.empresa_id,
            'empresa_nome', coalesce(e.nome_fantasia, e.razao_social, 'Empresa'),
            'papel', ue.papel,
            'ativo', ue.ativo,
            'deleted_at', ue.deleted_at
          )
          order by coalesce(e.nome_fantasia, e.razao_social, 'Empresa')
        )
        from a.usuario_empresa ue
        join public.empresas e on e.id = ue.empresa_id
        where ue.usuario_id = u.id
          and ue.deleted_at is null
          and e.tenant_id = p_tenant_id
      ),
      '[]'::jsonb
    ) as empresas,
    u.created_at as usuario_created_at,
    u.updated_at as usuario_updated_at
  from a.usuario u
  join a.usuario_tenant ut on ut.usuario_id = u.id
  where ut.tenant_id = p_tenant_id
    and ut.deleted_at is null
    and public.admin_can_manage_users(p_tenant_id) = true
  order by coalesce(u.nome, u.email), u.created_at desc;
$$;


--
-- Name: admin_merge_fornecedores(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_merge_fornecedores(p_tenant_id uuid, p_keep_fornecedor_id bigint, p_merge_fornecedor_id bigint, p_soft_delete boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
declare
  r record;
  v_sql text;
begin
  if p_keep_fornecedor_id = p_merge_fornecedor_id then
    raise exception 'keep e merge não podem ser iguais';
  end if;

  -- garante que ambos são do mesmo tenant
  if not exists (
    select 1 from public.fornecedores
    where id = p_keep_fornecedor_id and tenant_id = p_tenant_id and deleted_at is null
  ) then
    raise exception 'Fornecedor KEEP não encontrado para este tenant';
  end if;

  if not exists (
    select 1 from public.fornecedores
    where id = p_merge_fornecedor_id and tenant_id = p_tenant_id and deleted_at is null
  ) then
    raise exception 'Fornecedor MERGE não encontrado para este tenant';
  end if;

  -- atualiza todas as tabelas que têm FK -> public.fornecedores(id)
  for r in
    select
      n.nspname as schema_name,
      c.relname as table_name,
      a.attname as column_name
    from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_class cref on cref.oid = con.confrelid
    join pg_namespace nref on nref.oid = cref.relnamespace
    join unnest(con.conkey) with ordinality as ck(attnum, ord) on true
    join pg_attribute a on a.attrelid = c.oid and a.attnum = ck.attnum
    where con.contype = 'f'
      and nref.nspname = 'public'
      and cref.relname = 'fornecedores'
      and a.attname in ('fornecedor_id') -- padrão do teu modelo
  loop
    v_sql := format(
      'update %I.%I set %I = $1 where %I = $2',
      r.schema_name, r.table_name, r.column_name, r.column_name
    );
    execute v_sql using p_keep_fornecedor_id, p_merge_fornecedor_id;
  end loop;

  -- por fim, inativa o duplicado
  if p_soft_delete then
    update public.fornecedores
      set deleted_at = now(),
          updated_at = now()
    where id = p_merge_fornecedor_id;
  else
    delete from public.fornecedores
    where id = p_merge_fornecedor_id;
  end if;
end;
$_$;


--
-- Name: admin_set_user_empresa(uuid, uuid, uuid, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_set_user_empresa(p_tenant_id uuid, p_empresa_id uuid, p_usuario_id uuid, p_papel text, p_ativo boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'a'
    AS $$
declare
  v_empresa_tenant uuid;
  v_papel text;
begin
  if not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;

  select e.tenant_id into v_empresa_tenant
  from public.empresas e
  where e.id = p_empresa_id;

  if v_empresa_tenant is null then
    raise exception 'empresa_not_found';
  end if;

  if v_empresa_tenant <> p_tenant_id then
    raise exception 'empresa_not_in_tenant';
  end if;

  v_papel := upper(trim(coalesce(p_papel, 'TECNICO')));

  -- valida domínio da empresa
  if v_papel not in (
    'ADMIN',
    'FINANCEIRO',
    'COORDENACAO',
    'COMPRAS',
    'ALMOXARIFADO',
    'TECNICO',
    'APONTAMENTO_RH',
    'PAINEL_TV'
  ) then
    raise exception 'invalid_empresa_role: %', v_papel;
  end if;

  insert into a.usuario_empresa (
    id, usuario_id, empresa_id, papel, ativo,
    permissoes_extra, permissoes_negadas,
    created_at, updated_at, created_by, updated_by, deleted_at
  )
  values (
    gen_random_uuid(), p_usuario_id, p_empresa_id, v_papel, coalesce(p_ativo,true),
    null, null,
    now(), now(), auth.uid(), auth.uid(), null
  )
  on conflict (usuario_id, empresa_id) where deleted_at is null
  do update set
    papel = excluded.papel,
    ativo = excluded.ativo,
    updated_at = now(),
    updated_by = auth.uid(),
    deleted_at = null;
end;
$$;


--
-- Name: admin_set_user_tenant_role(uuid, uuid, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_set_user_tenant_role(p_tenant_id uuid, p_usuario_id uuid, p_papel text, p_ativo boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'a'
    AS $$
declare
  v_papel text;
begin
  if not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;

  v_papel := upper(trim(coalesce(p_papel, 'GESTOR')));

  -- valida domínio do tenant
  if v_papel not in ('OWNER','ADMIN','CONTADOR','GESTOR') then
    raise exception 'invalid_tenant_role: %', v_papel;
  end if;

  insert into a.usuario_tenant (
    id, usuario_id, tenant_id, papel, ativo,
    created_at, updated_at, created_by, updated_by, deleted_at
  )
  values (
    gen_random_uuid(), p_usuario_id, p_tenant_id, v_papel, coalesce(p_ativo, true),
    now(), now(), auth.uid(), auth.uid(), null
  )
  on conflict (usuario_id, tenant_id) where deleted_at is null
  do update set
    papel = excluded.papel,
    ativo = excluded.ativo,
    updated_at = now(),
    updated_by = auth.uid(),
    deleted_at = null;
end;
$$;


--
-- Name: admin_update_user(uuid, uuid, text, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_update_user(p_tenant_id uuid, p_usuario_id uuid, p_nome text, p_telefone text, p_ativo boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'a'
    AS $$
begin
  if not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;

  update a.usuario
     set nome = nullif(trim(p_nome), ''),
         telefone = nullif(regexp_replace(coalesce(p_telefone,''), '\D', '', 'g'), ''),
         ativo = coalesce(p_ativo, true),
         updated_at = now(),
         updated_by = auth.uid()
   where id = p_usuario_id
     and deleted_at is null;

  if not found then
    raise exception 'user_not_found';
  end if;
end;
$$;


--
-- Name: apply_fiscal_regras_em_lote(boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apply_fiscal_regras_em_lote(p_somente_sem_registro boolean DEFAULT true) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
  v_count int := 0;
  r record;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;
  if v_tenant is null then
    raise exception 'Tenant atual não definido';
  end if;
  if v_empresa is null then
    raise exception 'Empresa atual não definida';
  end if;

  if not public.has_permission('fiscal.editar') then
    raise exception 'Sem permissão: fiscal.editar';
  end if;

  for r in
    select
      i.id as item_id,
      fi.ncm as ncm_atual,
      fi.cfop_padrao as cfop_atual,
      fi.cst_icms as cst_icms_atual,
      fi.cst_pis as cst_pis_atual,
      fi.cst_cofins as cst_cofins_atual,
      fi.origem as origem_atual,
      i.tipo as tipo_item
    from public.itens i
    left join public.fiscal_itens fi
      on fi.tenant_id = v_tenant
     and fi.empresa_id = v_empresa
     and fi.item_id = i.id
    where coalesce(i.ativo, true) = true
      and (
        p_somente_sem_registro = false
        or fi.item_id is null
      )
  loop
    perform public.apply_fiscal_to_item(
      r.item_id,
      r.ncm_atual,
      r.cfop_atual,
      r.cst_icms_atual,
      r.cst_pis_atual,
      r.cst_cofins_atual,
      r.origem_atual,
      r.tipo_item
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;


--
-- Name: apply_fiscal_regras_em_lote_admin(uuid, uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apply_fiscal_regras_em_lote_admin(p_tenant uuid, p_empresa uuid, p_somente_sem_registro boolean DEFAULT true) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_count int := 0;
  r record;
begin
  if session_user not in ('postgres', 'service_role') then
    raise exception 'Função admin: execução não permitida para %', session_user;
  end if;

  for r in
    select
      i.id as item_id,
      fi.ncm as ncm_atual,
      fi.cfop_padrao as cfop_atual,
      fi.cst_icms as cst_icms_atual,
      fi.cst_pis as cst_pis_atual,
      fi.cst_cofins as cst_cofins_atual,
      fi.origem as origem_atual,
      i.tipo as tipo_item
    from public.itens i
    left join public.fiscal_itens fi
      on fi.tenant_id = p_tenant
     and fi.empresa_id = p_empresa
     and fi.item_id = i.id
    where coalesce(i.ativo, true) = true
      and (p_somente_sem_registro = false or fi.item_id is null)
  loop
    perform public.apply_fiscal_to_item_admin(
      p_tenant, p_empresa,
      r.item_id,
      r.ncm_atual,
      r.cfop_atual,
      r.cst_icms_atual,
      r.cst_pis_atual,
      r.cst_cofins_atual,
      r.origem_atual,
      r.tipo_item
    );

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;


--
-- Name: apply_fiscal_to_item(integer, text, text, text, text, text, smallint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apply_fiscal_to_item(p_item_id integer, p_ncm text DEFAULT NULL::text, p_cfop text DEFAULT NULL::text, p_cst_icms text DEFAULT NULL::text, p_cst_pis text DEFAULT NULL::text, p_cst_cofins text DEFAULT NULL::text, p_origem smallint DEFAULT NULL::smallint, p_tipo_item text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
  v_regra_id uuid;
  v_regra public.fiscal_regras;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;
  if v_tenant is null then
    raise exception 'Tenant atual não definido';
  end if;
  if v_empresa is null then
    raise exception 'Empresa atual não definida';
  end if;

  if not public.has_permission('fiscal.editar') then
    raise exception 'Sem permissão: fiscal.editar';
  end if;

  v_regra_id := public.pick_fiscal_regra(
    p_ncm, p_cfop, p_cst_icms, p_cst_pis, p_cst_cofins, p_origem, p_tipo_item
  );

  if v_regra_id is null then
    raise exception 'Nenhuma regra fiscal encontrada para o contexto informado';
  end if;

  select * into v_regra
  from public.fiscal_regras
  where id = v_regra_id;

  insert into public.fiscal_itens (
    tenant_id, empresa_id, item_id,
    ncm, origem, cfop_padrao,
    cst_icms, cst_pis, cst_cofins,
    aliq_icms, aliq_pis, aliq_cofins,
    credita_icms, credita_pis, credita_cofins,
    atualizado_em
  )
  values (
    v_tenant, v_empresa, p_item_id,
    p_ncm, v_regra.origem, v_regra.cfop,
    v_regra.cst_icms, v_regra.cst_pis, v_regra.cst_cofins,
    v_regra.aliq_icms, v_regra.aliq_pis, v_regra.aliq_cofins,
    v_regra.credita_icms, v_regra.credita_pis, v_regra.credita_cofins,
    now()
  )
  on conflict (tenant_id, empresa_id, item_id) do update set
    ncm = excluded.ncm,
    origem = excluded.origem,
    cfop_padrao = excluded.cfop_padrao,
    cst_icms = excluded.cst_icms,
    cst_pis = excluded.cst_pis,
    cst_cofins = excluded.cst_cofins,
    aliq_icms = excluded.aliq_icms,
    aliq_pis = excluded.aliq_pis,
    aliq_cofins = excluded.aliq_cofins,
    credita_icms = excluded.credita_icms,
    credita_pis = excluded.credita_pis,
    credita_cofins = excluded.credita_cofins,
    atualizado_em = now();

  -- garante consistência (não deixa crédito true com CST null)
  update public.fiscal_itens fi
     set credita_icms = false
   where fi.tenant_id = v_tenant
     and fi.empresa_id = v_empresa
     and fi.item_id = p_item_id
     and fi.credita_icms = true
     and fi.cst_icms is null;

  update public.fiscal_itens fi
     set credita_pis = false
   where fi.tenant_id = v_tenant
     and fi.empresa_id = v_empresa
     and fi.item_id = p_item_id
     and fi.credita_pis = true
     and fi.cst_pis is null;

  update public.fiscal_itens fi
     set credita_cofins = false
   where fi.tenant_id = v_tenant
     and fi.empresa_id = v_empresa
     and fi.item_id = p_item_id
     and fi.credita_cofins = true
     and fi.cst_cofins is null;

end;
$$;


--
-- Name: apply_fiscal_to_item_admin(uuid, uuid, integer, text, text, text, text, text, smallint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apply_fiscal_to_item_admin(p_tenant uuid, p_empresa uuid, p_item_id integer, p_ncm text DEFAULT NULL::text, p_cfop text DEFAULT NULL::text, p_cst_icms text DEFAULT NULL::text, p_cst_pis text DEFAULT NULL::text, p_cst_cofins text DEFAULT NULL::text, p_origem smallint DEFAULT NULL::smallint, p_tipo_item text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_regra_id uuid;
  v_regra public.fiscal_regras;
begin
  if session_user not in ('postgres', 'service_role') then
    raise exception 'Função admin: execução não permitida para %', session_user;
  end if;

  v_regra_id := public.pick_fiscal_regra_admin(
    p_tenant, p_empresa,
    p_ncm, p_cfop, p_cst_icms, p_cst_pis, p_cst_cofins, p_origem, p_tipo_item
  );

  if v_regra_id is null then
    raise exception 'Nenhuma regra fiscal encontrada para o item_id=%', p_item_id;
  end if;

  select * into v_regra
  from public.fiscal_regras
  where id = v_regra_id;

  insert into public.fiscal_itens (
    tenant_id, empresa_id, item_id,
    ncm, origem, cfop_padrao,
    cst_icms, cst_pis, cst_cofins,
    aliq_icms, aliq_pis, aliq_cofins,
    credita_icms, credita_pis, credita_cofins,
    ipi_entra_no_custo,
    atualizado_em
  )
  values (
    p_tenant, p_empresa, p_item_id,
    p_ncm, v_regra.origem, v_regra.cfop,
    v_regra.cst_icms, v_regra.cst_pis, v_regra.cst_cofins,
    v_regra.aliq_icms, v_regra.aliq_pis, v_regra.aliq_cofins,
    v_regra.credita_icms, v_regra.credita_pis, v_regra.credita_cofins,
    false,
    now()
  )
  on conflict (tenant_id, empresa_id, item_id) do update set
    ncm = excluded.ncm,
    origem = excluded.origem,
    cfop_padrao = excluded.cfop_padrao,
    cst_icms = excluded.cst_icms,
    cst_pis = excluded.cst_pis,
    cst_cofins = excluded.cst_cofins,
    aliq_icms = excluded.aliq_icms,
    aliq_pis = excluded.aliq_pis,
    aliq_cofins = excluded.aliq_cofins,
    credita_icms = excluded.credita_icms,
    credita_pis = excluded.credita_pis,
    credita_cofins = excluded.credita_cofins,
    ipi_entra_no_custo = excluded.ipi_entra_no_custo,
    atualizado_em = now();
end;
$$;


--
-- Name: apply_movimentacao_estoque(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apply_movimentacao_estoque() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_delta numeric;
  v_saldo_anterior numeric;
  v_custo_medio numeric;
  v_custo_entrada numeric;
  v_novo_custo numeric;
begin
  if new.item_id is null then
    return new;
  end if;

  v_saldo_anterior := 0;
  select coalesce(e.quantidade_atual, 0)
    into v_saldo_anterior
  from public.estoque e
  where e.tenant_id = new.tenant_id
    and e.empresa_id = new.empresa_id
    and e.item_id = new.item_id
  limit 1;

  v_delta := case when new.tipo = 'saida' then -1 else 1 end * coalesce(new.quantidade, 0);

  insert into public.estoque(tenant_id, empresa_id, item_id, quantidade_atual)
  values (new.tenant_id, new.empresa_id, new.item_id, v_delta)
  on conflict (tenant_id, empresa_id, item_id) do update
    set quantidade_atual = coalesce(public.estoque.quantidade_atual, 0) + v_delta;

  if new.tipo = 'entrada' and coalesce(new.quantidade, 0) > 0 then
    select coalesce(i.custo_medio, 0)
      into v_custo_medio
    from public.itens i
    where i.id = new.item_id
      and i.tenant_id = new.tenant_id
    limit 1;

    v_custo_entrada := coalesce(new.custo_unitario_real, new.custo_unitario_bruto, 0);
    v_novo_custo := case
      when (v_saldo_anterior + new.quantidade) > 0
        then ((v_saldo_anterior * v_custo_medio) + (new.quantidade * v_custo_entrada)) / (v_saldo_anterior + new.quantidade)
      else v_custo_entrada
    end;

    update public.itens
    set custo_ultima_compra = v_custo_entrada,
        custo_medio = v_novo_custo
    where id = new.item_id
      and tenant_id = new.tenant_id;
  end if;

  return new;
end;
$$;


--
-- Name: audit_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_tenant uuid;
  v_uid uuid;
  v_email text;
  v_pk text;
begin
  v_uid := auth.uid();
  v_email := coalesce(auth.jwt() ->> 'email', null);

  -- tenta capturar tenant_id se existir na linha
  v_tenant := null;
  begin
    if tg_op in ('INSERT','UPDATE') then
      v_tenant := (to_jsonb(new) ->> 'tenant_id')::uuid;
    else
      v_tenant := (to_jsonb(old) ->> 'tenant_id')::uuid;
    end if;
  exception when others then
    v_tenant := null;
  end;

  -- tenta capturar PK "id" se existir
  v_pk := null;
  begin
    if tg_op in ('INSERT','UPDATE') then
      v_pk := to_jsonb(new) ->> 'id';
    else
      v_pk := to_jsonb(old) ->> 'id';
    end if;
  exception when others then
    v_pk := null;
  end;

  insert into public.audit_log(
    tenant_id, table_name, action, row_pk,
    old_data, new_data,
    actor_user_id, actor_email,
    request_id
  )
  values (
    v_tenant,
    tg_table_name,
    tg_op,
    v_pk,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end,
    v_uid,
    v_email,
    current_setting('request.jwt.claim.jti', true)
  );

  if tg_op = 'DELETE' then
    return old;
  else
    return new;
  end if;
end;
$$;


--
-- Name: auto_assign_empresa_segau(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auto_assign_empresa_segau() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
begin
  -- Pegar tenant padrão
  select id into v_tenant_id
  from public.tenants
  where ativo = true
  order by created_at asc nulls last
  limit 1;

  if v_tenant_id is null then
    return NEW;
  end if;

  -- Pegar empresa Elétrica Segau
  select id into v_empresa_id
  from public.empresas
  where tenant_id = v_tenant_id
    and (
      razao_social ilike '%segau%'
      or nome_fantasia ilike '%segau%'
    )
    and ativo = true
  limit 1;

  if v_empresa_id is null then
    return NEW;
  end if;

  -- Criar tenant membership
  insert into public.tenant_memberships (
    tenant_id,
    user_id,
    status,
    role
  ) values (
    v_tenant_id,
    NEW.id,
    'active',
    'admin'
  )
  on conflict do nothing;

  -- Criar empresa membership
  insert into public.empresa_memberships (
    tenant_id,
    empresa_id,
    user_id,
    role,
    status
  ) values (
    v_tenant_id,
    v_empresa_id,
    NEW.id,
    'user',
    'active'
  )
  on conflict do nothing;

  -- Definir contexto padrão
  insert into public.user_empresa_context (
    user_id,
    tenant_id,
    empresa_id
  ) values (
    NEW.id,
    v_tenant_id,
    v_empresa_id
  )
  on conflict (user_id, tenant_id) do update
    set empresa_id = excluded.empresa_id,
        updated_at = now();

  return NEW;
end;
$$;


--
-- Name: auto_set_context_on_login(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auto_set_context_on_login() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_tenant_id uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';  -- Tenant fixo
  v_empresa_id uuid := 'f0e74f49-a127-46b4-901b-f7b37e43c690'; -- Elétrica Segau
begin
  -- Setar tenant
  perform set_config('app.current_tenant_id', v_tenant_id::text, false);
  
  -- Setar empresa
  perform set_config('app.current_empresa_id', v_empresa_id::text, false);
  
  return NEW;
end;
$$;


--
-- Name: block_movimentacoes_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.block_movimentacoes_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  raise exception 'Movimentações são imutáveis. Use estorno.';
end $$;


--
-- Name: calculate_hh_lancamento(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_hh_lancamento() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  v_preco NUMERIC(10,2);
BEGIN
  -- Calcular horas trabalhadas (hora_saida - hora_entrada)
  NEW.horas_trabalhadas := EXTRACT(EPOCH FROM (NEW.hora_saida - NEW.hora_entrada)) / 3600.0;
  
  -- Se horas negativas (passou meia-noite), adicionar 24h
  IF NEW.horas_trabalhadas < 0 THEN
    NEW.horas_trabalhadas := NEW.horas_trabalhadas + 24;
  END IF;
  
  -- Se valor_hora nÃ£o foi fornecido ou Ã© 0, buscar de hh_tabela_precos
  -- Caso contrÃ¡rio, respeitar o valor enviado (vem de cliente_hh_servicos)
  IF NEW.valor_hora IS NULL OR NEW.valor_hora = 0 THEN
    SELECT 
      CASE 
        WHEN NEW.percentual_aplicado = 50 THEN preco_50
        WHEN NEW.percentual_aplicado = 100 THEN preco_100
        ELSE preco_base
      END
    INTO v_preco
    FROM public.hh_tabela_precos
    WHERE id = NEW.hh_tipo_id;
    
    NEW.valor_hora := COALESCE(v_preco, 0);
  END IF;
  
  NEW.valor_total := NEW.horas_trabalhadas * NEW.valor_hora;
  
  RETURN NEW;
END;
$$;


--
-- Name: can(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can(p_resource text, p_action text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'a', 'c'
    AS $$
  select public.can(p_resource, p_action, public.current_tenant_id());
$$;


--
-- Name: can(text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can(p_resource text, p_action text, p_tenant_id uuid) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'a', 'c'
    AS $$
declare
  v_auth_user_id uuid;
  v_usuario_id uuid;
  v_papel_tenant text;
  v_papel_empresa text;
  v_empresa_id uuid;
begin
  v_auth_user_id := auth.uid();
  if v_auth_user_id is null then
    return false;
  end if;

  select u.id
    into v_usuario_id
  from a.usuario u
  where u.auth_user_id = v_auth_user_id
    and u.ativo = true
    and u.deleted_at is null
  limit 1;

  if v_usuario_id is null then
    return false;
  end if;

  select ut.papel
    into v_papel_tenant
  from a.usuario_tenant ut
  where ut.usuario_id = v_usuario_id
    and ut.tenant_id = p_tenant_id
    and ut.ativo = true
    and ut.deleted_at is null
  order by ut.updated_at desc nulls last, ut.created_at desc nulls last
  limit 1;

  if v_papel_tenant is null then
    return false;
  end if;

  -- ADMIN/OWNER do tenant => sempre libera
  if v_papel_tenant in ('ADMIN','OWNER') then
    return true;
  end if;

  -- Para não-admin, verifica permissões específicas do papel empresa
  v_empresa_id := public.current_empresa_id();
  
  if v_empresa_id is not null then
    select ue.papel
      into v_papel_empresa
    from a.usuario_empresa ue
    where ue.usuario_id = v_usuario_id
      and ue.empresa_id = v_empresa_id
      and ue.ativo = true
      and ue.deleted_at is null
    limit 1;
  end if;

  -- ✅ PERMISSÕES PARA APONTAMENTO_RH

  -- XML Import
  if p_resource = 'xml_import' and p_action = 'execute' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH') then
      return true;
    end if;
  end if;

  -- NF Entrada Import
  if p_resource = 'nf_entrada' and p_action = 'import' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH') then
      return true;
    end if;
  end if;

  -- Financeiro (Contas a Pagar)
  if p_resource = 'financeiro' and p_action in ('write', 'config') then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'FINANCEIRO', 'COORDENACAO', 'ADMIN') then
      return true;
    end if;
  end if;

  -- Estoque
  if p_resource = 'estoque' and p_action = 'write' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COMPRAS', 'COORDENACAO', 'ADMIN') then
      return true;
    end if;
  end if;

  if p_resource = 'estoque' and p_action = 'read' then
    if v_papel_empresa in ('ALMOXARIFADO', 'APONTAMENTO_RH', 'COMPRAS', 'FINANCEIRO', 'COORDENACAO', 'ADMIN') then
      return true;
    end if;
  end if;

  -- MVP: não-admin -> nega admin.manage_users
  if p_resource = 'admin' and p_action = 'manage_users' then
    return false;
  end if;

  -- fallback conservador
  return false;
end;
$$;


--
-- Name: can__legacy_40734(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can__legacy_40734(p_resource text, p_action text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    SET row_security TO 'off'
    AS $$
  select exists (
    select 1
    from public.tenant_memberships tm
    join public.membership_roles mr on mr.membership_id = tm.id
    join public.roles r on r.id = mr.role_id
    join public.role_access_rules ar on ar.role_id = r.id
    where tm.user_id = auth.uid()
      and tm.tenant_id = public.current_tenant_id()
      and tm.status in ('active', 'ativo')
      and (r.tenant_id is null or r.tenant_id = tm.tenant_id)
      and ar.resource = p_resource
      and ar.action = p_action
  );
$$;


--
-- Name: can__legacy_56548(text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can__legacy_56548(p_resource text, p_action text, p_tenant_id uuid DEFAULT public.current_tenant_id()) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  allowed boolean;
begin
  if p_tenant_id is null then
    return false;
  end if;

  -- NOVO MODELO: a.usuario_tenant (OWNER/ADMIN) -> libera tudo
  if exists (
    select 1
    from a.usuario_tenant ut
    where ut.usuario_id = auth.uid()
      and ut.tenant_id = p_tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER','ADMIN')
  ) then
    return true;
  end if;

  -- MODELO ANTIGO (mantém compatibilidade)
  select exists (
    select 1
    from public.tenant_memberships tm
    join public.membership_roles mr on mr.membership_role = tm.role
    join public.roles r on r.id = mr.role_id
    join public.role_access_rules rul on rul.role_id = r.id
    where tm.user_id = auth.uid()
      and tm.tenant_id = p_tenant_id
      and tm.status = 'active'
      and r.is_active = true
      and rul.resource = p_resource
      and rul.action = p_action
  )
  into allowed;

  return coalesce(allowed, false);
end;
$$;


--
-- Name: can_many(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_many(p_pairs jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  arr public.capability_pair[];
begin
  select coalesce(array_agg(
    row(
      (x->>'key')::text,
      (x->>'resource')::text,
      (x->>'action')::text
    )::public.capability_pair
  ), '{}'::public.capability_pair[])
  into arr
  from jsonb_array_elements(coalesce(p_pairs, '[]'::jsonb)) as x;

  return public.can_many(arr);
end;
$$;


--
-- Name: can_many(public.capability_pair[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_many(p_pairs public.capability_pair[]) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_tenant_id uuid;
  r public.capability_pair;
  out jsonb := '{}'::jsonb;
  allowed boolean;
begin
  v_tenant_id := public.current_tenant_id();

  foreach r in array p_pairs loop
    if v_tenant_id is null then
      allowed := false;
    else
      allowed := public.can(r.resource, r.action, v_tenant_id);
    end if;

    out := out || jsonb_build_object(r.key, allowed);
  end loop;

  return out;
end;
$$;


--
-- Name: concluir_os(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.concluir_os(os_id_param integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
  update public.ordens_servico
  set status = 'concluida',
      data_conclusao = now(),
      atualizado_em = now()
  where id = os_id_param;

  update public.os_gestao_itens
  set progresso_percent = 100,
      data_prevista = coalesce(data_prevista, current_date),
      updated_at = now()
  where os_id = os_id_param
    and habilitado = true
    and item_tipo in ('projeto'::public.os_gestao_tipo, 'execucao'::public.os_gestao_tipo)
    and area in (
      'eletrico'::public.os_gestao_area,
      'seguranca'::public.os_gestao_area,
      'mecanico'::public.os_gestao_area,
      'software'::public.os_gestao_area
    )
    and coalesce(progresso_percent,0) < 100;
end;
$$;


--
-- Name: confirmar_lancamento_contabil(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.confirmar_lancamento_contabil(p_lancamento_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
  v_diff numeric;
  v_comp uuid;
  v_ano int;
  v_mes int;
  v_status_comp text;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;
  if v_tenant is null then
    raise exception 'Tenant atual não definido';
  end if;
  if v_empresa is null then
    raise exception 'Empresa atual não definida';
  end if;

  -- garante que lançamento é da empresa/tenant atual
  perform 1
  from public.lancamentos_contabeis
  where id = p_lancamento_id
    and tenant_id = v_tenant
    and empresa_id = v_empresa;

  if not found then
    raise exception 'Lançamento não encontrado para este tenant/empresa';
  end if;

  -- valida débito = crédito
  select diferenca into v_diff
  from public.v_lancamentos_contabeis_balance
  where lancamento_id = p_lancamento_id;

  if v_diff is null then v_diff := 0; end if;

  if v_diff <> 0 then
    raise exception 'Lançamento não balanceado (diferença=%). Ajuste débitos/créditos.', v_diff;
  end if;

  -- trava por competência: pega competência do data_lancamento (se não existir, cria)
  select data_lancamento into strict v_ano
  from public.lancamentos_contabeis
  where id = p_lancamento_id;

  -- cria/pega competencia do mês do lançamento
  select public.ensure_competencia(
    (select data_lancamento from public.lancamentos_contabeis where id = p_lancamento_id)
  ) into v_comp;

  -- verifica se competência está aberta
  select c.status into v_status_comp
  from public.competencias c
  where c.id = v_comp;

  if v_status_comp <> 'aberta' then
    raise exception 'Competência fechada. Não é permitido confirmar lançamentos nesse mês.';
  end if;

  -- grava competencia no lançamento e confirma
  update public.lancamentos_contabeis
     set competencia_id = v_comp,
         status = 'confirmado',
         atualizado_em = now()
   where id = p_lancamento_id;
end;
$$;


--
-- Name: criar_gestao_padrao_os(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.criar_gestao_padrao_os() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Só cria itens de gestão quando a OS estiver com gestão habilitada
  IF COALESCE(NEW.tem_gestao, false) IS DISTINCT FROM true THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.os_gestao_itens (tenant_id, os_id, item_tipo, area)
  VALUES
    (NEW.tenant_id, NEW.id, 'projeto',  'eletrico'),
    (NEW.tenant_id, NEW.id, 'projeto',  'mecanico'),
    (NEW.tenant_id, NEW.id, 'projeto',  'seguranca'),
    (NEW.tenant_id, NEW.id, 'projeto',  'software'),
    (NEW.tenant_id, NEW.id, 'execucao', 'eletrico'),
    (NEW.tenant_id, NEW.id, 'execucao', 'mecanico')
  ON CONFLICT ON CONSTRAINT os_gestao_itens_os_key DO NOTHING;

  RETURN NEW;
END;
$$;


--
-- Name: current_competencia_key(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_competencia_key(p_data date DEFAULT CURRENT_DATE) RETURNS TABLE(ano integer, mes integer)
    LANGUAGE sql STABLE
    AS $$
  select extract(year from p_data)::int as ano,
         extract(month from p_data)::int as mes;
$$;


--
-- Name: current_empresa_id(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_empresa_id(p_tenant_id uuid) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'a', 'c'
    AS $$
  select public.current_empresa_id();
$$;


--
-- Name: current_empresa_id__by_tenant(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_empresa_id__by_tenant(p_tenant_id uuid DEFAULT public.current_tenant_id()) RETURNS uuid
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  e uuid;
begin
  if p_tenant_id is null then
    return null;
  end if;

  select uec.empresa_id
    into e
  from public.user_empresa_context uec
  where uec.user_id = auth.uid()
    and uec.tenant_id = p_tenant_id
  limit 1;

  if e is not null then
    return e;
  end if;

  select em.empresa_id
    into e
  from public.empresa_memberships em
  where em.user_id = auth.uid()
    and em.tenant_id = p_tenant_id
    and em.status = 'active'
  order by em.criado_em asc
  limit 1;

  if e is not null then
    return e;
  end if;

  select ue.empresa_id
    into e
  from a.usuario_empresa ue
  where ue.usuario_id = auth.uid()
    and ue.tenant_id = p_tenant_id
    and ue.ativo = true
    and ue.deleted_at is null
  order by ue.created_at asc
  limit 1;

  return e;
end;
$$;


--
-- Name: debug_me(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.debug_me() RETURNS json
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_email text := coalesce((auth.jwt() ->> 'email'), '');
  v_roles text[];
begin
  if v_uid is null then
    raise exception 'Não autenticado';
  end if;

  -- recomendado: só Admin pode usar debug
  if not public.has_permission('cadastros.itens') and not public.has_permission('os.gerenciar') then
    -- Se quiser travar estritamente por Admin, eu ajusto para checar role 'Admin'.
    raise exception 'Sem permissão para debug';
  end if;

  select array_agg(distinct r.name order by r.name) into v_roles
  from public.tenant_memberships tm
  join public.membership_roles mr on mr.membership_id = tm.id
  join public.roles r on r.id = mr.role_id
  where tm.user_id = v_uid
    and tm.status = 'active'
    and tm.tenant_id = public.current_tenant_id();

  return json_build_object(
    'uid', v_uid,
    'email', v_email,
    'tenant_id', public.current_tenant_id(),
    'roles', coalesce(v_roles, array[]::text[])
  );
end $$;


--
-- Name: debug_membership(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.debug_membership() RETURNS TABLE(uid uuid, memberships_active integer, tenant_id uuid)
    LANGUAGE sql STABLE
    AS $$
  select
    auth.uid() as uid,
    (
      select count(*)
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.status = 'active'
    ) as memberships_active,
    (
      select tm.tenant_id
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.status = 'active'
      order by tm.created_at desc
      limit 1
    ) as tenant_id
$$;


--
-- Name: debug_tenant(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.debug_tenant() RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  select jsonb_build_object(
    'uid', auth.uid(),
    'tenant', public.current_tenant_id(),
    'tenant_setting', current_setting('app.tenant_id', true)
  );
$$;


--
-- Name: default_empresa_id(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.default_empresa_id(p_tenant_id uuid) RETURNS uuid
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select e.id
  from public.empresas e
  where e.tenant_id = p_tenant_id
  order by e.criado_em asc
  limit 1
$$;


--
-- Name: ensure_competencia(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_competencia(p_data date DEFAULT CURRENT_DATE) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
  v_ano int;
  v_mes int;
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;

  if v_tenant is null then
    raise exception 'Tenant atual não definido';
  end if;

  if v_empresa is null then
    raise exception 'Empresa atual não definida';
  end if;

  select ano, mes into v_ano, v_mes from public.current_competencia_key(p_data);

  insert into public.competencias (tenant_id, empresa_id, ano, mes)
  values (v_tenant, v_empresa, v_ano, v_mes)
  on conflict (tenant_id, empresa_id, ano, mes) do update
    set atualizado_em = now()
  returning id into v_id;

  return v_id;
end;
$$;


--
-- Name: ensure_estoque_rows(uuid, integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_estoque_rows(p_tenant_id uuid, p_item_ids integer[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_tenant uuid;
  v_empresa uuid;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Tenant atual não definido';
  end if;

  v_empresa := public.current_empresa_id();
  if v_empresa is null then
    raise exception 'Empresa atual não definida';
  end if;

  if not public.has_permission('estoque.ajustar') then
    raise exception 'Sem permissão: estoque.ajustar';
  end if;

  insert into public.estoque (tenant_id, empresa_id, item_id, quantidade_atual, atualizado_em)
  select v_tenant, v_empresa, x, 0, now()
  from unnest(p_item_ids) as x
  on conflict on constraint estoque_tenant_empresa_item_key do nothing;
end;
$$;


--
-- Name: estornar_lancamento_contabil(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.estornar_lancamento_contabil(p_lancamento_id uuid, p_historico text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
  v_status text;
  v_comp uuid;
  v_comp_status text;
  v_new_id uuid;
  v_hist text;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;
  if v_tenant is null then
    raise exception 'Tenant atual não definido';
  end if;
  if v_empresa is null then
    raise exception 'Empresa atual não definida';
  end if;

  select l.status, l.competencia_id, l.historico
    into v_status, v_comp, v_hist
  from public.lancamentos_contabeis l
  where l.id = p_lancamento_id
    and l.tenant_id = v_tenant
    and l.empresa_id = v_empresa;

  if not found then
    raise exception 'Lançamento não encontrado para este tenant/empresa';
  end if;

  if v_status <> 'confirmado' then
    raise exception 'Apenas lançamentos CONFIRMADOS podem ser estornados (status atual=%)', v_status;
  end if;

  if v_comp is not null then
    select status into v_comp_status
    from public.competencias
    where id = v_comp;

    if v_comp_status <> 'aberta' then
      raise exception 'Competência fechada. Não é permitido estornar lançamentos nesse mês.';
    end if;
  end if;

  -- cria cabeçalho do estorno
  insert into public.lancamentos_contabeis (
    tenant_id, empresa_id, competencia_id, data_lancamento,
    historico, origem_tipo, origem_id, status
  )
  select
    tenant_id, empresa_id, competencia_id, data_lancamento,
    coalesce(p_historico, 'ESTORNO: ' || historico),
    'estorno',
    p_lancamento_id::text,
    'confirmado'
  from public.lancamentos_contabeis
  where id = p_lancamento_id
  returning id into v_new_id;

  -- cria itens invertendo débito/credito
  insert into public.lancamentos_contabeis_itens (
    tenant_id, empresa_id, lancamento_id, conta_id, centro_custo_id, tipo, valor, complemento
  )
  select
    tenant_id, empresa_id, v_new_id, conta_id, centro_custo_id,
    case when tipo='debito' then 'credito' else 'debito' end,
    valor,
    coalesce(complemento,'') || ' (estorno)'
  from public.lancamentos_contabeis_itens
  where lancamento_id = p_lancamento_id;

  -- marca original como estornado
  update public.lancamentos_contabeis
     set status = 'estornado',
         atualizado_em = now()
   where id = p_lancamento_id;

  return v_new_id;
end;
$$;


--
-- Name: estornar_movimentacao(integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.estornar_movimentacao(p_mov_id integer, p_motivo text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v public.movimentacoes%rowtype;
  v_new_id int;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;

  if not public.has_permission('estoque.movimentar') then
    raise exception 'Sem permissão: estoque.movimentar';
  end if;

  select *
  into v
  from public.movimentacoes
  where id = p_mov_id
    and tenant_id = public.current_tenant_id();

  if not found then
    raise exception 'Movimentação não encontrada no tenant atual';
  end if;

  insert into public.movimentacoes (
    tenant_id,
    item_id,
    tipo,
    quantidade,
    motivo,
    realizado_por,
    data_movimentacao,
    custo_unitario_bruto,
    custo_unitario_real,
    credito_icms,
    credito_pis,
    credito_cofins,
    origem_nf_entrada_id,
    v_ipi, v_icms, v_pis, v_cofins, v_frete_rateado,
    created_at
  ) values (
    v.tenant_id,
    v.item_id,
    'estorno',
    (v.quantidade * -1),
    coalesce(p_motivo, 'Estorno da movimentação #' || v.id),
    coalesce(v.realizado_por, auth.uid()::text),
    now(),
    v.custo_unitario_bruto,
    v.custo_unitario_real,
    (v.credito_icms * -1),
    (v.credito_pis * -1),
    (v.credito_cofins * -1),
    v.origem_nf_entrada_id,
    (v.v_ipi * -1),
    (v.v_icms * -1),
    (v.v_pis * -1),
    (v.v_cofins * -1),
    (v.v_frete_rateado * -1),
    now()
  )
  returning id into v_new_id;

  return v_new_id;
end $$;


--
-- Name: fechar_competencia(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fechar_competencia(p_ano integer, p_mes integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;

  if v_tenant is null then
    raise exception 'Tenant atual não definido';
  end if;

  if v_empresa is null then
    raise exception 'Empresa atual não definida';
  end if;

  update public.competencias
     set status = 'fechada',
         fechada_em = now(),
         fechada_por = auth.uid(),
         atualizado_em = now()
   where tenant_id = v_tenant
     and empresa_id = v_empresa
     and ano = p_ano
     and mes = p_mes;

  if not found then
    raise exception 'Competência não encontrada para fechar (%/%). Crie primeiro.', p_mes, p_ano;
  end if;
end;
$$;


--
-- Name: fn_atualiza_estoque_por_mov(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_atualiza_estoque_por_mov() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_delta numeric;
  v_qtd   numeric;
begin
  if new.empresa_id is null then
    raise exception 'empresa_id obrigatório na movimentação (tenant_id=%, item_id=%)', new.tenant_id, new.item_id;
  end if;

  v_delta :=
    case new.tipo
      when 'entrada' then coalesce(new.quantidade, 0)
      when 'saida'   then -coalesce(new.quantidade, 0)
      when 'ajuste'  then coalesce(new.quantidade, 0)
      else null
    end;

  if v_delta is null then
    raise exception 'Tipo de movimentação inválido: %', new.tipo;
  end if;

  -- garante linha no estoque (tenant+empresa+item)
  insert into public.estoque (tenant_id, empresa_id, item_id, quantidade_atual, atualizado_em)
  values (new.tenant_id, new.empresa_id, new.item_id, 0, now())
  on conflict on constraint estoque_tenant_empresa_item_key do nothing;

  -- atualiza e captura novo saldo
  update public.estoque
     set quantidade_atual = quantidade_atual + v_delta,
         atualizado_em = now()
   where tenant_id  = new.tenant_id
     and empresa_id = new.empresa_id
     and item_id    = new.item_id
   returning quantidade_atual into v_qtd;

  if v_qtd < 0 then
    raise exception
      'Estoque não pode ficar negativo (tenant_id=%, empresa_id=%, item_id=%, saldo=%)',
      new.tenant_id, new.empresa_id, new.item_id, v_qtd;
  end if;

  return new;
end;
$$;


--
-- Name: fn_calc_horas_2_periodos(time without time zone, time without time zone, time without time zone, time without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_calc_horas_2_periodos(p_e1 time without time zone, p_s1 time without time zone, p_e2 time without time zone, p_s2 time without time zone) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
  v_min1 numeric;
  v_min2 numeric;
  v_total_h numeric;
BEGIN
  IF p_e1 IS NULL OR p_s1 IS NULL OR p_e2 IS NULL OR p_s2 IS NULL THEN
    RETURN NULL;
  END IF;

  IF p_s1 <= p_e1 THEN
    RAISE EXCEPTION 'Saída 1 (%) deve ser maior que Entrada 1 (%).', p_s1, p_e1;
  END IF;

  IF p_s2 <= p_e2 THEN
    RAISE EXCEPTION 'Saída 2 (%) deve ser maior que Entrada 2 (%).', p_s2, p_e2;
  END IF;

  IF p_s1 > p_e2 THEN
    RAISE EXCEPTION 'Saída 1 (%) deve ser menor/igual à Entrada 2 (%).', p_s1, p_e2;
  END IF;

  v_min1 := EXTRACT(EPOCH FROM (p_s1 - p_e1)) / 60.0;
  v_min2 := EXTRACT(EPOCH FROM (p_s2 - p_e2)) / 60.0;

  v_total_h := (v_min1 + v_min2) / 60.0;

  RETURN ROUND(v_total_h::numeric, 2);
END $$;


--
-- Name: fn_calc_horas_periodos(time without time zone, time without time zone, time without time zone, time without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_calc_horas_periodos(p_e1 time without time zone, p_s1 time without time zone, p_e2 time without time zone, p_s2 time without time zone) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
  v_min1 numeric;
  v_min2 numeric;
  v_total_h numeric;
BEGIN
  IF p_e1 IS NULL OR p_s1 IS NULL OR p_e2 IS NULL OR p_s2 IS NULL THEN
    RETURN NULL;
  END IF;

  IF p_s1 <= p_e1 THEN
    RAISE EXCEPTION 'Saída 1 (%) deve ser maior que Entrada 1 (%).', p_s1, p_e1;
  END IF;

  IF p_s2 <= p_e2 THEN
    RAISE EXCEPTION 'Saída 2 (%) deve ser maior que Entrada 2 (%).', p_s2, p_e2;
  END IF;

  IF p_s1 > p_e2 THEN
    RAISE EXCEPTION 'Saída 1 (%) deve ser menor/igual à Entrada 2 (%).', p_s1, p_e2;
  END IF;

  v_min1 := EXTRACT(EPOCH FROM (p_s1 - p_e1)) / 60.0;
  v_min2 := EXTRACT(EPOCH FROM (p_s2 - p_e2)) / 60.0;

  v_total_h := (v_min1 + v_min2) / 60.0;

  -- arredonda para 2 casas como a coluna "horas" (numeric(6,2))
  RETURN ROUND(v_total_h::numeric, 2);
END $$;


--
-- Name: fn_documento_key(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_documento_key(p_doc text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select case
    when p_doc is null then ''
    else
      case
        when length(regexp_replace(p_doc, '\D', '', 'g')) >= 14
          then substring(regexp_replace(p_doc, '\D', '', 'g') from 1 for 14)
        else regexp_replace(p_doc, '\D', '', 'g')
      end
  end
$$;


--
-- Name: fn_fornecedor_upsert_por_documento(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_fornecedor_upsert_por_documento(p_tenant_id uuid, p_nome text, p_documento text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
  v_doc_norm text := public.fn_normalize_documento(p_documento);
  v_id integer;
begin
  -- Se tem documento (CNPJ/CPF), tenta achar pelo documento_norm
  if v_doc_norm <> '' then
    select f.id
      into v_id
      from public.fornecedores f
     where f.tenant_id = p_tenant_id
       and f.documento_norm = v_doc_norm
     order by f.id
     limit 1;

    if v_id is not null then
      -- melhora o nome se vier mais completo
      update public.fornecedores
         set nome = coalesce(nullif(nome,''), p_nome)
       where id = v_id;

      return v_id;
    end if;
  end if;

  -- Se não achou (ou não tem documento), cria novo
  insert into public.fornecedores (tenant_id, nome, documento, ativo)
  values (p_tenant_id, coalesce(nullif(p_nome,''),'(Sem nome)'), nullif(p_documento,''), true)
  returning id into v_id;

  return v_id;
end $$;


--
-- Name: fn_hh_criar_apontamento(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_hh_criar_apontamento() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  v_apontamento_id uuid;
BEGIN
  -- Ao inserir/atualizar HH, criar/atualizar apontamento
  
  -- Buscar apontamento existente
  SELECT id INTO v_apontamento_id
  FROM public.apontamentos_horas
  WHERE hh_lancamento_id = NEW.id
  LIMIT 1;
  
  IF v_apontamento_id IS NULL THEN
    -- Criar novo
    INSERT INTO public.apontamentos_horas (
      tenant_id,
      empresa_id,
      os_id,
      colaborador_id,
      data,
      horas,
      gerado_por_hh,
      hh_lancamento_id,
      status
    ) VALUES (
      NEW.tenant_id,
      NEW.empresa_id,
      NEW.os_id,
      NEW.colaborador_id,
      NEW.data,
      NEW.horas_trabalhadas,
      true,
      NEW.id,
      'lancado'
    );
  ELSE
    -- Atualizar existente
    UPDATE public.apontamentos_horas
    SET
      colaborador_id = NEW.colaborador_id,
      data = NEW.data,
      horas = NEW.horas_trabalhadas
    WHERE id = v_apontamento_id;
  END IF;
  
  RETURN NEW;
END;
$$;


--
-- Name: fn_hh_delete_apontamento(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_hh_delete_apontamento() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  -- Marcar apontamento como deletado
  UPDATE public.apontamentos_horas
  SET deleted_at = now()
  WHERE hh_lancamento_id = OLD.id
    AND deleted_at IS NULL;
  
  RETURN OLD;
END;
$$;


--
-- Name: fn_hh_lancamentos_calc(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_hh_lancamentos_calc() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_perc int;
  v_cliente_id bigint;
  v_servico_id bigint;
  v_preco numeric;
  v_ok_vinculo boolean;
BEGIN
  -- 1) percentual sempre pela data (0/50/100)
  v_perc := public.fn_percentual_por_data(NEW.data);
  NEW.percentual_aplicado := v_perc;

  -- 2) Se usou 2 períodos, calcula horas. Se foi preenchido manualmente, aceita horas_trabalhadas direto
  IF NEW.entrada_1 IS NOT NULL OR NEW.saida_1 IS NOT NULL OR NEW.entrada_2 IS NOT NULL OR NEW.saida_2 IS NOT NULL THEN
    -- Modo 2-períodos: todos os 4 campos devem ser preenchidos
    IF NEW.entrada_1 IS NULL OR NEW.saida_1 IS NULL OR NEW.entrada_2 IS NULL OR NEW.saida_2 IS NULL THEN
      RAISE EXCEPTION 'Preencha Entrada 1, Saída 1, Entrada 2 e Saída 2 ou deixe todos em branco.';
    END IF;

    NEW.horas_trabalhadas := public.fn_calc_horas_2_periodos(
      NEW.entrada_1, NEW.saida_1, NEW.entrada_2, NEW.saida_2
    );

    NEW.hora_entrada := NEW.entrada_1;
    NEW.hora_saida   := NEW.saida_2;
  ELSIF NEW.horas_trabalhadas IS NULL THEN
    -- Se nem período nem horas_trabalhadas foram preenchidas, erro
    RAISE EXCEPTION 'Preencha ou (Entrada 1, Saída 1, Entrada 2, Saída 2) ou horas_trabalhadas.';
  END IF;

  -- 3) Descobrir cliente da OS
  SELECT os.cliente_id::bigint
    INTO v_cliente_id
  FROM public.ordens_servico os
  WHERE os.id = NEW.os_id
    AND os.tenant_id = NEW.tenant_id
  LIMIT 1;

  IF v_cliente_id IS NULL THEN
    RAISE EXCEPTION 'OS % sem cliente vinculado (cliente_id).', NEW.os_id;
  END IF;

  -- 4) Serviço escolhido no lançamento:
  --    CRÍTICO: Usar hh_servico_id (ID real do serviço, ex: 8)
  --    NÃO usar hh_tipo_id (é apenas percentual mapping: 10, 11, 13, etc.)
  v_servico_id := NEW.hh_servico_id;

  IF v_servico_id IS NULL OR v_servico_id <= 0 THEN
    RAISE EXCEPTION 'Serviço HH inválido no lançamento (hh_servico_id=%).', NEW.hh_servico_id;
  END IF;

  -- 5) Valida se o colaborador tem vínculo com esse serviço para esse cliente
  SELECT EXISTS (
    SELECT 1
    FROM public.colaborador_cliente_funcao ccf
    WHERE ccf.tenant_id = NEW.tenant_id
      AND ccf.cliente_id = v_cliente_id
      AND ccf.colaborador_id = NEW.colaborador_id
      AND ccf.hh_servico_id = v_servico_id
      AND COALESCE(ccf.ativo, true) = true
  )
  INTO v_ok_vinculo;

  IF NOT v_ok_vinculo THEN
    RAISE EXCEPTION
      'Serviço HH % não está vinculado ao colaborador % para o cliente % (colaborador_cliente_funcao).',
      v_servico_id, NEW.colaborador_id, v_cliente_id;
  END IF;

  -- 6) Buscar preço no cliente_hh_servicos pelo serviço selecionado + cliente/empresa/tenant
  SELECT
    CASE
      WHEN v_perc = 0   THEN s.preco_base
      WHEN v_perc = 50  THEN s.preco_50
      WHEN v_perc = 100 THEN s.preco_100
      ELSE NULL
    END
  INTO v_preco
  FROM public.cliente_hh_servicos s
  WHERE s.tenant_id = NEW.tenant_id
    AND s.empresa_id = NEW.empresa_id
    AND s.cliente_id = v_cliente_id
    AND s.id = v_servico_id
    AND s.ativo = true
  LIMIT 1;

  IF v_preco IS NULL THEN
    RAISE EXCEPTION
      'Preço HH não encontrado para serviço % / cliente % / empresa % / percentual %.',
      v_servico_id, v_cliente_id, NEW.empresa_id, v_perc;
  END IF;

  NEW.valor_hora  := ROUND(v_preco::numeric, 2);
  NEW.valor_total := ROUND(COALESCE(NEW.horas_trabalhadas, 0) * COALESCE(NEW.valor_hora, 0), 2);

  RETURN NEW;
END;
$$;


--
-- Name: fn_hh_sync_apontamento(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_hh_sync_apontamento() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_apontamento_id uuid;
BEGIN
  -- Buscar apontamento existente vinculado a este HH
  SELECT id INTO v_apontamento_id
  FROM public.apontamentos_horas
  WHERE hh_lancamento_id = NEW.id
  LIMIT 1;
  
  IF v_apontamento_id IS NULL THEN
    -- Criar novo apontamento (somente total, sem horários)
    INSERT INTO public.apontamentos_horas (
      tenant_id,
      empresa_id,
      os_id,
      colaborador_id,
      data,
      horas,
      gerado_por_hh,
      hh_lancamento_id,
      status,
      hora_entrada_1,
      hora_saida_1,
      hora_entrada_2,
      hora_saida_2
    ) VALUES (
      NEW.tenant_id,
      NEW.empresa_id,
      NEW.os_id,
      NEW.colaborador_id,
      NEW.data,
      NEW.horas_trabalhadas,
      true,
      NEW.id,
      'lancado',
      NULL,  -- Sem horários, somente total
      NULL,
      NULL,
      NULL
    );
  ELSE
    -- Atualizar apontamento existente
    UPDATE public.apontamentos_horas
    SET
      colaborador_id = NEW.colaborador_id,
      data = NEW.data,
      horas = NEW.horas_trabalhadas,
      status = 'lancado'
    WHERE id = v_apontamento_id;
  END IF;
  
  RETURN NEW;
END;
$$;


--
-- Name: fn_normalize_documento(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_normalize_documento(p_doc text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select regexp_replace(coalesce(p_doc, ''), '[^0-9]', '', 'g');
$$;


--
-- Name: fn_ordens_servico_validate_hh(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_ordens_servico_validate_hh() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_cliente_habilita_hh boolean;
begin
  -- Se não tem cliente, não pode marcar HH
  if new.cliente_id is null then
    new.usa_relatorio_hh := false;
    return new;
  end if;

  -- Se não está marcada como HH, ok
  if coalesce(new.usa_relatorio_hh, false) = false then
    return new;
  end if;

  -- Se marcou HH, valida se o cliente permite HH
  select c.habilita_hh
    into v_cliente_habilita_hh
  from public.clientes c
  where c.id = new.cliente_id
    and c.tenant_id = new.tenant_id
    and c.empresa_id = new.empresa_id;

  if coalesce(v_cliente_habilita_hh, false) = false then
    raise exception
      'Cliente % não está habilitado para HH (clientes.habilita_hh=false). Não é permitido salvar OS com usa_relatorio_hh=true.',
      new.cliente_id
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;


--
-- Name: FUNCTION fn_ordens_servico_validate_hh(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_ordens_servico_validate_hh() IS 'Bloqueia OS HH (usa_relatorio_hh=true) quando o cliente não tem habilita_hh=true. Força false se cliente_id for null.';


--
-- Name: fn_percentual_por_data(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_percentual_por_data(p_data date) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT CASE EXTRACT(DOW FROM p_data)
    WHEN 0 THEN 100
    WHEN 6 THEN 50
    ELSE 0
  END;
$$;


--
-- Name: fn_set_fator_aplicado(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_set_fator_aplicado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_fator numeric(6,3);
begin
  -- Se não informou tipo, assume fator 1.000
  if new.tipo_hora_id is null then
    -- só seta se estiver null, ou se mudou o tipo (para manter coerência)
    if new.fator_aplicado is null or (tg_op = 'UPDATE' and new.tipo_hora_id is distinct from old.tipo_hora_id) then
      new.fator_aplicado := 1.000;
    end if;
    return new;
  end if;

  select fator into v_fator
  from public.tipos_horas
  where id = new.tipo_hora_id
    and ativo = true;

  -- Se não achar (tipo inativo/excluído), assume 1.000
  if v_fator is null then
    v_fator := 1.000;
  end if;

  -- Regra:
  -- - Se fator_aplicado está null, preenche.
  -- - Se UPDATE e mudou tipo_hora_id, recalcula o fator_aplicado.
  if new.fator_aplicado is null
     or (tg_op = 'UPDATE' and new.tipo_hora_id is distinct from old.tipo_hora_id) then
    new.fator_aplicado := v_fator;
  end if;

  return new;
end;
$$;


--
-- Name: fn_set_horas_from_periodos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_set_horas_from_periodos() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_horas numeric;
  v_info text;
BEGIN
  -- Se não usou períodos (modo antigo), não mexe
  IF NEW.hora_entrada_1 IS NULL
     AND NEW.hora_saida_1 IS NULL
     AND NEW.hora_entrada_2 IS NULL
     AND NEW.hora_saida_2 IS NULL THEN
    RETURN NEW;
  END IF;

  -- Se começou a usar, exige os 4 preenchidos
  IF NEW.hora_entrada_1 IS NULL OR NEW.hora_saida_1 IS NULL
     OR NEW.hora_entrada_2 IS NULL OR NEW.hora_saida_2 IS NULL THEN
    RAISE EXCEPTION 'Preencha Entrada 1, Saída 1, Entrada 2 e Saída 2 para calcular horas.';
  END IF;

  v_horas := public.fn_calc_horas_periodos(
    NEW.hora_entrada_1, NEW.hora_saida_1,
    NEW.hora_entrada_2, NEW.hora_saida_2
  );

  NEW.horas := v_horas;

  -- Opcional: anexa string de horários na descricao, sem destruir o que já existe
  v_info := format(
    'Horários: %s-%s / %s-%s',
    to_char(NEW.hora_entrada_1, 'HH24:MI'),
    to_char(NEW.hora_saida_1,   'HH24:MI'),
    to_char(NEW.hora_entrada_2, 'HH24:MI'),
    to_char(NEW.hora_saida_2,   'HH24:MI')
  );

  IF NEW.descricao IS NULL OR btrim(NEW.descricao) = '' THEN
    NEW.descricao := v_info;
  ELSIF position('Horários:' in NEW.descricao) = 0 THEN
    NEW.descricao := NEW.descricao || ' | ' || v_info;
  END IF;

  RETURN NEW;
END $$;


--
-- Name: fn_validar_apontamento_horas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_validar_apontamento_horas() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_status text;
  v_taxa numeric(10,2);
begin
  -- 1) Validar status da OS (bloqueia concluída/cancelada)
  select status into v_status
  from public.ordens_servico
  where id = new.os_id;

  if v_status is null then
    raise exception 'OS % não encontrada.', new.os_id;
  end if;

  if v_status in ('concluida', 'cancelada') then
    raise exception 'Não é permitido lançar horas: OS % está com status "%".', new.os_id, v_status;
  end if;

  -- 2) Se foi gerado por HH, não exigir taxa do colaborador (HH não depende de colaborador_taxas)
  if coalesce(new.gerado_por_hh, false) = true then
    return new;
  end if;

  -- 3) Validar existência de taxa vigente na data do apontamento (fluxo de apontamento normal)
  select t.valor_hora into v_taxa
  from public.colaborador_taxas t
  where t.colaborador_id = new.colaborador_id
    and new.data >= t.vigencia_inicio
    and (t.vigencia_fim is null or new.data <= t.vigencia_fim)
  order by t.vigencia_inicio desc, t.criado_em desc
  limit 1;

  if v_taxa is null then
    raise exception
      'Não é permitido lançar horas: colaborador % não possui taxa vigente em %.',
      new.colaborador_id, new.data;
  end if;

  return new;
end;
$$;


--
-- Name: gerar_relatorio_hh_os(integer, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gerar_relatorio_hh_os(p_os_id integer, p_periodo_inicio date, p_periodo_fim date) RETURNS TABLE(relatorio_id bigint, total numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_tenant_id uuid;
  v_cliente_id bigint;
  v_tabela_hh_id bigint;
  v_relatorio_id bigint;
  v_total numeric := 0;
  v_ano int;
  v_missing_apontamento_id text;
  v_missing_valor_apontamento_id text;
BEGIN
  -- 1) Tenant obrigatorio
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Tenant nao definido (current_tenant_id retornou null).';
  END IF;

  IF p_periodo_inicio IS NULL OR p_periodo_fim IS NULL THEN
    RAISE EXCEPTION 'Periodo inicio e fim sao obrigatorios.';
  END IF;

  IF p_periodo_inicio > p_periodo_fim THEN
    RAISE EXCEPTION 'Periodo inicio maior que periodo fim.';
  END IF;

  -- 2) Descobrir cliente da OS
  SELECT os.cliente_id
    INTO v_cliente_id
  FROM public.ordens_servico os
  WHERE os.id = p_os_id
    AND os.tenant_id = v_tenant_id
  LIMIT 1;

  IF v_cliente_id IS NULL THEN
    RAISE EXCEPTION 'OS % nao encontrada ou sem cliente vinculado.', p_os_id;
  END IF;

  -- 3) Descobrir tabela HH ativa do cliente para o ano do periodo
  v_ano := EXTRACT(YEAR FROM p_periodo_inicio)::int;
  SELECT t.id
    INTO v_tabela_hh_id
  FROM public.cliente_hh_tabela t
  WHERE t.tenant_id = v_tenant_id
    AND t.cliente_id = v_cliente_id
    AND t.ano = v_ano
    AND t.ativo = true
  ORDER BY t.criado_em DESC
  LIMIT 1;

  IF v_tabela_hh_id IS NULL THEN
    RAISE EXCEPTION 'Tabela HH ativa nao encontrada para cliente % no ano %.', v_cliente_id, v_ano;
  END IF;

  -- 4) Nao recalcular se ja existir relatorio fechado para a mesma OS e periodo
  IF EXISTS (
    SELECT 1
    FROM public.os_relatorios_hh r
    WHERE r.tenant_id = v_tenant_id
      AND r.os_id = p_os_id
      AND r.periodo_inicio = p_periodo_inicio
      AND r.periodo_fim = p_periodo_fim
      AND r.status = 'fechado'
  ) THEN
    RAISE EXCEPTION 'Relatorio HH ja fechado para OS % no periodo % a %.', p_os_id, p_periodo_inicio, p_periodo_fim;
  END IF;

  -- 5) Cria cabecalho (status fechado) com total 0 (sera atualizado no fim)
  INSERT INTO public.os_relatorios_hh (
    tenant_id,
    os_id,
    cliente_id,
    tabela_hh_id,
    periodo_inicio,
    periodo_fim,
    data_emissao,
    status,
    total
  ) VALUES (
    v_tenant_id,
    p_os_id,
    v_cliente_id,
    v_tabela_hh_id,
    p_periodo_inicio,
    p_periodo_fim,
    current_date,
    'fechado',
    0
  )
  RETURNING id INTO v_relatorio_id;

  -- 6) Validar especialidade: se nao houver, aborta com erro claro
  WITH base AS (
    SELECT
      ah.id AS apontamento_id,
      ah.colaborador_id,
      ah.data,
      ah.entrada_1,
      ah.saida_1,
      ah.entrada_2,
      ah.saida_2,
      ah.horas_trabalhadas,
      ah.tipo_hora_id,
      ah.fator_aplicado,
      COALESCE(ah.hh_especialidade_id, c.hh_especialidade_id) AS especialidade_id,
      th.codigo AS tipo_hora_codigo,
      th.fator AS tipo_hora_fator
    FROM public.apontamentos_horas ah
    LEFT JOIN public.colaboradores c ON c.id = ah.colaborador_id
    LEFT JOIN public.tipos_horas th ON th.id = ah.tipo_hora_id
    WHERE ah.tenant_id = v_tenant_id
      AND ah.os_id = p_os_id
      AND ah.data BETWEEN p_periodo_inicio AND p_periodo_fim
  )
  SELECT b.apontamento_id
    INTO v_missing_apontamento_id
  FROM base b
  WHERE b.especialidade_id IS NULL
  LIMIT 1;

  IF v_missing_apontamento_id IS NOT NULL THEN
    RAISE EXCEPTION 'Apontamento % sem especialidade (hh_especialidade_id).', v_missing_apontamento_id;
  END IF;

  -- 7) Validar valor_base da tabela HH para cada especialidade
  WITH base AS (
    SELECT
      ah.id AS apontamento_id,
      ah.colaborador_id,
      ah.data,
      ah.entrada_1,
      ah.saida_1,
      ah.entrada_2,
      ah.saida_2,
      ah.horas_trabalhadas,
      ah.tipo_hora_id,
      ah.fator_aplicado,
      COALESCE(ah.hh_especialidade_id, c.hh_especialidade_id) AS especialidade_id,
      th.codigo AS tipo_hora_codigo,
      th.fator AS tipo_hora_fator
    FROM public.apontamentos_horas ah
    LEFT JOIN public.colaboradores c ON c.id = ah.colaborador_id
    LEFT JOIN public.tipos_horas th ON th.id = ah.tipo_hora_id
    WHERE ah.tenant_id = v_tenant_id
      AND ah.os_id = p_os_id
      AND ah.data BETWEEN p_periodo_inicio AND p_periodo_fim
  ), enriched AS (
    SELECT
      b.*,
      ti.valor_base
    FROM base b
    LEFT JOIN public.cliente_hh_tabela_itens ti
      ON ti.tabela_hh_id = v_tabela_hh_id
     AND ti.hh_especialidade_id = b.especialidade_id
  )
  SELECT e.apontamento_id
    INTO v_missing_valor_apontamento_id
  FROM enriched e
  WHERE e.valor_base IS NULL
  LIMIT 1;

  IF v_missing_valor_apontamento_id IS NOT NULL THEN
    RAISE EXCEPTION 'Valor base nao encontrado na tabela HH para o apontamento %.', v_missing_valor_apontamento_id;
  END IF;

  -- 8) Inserir linhas (snapshot) com calculos financeiros
  WITH base AS (
    SELECT
      ah.id AS apontamento_id,
      ah.colaborador_id,
      ah.data,
      ah.entrada_1,
      ah.saida_1,
      ah.entrada_2,
      ah.saida_2,
      ah.horas_trabalhadas,
      ah.tipo_hora_id,
      ah.fator_aplicado,
      COALESCE(ah.hh_especialidade_id, c.hh_especialidade_id) AS especialidade_id,
      th.codigo AS tipo_hora_codigo,
      th.fator AS tipo_hora_fator
    FROM public.apontamentos_horas ah
    LEFT JOIN public.colaboradores c ON c.id = ah.colaborador_id
    LEFT JOIN public.tipos_horas th ON th.id = ah.tipo_hora_id
    WHERE ah.tenant_id = v_tenant_id
      AND ah.os_id = p_os_id
      AND ah.data BETWEEN p_periodo_inicio AND p_periodo_fim
  ), enriched AS (
    SELECT
      b.*,
      he.descricao AS especialidade_descricao,
      ti.valor_base,
      COALESCE(b.fator_aplicado, b.tipo_hora_fator, 1) AS fator_final
    FROM base b
    JOIN public.hh_especialidades he ON he.id = b.especialidade_id
    JOIN public.cliente_hh_tabela_itens ti
      ON ti.tabela_hh_id = v_tabela_hh_id
     AND ti.hh_especialidade_id = b.especialidade_id
  )
  INSERT INTO public.os_relatorios_hh_linhas (
    tenant_id,
    relatorio_id,
    colaborador_id,
    data,
    entrada_1,
    saida_1,
    entrada_2,
    saida_2,
    horas_trabalhadas,
    fator,
    tipo_hora_codigo,
    especialidade_descricao,
    valor_hora_base,
    valor_hora_aplicado,
    total
  )
  SELECT
    v_tenant_id,
    v_relatorio_id,
    e.colaborador_id,
    e.data,
    e.entrada_1,
    e.saida_1,
    e.entrada_2,
    e.saida_2,
    e.horas_trabalhadas,
    e.fator_final,
    e.tipo_hora_codigo,
    e.especialidade_descricao,
    e.valor_base,
    (e.valor_base * e.fator_final) AS valor_hora_aplicado,
    ROUND(e.horas_trabalhadas * (e.valor_base * e.fator_final), 2) AS total
  FROM enriched e;

  -- 9) Atualizar total no cabecalho (arredondamento financeiro)
  SELECT COALESCE(ROUND(SUM(l.total), 2), 0)
    INTO v_total
  FROM public.os_relatorios_hh_linhas l
  WHERE l.relatorio_id = v_relatorio_id;

  UPDATE public.os_relatorios_hh
     SET total = v_total
   WHERE id = v_relatorio_id;

  -- 10) Retorna id e total
  RETURN QUERY SELECT v_relatorio_id, v_total;
END;
$$;


--
-- Name: get_default_empresa_id(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_default_empresa_id(p_tenant_id uuid) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select e.id
  from public.empresas e
  where e.tenant_id = p_tenant_id
    and e.ativo = true
  order by e.criado_em asc nulls last
  limit 1;
$$;


--
-- Name: get_default_tenant_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_default_tenant_id() RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  tenant_id uuid;
  has_created_at boolean;
  has_criado_em boolean;
begin
  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'tenants'
  ) then
    raise exception 'Tabela tenants nao encontrada.';
  end if;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'tenants'
      and column_name = 'created_at'
  ) into has_created_at;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'tenants'
      and column_name = 'criado_em'
  ) into has_criado_em;

  if has_criado_em then
    execute 'select id from public.tenants order by criado_em asc nulls last limit 1'
      into tenant_id;
  elsif has_created_at then
    execute 'select id from public.tenants order by created_at asc nulls last limit 1'
      into tenant_id;
  else
    execute 'select id from public.tenants limit 1'
      into tenant_id;
  end if;

  if tenant_id is null then
    raise exception 'Nenhum tenant encontrado.';
  end if;

  return tenant_id;
end;
$$;


--
-- Name: get_full_permissions(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_full_permissions(p_tenant_id uuid, p_empresa_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'a'
    AS $$
declare
  v_usuario_id uuid;
  v_tenant_papel text;
  v_empresa_papel text;
  v_perm_extra jsonb;
  v_perm_negadas jsonb;
  base_perms jsonb := '{}'::jsonb;
  extra_perms jsonb := '{}'::jsonb;
  result_perms jsonb;
begin
  select u.id into v_usuario_id
  from a.usuario u
  where u.auth_user_id = auth.uid()
    and u.deleted_at is null
  limit 1;

  if v_usuario_id is null then
    return '{}'::jsonb;
  end if;

  select ut.papel into v_tenant_papel
  from a.usuario_tenant ut
  where ut.usuario_id = v_usuario_id
    and ut.tenant_id = p_tenant_id
    and ut.ativo = true
    and ut.deleted_at is null
  limit 1;

  if v_tenant_papel is null then
    return '{}'::jsonb;
  end if;

  select jsonb_object_agg(rp.permission, true) into base_perms
  from public.role_permissions rp
  where rp.role = a.fn_map_papel_tenant_to_role(v_tenant_papel);

  base_perms := coalesce(base_perms, '{}'::jsonb);

  select ue.papel, ue.permissoes_extra, ue.permissoes_negadas
  into v_empresa_papel, v_perm_extra, v_perm_negadas
  from a.usuario_empresa ue
  where ue.usuario_id = v_usuario_id
    and ue.empresa_id = p_empresa_id
    and ue.ativo = true
    and ue.deleted_at is null
  limit 1;

  if v_empresa_papel is null then
    return base_perms;
  end if;

  -- módulo preferencial por papel empresa
  extra_perms := extra_perms || jsonb_build_object(
    'modulo_preferencial',
    (
      case upper(coalesce(v_empresa_papel,''))
        when 'ADMIN' then 'admin'
        when 'FINANCEIRO' then 'financeiro'
        when 'COORDENACAO' then 'projetos'
        when 'COMPRAS' then 'estoque'
        when 'ALMOXARIFADO' then 'estoque'
        when 'APONTAMENTO_RH' then 'projetos'
        else null
      end
    )
  );

  -- GARANTIA: permissões mínimas OS
  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','COORDENACAO') then
    extra_perms := extra_perms || jsonb_build_object(
      'os.read', true,
      'os.write', true,
      'os.delete', true
    );
  end if;

  -- ESTOQUE READ (mantém)
  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH') then
    extra_perms := extra_perms || jsonb_build_object('estoque.read', true);
  end if;

  -- ✅ ESTOQUE WRITE (agora inclui COORDENACAO pq “tem tudo do APONTAMENTO_RH”)
  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH','COORDENACAO') then
    extra_perms := extra_perms || jsonb_build_object('estoque.write', true);
  end if;

  -- IMOBILIZADO
  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH') then
    extra_perms := extra_perms || jsonb_build_object('imobilizado.read', true);
  end if;

  if upper(coalesce(v_empresa_papel,'')) in ('ADMIN','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH') then
    extra_perms := extra_perms || jsonb_build_object('imobilizado.write', true);
  end if;

  -- ✅ XML IMPORT (agora inclui COORDENACAO pq “tem tudo do APONTAMENTO_RH”)
  if upper(coalesce(v_empresa_papel,'')) in ('ALMOXARIFADO','APONTAMENTO_RH','COORDENACAO') then
    extra_perms := extra_perms || jsonb_build_object(
      'xml_import.execute', true,
      'nf_entrada.import', true,
      'cad_fornecedores.write', true,
      'cad_itens.write', true
    );
  end if;

  -- extras/negadas do usuário
  if v_perm_extra is not null then
    extra_perms := extra_perms || v_perm_extra;
  end if;

  result_perms := base_perms || extra_perms;

  if v_perm_negadas is not null then
    result_perms := result_perms - (select array_agg(key) from jsonb_object_keys(v_perm_negadas) as key);
  end if;

  return coalesce(result_perms, '{}'::jsonb);
end;
$$;


--
-- Name: get_hh_tipo_id_for_tenant(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_hh_tipo_id_for_tenant(p_tenant_id uuid) RETURNS bigint
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_hh_tipo_id BIGINT;
BEGIN
  -- Busca primeiro mapeamento ativo para o tenant
  SELECT hh_tipo_id INTO v_hh_tipo_id
  FROM public.hh_tipos_mapping
  WHERE tenant_id = p_tenant_id AND ativo = true
  LIMIT 1;
  
  RETURN v_hh_tipo_id;
END;
$$;


--
-- Name: FUNCTION get_hh_tipo_id_for_tenant(p_tenant_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_hh_tipo_id_for_tenant(p_tenant_id uuid) IS 'Resolve hh_tipo_id padrÃ£o para um tenant baseado em tipos_horas';


--
-- Name: get_my_active_tenant(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_active_tenant() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select public.current_tenant_id()
$$;


--
-- Name: get_my_permissions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_permissions() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'a'
    AS $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
begin
  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();
  
  if v_tenant_id is null or v_empresa_id is null then
    return '{}'::jsonb;
  end if;
  
  return public.get_full_permissions(v_tenant_id, v_empresa_id);
end;
$$;


--
-- Name: get_my_permissions(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_permissions(p_tenant_id uuid) RETURNS TABLE(permission text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'a'
    AS $$
  select e.key as permission
  from jsonb_each(public.get_full_permissions(p_tenant_id, public.current_empresa_id())) e
  where e.value = 'true'::jsonb;
$$;


--
-- Name: get_my_permissions(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_permissions(p_tenant_id uuid, p_empresa_id uuid) RETURNS TABLE(permission text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'a'
    AS $$
  select e.key
  from jsonb_each(public.get_full_permissions(p_tenant_id, p_empresa_id)) e
  where e.value = 'true'::jsonb;
$$;


--
-- Name: get_my_roles(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_roles() RETURNS TABLE(role text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select distinct r.name as role
  from public.tenant_memberships tm
  join public.membership_roles mr on mr.membership_id = tm.id
  join public.roles r on r.id = mr.role_id
  where tm.user_id = auth.uid()
    and tm.status = 'active'
    and tm.tenant_id = public.current_tenant_id()
  order by r.name
$$;


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  insert into public.profiles (id, email, nome)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'nome', new.raw_user_meta_data->>'name')
  )
  on conflict (id) do update
    set email = excluded.email,
        nome = excluded.nome;
  return new;
end;
$$;


--
-- Name: has_permission(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.has_permission(p_code text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    SET row_security TO 'off'
    AS $$
  select exists (
    select 1
    from public.v_user_permissions v
    where v.tenant_id = public.current_tenant_id()
      and v.permission = p_code
  );
$$;


--
-- Name: import_nf_entrada(uuid, public.item_finalidade, bigint, jsonb, jsonb, uuid, text, boolean, jsonb, integer, boolean, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.import_nf_entrada(p_empresa_id uuid, p_finalidade_contexto public.item_finalidade, p_fornecedor_id bigint, p_itens_json jsonb, p_nf_json jsonb, p_tenant_id uuid, p_xml_raw text, p_gerar_contas_pagar boolean DEFAULT false, p_parcelas_json jsonb DEFAULT NULL::jsonb, p_os_id integer DEFAULT NULL::integer, p_baixar_os boolean DEFAULT false, p_motivo_compra_id uuid DEFAULT NULL::uuid, p_solicitante_usuario_id uuid DEFAULT NULL::uuid) RETURNS TABLE(status text, message text, nf_entrada_id bigint)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_nf_id bigint;
  v_chave text;
  v_emitente text;
  v_numero text;
  v_serie text;
  v_data_emissao timestamptz;
  v_total_nf numeric(14,2);
  v_soma_parcelas numeric(14,2);

  v_categoria_id uuid;
  v_parcelamento_id uuid;

  v_it jsonb;

  v_item_id int;
  v_qtd numeric(14,3);
  v_vunit numeric(14,6);
  v_vtotal numeric(14,2);

  v_has_os boolean;

  v_solicitante_ok boolean;
  v_motivo_ok boolean;
begin
  if auth.uid() is null then
    raise exception 'Usuario nao autenticado';
  end if;

  if p_tenant_id is null then
    raise exception 'tenant_id obrigatorio';
  end if;

  perform set_config('app.tenant_id', p_tenant_id::text, true);

  if not exists (
    select 1
    from public.tenant_memberships tm
    where tm.user_id = auth.uid()
      and tm.tenant_id = p_tenant_id
      and tm.status in ('active','ativo')
  ) then
    raise exception 'Tenant nao autorizado';
  end if;

  if not public.can('xml_import','execute') then
    raise exception 'Sem permissao para importar XML';
  end if;

  if p_nf_json is null then
    raise exception 'p_nf_json e obrigatorio';
  end if;

  -- SOLICITANTE (OBRIGATORIO)
  if p_solicitante_usuario_id is null then
    raise exception 'Solicitante (usuario) e obrigatorio para importar';
  end if;

  select exists (
    select 1
    from a.usuario u
    join a.usuario_empresa ue on ue.usuario_id = u.id
    join public.tenant_memberships tm on tm.user_id = u.auth_user_id and tm.tenant_id = p_tenant_id
    where u.id = p_solicitante_usuario_id
      and u.deleted_at is null
      and u.ativo = true
      and ue.deleted_at is null
      and ue.ativo = true
      and ue.empresa_id = p_empresa_id
      and tm.status in ('active','ativo')
  ) into v_solicitante_ok;

  if not coalesce(v_solicitante_ok,false) then
    raise exception 'Solicitante invalido/sem acesso (usuario_id=%)', p_solicitante_usuario_id;
  end if;

  -- MOTIVO (OBRIGATORIO)
  if p_motivo_compra_id is null then
    raise exception 'Classificacao/Motivo e obrigatorio para importar';
  end if;

  select exists (
    select 1
    from f.motivo_compra mc
    where mc.id = p_motivo_compra_id
      and mc.tenant_id = p_tenant_id
      and mc.deleted_at is null
      and mc.ativo = true
      and mc.aplica_em in ('PRODUTO','AMBOS')
  ) into v_motivo_ok;

  if not coalesce(v_motivo_ok,false) then
    raise exception 'Motivo invalido/inativo ou nao aplicavel a PRODUTO (id=%)', p_motivo_compra_id;
  end if;

  v_chave := nullif(trim(p_nf_json->>'chave'), '');
  if v_chave is null then
    raise exception 'NF sem chave (p_nf_json.chave)';
  end if;

  -- Ja existe?
  select id into v_nf_id
  from public.nf_entrada
  where chave = v_chave
  limit 1;

  if v_nf_id is not null then
    status := 'ja_importada';
    message := 'NF ja importada';
    nf_entrada_id := v_nf_id;
    return next;
    return;
  end if;

  v_emitente := coalesce(nullif(p_nf_json->>'emitente_nome',''), 'Emitente');
  v_numero   := coalesce(nullif(p_nf_json->>'numero',''), '');
  v_serie    := coalesce(nullif(p_nf_json->>'serie',''), '');
  v_data_emissao := nullif(p_nf_json->>'data_emissao','')::timestamptz;
  v_total_nf := coalesce((p_nf_json->>'valor_total')::numeric, 0);

  -- Se veio OS, validar se existe e pertence ao tenant
  v_has_os := (p_os_id is not null);

  if v_has_os then
    if not exists (
      select 1
      from public.ordens_servico os
      where os.id = p_os_id
        and os.tenant_id = p_tenant_id
    ) then
      raise exception 'OS invalida (id=%) para este tenant', p_os_id;
    end if;
  end if;

  -- 1) NF
  insert into public.nf_entrada (
    chave,
    numero,
    serie,
    emitente_nome,
    emitente_cnpj,
    data_emissao,
    valor_produtos,
    valor_frete,
    valor_seguro,
    valor_desconto,
    valor_outros,
    valor_total,
    xml_raw,
    fornecedor_id,
    tenant_id,
    empresa_id,
    finalidade_contexto,
    os_id,
    baixa_os_automatica,
    motivo_compra_id,
    solicitante_usuario_id
  )
  values (
    v_chave,
    v_numero,
    v_serie,
    v_emitente,
    p_nf_json->>'emitente_cnpj',
    v_data_emissao,
    coalesce((p_nf_json->>'valor_produtos')::numeric, 0),
    coalesce((p_nf_json->>'valor_frete')::numeric, 0),
    coalesce((p_nf_json->>'valor_seguro')::numeric, 0),
    coalesce((p_nf_json->>'valor_desconto')::numeric, 0),
    coalesce((p_nf_json->>'valor_outros')::numeric, 0),
    v_total_nf,
    p_xml_raw,
    p_fornecedor_id,
    p_tenant_id,
    p_empresa_id,
    p_finalidade_contexto,
    p_os_id,
    p_baixar_os,
    p_motivo_compra_id,
    p_solicitante_usuario_id
  )
  returning id into v_nf_id;

  -- 2) NF itens (igual ao seu)
  insert into public.nf_entrada_itens (
    nf_entrada_id,
    item_id,
    codigo_fornecedor,
    descricao,
    ncm,
    cfop,
    qtd,
    v_unit,
    v_prod,
    v_icms,
    v_ipi,
    v_pis,
    v_cofins,
    aliq_icms,
    aliq_ipi,
    aliq_pis,
    aliq_cofins,
    aliquota_icms,
    aliquota_ipi,
    aliquota_pis,
    aliquota_cofins,
    tenant_id
  )
  select
    v_nf_id,
    nullif((elem->>'item_id')::bigint, 0),
    elem->>'codigo',
    elem->>'nome',
    elem->>'ncm',
    elem->>'cfop',
    coalesce((elem->>'quantidade')::numeric, (elem->>'qtd')::numeric, 0),
    coalesce((elem->>'valorUnit')::numeric, (elem->>'v_unit')::numeric, 0),
    coalesce((elem->>'total')::numeric, (elem->>'v_prod')::numeric, 0),
    coalesce((elem->>'v_icms')::numeric, 0),
    coalesce((elem->>'v_ipi')::numeric, 0),
    coalesce((elem->>'v_pis')::numeric, 0),
    coalesce((elem->>'v_cofins')::numeric, 0),
    nullif((elem->>'aliq_icms')::numeric, 0),
    nullif((elem->>'aliq_ipi')::numeric, 0),
    nullif((elem->>'aliq_pis')::numeric, 0),
    nullif((elem->>'aliq_cofins')::numeric, 0),
    nullif((elem->>'aliq_icms')::numeric, 0),
    nullif((elem->>'aliq_ipi')::numeric, 0),
    nullif((elem->>'aliq_pis')::numeric, 0),
    nullif((elem->>'aliq_cofins')::numeric, 0),
    p_tenant_id
  from jsonb_array_elements(coalesce(p_itens_json, '[]'::jsonb)) elem;

  -- (restante igual ao seu: movimentacoes, financeiro, os_itens...)

  status := 'ok';
  message := 'Importado com sucesso';
  nf_entrada_id := v_nf_id;
  return next;
end;
$$;


--
-- Name: import_nf_entrada_v2(uuid, uuid, text, text, text, date, date, numeric, text, text, boolean, date, uuid, uuid, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.import_nf_entrada_v2(p_tenant_id uuid, p_empresa_id uuid, p_chave_acesso text, p_numero text, p_serie text, p_emissao_date date, p_competencia_date date, p_valor_total numeric, p_fornecedor_nome text, p_fornecedor_documento text, p_gerar_titulo boolean, p_vencimento_date date, p_plano_contas_id uuid, p_centro_custo_id uuid DEFAULT NULL::uuid, p_os_id integer DEFAULT NULL::integer, p_observacoes text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_fornecedor_id integer;
  v_doc_id uuid;
  v_titulo_id uuid;
begin
  if coalesce(nullif(trim(p_chave_acesso),''),'') = '' then
    raise exception 'Chave de acesso é obrigatória.';
  end if;

  -- Fornecedor por CNPJ/CPF (consolidado)
  v_fornecedor_id := public.fn_fornecedor_upsert_por_documento(
    p_tenant_id,
    p_fornecedor_nome,
    p_fornecedor_documento
  );

  -- Documento fiscal (upsert por chave)
  insert into f.documento_fiscal (
    tenant_id,
    empresa_id,
    tipo,
    chave_acesso,
    fornecedor_id,
    emissao_date,
    competencia_date,
    valor_total,
    status,
    observacoes
  ) values (
    p_tenant_id,
    p_empresa_id,
    'NF_ENTRADA',
    p_chave_acesso,
    v_fornecedor_id,
    p_emissao_date,
    p_competencia_date,
    coalesce(p_valor_total, 0),
    'IMPORTADO',
    p_observacoes
  )
  on conflict (tenant_id, chave_acesso)
  do update set
    empresa_id = excluded.empresa_id,
    fornecedor_id = excluded.fornecedor_id,
    emissao_date = excluded.emissao_date,
    competencia_date = excluded.competencia_date,
    valor_total = excluded.valor_total,
    observacoes = excluded.observacoes,
    updated_at = now()
  returning id into v_doc_id;

  -- Se não for gerar título, terminou aqui
  if not p_gerar_titulo then
    return v_doc_id;
  end if;

  -- CLASSIFICAÇÃO OBRIGATÓRIA daqui pra frente
  if p_plano_contas_id is null then
    raise exception 'Classificação (Plano de Contas) é obrigatória para gerar o título.';
  end if;

  if p_vencimento_date is null then
    raise exception 'Vencimento é obrigatório para gerar o título.';
  end if;

  -- Título (Contas a Pagar = tipo AP)
  insert into f.titulo (
    tenant_id,
    empresa_id,
    tipo,
    status,
    origem,
    fornecedor_id,
    documento_fiscal_id,
    descricao,
    emissao_date,
    competencia_date,
    valor_total,
    valor_aberto
  ) values (
    p_tenant_id,
    p_empresa_id,
    'AP',
    'PENDENTE',
    'XML',
    v_fornecedor_id,
    v_doc_id,
    concat('NF-e ', coalesce(p_numero,''), '/', coalesce(p_serie,'')),
    p_emissao_date,
    p_competencia_date,
    coalesce(p_valor_total,0),
    coalesce(p_valor_total,0)
  )
  returning id into v_titulo_id;

  -- Parcela única
  insert into f.titulo_parcela (
    tenant_id,
    titulo_id,
    numero,
    vencimento_date,
    valor,
    status
  ) values (
    p_tenant_id,
    v_titulo_id,
    1,
    p_vencimento_date,
    coalesce(p_valor_total,0),
    'ABERTA'
  );

  -- Rateio (classificação / plano de contas)
  insert into f.titulo_rateio (
    tenant_id,
    empresa_id,
    titulo_id,
    plano_contas_id,
    centro_custo_id,
    os_id,
    valor
  ) values (
    p_tenant_id,
    p_empresa_id,
    v_titulo_id,
    p_plano_contas_id,
    p_centro_custo_id,
    p_os_id,
    coalesce(p_valor_total,0)
  );

  return v_doc_id;
end $$;


--
-- Name: jwt_claim(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jwt_claim(claim text) RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select (current_setting('request.jwt.claims', true)::json ->> claim);
$$;


--
-- Name: jwt_empresa_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jwt_empresa_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select nullif(public.jwt_claim('empresa_id'), '')::uuid;
$$;


--
-- Name: jwt_tenant_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jwt_tenant_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select nullif(public.jwt_claim('tenant_id'), '')::uuid;
$$;


--
-- Name: list_user_empresas(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_user_empresas(p_tenant_id text) RETURNS TABLE(id bigint, nome text, nome_fantasia text, razao_social text, ativo boolean, criado_em timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    e.id,
    e.nome,
    e.nome_fantasia,
    e.razao_social,
    e.ativo,
    e.criado_em
  FROM empresas e
  INNER JOIN empresa_memberships em ON e.id = em.empresa_id
  WHERE em.tenant_id = p_tenant_id::BIGINT
    AND em.user_id = auth.uid()
    AND em.status = 'active'
    AND e.tenant_id = p_tenant_id::BIGINT
  ORDER BY e.criado_em ASC;
END;
$$;


--
-- Name: list_user_empresas(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_user_empresas(p_tenant_id uuid) RETURNS TABLE(id uuid, nome text, ativo boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT
    e.id,
    COALESCE(e.nome_fantasia, e.razao_social, 'Empresa '||e.id::text) AS nome,
    e.ativo
  FROM public.empresas e
  WHERE e.tenant_id = p_tenant_id
    AND e.ativo = true
    AND EXISTS (
      -- User must be an active member of the tenant
      SELECT 1
      FROM public.tenant_memberships tm
      WHERE tm.user_id = auth.uid()
        AND tm.tenant_id = p_tenant_id
        AND tm.status = 'active'
    )
  ORDER BY e.criado_em ASC;
$$;


--
-- Name: merge_fornecedores(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.merge_fornecedores(p_keep_id integer, p_kill_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $_$
begin
  if p_keep_id = p_kill_id then
    return;
  end if;

  -- Atualiza referências em f.titulo (contas a pagar)
  if to_regclass('f.titulo') is not null then
    execute '
      update f.titulo
         set fornecedor_id = $1
       where fornecedor_id = $2
    ' using p_keep_id, p_kill_id;
  end if;

  -- Se existirem outras tabelas com fornecedor_id, adicione aqui seguindo o mesmo padrão:
  -- if to_regclass('public.alguma_tabela') is not null then
  --   execute 'update public.alguma_tabela set fornecedor_id=$1 where fornecedor_id=$2'
  --   using p_keep_id, p_kill_id;
  -- end if;

  -- Apaga o duplicado
  delete from public.fornecedores
   where id = p_kill_id;

end;
$_$;


--
-- Name: merge_fornecedores(bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.merge_fornecedores(p_keep_fornecedor_id bigint, p_merge_fornecedor_id bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
  if p_keep_fornecedor_id = p_merge_fornecedor_id then
    raise exception 'keep e merge não podem ser iguais';
  end if;

  -- exemplos: ajuste conforme seu schema
  update public.contas_pagar_titulos
     set fornecedor_id = p_keep_fornecedor_id
   where fornecedor_id = p_merge_fornecedor_id;

  update public.contas_pagar_parcelas
     set fornecedor_id = p_keep_fornecedor_id
   where fornecedor_id = p_merge_fornecedor_id;

  -- se tiver NF entrada / compras etc, adicione aqui:
  -- update public.nf_entrada set fornecedor_id = p_keep_fornecedor_id where fornecedor_id = p_merge_fornecedor_id;

  delete from public.fornecedores
   where id = p_merge_fornecedor_id;
end;
$$;


--
-- Name: normalize_cnpj(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.normalize_cnpj(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select regexp_replace(coalesce(p,''), '\D', '', 'g');
$$;


--
-- Name: normalize_doc(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.normalize_doc(doc text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select nullif(regexp_replace(coalesce(doc,''), '[^0-9]', '', 'g'), '');
$$;


--
-- Name: pick_fiscal_regra(text, text, text, text, text, smallint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pick_fiscal_regra(p_ncm text, p_cfop text, p_cst_icms text, p_cst_pis text, p_cst_cofins text, p_origem smallint, p_tipo_item text) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select r.id
  from public.fiscal_regras r
  where r.tenant_id = public.current_tenant_id()
    and r.empresa_id = public.current_empresa_id()
    and r.ativo = true

    -- "match" com coringas (null = aceita qualquer)
    and (r.ncm is null or r.ncm = p_ncm)
    and (r.cfop is null or r.cfop = p_cfop)
    and (r.cst_icms is null or r.cst_icms = p_cst_icms)
    and (r.cst_pis is null or r.cst_pis = p_cst_pis)
    and (r.cst_cofins is null or r.cst_cofins = p_cst_cofins)
    and (r.origem is null or r.origem = p_origem)
    and (r.tipo_item is null or r.tipo_item = p_tipo_item)

  order by
    -- 1) prioridade explícita
    r.prioridade asc,

    -- 2) mais específico ganha (quanto mais campos preenchidos, menor "score")
    (
      (case when r.ncm is null then 1 else 0 end) +
      (case when r.cfop is null then 1 else 0 end) +
      (case when r.cst_icms is null then 1 else 0 end) +
      (case when r.cst_pis is null then 1 else 0 end) +
      (case when r.cst_cofins is null then 1 else 0 end) +
      (case when r.origem is null then 1 else 0 end) +
      (case when r.tipo_item is null then 1 else 0 end)
    ) asc,

    r.atualizado_em desc
  limit 1;
$$;


--
-- Name: pick_fiscal_regra_admin(uuid, uuid, text, text, text, text, text, smallint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pick_fiscal_regra_admin(p_tenant uuid, p_empresa uuid, p_ncm text, p_cfop text, p_cst_icms text, p_cst_pis text, p_cst_cofins text, p_origem smallint, p_tipo_item text) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select r.id
  from public.fiscal_regras r
  where r.tenant_id  = p_tenant
    and r.empresa_id = p_empresa
    and r.ativo = true

    and (r.ncm is null or r.ncm = p_ncm)
    and (r.cfop is null or r.cfop = p_cfop)
    and (r.cst_icms is null or r.cst_icms = p_cst_icms)
    and (r.cst_pis is null or r.cst_pis = p_cst_pis)
    and (r.cst_cofins is null or r.cst_cofins = p_cst_cofins)
    and (r.origem is null or r.origem = p_origem)
    and (r.tipo_item is null or r.tipo_item = p_tipo_item)

  order by
    coalesce(r.prioridade, 0) desc,
    r.atualizado_em desc
  limit 1;
$$;


--
-- Name: remove_os_item_reverte_estoque(integer, text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.remove_os_item_reverte_estoque(p_os_item_id integer, p_realizado_por text DEFAULT NULL::text, p_motivo text DEFAULT NULL::text, p_empresa_id uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_tenant uuid;
  v_empresa uuid;
  v_realizado_por text;
  v_item public.itens;
  v_row public.os_itens;
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Tenant atual nao definido';
  end if;

  if not public.can('os_rpcs','execute') then
    raise exception 'Sem permissao para executar operacao de OS';
  end if;

  v_empresa := coalesce(p_empresa_id, public.current_empresa_id());
  if v_empresa is null then
    raise exception 'Empresa atual nao definida. Informe p_empresa_id na chamada da RPC.';
  end if;

  perform public.set_current_empresa(v_empresa);

  v_realizado_por := coalesce(p_realizado_por, auth.uid()::text);

  select *
    into v_row
  from public.os_itens
  where id = p_os_item_id
    and tenant_id = v_tenant;

  if not found then
    raise exception 'Item da OS nao encontrado';
  end if;

  select *
    into v_item
  from public.itens
  where id = v_row.item_id
    and tenant_id = v_tenant;

  if not found then
    raise exception 'Item invalido ou fora do tenant atual';
  end if;

  delete from public.os_itens
  where id = p_os_item_id
    and tenant_id = v_tenant;

  if coalesce(v_row.baixa_estoque, false)
     and v_item.tipo = 'produto'
     and coalesce(v_item.controla_estoque, false) = true
  then
    if not (public.can('estoque','write') or public.can('os_rpcs','execute')) then
      raise exception 'Sem permissao para movimentar estoque';
    end if;

    insert into public.movimentacoes (
      tenant_id,
      empresa_id,
      item_id,
      tipo,
      quantidade,
      motivo,
      realizado_por,
      data_movimentacao,
      origem_os_id,
      created_at
    )
    values (
      v_tenant,
      v_empresa,
      v_row.item_id,
      'entrada',
      v_row.quantidade,
      coalesce(p_motivo, 'Estorno baixa OS ' || v_row.os_id),
      v_realizado_por,
      now(),
      v_row.os_id,
      now()
    );
  end if;

  update public.ordens_servico os
  set valor_total = coalesce((
        select sum(oi.valor_total)
        from public.os_itens oi
        where oi.os_id = v_row.os_id
          and oi.tenant_id = v_tenant
      ), 0),
      atualizado_em = now()
  where os.id = v_row.os_id
    and os.tenant_id = v_tenant;
end;
$$;


--
-- Name: set_current_empresa(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_current_empresa(p_empresa_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_tenant uuid;
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;
  if p_empresa_id is null then
    raise exception 'Empresa nao informada';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Tenant atual nao definido';
  end if;

  if not exists (
    select 1
    from public.empresas e
    where e.id = p_empresa_id
      and e.tenant_id = v_tenant
      and e.ativo = true
  ) then
    raise exception 'Empresa invalida/inativa para este tenant';
  end if;

  if not exists (
    select 1
    from public.empresa_memberships em
    where em.tenant_id = v_tenant
      and em.empresa_id = p_empresa_id
      and em.user_id = auth.uid()
      and em.status = 'active'
  ) then
    raise exception 'Sem acesso a esta empresa';
  end if;

  insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
  values (auth.uid(), v_tenant, p_empresa_id)
  on conflict (user_id, tenant_id) do update
    set empresa_id = excluded.empresa_id,
        updated_at = now();

  perform set_config('app.current_empresa_id', p_empresa_id::text, true);
end;
$$;


--
-- Name: set_current_tenant(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_current_tenant(p_tenant_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  if p_tenant_id is null then
    raise exception 'tenant_id nao informado';
  end if;

  if not (
    exists (
      select 1
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = p_tenant_id
        and tm.status = 'active'
    )
    or
    exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut on ut.usuario_id = u.id
      where u.auth_user_id = auth.uid()
        and u.deleted_at is null
        and ut.deleted_at is null
        and ut.ativo = true
        and ut.tenant_id = p_tenant_id
    )
  ) then
    raise exception 'Usuário não é membro ativo deste tenant';
  end if;

  insert into public.user_tenant_context (user_id, tenant_id)
  values (auth.uid(), p_tenant_id)
  on conflict (user_id) do update
    set tenant_id = excluded.tenant_id,
        updated_at = now();
end
$$;


--
-- Name: set_fornecedor_import_defaults(integer, public.item_finalidade, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_fornecedor_import_defaults(p_fornecedor_id integer, p_finalidade public.item_finalidade, p_motivo_compra_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'a', 'f'
    SET row_security TO 'off'
    AS $$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
  v_ok boolean;
begin
  -- Permissão: ADMIN do tenant OU papéis da empresa (os que importam)
  select (
    exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut on ut.usuario_id = u.id
      where u.auth_user_id = auth.uid()
        and ut.tenant_id = v_tenant
        and ut.deleted_at is null
        and ut.ativo = true
        and ut.papel in ('OWNER','ADMIN')
    )
    or
    exists (
      select 1
      from a.usuario u
      join a.usuario_empresa ue on ue.usuario_id = u.id
      where u.auth_user_id = auth.uid()
        and ue.empresa_id = v_empresa
        and ue.deleted_at is null
        and ue.ativo = true
        and ue.papel in ('ADMIN','FINANCEIRO','COORDENACAO','COMPRAS','ALMOXARIFADO','APONTAMENTO_RH')
    )
  ) into v_ok;

  if not v_ok then
    raise exception 'Sem permissão para alterar defaults de importação do fornecedor.';
  end if;

  -- Valida fornecedor no tenant/empresa do contexto
  if not exists (
    select 1
    from public.fornecedores f
    where f.id = p_fornecedor_id
      and f.tenant_id = v_tenant
      and f.empresa_id = v_empresa
  ) then
    raise exception 'Fornecedor inválido para o contexto atual.';
  end if;

  -- Valida motivo (se informado): mesmo tenant + ativo + não deletado
  if p_motivo_compra_id is not null then
    if not exists (
      select 1
      from f.motivo_compra mc
      where mc.id = p_motivo_compra_id
        and mc.tenant_id = v_tenant
        and mc.deleted_at is null
        and mc.ativo = true
        -- IMPORTAÇÃO XML (produtos): bloquear motivo de SERVIÇO
        and (
          -- se você já criou aplica_em:
          (mc.aplica_em in ('PRODUTO','AMBOS'))
        )
    ) then
      raise exception 'Motivo inválido (ou não permitido para importação de produtos).';
    end if;
  end if;

  update public.fornecedores
  set
    finalidade_padrao = p_finalidade,
    motivo_compra_padrao_id = p_motivo_compra_id,
    atualizado_em = now()
  where id = p_fornecedor_id
    and tenant_id = v_tenant
    and empresa_id = v_empresa;
end;
$$;


--
-- Name: set_fornecedor_import_defaults(bigint, public.item_finalidade, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_fornecedor_import_defaults(p_fornecedor_id bigint, p_finalidade public.item_finalidade, p_motivo_compra_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    SET row_security TO 'off'
    AS $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Usuario nao autenticado';
  end if;

  select f.tenant_id, f.empresa_id
    into v_tenant_id, v_empresa_id
  from public.fornecedores f
  where f.id = p_fornecedor_id
  limit 1;

  if v_tenant_id is null or v_empresa_id is null then
    raise exception 'Fornecedor nao encontrado';
  end if;

  -- Ensure the caller belongs to the same tenant/empresa.
  if not exists (
    select 1
    from public.tenant_memberships tm
    where tm.user_id = auth.uid()
      and tm.tenant_id = v_tenant_id
      and tm.status = 'active'
  ) then
    raise exception 'Tenant nao autorizado';
  end if;

  if not exists (
    select 1
    from public.empresa_memberships em
    where em.user_id = auth.uid()
      and em.empresa_id = v_empresa_id
      and em.status = 'active'
  ) then
    raise exception 'Empresa nao autorizada';
  end if;

  -- Best-effort: set context so public.can(...) evaluates consistently.
  begin
    perform public.set_current_tenant(v_tenant_id);
  exception
    when undefined_function then
      null;
  end;

  begin
    perform public.set_current_empresa(v_empresa_id);
  exception
    when undefined_function then
      null;
  end;

  if not (
    public.can('xml_import','execute')
    or public.can('cad_fornecedores','write')
    or public.can('estoque','write')
  ) then
    raise exception 'Sem permissao.';
  end if;

  -- Optional validation: if f.motivo_compra exists, ensure the chosen motivo belongs to the same tenant.
  if p_motivo_compra_id is not null and to_regclass('f.motivo_compra') is not null then
    if not exists (
      select 1
      from f.motivo_compra m
      where m.id = p_motivo_compra_id
        and m.tenant_id = v_tenant_id
        and m.ativo = true
        and m.deleted_at is null
    ) then
      raise exception 'Motivo invalido para este tenant.';
    end if;
  end if;

  update public.fornecedores f
  set finalidade_padrao = p_finalidade,
      motivo_compra_padrao_id = p_motivo_compra_id,
      atualizado_em = now()
  where f.id = p_fornecedor_id;
end;
$$;


--
-- Name: set_tenant_id_colaborador_cliente_funcao(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_tenant_id_colaborador_cliente_funcao() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  -- Se tenant_id nÃ£o foi fornecido ou Ã© NULL, pega do contexto
  IF NEW.tenant_id IS NULL THEN
    NEW.tenant_id := public.current_tenant_id();
  END IF;
  
  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION set_tenant_id_colaborador_cliente_funcao(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.set_tenant_id_colaborador_cliente_funcao() IS 'Trigger function: preenche automaticamente tenant_id no INSERT de colaborador_cliente_funcao';


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


--
-- Name: trg_block_nf_movimentacoes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_block_nf_movimentacoes() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  -- Bloqueia alterações/deleções de movimentos originados de NF
  if (coalesce(old.origem_nf_entrada_id, new.origem_nf_entrada_id) is not null) then
    raise exception 'Movimentação originada de NF não pode ser alterada/excluída. Use estorno.';
  end if;

  return new;
end;
$$;


--
-- Name: update_cliente_hh_servicos_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_cliente_hh_servicos_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.atualizado_em = NOW();
  RETURN NEW;
END;
$$;


--
-- Name: update_colaborador_cliente_funcao_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_colaborador_cliente_funcao_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.atualizado_em = now();
  RETURN NEW;
END;
$$;


--
-- Name: update_timestamp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.atualizado_em = NOW();
  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION update_timestamp(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.update_timestamp() IS 'Trigger function para atualizar campo atualizado_em automaticamente';


--
-- Name: validate_apontamento_colaborador_contrato(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_apontamento_colaborador_contrato() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_tenant_id uuid;
  v_cliente_id bigint;
  v_vinculo_exists boolean;
  v_usa_relatorio_hh boolean;
  v_os_num bigint;
  v_numero_os varchar;
begin
  v_tenant_id := new.tenant_id;

  -- Busca dados da OS (inclui o flag de HH)
  select
    os.cliente_id,
    os.usa_relatorio_hh,
    os.os_num,
    os.numero_os
  into
    v_cliente_id,
    v_usa_relatorio_hh,
    v_os_num,
    v_numero_os
  from public.ordens_servico os
  where os.id = new.os_id
    and os.tenant_id = v_tenant_id;

  -- Se não encontrou a OS, ou não é HH, NÃO valida vínculo (apontamento "normal")
  if v_usa_relatorio_hh is distinct from true then
    return new;
  end if;

  -- Se a OS não tem cliente_id, permite (validação opcional)
  if v_cliente_id is null then
    return new;
  end if;

  -- Verifica vínculo ativo do colaborador com o cliente
  select exists (
    select 1
    from public.colaborador_cliente_funcao
    where tenant_id = v_tenant_id
      and cliente_id = v_cliente_id
      and colaborador_id = new.colaborador_id
      and ativo = true
  ) into v_vinculo_exists;

  if not v_vinculo_exists then
    raise exception
      'Colaborador % não está vinculado ao contrato do cliente da OS % (id %). Cadastre o vínculo em Cadastros > Colaboradores × Cliente.',
      new.colaborador_id,
      coalesce(v_os_num::text, v_numero_os::text, new.os_id::text),
      new.os_id
      using errcode = '23503';
  end if;

  return new;
end;
$$;


--
-- Name: FUNCTION validate_apontamento_colaborador_contrato(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.validate_apontamento_colaborador_contrato() IS 'Valida vínculo do colaborador com o contrato do cliente SOMENTE quando a OS está em HH (usa_relatorio_hh=true).';


--
-- Name: validate_hh_lancamento(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_hh_lancamento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_cliente_id bigint;
  v_servico_id bigint;
  v_ok_vinculo boolean;
  v_perc integer;
  v_preco numeric;
BEGIN
  -- 1) Percentual aplicado
  v_perc := COALESCE(NEW.percentual_aplicado, 0);

  -- 2) Se não há hh_servico_id, não validar vínculo (deixar RLS validar)
  IF NEW.hh_servico_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- 3) Obter cliente_id da OS
  SELECT os.cliente_id
    INTO v_cliente_id
  FROM public.ordens_servico os
  WHERE os.id = NEW.os_id
    AND os.tenant_id = NEW.tenant_id
  LIMIT 1;

  IF v_cliente_id IS NULL THEN
    RAISE EXCEPTION 'OS % sem cliente vinculado (cliente_id).', NEW.os_id;
  END IF;

  -- 4) CRÍTICO: Usar hh_servico_id, NÃO hh_tipo_id!
  v_servico_id := NEW.hh_servico_id;

  IF v_servico_id IS NULL OR v_servico_id <= 0 THEN
    RAISE EXCEPTION 'Serviço HH inválido no lançamento (hh_servico_id=%).', NEW.hh_servico_id;
  END IF;

  -- 5) Validar vínculo
  SELECT EXISTS (
    SELECT 1
    FROM public.colaborador_cliente_funcao ccf
    WHERE ccf.tenant_id = NEW.tenant_id
      AND ccf.cliente_id = v_cliente_id
      AND ccf.colaborador_id = NEW.colaborador_id
      AND ccf.hh_servico_id = v_servico_id
      AND COALESCE(ccf.ativo, true) = true
  )
  INTO v_ok_vinculo;

  IF NOT v_ok_vinculo THEN
    RAISE EXCEPTION
      'Serviço HH % não está vinculado ao colaborador % para o cliente % (colaborador_cliente_funcao).',
      v_servico_id, NEW.colaborador_id, v_cliente_id;
  END IF;

  -- 6) Buscar e atualizar preço
  SELECT
    CASE
      WHEN v_perc = 0   THEN s.preco_base
      WHEN v_perc = 50  THEN s.preco_50
      WHEN v_perc = 100 THEN s.preco_100
      ELSE NULL
    END
  INTO v_preco
  FROM public.cliente_hh_servicos s
  WHERE s.tenant_id = NEW.tenant_id
    AND s.empresa_id = NEW.empresa_id
    AND s.cliente_id = v_cliente_id
    AND s.id = v_servico_id
    AND s.ativo = true
  LIMIT 1;

  IF v_preco IS NOT NULL THEN
    NEW.valor_hora := v_preco;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: apply_rls(jsonb, integer); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer DEFAULT (1024 * 1024)) RETURNS SETOF realtime.wal_rls
    LANGUAGE plpgsql
    AS $$
declare
-- Regclass of the table e.g. public.notes
entity_ regclass = (quote_ident(wal ->> 'schema') || '.' || quote_ident(wal ->> 'table'))::regclass;

-- I, U, D, T: insert, update ...
action realtime.action = (
    case wal ->> 'action'
        when 'I' then 'INSERT'
        when 'U' then 'UPDATE'
        when 'D' then 'DELETE'
        else 'ERROR'
    end
);

-- Is row level security enabled for the table
is_rls_enabled bool = relrowsecurity from pg_class where oid = entity_;

subscriptions realtime.subscription[] = array_agg(subs)
    from
        realtime.subscription subs
    where
        subs.entity = entity_;

-- Subscription vars
roles regrole[] = array_agg(distinct us.claims_role::text)
    from
        unnest(subscriptions) us;

working_role regrole;
claimed_role regrole;
claims jsonb;

subscription_id uuid;
subscription_has_access bool;
visible_to_subscription_ids uuid[] = '{}';

-- structured info for wal's columns
columns realtime.wal_column[];
-- previous identity values for update/delete
old_columns realtime.wal_column[];

error_record_exceeds_max_size boolean = octet_length(wal::text) > max_record_bytes;

-- Primary jsonb output for record
output jsonb;

begin
perform set_config('role', null, true);

columns =
    array_agg(
        (
            x->>'name',
            x->>'type',
            x->>'typeoid',
            realtime.cast(
                (x->'value') #>> '{}',
                coalesce(
                    (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                    (x->>'type')::regtype
                )
            ),
            (pks ->> 'name') is not null,
            true
        )::realtime.wal_column
    )
    from
        jsonb_array_elements(wal -> 'columns') x
        left join jsonb_array_elements(wal -> 'pk') pks
            on (x ->> 'name') = (pks ->> 'name');

old_columns =
    array_agg(
        (
            x->>'name',
            x->>'type',
            x->>'typeoid',
            realtime.cast(
                (x->'value') #>> '{}',
                coalesce(
                    (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                    (x->>'type')::regtype
                )
            ),
            (pks ->> 'name') is not null,
            true
        )::realtime.wal_column
    )
    from
        jsonb_array_elements(wal -> 'identity') x
        left join jsonb_array_elements(wal -> 'pk') pks
            on (x ->> 'name') = (pks ->> 'name');

for working_role in select * from unnest(roles) loop

    -- Update `is_selectable` for columns and old_columns
    columns =
        array_agg(
            (
                c.name,
                c.type_name,
                c.type_oid,
                c.value,
                c.is_pkey,
                pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
            )::realtime.wal_column
        )
        from
            unnest(columns) c;

    old_columns =
            array_agg(
                (
                    c.name,
                    c.type_name,
                    c.type_oid,
                    c.value,
                    c.is_pkey,
                    pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
                )::realtime.wal_column
            )
            from
                unnest(old_columns) c;

    if action <> 'DELETE' and count(1) = 0 from unnest(columns) c where c.is_pkey then
        return next (
            jsonb_build_object(
                'schema', wal ->> 'schema',
                'table', wal ->> 'table',
                'type', action
            ),
            is_rls_enabled,
            -- subscriptions is already filtered by entity
            (select array_agg(s.subscription_id) from unnest(subscriptions) as s where claims_role = working_role),
            array['Error 400: Bad Request, no primary key']
        )::realtime.wal_rls;

    -- The claims role does not have SELECT permission to the primary key of entity
    elsif action <> 'DELETE' and sum(c.is_selectable::int) <> count(1) from unnest(columns) c where c.is_pkey then
        return next (
            jsonb_build_object(
                'schema', wal ->> 'schema',
                'table', wal ->> 'table',
                'type', action
            ),
            is_rls_enabled,
            (select array_agg(s.subscription_id) from unnest(subscriptions) as s where claims_role = working_role),
            array['Error 401: Unauthorized']
        )::realtime.wal_rls;

    else
        output = jsonb_build_object(
            'schema', wal ->> 'schema',
            'table', wal ->> 'table',
            'type', action,
            'commit_timestamp', to_char(
                ((wal ->> 'timestamp')::timestamptz at time zone 'utc'),
                'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
            ),
            'columns', (
                select
                    jsonb_agg(
                        jsonb_build_object(
                            'name', pa.attname,
                            'type', pt.typname
                        )
                        order by pa.attnum asc
                    )
                from
                    pg_attribute pa
                    join pg_type pt
                        on pa.atttypid = pt.oid
                where
                    attrelid = entity_
                    and attnum > 0
                    and pg_catalog.has_column_privilege(working_role, entity_, pa.attname, 'SELECT')
            )
        )
        -- Add "record" key for insert and update
        || case
            when action in ('INSERT', 'UPDATE') then
                jsonb_build_object(
                    'record',
                    (
                        select
                            jsonb_object_agg(
                                -- if unchanged toast, get column name and value from old record
                                coalesce((c).name, (oc).name),
                                case
                                    when (c).name is null then (oc).value
                                    else (c).value
                                end
                            )
                        from
                            unnest(columns) c
                            full outer join unnest(old_columns) oc
                                on (c).name = (oc).name
                        where
                            coalesce((c).is_selectable, (oc).is_selectable)
                            and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                    )
                )
            else '{}'::jsonb
        end
        -- Add "old_record" key for update and delete
        || case
            when action = 'UPDATE' then
                jsonb_build_object(
                        'old_record',
                        (
                            select jsonb_object_agg((c).name, (c).value)
                            from unnest(old_columns) c
                            where
                                (c).is_selectable
                                and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                        )
                    )
            when action = 'DELETE' then
                jsonb_build_object(
                    'old_record',
                    (
                        select jsonb_object_agg((c).name, (c).value)
                        from unnest(old_columns) c
                        where
                            (c).is_selectable
                            and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                            and ( not is_rls_enabled or (c).is_pkey ) -- if RLS enabled, we can't secure deletes so filter to pkey
                    )
                )
            else '{}'::jsonb
        end;

        -- Create the prepared statement
        if is_rls_enabled and action <> 'DELETE' then
            if (select 1 from pg_prepared_statements where name = 'walrus_rls_stmt' limit 1) > 0 then
                deallocate walrus_rls_stmt;
            end if;
            execute realtime.build_prepared_statement_sql('walrus_rls_stmt', entity_, columns);
        end if;

        visible_to_subscription_ids = '{}';

        for subscription_id, claims in (
                select
                    subs.subscription_id,
                    subs.claims
                from
                    unnest(subscriptions) subs
                where
                    subs.entity = entity_
                    and subs.claims_role = working_role
                    and (
                        realtime.is_visible_through_filters(columns, subs.filters)
                        or (
                          action = 'DELETE'
                          and realtime.is_visible_through_filters(old_columns, subs.filters)
                        )
                    )
        ) loop

            if not is_rls_enabled or action = 'DELETE' then
                visible_to_subscription_ids = visible_to_subscription_ids || subscription_id;
            else
                -- Check if RLS allows the role to see the record
                perform
                    -- Trim leading and trailing quotes from working_role because set_config
                    -- doesn't recognize the role as valid if they are included
                    set_config('role', trim(both '"' from working_role::text), true),
                    set_config('request.jwt.claims', claims::text, true);

                execute 'execute walrus_rls_stmt' into subscription_has_access;

                if subscription_has_access then
                    visible_to_subscription_ids = visible_to_subscription_ids || subscription_id;
                end if;
            end if;
        end loop;

        perform set_config('role', null, true);

        return next (
            output,
            is_rls_enabled,
            visible_to_subscription_ids,
            case
                when error_record_exceeds_max_size then array['Error 413: Payload Too Large']
                else '{}'
            end
        )::realtime.wal_rls;

    end if;
end loop;

perform set_config('role', null, true);
end;
$$;


--
-- Name: broadcast_changes(text, text, text, text, text, record, record, text); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text DEFAULT 'ROW'::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    -- Declare a variable to hold the JSONB representation of the row
    row_data jsonb := '{}'::jsonb;
BEGIN
    IF level = 'STATEMENT' THEN
        RAISE EXCEPTION 'function can only be triggered for each row, not for each statement';
    END IF;
    -- Check the operation type and handle accordingly
    IF operation = 'INSERT' OR operation = 'UPDATE' OR operation = 'DELETE' THEN
        row_data := jsonb_build_object('old_record', OLD, 'record', NEW, 'operation', operation, 'table', table_name, 'schema', table_schema);
        PERFORM realtime.send (row_data, event_name, topic_name);
    ELSE
        RAISE EXCEPTION 'Unexpected operation type: %', operation;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to process the row: %', SQLERRM;
END;

$$;


--
-- Name: build_prepared_statement_sql(text, regclass, realtime.wal_column[]); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) RETURNS text
    LANGUAGE sql
    AS $$
      /*
      Builds a sql string that, if executed, creates a prepared statement to
      tests retrive a row from *entity* by its primary key columns.
      Example
          select realtime.build_prepared_statement_sql('public.notes', '{"id"}'::text[], '{"bigint"}'::text[])
      */
          select
      'prepare ' || prepared_statement_name || ' as
          select
              exists(
                  select
                      1
                  from
                      ' || entity || '
                  where
                      ' || string_agg(quote_ident(pkc.name) || '=' || quote_nullable(pkc.value #>> '{}') , ' and ') || '
              )'
          from
              unnest(columns) pkc
          where
              pkc.is_pkey
          group by
              entity
      $$;


--
-- Name: cast(text, regtype); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime."cast"(val text, type_ regtype) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
    declare
      res jsonb;
    begin
      execute format('select to_jsonb(%L::'|| type_::text || ')', val)  into res;
      return res;
    end
    $$;


--
-- Name: check_equality_op(realtime.equality_op, regtype, text, text); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
      /*
      Casts *val_1* and *val_2* as type *type_* and check the *op* condition for truthiness
      */
      declare
          op_symbol text = (
              case
                  when op = 'eq' then '='
                  when op = 'neq' then '!='
                  when op = 'lt' then '<'
                  when op = 'lte' then '<='
                  when op = 'gt' then '>'
                  when op = 'gte' then '>='
                  when op = 'in' then '= any'
                  else 'UNKNOWN OP'
              end
          );
          res boolean;
      begin
          execute format(
              'select %L::'|| type_::text || ' ' || op_symbol
              || ' ( %L::'
              || (
                  case
                      when op = 'in' then type_::text || '[]'
                      else type_::text end
              )
              || ')', val_1, val_2) into res;
          return res;
      end;
      $$;


--
-- Name: is_visible_through_filters(realtime.wal_column[], realtime.user_defined_filter[]); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
    /*
    Should the record be visible (true) or filtered out (false) after *filters* are applied
    */
        select
            -- Default to allowed when no filters present
            $2 is null -- no filters. this should not happen because subscriptions has a default
            or array_length($2, 1) is null -- array length of an empty array is null
            or bool_and(
                coalesce(
                    realtime.check_equality_op(
                        op:=f.op,
                        type_:=coalesce(
                            col.type_oid::regtype, -- null when wal2json version <= 2.4
                            col.type_name::regtype
                        ),
                        -- cast jsonb to text
                        val_1:=col.value #>> '{}',
                        val_2:=f.value
                    ),
                    false -- if null, filter does not match
                )
            )
        from
            unnest(filters) f
            join unnest(columns) col
                on f.column_name = col.name;
    $_$;


--
-- Name: list_changes(name, name, integer, integer); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) RETURNS SETOF realtime.wal_rls
    LANGUAGE sql
    SET log_min_messages TO 'fatal'
    AS $$
      with pub as (
        select
          concat_ws(
            ',',
            case when bool_or(pubinsert) then 'insert' else null end,
            case when bool_or(pubupdate) then 'update' else null end,
            case when bool_or(pubdelete) then 'delete' else null end
          ) as w2j_actions,
          coalesce(
            string_agg(
              realtime.quote_wal2json(format('%I.%I', schemaname, tablename)::regclass),
              ','
            ) filter (where ppt.tablename is not null and ppt.tablename not like '% %'),
            ''
          ) w2j_add_tables
        from
          pg_publication pp
          left join pg_publication_tables ppt
            on pp.pubname = ppt.pubname
        where
          pp.pubname = publication
        group by
          pp.pubname
        limit 1
      ),
      w2j as (
        select
          x.*, pub.w2j_add_tables
        from
          pub,
          pg_logical_slot_get_changes(
            slot_name, null, max_changes,
            'include-pk', 'true',
            'include-transaction', 'false',
            'include-timestamp', 'true',
            'include-type-oids', 'true',
            'format-version', '2',
            'actions', pub.w2j_actions,
            'add-tables', pub.w2j_add_tables
          ) x
      )
      select
        xyz.wal,
        xyz.is_rls_enabled,
        xyz.subscription_ids,
        xyz.errors
      from
        w2j,
        realtime.apply_rls(
          wal := w2j.data::jsonb,
          max_record_bytes := max_record_bytes
        ) xyz(wal, is_rls_enabled, subscription_ids, errors)
      where
        w2j.w2j_add_tables <> ''
        and xyz.subscription_ids[1] is not null
    $$;


--
-- Name: quote_wal2json(regclass); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.quote_wal2json(entity regclass) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
      select
        (
          select string_agg('' || ch,'')
          from unnest(string_to_array(nsp.nspname::text, null)) with ordinality x(ch, idx)
          where
            not (x.idx = 1 and x.ch = '"')
            and not (
              x.idx = array_length(string_to_array(nsp.nspname::text, null), 1)
              and x.ch = '"'
            )
        )
        || '.'
        || (
          select string_agg('' || ch,'')
          from unnest(string_to_array(pc.relname::text, null)) with ordinality x(ch, idx)
          where
            not (x.idx = 1 and x.ch = '"')
            and not (
              x.idx = array_length(string_to_array(nsp.nspname::text, null), 1)
              and x.ch = '"'
            )
          )
      from
        pg_class pc
        join pg_namespace nsp
          on pc.relnamespace = nsp.oid
      where
        pc.oid = entity
    $$;


--
-- Name: send(jsonb, text, text, boolean); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  generated_id uuid;
  final_payload jsonb;
BEGIN
  BEGIN
    -- Generate a new UUID for the id
    generated_id := gen_random_uuid();

    -- Check if payload has an 'id' key, if not, add the generated UUID
    IF payload ? 'id' THEN
      final_payload := payload;
    ELSE
      final_payload := jsonb_set(payload, '{id}', to_jsonb(generated_id));
    END IF;

    -- Set the topic configuration
    EXECUTE format('SET LOCAL realtime.topic TO %L', topic);

    -- Attempt to insert the message
    INSERT INTO realtime.messages (id, payload, event, topic, private, extension)
    VALUES (generated_id, final_payload, event, topic, private, 'broadcast');
  EXCEPTION
    WHEN OTHERS THEN
      -- Capture and notify the error
      RAISE WARNING 'ErrorSendingBroadcastMessage: %', SQLERRM;
  END;
END;
$$;


--
-- Name: subscription_check_filters(); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.subscription_check_filters() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    /*
    Validates that the user defined filters for a subscription:
    - refer to valid columns that the claimed role may access
    - values are coercable to the correct column type
    */
    declare
        col_names text[] = coalesce(
                array_agg(c.column_name order by c.ordinal_position),
                '{}'::text[]
            )
            from
                information_schema.columns c
            where
                format('%I.%I', c.table_schema, c.table_name)::regclass = new.entity
                and pg_catalog.has_column_privilege(
                    (new.claims ->> 'role'),
                    format('%I.%I', c.table_schema, c.table_name)::regclass,
                    c.column_name,
                    'SELECT'
                );
        filter realtime.user_defined_filter;
        col_type regtype;

        in_val jsonb;
    begin
        for filter in select * from unnest(new.filters) loop
            -- Filtered column is valid
            if not filter.column_name = any(col_names) then
                raise exception 'invalid column for filter %', filter.column_name;
            end if;

            -- Type is sanitized and safe for string interpolation
            col_type = (
                select atttypid::regtype
                from pg_catalog.pg_attribute
                where attrelid = new.entity
                      and attname = filter.column_name
            );
            if col_type is null then
                raise exception 'failed to lookup type for column %', filter.column_name;
            end if;

            -- Set maximum number of entries for in filter
            if filter.op = 'in'::realtime.equality_op then
                in_val = realtime.cast(filter.value, (col_type::text || '[]')::regtype);
                if coalesce(jsonb_array_length(in_val), 0) > 100 then
                    raise exception 'too many values for `in` filter. Maximum 100';
                end if;
            else
                -- raises an exception if value is not coercable to type
                perform realtime.cast(filter.value, col_type);
            end if;

        end loop;

        -- Apply consistent order to filters so the unique constraint on
        -- (subscription_id, entity, filters) can't be tricked by a different filter order
        new.filters = coalesce(
            array_agg(f order by f.column_name, f.op, f.value),
            '{}'
        ) from unnest(new.filters) f;

        return new;
    end;
    $$;


--
-- Name: to_regrole(text); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.to_regrole(role_name text) RETURNS regrole
    LANGUAGE sql IMMUTABLE
    AS $$ select role_name::regrole $$;


--
-- Name: topic(); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.topic() RETURNS text
    LANGUAGE sql STABLE
    AS $$
select nullif(current_setting('realtime.topic', true), '')::text;
$$;


--
-- Name: add_prefixes(text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.add_prefixes(_bucket_id text, _name text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    prefixes text[];
BEGIN
    prefixes := "storage"."get_prefixes"("_name");

    IF array_length(prefixes, 1) > 0 THEN
        INSERT INTO storage.prefixes (name, bucket_id)
        SELECT UNNEST(prefixes) as name, "_bucket_id" ON CONFLICT DO NOTHING;
    END IF;
END;
$$;


--
-- Name: can_insert_object(text, text, uuid, jsonb); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


--
-- Name: delete_leaf_prefixes(text[], text[]); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.delete_leaf_prefixes(bucket_ids text[], names text[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_rows_deleted integer;
BEGIN
    LOOP
        WITH candidates AS (
            SELECT DISTINCT
                t.bucket_id,
                unnest(storage.get_prefixes(t.name)) AS name
            FROM unnest(bucket_ids, names) AS t(bucket_id, name)
        ),
        uniq AS (
             SELECT
                 bucket_id,
                 name,
                 storage.get_level(name) AS level
             FROM candidates
             WHERE name <> ''
             GROUP BY bucket_id, name
        ),
        leaf AS (
             SELECT
                 p.bucket_id,
                 p.name,
                 p.level
             FROM storage.prefixes AS p
                  JOIN uniq AS u
                       ON u.bucket_id = p.bucket_id
                           AND u.name = p.name
                           AND u.level = p.level
             WHERE NOT EXISTS (
                 SELECT 1
                 FROM storage.objects AS o
                 WHERE o.bucket_id = p.bucket_id
                   AND o.level = p.level + 1
                   AND o.name COLLATE "C" LIKE p.name || '/%'
             )
             AND NOT EXISTS (
                 SELECT 1
                 FROM storage.prefixes AS c
                 WHERE c.bucket_id = p.bucket_id
                   AND c.level = p.level + 1
                   AND c.name COLLATE "C" LIKE p.name || '/%'
             )
        )
        DELETE
        FROM storage.prefixes AS p
            USING leaf AS l
        WHERE p.bucket_id = l.bucket_id
          AND p.name = l.name
          AND p.level = l.level;

        GET DIAGNOSTICS v_rows_deleted = ROW_COUNT;
        EXIT WHEN v_rows_deleted = 0;
    END LOOP;
END;
$$;


--
-- Name: delete_prefix(text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.delete_prefix(_bucket_id text, _name text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    -- Check if we can delete the prefix
    IF EXISTS(
        SELECT FROM "storage"."prefixes"
        WHERE "prefixes"."bucket_id" = "_bucket_id"
          AND level = "storage"."get_level"("_name") + 1
          AND "prefixes"."name" COLLATE "C" LIKE "_name" || '/%'
        LIMIT 1
    )
    OR EXISTS(
        SELECT FROM "storage"."objects"
        WHERE "objects"."bucket_id" = "_bucket_id"
          AND "storage"."get_level"("objects"."name") = "storage"."get_level"("_name") + 1
          AND "objects"."name" COLLATE "C" LIKE "_name" || '/%'
        LIMIT 1
    ) THEN
    -- There are sub-objects, skip deletion
    RETURN false;
    ELSE
        DELETE FROM "storage"."prefixes"
        WHERE "prefixes"."bucket_id" = "_bucket_id"
          AND level = "storage"."get_level"("_name")
          AND "prefixes"."name" = "_name";
        RETURN true;
    END IF;
END;
$$;


--
-- Name: delete_prefix_hierarchy_trigger(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.delete_prefix_hierarchy_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    prefix text;
BEGIN
    prefix := "storage"."get_prefix"(OLD."name");

    IF coalesce(prefix, '') != '' THEN
        PERFORM "storage"."delete_prefix"(OLD."bucket_id", prefix);
    END IF;

    RETURN OLD;
END;
$$;


--
-- Name: enforce_bucket_name_length(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.enforce_bucket_name_length() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name "%" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$$;


--
-- Name: extension(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.extension(name text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    SELECT _parts[array_length(_parts,1)] INTO _filename;
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$$;


--
-- Name: filename(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.filename(name text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[array_length(_parts,1)];
END
$$;


--
-- Name: foldername(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.foldername(name text) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$$;


--
-- Name: get_level(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_level(name text) RETURNS integer
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
SELECT array_length(string_to_array("name", '/'), 1);
$$;


--
-- Name: get_prefix(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_prefix(name text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT
    CASE WHEN strpos("name", '/') > 0 THEN
             regexp_replace("name", '[\/]{1}[^\/]+\/?$', '')
         ELSE
             ''
        END;
$_$;


--
-- Name: get_prefixes(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_prefixes(name text) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
DECLARE
    parts text[];
    prefixes text[];
    prefix text;
BEGIN
    -- Split the name into parts by '/'
    parts := string_to_array("name", '/');
    prefixes := '{}';

    -- Construct the prefixes, stopping one level below the last part
    FOR i IN 1..array_length(parts, 1) - 1 LOOP
            prefix := array_to_string(parts[1:i], '/');
            prefixes := array_append(prefixes, prefix);
    END LOOP;

    RETURN prefixes;
END;
$$;


--
-- Name: get_size_by_bucket(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_size_by_bucket() RETURNS TABLE(size bigint, bucket_id text)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    return query
        select sum((metadata->>'size')::bigint) as size, obj.bucket_id
        from "storage".objects as obj
        group by obj.bucket_id;
END
$$;


--
-- Name: list_multipart_uploads_with_delimiter(text, text, text, integer, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, next_key_token text DEFAULT ''::text, next_upload_token text DEFAULT ''::text) RETURNS TABLE(key text, id text, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(key COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                        substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1)))
                    ELSE
                        key
                END AS key, id, created_at
            FROM
                storage.s3_multipart_uploads
            WHERE
                bucket_id = $5 AND
                key ILIKE $1 || ''%'' AND
                CASE
                    WHEN $4 != '''' AND $6 = '''' THEN
                        CASE
                            WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                                substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                key COLLATE "C" > $4
                            END
                    ELSE
                        true
                END AND
                CASE
                    WHEN $6 != '''' THEN
                        id COLLATE "C" > $6
                    ELSE
                        true
                    END
            ORDER BY
                key COLLATE "C" ASC, created_at ASC) as e order by key COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_key_token, bucket_id, next_upload_token;
END;
$_$;


--
-- Name: list_objects_with_delimiter(text, text, text, integer, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.list_objects_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, start_after text DEFAULT ''::text, next_token text DEFAULT ''::text) RETURNS TABLE(name text, id uuid, metadata jsonb, updated_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(name COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(name from length($1) + 1)) > 0 THEN
                        substring(name from 1 for length($1) + position($2 IN substring(name from length($1) + 1)))
                    ELSE
                        name
                END AS name, id, metadata, updated_at
            FROM
                storage.objects
            WHERE
                bucket_id = $5 AND
                name ILIKE $1 || ''%'' AND
                CASE
                    WHEN $6 != '''' THEN
                    name COLLATE "C" > $6
                ELSE true END
                AND CASE
                    WHEN $4 != '''' THEN
                        CASE
                            WHEN position($2 IN substring(name from length($1) + 1)) > 0 THEN
                                substring(name from 1 for length($1) + position($2 IN substring(name from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                name COLLATE "C" > $4
                            END
                    ELSE
                        true
                END
            ORDER BY
                name COLLATE "C" ASC) as e order by name COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_token, bucket_id, start_after;
END;
$_$;


--
-- Name: lock_top_prefixes(text[], text[]); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.lock_top_prefixes(bucket_ids text[], names text[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_bucket text;
    v_top text;
BEGIN
    FOR v_bucket, v_top IN
        SELECT DISTINCT t.bucket_id,
            split_part(t.name, '/', 1) AS top
        FROM unnest(bucket_ids, names) AS t(bucket_id, name)
        WHERE t.name <> ''
        ORDER BY 1, 2
        LOOP
            PERFORM pg_advisory_xact_lock(hashtextextended(v_bucket || '/' || v_top, 0));
        END LOOP;
END;
$$;


--
-- Name: objects_delete_cleanup(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.objects_delete_cleanup() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_bucket_ids text[];
    v_names      text[];
BEGIN
    IF current_setting('storage.gc.prefixes', true) = '1' THEN
        RETURN NULL;
    END IF;

    PERFORM set_config('storage.gc.prefixes', '1', true);

    SELECT COALESCE(array_agg(d.bucket_id), '{}'),
           COALESCE(array_agg(d.name), '{}')
    INTO v_bucket_ids, v_names
    FROM deleted AS d
    WHERE d.name <> '';

    PERFORM storage.lock_top_prefixes(v_bucket_ids, v_names);
    PERFORM storage.delete_leaf_prefixes(v_bucket_ids, v_names);

    RETURN NULL;
END;
$$;


--
-- Name: objects_insert_prefix_trigger(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.objects_insert_prefix_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM "storage"."add_prefixes"(NEW."bucket_id", NEW."name");
    NEW.level := "storage"."get_level"(NEW."name");

    RETURN NEW;
END;
$$;


--
-- Name: objects_update_cleanup(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.objects_update_cleanup() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    -- NEW - OLD (destinations to create prefixes for)
    v_add_bucket_ids text[];
    v_add_names      text[];

    -- OLD - NEW (sources to prune)
    v_src_bucket_ids text[];
    v_src_names      text[];
BEGIN
    IF TG_OP <> 'UPDATE' THEN
        RETURN NULL;
    END IF;

    -- 1) Compute NEW−OLD (added paths) and OLD−NEW (moved-away paths)
    WITH added AS (
        SELECT n.bucket_id, n.name
        FROM new_rows n
        WHERE n.name <> '' AND position('/' in n.name) > 0
        EXCEPT
        SELECT o.bucket_id, o.name FROM old_rows o WHERE o.name <> ''
    ),
    moved AS (
         SELECT o.bucket_id, o.name
         FROM old_rows o
         WHERE o.name <> ''
         EXCEPT
         SELECT n.bucket_id, n.name FROM new_rows n WHERE n.name <> ''
    )
    SELECT
        -- arrays for ADDED (dest) in stable order
        COALESCE( (SELECT array_agg(a.bucket_id ORDER BY a.bucket_id, a.name) FROM added a), '{}' ),
        COALESCE( (SELECT array_agg(a.name      ORDER BY a.bucket_id, a.name) FROM added a), '{}' ),
        -- arrays for MOVED (src) in stable order
        COALESCE( (SELECT array_agg(m.bucket_id ORDER BY m.bucket_id, m.name) FROM moved m), '{}' ),
        COALESCE( (SELECT array_agg(m.name      ORDER BY m.bucket_id, m.name) FROM moved m), '{}' )
    INTO v_add_bucket_ids, v_add_names, v_src_bucket_ids, v_src_names;

    -- Nothing to do?
    IF (array_length(v_add_bucket_ids, 1) IS NULL) AND (array_length(v_src_bucket_ids, 1) IS NULL) THEN
        RETURN NULL;
    END IF;

    -- 2) Take per-(bucket, top) locks: ALL prefixes in consistent global order to prevent deadlocks
    DECLARE
        v_all_bucket_ids text[];
        v_all_names text[];
    BEGIN
        -- Combine source and destination arrays for consistent lock ordering
        v_all_bucket_ids := COALESCE(v_src_bucket_ids, '{}') || COALESCE(v_add_bucket_ids, '{}');
        v_all_names := COALESCE(v_src_names, '{}') || COALESCE(v_add_names, '{}');

        -- Single lock call ensures consistent global ordering across all transactions
        IF array_length(v_all_bucket_ids, 1) IS NOT NULL THEN
            PERFORM storage.lock_top_prefixes(v_all_bucket_ids, v_all_names);
        END IF;
    END;

    -- 3) Create destination prefixes (NEW−OLD) BEFORE pruning sources
    IF array_length(v_add_bucket_ids, 1) IS NOT NULL THEN
        WITH candidates AS (
            SELECT DISTINCT t.bucket_id, unnest(storage.get_prefixes(t.name)) AS name
            FROM unnest(v_add_bucket_ids, v_add_names) AS t(bucket_id, name)
            WHERE name <> ''
        )
        INSERT INTO storage.prefixes (bucket_id, name)
        SELECT c.bucket_id, c.name
        FROM candidates c
        ON CONFLICT DO NOTHING;
    END IF;

    -- 4) Prune source prefixes bottom-up for OLD−NEW
    IF array_length(v_src_bucket_ids, 1) IS NOT NULL THEN
        -- re-entrancy guard so DELETE on prefixes won't recurse
        IF current_setting('storage.gc.prefixes', true) <> '1' THEN
            PERFORM set_config('storage.gc.prefixes', '1', true);
        END IF;

        PERFORM storage.delete_leaf_prefixes(v_src_bucket_ids, v_src_names);
    END IF;

    RETURN NULL;
END;
$$;


--
-- Name: objects_update_level_trigger(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.objects_update_level_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Ensure this is an update operation and the name has changed
    IF TG_OP = 'UPDATE' AND (NEW."name" <> OLD."name" OR NEW."bucket_id" <> OLD."bucket_id") THEN
        -- Set the new level
        NEW."level" := "storage"."get_level"(NEW."name");
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: objects_update_prefix_trigger(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.objects_update_prefix_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    old_prefixes TEXT[];
BEGIN
    -- Ensure this is an update operation and the name has changed
    IF TG_OP = 'UPDATE' AND (NEW."name" <> OLD."name" OR NEW."bucket_id" <> OLD."bucket_id") THEN
        -- Retrieve old prefixes
        old_prefixes := "storage"."get_prefixes"(OLD."name");

        -- Remove old prefixes that are only used by this object
        WITH all_prefixes as (
            SELECT unnest(old_prefixes) as prefix
        ),
        can_delete_prefixes as (
             SELECT prefix
             FROM all_prefixes
             WHERE NOT EXISTS (
                 SELECT 1 FROM "storage"."objects"
                 WHERE "bucket_id" = OLD."bucket_id"
                   AND "name" <> OLD."name"
                   AND "name" LIKE (prefix || '%')
             )
         )
        DELETE FROM "storage"."prefixes" WHERE name IN (SELECT prefix FROM can_delete_prefixes);

        -- Add new prefixes
        PERFORM "storage"."add_prefixes"(NEW."bucket_id", NEW."name");
    END IF;
    -- Set the new level
    NEW."level" := "storage"."get_level"(NEW."name");

    RETURN NEW;
END;
$$;


--
-- Name: operation(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.operation() RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


--
-- Name: prefixes_delete_cleanup(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.prefixes_delete_cleanup() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_bucket_ids text[];
    v_names      text[];
BEGIN
    IF current_setting('storage.gc.prefixes', true) = '1' THEN
        RETURN NULL;
    END IF;

    PERFORM set_config('storage.gc.prefixes', '1', true);

    SELECT COALESCE(array_agg(d.bucket_id), '{}'),
           COALESCE(array_agg(d.name), '{}')
    INTO v_bucket_ids, v_names
    FROM deleted AS d
    WHERE d.name <> '';

    PERFORM storage.lock_top_prefixes(v_bucket_ids, v_names);
    PERFORM storage.delete_leaf_prefixes(v_bucket_ids, v_names);

    RETURN NULL;
END;
$$;


--
-- Name: prefixes_insert_trigger(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.prefixes_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM "storage"."add_prefixes"(NEW."bucket_id", NEW."name");
    RETURN NEW;
END;
$$;


--
-- Name: search(text, text, integer, integer, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql
    AS $$
declare
    can_bypass_rls BOOLEAN;
begin
    SELECT rolbypassrls
    INTO can_bypass_rls
    FROM pg_roles
    WHERE rolname = coalesce(nullif(current_setting('role', true), 'none'), current_user);

    IF can_bypass_rls THEN
        RETURN QUERY SELECT * FROM storage.search_v1_optimised(prefix, bucketname, limits, levels, offsets, search, sortcolumn, sortorder);
    ELSE
        RETURN QUERY SELECT * FROM storage.search_legacy_v1(prefix, bucketname, limits, levels, offsets, search, sortcolumn, sortorder);
    END IF;
end;
$$;


--
-- Name: search_legacy_v1(text, text, integer, integer, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search_legacy_v1(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
declare
    v_order_by text;
    v_sort_order text;
begin
    case
        when sortcolumn = 'name' then
            v_order_by = 'name';
        when sortcolumn = 'updated_at' then
            v_order_by = 'updated_at';
        when sortcolumn = 'created_at' then
            v_order_by = 'created_at';
        when sortcolumn = 'last_accessed_at' then
            v_order_by = 'last_accessed_at';
        else
            v_order_by = 'name';
        end case;

    case
        when sortorder = 'asc' then
            v_sort_order = 'asc';
        when sortorder = 'desc' then
            v_sort_order = 'desc';
        else
            v_sort_order = 'asc';
        end case;

    v_order_by = v_order_by || ' ' || v_sort_order;

    return query execute
        'with folders as (
           select path_tokens[$1] as folder
           from storage.objects
             where objects.name ilike $2 || $3 || ''%''
               and bucket_id = $4
               and array_length(objects.path_tokens, 1) <> $1
           group by folder
           order by folder ' || v_sort_order || '
     )
     (select folder as "name",
            null as id,
            null as updated_at,
            null as created_at,
            null as last_accessed_at,
            null as metadata from folders)
     union all
     (select path_tokens[$1] as "name",
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
     from storage.objects
     where objects.name ilike $2 || $3 || ''%''
       and bucket_id = $4
       and array_length(objects.path_tokens, 1) = $1
     order by ' || v_order_by || ')
     limit $5
     offset $6' using levels, prefix, search, bucketname, limits, offsets;
end;
$_$;


--
-- Name: search_v1_optimised(text, text, integer, integer, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search_v1_optimised(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
declare
    v_order_by text;
    v_sort_order text;
begin
    case
        when sortcolumn = 'name' then
            v_order_by = 'name';
        when sortcolumn = 'updated_at' then
            v_order_by = 'updated_at';
        when sortcolumn = 'created_at' then
            v_order_by = 'created_at';
        when sortcolumn = 'last_accessed_at' then
            v_order_by = 'last_accessed_at';
        else
            v_order_by = 'name';
        end case;

    case
        when sortorder = 'asc' then
            v_sort_order = 'asc';
        when sortorder = 'desc' then
            v_sort_order = 'desc';
        else
            v_sort_order = 'asc';
        end case;

    v_order_by = v_order_by || ' ' || v_sort_order;

    return query execute
        'with folders as (
           select (string_to_array(name, ''/''))[level] as name
           from storage.prefixes
             where lower(prefixes.name) like lower($2 || $3) || ''%''
               and bucket_id = $4
               and level = $1
           order by name ' || v_sort_order || '
     )
     (select name,
            null as id,
            null as updated_at,
            null as created_at,
            null as last_accessed_at,
            null as metadata from folders)
     union all
     (select path_tokens[level] as "name",
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
     from storage.objects
     where lower(objects.name) like lower($2 || $3) || ''%''
       and bucket_id = $4
       and level = $1
     order by ' || v_order_by || ')
     limit $5
     offset $6' using levels, prefix, search, bucketname, limits, offsets;
end;
$_$;


--
-- Name: search_v2(text, text, integer, integer, text, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search_v2(prefix text, bucket_name text, limits integer DEFAULT 100, levels integer DEFAULT 1, start_after text DEFAULT ''::text, sort_order text DEFAULT 'asc'::text, sort_column text DEFAULT 'name'::text, sort_column_after text DEFAULT ''::text) RETURNS TABLE(key text, name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    sort_col text;
    sort_ord text;
    cursor_op text;
    cursor_expr text;
    sort_expr text;
BEGIN
    -- Validate sort_order
    sort_ord := lower(sort_order);
    IF sort_ord NOT IN ('asc', 'desc') THEN
        sort_ord := 'asc';
    END IF;

    -- Determine cursor comparison operator
    IF sort_ord = 'asc' THEN
        cursor_op := '>';
    ELSE
        cursor_op := '<';
    END IF;
    
    sort_col := lower(sort_column);
    -- Validate sort column  
    IF sort_col IN ('updated_at', 'created_at') THEN
        cursor_expr := format(
            '($5 = '''' OR ROW(date_trunc(''milliseconds'', %I), name COLLATE "C") %s ROW(COALESCE(NULLIF($6, '''')::timestamptz, ''epoch''::timestamptz), $5))',
            sort_col, cursor_op
        );
        sort_expr := format(
            'COALESCE(date_trunc(''milliseconds'', %I), ''epoch''::timestamptz) %s, name COLLATE "C" %s',
            sort_col, sort_ord, sort_ord
        );
    ELSE
        cursor_expr := format('($5 = '''' OR name COLLATE "C" %s $5)', cursor_op);
        sort_expr := format('name COLLATE "C" %s', sort_ord);
    END IF;

    RETURN QUERY EXECUTE format(
        $sql$
        SELECT * FROM (
            (
                SELECT
                    split_part(name, '/', $4) AS key,
                    name,
                    NULL::uuid AS id,
                    updated_at,
                    created_at,
                    NULL::timestamptz AS last_accessed_at,
                    NULL::jsonb AS metadata
                FROM storage.prefixes
                WHERE name COLLATE "C" LIKE $1 || '%%'
                    AND bucket_id = $2
                    AND level = $4
                    AND %s
                ORDER BY %s
                LIMIT $3
            )
            UNION ALL
            (
                SELECT
                    split_part(name, '/', $4) AS key,
                    name,
                    id,
                    updated_at,
                    created_at,
                    last_accessed_at,
                    metadata
                FROM storage.objects
                WHERE name COLLATE "C" LIKE $1 || '%%'
                    AND bucket_id = $2
                    AND level = $4
                    AND %s
                ORDER BY %s
                LIMIT $3
            )
        ) obj
        ORDER BY %s
        LIMIT $3
        $sql$,
        cursor_expr,    -- prefixes WHERE
        sort_expr,      -- prefixes ORDER BY
        cursor_expr,    -- objects WHERE
        sort_expr,      -- objects ORDER BY
        sort_expr       -- final ORDER BY
    )
    USING prefix, bucket_name, limits, levels, start_after, sort_column_after;
END;
$_$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


--
-- Name: usuario; Type: TABLE; Schema: a; Owner: -
--

CREATE TABLE a.usuario (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    auth_user_id uuid NOT NULL,
    nome text NOT NULL,
    email text NOT NULL,
    telefone text,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_usuario__email_lower CHECK ((email = lower(email))),
    CONSTRAINT ck_usuario__telefone_digits CHECK (((telefone IS NULL) OR (telefone ~ '^[0-9]+$'::text)))
);


--
-- Name: usuario_empresa; Type: TABLE; Schema: a; Owner: -
--

CREATE TABLE a.usuario_empresa (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    usuario_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    papel text NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    permissoes_extra jsonb,
    permissoes_negadas jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_usuario_empresa__papel CHECK ((papel = ANY (ARRAY['ADMIN'::text, 'FINANCEIRO'::text, 'COORDENACAO'::text, 'COMPRAS'::text, 'ALMOXARIFADO'::text, 'TECNICO'::text, 'APONTAMENTO_RH'::text, 'PAINEL_TV'::text])))
);


--
-- Name: usuario_tenant; Type: TABLE; Schema: a; Owner: -
--

CREATE TABLE a.usuario_tenant (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    usuario_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    papel text NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_usuario_tenant__papel CHECK ((papel = ANY (ARRAY['OWNER'::text, 'ADMIN'::text, 'CONTADOR'::text, 'GESTOR'::text])))
);


--
-- Name: audit_log_entries; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.audit_log_entries (
    instance_id uuid,
    id uuid NOT NULL,
    payload json,
    created_at timestamp with time zone,
    ip_address character varying(64) DEFAULT ''::character varying NOT NULL
);


--
-- Name: TABLE audit_log_entries; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.audit_log_entries IS 'Auth: Audit trail for user actions.';


--
-- Name: flow_state; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.flow_state (
    id uuid NOT NULL,
    user_id uuid,
    auth_code text NOT NULL,
    code_challenge_method auth.code_challenge_method NOT NULL,
    code_challenge text NOT NULL,
    provider_type text NOT NULL,
    provider_access_token text,
    provider_refresh_token text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    authentication_method text NOT NULL,
    auth_code_issued_at timestamp with time zone
);


--
-- Name: TABLE flow_state; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.flow_state IS 'stores metadata for pkce logins';


--
-- Name: identities; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.identities (
    provider_id text NOT NULL,
    user_id uuid NOT NULL,
    identity_data jsonb NOT NULL,
    provider text NOT NULL,
    last_sign_in_at timestamp with time zone,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    email text GENERATED ALWAYS AS (lower((identity_data ->> 'email'::text))) STORED,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: TABLE identities; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.identities IS 'Auth: Stores identities associated to a user.';


--
-- Name: COLUMN identities.email; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.identities.email IS 'Auth: Email is a generated column that references the optional email property in the identity_data';


--
-- Name: instances; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.instances (
    id uuid NOT NULL,
    uuid uuid,
    raw_base_config text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);


--
-- Name: TABLE instances; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.instances IS 'Auth: Manages users across multiple sites.';


--
-- Name: mfa_amr_claims; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.mfa_amr_claims (
    session_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    authentication_method text NOT NULL,
    id uuid NOT NULL
);


--
-- Name: TABLE mfa_amr_claims; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.mfa_amr_claims IS 'auth: stores authenticator method reference claims for multi factor authentication';


--
-- Name: mfa_challenges; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.mfa_challenges (
    id uuid NOT NULL,
    factor_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    verified_at timestamp with time zone,
    ip_address inet NOT NULL,
    otp_code text,
    web_authn_session_data jsonb
);


--
-- Name: TABLE mfa_challenges; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.mfa_challenges IS 'auth: stores metadata about challenge requests made';


--
-- Name: mfa_factors; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.mfa_factors (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    friendly_name text,
    factor_type auth.factor_type NOT NULL,
    status auth.factor_status NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    secret text,
    phone text,
    last_challenged_at timestamp with time zone,
    web_authn_credential jsonb,
    web_authn_aaguid uuid,
    last_webauthn_challenge_data jsonb
);


--
-- Name: TABLE mfa_factors; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.mfa_factors IS 'auth: stores metadata about factors';


--
-- Name: COLUMN mfa_factors.last_webauthn_challenge_data; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.mfa_factors.last_webauthn_challenge_data IS 'Stores the latest WebAuthn challenge data including attestation/assertion for customer verification';


--
-- Name: oauth_authorizations; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.oauth_authorizations (
    id uuid NOT NULL,
    authorization_id text NOT NULL,
    client_id uuid NOT NULL,
    user_id uuid,
    redirect_uri text NOT NULL,
    scope text NOT NULL,
    state text,
    resource text,
    code_challenge text,
    code_challenge_method auth.code_challenge_method,
    response_type auth.oauth_response_type DEFAULT 'code'::auth.oauth_response_type NOT NULL,
    status auth.oauth_authorization_status DEFAULT 'pending'::auth.oauth_authorization_status NOT NULL,
    authorization_code text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '00:03:00'::interval) NOT NULL,
    approved_at timestamp with time zone,
    nonce text,
    CONSTRAINT oauth_authorizations_authorization_code_length CHECK ((char_length(authorization_code) <= 255)),
    CONSTRAINT oauth_authorizations_code_challenge_length CHECK ((char_length(code_challenge) <= 128)),
    CONSTRAINT oauth_authorizations_expires_at_future CHECK ((expires_at > created_at)),
    CONSTRAINT oauth_authorizations_nonce_length CHECK ((char_length(nonce) <= 255)),
    CONSTRAINT oauth_authorizations_redirect_uri_length CHECK ((char_length(redirect_uri) <= 2048)),
    CONSTRAINT oauth_authorizations_resource_length CHECK ((char_length(resource) <= 2048)),
    CONSTRAINT oauth_authorizations_scope_length CHECK ((char_length(scope) <= 4096)),
    CONSTRAINT oauth_authorizations_state_length CHECK ((char_length(state) <= 4096))
);


--
-- Name: oauth_client_states; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.oauth_client_states (
    id uuid NOT NULL,
    provider_type text NOT NULL,
    code_verifier text,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: TABLE oauth_client_states; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.oauth_client_states IS 'Stores OAuth states for third-party provider authentication flows where Supabase acts as the OAuth client.';


--
-- Name: oauth_clients; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.oauth_clients (
    id uuid NOT NULL,
    client_secret_hash text,
    registration_type auth.oauth_registration_type NOT NULL,
    redirect_uris text NOT NULL,
    grant_types text NOT NULL,
    client_name text,
    client_uri text,
    logo_uri text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    client_type auth.oauth_client_type DEFAULT 'confidential'::auth.oauth_client_type NOT NULL,
    CONSTRAINT oauth_clients_client_name_length CHECK ((char_length(client_name) <= 1024)),
    CONSTRAINT oauth_clients_client_uri_length CHECK ((char_length(client_uri) <= 2048)),
    CONSTRAINT oauth_clients_logo_uri_length CHECK ((char_length(logo_uri) <= 2048))
);


--
-- Name: oauth_consents; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.oauth_consents (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    client_id uuid NOT NULL,
    scopes text NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    revoked_at timestamp with time zone,
    CONSTRAINT oauth_consents_revoked_after_granted CHECK (((revoked_at IS NULL) OR (revoked_at >= granted_at))),
    CONSTRAINT oauth_consents_scopes_length CHECK ((char_length(scopes) <= 2048)),
    CONSTRAINT oauth_consents_scopes_not_empty CHECK ((char_length(TRIM(BOTH FROM scopes)) > 0))
);


--
-- Name: one_time_tokens; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.one_time_tokens (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    token_type auth.one_time_token_type NOT NULL,
    token_hash text NOT NULL,
    relates_to text NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT one_time_tokens_token_hash_check CHECK ((char_length(token_hash) > 0))
);


--
-- Name: refresh_tokens; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.refresh_tokens (
    instance_id uuid,
    id bigint NOT NULL,
    token character varying(255),
    user_id character varying(255),
    revoked boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    parent character varying(255),
    session_id uuid
);


--
-- Name: TABLE refresh_tokens; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.refresh_tokens IS 'Auth: Store of tokens used to refresh JWT tokens once they expire.';


--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE; Schema: auth; Owner: -
--

CREATE SEQUENCE auth.refresh_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: auth; Owner: -
--

ALTER SEQUENCE auth.refresh_tokens_id_seq OWNED BY auth.refresh_tokens.id;


--
-- Name: saml_providers; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.saml_providers (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    entity_id text NOT NULL,
    metadata_xml text NOT NULL,
    metadata_url text,
    attribute_mapping jsonb,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    name_id_format text,
    CONSTRAINT "entity_id not empty" CHECK ((char_length(entity_id) > 0)),
    CONSTRAINT "metadata_url not empty" CHECK (((metadata_url = NULL::text) OR (char_length(metadata_url) > 0))),
    CONSTRAINT "metadata_xml not empty" CHECK ((char_length(metadata_xml) > 0))
);


--
-- Name: TABLE saml_providers; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.saml_providers IS 'Auth: Manages SAML Identity Provider connections.';


--
-- Name: saml_relay_states; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.saml_relay_states (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    request_id text NOT NULL,
    for_email text,
    redirect_to text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    flow_state_id uuid,
    CONSTRAINT "request_id not empty" CHECK ((char_length(request_id) > 0))
);


--
-- Name: TABLE saml_relay_states; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.saml_relay_states IS 'Auth: Contains SAML Relay State information for each Service Provider initiated login.';


--
-- Name: schema_migrations; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.schema_migrations (
    version character varying(255) NOT NULL
);


--
-- Name: TABLE schema_migrations; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.schema_migrations IS 'Auth: Manages updates to the auth system.';


--
-- Name: sessions; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.sessions (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    factor_id uuid,
    aal auth.aal_level,
    not_after timestamp with time zone,
    refreshed_at timestamp without time zone,
    user_agent text,
    ip inet,
    tag text,
    oauth_client_id uuid,
    refresh_token_hmac_key text,
    refresh_token_counter bigint,
    scopes text,
    CONSTRAINT sessions_scopes_length CHECK ((char_length(scopes) <= 4096))
);


--
-- Name: TABLE sessions; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.sessions IS 'Auth: Stores session data associated to a user.';


--
-- Name: COLUMN sessions.not_after; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.sessions.not_after IS 'Auth: Not after is a nullable column that contains a timestamp after which the session should be regarded as expired.';


--
-- Name: COLUMN sessions.refresh_token_hmac_key; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.sessions.refresh_token_hmac_key IS 'Holds a HMAC-SHA256 key used to sign refresh tokens for this session.';


--
-- Name: COLUMN sessions.refresh_token_counter; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.sessions.refresh_token_counter IS 'Holds the ID (counter) of the last issued refresh token.';


--
-- Name: sso_domains; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.sso_domains (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    domain text NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT "domain not empty" CHECK ((char_length(domain) > 0))
);


--
-- Name: TABLE sso_domains; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.sso_domains IS 'Auth: Manages SSO email address domain mapping to an SSO Identity Provider.';


--
-- Name: sso_providers; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.sso_providers (
    id uuid NOT NULL,
    resource_id text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    disabled boolean,
    CONSTRAINT "resource_id not empty" CHECK (((resource_id = NULL::text) OR (char_length(resource_id) > 0)))
);


--
-- Name: TABLE sso_providers; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.sso_providers IS 'Auth: Manages SSO identity provider information; see saml_providers for SAML.';


--
-- Name: COLUMN sso_providers.resource_id; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.sso_providers.resource_id IS 'Auth: Uniquely identifies a SSO provider according to a user-chosen resource ID (case insensitive), useful in infrastructure as code.';


--
-- Name: users; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.users (
    instance_id uuid,
    id uuid NOT NULL,
    aud character varying(255),
    role character varying(255),
    email character varying(255),
    encrypted_password character varying(255),
    email_confirmed_at timestamp with time zone,
    invited_at timestamp with time zone,
    confirmation_token character varying(255),
    confirmation_sent_at timestamp with time zone,
    recovery_token character varying(255),
    recovery_sent_at timestamp with time zone,
    email_change_token_new character varying(255),
    email_change character varying(255),
    email_change_sent_at timestamp with time zone,
    last_sign_in_at timestamp with time zone,
    raw_app_meta_data jsonb,
    raw_user_meta_data jsonb,
    is_super_admin boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    phone text DEFAULT NULL::character varying,
    phone_confirmed_at timestamp with time zone,
    phone_change text DEFAULT ''::character varying,
    phone_change_token character varying(255) DEFAULT ''::character varying,
    phone_change_sent_at timestamp with time zone,
    confirmed_at timestamp with time zone GENERATED ALWAYS AS (LEAST(email_confirmed_at, phone_confirmed_at)) STORED,
    email_change_token_current character varying(255) DEFAULT ''::character varying,
    email_change_confirm_status smallint DEFAULT 0,
    banned_until timestamp with time zone,
    reauthentication_token character varying(255) DEFAULT ''::character varying,
    reauthentication_sent_at timestamp with time zone,
    is_sso_user boolean DEFAULT false NOT NULL,
    deleted_at timestamp with time zone,
    is_anonymous boolean DEFAULT false NOT NULL,
    CONSTRAINT users_email_change_confirm_status_check CHECK (((email_change_confirm_status >= 0) AND (email_change_confirm_status <= 2)))
);


--
-- Name: TABLE users; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.users IS 'Auth: Stores user login data within a secure schema.';


--
-- Name: COLUMN users.is_sso_user; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.users.is_sso_user IS 'Auth: Set this column to true when the account comes from SSO. These accounts can have duplicate emails.';


--
-- Name: empresa; Type: TABLE; Schema: c; Owner: -
--

CREATE TABLE c.empresa (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    codigo text NOT NULL,
    razao_social text NOT NULL,
    nome_fantasia text NOT NULL,
    cnpj text,
    email text,
    telefone text,
    site text,
    observacao text,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_empresa__cnpj_digits CHECK (((cnpj IS NULL) OR (cnpj ~ '^[0-9]+$'::text))),
    CONSTRAINT ck_empresa__codigo_not_blank CHECK ((length(TRIM(BOTH FROM codigo)) > 0)),
    CONSTRAINT ck_empresa__email_lower CHECK (((email IS NULL) OR (email = lower(email)))),
    CONSTRAINT ck_empresa__site_lower CHECK (((site IS NULL) OR (site = lower(site)))),
    CONSTRAINT ck_empresa__telefone_digits CHECK (((telefone IS NULL) OR (telefone ~ '^[0-9]+$'::text)))
);


--
-- Name: empresa_endereco; Type: TABLE; Schema: c; Owner: -
--

CREATE TABLE c.empresa_endereco (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    tipo text NOT NULL,
    cep text NOT NULL,
    logradouro text NOT NULL,
    numero text NOT NULL,
    complemento text,
    bairro text NOT NULL,
    cidade text NOT NULL,
    uf character(2) NOT NULL,
    codigo_municipio_ibge text,
    pais character(2) DEFAULT 'BR'::bpchar NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_empresa_endereco__cep_digits CHECK ((cep ~ '^[0-9]+$'::text)),
    CONSTRAINT ck_empresa_endereco__ibge_digits CHECK (((codigo_municipio_ibge IS NULL) OR (codigo_municipio_ibge ~ '^[0-9]+$'::text))),
    CONSTRAINT ck_empresa_endereco__pais CHECK ((pais ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT ck_empresa_endereco__tipo CHECK ((tipo = ANY (ARRAY['FISCAL'::text, 'COBRANCA'::text, 'ENTREGA'::text, 'CORRESPONDENCIA'::text]))),
    CONSTRAINT ck_empresa_endereco__uf CHECK ((uf ~ '^[A-Z]{2}$'::text))
);


--
-- Name: empresa_fiscal; Type: TABLE; Schema: c; Owner: -
--

CREATE TABLE c.empresa_fiscal (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    ie_isento boolean DEFAULT false NOT NULL,
    inscricao_estadual text,
    inscricao_municipal text,
    cnae_principal text,
    regime_tributario text,
    crt smallint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_empresa_fiscal__cnae_digits CHECK (((cnae_principal IS NULL) OR (cnae_principal ~ '^[0-9]+$'::text))),
    CONSTRAINT ck_empresa_fiscal__crt_range CHECK (((crt IS NULL) OR ((crt >= 1) AND (crt <= 4)))),
    CONSTRAINT ck_empresa_fiscal__ie_digits CHECK (((inscricao_estadual IS NULL) OR (inscricao_estadual ~ '^[0-9]+$'::text))),
    CONSTRAINT ck_empresa_fiscal__ie_isento_regra CHECK ((((ie_isento = true) AND (inscricao_estadual IS NULL)) OR (ie_isento = false))),
    CONSTRAINT ck_empresa_fiscal__im_digits CHECK (((inscricao_municipal IS NULL) OR (inscricao_municipal ~ '^[0-9]+$'::text)))
);


--
-- Name: i_caixa; Type: TABLE; Schema: c; Owner: -
--

CREATE TABLE c.i_caixa (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    codigo text NOT NULL,
    nome text NOT NULL,
    status text DEFAULT 'DISPONIVEL'::text NOT NULL,
    localizacao text,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_i_caixa__status CHECK ((status = ANY (ARRAY['DISPONIVEL'::text, 'COM_COLABORADOR'::text, 'MANUTENCAO'::text, 'BAIXADA'::text])))
);


--
-- Name: i_caixa_item; Type: TABLE; Schema: c; Owner: -
--

CREATE TABLE c.i_caixa_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    caixa_id uuid NOT NULL,
    ferramenta_id uuid NOT NULL,
    quantidade numeric(15,2) DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- Name: i_caixa_vinculo; Type: TABLE; Schema: c; Owner: -
--

CREATE TABLE c.i_caixa_vinculo (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    caixa_id uuid NOT NULL,
    colaborador_id uuid NOT NULL,
    data_inicio timestamp with time zone DEFAULT now() NOT NULL,
    data_fim timestamp with time zone,
    observacao text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- Name: i_ferramenta; Type: TABLE; Schema: c; Owner: -
--

CREATE TABLE c.i_ferramenta (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    codigo text NOT NULL,
    nome text NOT NULL,
    ncm text,
    unidade text,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone,
    custo_unit numeric(15,2) DEFAULT 0 NOT NULL,
    custo_moeda character(3) DEFAULT 'BRL'::bpchar NOT NULL,
    custo_atualizado_em timestamp with time zone,
    categoria_id uuid
);


--
-- Name: i_ferramenta_categoria; Type: TABLE; Schema: c; Owner: -
--

CREATE TABLE c.i_ferramenta_categoria (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid DEFAULT public.current_tenant_id() NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    prefixo text NOT NULL,
    nome text NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);


--
-- Name: i_ferramenta_codigo_seq; Type: TABLE; Schema: c; Owner: -
--

CREATE TABLE c.i_ferramenta_codigo_seq (
    tenant_id uuid DEFAULT public.current_tenant_id() NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    categoria_id uuid NOT NULL,
    proximo_numero integer DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: i_ferramenta_sugestao_xml; Type: TABLE; Schema: c; Owner: -
--

CREATE TABLE c.i_ferramenta_sugestao_xml (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    chave_nfe text,
    nfe_numero text,
    item_numero integer,
    fornecedor_nome text,
    fornecedor_doc text,
    descricao_xml text NOT NULL,
    ncm text,
    unidade text,
    qtd numeric(15,2),
    valor_unit numeric(15,2),
    valor_total numeric(15,2),
    status text DEFAULT 'PENDENTE'::text NOT NULL,
    ferramenta_id uuid,
    payload jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_i_ferr_sug_xml__status CHECK ((status = ANY (ARRAY['PENDENTE'::text, 'VINCULADA'::text, 'CRIADA'::text, 'IGNORADA'::text])))
);


--
-- Name: i_ferramenta_unidade; Type: TABLE; Schema: c; Owner: -
--

CREATE TABLE c.i_ferramenta_unidade (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid DEFAULT public.current_tenant_id() NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    ferramenta_id uuid NOT NULL,
    patrimonio_codigo text NOT NULL,
    status text DEFAULT 'DISPONIVEL'::text NOT NULL,
    localizacao text,
    custo_aquisicao numeric(15,2) DEFAULT 0 NOT NULL,
    adquirido_em date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_i_ferr_unid__status CHECK ((status = ANY (ARRAY['DISPONIVEL'::text, 'COM_COLABORADOR'::text, 'MANUTENCAO'::text, 'BAIXADA'::text])))
);


--
-- Name: i_ferramenta_unidade_vinculo; Type: TABLE; Schema: c; Owner: -
--

CREATE TABLE c.i_ferramenta_unidade_vinculo (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid DEFAULT public.current_tenant_id() NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    ferramenta_unidade_id uuid NOT NULL,
    colaborador_id uuid NOT NULL,
    data_inicio timestamp with time zone DEFAULT now() NOT NULL,
    data_fim timestamp with time zone,
    observacao text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- Name: tenant; Type: TABLE; Schema: c; Owner: -
--

CREATE TABLE c.tenant (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    codigo text NOT NULL,
    nome text NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_tenant__codigo_not_blank CHECK ((length(TRIM(BOTH FROM codigo)) > 0)),
    CONSTRAINT ck_tenant__nome_not_blank CHECK ((length(TRIM(BOTH FROM nome)) > 0))
);


--
-- Name: anexo; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.anexo (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    ref_table text NOT NULL,
    ref_id uuid NOT NULL,
    arquivo_nome text NOT NULL,
    mime_type text,
    storage_path text NOT NULL,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL,
    uploaded_by uuid DEFAULT a.fn_current_usuario_id(),
    deleted_at timestamp with time zone
);


--
-- Name: aprovacao_evento; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.aprovacao_evento (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    acao text NOT NULL,
    ref_table text NOT NULL,
    ref_id uuid NOT NULL,
    motivo text,
    payload jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    CONSTRAINT ck_aprovacao_evento__acao CHECK ((acao = ANY (ARRAY['APROVOU'::text, 'REPROVOU'::text])))
);


--
-- Name: centro_custo; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.centro_custo (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    codigo text NOT NULL,
    nome text NOT NULL,
    parent_id uuid,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- Name: conciliacao_bancaria; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.conciliacao_bancaria (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    conta_bancaria_id uuid NOT NULL,
    referencia text,
    status text DEFAULT 'ABERTA'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    extrato_linha_id uuid,
    pagamento_id uuid,
    valor_conciliado numeric(15,2),
    diferenca numeric(15,2) DEFAULT 0,
    conciliado_em timestamp with time zone DEFAULT now(),
    conciliado_por uuid,
    observacoes text,
    change_reason text,
    updated_at timestamp with time zone DEFAULT now(),
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_conciliacao_bancaria__status CHECK ((status = ANY (ARRAY['CONCILIADO'::text, 'DESCONCILIADO'::text])))
);


--
-- Name: conciliacao_lancamento; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.conciliacao_lancamento (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    conciliacao_id uuid NOT NULL,
    data_lancamento date NOT NULL,
    descricao text NOT NULL,
    valor numeric(15,2) NOT NULL,
    pagamento_id uuid,
    conciliado_em timestamp with time zone,
    conciliado_por uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id()
);


--
-- Name: conta_bancaria; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.conta_bancaria (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    codigo text NOT NULL,
    nome text NOT NULL,
    tipo text DEFAULT 'BANCO'::text NOT NULL,
    banco text,
    agencia text,
    conta text,
    pix_chave text,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_conta_bancaria__tipo CHECK ((tipo = ANY (ARRAY['BANCO'::text, 'CAIXA'::text])))
);


--
-- Name: documento_fiscal; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.documento_fiscal (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    source_nf_entrada_id bigint,
    fornecedor_id integer,
    chave_acesso text NOT NULL,
    modelo text,
    serie text,
    numero text,
    emissao_date date,
    competencia_date date,
    valor_total numeric(15,2) DEFAULT 0 NOT NULL,
    valor_produtos numeric(15,2) DEFAULT 0 NOT NULL,
    valor_frete numeric(15,2) DEFAULT 0 NOT NULL,
    valor_desconto numeric(15,2) DEFAULT 0 NOT NULL,
    valor_outros numeric(15,2) DEFAULT 0 NOT NULL,
    valor_seguro numeric(15,2) DEFAULT 0 NOT NULL,
    finalidade_import public.item_finalidade,
    os_id_import integer,
    pagamento_import_json jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_documento_fiscal__competencia_day1 CHECK (((competencia_date IS NULL) OR (EXTRACT(day FROM competencia_date) = (1)::numeric)))
);


--
-- Name: documento_fiscal_xml; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.documento_fiscal_xml (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    documento_fiscal_id uuid NOT NULL,
    chave_acesso text NOT NULL,
    xml_raw text NOT NULL,
    xml_hash text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    deleted_at timestamp with time zone
);


--
-- Name: evento_financeiro; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.evento_financeiro (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    evento text NOT NULL,
    ref_table text,
    ref_id uuid,
    payload jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id()
);


--
-- Name: extrato_bancario; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.extrato_bancario (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    conta_bancaria_id uuid NOT NULL,
    fonte text DEFAULT 'MANUAL'::text NOT NULL,
    referencia text,
    periodo_inicio date,
    periodo_fim date,
    observacoes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_extrato_bancario__fonte CHECK ((fonte = ANY (ARRAY['MANUAL'::text, 'OFX'::text, 'CSV'::text, 'API'::text])))
);


--
-- Name: extrato_bancario_linha; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.extrato_bancario_linha (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    extrato_bancario_id uuid NOT NULL,
    conta_bancaria_id uuid NOT NULL,
    data_movimento date NOT NULL,
    descricao text,
    documento text,
    fit_id text,
    valor numeric(15,2) NOT NULL,
    status text DEFAULT 'PENDENTE'::text NOT NULL,
    observacoes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_extrato_linha__status CHECK ((status = ANY (ARRAY['PENDENTE'::text, 'CONCILIADO'::text, 'IGNORADO'::text])))
);


--
-- Name: fin_config; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.fin_config (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    conta_bancaria_padrao_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- Name: importacao_doc_log; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.importacao_doc_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    documento_fiscal_id uuid,
    origem text DEFAULT 'XML'::text NOT NULL,
    status text NOT NULL,
    mensagem text,
    payload jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    CONSTRAINT ck_importacao_doc_log__status CHECK ((status = ANY (ARRAY['SUCESSO'::text, 'ERRO'::text])))
);


--
-- Name: imposto_retencao; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.imposto_retencao (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    titulo_id uuid NOT NULL,
    documento_fiscal_id uuid,
    imposto text NOT NULL,
    base_calculo numeric(15,2) DEFAULT 0 NOT NULL,
    aliquota numeric(7,4) DEFAULT 0 NOT NULL,
    valor_calculado numeric(15,2) DEFAULT 0 NOT NULL,
    valor_ajustado numeric(15,2),
    vencimento_date date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- Name: motivo_compra; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.motivo_compra (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    codigo text NOT NULL,
    nome text NOT NULL,
    requires_text boolean DEFAULT false NOT NULL,
    requires_os boolean DEFAULT false NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone,
    aplica_em text DEFAULT 'PRODUTO'::text NOT NULL,
    CONSTRAINT ck_motivo_compra__aplica_em CHECK ((aplica_em = ANY (ARRAY['PRODUTO'::text, 'SERVICO'::text, 'AMBOS'::text])))
);


--
-- Name: pagamento; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.pagamento (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    conta_bancaria_id uuid NOT NULL,
    data_pagamento date NOT NULL,
    forma_pagamento text DEFAULT 'OUTROS'::text NOT NULL,
    valor numeric(15,2) NOT NULL,
    observacoes text,
    pago_por uuid DEFAULT a.fn_current_usuario_id(),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone,
    conciliado_at timestamp with time zone,
    conciliado_por uuid,
    CONSTRAINT ck_pagamento__forma CHECK ((forma_pagamento = ANY (ARRAY['PIX'::text, 'BOLETO'::text, 'TRANSFERENCIA'::text, 'DINHEIRO'::text, 'CARTAO'::text, 'OUTROS'::text]))),
    CONSTRAINT ck_pagamento__valor CHECK ((valor >= (0)::numeric))
);


--
-- Name: pagamento_item; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.pagamento_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    pagamento_id uuid NOT NULL,
    titulo_parcela_id uuid NOT NULL,
    valor numeric(15,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    deleted_at timestamp with time zone,
    CONSTRAINT ck_pagamento_item__valor CHECK ((valor >= (0)::numeric))
);


--
-- Name: parametro_financeiro_empresa; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.parametro_financeiro_empresa (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    conta_bancaria_padrao_id uuid,
    saldo_inicial numeric(15,2) DEFAULT 0 NOT NULL,
    data_saldo_inicial date DEFAULT CURRENT_DATE NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- Name: plano_contas; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.plano_contas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    codigo text NOT NULL,
    nome text NOT NULL,
    parent_id uuid,
    natureza text DEFAULT 'DEBITO'::text NOT NULL,
    tipo text DEFAULT 'ANALITICA'::text NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_plano_contas__natureza CHECK ((natureza = ANY (ARRAY['DEBITO'::text, 'CREDITO'::text]))),
    CONSTRAINT ck_plano_contas__tipo CHECK ((tipo = ANY (ARRAY['SINTETICA'::text, 'ANALITICA'::text])))
);


--
-- Name: titulo; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.titulo (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    tipo text NOT NULL,
    status text DEFAULT 'PENDENTE'::text NOT NULL,
    origem text DEFAULT 'XML'::text NOT NULL,
    fornecedor_id integer,
    cliente_id integer,
    documento_fiscal_id uuid,
    descricao text,
    emissao_date date,
    competencia_date date,
    valor_total numeric(15,2) DEFAULT 0 NOT NULL,
    valor_aberto numeric(15,2) DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone,
    motivo_compra_id uuid,
    classificacao_id bigint,
    CONSTRAINT ck_titulo__competencia_day1 CHECK (((competencia_date IS NULL) OR (EXTRACT(day FROM competencia_date) = (1)::numeric))),
    CONSTRAINT ck_titulo__status CHECK ((status = ANY (ARRAY['PENDENTE'::text, 'APROVADO'::text, 'AGENDADO'::text, 'PAGO'::text, 'CANCELADO'::text]))),
    CONSTRAINT ck_titulo__tipo CHECK ((tipo = ANY (ARRAY['AP'::text, 'AR'::text])))
);


--
-- Name: titulo_aprovacao; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.titulo_aprovacao (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    titulo_id uuid NOT NULL,
    motivo_compra_id uuid NOT NULL,
    motivo_outros_text text,
    os_id integer,
    aprovado_em timestamp with time zone DEFAULT now() NOT NULL,
    aprovado_por uuid DEFAULT a.fn_current_usuario_id() NOT NULL,
    change_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- Name: titulo_parcela; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.titulo_parcela (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    titulo_id uuid NOT NULL,
    numero text,
    vencimento_date date NOT NULL,
    valor numeric(15,2) NOT NULL,
    valor_aberto numeric(15,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_titulo_parcela__valor CHECK ((valor >= (0)::numeric)),
    CONSTRAINT ck_titulo_parcela__valor_aberto CHECK ((valor_aberto >= (0)::numeric))
);


--
-- Name: fornecedores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fornecedores (
    id integer NOT NULL,
    nome character varying(255) NOT NULL,
    documento character varying(20),
    email character varying(120),
    telefone character varying(30),
    endereco text,
    observacoes text,
    ativo boolean DEFAULT true,
    criado_em timestamp without time zone DEFAULT now(),
    atualizado_em timestamp without time zone DEFAULT now(),
    documento_norm text GENERATED ALWAYS AS (regexp_replace((COALESCE(documento, ''::character varying))::text, '\D'::text, ''::text, 'g'::text)) STORED,
    tenant_id uuid NOT NULL,
    finalidade_padrao public.item_finalidade,
    gerar_contas_pagar_auto boolean DEFAULT false NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    cnpj text,
    cnpj_norm text GENERATED ALWAYS AS (public.normalize_doc(cnpj)) STORED,
    doc text,
    doc_digits text GENERATED ALWAYS AS (
CASE
    WHEN ((doc IS NULL) OR (btrim(doc) = ''::text)) THEN NULL::text
    ELSE regexp_replace(doc, '\D'::text, ''::text, 'g'::text)
END) STORED,
    documento_key text GENERATED ALWAYS AS (public.fn_documento_key((documento)::text)) STORED,
    cnpj_digits text GENERATED ALWAYS AS (public.normalize_cnpj(cnpj)) STORED,
    motivo_compra_padrao_id uuid,
    CONSTRAINT fornecedores_doc_digits_len CHECK (((doc_digits IS NULL) OR (length(doc_digits) = ANY (ARRAY[11, 14]))))
);


--
-- Name: COLUMN fornecedores.gerar_contas_pagar_auto; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.fornecedores.gerar_contas_pagar_auto IS 'Quando true, importaÃ§Ãµes XML do fornecedor geram automaticamente contas a pagar a partir das parcelas do XML.';


--
-- Name: r_ap_aging_detalhe; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_ap_aging_detalhe AS
 SELECT t.tenant_id,
    t.empresa_id,
    t.id AS titulo_id,
    tp.id AS parcela_id,
    tp.numero AS parcela_numero,
    t.fornecedor_id,
    COALESCE(forn.nome, 'SEM FORNECEDOR'::character varying) AS fornecedor_nome,
    COALESCE(mc.codigo, 'NAO_CLASSIFICADO'::text) AS motivo_codigo,
    COALESCE(mc.nome, 'NAO CLASSIFICADO'::text) AS motivo_nome,
    tp.vencimento_date,
    (CURRENT_DATE - tp.vencimento_date) AS dias_atraso,
    tp.valor AS valor_parcela,
    tp.valor_aberto,
    t.status,
    t.emissao_date,
    t.competencia_date
   FROM ((((f.titulo_parcela tp
     JOIN f.titulo t ON ((t.id = tp.titulo_id)))
     LEFT JOIN f.titulo_aprovacao ta ON (((ta.tenant_id = t.tenant_id) AND (ta.titulo_id = t.id) AND (ta.deleted_at IS NULL))))
     LEFT JOIN f.motivo_compra mc ON (((mc.id = ta.motivo_compra_id) AND (mc.deleted_at IS NULL))))
     LEFT JOIN public.fornecedores forn ON ((forn.id = t.fornecedor_id)))
  WHERE ((tp.deleted_at IS NULL) AND (t.deleted_at IS NULL) AND (t.tipo = 'AP'::text) AND (tp.valor_aberto > (0)::numeric));


--
-- Name: r_ap_aging_resumo; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_ap_aging_resumo AS
 WITH base AS (
         SELECT t.tenant_id,
            t.empresa_id,
            t.fornecedor_id,
            COALESCE(forn.nome, 'SEM FORNECEDOR'::character varying) AS fornecedor_nome,
            COALESCE(mc.codigo, 'NAO_CLASSIFICADO'::text) AS motivo_codigo,
            COALESCE(mc.nome, 'NAO CLASSIFICADO'::text) AS motivo_nome,
            tp.vencimento_date,
            tp.valor_aberto,
            (CURRENT_DATE - tp.vencimento_date) AS dias_atraso
           FROM ((((f.titulo_parcela tp
             JOIN f.titulo t ON ((t.id = tp.titulo_id)))
             LEFT JOIN f.titulo_aprovacao ta ON (((ta.tenant_id = t.tenant_id) AND (ta.titulo_id = t.id) AND (ta.deleted_at IS NULL))))
             LEFT JOIN f.motivo_compra mc ON (((mc.id = ta.motivo_compra_id) AND (mc.deleted_at IS NULL))))
             LEFT JOIN public.fornecedores forn ON ((forn.id = t.fornecedor_id)))
          WHERE ((tp.deleted_at IS NULL) AND (t.deleted_at IS NULL) AND (t.tipo = 'AP'::text) AND (tp.valor_aberto > (0)::numeric))
        )
 SELECT tenant_id,
    empresa_id,
    fornecedor_id,
    fornecedor_nome,
    motivo_codigo,
    motivo_nome,
    (sum(
        CASE
            WHEN (vencimento_date > CURRENT_DATE) THEN valor_aberto
            ELSE (0)::numeric
        END))::numeric(15,2) AS a_vencer,
    (sum(
        CASE
            WHEN ((dias_atraso >= 0) AND (dias_atraso <= 30)) THEN valor_aberto
            ELSE (0)::numeric
        END))::numeric(15,2) AS vencido_0_30,
    (sum(
        CASE
            WHEN ((dias_atraso >= 31) AND (dias_atraso <= 60)) THEN valor_aberto
            ELSE (0)::numeric
        END))::numeric(15,2) AS vencido_31_60,
    (sum(
        CASE
            WHEN ((dias_atraso >= 61) AND (dias_atraso <= 90)) THEN valor_aberto
            ELSE (0)::numeric
        END))::numeric(15,2) AS vencido_61_90,
    (sum(
        CASE
            WHEN (dias_atraso > 90) THEN valor_aberto
            ELSE (0)::numeric
        END))::numeric(15,2) AS vencido_90_mais,
    (sum(valor_aberto))::numeric(15,2) AS total_aberto
   FROM base
  GROUP BY tenant_id, empresa_id, fornecedor_id, fornecedor_nome, motivo_codigo, motivo_nome
  ORDER BY ((sum(valor_aberto))::numeric(15,2)) DESC;


--
-- Name: titulo_agendamento; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.titulo_agendamento (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    titulo_id uuid NOT NULL,
    conta_bancaria_id uuid NOT NULL,
    data_prevista date NOT NULL,
    forma_pagamento text DEFAULT 'OUTROS'::text NOT NULL,
    valor_previsto numeric(15,2) NOT NULL,
    observacoes text,
    change_reason text,
    agendado_em timestamp with time zone DEFAULT now() NOT NULL,
    agendado_por uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_titulo_agendamento__forma CHECK ((forma_pagamento = ANY (ARRAY['PIX'::text, 'BOLETO'::text, 'TRANSFERENCIA'::text, 'DINHEIRO'::text, 'CARTAO'::text, 'OUTROS'::text]))),
    CONSTRAINT ck_titulo_agendamento__valor CHECK ((valor_previsto > (0)::numeric))
);


--
-- Name: r_fluxo_caixa_previsto_diario; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_fluxo_caixa_previsto_diario AS
 WITH ag AS (
         SELECT t.tenant_id,
            t.empresa_id,
            ta.conta_bancaria_id,
            ta.data_prevista AS data_ref,
            'AGENDADO'::text AS origem,
            ta.valor_previsto
           FROM (f.titulo_agendamento ta
             JOIN f.titulo t ON ((t.id = ta.titulo_id)))
          WHERE ((ta.deleted_at IS NULL) AND (t.deleted_at IS NULL) AND (t.tipo = 'AP'::text))
        ), venc AS (
         SELECT t.tenant_id,
            t.empresa_id,
            COALESCE(ta.conta_bancaria_id, NULL::uuid) AS conta_bancaria_id,
            tp.vencimento_date AS data_ref,
            'VENCIMENTO'::text AS origem,
            tp.valor_aberto AS valor_previsto
           FROM ((f.titulo_parcela tp
             JOIN f.titulo t ON ((t.id = tp.titulo_id)))
             LEFT JOIN f.titulo_agendamento ta ON (((ta.tenant_id = t.tenant_id) AND (ta.titulo_id = t.id) AND (ta.deleted_at IS NULL))))
          WHERE ((tp.deleted_at IS NULL) AND (t.deleted_at IS NULL) AND (t.tipo = 'AP'::text) AND (t.status = ANY (ARRAY['APROVADO'::text, 'AGENDADO'::text, 'PENDENTE'::text])) AND (tp.valor_aberto > (0)::numeric) AND (ta.id IS NULL))
        )
 SELECT tenant_id,
    empresa_id,
    conta_bancaria_id,
    data_ref,
    origem,
    (sum(valor_previsto))::numeric(15,2) AS valor_previsto
   FROM ( SELECT ag.tenant_id,
            ag.empresa_id,
            ag.conta_bancaria_id,
            ag.data_ref,
            ag.origem,
            ag.valor_previsto
           FROM ag
        UNION ALL
         SELECT venc.tenant_id,
            venc.empresa_id,
            venc.conta_bancaria_id,
            venc.data_ref,
            venc.origem,
            venc.valor_previsto
           FROM venc) x
  GROUP BY tenant_id, empresa_id, conta_bancaria_id, data_ref, origem;


--
-- Name: r_fluxo_caixa_realizado_diario; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_fluxo_caixa_realizado_diario AS
 SELECT tenant_id,
    empresa_id,
    conta_bancaria_id,
    data_pagamento AS data_ref,
        CASE
            WHEN (conciliado_at IS NOT NULL) THEN 'CONCILIADO'::text
            ELSE 'NAO_CONCILIADO'::text
        END AS status_conciliacao,
    (sum(valor))::numeric(15,2) AS valor_realizado
   FROM f.pagamento p
  WHERE (deleted_at IS NULL)
  GROUP BY tenant_id, empresa_id, conta_bancaria_id, data_pagamento,
        CASE
            WHEN (conciliado_at IS NOT NULL) THEN 'CONCILIADO'::text
            ELSE 'NAO_CONCILIADO'::text
        END;


--
-- Name: r_fluxo_caixa_diario; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_fluxo_caixa_diario AS
 SELECT COALESCE(pr.tenant_id, rr.tenant_id) AS tenant_id,
    COALESCE(pr.empresa_id, rr.empresa_id) AS empresa_id,
    COALESCE(pr.conta_bancaria_id, rr.conta_bancaria_id) AS conta_bancaria_id,
    COALESCE(pr.data_ref, rr.data_ref) AS data_ref,
    (COALESCE(pr.valor_previsto, (0)::numeric))::numeric(15,2) AS valor_previsto,
    (COALESCE(rr.valor_realizado, (0)::numeric))::numeric(15,2) AS valor_realizado
   FROM (( SELECT r_fluxo_caixa_previsto_diario.tenant_id,
            r_fluxo_caixa_previsto_diario.empresa_id,
            r_fluxo_caixa_previsto_diario.conta_bancaria_id,
            r_fluxo_caixa_previsto_diario.data_ref,
            (sum(r_fluxo_caixa_previsto_diario.valor_previsto))::numeric(15,2) AS valor_previsto
           FROM f.r_fluxo_caixa_previsto_diario
          GROUP BY r_fluxo_caixa_previsto_diario.tenant_id, r_fluxo_caixa_previsto_diario.empresa_id, r_fluxo_caixa_previsto_diario.conta_bancaria_id, r_fluxo_caixa_previsto_diario.data_ref) pr
     FULL JOIN ( SELECT r_fluxo_caixa_realizado_diario.tenant_id,
            r_fluxo_caixa_realizado_diario.empresa_id,
            r_fluxo_caixa_realizado_diario.conta_bancaria_id,
            r_fluxo_caixa_realizado_diario.data_ref,
            (sum(r_fluxo_caixa_realizado_diario.valor_realizado))::numeric(15,2) AS valor_realizado
           FROM f.r_fluxo_caixa_realizado_diario
          GROUP BY r_fluxo_caixa_realizado_diario.tenant_id, r_fluxo_caixa_realizado_diario.empresa_id, r_fluxo_caixa_realizado_diario.conta_bancaria_id, r_fluxo_caixa_realizado_diario.data_ref) rr ON (((rr.tenant_id = pr.tenant_id) AND (rr.empresa_id = pr.empresa_id) AND (NOT (rr.conta_bancaria_id IS DISTINCT FROM pr.conta_bancaria_id)) AND (rr.data_ref = pr.data_ref))));


--
-- Name: r_fluxo_caixa_diario_conta_resolvida; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_fluxo_caixa_diario_conta_resolvida AS
 SELECT d.tenant_id,
    d.empresa_id,
    COALESCE(d.conta_bancaria_id, p.conta_bancaria_padrao_id) AS conta_bancaria_id,
    d.data_ref,
    d.valor_previsto,
    d.valor_realizado
   FROM (f.r_fluxo_caixa_diario d
     LEFT JOIN f.parametro_financeiro_empresa p ON (((p.tenant_id = d.tenant_id) AND (p.empresa_id = d.empresa_id) AND (p.deleted_at IS NULL))));


--
-- Name: r_fluxo_previsto_diario_dim; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_fluxo_previsto_diario_dim AS
 WITH aprov AS (
         SELECT a.tenant_id,
            a.titulo_id,
            a.motivo_compra_id,
            a.os_id
           FROM f.titulo_aprovacao a
          WHERE (a.deleted_at IS NULL)
        ), ag AS (
         SELECT t.tenant_id,
            t.empresa_id,
            ta.conta_bancaria_id,
            ta.data_prevista AS data_ref,
            'AGENDADO'::text AS origem,
            t.fornecedor_id,
            ap.motivo_compra_id,
            ap.os_id,
            ta.valor_previsto
           FROM ((f.titulo_agendamento ta
             JOIN f.titulo t ON ((t.id = ta.titulo_id)))
             LEFT JOIN aprov ap ON (((ap.tenant_id = t.tenant_id) AND (ap.titulo_id = t.id))))
          WHERE ((ta.deleted_at IS NULL) AND (t.deleted_at IS NULL) AND (t.tipo = 'AP'::text))
        ), venc AS (
         SELECT t.tenant_id,
            t.empresa_id,
            NULL::uuid AS conta_bancaria_id,
            tp.vencimento_date AS data_ref,
            'VENCIMENTO'::text AS origem,
            t.fornecedor_id,
            ap.motivo_compra_id,
            ap.os_id,
            tp.valor_aberto AS valor_previsto
           FROM (((f.titulo_parcela tp
             JOIN f.titulo t ON ((t.id = tp.titulo_id)))
             LEFT JOIN f.titulo_agendamento ta ON (((ta.tenant_id = t.tenant_id) AND (ta.titulo_id = t.id) AND (ta.deleted_at IS NULL))))
             LEFT JOIN aprov ap ON (((ap.tenant_id = t.tenant_id) AND (ap.titulo_id = t.id))))
          WHERE ((tp.deleted_at IS NULL) AND (t.deleted_at IS NULL) AND (t.tipo = 'AP'::text) AND (t.status = ANY (ARRAY['PENDENTE'::text, 'APROVADO'::text, 'AGENDADO'::text])) AND (tp.valor_aberto > (0)::numeric) AND (ta.id IS NULL))
        )
 SELECT tenant_id,
    empresa_id,
    conta_bancaria_id,
    data_ref,
    origem,
    fornecedor_id,
    motivo_compra_id,
    os_id,
    (sum(valor_previsto))::numeric(15,2) AS valor_previsto
   FROM ( SELECT ag.tenant_id,
            ag.empresa_id,
            ag.conta_bancaria_id,
            ag.data_ref,
            ag.origem,
            ag.fornecedor_id,
            ag.motivo_compra_id,
            ag.os_id,
            ag.valor_previsto
           FROM ag
        UNION ALL
         SELECT venc.tenant_id,
            venc.empresa_id,
            venc.conta_bancaria_id,
            venc.data_ref,
            venc.origem,
            venc.fornecedor_id,
            venc.motivo_compra_id,
            venc.os_id,
            venc.valor_previsto
           FROM venc) x
  GROUP BY tenant_id, empresa_id, conta_bancaria_id, data_ref, origem, fornecedor_id, motivo_compra_id, os_id;


--
-- Name: r_fluxo_realizado_diario_dim; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_fluxo_realizado_diario_dim AS
 WITH aprov AS (
         SELECT a.tenant_id,
            a.titulo_id,
            a.motivo_compra_id,
            a.os_id
           FROM f.titulo_aprovacao a
          WHERE (a.deleted_at IS NULL)
        ), base AS (
         SELECT pa.tenant_id,
            pa.empresa_id,
            pa.conta_bancaria_id,
            pa.data_pagamento AS data_ref,
            pa.pagamento_id,
            pa.forma_pagamento,
            pa.valor_pagamento,
            t.fornecedor_id,
            ap.motivo_compra_id,
            ap.os_id,
            pa.valor_aplicado
           FROM ((f.fn_pagamentos_aplicados() pa(tenant_id, empresa_id, conta_bancaria_id, pagamento_id, data_pagamento, forma_pagamento, valor_pagamento, titulo_id, titulo_parcela_id, valor_aplicado)
             JOIN f.titulo t ON ((t.id = pa.titulo_id)))
             LEFT JOIN aprov ap ON (((ap.tenant_id = t.tenant_id) AND (ap.titulo_id = t.id))))
          WHERE ((t.deleted_at IS NULL) AND (t.tipo = 'AP'::text))
        )
 SELECT tenant_id,
    empresa_id,
    conta_bancaria_id,
    data_ref,
    fornecedor_id,
    motivo_compra_id,
    os_id,
    (sum(valor_aplicado))::numeric(15,2) AS valor_realizado
   FROM base
  GROUP BY tenant_id, empresa_id, conta_bancaria_id, data_ref, fornecedor_id, motivo_compra_id, os_id;


--
-- Name: r_fluxo_caixa_diario_dim; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_fluxo_caixa_diario_dim AS
 SELECT COALESCE(p.tenant_id, r.tenant_id) AS tenant_id,
    COALESCE(p.empresa_id, r.empresa_id) AS empresa_id,
    COALESCE(p.conta_bancaria_id, r.conta_bancaria_id) AS conta_bancaria_id,
    COALESCE(p.data_ref, r.data_ref) AS data_ref,
    COALESCE(p.fornecedor_id, r.fornecedor_id) AS fornecedor_id,
    COALESCE(p.motivo_compra_id, r.motivo_compra_id) AS motivo_compra_id,
    COALESCE(p.os_id, r.os_id) AS os_id,
    (COALESCE(p.valor_previsto, (0)::numeric))::numeric(15,2) AS valor_previsto,
    (COALESCE(r.valor_realizado, (0)::numeric))::numeric(15,2) AS valor_realizado
   FROM (f.r_fluxo_previsto_diario_dim p
     FULL JOIN f.r_fluxo_realizado_diario_dim r ON (((r.tenant_id = p.tenant_id) AND (r.empresa_id = p.empresa_id) AND (NOT (r.conta_bancaria_id IS DISTINCT FROM p.conta_bancaria_id)) AND (r.data_ref = p.data_ref) AND (NOT (r.fornecedor_id IS DISTINCT FROM p.fornecedor_id)) AND (NOT (r.motivo_compra_id IS DISTINCT FROM p.motivo_compra_id)) AND (NOT (r.os_id IS DISTINCT FROM p.os_id)))));


--
-- Name: r_fluxo_caixa_diario_por_fornecedor; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_fluxo_caixa_diario_por_fornecedor AS
 SELECT tenant_id,
    empresa_id,
    conta_bancaria_id,
    data_ref,
    fornecedor_id,
    (sum(valor_previsto))::numeric(15,2) AS valor_previsto,
    (sum(valor_realizado))::numeric(15,2) AS valor_realizado
   FROM f.r_fluxo_caixa_diario_dim
  GROUP BY tenant_id, empresa_id, conta_bancaria_id, data_ref, fornecedor_id;


--
-- Name: r_fluxo_caixa_diario_por_motivo; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_fluxo_caixa_diario_por_motivo AS
 SELECT tenant_id,
    empresa_id,
    conta_bancaria_id,
    data_ref,
    motivo_compra_id,
    (sum(valor_previsto))::numeric(15,2) AS valor_previsto,
    (sum(valor_realizado))::numeric(15,2) AS valor_realizado
   FROM f.r_fluxo_caixa_diario_dim
  GROUP BY tenant_id, empresa_id, conta_bancaria_id, data_ref, motivo_compra_id;


--
-- Name: r_fluxo_caixa_diario_por_motivo_rotulado; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_fluxo_caixa_diario_por_motivo_rotulado AS
 SELECT x.tenant_id,
    x.empresa_id,
    x.conta_bancaria_id,
    x.data_ref,
    x.motivo_compra_id,
    COALESCE(mc.codigo, 'NAO_CLASSIFICADO'::text) AS motivo_codigo,
    COALESCE(mc.nome, 'NAO CLASSIFICADO'::text) AS motivo_nome,
    x.valor_previsto,
    x.valor_realizado
   FROM (f.r_fluxo_caixa_diario_por_motivo x
     LEFT JOIN f.motivo_compra mc ON (((mc.id = x.motivo_compra_id) AND (mc.deleted_at IS NULL))));


--
-- Name: r_fluxo_caixa_diario_por_os; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_fluxo_caixa_diario_por_os AS
 SELECT tenant_id,
    empresa_id,
    conta_bancaria_id,
    data_ref,
    os_id,
    (sum(valor_previsto))::numeric(15,2) AS valor_previsto,
    (sum(valor_realizado))::numeric(15,2) AS valor_realizado
   FROM f.r_fluxo_caixa_diario_dim
  GROUP BY tenant_id, empresa_id, conta_bancaria_id, data_ref, os_id;


--
-- Name: r_fluxo_caixa_mensal; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_fluxo_caixa_mensal AS
 SELECT tenant_id,
    empresa_id,
    conta_bancaria_id,
    (date_trunc('month'::text, (data_ref)::timestamp with time zone))::date AS mes_ref,
    (sum(valor_previsto))::numeric(15,2) AS valor_previsto,
    (sum(valor_realizado))::numeric(15,2) AS valor_realizado
   FROM f.r_fluxo_caixa_diario
  GROUP BY tenant_id, empresa_id, conta_bancaria_id, ((date_trunc('month'::text, (data_ref)::timestamp with time zone))::date);


--
-- Name: r_fluxo_previsto_diario_ajustado_hoje; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_fluxo_previsto_diario_ajustado_hoje AS
 SELECT tenant_id,
    empresa_id,
    conta_bancaria_id,
        CASE
            WHEN (data_ref < CURRENT_DATE) THEN CURRENT_DATE
            ELSE data_ref
        END AS data_ref,
    (sum(valor_previsto))::numeric(15,2) AS valor_previsto
   FROM f.r_fluxo_previsto_diario_dim
  GROUP BY tenant_id, empresa_id, conta_bancaria_id,
        CASE
            WHEN (data_ref < CURRENT_DATE) THEN CURRENT_DATE
            ELSE data_ref
        END;


--
-- Name: r_saldo_projetado_diario; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_saldo_projetado_diario AS
 WITH base AS (
         SELECT r_fluxo_caixa_diario.tenant_id,
            r_fluxo_caixa_diario.empresa_id,
            r_fluxo_caixa_diario.conta_bancaria_id,
            r_fluxo_caixa_diario.data_ref,
            (sum(r_fluxo_caixa_diario.valor_previsto))::numeric(15,2) AS valor_previsto,
            (sum(r_fluxo_caixa_diario.valor_realizado))::numeric(15,2) AS valor_realizado
           FROM f.r_fluxo_caixa_diario
          GROUP BY r_fluxo_caixa_diario.tenant_id, r_fluxo_caixa_diario.empresa_id, r_fluxo_caixa_diario.conta_bancaria_id, r_fluxo_caixa_diario.data_ref
        )
 SELECT tenant_id,
    empresa_id,
    conta_bancaria_id,
    data_ref,
    valor_previsto,
    valor_realizado,
    (sum(valor_previsto) OVER (PARTITION BY tenant_id, empresa_id, conta_bancaria_id ORDER BY data_ref ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))::numeric(15,2) AS acumulado_previsto,
    (sum(valor_realizado) OVER (PARTITION BY tenant_id, empresa_id, conta_bancaria_id ORDER BY data_ref ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))::numeric(15,2) AS acumulado_realizado,
    (sum((valor_realizado - valor_previsto)) OVER (PARTITION BY tenant_id, empresa_id, conta_bancaria_id ORDER BY data_ref ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))::numeric(15,2) AS acumulado_delta
   FROM base;


--
-- Name: r_saldo_projetado_diario_com_saldo_inicial; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_saldo_projetado_diario_com_saldo_inicial AS
 WITH base AS (
         SELECT d.tenant_id,
            d.empresa_id,
            d.conta_bancaria_id,
            d.data_ref,
            d.valor_previsto,
            d.valor_realizado,
            (COALESCE(p.saldo_inicial, (0)::numeric))::numeric(15,2) AS saldo_inicial,
            COALESCE(p.data_saldo_inicial, d.data_ref) AS data_saldo_inicial
           FROM (f.r_fluxo_caixa_diario_conta_resolvida d
             LEFT JOIN f.parametro_financeiro_empresa p ON (((p.tenant_id = d.tenant_id) AND (p.empresa_id = d.empresa_id) AND (p.deleted_at IS NULL))))
        )
 SELECT tenant_id,
    empresa_id,
    conta_bancaria_id,
    data_ref,
    valor_previsto,
    valor_realizado,
    (sum(
        CASE
            WHEN (data_ref >= data_saldo_inicial) THEN valor_previsto
            ELSE (0)::numeric
        END) OVER (PARTITION BY tenant_id, empresa_id, conta_bancaria_id ORDER BY data_ref))::numeric(15,2) AS acumulado_previsto,
    (sum(
        CASE
            WHEN (data_ref >= data_saldo_inicial) THEN valor_realizado
            ELSE (0)::numeric
        END) OVER (PARTITION BY tenant_id, empresa_id, conta_bancaria_id ORDER BY data_ref))::numeric(15,2) AS acumulado_realizado,
    ((max(saldo_inicial) OVER (PARTITION BY tenant_id, empresa_id, conta_bancaria_id) + sum(
        CASE
            WHEN (data_ref >= data_saldo_inicial) THEN (valor_realizado - valor_previsto)
            ELSE (0)::numeric
        END) OVER (PARTITION BY tenant_id, empresa_id, conta_bancaria_id ORDER BY data_ref)))::numeric(15,2) AS saldo_projetado
   FROM base
  WHERE (data_ref >= data_saldo_inicial);


--
-- Name: r_sugestoes_conciliacao_ap; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_sugestoes_conciliacao_ap AS
 WITH extrato AS (
         SELECT el.id AS extrato_linha_id,
            el.tenant_id,
            el.conta_bancaria_id,
            el.data_movimento,
            el.descricao,
            el.documento,
            el.valor AS valor_extrato,
            (abs(el.valor))::numeric(15,2) AS valor_extrato_abs
           FROM f.extrato_bancario_linha el
          WHERE ((el.deleted_at IS NULL) AND (el.status = 'PENDENTE'::text) AND (el.valor < (0)::numeric))
        ), pag AS (
         SELECT p_1.id AS pagamento_id,
            p_1.tenant_id,
            p_1.empresa_id,
            p_1.conta_bancaria_id,
            p_1.data_pagamento,
            p_1.forma_pagamento,
            p_1.valor AS valor_pagamento
           FROM f.pagamento p_1
          WHERE ((p_1.deleted_at IS NULL) AND (p_1.conciliado_at IS NULL))
        )
 SELECT e.tenant_id,
    p.empresa_id,
    e.conta_bancaria_id,
    e.extrato_linha_id,
    e.data_movimento,
    e.valor_extrato,
    e.descricao,
    e.documento,
    p.pagamento_id,
    p.data_pagamento,
    p.forma_pagamento,
    p.valor_pagamento,
    ((e.valor_extrato_abs - p.valor_pagamento))::numeric(15,2) AS diferenca_valor,
        CASE
            WHEN (e.data_movimento = p.data_pagamento) THEN 3
            WHEN ((e.data_movimento = (p.data_pagamento - 1)) OR (e.data_movimento = (p.data_pagamento + 1))) THEN 2
            WHEN ((e.data_movimento = (p.data_pagamento - 2)) OR (e.data_movimento = (p.data_pagamento + 2))) THEN 1
            ELSE 0
        END AS score_data
   FROM (extrato e
     JOIN pag p ON (((p.tenant_id = e.tenant_id) AND (p.conta_bancaria_id = e.conta_bancaria_id) AND (p.valor_pagamento = e.valor_extrato_abs) AND ((e.data_movimento >= (p.data_pagamento - 2)) AND (e.data_movimento <= (p.data_pagamento + 2))))));


--
-- Name: r_titulos_sem_motivo_por_fornecedor; Type: VIEW; Schema: f; Owner: -
--

CREATE VIEW f.r_titulos_sem_motivo_por_fornecedor AS
 SELECT t.tenant_id,
    t.empresa_id,
    t.fornecedor_id,
    COALESCE(f.nome, 'SEM FORNECEDOR'::character varying) AS fornecedor_nome,
    count(*) AS qtd_titulos_sem_motivo,
    (sum(tp.valor_aberto))::numeric(15,2) AS total_aberto
   FROM (((f.titulo_parcela tp
     JOIN f.titulo t ON ((t.id = tp.titulo_id)))
     LEFT JOIN f.titulo_aprovacao ta ON (((ta.tenant_id = t.tenant_id) AND (ta.titulo_id = t.id) AND (ta.deleted_at IS NULL))))
     LEFT JOIN public.fornecedores f ON ((f.id = t.fornecedor_id)))
  WHERE ((tp.deleted_at IS NULL) AND (t.deleted_at IS NULL) AND (t.tipo = 'AP'::text) AND (tp.valor_aberto > (0)::numeric) AND (ta.id IS NULL))
  GROUP BY t.tenant_id, t.empresa_id, t.fornecedor_id, COALESCE(f.nome, 'SEM FORNECEDOR'::character varying)
  ORDER BY ((sum(tp.valor_aberto))::numeric(15,2)) DESC;


--
-- Name: titulo_rateio; Type: TABLE; Schema: f; Owner: -
--

CREATE TABLE f.titulo_rateio (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    titulo_id uuid NOT NULL,
    plano_contas_id uuid,
    centro_custo_id uuid,
    os_id integer,
    percentual numeric(7,4),
    valor numeric(15,2),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT a.fn_current_usuario_id(),
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_titulo_rateio__percentual CHECK (((percentual IS NULL) OR ((percentual >= (0)::numeric) AND (percentual <= (100)::numeric)))),
    CONSTRAINT ck_titulo_rateio__valor CHECK (((valor IS NULL) OR (valor >= (0)::numeric)))
);


--
-- Name: apontamentos_horas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.apontamentos_horas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    os_id integer NOT NULL,
    colaborador_id uuid NOT NULL,
    data date NOT NULL,
    horas numeric(6,2) NOT NULL,
    tipo_hora_id uuid,
    fator_aplicado numeric(6,3),
    descricao text,
    status character varying(20) DEFAULT 'lancado'::character varying NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    tenant_id uuid NOT NULL,
    hh_especialidade_id uuid,
    hora_entrada_1 time without time zone,
    hora_saida_1 time without time zone,
    hora_entrada_2 time without time zone,
    hora_saida_2 time without time zone,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    gerado_por_hh boolean DEFAULT false NOT NULL,
    hh_lancamento_id bigint,
    CONSTRAINT apontamentos_horas_chk CHECK (((horas > (0)::numeric) AND (horas <= (24)::numeric))),
    CONSTRAINT apontamentos_horas_periodos_ck CHECK ((((hora_entrada_1 IS NULL) AND (hora_saida_1 IS NULL) AND (hora_entrada_2 IS NULL) AND (hora_saida_2 IS NULL)) OR ((hora_entrada_1 IS NOT NULL) AND (hora_saida_1 IS NOT NULL) AND (hora_entrada_2 IS NOT NULL) AND (hora_saida_2 IS NOT NULL) AND (hora_saida_1 > hora_entrada_1) AND (hora_saida_2 > hora_entrada_2) AND (hora_saida_1 <= hora_entrada_2))))
);


--
-- Name: COLUMN apontamentos_horas.hora_entrada_1; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.apontamentos_horas.hora_entrada_1 IS 'Entrada período 1 (manhã)';


--
-- Name: COLUMN apontamentos_horas.hora_saida_1; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.apontamentos_horas.hora_saida_1 IS 'Saída período 1 (manhã)';


--
-- Name: COLUMN apontamentos_horas.hora_entrada_2; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.apontamentos_horas.hora_entrada_2 IS 'Entrada período 2 (tarde)';


--
-- Name: COLUMN apontamentos_horas.hora_saida_2; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.apontamentos_horas.hora_saida_2 IS 'Saída período 2 (tarde)';


--
-- Name: COLUMN apontamentos_horas.gerado_por_hh; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.apontamentos_horas.gerado_por_hh IS 'True quando o lançamento foi gerado automaticamente a partir de HH lançado dentro da OS (sem horários, só total)';


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id bigint NOT NULL,
    tenant_id uuid,
    table_name text NOT NULL,
    action text NOT NULL,
    row_pk text,
    old_data jsonb,
    new_data jsonb,
    actor_user_id uuid,
    actor_email text,
    request_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT audit_log_action_check CHECK ((action = ANY (ARRAY['INSERT'::text, 'UPDATE'::text, 'DELETE'::text])))
);


--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_log_id_seq OWNED BY public.audit_log.id;


--
-- Name: centros_custo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.centros_custo (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    codigo text NOT NULL,
    descricao text NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: cliente_hh_servicos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cliente_hh_servicos (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    cliente_id bigint NOT NULL,
    nome text NOT NULL,
    descricao text,
    preco_base numeric(15,2) DEFAULT 0 NOT NULL,
    preco_50 numeric(15,2) DEFAULT 0 NOT NULL,
    preco_100 numeric(15,2) DEFAULT 0 NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    criado_por text
);


--
-- Name: TABLE cliente_hh_servicos; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.cliente_hh_servicos IS 'ServiÃ§os de HH (Hora-Homem) especÃ­ficos por cliente, com preÃ§os em 3 nÃ­veis: base, 50% e 100%';


--
-- Name: COLUMN cliente_hh_servicos.preco_base; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cliente_hh_servicos.preco_base IS 'PreÃ§o base do serviÃ§o (ex: R$ 100,00)';


--
-- Name: COLUMN cliente_hh_servicos.preco_50; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cliente_hh_servicos.preco_50 IS 'PreÃ§o com acrÃ©scimo de 50% (ex: R$ 150,00)';


--
-- Name: COLUMN cliente_hh_servicos.preco_100; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cliente_hh_servicos.preco_100 IS 'PreÃ§o com acrÃ©scimo de 100% (ex: R$ 200,00)';


--
-- Name: cliente_hh_servicos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cliente_hh_servicos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cliente_hh_servicos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cliente_hh_servicos_id_seq OWNED BY public.cliente_hh_servicos.id;


--
-- Name: cliente_hh_tabelas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cliente_hh_tabelas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cliente_id integer NOT NULL,
    ano integer NOT NULL,
    nome text,
    vigencia_inicio date NOT NULL,
    vigencia_fim date NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    tenant_id uuid NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now(),
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    CONSTRAINT cliente_hh_tabelas_vigencia_chk CHECK ((vigencia_fim >= vigencia_inicio))
);


--
-- Name: clientes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clientes (
    id integer NOT NULL,
    nome character varying(255) NOT NULL,
    documento character varying(20),
    email character varying(120),
    telefone character varying(30),
    endereco text,
    observacoes text,
    ativo boolean DEFAULT true,
    criado_em timestamp without time zone DEFAULT now(),
    atualizado_em timestamp without time zone DEFAULT now(),
    tenant_id uuid NOT NULL,
    habilita_hh boolean DEFAULT false NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL
);


--
-- Name: COLUMN clientes.habilita_hh; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.clientes.habilita_hh IS 'Indica se o cliente utiliza relatÃ³rios de Hora-Homem (HH)';


--
-- Name: clientes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.clientes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: clientes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.clientes_id_seq OWNED BY public.clientes.id;


--
-- Name: colaborador_cliente_funcao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.colaborador_cliente_funcao (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    cliente_id bigint NOT NULL,
    colaborador_id uuid NOT NULL,
    hh_servico_id bigint NOT NULL,
    ativo boolean DEFAULT true,
    criado_em timestamp without time zone DEFAULT now(),
    atualizado_em timestamp without time zone DEFAULT now(),
    criado_por text,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL
);


--
-- Name: TABLE colaborador_cliente_funcao; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.colaborador_cliente_funcao IS 'VÃ­nculos entre colaboradores e funÃ§Ãµes/serviÃ§os HH por cliente';


--
-- Name: COLUMN colaborador_cliente_funcao.tenant_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.colaborador_cliente_funcao.tenant_id IS 'Tenant proprietÃ¡rio do vÃ­nculo';


--
-- Name: COLUMN colaborador_cliente_funcao.cliente_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.colaborador_cliente_funcao.cliente_id IS 'Cliente para o qual o colaborador presta serviÃ§o';


--
-- Name: COLUMN colaborador_cliente_funcao.colaborador_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.colaborador_cliente_funcao.colaborador_id IS 'Colaborador vinculado';


--
-- Name: COLUMN colaborador_cliente_funcao.hh_servico_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.colaborador_cliente_funcao.hh_servico_id IS 'ServiÃ§o/especialidade HH atribuÃ­da ao colaborador neste cliente';


--
-- Name: COLUMN colaborador_cliente_funcao.ativo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.colaborador_cliente_funcao.ativo IS 'Se false, vÃ­nculo foi desativado (soft delete)';


--
-- Name: colaborador_cliente_funcao_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.colaborador_cliente_funcao_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: colaborador_cliente_funcao_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.colaborador_cliente_funcao_id_seq OWNED BY public.colaborador_cliente_funcao.id;


--
-- Name: colaborador_funcao_hh; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.colaborador_funcao_hh (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    cliente_id bigint NOT NULL,
    colaborador_id uuid NOT NULL,
    servico_hh_id bigint NOT NULL,
    ativo boolean DEFAULT true,
    criado_em timestamp with time zone DEFAULT now(),
    atualizado_em timestamp with time zone DEFAULT now(),
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL
);


--
-- Name: TABLE colaborador_funcao_hh; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.colaborador_funcao_hh IS 'VÃ­nculo entre colaboradores e serviÃ§os de HH (funÃ§Ãµes/especialidades) por cliente';


--
-- Name: COLUMN colaborador_funcao_hh.tenant_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.colaborador_funcao_hh.tenant_id IS 'Tenant (organizaÃ§Ã£o)';


--
-- Name: COLUMN colaborador_funcao_hh.cliente_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.colaborador_funcao_hh.cliente_id IS 'Cliente relacionado';


--
-- Name: COLUMN colaborador_funcao_hh.colaborador_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.colaborador_funcao_hh.colaborador_id IS 'Colaborador (funcionÃ¡rio)';


--
-- Name: COLUMN colaborador_funcao_hh.servico_hh_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.colaborador_funcao_hh.servico_hh_id IS 'ServiÃ§o de HH (funÃ§Ã£o/especialidade) do cliente';


--
-- Name: colaborador_funcao_hh_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.colaborador_funcao_hh ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.colaborador_funcao_hh_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: colaborador_taxas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.colaborador_taxas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    colaborador_id uuid NOT NULL,
    valor_hora numeric(10,2) NOT NULL,
    vigencia_inicio date NOT NULL,
    vigencia_fim date,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    CONSTRAINT colaborador_taxas_vigencia_chk CHECK (((vigencia_fim IS NULL) OR (vigencia_fim >= vigencia_inicio)))
);


--
-- Name: colaboradores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.colaboradores (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nome character varying(150) NOT NULL,
    cargo character varying(100),
    ativo boolean DEFAULT true NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    tenant_id uuid NOT NULL,
    hh_especialidade_id uuid,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL
);


--
-- Name: competencias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.competencias (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    ano integer NOT NULL,
    mes integer NOT NULL,
    status text DEFAULT 'aberta'::text NOT NULL,
    fechada_em timestamp with time zone,
    fechada_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT competencias_ano_check CHECK (((ano >= 2000) AND (ano <= 2100))),
    CONSTRAINT competencias_mes_check CHECK (((mes >= 1) AND (mes <= 12))),
    CONSTRAINT competencias_status_check CHECK ((status = ANY (ARRAY['aberta'::text, 'fechada'::text])))
);


--
-- Name: contas_pagar_titulos; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.contas_pagar_titulos AS
 SELECT id,
    tenant_id,
    empresa_id,
    tipo,
    status,
    origem,
    fornecedor_id,
    cliente_id,
    documento_fiscal_id,
    descricao,
    emissao_date,
    competencia_date,
    valor_total,
    valor_aberto,
    created_at,
    updated_at,
    created_by,
    updated_by,
    deleted_at,
    motivo_compra_id
   FROM f.titulo t;


--
-- Name: contas_pagar_titulos_agendamentos; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.contas_pagar_titulos_agendamentos AS
 SELECT id,
    tenant_id,
    titulo_id,
    conta_bancaria_id,
    data_prevista,
    forma_pagamento,
    valor_previsto,
    observacoes,
    change_reason,
    agendado_em,
    agendado_por,
    created_at,
    updated_at,
    created_by,
    updated_by,
    deleted_at
   FROM f.titulo_agendamento;


--
-- Name: contas_pagar_titulos_aprovacoes; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.contas_pagar_titulos_aprovacoes AS
 SELECT id,
    tenant_id,
    titulo_id,
    motivo_compra_id,
    motivo_outros_text,
    os_id,
    aprovado_em,
    aprovado_por,
    change_reason,
    created_at,
    updated_at,
    created_by,
    updated_by,
    deleted_at
   FROM f.titulo_aprovacao;


--
-- Name: contas_pagar_titulos_parcelas; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.contas_pagar_titulos_parcelas AS
 SELECT id,
    tenant_id,
    titulo_id,
    numero,
    vencimento_date,
    valor,
    valor_aberto,
    created_at,
    updated_at,
    created_by,
    updated_by,
    deleted_at
   FROM f.titulo_parcela;


--
-- Name: contas_pagar_titulos_rateios; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.contas_pagar_titulos_rateios AS
 SELECT id,
    tenant_id,
    titulo_id,
    plano_contas_id,
    centro_custo_id,
    os_id,
    percentual,
    valor,
    created_at,
    updated_at,
    created_by,
    updated_by,
    deleted_at
   FROM f.titulo_rateio;


--
-- Name: empresa_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.empresa_memberships (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role text DEFAULT 'user'::text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: empresa_memberships_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.empresa_memberships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: empresa_memberships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.empresa_memberships_id_seq OWNED BY public.empresa_memberships.id;


--
-- Name: empresas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.empresas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    cnpj text NOT NULL,
    razao_social text NOT NULL,
    nome_fantasia text,
    ie text,
    im text,
    uf character(2),
    cidade text,
    endereco text,
    regime_tributario text,
    ativo boolean DEFAULT true NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    habilita_servico_hh boolean DEFAULT false NOT NULL
);


--
-- Name: estoque; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.estoque (
    id integer NOT NULL,
    item_id integer NOT NULL,
    quantidade_atual numeric(14,3) DEFAULT 0 NOT NULL,
    localizacao text,
    atualizado_em timestamp without time zone DEFAULT now(),
    tenant_id uuid NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL
);


--
-- Name: estoque_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.estoque_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: estoque_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.estoque_id_seq OWNED BY public.estoque.id;


--
-- Name: feriados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.feriados (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    data date NOT NULL,
    descricao character varying(120),
    abrangencia character varying(20) DEFAULT 'NACIONAL'::character varying NOT NULL
);


--
-- Name: fiscal_itens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fiscal_itens (
    id bigint NOT NULL,
    item_id bigint NOT NULL,
    ncm character varying(12),
    cest character varying(12),
    origem smallint,
    cfop_padrao character varying(10),
    cst_icms character varying(5),
    cst_pis character varying(5),
    cst_cofins character varying(5),
    aliq_icms numeric(7,4) DEFAULT 0,
    aliq_ipi numeric(7,4) DEFAULT 0,
    aliq_pis numeric(7,4) DEFAULT 0,
    aliq_cofins numeric(7,4) DEFAULT 0,
    credita_icms boolean DEFAULT false NOT NULL,
    credita_pis boolean DEFAULT false NOT NULL,
    credita_cofins boolean DEFAULT false NOT NULL,
    ipi_entra_no_custo boolean DEFAULT true NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    CONSTRAINT fiscal_itens_aliq_cofins_ck CHECK (((aliq_cofins IS NULL) OR ((aliq_cofins >= (0)::numeric) AND (aliq_cofins <= (100)::numeric)))),
    CONSTRAINT fiscal_itens_aliq_icms_ck CHECK (((aliq_icms IS NULL) OR ((aliq_icms >= (0)::numeric) AND (aliq_icms <= (100)::numeric)))),
    CONSTRAINT fiscal_itens_aliq_ipi_ck CHECK (((aliq_ipi IS NULL) OR ((aliq_ipi >= (0)::numeric) AND (aliq_ipi <= (100)::numeric)))),
    CONSTRAINT fiscal_itens_aliq_pis_ck CHECK (((aliq_pis IS NULL) OR ((aliq_pis >= (0)::numeric) AND (aliq_pis <= (100)::numeric)))),
    CONSTRAINT fiscal_itens_cofins_credit_ck CHECK (((credita_cofins IS NOT TRUE) OR ((cst_cofins IS NOT NULL) AND (length(TRIM(BOTH FROM cst_cofins)) > 0)))),
    CONSTRAINT fiscal_itens_icms_credit_ck CHECK (((credita_icms IS NOT TRUE) OR ((cst_icms IS NOT NULL) AND (length(TRIM(BOTH FROM cst_icms)) > 0)))),
    CONSTRAINT fiscal_itens_origem_ck CHECK (((origem IS NULL) OR ((origem >= 0) AND (origem <= 8)))),
    CONSTRAINT fiscal_itens_pis_credit_ck CHECK (((credita_pis IS NOT TRUE) OR ((cst_pis IS NOT NULL) AND (length(TRIM(BOTH FROM cst_pis)) > 0))))
);


--
-- Name: fiscal_itens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.fiscal_itens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fiscal_itens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.fiscal_itens_id_seq OWNED BY public.fiscal_itens.id;


--
-- Name: fiscal_regras; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fiscal_regras (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    ncm text,
    cfop text,
    cst_icms text,
    cst_pis text,
    cst_cofins text,
    origem smallint,
    tipo_item text,
    credita_icms boolean DEFAULT false NOT NULL,
    credita_pis boolean DEFAULT false NOT NULL,
    credita_cofins boolean DEFAULT false NOT NULL,
    aliq_icms numeric,
    aliq_pis numeric,
    aliq_cofins numeric,
    prioridade integer DEFAULT 100 NOT NULL,
    descricao text,
    ativo boolean DEFAULT true NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: fornecedores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.fornecedores_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fornecedores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.fornecedores_id_seq OWNED BY public.fornecedores.id;


--
-- Name: hh_especialidades; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hh_especialidades (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    descricao text NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: hh_especialidades_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.hh_especialidades ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.hh_especialidades_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: hh_lancamentos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hh_lancamentos (
    id bigint NOT NULL,
    tenant_id uuid DEFAULT public.current_tenant_id() NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    os_id bigint NOT NULL,
    colaborador_id uuid NOT NULL,
    hh_tipo_id bigint NOT NULL,
    data date NOT NULL,
    hora_entrada time without time zone NOT NULL,
    hora_saida time without time zone NOT NULL,
    horas_trabalhadas numeric(10,2) DEFAULT 0 NOT NULL,
    percentual_aplicado integer DEFAULT 0 NOT NULL,
    valor_hora numeric(10,2) DEFAULT 0 NOT NULL,
    valor_total numeric(10,2) DEFAULT 0 NOT NULL,
    observacao text,
    criado_por text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    hh_especialidade_id uuid,
    entrada_1 time without time zone,
    saida_1 time without time zone,
    entrada_2 time without time zone,
    saida_2 time without time zone,
    hh_servico_id bigint,
    CONSTRAINT hh_lancamentos_percentual_aplicado_check CHECK ((percentual_aplicado = ANY (ARRAY[0, 50, 100]))),
    CONSTRAINT hh_lancamentos_periodos_ck CHECK ((((entrada_1 IS NULL) AND (saida_1 IS NULL) AND (entrada_2 IS NULL) AND (saida_2 IS NULL)) OR ((entrada_1 IS NOT NULL) AND (saida_1 IS NOT NULL) AND (entrada_2 IS NOT NULL) AND (saida_2 IS NOT NULL) AND (saida_1 > entrada_1) AND (saida_2 > entrada_2) AND (saida_1 <= entrada_2))))
);


--
-- Name: TABLE hh_lancamentos; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.hh_lancamentos IS 'Lançamentos de HH por OS (entrada/saída) com tabela negociada';


--
-- Name: COLUMN hh_lancamentos.entrada_1; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.hh_lancamentos.entrada_1 IS 'Entrada período 1 (manhã)';


--
-- Name: COLUMN hh_lancamentos.saida_1; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.hh_lancamentos.saida_1 IS 'Saída período 1 (manhã)';


--
-- Name: COLUMN hh_lancamentos.entrada_2; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.hh_lancamentos.entrada_2 IS 'Entrada período 2 (tarde)';


--
-- Name: COLUMN hh_lancamentos.saida_2; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.hh_lancamentos.saida_2 IS 'Saída período 2 (tarde)';


--
-- Name: hh_lancamentos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hh_lancamentos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hh_lancamentos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hh_lancamentos_id_seq OWNED BY public.hh_lancamentos.id;


--
-- Name: hh_tipos_mapping; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hh_tipos_mapping (
    id bigint NOT NULL,
    tipo_hora_id uuid NOT NULL,
    hh_tipo_id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE hh_tipos_mapping; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.hh_tipos_mapping IS 'Mapeamento entre tipos_horas (UUID) e hh_lancamentos.hh_tipo_id (BIGINT)';


--
-- Name: hh_tipos_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hh_tipos_mapping_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hh_tipos_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hh_tipos_mapping_id_seq OWNED BY public.hh_tipos_mapping.id;


--
-- Name: horas_trabalhadas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.horas_trabalhadas (
    id integer NOT NULL,
    os_id integer NOT NULL,
    profissional_id integer NOT NULL,
    data_trabalho date NOT NULL,
    horas_trabalhadas numeric(5,2) NOT NULL,
    valor_hora numeric(10,2) NOT NULL,
    valor_total numeric(10,2) GENERATED ALWAYS AS ((horas_trabalhadas * valor_hora)) STORED,
    descricao text,
    criado_em timestamp without time zone DEFAULT now()
);


--
-- Name: horas_trabalhadas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.horas_trabalhadas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: horas_trabalhadas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.horas_trabalhadas_id_seq OWNED BY public.horas_trabalhadas.id;


--
-- Name: itens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.itens (
    id integer NOT NULL,
    codigo_interno character varying(50) NOT NULL,
    codigo_barras character varying(50),
    nome character varying(255) NOT NULL,
    descricao text,
    tipo character varying(20) NOT NULL,
    categoria character varying(100),
    subcategoria character varying(100),
    unidade_medida character varying(10) DEFAULT 'UN'::character varying,
    peso_bruto numeric(10,3),
    peso_liquido numeric(10,3),
    controla_estoque boolean DEFAULT false,
    estoque_minimo integer DEFAULT 0,
    estoque_maximo integer DEFAULT 0,
    estoque_ideal integer DEFAULT 0,
    custo_ultima_compra numeric(10,2) DEFAULT 0,
    custo_medio numeric(10,2) DEFAULT 0,
    data_ultima_compra timestamp without time zone,
    preco_unitario numeric(10,2) DEFAULT 0,
    preco_promocional numeric(10,2),
    data_atualizacao_preco timestamp without time zone,
    margem_lucro_percentual numeric(5,2),
    ncm character varying(10),
    cest character varying(10),
    cfop_padrao character varying(10),
    aliquota_icms numeric(5,2),
    aliquota_ipi numeric(5,2),
    aliquota_pis numeric(5,2),
    aliquota_cofins numeric(5,2),
    fornecedor_id integer,
    codigo_fornecedor character varying(50),
    controla_lote boolean DEFAULT false,
    controla_validade boolean DEFAULT false,
    dias_alerta_vencimento integer DEFAULT 30,
    ativo boolean DEFAULT true,
    observacoes text,
    criado_em timestamp without time zone DEFAULT now(),
    criado_por character varying(100),
    atualizado_em timestamp without time zone DEFAULT now(),
    atualizado_por character varying(100),
    fabricante character varying(150),
    tenant_id uuid NOT NULL,
    finalidade public.item_finalidade NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    motivo_compra_id uuid,
    CONSTRAINT itens_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['produto'::character varying, 'servico'::character varying, 'despesa'::character varying])::text[])))
);


--
-- Name: itens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.itens_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: itens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.itens_id_seq OWNED BY public.itens.id;


--
-- Name: lancamentos_contabeis; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lancamentos_contabeis (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    competencia_id uuid,
    data_lancamento date DEFAULT CURRENT_DATE NOT NULL,
    historico text NOT NULL,
    origem_tipo text,
    origem_id text,
    status text DEFAULT 'rascunho'::text NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT lancamentos_contabeis_status_check CHECK ((status = ANY (ARRAY['rascunho'::text, 'confirmado'::text, 'estornado'::text])))
);


--
-- Name: lancamentos_contabeis_itens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lancamentos_contabeis_itens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    lancamento_id uuid NOT NULL,
    conta_id uuid NOT NULL,
    centro_custo_id uuid,
    tipo text NOT NULL,
    valor numeric(18,2) NOT NULL,
    complemento text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT lancamentos_contabeis_itens_tipo_check CHECK ((tipo = ANY (ARRAY['debito'::text, 'credito'::text]))),
    CONSTRAINT lancamentos_contabeis_itens_valor_check CHECK ((valor > (0)::numeric))
);


--
-- Name: membership_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.membership_roles (
    membership_id uuid NOT NULL,
    role_id uuid NOT NULL
);


--
-- Name: movimentacoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.movimentacoes (
    id integer NOT NULL,
    item_id integer NOT NULL,
    tipo text NOT NULL,
    quantidade numeric(14,3) DEFAULT 0 NOT NULL,
    motivo text,
    realizado_por character varying(100),
    data_movimentacao timestamp without time zone DEFAULT now(),
    custo_unitario_bruto numeric(14,6),
    custo_unitario_real numeric(14,6),
    credito_icms numeric(14,2) DEFAULT 0 NOT NULL,
    credito_pis numeric(14,2) DEFAULT 0 NOT NULL,
    credito_cofins numeric(14,2) DEFAULT 0 NOT NULL,
    origem_nf_entrada_id bigint,
    v_ipi numeric(14,2) DEFAULT 0 NOT NULL,
    v_icms numeric(14,2) DEFAULT 0 NOT NULL,
    v_pis numeric(14,2) DEFAULT 0 NOT NULL,
    v_cofins numeric(14,2) DEFAULT 0 NOT NULL,
    v_frete_rateado numeric(14,2) DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    origem_os_id integer,
    CONSTRAINT movimentacoes_empresa_nn_ck CHECK ((empresa_id IS NOT NULL)),
    CONSTRAINT movimentacoes_nf_required_ck CHECK (((origem_nf_entrada_id IS NULL) OR ((tenant_id IS NOT NULL) AND (data_movimentacao IS NOT NULL) AND (tipo = ANY (ARRAY['entrada'::text, 'saida'::text]))))),
    CONSTRAINT movimentacoes_tipo_check CHECK ((tipo = ANY (ARRAY['entrada'::text, 'saida'::text, 'ajuste'::text])))
);


--
-- Name: movimentacoes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.movimentacoes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: movimentacoes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.movimentacoes_id_seq OWNED BY public.movimentacoes.id;


--
-- Name: nf_entrada; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.nf_entrada (
    id bigint NOT NULL,
    chave character varying(60) NOT NULL,
    numero character varying(20),
    serie character varying(10),
    emitente_nome character varying(255),
    emitente_cnpj character varying(20),
    data_emissao timestamp with time zone,
    valor_produtos numeric(14,2) DEFAULT 0 NOT NULL,
    valor_frete numeric(14,2) DEFAULT 0 NOT NULL,
    valor_total numeric(14,2) DEFAULT 0 NOT NULL,
    xml_raw text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    fornecedor_id bigint,
    modelo character varying(10),
    valor_seguro numeric(18,6) DEFAULT 0 NOT NULL,
    valor_desconto numeric(18,6) DEFAULT 0 NOT NULL,
    valor_outros numeric(18,6) DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    finalidade_contexto public.item_finalidade,
    os_id integer,
    baixa_os_automatica boolean DEFAULT false NOT NULL,
    motivo_compra_id uuid,
    solicitante_usuario_id uuid
);


--
-- Name: nf_entrada_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.nf_entrada_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: nf_entrada_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.nf_entrada_id_seq OWNED BY public.nf_entrada.id;


--
-- Name: nf_entrada_itens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.nf_entrada_itens (
    id bigint NOT NULL,
    nf_entrada_id bigint NOT NULL,
    item_id bigint,
    codigo_fornecedor character varying(80),
    descricao text,
    ncm character varying(12),
    cfop character varying(10),
    qtd numeric(14,4) DEFAULT 0 NOT NULL,
    v_unit numeric(14,6) DEFAULT 0 NOT NULL,
    v_prod numeric(14,2) DEFAULT 0 NOT NULL,
    v_icms numeric(14,2) DEFAULT 0 NOT NULL,
    v_ipi numeric(14,2) DEFAULT 0 NOT NULL,
    v_pis numeric(14,2) DEFAULT 0 NOT NULL,
    v_cofins numeric(14,2) DEFAULT 0 NOT NULL,
    aliq_icms numeric(7,4),
    aliq_ipi numeric(7,4),
    aliq_pis numeric(7,4),
    aliq_cofins numeric(7,4),
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    aliquota_icms numeric(12,4),
    aliquota_ipi numeric(12,4),
    aliquota_pis numeric(12,4),
    aliquota_cofins numeric(12,4),
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL
);


--
-- Name: nf_entrada_itens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.nf_entrada_itens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: nf_entrada_itens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.nf_entrada_itens_id_seq OWNED BY public.nf_entrada_itens.id;


--
-- Name: ordens_servico; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ordens_servico (
    id integer NOT NULL,
    numero_os character varying(50) NOT NULL,
    cliente_nome character varying(255) NOT NULL,
    cliente_id integer,
    descricao_servico text,
    status character varying(20) DEFAULT 'aberta'::character varying,
    data_abertura timestamp without time zone DEFAULT now(),
    data_conclusao timestamp without time zone,
    valor_total numeric(12,2) DEFAULT 0,
    observacoes text,
    criado_por character varying(100),
    atualizado_em timestamp without time zone DEFAULT now(),
    os_num bigint NOT NULL,
    pedido_compra text,
    tipo_pedido text,
    vendedor text,
    orcado numeric(12,2) DEFAULT 0,
    custo numeric(12,2) DEFAULT 0,
    tem_gestao boolean DEFAULT false NOT NULL,
    tenant_id uuid NOT NULL,
    usa_relatorio_hh boolean DEFAULT false NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    CONSTRAINT ordens_servico_status_check CHECK (((status)::text = ANY ((ARRAY['aberta'::character varying, 'em_andamento'::character varying, 'concluida'::character varying, 'cancelada'::character varying])::text[]))),
    CONSTRAINT ordens_servico_tipo_pedido_check CHECK ((tipo_pedido = ANY (ARRAY['servico'::text, 'material'::text])))
);


--
-- Name: ordens_servico_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ordens_servico_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ordens_servico_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ordens_servico_id_seq OWNED BY public.ordens_servico.id;


--
-- Name: ordens_servico_os_num_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.ordens_servico ALTER COLUMN os_num ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.ordens_servico_os_num_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: os_gestao_itens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.os_gestao_itens (
    id bigint NOT NULL,
    os_id integer NOT NULL,
    item_tipo public.os_gestao_tipo NOT NULL,
    area public.os_gestao_area NOT NULL,
    habilitado boolean DEFAULT false NOT NULL,
    responsavel_id text,
    data_prevista date,
    progresso_percent integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid DEFAULT public.current_empresa_id() NOT NULL,
    CONSTRAINT os_gestao_itens_progresso_percent_check CHECK (((progresso_percent >= 0) AND (progresso_percent <= 100)))
);


--
-- Name: os_gestao_itens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.os_gestao_itens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: os_gestao_itens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.os_gestao_itens_id_seq OWNED BY public.os_gestao_itens.id;


--
-- Name: os_itens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.os_itens_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: os_itens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.os_itens_id_seq OWNED BY public.os_itens.id;


--
-- Name: permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permissions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    description text
);


--
-- Name: plano_contas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plano_contas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    codigo text NOT NULL,
    descricao text NOT NULL,
    tipo text NOT NULL,
    natureza text NOT NULL,
    parent_id uuid,
    nivel integer,
    ativo boolean DEFAULT true NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT plano_contas_natureza_check CHECK ((natureza = ANY (ARRAY['devedora'::text, 'credora'::text]))),
    CONSTRAINT plano_contas_tipo_check CHECK ((tipo = ANY (ARRAY['ativo'::text, 'passivo'::text, 'patrimonio_liquido'::text, 'receita'::text, 'despesa'::text, 'resultado'::text])))
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    email text,
    nome text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: profissionais; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profissionais (
    id integer NOT NULL,
    nome character varying(255) NOT NULL,
    cpf character varying(14),
    email character varying(100),
    telefone character varying(20),
    valor_hora numeric(10,2) NOT NULL,
    ativo boolean DEFAULT true,
    criado_em timestamp without time zone DEFAULT now(),
    atualizado_em timestamp without time zone DEFAULT now()
);


--
-- Name: profissionais_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.profissionais_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: profissionais_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.profissionais_id_seq OWNED BY public.profissionais.id;


--
-- Name: role_access_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_access_rules (
    role_id uuid NOT NULL,
    resource text NOT NULL,
    action text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: role_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_permissions (
    role text NOT NULL,
    permission text NOT NULL
);


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    name text NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: tenant_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenant_memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    role text DEFAULT 'admin'::text,
    CONSTRAINT tenant_memberships_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'fiscal'::text, 'estoque'::text, 'projetos'::text, 'financeiro'::text])))
);


--
-- Name: tenants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: tipos_horas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tipos_horas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    codigo character varying(30) NOT NULL,
    descricao character varying(120) NOT NULL,
    fator numeric(6,3) DEFAULT 1 NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    tenant_id uuid NOT NULL
);


--
-- Name: user_empresa_context; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_empresa_context (
    user_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    empresa_id uuid NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: user_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_profiles (
    user_id uuid NOT NULL,
    nome text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: user_tenant_context; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_tenant_context (
    user_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: v_creditos_por_periodo; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_creditos_por_periodo AS
 SELECT tenant_id,
    empresa_id,
    (date_trunc('month'::text, data_movimentacao))::date AS competencia,
    sum(COALESCE(credito_icms, (0)::numeric)) AS credito_icms,
    sum(COALESCE(credito_pis, (0)::numeric)) AS credito_pis,
    sum(COALESCE(credito_cofins, (0)::numeric)) AS credito_cofins
   FROM public.movimentacoes m
  WHERE (tipo = 'entrada'::text)
  GROUP BY tenant_id, empresa_id, ((date_trunc('month'::text, data_movimentacao))::date);


--
-- Name: v_item_ultimo_custo; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_item_ultimo_custo AS
 SELECT DISTINCT ON (tenant_id, item_id) tenant_id,
    item_id,
    data_movimentacao,
    origem_nf_entrada_id,
    custo_unitario_bruto,
    custo_unitario_real,
    v_frete_rateado,
    v_ipi,
    v_icms,
    v_pis,
    v_cofins
   FROM public.movimentacoes m
  WHERE (tipo = 'entrada'::text)
  ORDER BY tenant_id, item_id, data_movimentacao DESC, id DESC;


--
-- Name: v_estoque_custo_atual; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_estoque_custo_atual AS
 SELECT e.tenant_id,
    e.item_id,
    e.quantidade_atual,
    u.custo_unitario_real AS custo_atual_unitario,
    (e.quantidade_atual * COALESCE(u.custo_unitario_real, (0)::numeric)) AS custo_total_em_estoque,
    u.data_movimentacao AS data_ultimo_custo,
    u.origem_nf_entrada_id
   FROM (public.estoque e
     LEFT JOIN public.v_item_ultimo_custo u ON (((u.tenant_id = e.tenant_id) AND (u.item_id = e.item_id))));


--
-- Name: v_lancamentos_contabeis_balance; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_lancamentos_contabeis_balance AS
 SELECT l.id AS lancamento_id,
    l.tenant_id,
    l.empresa_id,
    l.status,
    l.data_lancamento,
    l.historico,
    COALESCE(sum(
        CASE
            WHEN (i.tipo = 'debito'::text) THEN i.valor
            ELSE (0)::numeric
        END), (0)::numeric) AS total_debito,
    COALESCE(sum(
        CASE
            WHEN (i.tipo = 'credito'::text) THEN i.valor
            ELSE (0)::numeric
        END), (0)::numeric) AS total_credito,
    (COALESCE(sum(
        CASE
            WHEN (i.tipo = 'debito'::text) THEN i.valor
            ELSE (0)::numeric
        END), (0)::numeric) - COALESCE(sum(
        CASE
            WHEN (i.tipo = 'credito'::text) THEN i.valor
            ELSE (0)::numeric
        END), (0)::numeric)) AS diferenca
   FROM (public.lancamentos_contabeis l
     LEFT JOIN public.lancamentos_contabeis_itens i ON ((i.lancamento_id = l.id)))
  GROUP BY l.id, l.tenant_id, l.empresa_id, l.status, l.data_lancamento, l.historico;


--
-- Name: v_user_permissions; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_user_permissions AS
 SELECT DISTINCT ut.tenant_id,
    rp.permission
   FROM ((a.usuario u
     JOIN a.usuario_tenant ut ON ((ut.usuario_id = u.id)))
     JOIN public.role_permissions rp ON ((rp.role = a.fn_map_papel_tenant_to_role(ut.papel))))
  WHERE ((u.auth_user_id = auth.uid()) AND (ut.deleted_at IS NULL) AND (ut.ativo = true))
UNION
 SELECT DISTINCT e.tenant_id,
    rp.permission
   FROM (((a.usuario u
     JOIN a.usuario_empresa ue ON ((ue.usuario_id = u.id)))
     JOIN c.empresa e ON ((e.id = ue.empresa_id)))
     JOIN public.role_permissions rp ON ((rp.role = a.fn_map_papel_empresa_to_role(ue.papel))))
  WHERE ((u.auth_user_id = auth.uid()) AND (ue.deleted_at IS NULL) AND (ue.ativo = true) AND (e.deleted_at IS NULL));


--
-- Name: vw_apontamentos_horas_custo; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_apontamentos_horas_custo AS
 SELECT a.id AS apontamento_id,
    a.os_id,
    a.colaborador_id,
    c.nome AS colaborador_nome,
    a.data,
    a.horas,
    th.codigo AS tipo_hora_codigo,
    th.descricao AS tipo_hora_descricao,
    COALESCE(a.fator_aplicado, th.fator, (1)::numeric) AS fator,
    tx.valor_hora,
    round(((a.horas * tx.valor_hora) * COALESCE(a.fator_aplicado, th.fator, (1)::numeric)), 2) AS custo_lancamento,
    a.descricao,
    a.status,
    a.criado_em
   FROM (((public.apontamentos_horas a
     JOIN public.colaboradores c ON ((c.id = a.colaborador_id)))
     LEFT JOIN public.tipos_horas th ON ((th.id = a.tipo_hora_id)))
     JOIN LATERAL ( SELECT t.valor_hora
           FROM public.colaborador_taxas t
          WHERE ((t.colaborador_id = a.colaborador_id) AND (a.data >= t.vigencia_inicio) AND ((t.vigencia_fim IS NULL) OR (a.data <= t.vigencia_fim)))
          ORDER BY t.vigencia_inicio DESC, t.criado_em DESC
         LIMIT 1) tx ON (true));


--
-- Name: vw_colaboradores_taxa_atual; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_colaboradores_taxa_atual AS
 SELECT c.id,
    c.nome,
    c.cargo,
    c.ativo,
    c.criado_em,
    tx.id AS taxa_id,
    tx.valor_hora,
    tx.vigencia_inicio,
    tx.vigencia_fim
   FROM (public.colaboradores c
     LEFT JOIN LATERAL ( SELECT t.id,
            t.colaborador_id,
            t.valor_hora,
            t.vigencia_inicio,
            t.vigencia_fim,
            t.criado_em
           FROM public.colaborador_taxas t
          WHERE ((t.colaborador_id = c.id) AND (CURRENT_DATE >= t.vigencia_inicio) AND ((t.vigencia_fim IS NULL) OR (CURRENT_DATE <= t.vigencia_fim)))
          ORDER BY t.vigencia_inicio DESC, t.criado_em DESC
         LIMIT 1) tx ON (true));


--
-- Name: vw_creditos_mensais; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_creditos_mensais AS
 SELECT date_trunc('month'::text, data_movimentacao) AS mes,
    sum(credito_icms) AS credito_icms,
    sum(credito_pis) AS credito_pis,
    sum(credito_cofins) AS credito_cofins
   FROM public.movimentacoes
  WHERE (tipo = 'entrada'::text)
  GROUP BY (date_trunc('month'::text, data_movimentacao))
  ORDER BY (date_trunc('month'::text, data_movimentacao));


--
-- Name: vw_custo_mao_obra_os; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_custo_mao_obra_os AS
 SELECT os_id,
    sum(horas) AS total_horas,
    sum(custo_lancamento) AS custo_mao_obra
   FROM public.vw_apontamentos_horas_custo
  GROUP BY os_id;


--
-- Name: vw_hh_total_os; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_hh_total_os AS
 SELECT tenant_id,
    empresa_id,
    os_id,
    (COALESCE(sum(valor_total), (0)::numeric))::numeric(12,2) AS total_hh
   FROM public.hh_lancamentos
  GROUP BY tenant_id, empresa_id, os_id;


--
-- Name: VIEW vw_hh_total_os; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.vw_hh_total_os IS 'Total de HH (cobrança) por OS.';


--
-- Name: r_i_caixa_custo; Type: VIEW; Schema: r; Owner: -
--

CREATE VIEW r.r_i_caixa_custo AS
 SELECT cx.tenant_id,
    cx.empresa_id,
    cx.id AS caixa_id,
    cx.codigo AS caixa_codigo,
    cx.nome AS caixa_nome,
    (COALESCE(sum((ci.quantidade * f.custo_unit)), (0)::numeric))::numeric(15,2) AS custo_total
   FROM ((c.i_caixa cx
     LEFT JOIN c.i_caixa_item ci ON (((ci.caixa_id = cx.id) AND (ci.deleted_at IS NULL))))
     LEFT JOIN c.i_ferramenta f ON (((f.id = ci.ferramenta_id) AND (f.deleted_at IS NULL))))
  WHERE (cx.deleted_at IS NULL)
  GROUP BY cx.tenant_id, cx.empresa_id, cx.id, cx.codigo, cx.nome;


--
-- Name: messages; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
)
PARTITION BY RANGE (inserted_at);


--
-- Name: schema_migrations; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


--
-- Name: subscription; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.subscription (
    id bigint NOT NULL,
    subscription_id uuid NOT NULL,
    entity regclass NOT NULL,
    filters realtime.user_defined_filter[] DEFAULT '{}'::realtime.user_defined_filter[] NOT NULL,
    claims jsonb NOT NULL,
    claims_role regrole GENERATED ALWAYS AS (realtime.to_regrole((claims ->> 'role'::text))) STORED NOT NULL,
    created_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: subscription_id_seq; Type: SEQUENCE; Schema: realtime; Owner: -
--

ALTER TABLE realtime.subscription ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME realtime.subscription_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: buckets; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.buckets (
    id text NOT NULL,
    name text NOT NULL,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    public boolean DEFAULT false,
    avif_autodetection boolean DEFAULT false,
    file_size_limit bigint,
    allowed_mime_types text[],
    owner_id text,
    type storage.buckettype DEFAULT 'STANDARD'::storage.buckettype NOT NULL
);


--
-- Name: COLUMN buckets.owner; Type: COMMENT; Schema: storage; Owner: -
--

COMMENT ON COLUMN storage.buckets.owner IS 'Field is deprecated, use owner_id instead';


--
-- Name: buckets_analytics; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.buckets_analytics (
    name text NOT NULL,
    type storage.buckettype DEFAULT 'ANALYTICS'::storage.buckettype NOT NULL,
    format text DEFAULT 'ICEBERG'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    deleted_at timestamp with time zone
);


--
-- Name: buckets_vectors; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.buckets_vectors (
    id text NOT NULL,
    type storage.buckettype DEFAULT 'VECTOR'::storage.buckettype NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: migrations; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.migrations (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    hash character varying(40) NOT NULL,
    executed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: objects; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.objects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    bucket_id text,
    name text,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    metadata jsonb,
    path_tokens text[] GENERATED ALWAYS AS (string_to_array(name, '/'::text)) STORED,
    version text,
    owner_id text,
    user_metadata jsonb,
    level integer
);


--
-- Name: COLUMN objects.owner; Type: COMMENT; Schema: storage; Owner: -
--

COMMENT ON COLUMN storage.objects.owner IS 'Field is deprecated, use owner_id instead';


--
-- Name: prefixes; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.prefixes (
    bucket_id text NOT NULL,
    name text NOT NULL COLLATE pg_catalog."C",
    level integer GENERATED ALWAYS AS (storage.get_level(name)) STORED NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: s3_multipart_uploads; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.s3_multipart_uploads (
    id text NOT NULL,
    in_progress_size bigint DEFAULT 0 NOT NULL,
    upload_signature text NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    version text NOT NULL,
    owner_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_metadata jsonb
);


--
-- Name: s3_multipart_uploads_parts; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.s3_multipart_uploads_parts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    upload_id text NOT NULL,
    size bigint DEFAULT 0 NOT NULL,
    part_number integer NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    etag text NOT NULL,
    owner_id text,
    version text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: vector_indexes; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.vector_indexes (
    id text DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL COLLATE pg_catalog."C",
    bucket_id text NOT NULL,
    data_type text NOT NULL,
    dimension integer NOT NULL,
    distance_metric text NOT NULL,
    metadata_configuration jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: refresh_tokens id; Type: DEFAULT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.refresh_tokens ALTER COLUMN id SET DEFAULT nextval('auth.refresh_tokens_id_seq'::regclass);


--
-- Name: audit_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log ALTER COLUMN id SET DEFAULT nextval('public.audit_log_id_seq'::regclass);


--
-- Name: cliente_hh_servicos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cliente_hh_servicos ALTER COLUMN id SET DEFAULT nextval('public.cliente_hh_servicos_id_seq'::regclass);


--
-- Name: clientes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clientes ALTER COLUMN id SET DEFAULT nextval('public.clientes_id_seq'::regclass);


--
-- Name: colaborador_cliente_funcao id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaborador_cliente_funcao ALTER COLUMN id SET DEFAULT nextval('public.colaborador_cliente_funcao_id_seq'::regclass);


--
-- Name: empresa_memberships id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_memberships ALTER COLUMN id SET DEFAULT nextval('public.empresa_memberships_id_seq'::regclass);


--
-- Name: estoque id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estoque ALTER COLUMN id SET DEFAULT nextval('public.estoque_id_seq'::regclass);


--
-- Name: fiscal_itens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_itens ALTER COLUMN id SET DEFAULT nextval('public.fiscal_itens_id_seq'::regclass);


--
-- Name: fornecedores id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fornecedores ALTER COLUMN id SET DEFAULT nextval('public.fornecedores_id_seq'::regclass);


--
-- Name: hh_lancamentos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hh_lancamentos ALTER COLUMN id SET DEFAULT nextval('public.hh_lancamentos_id_seq'::regclass);


--
-- Name: hh_tipos_mapping id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hh_tipos_mapping ALTER COLUMN id SET DEFAULT nextval('public.hh_tipos_mapping_id_seq'::regclass);


--
-- Name: horas_trabalhadas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.horas_trabalhadas ALTER COLUMN id SET DEFAULT nextval('public.horas_trabalhadas_id_seq'::regclass);


--
-- Name: itens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.itens ALTER COLUMN id SET DEFAULT nextval('public.itens_id_seq'::regclass);


--
-- Name: movimentacoes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimentacoes ALTER COLUMN id SET DEFAULT nextval('public.movimentacoes_id_seq'::regclass);


--
-- Name: nf_entrada id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nf_entrada ALTER COLUMN id SET DEFAULT nextval('public.nf_entrada_id_seq'::regclass);


--
-- Name: nf_entrada_itens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nf_entrada_itens ALTER COLUMN id SET DEFAULT nextval('public.nf_entrada_itens_id_seq'::regclass);


--
-- Name: ordens_servico id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ordens_servico ALTER COLUMN id SET DEFAULT nextval('public.ordens_servico_id_seq'::regclass);


--
-- Name: os_gestao_itens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_gestao_itens ALTER COLUMN id SET DEFAULT nextval('public.os_gestao_itens_id_seq'::regclass);


--
-- Name: os_itens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_itens ALTER COLUMN id SET DEFAULT nextval('public.os_itens_id_seq'::regclass);


--
-- Name: profissionais id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profissionais ALTER COLUMN id SET DEFAULT nextval('public.profissionais_id_seq'::regclass);


--
-- Name: usuario pk_a_usuario; Type: CONSTRAINT; Schema: a; Owner: -
--

ALTER TABLE ONLY a.usuario
    ADD CONSTRAINT pk_a_usuario PRIMARY KEY (id);


--
-- Name: usuario_empresa pk_a_usuario_empresa; Type: CONSTRAINT; Schema: a; Owner: -
--

ALTER TABLE ONLY a.usuario_empresa
    ADD CONSTRAINT pk_a_usuario_empresa PRIMARY KEY (id);


--
-- Name: usuario_tenant pk_a_usuario_tenant; Type: CONSTRAINT; Schema: a; Owner: -
--

ALTER TABLE ONLY a.usuario_tenant
    ADD CONSTRAINT pk_a_usuario_tenant PRIMARY KEY (id);


--
-- Name: usuario uq_usuario__auth_user_id; Type: CONSTRAINT; Schema: a; Owner: -
--

ALTER TABLE ONLY a.usuario
    ADD CONSTRAINT uq_usuario__auth_user_id UNIQUE (auth_user_id);


--
-- Name: usuario uq_usuario__email; Type: CONSTRAINT; Schema: a; Owner: -
--

ALTER TABLE ONLY a.usuario
    ADD CONSTRAINT uq_usuario__email UNIQUE (email);


--
-- Name: mfa_amr_claims amr_id_pk; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT amr_id_pk PRIMARY KEY (id);


--
-- Name: audit_log_entries audit_log_entries_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.audit_log_entries
    ADD CONSTRAINT audit_log_entries_pkey PRIMARY KEY (id);


--
-- Name: flow_state flow_state_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.flow_state
    ADD CONSTRAINT flow_state_pkey PRIMARY KEY (id);


--
-- Name: identities identities_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_pkey PRIMARY KEY (id);


--
-- Name: identities identities_provider_id_provider_unique; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_provider_id_provider_unique UNIQUE (provider_id, provider);


--
-- Name: instances instances_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.instances
    ADD CONSTRAINT instances_pkey PRIMARY KEY (id);


--
-- Name: mfa_amr_claims mfa_amr_claims_session_id_authentication_method_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT mfa_amr_claims_session_id_authentication_method_pkey UNIQUE (session_id, authentication_method);


--
-- Name: mfa_challenges mfa_challenges_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_challenges
    ADD CONSTRAINT mfa_challenges_pkey PRIMARY KEY (id);


--
-- Name: mfa_factors mfa_factors_last_challenged_at_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_last_challenged_at_key UNIQUE (last_challenged_at);


--
-- Name: mfa_factors mfa_factors_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_pkey PRIMARY KEY (id);


--
-- Name: oauth_authorizations oauth_authorizations_authorization_code_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_authorization_code_key UNIQUE (authorization_code);


--
-- Name: oauth_authorizations oauth_authorizations_authorization_id_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_authorization_id_key UNIQUE (authorization_id);


--
-- Name: oauth_authorizations oauth_authorizations_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_pkey PRIMARY KEY (id);


--
-- Name: oauth_client_states oauth_client_states_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_client_states
    ADD CONSTRAINT oauth_client_states_pkey PRIMARY KEY (id);


--
-- Name: oauth_clients oauth_clients_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_clients
    ADD CONSTRAINT oauth_clients_pkey PRIMARY KEY (id);


--
-- Name: oauth_consents oauth_consents_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_pkey PRIMARY KEY (id);


--
-- Name: oauth_consents oauth_consents_user_client_unique; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_user_client_unique UNIQUE (user_id, client_id);


--
-- Name: one_time_tokens one_time_tokens_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.one_time_tokens
    ADD CONSTRAINT one_time_tokens_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_token_unique; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_token_unique UNIQUE (token);


--
-- Name: saml_providers saml_providers_entity_id_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_entity_id_key UNIQUE (entity_id);


--
-- Name: saml_providers saml_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_pkey PRIMARY KEY (id);


--
-- Name: saml_relay_states saml_relay_states_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: sso_domains sso_domains_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sso_domains
    ADD CONSTRAINT sso_domains_pkey PRIMARY KEY (id);


--
-- Name: sso_providers sso_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sso_providers
    ADD CONSTRAINT sso_providers_pkey PRIMARY KEY (id);


--
-- Name: users users_phone_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_phone_key UNIQUE (phone);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: i_caixa_item i_caixa_item_pkey; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_caixa_item
    ADD CONSTRAINT i_caixa_item_pkey PRIMARY KEY (id);


--
-- Name: i_caixa i_caixa_pkey; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_caixa
    ADD CONSTRAINT i_caixa_pkey PRIMARY KEY (id);


--
-- Name: i_caixa_vinculo i_caixa_vinculo_pkey; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_caixa_vinculo
    ADD CONSTRAINT i_caixa_vinculo_pkey PRIMARY KEY (id);


--
-- Name: i_ferramenta_categoria i_ferramenta_categoria_pkey; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_ferramenta_categoria
    ADD CONSTRAINT i_ferramenta_categoria_pkey PRIMARY KEY (id);


--
-- Name: i_ferramenta i_ferramenta_pkey; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_ferramenta
    ADD CONSTRAINT i_ferramenta_pkey PRIMARY KEY (id);


--
-- Name: i_ferramenta_sugestao_xml i_ferramenta_sugestao_xml_pkey; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_ferramenta_sugestao_xml
    ADD CONSTRAINT i_ferramenta_sugestao_xml_pkey PRIMARY KEY (id);


--
-- Name: i_ferramenta_unidade i_ferramenta_unidade_pkey; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_ferramenta_unidade
    ADD CONSTRAINT i_ferramenta_unidade_pkey PRIMARY KEY (id);


--
-- Name: i_ferramenta_unidade_vinculo i_ferramenta_unidade_vinculo_pkey; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_ferramenta_unidade_vinculo
    ADD CONSTRAINT i_ferramenta_unidade_vinculo_pkey PRIMARY KEY (id);


--
-- Name: empresa pk_c_empresa; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.empresa
    ADD CONSTRAINT pk_c_empresa PRIMARY KEY (id);


--
-- Name: empresa_endereco pk_c_empresa_endereco; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.empresa_endereco
    ADD CONSTRAINT pk_c_empresa_endereco PRIMARY KEY (id);


--
-- Name: empresa_fiscal pk_c_empresa_fiscal; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.empresa_fiscal
    ADD CONSTRAINT pk_c_empresa_fiscal PRIMARY KEY (id);


--
-- Name: tenant pk_c_tenant; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.tenant
    ADD CONSTRAINT pk_c_tenant PRIMARY KEY (id);


--
-- Name: i_ferramenta_codigo_seq pk_i_ferr_codigo_seq; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_ferramenta_codigo_seq
    ADD CONSTRAINT pk_i_ferr_codigo_seq PRIMARY KEY (tenant_id, empresa_id, categoria_id);


--
-- Name: i_caixa uq_i_caixa__tenant_empresa_codigo; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_caixa
    ADD CONSTRAINT uq_i_caixa__tenant_empresa_codigo UNIQUE (tenant_id, empresa_id, codigo);


--
-- Name: i_caixa_item uq_i_caixa_item__tenant_empresa_caixa_ferr; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_caixa_item
    ADD CONSTRAINT uq_i_caixa_item__tenant_empresa_caixa_ferr UNIQUE (tenant_id, empresa_id, caixa_id, ferramenta_id);


--
-- Name: i_ferramenta_categoria uq_i_ferr_cat__tenant_empresa_nome; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_ferramenta_categoria
    ADD CONSTRAINT uq_i_ferr_cat__tenant_empresa_nome UNIQUE (tenant_id, empresa_id, nome);


--
-- Name: i_ferramenta_categoria uq_i_ferr_cat__tenant_empresa_prefixo; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_ferramenta_categoria
    ADD CONSTRAINT uq_i_ferr_cat__tenant_empresa_prefixo UNIQUE (tenant_id, empresa_id, prefixo);


--
-- Name: i_ferramenta_unidade uq_i_ferr_unid__tenant_empresa_patrimonio; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_ferramenta_unidade
    ADD CONSTRAINT uq_i_ferr_unid__tenant_empresa_patrimonio UNIQUE (tenant_id, empresa_id, patrimonio_codigo);


--
-- Name: i_ferramenta uq_i_ferramenta__tenant_empresa_codigo; Type: CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_ferramenta
    ADD CONSTRAINT uq_i_ferramenta__tenant_empresa_codigo UNIQUE (tenant_id, empresa_id, codigo);


--
-- Name: anexo pk_f_anexo; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.anexo
    ADD CONSTRAINT pk_f_anexo PRIMARY KEY (id);


--
-- Name: aprovacao_evento pk_f_aprovacao_evento; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.aprovacao_evento
    ADD CONSTRAINT pk_f_aprovacao_evento PRIMARY KEY (id);


--
-- Name: centro_custo pk_f_centro_custo; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.centro_custo
    ADD CONSTRAINT pk_f_centro_custo PRIMARY KEY (id);


--
-- Name: conciliacao_bancaria pk_f_conciliacao_bancaria; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.conciliacao_bancaria
    ADD CONSTRAINT pk_f_conciliacao_bancaria PRIMARY KEY (id);


--
-- Name: conciliacao_lancamento pk_f_conciliacao_lancamento; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.conciliacao_lancamento
    ADD CONSTRAINT pk_f_conciliacao_lancamento PRIMARY KEY (id);


--
-- Name: conta_bancaria pk_f_conta_bancaria; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.conta_bancaria
    ADD CONSTRAINT pk_f_conta_bancaria PRIMARY KEY (id);


--
-- Name: documento_fiscal pk_f_documento_fiscal; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.documento_fiscal
    ADD CONSTRAINT pk_f_documento_fiscal PRIMARY KEY (id);


--
-- Name: documento_fiscal_xml pk_f_documento_fiscal_xml; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.documento_fiscal_xml
    ADD CONSTRAINT pk_f_documento_fiscal_xml PRIMARY KEY (id);


--
-- Name: evento_financeiro pk_f_evento_financeiro; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.evento_financeiro
    ADD CONSTRAINT pk_f_evento_financeiro PRIMARY KEY (id);


--
-- Name: extrato_bancario pk_f_extrato_bancario; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.extrato_bancario
    ADD CONSTRAINT pk_f_extrato_bancario PRIMARY KEY (id);


--
-- Name: extrato_bancario_linha pk_f_extrato_bancario_linha; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.extrato_bancario_linha
    ADD CONSTRAINT pk_f_extrato_bancario_linha PRIMARY KEY (id);


--
-- Name: fin_config pk_f_fin_config; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.fin_config
    ADD CONSTRAINT pk_f_fin_config PRIMARY KEY (id);


--
-- Name: importacao_doc_log pk_f_importacao_doc_log; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.importacao_doc_log
    ADD CONSTRAINT pk_f_importacao_doc_log PRIMARY KEY (id);


--
-- Name: imposto_retencao pk_f_imposto_retencao; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.imposto_retencao
    ADD CONSTRAINT pk_f_imposto_retencao PRIMARY KEY (id);


--
-- Name: motivo_compra pk_f_motivo_compra; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.motivo_compra
    ADD CONSTRAINT pk_f_motivo_compra PRIMARY KEY (id);


--
-- Name: pagamento pk_f_pagamento; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.pagamento
    ADD CONSTRAINT pk_f_pagamento PRIMARY KEY (id);


--
-- Name: pagamento_item pk_f_pagamento_item; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.pagamento_item
    ADD CONSTRAINT pk_f_pagamento_item PRIMARY KEY (id);


--
-- Name: parametro_financeiro_empresa pk_f_parametro_financeiro_empresa; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.parametro_financeiro_empresa
    ADD CONSTRAINT pk_f_parametro_financeiro_empresa PRIMARY KEY (id);


--
-- Name: plano_contas pk_f_plano_contas; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.plano_contas
    ADD CONSTRAINT pk_f_plano_contas PRIMARY KEY (id);


--
-- Name: titulo pk_f_titulo; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo
    ADD CONSTRAINT pk_f_titulo PRIMARY KEY (id);


--
-- Name: titulo_agendamento pk_f_titulo_agendamento; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_agendamento
    ADD CONSTRAINT pk_f_titulo_agendamento PRIMARY KEY (id);


--
-- Name: titulo_aprovacao pk_f_titulo_aprovacao; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_aprovacao
    ADD CONSTRAINT pk_f_titulo_aprovacao PRIMARY KEY (id);


--
-- Name: titulo_parcela pk_f_titulo_parcela; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_parcela
    ADD CONSTRAINT pk_f_titulo_parcela PRIMARY KEY (id);


--
-- Name: titulo_rateio pk_f_titulo_rateio; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_rateio
    ADD CONSTRAINT pk_f_titulo_rateio PRIMARY KEY (id);


--
-- Name: titulo titulo_classificacao_obrigatoria_chk; Type: CHECK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE f.titulo
    ADD CONSTRAINT titulo_classificacao_obrigatoria_chk CHECK ((classificacao_id IS NOT NULL)) NOT VALID;


--
-- Name: titulo_rateio titulo_rateio_plano_contas_obrigatorio; Type: CHECK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE f.titulo_rateio
    ADD CONSTRAINT titulo_rateio_plano_contas_obrigatorio CHECK ((plano_contas_id IS NOT NULL)) NOT VALID;


--
-- Name: centro_custo uq_centro_custo__tenant_empresa_codigo; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.centro_custo
    ADD CONSTRAINT uq_centro_custo__tenant_empresa_codigo UNIQUE (tenant_id, empresa_id, codigo);


--
-- Name: conta_bancaria uq_conta_bancaria__tenant_empresa_codigo; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.conta_bancaria
    ADD CONSTRAINT uq_conta_bancaria__tenant_empresa_codigo UNIQUE (tenant_id, empresa_id, codigo);


--
-- Name: documento_fiscal uq_documento_fiscal__tenant_chave; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.documento_fiscal
    ADD CONSTRAINT uq_documento_fiscal__tenant_chave UNIQUE (tenant_id, chave_acesso);


--
-- Name: documento_fiscal uq_documento_fiscal__tenant_source_nf; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.documento_fiscal
    ADD CONSTRAINT uq_documento_fiscal__tenant_source_nf UNIQUE (tenant_id, source_nf_entrada_id);


--
-- Name: documento_fiscal_xml uq_documento_fiscal_xml__tenant_doc; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.documento_fiscal_xml
    ADD CONSTRAINT uq_documento_fiscal_xml__tenant_doc UNIQUE (tenant_id, documento_fiscal_id);


--
-- Name: fin_config uq_fin_config__tenant_empresa; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.fin_config
    ADD CONSTRAINT uq_fin_config__tenant_empresa UNIQUE (tenant_id, empresa_id);


--
-- Name: motivo_compra uq_motivo_compra__tenant_codigo; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.motivo_compra
    ADD CONSTRAINT uq_motivo_compra__tenant_codigo UNIQUE (tenant_id, codigo);


--
-- Name: motivo_compra uq_motivo_compra__tenant_nome; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.motivo_compra
    ADD CONSTRAINT uq_motivo_compra__tenant_nome UNIQUE (tenant_id, nome);


--
-- Name: pagamento_item uq_pagamento_item__tenant_pagamento_parcela; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.pagamento_item
    ADD CONSTRAINT uq_pagamento_item__tenant_pagamento_parcela UNIQUE (tenant_id, pagamento_id, titulo_parcela_id);


--
-- Name: parametro_financeiro_empresa uq_param_fin_emp__tenant_empresa; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.parametro_financeiro_empresa
    ADD CONSTRAINT uq_param_fin_emp__tenant_empresa UNIQUE (tenant_id, empresa_id);


--
-- Name: plano_contas uq_plano_contas__tenant_codigo; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.plano_contas
    ADD CONSTRAINT uq_plano_contas__tenant_codigo UNIQUE (tenant_id, codigo);


--
-- Name: titulo_agendamento uq_titulo_agendamento__tenant_titulo; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_agendamento
    ADD CONSTRAINT uq_titulo_agendamento__tenant_titulo UNIQUE (tenant_id, titulo_id);


--
-- Name: titulo_aprovacao uq_titulo_aprovacao__tenant_titulo; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_aprovacao
    ADD CONSTRAINT uq_titulo_aprovacao__tenant_titulo UNIQUE (tenant_id, titulo_id);


--
-- Name: titulo_parcela uq_titulo_parcela__tenant_titulo_numero; Type: CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_parcela
    ADD CONSTRAINT uq_titulo_parcela__tenant_titulo_numero UNIQUE (tenant_id, titulo_id, numero);


--
-- Name: apontamentos_horas apontamentos_horas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apontamentos_horas
    ADD CONSTRAINT apontamentos_horas_pkey PRIMARY KEY (id);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: centros_custo centros_custo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.centros_custo
    ADD CONSTRAINT centros_custo_pkey PRIMARY KEY (id);


--
-- Name: centros_custo centros_custo_tenant_empresa_codigo_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.centros_custo
    ADD CONSTRAINT centros_custo_tenant_empresa_codigo_uk UNIQUE (tenant_id, empresa_id, codigo);


--
-- Name: cliente_hh_servicos cliente_hh_servicos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cliente_hh_servicos
    ADD CONSTRAINT cliente_hh_servicos_pkey PRIMARY KEY (id);


--
-- Name: cliente_hh_tabelas cliente_hh_tabelas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cliente_hh_tabelas
    ADD CONSTRAINT cliente_hh_tabelas_pkey PRIMARY KEY (id);


--
-- Name: cliente_hh_tabelas cliente_hh_tabelas_tenant_cliente_ano_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cliente_hh_tabelas
    ADD CONSTRAINT cliente_hh_tabelas_tenant_cliente_ano_uk UNIQUE (tenant_id, cliente_id, ano);


--
-- Name: clientes clientes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clientes
    ADD CONSTRAINT clientes_pkey PRIMARY KEY (id);


--
-- Name: colaborador_cliente_funcao colaborador_cliente_funcao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaborador_cliente_funcao
    ADD CONSTRAINT colaborador_cliente_funcao_pkey PRIMARY KEY (id);


--
-- Name: colaborador_funcao_hh colaborador_funcao_hh_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaborador_funcao_hh
    ADD CONSTRAINT colaborador_funcao_hh_pkey PRIMARY KEY (id);


--
-- Name: colaborador_funcao_hh colaborador_funcao_hh_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaborador_funcao_hh
    ADD CONSTRAINT colaborador_funcao_hh_unique UNIQUE (tenant_id, cliente_id, colaborador_id, servico_hh_id);


--
-- Name: colaborador_taxas colaborador_taxas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaborador_taxas
    ADD CONSTRAINT colaborador_taxas_pkey PRIMARY KEY (id);


--
-- Name: colaboradores colaboradores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaboradores
    ADD CONSTRAINT colaboradores_pkey PRIMARY KEY (id);


--
-- Name: competencias competencias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.competencias
    ADD CONSTRAINT competencias_pkey PRIMARY KEY (id);


--
-- Name: competencias competencias_tenant_empresa_ano_mes_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.competencias
    ADD CONSTRAINT competencias_tenant_empresa_ano_mes_uk UNIQUE (tenant_id, empresa_id, ano, mes);


--
-- Name: empresa_memberships empresa_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_memberships
    ADD CONSTRAINT empresa_memberships_pkey PRIMARY KEY (id);


--
-- Name: empresa_memberships empresa_memberships_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_memberships
    ADD CONSTRAINT empresa_memberships_unique UNIQUE (tenant_id, empresa_id, user_id);


--
-- Name: empresas empresas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresas
    ADD CONSTRAINT empresas_pkey PRIMARY KEY (id);


--
-- Name: estoque estoque_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estoque
    ADD CONSTRAINT estoque_pkey PRIMARY KEY (id);


--
-- Name: estoque estoque_tenant_empresa_item_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estoque
    ADD CONSTRAINT estoque_tenant_empresa_item_key UNIQUE (tenant_id, empresa_id, item_id);


--
-- Name: feriados feriados_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feriados
    ADD CONSTRAINT feriados_pkey PRIMARY KEY (id);


--
-- Name: feriados feriados_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feriados
    ADD CONSTRAINT feriados_uk UNIQUE (data, abrangencia);


--
-- Name: fiscal_itens fiscal_itens_item_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_itens
    ADD CONSTRAINT fiscal_itens_item_id_key UNIQUE (item_id);


--
-- Name: fiscal_itens fiscal_itens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_itens
    ADD CONSTRAINT fiscal_itens_pkey PRIMARY KEY (id);


--
-- Name: fiscal_itens fiscal_itens_tenant_empresa_item_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_itens
    ADD CONSTRAINT fiscal_itens_tenant_empresa_item_uk UNIQUE (tenant_id, empresa_id, item_id);


--
-- Name: fiscal_regras fiscal_regras_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_regras
    ADD CONSTRAINT fiscal_regras_pkey PRIMARY KEY (id);


--
-- Name: fornecedores fornecedores_cnpj_digits_len_chk; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.fornecedores
    ADD CONSTRAINT fornecedores_cnpj_digits_len_chk CHECK (((cnpj_digits = ''::text) OR (length(cnpj_digits) = 14))) NOT VALID;


--
-- Name: fornecedores fornecedores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fornecedores
    ADD CONSTRAINT fornecedores_pkey PRIMARY KEY (id);


--
-- Name: hh_especialidades hh_especialidades_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hh_especialidades
    ADD CONSTRAINT hh_especialidades_pkey PRIMARY KEY (id);


--
-- Name: hh_lancamentos hh_lancamentos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hh_lancamentos
    ADD CONSTRAINT hh_lancamentos_pkey PRIMARY KEY (id);


--
-- Name: hh_tipos_mapping hh_tipos_mapping_hh_tipo_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hh_tipos_mapping
    ADD CONSTRAINT hh_tipos_mapping_hh_tipo_id_key UNIQUE (hh_tipo_id);


--
-- Name: hh_tipos_mapping hh_tipos_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hh_tipos_mapping
    ADD CONSTRAINT hh_tipos_mapping_pkey PRIMARY KEY (id);


--
-- Name: hh_tipos_mapping hh_tipos_mapping_tipo_hora_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hh_tipos_mapping
    ADD CONSTRAINT hh_tipos_mapping_tipo_hora_id_key UNIQUE (tipo_hora_id);


--
-- Name: horas_trabalhadas horas_trabalhadas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.horas_trabalhadas
    ADD CONSTRAINT horas_trabalhadas_pkey PRIMARY KEY (id);


--
-- Name: itens itens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.itens
    ADD CONSTRAINT itens_pkey PRIMARY KEY (id);


--
-- Name: itens itens_tenant_codigo_interno_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.itens
    ADD CONSTRAINT itens_tenant_codigo_interno_uk UNIQUE (tenant_id, codigo_interno);


--
-- Name: itens itens_tenant_id_id_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.itens
    ADD CONSTRAINT itens_tenant_id_id_uk UNIQUE (tenant_id, id);


--
-- Name: lancamentos_contabeis_itens lancamentos_contabeis_itens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lancamentos_contabeis_itens
    ADD CONSTRAINT lancamentos_contabeis_itens_pkey PRIMARY KEY (id);


--
-- Name: lancamentos_contabeis lancamentos_contabeis_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lancamentos_contabeis
    ADD CONSTRAINT lancamentos_contabeis_pkey PRIMARY KEY (id);


--
-- Name: membership_roles membership_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_roles
    ADD CONSTRAINT membership_roles_pkey PRIMARY KEY (membership_id, role_id);


--
-- Name: movimentacoes movimentacoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimentacoes
    ADD CONSTRAINT movimentacoes_pkey PRIMARY KEY (id);


--
-- Name: nf_entrada nf_entrada_chave_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nf_entrada
    ADD CONSTRAINT nf_entrada_chave_key UNIQUE (chave);


--
-- Name: nf_entrada_itens nf_entrada_itens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nf_entrada_itens
    ADD CONSTRAINT nf_entrada_itens_pkey PRIMARY KEY (id);


--
-- Name: nf_entrada nf_entrada_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nf_entrada
    ADD CONSTRAINT nf_entrada_pkey PRIMARY KEY (id);


--
-- Name: nf_entrada nf_entrada_tenant_id_id_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nf_entrada
    ADD CONSTRAINT nf_entrada_tenant_id_id_uk UNIQUE (tenant_id, id);


--
-- Name: ordens_servico ordens_servico_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ordens_servico
    ADD CONSTRAINT ordens_servico_pkey PRIMARY KEY (id);


--
-- Name: ordens_servico ordens_servico_tenant_id_id_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ordens_servico
    ADD CONSTRAINT ordens_servico_tenant_id_id_uk UNIQUE (tenant_id, id);


--
-- Name: ordens_servico ordens_servico_tenant_numero_os_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ordens_servico
    ADD CONSTRAINT ordens_servico_tenant_numero_os_uk UNIQUE (tenant_id, numero_os);


--
-- Name: os_gestao_itens os_gestao_itens_os_id_item_tipo_area_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_gestao_itens
    ADD CONSTRAINT os_gestao_itens_os_id_item_tipo_area_key UNIQUE (os_id, item_tipo, area);


--
-- Name: os_gestao_itens os_gestao_itens_os_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_gestao_itens
    ADD CONSTRAINT os_gestao_itens_os_key UNIQUE (os_id, item_tipo, area);


--
-- Name: os_gestao_itens os_gestao_itens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_gestao_itens
    ADD CONSTRAINT os_gestao_itens_pkey PRIMARY KEY (id);


--
-- Name: os_itens os_itens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_itens
    ADD CONSTRAINT os_itens_pkey PRIMARY KEY (id);


--
-- Name: permissions permissions_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_code_key UNIQUE (code);


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (id);


--
-- Name: plano_contas plano_contas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plano_contas
    ADD CONSTRAINT plano_contas_pkey PRIMARY KEY (id);


--
-- Name: plano_contas plano_contas_tenant_empresa_codigo_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plano_contas
    ADD CONSTRAINT plano_contas_tenant_empresa_codigo_uk UNIQUE (tenant_id, empresa_id, codigo);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: profissionais profissionais_cpf_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profissionais
    ADD CONSTRAINT profissionais_cpf_key UNIQUE (cpf);


--
-- Name: profissionais profissionais_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profissionais
    ADD CONSTRAINT profissionais_pkey PRIMARY KEY (id);


--
-- Name: role_access_rules role_access_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_access_rules
    ADD CONSTRAINT role_access_rules_pkey PRIMARY KEY (role_id, resource, action);


--
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role, permission);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: roles roles_tenant_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_tenant_id_name_key UNIQUE (tenant_id, name);


--
-- Name: tenant_memberships tenant_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_memberships
    ADD CONSTRAINT tenant_memberships_pkey PRIMARY KEY (id);


--
-- Name: tenant_memberships tenant_memberships_tenant_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_memberships
    ADD CONSTRAINT tenant_memberships_tenant_id_user_id_key UNIQUE (tenant_id, user_id);


--
-- Name: tenant_memberships tenant_memberships_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_memberships
    ADD CONSTRAINT tenant_memberships_unique UNIQUE (tenant_id, user_id);


--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);


--
-- Name: hh_tipos_mapping tipos_horas_mapping_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hh_tipos_mapping
    ADD CONSTRAINT tipos_horas_mapping_uk UNIQUE (tenant_id, tipo_hora_id);


--
-- Name: tipos_horas tipos_horas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipos_horas
    ADD CONSTRAINT tipos_horas_pkey PRIMARY KEY (id);


--
-- Name: tipos_horas tipos_horas_tenant_codigo_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipos_horas
    ADD CONSTRAINT tipos_horas_tenant_codigo_uk UNIQUE (tenant_id, codigo);


--
-- Name: cliente_hh_servicos uk_cliente_hh_servicos_nome; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cliente_hh_servicos
    ADD CONSTRAINT uk_cliente_hh_servicos_nome UNIQUE (tenant_id, empresa_id, cliente_id, nome);


--
-- Name: colaborador_cliente_funcao unique_colab_cliente_funcao; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaborador_cliente_funcao
    ADD CONSTRAINT unique_colab_cliente_funcao UNIQUE (tenant_id, cliente_id, colaborador_id, hh_servico_id);


--
-- Name: user_empresa_context user_empresa_context_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_empresa_context
    ADD CONSTRAINT user_empresa_context_pkey PRIMARY KEY (user_id, tenant_id);


--
-- Name: user_profiles user_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_pkey PRIMARY KEY (user_id);


--
-- Name: user_tenant_context user_tenant_context_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_tenant_context
    ADD CONSTRAINT user_tenant_context_pkey PRIMARY KEY (user_id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: subscription pk_subscription; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.subscription
    ADD CONSTRAINT pk_subscription PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: buckets_analytics buckets_analytics_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.buckets_analytics
    ADD CONSTRAINT buckets_analytics_pkey PRIMARY KEY (id);


--
-- Name: buckets buckets_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.buckets
    ADD CONSTRAINT buckets_pkey PRIMARY KEY (id);


--
-- Name: buckets_vectors buckets_vectors_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.buckets_vectors
    ADD CONSTRAINT buckets_vectors_pkey PRIMARY KEY (id);


--
-- Name: migrations migrations_name_key; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_name_key UNIQUE (name);


--
-- Name: migrations migrations_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_pkey PRIMARY KEY (id);


--
-- Name: objects objects_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT objects_pkey PRIMARY KEY (id);


--
-- Name: prefixes prefixes_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.prefixes
    ADD CONSTRAINT prefixes_pkey PRIMARY KEY (bucket_id, level, name);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_pkey PRIMARY KEY (id);


--
-- Name: s3_multipart_uploads s3_multipart_uploads_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_pkey PRIMARY KEY (id);


--
-- Name: vector_indexes vector_indexes_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.vector_indexes
    ADD CONSTRAINT vector_indexes_pkey PRIMARY KEY (id);


--
-- Name: idx_usuario_empresa__empresa_id; Type: INDEX; Schema: a; Owner: -
--

CREATE INDEX idx_usuario_empresa__empresa_id ON a.usuario_empresa USING btree (empresa_id);


--
-- Name: idx_usuario_tenant__tenant_id; Type: INDEX; Schema: a; Owner: -
--

CREATE INDEX idx_usuario_tenant__tenant_id ON a.usuario_tenant USING btree (tenant_id);


--
-- Name: uq_usuario_empresa__usuario_id__empresa_id; Type: INDEX; Schema: a; Owner: -
--

CREATE UNIQUE INDEX uq_usuario_empresa__usuario_id__empresa_id ON a.usuario_empresa USING btree (usuario_id, empresa_id) WHERE (deleted_at IS NULL);


--
-- Name: uq_usuario_empresa__usuario_id__empresa_id__active; Type: INDEX; Schema: a; Owner: -
--

CREATE UNIQUE INDEX uq_usuario_empresa__usuario_id__empresa_id__active ON a.usuario_empresa USING btree (usuario_id, empresa_id) WHERE (deleted_at IS NULL);


--
-- Name: uq_usuario_tenant__usuario_id__tenant_id; Type: INDEX; Schema: a; Owner: -
--

CREATE UNIQUE INDEX uq_usuario_tenant__usuario_id__tenant_id ON a.usuario_tenant USING btree (usuario_id, tenant_id) WHERE (deleted_at IS NULL);


--
-- Name: uq_usuario_tenant__usuario_id__tenant_id__active; Type: INDEX; Schema: a; Owner: -
--

CREATE UNIQUE INDEX uq_usuario_tenant__usuario_id__tenant_id__active ON a.usuario_tenant USING btree (usuario_id, tenant_id) WHERE (deleted_at IS NULL);


--
-- Name: audit_logs_instance_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX audit_logs_instance_id_idx ON auth.audit_log_entries USING btree (instance_id);


--
-- Name: confirmation_token_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX confirmation_token_idx ON auth.users USING btree (confirmation_token) WHERE ((confirmation_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: email_change_token_current_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX email_change_token_current_idx ON auth.users USING btree (email_change_token_current) WHERE ((email_change_token_current)::text !~ '^[0-9 ]*$'::text);


--
-- Name: email_change_token_new_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX email_change_token_new_idx ON auth.users USING btree (email_change_token_new) WHERE ((email_change_token_new)::text !~ '^[0-9 ]*$'::text);


--
-- Name: factor_id_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX factor_id_created_at_idx ON auth.mfa_factors USING btree (user_id, created_at);


--
-- Name: flow_state_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX flow_state_created_at_idx ON auth.flow_state USING btree (created_at DESC);


--
-- Name: identities_email_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX identities_email_idx ON auth.identities USING btree (email text_pattern_ops);


--
-- Name: INDEX identities_email_idx; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON INDEX auth.identities_email_idx IS 'Auth: Ensures indexed queries on the email column';


--
-- Name: identities_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX identities_user_id_idx ON auth.identities USING btree (user_id);


--
-- Name: idx_auth_code; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_auth_code ON auth.flow_state USING btree (auth_code);


--
-- Name: idx_oauth_client_states_created_at; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_oauth_client_states_created_at ON auth.oauth_client_states USING btree (created_at);


--
-- Name: idx_user_id_auth_method; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_user_id_auth_method ON auth.flow_state USING btree (user_id, authentication_method);


--
-- Name: mfa_challenge_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX mfa_challenge_created_at_idx ON auth.mfa_challenges USING btree (created_at DESC);


--
-- Name: mfa_factors_user_friendly_name_unique; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX mfa_factors_user_friendly_name_unique ON auth.mfa_factors USING btree (friendly_name, user_id) WHERE (TRIM(BOTH FROM friendly_name) <> ''::text);


--
-- Name: mfa_factors_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX mfa_factors_user_id_idx ON auth.mfa_factors USING btree (user_id);


--
-- Name: oauth_auth_pending_exp_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_auth_pending_exp_idx ON auth.oauth_authorizations USING btree (expires_at) WHERE (status = 'pending'::auth.oauth_authorization_status);


--
-- Name: oauth_clients_deleted_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_clients_deleted_at_idx ON auth.oauth_clients USING btree (deleted_at);


--
-- Name: oauth_consents_active_client_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_consents_active_client_idx ON auth.oauth_consents USING btree (client_id) WHERE (revoked_at IS NULL);


--
-- Name: oauth_consents_active_user_client_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_consents_active_user_client_idx ON auth.oauth_consents USING btree (user_id, client_id) WHERE (revoked_at IS NULL);


--
-- Name: oauth_consents_user_order_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_consents_user_order_idx ON auth.oauth_consents USING btree (user_id, granted_at DESC);


--
-- Name: one_time_tokens_relates_to_hash_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX one_time_tokens_relates_to_hash_idx ON auth.one_time_tokens USING hash (relates_to);


--
-- Name: one_time_tokens_token_hash_hash_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX one_time_tokens_token_hash_hash_idx ON auth.one_time_tokens USING hash (token_hash);


--
-- Name: one_time_tokens_user_id_token_type_key; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX one_time_tokens_user_id_token_type_key ON auth.one_time_tokens USING btree (user_id, token_type);


--
-- Name: reauthentication_token_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX reauthentication_token_idx ON auth.users USING btree (reauthentication_token) WHERE ((reauthentication_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: recovery_token_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX recovery_token_idx ON auth.users USING btree (recovery_token) WHERE ((recovery_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: refresh_tokens_instance_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_instance_id_idx ON auth.refresh_tokens USING btree (instance_id);


--
-- Name: refresh_tokens_instance_id_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_instance_id_user_id_idx ON auth.refresh_tokens USING btree (instance_id, user_id);


--
-- Name: refresh_tokens_parent_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_parent_idx ON auth.refresh_tokens USING btree (parent);


--
-- Name: refresh_tokens_session_id_revoked_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_session_id_revoked_idx ON auth.refresh_tokens USING btree (session_id, revoked);


--
-- Name: refresh_tokens_updated_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_updated_at_idx ON auth.refresh_tokens USING btree (updated_at DESC);


--
-- Name: saml_providers_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX saml_providers_sso_provider_id_idx ON auth.saml_providers USING btree (sso_provider_id);


--
-- Name: saml_relay_states_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX saml_relay_states_created_at_idx ON auth.saml_relay_states USING btree (created_at DESC);


--
-- Name: saml_relay_states_for_email_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX saml_relay_states_for_email_idx ON auth.saml_relay_states USING btree (for_email);


--
-- Name: saml_relay_states_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX saml_relay_states_sso_provider_id_idx ON auth.saml_relay_states USING btree (sso_provider_id);


--
-- Name: sessions_not_after_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sessions_not_after_idx ON auth.sessions USING btree (not_after DESC);


--
-- Name: sessions_oauth_client_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sessions_oauth_client_id_idx ON auth.sessions USING btree (oauth_client_id);


--
-- Name: sessions_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sessions_user_id_idx ON auth.sessions USING btree (user_id);


--
-- Name: sso_domains_domain_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX sso_domains_domain_idx ON auth.sso_domains USING btree (lower(domain));


--
-- Name: sso_domains_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sso_domains_sso_provider_id_idx ON auth.sso_domains USING btree (sso_provider_id);


--
-- Name: sso_providers_resource_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX sso_providers_resource_id_idx ON auth.sso_providers USING btree (lower(resource_id));


--
-- Name: sso_providers_resource_id_pattern_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sso_providers_resource_id_pattern_idx ON auth.sso_providers USING btree (resource_id text_pattern_ops);


--
-- Name: unique_phone_factor_per_user; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX unique_phone_factor_per_user ON auth.mfa_factors USING btree (user_id, phone);


--
-- Name: user_id_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX user_id_created_at_idx ON auth.sessions USING btree (user_id, created_at);


--
-- Name: users_email_partial_key; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX users_email_partial_key ON auth.users USING btree (email) WHERE (is_sso_user = false);


--
-- Name: INDEX users_email_partial_key; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON INDEX auth.users_email_partial_key IS 'Auth: A partial unique index that applies only when is_sso_user is false';


--
-- Name: users_instance_id_email_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX users_instance_id_email_idx ON auth.users USING btree (instance_id, lower((email)::text));


--
-- Name: users_instance_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX users_instance_id_idx ON auth.users USING btree (instance_id);


--
-- Name: users_is_anonymous_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX users_is_anonymous_idx ON auth.users USING btree (is_anonymous);


--
-- Name: idx_empresa__tenant_id; Type: INDEX; Schema: c; Owner: -
--

CREATE INDEX idx_empresa__tenant_id ON c.empresa USING btree (tenant_id);


--
-- Name: idx_empresa_endereco__empresa_id; Type: INDEX; Schema: c; Owner: -
--

CREATE INDEX idx_empresa_endereco__empresa_id ON c.empresa_endereco USING btree (empresa_id);


--
-- Name: idx_i_caixa_vinculo__tenant_empresa_caixa_ativo; Type: INDEX; Schema: c; Owner: -
--

CREATE INDEX idx_i_caixa_vinculo__tenant_empresa_caixa_ativo ON c.i_caixa_vinculo USING btree (tenant_id, empresa_id, caixa_id) WHERE ((data_fim IS NULL) AND (deleted_at IS NULL));


--
-- Name: idx_i_ferr_sug_xml__tenant_empresa_status; Type: INDEX; Schema: c; Owner: -
--

CREATE INDEX idx_i_ferr_sug_xml__tenant_empresa_status ON c.i_ferramenta_sugestao_xml USING btree (tenant_id, empresa_id, status) WHERE (deleted_at IS NULL);


--
-- Name: idx_i_ferr_unid__tenant_empresa_ferr; Type: INDEX; Schema: c; Owner: -
--

CREATE INDEX idx_i_ferr_unid__tenant_empresa_ferr ON c.i_ferramenta_unidade USING btree (tenant_id, empresa_id, ferramenta_id) WHERE (deleted_at IS NULL);


--
-- Name: idx_i_ferr_unid__tenant_empresa_status; Type: INDEX; Schema: c; Owner: -
--

CREATE INDEX idx_i_ferr_unid__tenant_empresa_status ON c.i_ferramenta_unidade USING btree (tenant_id, empresa_id, status) WHERE (deleted_at IS NULL);


--
-- Name: idx_i_ferr_unid_vinc__tenant_empresa_unidade_ativo; Type: INDEX; Schema: c; Owner: -
--

CREATE INDEX idx_i_ferr_unid_vinc__tenant_empresa_unidade_ativo ON c.i_ferramenta_unidade_vinculo USING btree (tenant_id, empresa_id, ferramenta_unidade_id) WHERE ((data_fim IS NULL) AND (deleted_at IS NULL));


--
-- Name: uq_empresa__tenant_id__cnpj; Type: INDEX; Schema: c; Owner: -
--

CREATE UNIQUE INDEX uq_empresa__tenant_id__cnpj ON c.empresa USING btree (tenant_id, cnpj) WHERE ((deleted_at IS NULL) AND (cnpj IS NOT NULL));


--
-- Name: uq_empresa__tenant_id__codigo; Type: INDEX; Schema: c; Owner: -
--

CREATE UNIQUE INDEX uq_empresa__tenant_id__codigo ON c.empresa USING btree (tenant_id, codigo) WHERE (deleted_at IS NULL);


--
-- Name: uq_empresa_endereco__empresa_id__tipo; Type: INDEX; Schema: c; Owner: -
--

CREATE UNIQUE INDEX uq_empresa_endereco__empresa_id__tipo ON c.empresa_endereco USING btree (empresa_id, tipo) WHERE (deleted_at IS NULL);


--
-- Name: uq_empresa_fiscal__empresa_id; Type: INDEX; Schema: c; Owner: -
--

CREATE UNIQUE INDEX uq_empresa_fiscal__empresa_id ON c.empresa_fiscal USING btree (empresa_id) WHERE (deleted_at IS NULL);


--
-- Name: uq_tenant__codigo; Type: INDEX; Schema: c; Owner: -
--

CREATE UNIQUE INDEX uq_tenant__codigo ON c.tenant USING btree (codigo) WHERE (deleted_at IS NULL);


--
-- Name: uq_tenant__nome; Type: INDEX; Schema: c; Owner: -
--

CREATE UNIQUE INDEX uq_tenant__nome ON c.tenant USING btree (nome) WHERE (deleted_at IS NULL);


--
-- Name: idx_centro_custo__tenant_empresa_parent; Type: INDEX; Schema: f; Owner: -
--

CREATE INDEX idx_centro_custo__tenant_empresa_parent ON f.centro_custo USING btree (tenant_id, empresa_id, parent_id);


--
-- Name: idx_conciliacao__tenant_empresa_conta; Type: INDEX; Schema: f; Owner: -
--

CREATE INDEX idx_conciliacao__tenant_empresa_conta ON f.conciliacao_bancaria USING btree (tenant_id, empresa_id, conta_bancaria_id);


--
-- Name: idx_conta_bancaria__tenant_empresa_ativo; Type: INDEX; Schema: f; Owner: -
--

CREATE INDEX idx_conta_bancaria__tenant_empresa_ativo ON f.conta_bancaria USING btree (tenant_id, empresa_id, ativo);


--
-- Name: idx_documento_fiscal__tenant_empresa; Type: INDEX; Schema: f; Owner: -
--

CREATE INDEX idx_documento_fiscal__tenant_empresa ON f.documento_fiscal USING btree (tenant_id, empresa_id);


--
-- Name: idx_documento_fiscal__tenant_fornecedor; Type: INDEX; Schema: f; Owner: -
--

CREATE INDEX idx_documento_fiscal__tenant_fornecedor ON f.documento_fiscal USING btree (tenant_id, fornecedor_id);


--
-- Name: idx_evento_financeiro__tenant_empresa_created; Type: INDEX; Schema: f; Owner: -
--

CREATE INDEX idx_evento_financeiro__tenant_empresa_created ON f.evento_financeiro USING btree (tenant_id, empresa_id, created_at DESC);


--
-- Name: idx_extrato_bancario__tenant_empresa_conta; Type: INDEX; Schema: f; Owner: -
--

CREATE INDEX idx_extrato_bancario__tenant_empresa_conta ON f.extrato_bancario USING btree (tenant_id, empresa_id, conta_bancaria_id);


--
-- Name: idx_extrato_linha__tenant_conta_data; Type: INDEX; Schema: f; Owner: -
--

CREATE INDEX idx_extrato_linha__tenant_conta_data ON f.extrato_bancario_linha USING btree (tenant_id, conta_bancaria_id, data_movimento);


--
-- Name: idx_extrato_linha__tenant_extrato; Type: INDEX; Schema: f; Owner: -
--

CREATE INDEX idx_extrato_linha__tenant_extrato ON f.extrato_bancario_linha USING btree (tenant_id, extrato_bancario_id);


--
-- Name: idx_motivo_compra__tenant_aplica_em; Type: INDEX; Schema: f; Owner: -
--

CREATE INDEX idx_motivo_compra__tenant_aplica_em ON f.motivo_compra USING btree (tenant_id, aplica_em) WHERE (deleted_at IS NULL);


--
-- Name: idx_motivo_compra__tenant_ativo; Type: INDEX; Schema: f; Owner: -
--

CREATE INDEX idx_motivo_compra__tenant_ativo ON f.motivo_compra USING btree (tenant_id, ativo);


--
-- Name: idx_plano_contas__tenant_parent; Type: INDEX; Schema: f; Owner: -
--

CREATE INDEX idx_plano_contas__tenant_parent ON f.plano_contas USING btree (tenant_id, parent_id);


--
-- Name: idx_titulo__tenant_empresa_status; Type: INDEX; Schema: f; Owner: -
--

CREATE INDEX idx_titulo__tenant_empresa_status ON f.titulo USING btree (tenant_id, empresa_id, status);


--
-- Name: idx_titulo_agendamento__tenant_titulo; Type: INDEX; Schema: f; Owner: -
--

CREATE INDEX idx_titulo_agendamento__tenant_titulo ON f.titulo_agendamento USING btree (tenant_id, titulo_id);


--
-- Name: idx_titulo_parcela__tenant_titulo; Type: INDEX; Schema: f; Owner: -
--

CREATE INDEX idx_titulo_parcela__tenant_titulo ON f.titulo_parcela USING btree (tenant_id, titulo_id);


--
-- Name: uq_conciliacao__tenant_extrato_linha; Type: INDEX; Schema: f; Owner: -
--

CREATE UNIQUE INDEX uq_conciliacao__tenant_extrato_linha ON f.conciliacao_bancaria USING btree (tenant_id, extrato_linha_id) WHERE (deleted_at IS NULL);


--
-- Name: uq_conciliacao__tenant_pagamento; Type: INDEX; Schema: f; Owner: -
--

CREATE UNIQUE INDEX uq_conciliacao__tenant_pagamento ON f.conciliacao_bancaria USING btree (tenant_id, pagamento_id) WHERE (deleted_at IS NULL);


--
-- Name: uq_extrato_linha__tenant_conta_fitid; Type: INDEX; Schema: f; Owner: -
--

CREATE UNIQUE INDEX uq_extrato_linha__tenant_conta_fitid ON f.extrato_bancario_linha USING btree (tenant_id, conta_bancaria_id, fit_id) WHERE ((fit_id IS NOT NULL) AND (deleted_at IS NULL));


--
-- Name: apontamentos_colab_data_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX apontamentos_colab_data_idx ON public.apontamentos_horas USING btree (colaborador_id, data);


--
-- Name: apontamentos_data_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX apontamentos_data_idx ON public.apontamentos_horas USING btree (data);


--
-- Name: apontamentos_horas_hh_especialidade_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX apontamentos_horas_hh_especialidade_id_idx ON public.apontamentos_horas USING btree (hh_especialidade_id);


--
-- Name: apontamentos_horas_tenant_empresa_id_ux; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX apontamentos_horas_tenant_empresa_id_ux ON public.apontamentos_horas USING btree (tenant_id, empresa_id, id);


--
-- Name: apontamentos_horas_tenant_empresa_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX apontamentos_horas_tenant_empresa_idx ON public.apontamentos_horas USING btree (tenant_id, empresa_id);


--
-- Name: apontamentos_horas_tenant_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX apontamentos_horas_tenant_id_idx ON public.apontamentos_horas USING btree (tenant_id);


--
-- Name: apontamentos_os_data_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX apontamentos_os_data_idx ON public.apontamentos_horas USING btree (os_id, data);


--
-- Name: audit_log_table_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_table_created_idx ON public.audit_log USING btree (table_name, created_at DESC);


--
-- Name: audit_log_tenant_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_tenant_created_idx ON public.audit_log USING btree (tenant_id, created_at DESC);


--
-- Name: cliente_hh_tabelas_cliente_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cliente_hh_tabelas_cliente_id_idx ON public.cliente_hh_tabelas USING btree (cliente_id);


--
-- Name: cliente_hh_tabelas_tenant_empresa_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cliente_hh_tabelas_tenant_empresa_idx ON public.cliente_hh_tabelas USING btree (tenant_id, empresa_id);


--
-- Name: cliente_hh_tabelas_tenant_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cliente_hh_tabelas_tenant_id_idx ON public.cliente_hh_tabelas USING btree (tenant_id);


--
-- Name: clientes_tenant_empresa_id_ux; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX clientes_tenant_empresa_id_ux ON public.clientes USING btree (tenant_id, empresa_id, id);


--
-- Name: clientes_tenant_empresa_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX clientes_tenant_empresa_idx ON public.clientes USING btree (tenant_id, empresa_id);


--
-- Name: clientes_tenant_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX clientes_tenant_id_idx ON public.clientes USING btree (tenant_id);


--
-- Name: colaborador_cliente_funcao_tenant_empresa_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX colaborador_cliente_funcao_tenant_empresa_idx ON public.colaborador_cliente_funcao USING btree (tenant_id, empresa_id);


--
-- Name: colaborador_funcao_hh_tenant_empresa_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX colaborador_funcao_hh_tenant_empresa_idx ON public.colaborador_funcao_hh USING btree (tenant_id, empresa_id);


--
-- Name: colaborador_taxas_lookup_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX colaborador_taxas_lookup_idx ON public.colaborador_taxas USING btree (colaborador_id, vigencia_inicio, vigencia_fim);


--
-- Name: colaborador_taxas_tenant_empresa_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX colaborador_taxas_tenant_empresa_idx ON public.colaborador_taxas USING btree (tenant_id, empresa_id);


--
-- Name: colaborador_taxas_tenant_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX colaborador_taxas_tenant_id_idx ON public.colaborador_taxas USING btree (tenant_id);


--
-- Name: colaboradores_hh_especialidade_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX colaboradores_hh_especialidade_id_idx ON public.colaboradores USING btree (hh_especialidade_id);


--
-- Name: colaboradores_nome_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX colaboradores_nome_idx ON public.colaboradores USING btree (nome);


--
-- Name: colaboradores_tenant_empresa_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX colaboradores_tenant_empresa_idx ON public.colaboradores USING btree (tenant_id, empresa_id);


--
-- Name: colaboradores_tenant_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX colaboradores_tenant_id_idx ON public.colaboradores USING btree (tenant_id);


--
-- Name: empresas_tenant_ativo_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX empresas_tenant_ativo_idx ON public.empresas USING btree (tenant_id, ativo);


--
-- Name: empresas_tenant_cnpj_uk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX empresas_tenant_cnpj_uk ON public.empresas USING btree (tenant_id, cnpj);


--
-- Name: feriados_data_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX feriados_data_idx ON public.feriados USING btree (data);


--
-- Name: fiscal_itens_tenant_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX fiscal_itens_tenant_id_idx ON public.fiscal_itens USING btree (tenant_id);


--
-- Name: fornecedores_documento_norm_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX fornecedores_documento_norm_uniq ON public.fornecedores USING btree (documento_norm) WHERE (documento_norm <> ''::text);


--
-- Name: fornecedores_tenant_documento_key_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX fornecedores_tenant_documento_key_uidx ON public.fornecedores USING btree (tenant_id, documento_key) WHERE (documento_key <> ''::text);


--
-- Name: fornecedores_tenant_documento_norm_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX fornecedores_tenant_documento_norm_uidx ON public.fornecedores USING btree (tenant_id, documento_norm);


--
-- Name: fornecedores_tenant_documento_norm_uk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX fornecedores_tenant_documento_norm_uk ON public.fornecedores USING btree (tenant_id, documento_norm) WHERE ((documento_norm IS NOT NULL) AND (length(TRIM(BOTH FROM documento_norm)) > 0));


--
-- Name: fornecedores_tenant_empresa_cnpj_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX fornecedores_tenant_empresa_cnpj_uq ON public.fornecedores USING btree (tenant_id, empresa_id, cnpj_digits) WHERE (cnpj_digits <> ''::text);


--
-- Name: fornecedores_tenant_empresa_id_ux; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX fornecedores_tenant_empresa_id_ux ON public.fornecedores USING btree (tenant_id, empresa_id, id);


--
-- Name: fornecedores_tenant_empresa_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX fornecedores_tenant_empresa_idx ON public.fornecedores USING btree (tenant_id, empresa_id);


--
-- Name: fornecedores_tenant_finalidade_padrao_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX fornecedores_tenant_finalidade_padrao_idx ON public.fornecedores USING btree (tenant_id, finalidade_padrao);


--
-- Name: fornecedores_tenant_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX fornecedores_tenant_id_idx ON public.fornecedores USING btree (tenant_id);


--
-- Name: fornecedores_unique_cnpj; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX fornecedores_unique_cnpj ON public.fornecedores USING btree (tenant_id, empresa_id, cnpj_norm) WHERE (cnpj_norm IS NOT NULL);


--
-- Name: fornecedores_unique_docnorm; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX fornecedores_unique_docnorm ON public.fornecedores USING btree (tenant_id, empresa_id, documento_norm) WHERE ((documento_norm IS NOT NULL) AND (documento_norm <> ''::text));


--
-- Name: hh_especialidades_tenant_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hh_especialidades_tenant_id_idx ON public.hh_especialidades USING btree (tenant_id);


--
-- Name: hh_lancamentos_hh_especialidade_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hh_lancamentos_hh_especialidade_id_idx ON public.hh_lancamentos USING btree (hh_especialidade_id);


--
-- Name: hh_tipos_mapping_tenant_tipo_hora_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hh_tipos_mapping_tenant_tipo_hora_uidx ON public.hh_tipos_mapping USING btree (tenant_id, tipo_hora_id);


--
-- Name: hh_tipos_mapping_tenant_tipo_hora_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hh_tipos_mapping_tenant_tipo_hora_uq ON public.hh_tipos_mapping USING btree (tenant_id, tipo_hora_id);


--
-- Name: idx_apontamentos_horas_hh_lancamento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_apontamentos_horas_hh_lancamento ON public.apontamentos_horas USING btree (hh_lancamento_id) WHERE (hh_lancamento_id IS NOT NULL);


--
-- Name: idx_centros_custo_tenant_empresa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_centros_custo_tenant_empresa ON public.centros_custo USING btree (tenant_id, empresa_id);


--
-- Name: idx_cliente_hh_servicos_ativo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cliente_hh_servicos_ativo ON public.cliente_hh_servicos USING btree (ativo) WHERE (ativo = true);


--
-- Name: idx_cliente_hh_servicos_cliente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cliente_hh_servicos_cliente ON public.cliente_hh_servicos USING btree (cliente_id);


--
-- Name: idx_cliente_hh_servicos_tenant_empresa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cliente_hh_servicos_tenant_empresa ON public.cliente_hh_servicos USING btree (tenant_id, empresa_id);


--
-- Name: idx_clientes_ativo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_clientes_ativo ON public.clientes USING btree (ativo);


--
-- Name: idx_clientes_habilita_hh; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_clientes_habilita_hh ON public.clientes USING btree (habilita_hh);


--
-- Name: idx_clientes_nome; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_clientes_nome ON public.clientes USING btree (nome);


--
-- Name: idx_colaborador_cliente_funcao_ativo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_colaborador_cliente_funcao_ativo ON public.colaborador_cliente_funcao USING btree (ativo) WHERE (ativo = true);


--
-- Name: idx_colaborador_cliente_funcao_cliente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_colaborador_cliente_funcao_cliente ON public.colaborador_cliente_funcao USING btree (tenant_id, cliente_id);


--
-- Name: idx_colaborador_cliente_funcao_colab; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_colaborador_cliente_funcao_colab ON public.colaborador_cliente_funcao USING btree (tenant_id, colaborador_id);


--
-- Name: idx_colaborador_cliente_funcao_colaborador; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_colaborador_cliente_funcao_colaborador ON public.colaborador_cliente_funcao USING btree (tenant_id, colaborador_id);


--
-- Name: idx_colaborador_cliente_funcao_servico; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_colaborador_cliente_funcao_servico ON public.colaborador_cliente_funcao USING btree (tenant_id, hh_servico_id);


--
-- Name: idx_colaborador_cliente_funcao_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_colaborador_cliente_funcao_tenant ON public.colaborador_cliente_funcao USING btree (tenant_id);


--
-- Name: idx_colaborador_funcao_hh_cliente_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_colaborador_funcao_hh_cliente_id ON public.colaborador_funcao_hh USING btree (cliente_id);


--
-- Name: idx_colaborador_funcao_hh_colaborador_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_colaborador_funcao_hh_colaborador_id ON public.colaborador_funcao_hh USING btree (colaborador_id);


--
-- Name: idx_colaborador_funcao_hh_servico_hh_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_colaborador_funcao_hh_servico_hh_id ON public.colaborador_funcao_hh USING btree (servico_hh_id);


--
-- Name: idx_colaborador_funcao_hh_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_colaborador_funcao_hh_tenant_id ON public.colaborador_funcao_hh USING btree (tenant_id);


--
-- Name: idx_competencias_tenant_empresa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_competencias_tenant_empresa ON public.competencias USING btree (tenant_id, empresa_id);


--
-- Name: idx_empresa_memberships_empresa_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_empresa_memberships_empresa_user ON public.empresa_memberships USING btree (empresa_id, user_id);


--
-- Name: idx_empresa_memberships_tenant_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_empresa_memberships_tenant_user ON public.empresa_memberships USING btree (tenant_id, user_id);


--
-- Name: idx_estoque_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_estoque_item ON public.estoque USING btree (item_id);


--
-- Name: idx_fiscal_itens_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fiscal_itens_item ON public.fiscal_itens USING btree (item_id);


--
-- Name: idx_fiscal_itens_tenant_empresa_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fiscal_itens_tenant_empresa_item ON public.fiscal_itens USING btree (tenant_id, empresa_id, item_id);


--
-- Name: idx_fiscal_regras_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fiscal_regras_lookup ON public.fiscal_regras USING btree (tenant_id, empresa_id, ativo, prioridade);


--
-- Name: idx_fiscal_regras_tenant_empresa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fiscal_regras_tenant_empresa ON public.fiscal_regras USING btree (tenant_id, empresa_id);


--
-- Name: idx_fornecedores__tenant_motivo_compra_padrao; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fornecedores__tenant_motivo_compra_padrao ON public.fornecedores USING btree (tenant_id, motivo_compra_padrao_id);


--
-- Name: idx_fornecedores_ativo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fornecedores_ativo ON public.fornecedores USING btree (ativo);


--
-- Name: idx_fornecedores_nome; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fornecedores_nome ON public.fornecedores USING btree (nome);


--
-- Name: idx_hh_lancamentos_colaborador; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hh_lancamentos_colaborador ON public.hh_lancamentos USING btree (colaborador_id);


--
-- Name: idx_hh_lancamentos_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hh_lancamentos_data ON public.hh_lancamentos USING btree (data);


--
-- Name: idx_hh_lancamentos_empresa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hh_lancamentos_empresa ON public.hh_lancamentos USING btree (empresa_id);


--
-- Name: idx_hh_lancamentos_hh_servico_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hh_lancamentos_hh_servico_id ON public.hh_lancamentos USING btree (hh_servico_id);


--
-- Name: idx_hh_lancamentos_os; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hh_lancamentos_os ON public.hh_lancamentos USING btree (os_id);


--
-- Name: idx_hh_lancamentos_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hh_lancamentos_tenant ON public.hh_lancamentos USING btree (tenant_id);


--
-- Name: idx_hh_tipos_mapping_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hh_tipos_mapping_tenant ON public.hh_tipos_mapping USING btree (tenant_id);


--
-- Name: idx_hh_tipos_mapping_tipo_hora; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hh_tipos_mapping_tipo_hora ON public.hh_tipos_mapping USING btree (tipo_hora_id);


--
-- Name: idx_horas_os; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_horas_os ON public.horas_trabalhadas USING btree (os_id);


--
-- Name: idx_horas_profissional; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_horas_profissional ON public.horas_trabalhadas USING btree (profissional_id);


--
-- Name: idx_itens_ativo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_itens_ativo ON public.itens USING btree (ativo);


--
-- Name: idx_itens_categoria; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_itens_categoria ON public.itens USING btree (categoria);


--
-- Name: idx_itens_codigo_barras; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_itens_codigo_barras ON public.itens USING btree (codigo_barras);


--
-- Name: idx_itens_fabricante; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_itens_fabricante ON public.itens USING btree (fabricante);


--
-- Name: idx_itens_fornecedor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_itens_fornecedor_id ON public.itens USING btree (fornecedor_id);


--
-- Name: idx_itens_tipo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_itens_tipo ON public.itens USING btree (tipo);


--
-- Name: idx_lanc_cont_itens_conta; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lanc_cont_itens_conta ON public.lancamentos_contabeis_itens USING btree (conta_id);


--
-- Name: idx_lanc_cont_itens_lanc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lanc_cont_itens_lanc ON public.lancamentos_contabeis_itens USING btree (lancamento_id);


--
-- Name: idx_lanc_cont_tenant_empresa_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lanc_cont_tenant_empresa_data ON public.lancamentos_contabeis USING btree (tenant_id, empresa_id, data_lancamento);


--
-- Name: idx_memberships_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memberships_tenant ON public.tenant_memberships USING btree (tenant_id);


--
-- Name: idx_memberships_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memberships_user ON public.tenant_memberships USING btree (user_id);


--
-- Name: idx_mov_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mov_created_at ON public.movimentacoes USING btree (created_at);


--
-- Name: idx_mov_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mov_data ON public.movimentacoes USING btree (data_movimentacao);


--
-- Name: idx_mov_nf_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mov_nf_data ON public.movimentacoes USING btree (origem_nf_entrada_id, data_movimentacao);


--
-- Name: idx_mov_origem_nf; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mov_origem_nf ON public.movimentacoes USING btree (origem_nf_entrada_id);


--
-- Name: idx_mov_origem_os; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mov_origem_os ON public.movimentacoes USING btree (origem_os_id);


--
-- Name: idx_movimentacoes_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_movimentacoes_item ON public.movimentacoes USING btree (item_id);


--
-- Name: idx_movimentacoes_tipo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_movimentacoes_tipo ON public.movimentacoes USING btree (tipo);


--
-- Name: idx_nf_entrada__tenant_empresa_motivo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_nf_entrada__tenant_empresa_motivo ON public.nf_entrada USING btree (tenant_id, empresa_id, motivo_compra_id);


--
-- Name: idx_nf_entrada__tenant_empresa_solicitante_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_nf_entrada__tenant_empresa_solicitante_usuario ON public.nf_entrada USING btree (tenant_id, empresa_id, solicitante_usuario_id);


--
-- Name: idx_nf_entrada_data_emissao; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_nf_entrada_data_emissao ON public.nf_entrada USING btree (data_emissao);


--
-- Name: idx_nf_entrada_fornecedor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_nf_entrada_fornecedor ON public.nf_entrada USING btree (fornecedor_id);


--
-- Name: idx_nf_entrada_itens_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_nf_entrada_itens_item ON public.nf_entrada_itens USING btree (item_id);


--
-- Name: idx_nf_itens_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_nf_itens_item ON public.nf_entrada_itens USING btree (item_id);


--
-- Name: idx_nf_itens_nf; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_nf_itens_nf ON public.nf_entrada_itens USING btree (nf_entrada_id);


--
-- Name: idx_os_cliente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_os_cliente ON public.ordens_servico USING btree (cliente_id);


--
-- Name: idx_os_cliente_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_os_cliente_id ON public.ordens_servico USING btree (cliente_id);


--
-- Name: idx_os_gestao_itens_osid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_os_gestao_itens_osid ON public.os_gestao_itens USING btree (os_id);


--
-- Name: idx_os_itens_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_os_itens_item ON public.os_itens USING btree (item_id);


--
-- Name: idx_os_itens_os; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_os_itens_os ON public.os_itens USING btree (os_id);


--
-- Name: idx_os_numero; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_os_numero ON public.ordens_servico USING btree (numero_os);


--
-- Name: idx_os_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_os_status ON public.ordens_servico USING btree (status);


--
-- Name: idx_plano_contas_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_plano_contas_parent ON public.plano_contas USING btree (parent_id);


--
-- Name: idx_plano_contas_tenant_empresa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_plano_contas_tenant_empresa ON public.plano_contas USING btree (tenant_id, empresa_id);


--
-- Name: idx_profissionais_ativo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profissionais_ativo ON public.profissionais USING btree (ativo);


--
-- Name: idx_roles_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roles_tenant ON public.roles USING btree (tenant_id);


--
-- Name: idx_user_empresa_context_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_empresa_context_tenant ON public.user_empresa_context USING btree (tenant_id);


--
-- Name: idx_user_empresa_context_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_empresa_context_user ON public.user_empresa_context USING btree (user_id);


--
-- Name: itens_tenant_codigo_barras_uk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX itens_tenant_codigo_barras_uk ON public.itens USING btree (tenant_id, codigo_barras) WHERE ((codigo_barras IS NOT NULL) AND (length(TRIM(BOTH FROM codigo_barras)) > 0));


--
-- Name: itens_tenant_empresa_id_ux; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX itens_tenant_empresa_id_ux ON public.itens USING btree (tenant_id, empresa_id, id);


--
-- Name: itens_tenant_empresa_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX itens_tenant_empresa_idx ON public.itens USING btree (tenant_id, empresa_id);


--
-- Name: itens_tenant_empresa_motivo_compra_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX itens_tenant_empresa_motivo_compra_idx ON public.itens USING btree (tenant_id, empresa_id, motivo_compra_id);


--
-- Name: itens_tenant_finalidade_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX itens_tenant_finalidade_idx ON public.itens USING btree (tenant_id, finalidade);


--
-- Name: movimentacoes_origem_os_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX movimentacoes_origem_os_id_idx ON public.movimentacoes USING btree (tenant_id, empresa_id, origem_os_id) WHERE (origem_os_id IS NOT NULL);


--
-- Name: movimentacoes_tenant_data_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX movimentacoes_tenant_data_idx ON public.movimentacoes USING btree (tenant_id, data_movimentacao);


--
-- Name: movimentacoes_tenant_data_movimentacao_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX movimentacoes_tenant_data_movimentacao_idx ON public.movimentacoes USING btree (tenant_id, data_movimentacao);


--
-- Name: movimentacoes_tenant_empresa_data_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX movimentacoes_tenant_empresa_data_idx ON public.movimentacoes USING btree (tenant_id, empresa_id, data_movimentacao);


--
-- Name: movimentacoes_tenant_empresa_nf_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX movimentacoes_tenant_empresa_nf_idx ON public.movimentacoes USING btree (tenant_id, empresa_id, origem_nf_entrada_id);


--
-- Name: movimentacoes_tenant_item_data_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX movimentacoes_tenant_item_data_idx ON public.movimentacoes USING btree (tenant_id, item_id, data_movimentacao);


--
-- Name: movimentacoes_tenant_item_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX movimentacoes_tenant_item_idx ON public.movimentacoes USING btree (tenant_id, item_id);


--
-- Name: movimentacoes_tenant_nf_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX movimentacoes_tenant_nf_idx ON public.movimentacoes USING btree (tenant_id, origem_nf_entrada_id);


--
-- Name: movimentacoes_tenant_tipo_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX movimentacoes_tenant_tipo_idx ON public.movimentacoes USING btree (tenant_id, tipo);


--
-- Name: nf_entrada_itens_tenant_empresa_id_ux; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX nf_entrada_itens_tenant_empresa_id_ux ON public.nf_entrada_itens USING btree (tenant_id, empresa_id, id);


--
-- Name: nf_entrada_itens_tenant_empresa_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX nf_entrada_itens_tenant_empresa_idx ON public.nf_entrada_itens USING btree (tenant_id, empresa_id);


--
-- Name: nf_entrada_itens_tenant_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX nf_entrada_itens_tenant_id_idx ON public.nf_entrada_itens USING btree (tenant_id);


--
-- Name: nf_entrada_os_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX nf_entrada_os_id_idx ON public.nf_entrada USING btree (tenant_id, os_id) WHERE (os_id IS NOT NULL);


--
-- Name: nf_entrada_tenant_empresa_id_ux; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX nf_entrada_tenant_empresa_id_ux ON public.nf_entrada USING btree (tenant_id, empresa_id, id);


--
-- Name: nf_entrada_tenant_empresa_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX nf_entrada_tenant_empresa_idx ON public.nf_entrada USING btree (tenant_id, empresa_id);


--
-- Name: nf_entrada_tenant_finalidade_contexto_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX nf_entrada_tenant_finalidade_contexto_idx ON public.nf_entrada USING btree (tenant_id, finalidade_contexto);


--
-- Name: nf_entrada_tenant_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX nf_entrada_tenant_id_idx ON public.nf_entrada USING btree (tenant_id);


--
-- Name: ordens_servico_numero_os_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ordens_servico_numero_os_uniq ON public.ordens_servico USING btree (numero_os);


--
-- Name: ordens_servico_os_num_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ordens_servico_os_num_uniq ON public.ordens_servico USING btree (os_num);


--
-- Name: ordens_servico_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ordens_servico_status_idx ON public.ordens_servico USING btree (status);


--
-- Name: ordens_servico_tenant_empresa_id_ux; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ordens_servico_tenant_empresa_id_ux ON public.ordens_servico USING btree (tenant_id, empresa_id, id);


--
-- Name: ordens_servico_tenant_empresa_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ordens_servico_tenant_empresa_idx ON public.ordens_servico USING btree (tenant_id, empresa_id);


--
-- Name: ordens_servico_usa_relatorio_hh_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ordens_servico_usa_relatorio_hh_idx ON public.ordens_servico USING btree (usa_relatorio_hh);


--
-- Name: os_gestao_itens_tenant_empresa_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX os_gestao_itens_tenant_empresa_idx ON public.os_gestao_itens USING btree (tenant_id, empresa_id);


--
-- Name: os_gestao_itens_tenant_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX os_gestao_itens_tenant_id_idx ON public.os_gestao_itens USING btree (tenant_id);


--
-- Name: os_itens_tenant_empresa_id_ux; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX os_itens_tenant_empresa_id_ux ON public.os_itens USING btree (tenant_id, empresa_id, id);


--
-- Name: os_itens_tenant_empresa_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX os_itens_tenant_empresa_idx ON public.os_itens USING btree (tenant_id, empresa_id);


--
-- Name: os_itens_tenant_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX os_itens_tenant_id_idx ON public.os_itens USING btree (tenant_id);


--
-- Name: tipos_horas_tenant_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tipos_horas_tenant_id_idx ON public.tipos_horas USING btree (tenant_id);


--
-- Name: uq_apont_horas__hh__tenant_empresa_os_colab_data; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_apont_horas__hh__tenant_empresa_os_colab_data ON public.apontamentos_horas USING btree (tenant_id, empresa_id, os_id, colaborador_id, data) WHERE (gerado_por_hh = true);


--
-- Name: ux_fornecedores_doc_digits; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_fornecedores_doc_digits ON public.fornecedores USING btree (tenant_id, empresa_id, doc_digits) WHERE (doc_digits IS NOT NULL);


--
-- Name: ux_fornecedores_tenant_documento_norm; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_fornecedores_tenant_documento_norm ON public.fornecedores USING btree (tenant_id, documento_norm) WHERE ((documento_norm IS NOT NULL) AND (documento_norm <> ''::text));


--
-- Name: ix_realtime_subscription_entity; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX ix_realtime_subscription_entity ON realtime.subscription USING btree (entity);


--
-- Name: messages_inserted_at_topic_index; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_inserted_at_topic_index ON ONLY realtime.messages USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: subscription_subscription_id_entity_filters_key; Type: INDEX; Schema: realtime; Owner: -
--

CREATE UNIQUE INDEX subscription_subscription_id_entity_filters_key ON realtime.subscription USING btree (subscription_id, entity, filters);


--
-- Name: bname; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX bname ON storage.buckets USING btree (name);


--
-- Name: bucketid_objname; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX bucketid_objname ON storage.objects USING btree (bucket_id, name);


--
-- Name: buckets_analytics_unique_name_idx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX buckets_analytics_unique_name_idx ON storage.buckets_analytics USING btree (name) WHERE (deleted_at IS NULL);


--
-- Name: idx_multipart_uploads_list; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_multipart_uploads_list ON storage.s3_multipart_uploads USING btree (bucket_id, key, created_at);


--
-- Name: idx_name_bucket_level_unique; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX idx_name_bucket_level_unique ON storage.objects USING btree (name COLLATE "C", bucket_id, level);


--
-- Name: idx_objects_bucket_id_name; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_objects_bucket_id_name ON storage.objects USING btree (bucket_id, name COLLATE "C");


--
-- Name: idx_objects_lower_name; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_objects_lower_name ON storage.objects USING btree ((path_tokens[level]), lower(name) text_pattern_ops, bucket_id, level);


--
-- Name: idx_prefixes_lower_name; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_prefixes_lower_name ON storage.prefixes USING btree (bucket_id, level, ((string_to_array(name, '/'::text))[level]), lower(name) text_pattern_ops);


--
-- Name: name_prefix_search; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX name_prefix_search ON storage.objects USING btree (name text_pattern_ops);


--
-- Name: objects_bucket_id_level_idx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX objects_bucket_id_level_idx ON storage.objects USING btree (bucket_id, level, name COLLATE "C");


--
-- Name: vector_indexes_name_bucket_id_idx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX vector_indexes_name_bucket_id_idx ON storage.vector_indexes USING btree (name, bucket_id);


--
-- Name: usuario_empresa trg_usuario_empresa_set_updated_at; Type: TRIGGER; Schema: a; Owner: -
--

CREATE TRIGGER trg_usuario_empresa_set_updated_at BEFORE UPDATE ON a.usuario_empresa FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: usuario trg_usuario_set_updated_at; Type: TRIGGER; Schema: a; Owner: -
--

CREATE TRIGGER trg_usuario_set_updated_at BEFORE UPDATE ON a.usuario FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: usuario_tenant trg_usuario_tenant_set_updated_at; Type: TRIGGER; Schema: a; Owner: -
--

CREATE TRIGGER trg_usuario_tenant_set_updated_at BEFORE UPDATE ON a.usuario_tenant FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: users on_auth_user_created; Type: TRIGGER; Schema: auth; Owner: -
--

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


--
-- Name: users on_auth_user_created_assign_empresa; Type: TRIGGER; Schema: auth; Owner: -
--

CREATE TRIGGER on_auth_user_created_assign_empresa AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.auto_assign_empresa_segau();


--
-- Name: users on_auth_user_login_set_context; Type: TRIGGER; Schema: auth; Owner: -
--

CREATE TRIGGER on_auth_user_login_set_context AFTER UPDATE ON auth.users FOR EACH ROW WHEN ((old.last_sign_in_at IS DISTINCT FROM new.last_sign_in_at)) EXECUTE FUNCTION public.auto_set_context_on_login();


--
-- Name: empresa_endereco trg_empresa_endereco_set_updated_at; Type: TRIGGER; Schema: c; Owner: -
--

CREATE TRIGGER trg_empresa_endereco_set_updated_at BEFORE UPDATE ON c.empresa_endereco FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: empresa_fiscal trg_empresa_fiscal_set_updated_at; Type: TRIGGER; Schema: c; Owner: -
--

CREATE TRIGGER trg_empresa_fiscal_set_updated_at BEFORE UPDATE ON c.empresa_fiscal FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: empresa trg_empresa_set_updated_at; Type: TRIGGER; Schema: c; Owner: -
--

CREATE TRIGGER trg_empresa_set_updated_at BEFORE UPDATE ON c.empresa FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: i_caixa_item trg_i_caixa_item_set_updated_at; Type: TRIGGER; Schema: c; Owner: -
--

CREATE TRIGGER trg_i_caixa_item_set_updated_at BEFORE UPDATE ON c.i_caixa_item FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: i_caixa trg_i_caixa_set_updated_at; Type: TRIGGER; Schema: c; Owner: -
--

CREATE TRIGGER trg_i_caixa_set_updated_at BEFORE UPDATE ON c.i_caixa FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: i_caixa_vinculo trg_i_caixa_vinculo_set_updated_at; Type: TRIGGER; Schema: c; Owner: -
--

CREATE TRIGGER trg_i_caixa_vinculo_set_updated_at BEFORE UPDATE ON c.i_caixa_vinculo FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: i_ferramenta_sugestao_xml trg_i_ferr_sug_xml_set_updated_at; Type: TRIGGER; Schema: c; Owner: -
--

CREATE TRIGGER trg_i_ferr_sug_xml_set_updated_at BEFORE UPDATE ON c.i_ferramenta_sugestao_xml FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: i_ferramenta_unidade trg_i_ferr_unid_set_updated_at; Type: TRIGGER; Schema: c; Owner: -
--

CREATE TRIGGER trg_i_ferr_unid_set_updated_at BEFORE UPDATE ON c.i_ferramenta_unidade FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: i_ferramenta_unidade_vinculo trg_i_ferr_unid_vinc_set_updated_at; Type: TRIGGER; Schema: c; Owner: -
--

CREATE TRIGGER trg_i_ferr_unid_vinc_set_updated_at BEFORE UPDATE ON c.i_ferramenta_unidade_vinculo FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: i_ferramenta trg_i_ferramenta_set_codigo; Type: TRIGGER; Schema: c; Owner: -
--

CREATE TRIGGER trg_i_ferramenta_set_codigo BEFORE INSERT ON c.i_ferramenta FOR EACH ROW EXECUTE FUNCTION c.trg_i_ferramenta_set_codigo();


--
-- Name: i_ferramenta trg_i_ferramenta_set_updated_at; Type: TRIGGER; Schema: c; Owner: -
--

CREATE TRIGGER trg_i_ferramenta_set_updated_at BEFORE UPDATE ON c.i_ferramenta FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: tenant trg_tenant_set_updated_at; Type: TRIGGER; Schema: c; Owner: -
--

CREATE TRIGGER trg_tenant_set_updated_at BEFORE UPDATE ON c.tenant FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: anexo trg_audit_anexo; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_anexo AFTER INSERT OR DELETE OR UPDATE ON f.anexo FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: aprovacao_evento trg_audit_aprovacao_evento; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_aprovacao_evento AFTER INSERT OR DELETE OR UPDATE ON f.aprovacao_evento FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: centro_custo trg_audit_centro_custo; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_centro_custo AFTER INSERT OR DELETE OR UPDATE ON f.centro_custo FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: conciliacao_bancaria trg_audit_conciliacao_bancaria; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_conciliacao_bancaria AFTER INSERT OR DELETE OR UPDATE ON f.conciliacao_bancaria FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: conciliacao_lancamento trg_audit_conciliacao_lancamento; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_conciliacao_lancamento AFTER INSERT OR DELETE OR UPDATE ON f.conciliacao_lancamento FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: conta_bancaria trg_audit_conta_bancaria; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_conta_bancaria AFTER INSERT OR DELETE OR UPDATE ON f.conta_bancaria FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: documento_fiscal trg_audit_documento_fiscal; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_documento_fiscal AFTER INSERT OR DELETE OR UPDATE ON f.documento_fiscal FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: documento_fiscal_xml trg_audit_documento_fiscal_xml; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_documento_fiscal_xml AFTER INSERT OR DELETE OR UPDATE ON f.documento_fiscal_xml FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: evento_financeiro trg_audit_evento_financeiro; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_evento_financeiro AFTER INSERT OR DELETE OR UPDATE ON f.evento_financeiro FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: extrato_bancario trg_audit_extrato_bancario; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_extrato_bancario AFTER INSERT OR DELETE OR UPDATE ON f.extrato_bancario FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: extrato_bancario_linha trg_audit_extrato_linha; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_extrato_linha AFTER INSERT OR DELETE OR UPDATE ON f.extrato_bancario_linha FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: fin_config trg_audit_fin_config; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_fin_config AFTER INSERT OR DELETE OR UPDATE ON f.fin_config FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: importacao_doc_log trg_audit_importacao_doc_log; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_importacao_doc_log AFTER INSERT OR DELETE OR UPDATE ON f.importacao_doc_log FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: imposto_retencao trg_audit_imposto_retencao; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_imposto_retencao AFTER INSERT OR DELETE OR UPDATE ON f.imposto_retencao FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: motivo_compra trg_audit_motivo_compra; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_motivo_compra AFTER INSERT OR DELETE OR UPDATE ON f.motivo_compra FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: pagamento trg_audit_pagamento; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_pagamento AFTER INSERT OR DELETE OR UPDATE ON f.pagamento FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: pagamento_item trg_audit_pagamento_item; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_pagamento_item AFTER INSERT OR DELETE OR UPDATE ON f.pagamento_item FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: plano_contas trg_audit_plano_contas; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_plano_contas AFTER INSERT OR DELETE OR UPDATE ON f.plano_contas FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: titulo trg_audit_titulo; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_titulo AFTER INSERT OR DELETE OR UPDATE ON f.titulo FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: titulo_agendamento trg_audit_titulo_agendamento; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_titulo_agendamento AFTER INSERT OR DELETE OR UPDATE ON f.titulo_agendamento FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: titulo_aprovacao trg_audit_titulo_aprovacao; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_titulo_aprovacao AFTER INSERT OR DELETE OR UPDATE ON f.titulo_aprovacao FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: titulo_parcela trg_audit_titulo_parcela; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_titulo_parcela AFTER INSERT OR DELETE OR UPDATE ON f.titulo_parcela FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: titulo_rateio trg_audit_titulo_rateio; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_audit_titulo_rateio AFTER INSERT OR DELETE OR UPDATE ON f.titulo_rateio FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: centro_custo trg_centro_custo_set_updated_at; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_centro_custo_set_updated_at BEFORE UPDATE ON f.centro_custo FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: centro_custo trg_centro_custo_set_updated_by; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_centro_custo_set_updated_by BEFORE UPDATE ON f.centro_custo FOR EACH ROW EXECUTE FUNCTION f.fn_set_updated_by();


--
-- Name: conta_bancaria trg_conta_bancaria_set_updated_at; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_conta_bancaria_set_updated_at BEFORE UPDATE ON f.conta_bancaria FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: conta_bancaria trg_conta_bancaria_set_updated_by; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_conta_bancaria_set_updated_by BEFORE UPDATE ON f.conta_bancaria FOR EACH ROW EXECUTE FUNCTION f.fn_set_updated_by();


--
-- Name: documento_fiscal trg_documento_fiscal_set_updated_at; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_documento_fiscal_set_updated_at BEFORE UPDATE ON f.documento_fiscal FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: documento_fiscal trg_documento_fiscal_set_updated_by; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_documento_fiscal_set_updated_by BEFORE UPDATE ON f.documento_fiscal FOR EACH ROW EXECUTE FUNCTION f.fn_set_updated_by();


--
-- Name: extrato_bancario trg_extrato_bancario_set_updated_at; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_extrato_bancario_set_updated_at BEFORE UPDATE ON f.extrato_bancario FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: extrato_bancario trg_extrato_bancario_set_updated_by; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_extrato_bancario_set_updated_by BEFORE UPDATE ON f.extrato_bancario FOR EACH ROW EXECUTE FUNCTION f.fn_set_updated_by();


--
-- Name: extrato_bancario_linha trg_extrato_linha_set_updated_at; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_extrato_linha_set_updated_at BEFORE UPDATE ON f.extrato_bancario_linha FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: extrato_bancario_linha trg_extrato_linha_set_updated_by; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_extrato_linha_set_updated_by BEFORE UPDATE ON f.extrato_bancario_linha FOR EACH ROW EXECUTE FUNCTION f.fn_set_updated_by();


--
-- Name: fin_config trg_fin_config_set_updated_at; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_fin_config_set_updated_at BEFORE UPDATE ON f.fin_config FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: fin_config trg_fin_config_set_updated_by; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_fin_config_set_updated_by BEFORE UPDATE ON f.fin_config FOR EACH ROW EXECUTE FUNCTION f.fn_set_updated_by();


--
-- Name: imposto_retencao trg_imposto_retencao_set_updated_at; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_imposto_retencao_set_updated_at BEFORE UPDATE ON f.imposto_retencao FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: imposto_retencao trg_imposto_retencao_set_updated_by; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_imposto_retencao_set_updated_by BEFORE UPDATE ON f.imposto_retencao FOR EACH ROW EXECUTE FUNCTION f.fn_set_updated_by();


--
-- Name: motivo_compra trg_motivo_compra_set_updated_at; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_motivo_compra_set_updated_at BEFORE UPDATE ON f.motivo_compra FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: motivo_compra trg_motivo_compra_set_updated_by; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_motivo_compra_set_updated_by BEFORE UPDATE ON f.motivo_compra FOR EACH ROW EXECUTE FUNCTION f.fn_set_updated_by();


--
-- Name: pagamento trg_pagamento_set_updated_at; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_pagamento_set_updated_at BEFORE UPDATE ON f.pagamento FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: pagamento trg_pagamento_set_updated_by; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_pagamento_set_updated_by BEFORE UPDATE ON f.pagamento FOR EACH ROW EXECUTE FUNCTION f.fn_set_updated_by();


--
-- Name: plano_contas trg_plano_contas_set_updated_at; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_plano_contas_set_updated_at BEFORE UPDATE ON f.plano_contas FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: plano_contas trg_plano_contas_set_updated_by; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_plano_contas_set_updated_by BEFORE UPDATE ON f.plano_contas FOR EACH ROW EXECUTE FUNCTION f.fn_set_updated_by();


--
-- Name: titulo_agendamento trg_titulo_agendamento_set_updated_at; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_titulo_agendamento_set_updated_at BEFORE UPDATE ON f.titulo_agendamento FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: titulo_agendamento trg_titulo_agendamento_set_updated_by; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_titulo_agendamento_set_updated_by BEFORE UPDATE ON f.titulo_agendamento FOR EACH ROW EXECUTE FUNCTION f.fn_set_updated_by();


--
-- Name: titulo_aprovacao trg_titulo_aprovacao_set_updated_at; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_titulo_aprovacao_set_updated_at BEFORE UPDATE ON f.titulo_aprovacao FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: titulo_aprovacao trg_titulo_aprovacao_set_updated_by; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_titulo_aprovacao_set_updated_by BEFORE UPDATE ON f.titulo_aprovacao FOR EACH ROW EXECUTE FUNCTION f.fn_set_updated_by();


--
-- Name: titulo_parcela trg_titulo_parcela_set_updated_at; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_titulo_parcela_set_updated_at BEFORE UPDATE ON f.titulo_parcela FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: titulo_parcela trg_titulo_parcela_set_updated_by; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_titulo_parcela_set_updated_by BEFORE UPDATE ON f.titulo_parcela FOR EACH ROW EXECUTE FUNCTION f.fn_set_updated_by();


--
-- Name: titulo_rateio trg_titulo_rateio_set_updated_at; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_titulo_rateio_set_updated_at BEFORE UPDATE ON f.titulo_rateio FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: titulo_rateio trg_titulo_rateio_set_updated_by; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_titulo_rateio_set_updated_by BEFORE UPDATE ON f.titulo_rateio FOR EACH ROW EXECUTE FUNCTION f.fn_set_updated_by();


--
-- Name: titulo trg_titulo_require_motivo_compra; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_titulo_require_motivo_compra BEFORE INSERT OR UPDATE ON f.titulo FOR EACH ROW EXECUTE FUNCTION f.trg_titulo_require_motivo_compra();


--
-- Name: titulo trg_titulo_set_updated_at; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_titulo_set_updated_at BEFORE UPDATE ON f.titulo FOR EACH ROW EXECUTE FUNCTION a.fn_set_updated_at();


--
-- Name: titulo trg_titulo_set_updated_by; Type: TRIGGER; Schema: f; Owner: -
--

CREATE TRIGGER trg_titulo_set_updated_by BEFORE UPDATE ON f.titulo FOR EACH ROW EXECUTE FUNCTION f.fn_set_updated_by();


--
-- Name: colaborador_funcao_hh colaborador_funcao_hh_update_timestamp; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER colaborador_funcao_hh_update_timestamp BEFORE UPDATE ON public.colaborador_funcao_hh FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();


--
-- Name: hh_lancamentos hh_lancamentos_calculate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER hh_lancamentos_calculate BEFORE INSERT OR UPDATE ON public.hh_lancamentos FOR EACH ROW EXECUTE FUNCTION public.calculate_hh_lancamento();


--
-- Name: fiscal_itens trg_audit_fiscal_itens; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_fiscal_itens AFTER INSERT OR DELETE OR UPDATE ON public.fiscal_itens FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: movimentacoes trg_audit_movimentacoes; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_movimentacoes AFTER INSERT OR DELETE OR UPDATE ON public.movimentacoes FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: nf_entrada trg_audit_nf_entrada; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_nf_entrada AFTER INSERT OR DELETE OR UPDATE ON public.nf_entrada FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: nf_entrada_itens trg_audit_nf_entrada_itens; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_nf_entrada_itens AFTER INSERT OR DELETE OR UPDATE ON public.nf_entrada_itens FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: ordens_servico trg_audit_ordens_servico; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_ordens_servico AFTER INSERT OR DELETE OR UPDATE ON public.ordens_servico FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();


--
-- Name: movimentacoes trg_block_mov_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_block_mov_delete BEFORE DELETE ON public.movimentacoes FOR EACH ROW EXECUTE FUNCTION public.block_movimentacoes_mutation();


--
-- Name: movimentacoes trg_block_mov_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_block_mov_update BEFORE UPDATE ON public.movimentacoes FOR EACH ROW EXECUTE FUNCTION public.block_movimentacoes_mutation();


--
-- Name: movimentacoes trg_block_nf_mov_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_block_nf_mov_delete BEFORE DELETE ON public.movimentacoes FOR EACH ROW WHEN ((old.origem_nf_entrada_id IS NOT NULL)) EXECUTE FUNCTION public.trg_block_nf_movimentacoes();


--
-- Name: movimentacoes trg_block_nf_mov_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_block_nf_mov_update BEFORE UPDATE ON public.movimentacoes FOR EACH ROW WHEN (((old.origem_nf_entrada_id IS NOT NULL) OR (new.origem_nf_entrada_id IS NOT NULL))) EXECUTE FUNCTION public.trg_block_nf_movimentacoes();


--
-- Name: cliente_hh_servicos trg_cliente_hh_servicos_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cliente_hh_servicos_updated_at BEFORE UPDATE ON public.cliente_hh_servicos FOR EACH ROW EXECUTE FUNCTION public.update_cliente_hh_servicos_updated_at();


--
-- Name: ordens_servico trg_criar_gestao_padrao_os; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_criar_gestao_padrao_os AFTER INSERT ON public.ordens_servico FOR EACH ROW EXECUTE FUNCTION public.criar_gestao_padrao_os();


--
-- Name: fiscal_itens trg_fiscal_itens_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_fiscal_itens_updated_at BEFORE UPDATE ON public.fiscal_itens FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: hh_lancamentos trg_hh_criar_apontamento; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_hh_criar_apontamento AFTER INSERT OR UPDATE ON public.hh_lancamentos FOR EACH ROW EXECUTE FUNCTION public.fn_hh_criar_apontamento();


--
-- Name: hh_lancamentos trg_hh_delete_apontamento; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_hh_delete_apontamento BEFORE DELETE ON public.hh_lancamentos FOR EACH ROW EXECUTE FUNCTION public.fn_hh_delete_apontamento();


--
-- Name: hh_lancamentos trg_hh_sync_apontamento; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_hh_sync_apontamento AFTER INSERT OR UPDATE ON public.hh_lancamentos FOR EACH ROW EXECUTE FUNCTION public.fn_hh_sync_apontamento();


--
-- Name: movimentacoes trg_mov_atualiza_estoque; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_mov_atualiza_estoque AFTER INSERT ON public.movimentacoes FOR EACH ROW EXECUTE FUNCTION public.fn_atualiza_estoque_por_mov();


--
-- Name: movimentacoes trg_movimentacoes_apply_estoque; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_movimentacoes_apply_estoque AFTER INSERT ON public.movimentacoes FOR EACH ROW EXECUTE FUNCTION public.apply_movimentacao_estoque();


--
-- Name: nf_entrada_itens trg_nf_entrada_itens_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_nf_entrada_itens_updated_at BEFORE UPDATE ON public.nf_entrada_itens FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: nf_entrada trg_nf_entrada_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_nf_entrada_updated_at BEFORE UPDATE ON public.nf_entrada FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: ordens_servico trg_ordens_servico_validate_hh; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ordens_servico_validate_hh BEFORE INSERT OR UPDATE OF cliente_id, usa_relatorio_hh ON public.ordens_servico FOR EACH ROW EXECUTE FUNCTION public.fn_ordens_servico_validate_hh();


--
-- Name: os_gestao_itens trg_os_gestao_itens_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_os_gestao_itens_updated_at BEFORE UPDATE ON public.os_gestao_itens FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: apontamentos_horas trg_set_fator_aplicado; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_fator_aplicado BEFORE INSERT OR UPDATE OF tipo_hora_id, fator_aplicado ON public.apontamentos_horas FOR EACH ROW EXECUTE FUNCTION public.fn_set_fator_aplicado();


--
-- Name: apontamentos_horas trg_set_horas_from_periodos; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_horas_from_periodos BEFORE INSERT OR UPDATE OF hora_entrada_1, hora_saida_1, hora_entrada_2, hora_saida_2 ON public.apontamentos_horas FOR EACH ROW EXECUTE FUNCTION public.fn_set_horas_from_periodos();


--
-- Name: colaborador_cliente_funcao trg_set_tenant_id_colaborador_cliente_funcao; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_tenant_id_colaborador_cliente_funcao BEFORE INSERT ON public.colaborador_cliente_funcao FOR EACH ROW EXECUTE FUNCTION public.set_tenant_id_colaborador_cliente_funcao();


--
-- Name: apontamentos_horas trg_validar_apontamento_horas; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validar_apontamento_horas BEFORE INSERT OR UPDATE OF os_id, colaborador_id, data ON public.apontamentos_horas FOR EACH ROW EXECUTE FUNCTION public.fn_validar_apontamento_horas();


--
-- Name: colaborador_cliente_funcao trigger_update_colaborador_cliente_funcao_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_colaborador_cliente_funcao_updated_at BEFORE UPDATE ON public.colaborador_cliente_funcao FOR EACH ROW EXECUTE FUNCTION public.update_colaborador_cliente_funcao_updated_at();


--
-- Name: apontamentos_horas trigger_validate_apontamento_colaborador; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_validate_apontamento_colaborador BEFORE INSERT OR UPDATE OF colaborador_id, os_id ON public.apontamentos_horas FOR EACH ROW EXECUTE FUNCTION public.validate_apontamento_colaborador_contrato();


--
-- Name: hh_lancamentos trigger_validate_hh_lancamento; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_validate_hh_lancamento BEFORE INSERT OR UPDATE OF colaborador_id, hh_servico_id ON public.hh_lancamentos FOR EACH ROW EXECUTE FUNCTION public.validate_hh_lancamento();

ALTER TABLE public.hh_lancamentos DISABLE TRIGGER trigger_validate_hh_lancamento;


--
-- Name: subscription tr_check_filters; Type: TRIGGER; Schema: realtime; Owner: -
--

CREATE TRIGGER tr_check_filters BEFORE INSERT OR UPDATE ON realtime.subscription FOR EACH ROW EXECUTE FUNCTION realtime.subscription_check_filters();


--
-- Name: buckets enforce_bucket_name_length_trigger; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER enforce_bucket_name_length_trigger BEFORE INSERT OR UPDATE OF name ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.enforce_bucket_name_length();


--
-- Name: objects objects_delete_delete_prefix; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER objects_delete_delete_prefix AFTER DELETE ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.delete_prefix_hierarchy_trigger();


--
-- Name: objects objects_insert_create_prefix; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER objects_insert_create_prefix BEFORE INSERT ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.objects_insert_prefix_trigger();


--
-- Name: objects objects_update_create_prefix; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER objects_update_create_prefix BEFORE UPDATE ON storage.objects FOR EACH ROW WHEN (((new.name <> old.name) OR (new.bucket_id <> old.bucket_id))) EXECUTE FUNCTION storage.objects_update_prefix_trigger();


--
-- Name: prefixes prefixes_create_hierarchy; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER prefixes_create_hierarchy BEFORE INSERT ON storage.prefixes FOR EACH ROW WHEN ((pg_trigger_depth() < 1)) EXECUTE FUNCTION storage.prefixes_insert_trigger();


--
-- Name: prefixes prefixes_delete_hierarchy; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER prefixes_delete_hierarchy AFTER DELETE ON storage.prefixes FOR EACH ROW EXECUTE FUNCTION storage.delete_prefix_hierarchy_trigger();


--
-- Name: objects update_objects_updated_at; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER update_objects_updated_at BEFORE UPDATE ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.update_updated_at_column();


--
-- Name: usuario fk_usuario__auth_user_id__auth_users; Type: FK CONSTRAINT; Schema: a; Owner: -
--

ALTER TABLE ONLY a.usuario
    ADD CONSTRAINT fk_usuario__auth_user_id__auth_users FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: usuario_empresa fk_usuario_empresa__empresa_id__c_empresa; Type: FK CONSTRAINT; Schema: a; Owner: -
--

ALTER TABLE ONLY a.usuario_empresa
    ADD CONSTRAINT fk_usuario_empresa__empresa_id__c_empresa FOREIGN KEY (empresa_id) REFERENCES c.empresa(id);


--
-- Name: usuario_empresa fk_usuario_empresa__usuario_id__a_usuario; Type: FK CONSTRAINT; Schema: a; Owner: -
--

ALTER TABLE ONLY a.usuario_empresa
    ADD CONSTRAINT fk_usuario_empresa__usuario_id__a_usuario FOREIGN KEY (usuario_id) REFERENCES a.usuario(id);


--
-- Name: usuario_tenant fk_usuario_tenant__tenant_id__c_tenant; Type: FK CONSTRAINT; Schema: a; Owner: -
--

ALTER TABLE ONLY a.usuario_tenant
    ADD CONSTRAINT fk_usuario_tenant__tenant_id__c_tenant FOREIGN KEY (tenant_id) REFERENCES c.tenant(id);


--
-- Name: usuario_tenant fk_usuario_tenant__usuario_id__a_usuario; Type: FK CONSTRAINT; Schema: a; Owner: -
--

ALTER TABLE ONLY a.usuario_tenant
    ADD CONSTRAINT fk_usuario_tenant__usuario_id__a_usuario FOREIGN KEY (usuario_id) REFERENCES a.usuario(id);


--
-- Name: identities identities_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: mfa_amr_claims mfa_amr_claims_session_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT mfa_amr_claims_session_id_fkey FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE;


--
-- Name: mfa_challenges mfa_challenges_auth_factor_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_challenges
    ADD CONSTRAINT mfa_challenges_auth_factor_id_fkey FOREIGN KEY (factor_id) REFERENCES auth.mfa_factors(id) ON DELETE CASCADE;


--
-- Name: mfa_factors mfa_factors_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: oauth_authorizations oauth_authorizations_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_client_id_fkey FOREIGN KEY (client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: oauth_authorizations oauth_authorizations_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: oauth_consents oauth_consents_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_client_id_fkey FOREIGN KEY (client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: oauth_consents oauth_consents_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: one_time_tokens one_time_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.one_time_tokens
    ADD CONSTRAINT one_time_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: refresh_tokens refresh_tokens_session_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_session_id_fkey FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE;


--
-- Name: saml_providers saml_providers_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: saml_relay_states saml_relay_states_flow_state_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_flow_state_id_fkey FOREIGN KEY (flow_state_id) REFERENCES auth.flow_state(id) ON DELETE CASCADE;


--
-- Name: saml_relay_states saml_relay_states_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_oauth_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_oauth_client_id_fkey FOREIGN KEY (oauth_client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: sso_domains sso_domains_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sso_domains
    ADD CONSTRAINT sso_domains_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: empresa fk_empresa__tenant_id__c_tenant; Type: FK CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.empresa
    ADD CONSTRAINT fk_empresa__tenant_id__c_tenant FOREIGN KEY (tenant_id) REFERENCES c.tenant(id);


--
-- Name: empresa_endereco fk_empresa_endereco__empresa_id__c_empresa; Type: FK CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.empresa_endereco
    ADD CONSTRAINT fk_empresa_endereco__empresa_id__c_empresa FOREIGN KEY (empresa_id) REFERENCES c.empresa(id);


--
-- Name: empresa_fiscal fk_empresa_fiscal__empresa_id__c_empresa; Type: FK CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.empresa_fiscal
    ADD CONSTRAINT fk_empresa_fiscal__empresa_id__c_empresa FOREIGN KEY (empresa_id) REFERENCES c.empresa(id);


--
-- Name: i_caixa_item fk_i_caixa_item__caixa_id__c_i_caixa; Type: FK CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_caixa_item
    ADD CONSTRAINT fk_i_caixa_item__caixa_id__c_i_caixa FOREIGN KEY (caixa_id) REFERENCES c.i_caixa(id);


--
-- Name: i_caixa_item fk_i_caixa_item__ferramenta_id__c_i_ferramenta; Type: FK CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_caixa_item
    ADD CONSTRAINT fk_i_caixa_item__ferramenta_id__c_i_ferramenta FOREIGN KEY (ferramenta_id) REFERENCES c.i_ferramenta(id);


--
-- Name: i_caixa_vinculo fk_i_caixa_vinculo__caixa_id__c_i_caixa; Type: FK CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_caixa_vinculo
    ADD CONSTRAINT fk_i_caixa_vinculo__caixa_id__c_i_caixa FOREIGN KEY (caixa_id) REFERENCES c.i_caixa(id);


--
-- Name: i_caixa_vinculo fk_i_caixa_vinculo__colaborador_id__public_colaboradores; Type: FK CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_caixa_vinculo
    ADD CONSTRAINT fk_i_caixa_vinculo__colaborador_id__public_colaboradores FOREIGN KEY (colaborador_id) REFERENCES public.colaboradores(id);


--
-- Name: i_ferramenta_codigo_seq fk_i_ferr_codigo_seq__categoria_id__c_i_ferramenta_categoria; Type: FK CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_ferramenta_codigo_seq
    ADD CONSTRAINT fk_i_ferr_codigo_seq__categoria_id__c_i_ferramenta_categoria FOREIGN KEY (categoria_id) REFERENCES c.i_ferramenta_categoria(id);


--
-- Name: i_ferramenta_sugestao_xml fk_i_ferr_sug_xml__ferramenta_id__c_i_ferramenta; Type: FK CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_ferramenta_sugestao_xml
    ADD CONSTRAINT fk_i_ferr_sug_xml__ferramenta_id__c_i_ferramenta FOREIGN KEY (ferramenta_id) REFERENCES c.i_ferramenta(id);


--
-- Name: i_ferramenta_unidade fk_i_ferr_unid__ferramenta_id__c_i_ferramenta; Type: FK CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_ferramenta_unidade
    ADD CONSTRAINT fk_i_ferr_unid__ferramenta_id__c_i_ferramenta FOREIGN KEY (ferramenta_id) REFERENCES c.i_ferramenta(id);


--
-- Name: i_ferramenta_unidade_vinculo fk_i_ferr_unid_vinc__colaborador_id__public_colaboradores; Type: FK CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_ferramenta_unidade_vinculo
    ADD CONSTRAINT fk_i_ferr_unid_vinc__colaborador_id__public_colaboradores FOREIGN KEY (colaborador_id) REFERENCES public.colaboradores(id);


--
-- Name: i_ferramenta_unidade_vinculo fk_i_ferr_unid_vinc__unidade_id__c_i_ferr_unidade; Type: FK CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_ferramenta_unidade_vinculo
    ADD CONSTRAINT fk_i_ferr_unid_vinc__unidade_id__c_i_ferr_unidade FOREIGN KEY (ferramenta_unidade_id) REFERENCES c.i_ferramenta_unidade(id);


--
-- Name: i_ferramenta fk_i_ferramenta__categoria_id__c_i_ferr_cat; Type: FK CONSTRAINT; Schema: c; Owner: -
--

ALTER TABLE ONLY c.i_ferramenta
    ADD CONSTRAINT fk_i_ferramenta__categoria_id__c_i_ferr_cat FOREIGN KEY (categoria_id) REFERENCES c.i_ferramenta_categoria(id);


--
-- Name: anexo fk_anexo__uploaded_by__usuario; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.anexo
    ADD CONSTRAINT fk_anexo__uploaded_by__usuario FOREIGN KEY (uploaded_by) REFERENCES a.usuario(id);


--
-- Name: aprovacao_evento fk_aprovacao_evento__empresa_id__empresa; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.aprovacao_evento
    ADD CONSTRAINT fk_aprovacao_evento__empresa_id__empresa FOREIGN KEY (empresa_id) REFERENCES c.empresa(id);


--
-- Name: centro_custo fk_centro_custo__empresa_id__empresa; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.centro_custo
    ADD CONSTRAINT fk_centro_custo__empresa_id__empresa FOREIGN KEY (empresa_id) REFERENCES c.empresa(id);


--
-- Name: centro_custo fk_centro_custo__parent_id__centro_custo; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.centro_custo
    ADD CONSTRAINT fk_centro_custo__parent_id__centro_custo FOREIGN KEY (parent_id) REFERENCES f.centro_custo(id);


--
-- Name: conciliacao_bancaria fk_conciliacao_bancaria__conta_bancaria_id__conta_bancaria; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.conciliacao_bancaria
    ADD CONSTRAINT fk_conciliacao_bancaria__conta_bancaria_id__conta_bancaria FOREIGN KEY (conta_bancaria_id) REFERENCES f.conta_bancaria(id);


--
-- Name: conciliacao_bancaria fk_conciliacao_bancaria__empresa_id__empresa; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.conciliacao_bancaria
    ADD CONSTRAINT fk_conciliacao_bancaria__empresa_id__empresa FOREIGN KEY (empresa_id) REFERENCES c.empresa(id);


--
-- Name: conciliacao_lancamento fk_conciliacao_lancamento__conciliacao_id__conciliacao; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.conciliacao_lancamento
    ADD CONSTRAINT fk_conciliacao_lancamento__conciliacao_id__conciliacao FOREIGN KEY (conciliacao_id) REFERENCES f.conciliacao_bancaria(id);


--
-- Name: conciliacao_lancamento fk_conciliacao_lancamento__conciliado_por__usuario; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.conciliacao_lancamento
    ADD CONSTRAINT fk_conciliacao_lancamento__conciliado_por__usuario FOREIGN KEY (conciliado_por) REFERENCES a.usuario(id);


--
-- Name: conciliacao_lancamento fk_conciliacao_lancamento__pagamento_id__pagamento; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.conciliacao_lancamento
    ADD CONSTRAINT fk_conciliacao_lancamento__pagamento_id__pagamento FOREIGN KEY (pagamento_id) REFERENCES f.pagamento(id);


--
-- Name: conta_bancaria fk_conta_bancaria__empresa_id__empresa; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.conta_bancaria
    ADD CONSTRAINT fk_conta_bancaria__empresa_id__empresa FOREIGN KEY (empresa_id) REFERENCES c.empresa(id);


--
-- Name: documento_fiscal fk_documento_fiscal__empresa_id__empresa; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.documento_fiscal
    ADD CONSTRAINT fk_documento_fiscal__empresa_id__empresa FOREIGN KEY (empresa_id) REFERENCES c.empresa(id);


--
-- Name: documento_fiscal fk_documento_fiscal__fornecedor_id__fornecedores; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.documento_fiscal
    ADD CONSTRAINT fk_documento_fiscal__fornecedor_id__fornecedores FOREIGN KEY (fornecedor_id) REFERENCES public.fornecedores(id);


--
-- Name: documento_fiscal fk_documento_fiscal__os_id_import__ordens_servico; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.documento_fiscal
    ADD CONSTRAINT fk_documento_fiscal__os_id_import__ordens_servico FOREIGN KEY (os_id_import) REFERENCES public.ordens_servico(id);


--
-- Name: documento_fiscal fk_documento_fiscal__source_nf_entrada_id__nf_entrada; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.documento_fiscal
    ADD CONSTRAINT fk_documento_fiscal__source_nf_entrada_id__nf_entrada FOREIGN KEY (source_nf_entrada_id) REFERENCES public.nf_entrada(id);


--
-- Name: documento_fiscal_xml fk_documento_fiscal_xml__documento_fiscal_id__documento_fiscal; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.documento_fiscal_xml
    ADD CONSTRAINT fk_documento_fiscal_xml__documento_fiscal_id__documento_fiscal FOREIGN KEY (documento_fiscal_id) REFERENCES f.documento_fiscal(id);


--
-- Name: evento_financeiro fk_evento_financeiro__empresa_id__empresa; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.evento_financeiro
    ADD CONSTRAINT fk_evento_financeiro__empresa_id__empresa FOREIGN KEY (empresa_id) REFERENCES c.empresa(id);


--
-- Name: extrato_bancario fk_extrato_bancario__conta_bancaria_id__conta_bancaria; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.extrato_bancario
    ADD CONSTRAINT fk_extrato_bancario__conta_bancaria_id__conta_bancaria FOREIGN KEY (conta_bancaria_id) REFERENCES f.conta_bancaria(id);


--
-- Name: extrato_bancario fk_extrato_bancario__empresa_id__empresa; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.extrato_bancario
    ADD CONSTRAINT fk_extrato_bancario__empresa_id__empresa FOREIGN KEY (empresa_id) REFERENCES c.empresa(id);


--
-- Name: extrato_bancario_linha fk_extrato_linha__conta_bancaria_id__conta_bancaria; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.extrato_bancario_linha
    ADD CONSTRAINT fk_extrato_linha__conta_bancaria_id__conta_bancaria FOREIGN KEY (conta_bancaria_id) REFERENCES f.conta_bancaria(id);


--
-- Name: extrato_bancario_linha fk_extrato_linha__extrato_bancario_id__extrato_bancario; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.extrato_bancario_linha
    ADD CONSTRAINT fk_extrato_linha__extrato_bancario_id__extrato_bancario FOREIGN KEY (extrato_bancario_id) REFERENCES f.extrato_bancario(id);


--
-- Name: fin_config fk_fin_config__conta_bancaria_padrao_id__conta_bancaria; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.fin_config
    ADD CONSTRAINT fk_fin_config__conta_bancaria_padrao_id__conta_bancaria FOREIGN KEY (conta_bancaria_padrao_id) REFERENCES f.conta_bancaria(id);


--
-- Name: importacao_doc_log fk_importacao_doc_log__documento_fiscal_id__documento_fiscal; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.importacao_doc_log
    ADD CONSTRAINT fk_importacao_doc_log__documento_fiscal_id__documento_fiscal FOREIGN KEY (documento_fiscal_id) REFERENCES f.documento_fiscal(id);


--
-- Name: importacao_doc_log fk_importacao_doc_log__empresa_id__empresa; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.importacao_doc_log
    ADD CONSTRAINT fk_importacao_doc_log__empresa_id__empresa FOREIGN KEY (empresa_id) REFERENCES c.empresa(id);


--
-- Name: imposto_retencao fk_imposto_retencao__documento_fiscal_id__documento_fiscal; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.imposto_retencao
    ADD CONSTRAINT fk_imposto_retencao__documento_fiscal_id__documento_fiscal FOREIGN KEY (documento_fiscal_id) REFERENCES f.documento_fiscal(id);


--
-- Name: imposto_retencao fk_imposto_retencao__titulo_id__titulo; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.imposto_retencao
    ADD CONSTRAINT fk_imposto_retencao__titulo_id__titulo FOREIGN KEY (titulo_id) REFERENCES f.titulo(id);


--
-- Name: pagamento fk_pagamento__conciliado_por__usuario; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.pagamento
    ADD CONSTRAINT fk_pagamento__conciliado_por__usuario FOREIGN KEY (conciliado_por) REFERENCES a.usuario(id);


--
-- Name: pagamento fk_pagamento__conta_bancaria_id__conta_bancaria; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.pagamento
    ADD CONSTRAINT fk_pagamento__conta_bancaria_id__conta_bancaria FOREIGN KEY (conta_bancaria_id) REFERENCES f.conta_bancaria(id);


--
-- Name: pagamento fk_pagamento__empresa_id__empresa; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.pagamento
    ADD CONSTRAINT fk_pagamento__empresa_id__empresa FOREIGN KEY (empresa_id) REFERENCES c.empresa(id);


--
-- Name: pagamento fk_pagamento__pago_por__usuario; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.pagamento
    ADD CONSTRAINT fk_pagamento__pago_por__usuario FOREIGN KEY (pago_por) REFERENCES a.usuario(id);


--
-- Name: pagamento_item fk_pagamento_item__pagamento_id__pagamento; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.pagamento_item
    ADD CONSTRAINT fk_pagamento_item__pagamento_id__pagamento FOREIGN KEY (pagamento_id) REFERENCES f.pagamento(id);


--
-- Name: pagamento_item fk_pagamento_item__titulo_parcela_id__titulo_parcela; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.pagamento_item
    ADD CONSTRAINT fk_pagamento_item__titulo_parcela_id__titulo_parcela FOREIGN KEY (titulo_parcela_id) REFERENCES f.titulo_parcela(id);


--
-- Name: parametro_financeiro_empresa fk_param_fin_emp__conta_bancaria_padrao_id__conta_bancaria; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.parametro_financeiro_empresa
    ADD CONSTRAINT fk_param_fin_emp__conta_bancaria_padrao_id__conta_bancaria FOREIGN KEY (conta_bancaria_padrao_id) REFERENCES f.conta_bancaria(id);


--
-- Name: parametro_financeiro_empresa fk_param_fin_emp__empresa_id__empresa; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.parametro_financeiro_empresa
    ADD CONSTRAINT fk_param_fin_emp__empresa_id__empresa FOREIGN KEY (empresa_id) REFERENCES c.empresa(id);


--
-- Name: plano_contas fk_plano_contas__parent_id__plano_contas; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.plano_contas
    ADD CONSTRAINT fk_plano_contas__parent_id__plano_contas FOREIGN KEY (parent_id) REFERENCES f.plano_contas(id);


--
-- Name: titulo fk_titulo__cliente_id__clientes; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo
    ADD CONSTRAINT fk_titulo__cliente_id__clientes FOREIGN KEY (cliente_id) REFERENCES public.clientes(id);


--
-- Name: titulo fk_titulo__documento_fiscal_id__documento_fiscal; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo
    ADD CONSTRAINT fk_titulo__documento_fiscal_id__documento_fiscal FOREIGN KEY (documento_fiscal_id) REFERENCES f.documento_fiscal(id);


--
-- Name: titulo fk_titulo__empresa_id__empresa; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo
    ADD CONSTRAINT fk_titulo__empresa_id__empresa FOREIGN KEY (empresa_id) REFERENCES c.empresa(id);


--
-- Name: titulo fk_titulo__fornecedor_id__fornecedores; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo
    ADD CONSTRAINT fk_titulo__fornecedor_id__fornecedores FOREIGN KEY (fornecedor_id) REFERENCES public.fornecedores(id);


--
-- Name: titulo_agendamento fk_titulo_agendamento__agendado_por__usuario; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_agendamento
    ADD CONSTRAINT fk_titulo_agendamento__agendado_por__usuario FOREIGN KEY (agendado_por) REFERENCES a.usuario(id);


--
-- Name: titulo_agendamento fk_titulo_agendamento__conta_bancaria_id__conta_bancaria; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_agendamento
    ADD CONSTRAINT fk_titulo_agendamento__conta_bancaria_id__conta_bancaria FOREIGN KEY (conta_bancaria_id) REFERENCES f.conta_bancaria(id);


--
-- Name: titulo_agendamento fk_titulo_agendamento__titulo_id__titulo; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_agendamento
    ADD CONSTRAINT fk_titulo_agendamento__titulo_id__titulo FOREIGN KEY (titulo_id) REFERENCES f.titulo(id);


--
-- Name: titulo_aprovacao fk_titulo_aprovacao__aprovado_por__usuario; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_aprovacao
    ADD CONSTRAINT fk_titulo_aprovacao__aprovado_por__usuario FOREIGN KEY (aprovado_por) REFERENCES a.usuario(id);


--
-- Name: titulo_aprovacao fk_titulo_aprovacao__motivo_compra_id__motivo_compra; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_aprovacao
    ADD CONSTRAINT fk_titulo_aprovacao__motivo_compra_id__motivo_compra FOREIGN KEY (motivo_compra_id) REFERENCES f.motivo_compra(id);


--
-- Name: titulo_aprovacao fk_titulo_aprovacao__os_id__ordens_servico; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_aprovacao
    ADD CONSTRAINT fk_titulo_aprovacao__os_id__ordens_servico FOREIGN KEY (os_id) REFERENCES public.ordens_servico(id);


--
-- Name: titulo_aprovacao fk_titulo_aprovacao__titulo_id__titulo; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_aprovacao
    ADD CONSTRAINT fk_titulo_aprovacao__titulo_id__titulo FOREIGN KEY (titulo_id) REFERENCES f.titulo(id);


--
-- Name: titulo_parcela fk_titulo_parcela__titulo_id__titulo; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_parcela
    ADD CONSTRAINT fk_titulo_parcela__titulo_id__titulo FOREIGN KEY (titulo_id) REFERENCES f.titulo(id);


--
-- Name: titulo_rateio fk_titulo_rateio__centro_custo_id__centro_custo; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_rateio
    ADD CONSTRAINT fk_titulo_rateio__centro_custo_id__centro_custo FOREIGN KEY (centro_custo_id) REFERENCES f.centro_custo(id);


--
-- Name: titulo_rateio fk_titulo_rateio__os_id__ordens_servico; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_rateio
    ADD CONSTRAINT fk_titulo_rateio__os_id__ordens_servico FOREIGN KEY (os_id) REFERENCES public.ordens_servico(id);


--
-- Name: titulo_rateio fk_titulo_rateio__plano_contas_id__plano_contas; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_rateio
    ADD CONSTRAINT fk_titulo_rateio__plano_contas_id__plano_contas FOREIGN KEY (plano_contas_id) REFERENCES f.plano_contas(id);


--
-- Name: titulo_rateio fk_titulo_rateio__titulo_id__titulo; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo_rateio
    ADD CONSTRAINT fk_titulo_rateio__titulo_id__titulo FOREIGN KEY (titulo_id) REFERENCES f.titulo(id);


--
-- Name: titulo titulo_motivo_compra_fk; Type: FK CONSTRAINT; Schema: f; Owner: -
--

ALTER TABLE ONLY f.titulo
    ADD CONSTRAINT titulo_motivo_compra_fk FOREIGN KEY (motivo_compra_id) REFERENCES f.motivo_compra(id);


--
-- Name: apontamentos_horas apontamentos_horas_colaborador_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apontamentos_horas
    ADD CONSTRAINT apontamentos_horas_colaborador_id_fkey FOREIGN KEY (colaborador_id) REFERENCES public.colaboradores(id);


--
-- Name: apontamentos_horas apontamentos_horas_hh_lancamento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apontamentos_horas
    ADD CONSTRAINT apontamentos_horas_hh_lancamento_id_fkey FOREIGN KEY (hh_lancamento_id) REFERENCES public.hh_lancamentos(id) ON DELETE CASCADE;


--
-- Name: apontamentos_horas apontamentos_horas_tenant_empresa_os_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apontamentos_horas
    ADD CONSTRAINT apontamentos_horas_tenant_empresa_os_fk FOREIGN KEY (tenant_id, empresa_id, os_id) REFERENCES public.ordens_servico(tenant_id, empresa_id, id) ON DELETE CASCADE;


--
-- Name: apontamentos_horas apontamentos_horas_tenant_os_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apontamentos_horas
    ADD CONSTRAINT apontamentos_horas_tenant_os_fk FOREIGN KEY (tenant_id, os_id) REFERENCES public.ordens_servico(tenant_id, id) ON DELETE SET NULL;


--
-- Name: apontamentos_horas apontamentos_horas_tipo_hora_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apontamentos_horas
    ADD CONSTRAINT apontamentos_horas_tipo_hora_id_fkey FOREIGN KEY (tipo_hora_id) REFERENCES public.tipos_horas(id);


--
-- Name: centros_custo centros_custo_empresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.centros_custo
    ADD CONSTRAINT centros_custo_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresas(id) ON DELETE CASCADE;


--
-- Name: cliente_hh_tabelas cliente_hh_tabelas_cliente_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cliente_hh_tabelas
    ADD CONSTRAINT cliente_hh_tabelas_cliente_fk FOREIGN KEY (cliente_id) REFERENCES public.clientes(id) ON DELETE RESTRICT;


--
-- Name: colaborador_funcao_hh colaborador_funcao_hh_cliente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaborador_funcao_hh
    ADD CONSTRAINT colaborador_funcao_hh_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.clientes(id) ON DELETE CASCADE;


--
-- Name: colaborador_funcao_hh colaborador_funcao_hh_colaborador_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaborador_funcao_hh
    ADD CONSTRAINT colaborador_funcao_hh_colaborador_id_fkey FOREIGN KEY (colaborador_id) REFERENCES public.colaboradores(id) ON DELETE CASCADE;


--
-- Name: colaborador_funcao_hh colaborador_funcao_hh_servico_hh_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaborador_funcao_hh
    ADD CONSTRAINT colaborador_funcao_hh_servico_hh_id_fkey FOREIGN KEY (servico_hh_id) REFERENCES public.cliente_hh_servicos(id) ON DELETE CASCADE;


--
-- Name: colaborador_funcao_hh colaborador_funcao_hh_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaborador_funcao_hh
    ADD CONSTRAINT colaborador_funcao_hh_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: colaborador_taxas colaborador_taxas_colaborador_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaborador_taxas
    ADD CONSTRAINT colaborador_taxas_colaborador_id_fkey FOREIGN KEY (colaborador_id) REFERENCES public.colaboradores(id) ON DELETE CASCADE;


--
-- Name: competencias competencias_empresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.competencias
    ADD CONSTRAINT competencias_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresas(id) ON DELETE CASCADE;


--
-- Name: empresa_memberships empresa_memberships_empresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_memberships
    ADD CONSTRAINT empresa_memberships_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresas(id) ON DELETE CASCADE;


--
-- Name: empresa_memberships empresa_memberships_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_memberships
    ADD CONSTRAINT empresa_memberships_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: empresa_memberships empresa_memberships_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_memberships
    ADD CONSTRAINT empresa_memberships_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: estoque estoque_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estoque
    ADD CONSTRAINT estoque_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.itens(id) ON DELETE CASCADE;


--
-- Name: estoque estoque_tenant_item_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estoque
    ADD CONSTRAINT estoque_tenant_item_fk FOREIGN KEY (tenant_id, item_id) REFERENCES public.itens(tenant_id, id) ON DELETE CASCADE;


--
-- Name: fiscal_itens fiscal_itens_empresa_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_itens
    ADD CONSTRAINT fiscal_itens_empresa_fk FOREIGN KEY (empresa_id) REFERENCES public.empresas(id) ON DELETE CASCADE;


--
-- Name: fiscal_itens fiscal_itens_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_itens
    ADD CONSTRAINT fiscal_itens_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.itens(id) ON DELETE CASCADE;


--
-- Name: fiscal_itens fiscal_itens_tenant_item_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_itens
    ADD CONSTRAINT fiscal_itens_tenant_item_fk FOREIGN KEY (tenant_id, item_id) REFERENCES public.itens(tenant_id, id) ON DELETE CASCADE;


--
-- Name: fiscal_regras fiscal_regras_empresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_regras
    ADD CONSTRAINT fiscal_regras_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresas(id) ON DELETE CASCADE;


--
-- Name: cliente_hh_servicos fk_cliente_hh_servicos_cliente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cliente_hh_servicos
    ADD CONSTRAINT fk_cliente_hh_servicos_cliente FOREIGN KEY (cliente_id) REFERENCES public.clientes(id) ON DELETE CASCADE;


--
-- Name: colaborador_cliente_funcao fk_colaborador_cliente_funcao_cliente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaborador_cliente_funcao
    ADD CONSTRAINT fk_colaborador_cliente_funcao_cliente FOREIGN KEY (cliente_id) REFERENCES public.clientes(id) ON DELETE CASCADE;


--
-- Name: colaborador_cliente_funcao fk_colaborador_cliente_funcao_colaborador; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaborador_cliente_funcao
    ADD CONSTRAINT fk_colaborador_cliente_funcao_colaborador FOREIGN KEY (colaborador_id) REFERENCES public.colaboradores(id) ON DELETE CASCADE;


--
-- Name: colaborador_cliente_funcao fk_colaborador_cliente_funcao_servico; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaborador_cliente_funcao
    ADD CONSTRAINT fk_colaborador_cliente_funcao_servico FOREIGN KEY (hh_servico_id) REFERENCES public.cliente_hh_servicos(id) ON DELETE CASCADE;


--
-- Name: fornecedores fk_fornecedores__motivo_compra_padrao_id__motivo_compra; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fornecedores
    ADD CONSTRAINT fk_fornecedores__motivo_compra_padrao_id__motivo_compra FOREIGN KEY (motivo_compra_padrao_id) REFERENCES f.motivo_compra(id);


--
-- Name: colaborador_cliente_funcao fk_hh_servico; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaborador_cliente_funcao
    ADD CONSTRAINT fk_hh_servico FOREIGN KEY (hh_servico_id) REFERENCES public.cliente_hh_servicos(id) ON DELETE CASCADE;


--
-- Name: nf_entrada fk_nf_entrada__motivo_compra_id__f_motivo_compra; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nf_entrada
    ADD CONSTRAINT fk_nf_entrada__motivo_compra_id__f_motivo_compra FOREIGN KEY (motivo_compra_id) REFERENCES f.motivo_compra(id) ON UPDATE RESTRICT ON DELETE SET NULL;


--
-- Name: nf_entrada fk_nf_entrada__solicitante_usuario_id__a_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nf_entrada
    ADD CONSTRAINT fk_nf_entrada__solicitante_usuario_id__a_usuario FOREIGN KEY (solicitante_usuario_id) REFERENCES a.usuario(id) ON UPDATE RESTRICT ON DELETE SET NULL;


--
-- Name: fornecedores fornecedores_motivo_compra_padrao_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fornecedores
    ADD CONSTRAINT fornecedores_motivo_compra_padrao_fk FOREIGN KEY (motivo_compra_padrao_id) REFERENCES f.motivo_compra(id) ON DELETE SET NULL;


--
-- Name: hh_lancamentos hh_lancamentos_colaborador_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hh_lancamentos
    ADD CONSTRAINT hh_lancamentos_colaborador_id_fkey FOREIGN KEY (colaborador_id) REFERENCES public.colaboradores(id) ON DELETE RESTRICT;


--
-- Name: hh_lancamentos hh_lancamentos_hh_servico_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hh_lancamentos
    ADD CONSTRAINT hh_lancamentos_hh_servico_id_fkey FOREIGN KEY (hh_servico_id) REFERENCES public.cliente_hh_servicos(id) ON DELETE RESTRICT;


--
-- Name: hh_lancamentos hh_lancamentos_hh_tipo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hh_lancamentos
    ADD CONSTRAINT hh_lancamentos_hh_tipo_id_fkey FOREIGN KEY (hh_tipo_id) REFERENCES public.cliente_hh_servicos(id);


--
-- Name: hh_lancamentos hh_lancamentos_os_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hh_lancamentos
    ADD CONSTRAINT hh_lancamentos_os_id_fkey FOREIGN KEY (os_id) REFERENCES public.ordens_servico(id) ON DELETE CASCADE;


--
-- Name: hh_tipos_mapping hh_tipos_mapping_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hh_tipos_mapping
    ADD CONSTRAINT hh_tipos_mapping_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: hh_tipos_mapping hh_tipos_mapping_tipo_hora_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hh_tipos_mapping
    ADD CONSTRAINT hh_tipos_mapping_tipo_hora_id_fkey FOREIGN KEY (tipo_hora_id) REFERENCES public.tipos_horas(id) ON DELETE CASCADE;


--
-- Name: horas_trabalhadas horas_trabalhadas_os_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.horas_trabalhadas
    ADD CONSTRAINT horas_trabalhadas_os_id_fkey FOREIGN KEY (os_id) REFERENCES public.ordens_servico(id) ON DELETE CASCADE;


--
-- Name: horas_trabalhadas horas_trabalhadas_profissional_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.horas_trabalhadas
    ADD CONSTRAINT horas_trabalhadas_profissional_id_fkey FOREIGN KEY (profissional_id) REFERENCES public.profissionais(id) ON DELETE RESTRICT;


--
-- Name: itens itens_motivo_compra_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.itens
    ADD CONSTRAINT itens_motivo_compra_fk FOREIGN KEY (motivo_compra_id) REFERENCES f.motivo_compra(id) ON DELETE SET NULL;


--
-- Name: itens itens_tenant_empresa_fornecedor_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.itens
    ADD CONSTRAINT itens_tenant_empresa_fornecedor_fk FOREIGN KEY (tenant_id, empresa_id, fornecedor_id) REFERENCES public.fornecedores(tenant_id, empresa_id, id) ON DELETE SET NULL;


--
-- Name: lancamentos_contabeis lancamentos_contabeis_competencia_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lancamentos_contabeis
    ADD CONSTRAINT lancamentos_contabeis_competencia_id_fkey FOREIGN KEY (competencia_id) REFERENCES public.competencias(id) ON DELETE RESTRICT;


--
-- Name: lancamentos_contabeis lancamentos_contabeis_empresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lancamentos_contabeis
    ADD CONSTRAINT lancamentos_contabeis_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresas(id) ON DELETE CASCADE;


--
-- Name: lancamentos_contabeis_itens lancamentos_contabeis_itens_centro_custo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lancamentos_contabeis_itens
    ADD CONSTRAINT lancamentos_contabeis_itens_centro_custo_id_fkey FOREIGN KEY (centro_custo_id) REFERENCES public.centros_custo(id) ON DELETE RESTRICT;


--
-- Name: lancamentos_contabeis_itens lancamentos_contabeis_itens_conta_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lancamentos_contabeis_itens
    ADD CONSTRAINT lancamentos_contabeis_itens_conta_id_fkey FOREIGN KEY (conta_id) REFERENCES public.plano_contas(id) ON DELETE RESTRICT;


--
-- Name: lancamentos_contabeis_itens lancamentos_contabeis_itens_empresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lancamentos_contabeis_itens
    ADD CONSTRAINT lancamentos_contabeis_itens_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresas(id) ON DELETE CASCADE;


--
-- Name: lancamentos_contabeis_itens lancamentos_contabeis_itens_lancamento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lancamentos_contabeis_itens
    ADD CONSTRAINT lancamentos_contabeis_itens_lancamento_id_fkey FOREIGN KEY (lancamento_id) REFERENCES public.lancamentos_contabeis(id) ON DELETE CASCADE;


--
-- Name: membership_roles membership_roles_membership_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_roles
    ADD CONSTRAINT membership_roles_membership_id_fkey FOREIGN KEY (membership_id) REFERENCES public.tenant_memberships(id) ON DELETE CASCADE;


--
-- Name: membership_roles membership_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_roles
    ADD CONSTRAINT membership_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE;


--
-- Name: movimentacoes movimentacoes_empresa_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimentacoes
    ADD CONSTRAINT movimentacoes_empresa_fk FOREIGN KEY (empresa_id) REFERENCES public.empresas(id);


--
-- Name: movimentacoes movimentacoes_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimentacoes
    ADD CONSTRAINT movimentacoes_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.itens(id) ON DELETE CASCADE;


--
-- Name: movimentacoes movimentacoes_origem_nf_entrada_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimentacoes
    ADD CONSTRAINT movimentacoes_origem_nf_entrada_id_fkey FOREIGN KEY (origem_nf_entrada_id) REFERENCES public.nf_entrada(id);


--
-- Name: movimentacoes movimentacoes_tenant_item_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimentacoes
    ADD CONSTRAINT movimentacoes_tenant_item_fk FOREIGN KEY (tenant_id, item_id) REFERENCES public.itens(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: nf_entrada nf_entrada_empresa_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nf_entrada
    ADD CONSTRAINT nf_entrada_empresa_fk FOREIGN KEY (empresa_id) REFERENCES public.empresas(id);


--
-- Name: nf_entrada nf_entrada_fornecedor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nf_entrada
    ADD CONSTRAINT nf_entrada_fornecedor_id_fkey FOREIGN KEY (fornecedor_id) REFERENCES public.fornecedores(id);


--
-- Name: nf_entrada_itens nf_entrada_itens_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nf_entrada_itens
    ADD CONSTRAINT nf_entrada_itens_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.itens(id);


--
-- Name: nf_entrada_itens nf_entrada_itens_tenant_empresa_nf_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nf_entrada_itens
    ADD CONSTRAINT nf_entrada_itens_tenant_empresa_nf_fk FOREIGN KEY (tenant_id, empresa_id, nf_entrada_id) REFERENCES public.nf_entrada(tenant_id, empresa_id, id) ON DELETE CASCADE;


--
-- Name: nf_entrada_itens nf_entrada_itens_tenant_nf_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nf_entrada_itens
    ADD CONSTRAINT nf_entrada_itens_tenant_nf_fk FOREIGN KEY (tenant_id, nf_entrada_id) REFERENCES public.nf_entrada(tenant_id, id) ON DELETE CASCADE;


--
-- Name: ordens_servico ordens_servico_tenant_empresa_cliente_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ordens_servico
    ADD CONSTRAINT ordens_servico_tenant_empresa_cliente_fk FOREIGN KEY (tenant_id, empresa_id, cliente_id) REFERENCES public.clientes(tenant_id, empresa_id, id) ON DELETE SET NULL;


--
-- Name: os_gestao_itens os_gestao_itens_os_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_gestao_itens
    ADD CONSTRAINT os_gestao_itens_os_id_fkey FOREIGN KEY (os_id) REFERENCES public.ordens_servico(id) ON DELETE CASCADE;


--
-- Name: os_gestao_itens os_gestao_itens_tenant_os_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_gestao_itens
    ADD CONSTRAINT os_gestao_itens_tenant_os_fk FOREIGN KEY (tenant_id, os_id) REFERENCES public.ordens_servico(tenant_id, id) ON DELETE CASCADE;


--
-- Name: os_itens os_itens_tenant_empresa_item_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_itens
    ADD CONSTRAINT os_itens_tenant_empresa_item_fk FOREIGN KEY (tenant_id, empresa_id, item_id) REFERENCES public.itens(tenant_id, empresa_id, id) ON DELETE RESTRICT;


--
-- Name: os_itens os_itens_tenant_empresa_os_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.os_itens
    ADD CONSTRAINT os_itens_tenant_empresa_os_fk FOREIGN KEY (tenant_id, empresa_id, os_id) REFERENCES public.ordens_servico(tenant_id, empresa_id, id) ON DELETE CASCADE;


--
-- Name: plano_contas plano_contas_empresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plano_contas
    ADD CONSTRAINT plano_contas_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresas(id) ON DELETE CASCADE;


--
-- Name: plano_contas plano_contas_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plano_contas
    ADD CONSTRAINT plano_contas_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.plano_contas(id) ON DELETE RESTRICT;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: role_access_rules role_access_rules_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_access_rules
    ADD CONSTRAINT role_access_rules_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE;


--
-- Name: roles roles_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: tenant_memberships tenant_memberships_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_memberships
    ADD CONSTRAINT tenant_memberships_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: tenant_memberships tenant_memberships_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_memberships
    ADD CONSTRAINT tenant_memberships_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: user_empresa_context user_empresa_context_empresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_empresa_context
    ADD CONSTRAINT user_empresa_context_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresas(id) ON DELETE CASCADE;


--
-- Name: user_empresa_context user_empresa_context_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_empresa_context
    ADD CONSTRAINT user_empresa_context_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: user_empresa_context user_empresa_context_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_empresa_context
    ADD CONSTRAINT user_empresa_context_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: user_profiles user_profiles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: user_tenant_context user_tenant_context_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_tenant_context
    ADD CONSTRAINT user_tenant_context_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: user_tenant_context user_tenant_context_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_tenant_context
    ADD CONSTRAINT user_tenant_context_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: objects objects_bucketId_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: prefixes prefixes_bucketId_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.prefixes
    ADD CONSTRAINT "prefixes_bucketId_fkey" FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads s3_multipart_uploads_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_upload_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_upload_id_fkey FOREIGN KEY (upload_id) REFERENCES storage.s3_multipart_uploads(id) ON DELETE CASCADE;


--
-- Name: vector_indexes vector_indexes_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.vector_indexes
    ADD CONSTRAINT vector_indexes_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets_vectors(id);


--
-- Name: usuario; Type: ROW SECURITY; Schema: a; Owner: -
--

ALTER TABLE a.usuario ENABLE ROW LEVEL SECURITY;

--
-- Name: usuario_empresa; Type: ROW SECURITY; Schema: a; Owner: -
--

ALTER TABLE a.usuario_empresa ENABLE ROW LEVEL SECURITY;

--
-- Name: usuario_empresa usuario_empresa_insert_admin; Type: POLICY; Schema: a; Owner: -
--

CREATE POLICY usuario_empresa_insert_admin ON a.usuario_empresa FOR INSERT TO authenticated WITH CHECK (((deleted_at IS NULL) AND a.fn_can_manage_empresa(empresa_id)));


--
-- Name: usuario_empresa usuario_empresa_select_self_or_admin; Type: POLICY; Schema: a; Owner: -
--

CREATE POLICY usuario_empresa_select_self_or_admin ON a.usuario_empresa FOR SELECT TO authenticated USING (((deleted_at IS NULL) AND ((usuario_id = a.fn_current_usuario_id()) OR a.fn_can_manage_empresa(empresa_id))));


--
-- Name: usuario_empresa usuario_empresa_update_admin; Type: POLICY; Schema: a; Owner: -
--

CREATE POLICY usuario_empresa_update_admin ON a.usuario_empresa FOR UPDATE TO authenticated USING (((deleted_at IS NULL) AND a.fn_can_manage_empresa(empresa_id))) WITH CHECK (((deleted_at IS NULL) AND a.fn_can_manage_empresa(empresa_id)));


--
-- Name: usuario usuario_select_self_or_tenant_admin; Type: POLICY; Schema: a; Owner: -
--

CREATE POLICY usuario_select_self_or_tenant_admin ON a.usuario FOR SELECT TO authenticated USING (((deleted_at IS NULL) AND ((id = a.fn_current_usuario_id()) OR a.fn_is_admin_of_same_tenant(id))));


--
-- Name: usuario_tenant; Type: ROW SECURITY; Schema: a; Owner: -
--

ALTER TABLE a.usuario_tenant ENABLE ROW LEVEL SECURITY;

--
-- Name: usuario_tenant usuario_tenant_insert_admin; Type: POLICY; Schema: a; Owner: -
--

CREATE POLICY usuario_tenant_insert_admin ON a.usuario_tenant FOR INSERT TO authenticated WITH CHECK (((deleted_at IS NULL) AND a.fn_is_tenant_admin(tenant_id)));


--
-- Name: usuario_tenant usuario_tenant_select_self_or_admin; Type: POLICY; Schema: a; Owner: -
--

CREATE POLICY usuario_tenant_select_self_or_admin ON a.usuario_tenant FOR SELECT TO authenticated USING (((deleted_at IS NULL) AND ((usuario_id = a.fn_current_usuario_id()) OR a.fn_is_tenant_admin(tenant_id))));


--
-- Name: usuario_tenant usuario_tenant_update_admin; Type: POLICY; Schema: a; Owner: -
--

CREATE POLICY usuario_tenant_update_admin ON a.usuario_tenant FOR UPDATE TO authenticated USING (((deleted_at IS NULL) AND a.fn_is_tenant_admin(tenant_id))) WITH CHECK (((deleted_at IS NULL) AND a.fn_is_tenant_admin(tenant_id)));


--
-- Name: usuario usuario_update_admin_only; Type: POLICY; Schema: a; Owner: -
--

CREATE POLICY usuario_update_admin_only ON a.usuario FOR UPDATE TO authenticated USING (((deleted_at IS NULL) AND a.fn_is_admin_of_same_tenant(id))) WITH CHECK (((deleted_at IS NULL) AND a.fn_is_admin_of_same_tenant(id)));


--
-- Name: audit_log_entries; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.audit_log_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: flow_state; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.flow_state ENABLE ROW LEVEL SECURITY;

--
-- Name: identities; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.identities ENABLE ROW LEVEL SECURITY;

--
-- Name: instances; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.instances ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_amr_claims; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.mfa_amr_claims ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_challenges; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.mfa_challenges ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_factors; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.mfa_factors ENABLE ROW LEVEL SECURITY;

--
-- Name: one_time_tokens; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.one_time_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: refresh_tokens; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.refresh_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: saml_providers; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.saml_providers ENABLE ROW LEVEL SECURITY;

--
-- Name: saml_relay_states; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.saml_relay_states ENABLE ROW LEVEL SECURITY;

--
-- Name: schema_migrations; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.schema_migrations ENABLE ROW LEVEL SECURITY;

--
-- Name: sessions; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: sso_domains; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.sso_domains ENABLE ROW LEVEL SECURITY;

--
-- Name: sso_providers; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.sso_providers ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.users ENABLE ROW LEVEL SECURITY;

--
-- Name: empresa; Type: ROW SECURITY; Schema: c; Owner: -
--

ALTER TABLE c.empresa ENABLE ROW LEVEL SECURITY;

--
-- Name: empresa empresa_insert_admin; Type: POLICY; Schema: c; Owner: -
--

CREATE POLICY empresa_insert_admin ON c.empresa FOR INSERT TO authenticated WITH CHECK (((deleted_at IS NULL) AND a.fn_is_tenant_admin(tenant_id)));


--
-- Name: empresa empresa_select_member; Type: POLICY; Schema: c; Owner: -
--

CREATE POLICY empresa_select_member ON c.empresa FOR SELECT TO authenticated USING (((deleted_at IS NULL) AND a.fn_is_tenant_member(tenant_id)));


--
-- Name: empresa empresa_update_admin; Type: POLICY; Schema: c; Owner: -
--

CREATE POLICY empresa_update_admin ON c.empresa FOR UPDATE TO authenticated USING (((deleted_at IS NULL) AND a.fn_is_tenant_admin(tenant_id))) WITH CHECK (((deleted_at IS NULL) AND a.fn_is_tenant_admin(tenant_id)));


--
-- Name: i_caixa; Type: ROW SECURITY; Schema: c; Owner: -
--

ALTER TABLE c.i_caixa ENABLE ROW LEVEL SECURITY;

--
-- Name: i_caixa i_caixa_all; Type: POLICY; Schema: c; Owner: -
--

CREATE POLICY i_caixa_all ON c.i_caixa TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND c.has_imobilizado_access() AND (deleted_at IS NULL))) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND c.has_imobilizado_access() AND (deleted_at IS NULL)));


--
-- Name: i_caixa_item; Type: ROW SECURITY; Schema: c; Owner: -
--

ALTER TABLE c.i_caixa_item ENABLE ROW LEVEL SECURITY;

--
-- Name: i_caixa_item i_caixa_item_all; Type: POLICY; Schema: c; Owner: -
--

CREATE POLICY i_caixa_item_all ON c.i_caixa_item TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND c.has_imobilizado_access() AND (deleted_at IS NULL))) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND c.has_imobilizado_access() AND (deleted_at IS NULL)));


--
-- Name: i_caixa_vinculo; Type: ROW SECURITY; Schema: c; Owner: -
--

ALTER TABLE c.i_caixa_vinculo ENABLE ROW LEVEL SECURITY;

--
-- Name: i_caixa_vinculo i_caixa_vinculo_all; Type: POLICY; Schema: c; Owner: -
--

CREATE POLICY i_caixa_vinculo_all ON c.i_caixa_vinculo TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND c.has_imobilizado_access() AND (deleted_at IS NULL))) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND c.has_imobilizado_access() AND (deleted_at IS NULL)));


--
-- Name: i_ferramenta_sugestao_xml i_ferr_sug_xml_all; Type: POLICY; Schema: c; Owner: -
--

CREATE POLICY i_ferr_sug_xml_all ON c.i_ferramenta_sugestao_xml TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND c.has_imobilizado_access() AND (deleted_at IS NULL))) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND c.has_imobilizado_access() AND (deleted_at IS NULL)));


--
-- Name: i_ferramenta_unidade i_ferr_unid_all; Type: POLICY; Schema: c; Owner: -
--

CREATE POLICY i_ferr_unid_all ON c.i_ferramenta_unidade TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND c.has_imobilizado_access() AND (deleted_at IS NULL))) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND c.has_imobilizado_access() AND (deleted_at IS NULL)));


--
-- Name: i_ferramenta_unidade_vinculo i_ferr_unid_vinc_all; Type: POLICY; Schema: c; Owner: -
--

CREATE POLICY i_ferr_unid_vinc_all ON c.i_ferramenta_unidade_vinculo TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND c.has_imobilizado_access() AND (deleted_at IS NULL))) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND c.has_imobilizado_access() AND (deleted_at IS NULL)));


--
-- Name: i_ferramenta; Type: ROW SECURITY; Schema: c; Owner: -
--

ALTER TABLE c.i_ferramenta ENABLE ROW LEVEL SECURITY;

--
-- Name: i_ferramenta i_ferramenta_all; Type: POLICY; Schema: c; Owner: -
--

CREATE POLICY i_ferramenta_all ON c.i_ferramenta TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND c.has_imobilizado_access() AND (deleted_at IS NULL))) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND c.has_imobilizado_access() AND (deleted_at IS NULL)));


--
-- Name: i_ferramenta_sugestao_xml; Type: ROW SECURITY; Schema: c; Owner: -
--

ALTER TABLE c.i_ferramenta_sugestao_xml ENABLE ROW LEVEL SECURITY;

--
-- Name: i_ferramenta_unidade; Type: ROW SECURITY; Schema: c; Owner: -
--

ALTER TABLE c.i_ferramenta_unidade ENABLE ROW LEVEL SECURITY;

--
-- Name: i_ferramenta_unidade_vinculo; Type: ROW SECURITY; Schema: c; Owner: -
--

ALTER TABLE c.i_ferramenta_unidade_vinculo ENABLE ROW LEVEL SECURITY;

--
-- Name: tenant; Type: ROW SECURITY; Schema: c; Owner: -
--

ALTER TABLE c.tenant ENABLE ROW LEVEL SECURITY;

--
-- Name: tenant tenant_select_member; Type: POLICY; Schema: c; Owner: -
--

CREATE POLICY tenant_select_member ON c.tenant FOR SELECT TO authenticated USING (((deleted_at IS NULL) AND a.fn_is_tenant_member(id)));


--
-- Name: tenant tenant_update_admin; Type: POLICY; Schema: c; Owner: -
--

CREATE POLICY tenant_update_admin ON c.tenant FOR UPDATE TO authenticated USING (((deleted_at IS NULL) AND a.fn_is_tenant_admin(id))) WITH CHECK (((deleted_at IS NULL) AND a.fn_is_tenant_admin(id)));


--
-- Name: anexo; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.anexo ENABLE ROW LEVEL SECURITY;

--
-- Name: anexo anexo_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY anexo_all ON f.anexo TO authenticated USING (((tenant_id = public.current_tenant_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND f.has_finance_access()));


--
-- Name: aprovacao_evento; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.aprovacao_evento ENABLE ROW LEVEL SECURITY;

--
-- Name: aprovacao_evento aprovacao_evento_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY aprovacao_evento_all ON f.aprovacao_evento TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access()));


--
-- Name: centro_custo; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.centro_custo ENABLE ROW LEVEL SECURITY;

--
-- Name: centro_custo centro_custo_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY centro_custo_all ON f.centro_custo TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access()));


--
-- Name: conciliacao_bancaria; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.conciliacao_bancaria ENABLE ROW LEVEL SECURITY;

--
-- Name: conciliacao_bancaria conciliacao_bancaria_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY conciliacao_bancaria_all ON f.conciliacao_bancaria TO authenticated USING (((tenant_id = public.current_tenant_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND f.has_finance_access()));


--
-- Name: conciliacao_lancamento; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.conciliacao_lancamento ENABLE ROW LEVEL SECURITY;

--
-- Name: conciliacao_lancamento conciliacao_lancamento_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY conciliacao_lancamento_all ON f.conciliacao_lancamento TO authenticated USING (((tenant_id = public.current_tenant_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND f.has_finance_access()));


--
-- Name: conta_bancaria; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.conta_bancaria ENABLE ROW LEVEL SECURITY;

--
-- Name: conta_bancaria conta_bancaria_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY conta_bancaria_all ON f.conta_bancaria TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access()));


--
-- Name: documento_fiscal; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.documento_fiscal ENABLE ROW LEVEL SECURITY;

--
-- Name: documento_fiscal documento_fiscal_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY documento_fiscal_all ON f.documento_fiscal TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access()));


--
-- Name: documento_fiscal_xml; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.documento_fiscal_xml ENABLE ROW LEVEL SECURITY;

--
-- Name: documento_fiscal_xml documento_fiscal_xml_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY documento_fiscal_xml_all ON f.documento_fiscal_xml TO authenticated USING (((tenant_id = public.current_tenant_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND f.has_finance_access()));


--
-- Name: evento_financeiro; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.evento_financeiro ENABLE ROW LEVEL SECURITY;

--
-- Name: evento_financeiro evento_financeiro_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY evento_financeiro_all ON f.evento_financeiro TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access()));


--
-- Name: extrato_bancario; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.extrato_bancario ENABLE ROW LEVEL SECURITY;

--
-- Name: extrato_bancario extrato_bancario_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY extrato_bancario_all ON f.extrato_bancario TO authenticated USING (((tenant_id = public.current_tenant_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND f.has_finance_access()));


--
-- Name: extrato_bancario_linha; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.extrato_bancario_linha ENABLE ROW LEVEL SECURITY;

--
-- Name: extrato_bancario_linha extrato_bancario_linha_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY extrato_bancario_linha_all ON f.extrato_bancario_linha TO authenticated USING (((tenant_id = public.current_tenant_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND f.has_finance_access()));


--
-- Name: fin_config; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.fin_config ENABLE ROW LEVEL SECURITY;

--
-- Name: fin_config fin_config_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY fin_config_all ON f.fin_config TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access()));


--
-- Name: importacao_doc_log; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.importacao_doc_log ENABLE ROW LEVEL SECURITY;

--
-- Name: importacao_doc_log importacao_doc_log_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY importacao_doc_log_all ON f.importacao_doc_log TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access()));


--
-- Name: imposto_retencao; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.imposto_retencao ENABLE ROW LEVEL SECURITY;

--
-- Name: imposto_retencao imposto_retencao_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY imposto_retencao_all ON f.imposto_retencao TO authenticated USING (((tenant_id = public.current_tenant_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND f.has_finance_access()));


--
-- Name: motivo_compra; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.motivo_compra ENABLE ROW LEVEL SECURITY;

--
-- Name: motivo_compra motivo_compra_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY motivo_compra_all ON f.motivo_compra TO authenticated USING (((tenant_id = public.current_tenant_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND f.has_finance_access()));


--
-- Name: motivo_compra motivo_compra_select_allowed_roles; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY motivo_compra_select_allowed_roles ON f.motivo_compra FOR SELECT TO authenticated USING (((deleted_at IS NULL) AND (ativo IS TRUE) AND f.has_motivo_compra_access(tenant_id)));


--
-- Name: pagamento; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.pagamento ENABLE ROW LEVEL SECURITY;

--
-- Name: pagamento pagamento_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY pagamento_all ON f.pagamento TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access()));


--
-- Name: pagamento_item; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.pagamento_item ENABLE ROW LEVEL SECURITY;

--
-- Name: pagamento_item pagamento_item_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY pagamento_item_all ON f.pagamento_item TO authenticated USING (((tenant_id = public.current_tenant_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND f.has_finance_access()));


--
-- Name: parametro_financeiro_empresa param_fin_emp_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY param_fin_emp_all ON f.parametro_financeiro_empresa TO authenticated USING (((tenant_id = public.current_tenant_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND f.has_finance_access()));


--
-- Name: parametro_financeiro_empresa; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.parametro_financeiro_empresa ENABLE ROW LEVEL SECURITY;

--
-- Name: plano_contas; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.plano_contas ENABLE ROW LEVEL SECURITY;

--
-- Name: plano_contas plano_contas_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY plano_contas_all ON f.plano_contas TO authenticated USING (((tenant_id = public.current_tenant_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND f.has_finance_access()));


--
-- Name: titulo; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.titulo ENABLE ROW LEVEL SECURITY;

--
-- Name: titulo_agendamento; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.titulo_agendamento ENABLE ROW LEVEL SECURITY;

--
-- Name: titulo_agendamento titulo_agendamento_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY titulo_agendamento_all ON f.titulo_agendamento TO authenticated USING (((tenant_id = public.current_tenant_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND f.has_finance_access()));


--
-- Name: titulo titulo_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY titulo_all ON f.titulo TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND f.has_finance_access()));


--
-- Name: titulo_aprovacao; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.titulo_aprovacao ENABLE ROW LEVEL SECURITY;

--
-- Name: titulo_aprovacao titulo_aprovacao_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY titulo_aprovacao_all ON f.titulo_aprovacao TO authenticated USING (((tenant_id = public.current_tenant_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND f.has_finance_access()));


--
-- Name: titulo_parcela; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.titulo_parcela ENABLE ROW LEVEL SECURITY;

--
-- Name: titulo_parcela titulo_parcela_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY titulo_parcela_all ON f.titulo_parcela TO authenticated USING (((tenant_id = public.current_tenant_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND f.has_finance_access()));


--
-- Name: titulo_rateio; Type: ROW SECURITY; Schema: f; Owner: -
--

ALTER TABLE f.titulo_rateio ENABLE ROW LEVEL SECURITY;

--
-- Name: titulo_rateio titulo_rateio_all; Type: POLICY; Schema: f; Owner: -
--

CREATE POLICY titulo_rateio_all ON f.titulo_rateio TO authenticated USING (((tenant_id = public.current_tenant_id()) AND f.has_finance_access())) WITH CHECK (((tenant_id = public.current_tenant_id()) AND f.has_finance_access()));


--
-- Name: tenants Users can view their tenants; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view their tenants" ON public.tenants FOR SELECT USING ((id IN ( SELECT tenant_memberships.tenant_id
   FROM public.tenant_memberships
  WHERE ((tenant_memberships.user_id = auth.uid()) AND (tenant_memberships.status = 'active'::text)))));


--
-- Name: apontamentos_horas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.apontamentos_horas ENABLE ROW LEVEL SECURITY;

--
-- Name: apontamentos_horas apontamentos_horas_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY apontamentos_horas_delete ON public.apontamentos_horas FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.empresa_memberships em
  WHERE ((em.user_id = auth.uid()) AND (em.tenant_id = em.tenant_id) AND (em.empresa_id = em.empresa_id) AND (em.status = ANY (ARRAY['active'::text, 'ativo'::text]))))));


--
-- Name: apontamentos_horas apontamentos_horas_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY apontamentos_horas_insert ON public.apontamentos_horas FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM public.empresa_memberships em
  WHERE ((em.user_id = auth.uid()) AND (em.tenant_id = em.tenant_id) AND (em.empresa_id = em.empresa_id) AND (em.status = ANY (ARRAY['active'::text, 'ativo'::text]))))));


--
-- Name: apontamentos_horas apontamentos_horas_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY apontamentos_horas_select ON public.apontamentos_horas FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.empresa_memberships em
  WHERE ((em.user_id = auth.uid()) AND (em.tenant_id = em.tenant_id) AND (em.empresa_id = em.empresa_id) AND (em.status = ANY (ARRAY['active'::text, 'ativo'::text]))))));


--
-- Name: apontamentos_horas apontamentos_horas_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY apontamentos_horas_update ON public.apontamentos_horas FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.empresa_memberships em
  WHERE ((em.user_id = auth.uid()) AND (em.tenant_id = em.tenant_id) AND (em.empresa_id = em.empresa_id) AND (em.status = ANY (ARRAY['active'::text, 'ativo'::text])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.empresa_memberships em
  WHERE ((em.user_id = auth.uid()) AND (em.tenant_id = em.tenant_id) AND (em.empresa_id = em.empresa_id) AND (em.status = ANY (ARRAY['active'::text, 'ativo'::text]))))));


--
-- Name: cliente_hh_servicos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cliente_hh_servicos ENABLE ROW LEVEL SECURITY;

--
-- Name: cliente_hh_servicos cliente_hh_servicos_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cliente_hh_servicos_delete ON public.cliente_hh_servicos FOR DELETE USING (((tenant_id = public.current_tenant_id()) AND (public.can__legacy_40734('admin'::text, 'manage_users'::text) OR public.can__legacy_40734('financeiro'::text, 'read'::text))));


--
-- Name: cliente_hh_servicos cliente_hh_servicos_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cliente_hh_servicos_insert ON public.cliente_hh_servicos FOR INSERT WITH CHECK (((tenant_id = public.current_tenant_id()) AND (public.can__legacy_40734('admin'::text, 'manage_users'::text) OR public.can__legacy_40734('financeiro'::text, 'read'::text) OR public.can__legacy_40734('apontamentos'::text, 'write'::text))));


--
-- Name: cliente_hh_servicos cliente_hh_servicos_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cliente_hh_servicos_select ON public.cliente_hh_servicos FOR SELECT USING (((tenant_id = public.current_tenant_id()) AND (public.can__legacy_40734('admin'::text, 'manage_users'::text) OR public.can__legacy_40734('financeiro'::text, 'read'::text) OR public.can__legacy_40734('apontamentos'::text, 'read'::text) OR public.can__legacy_40734('apontamentos'::text, 'write'::text))));


--
-- Name: cliente_hh_servicos cliente_hh_servicos_tenant_empresa_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cliente_hh_servicos_tenant_empresa_policy ON public.cliente_hh_servicos USING (((tenant_id = public.current_tenant_id()) AND (public.can__legacy_40734('admin'::text, 'manage_users'::text) OR public.can__legacy_40734('financeiro'::text, 'read'::text) OR public.can__legacy_40734('apontamentos'::text, 'read'::text) OR public.can__legacy_40734('apontamentos'::text, 'write'::text))));


--
-- Name: cliente_hh_servicos cliente_hh_servicos_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cliente_hh_servicos_update ON public.cliente_hh_servicos FOR UPDATE USING (((tenant_id = public.current_tenant_id()) AND (public.can__legacy_40734('admin'::text, 'manage_users'::text) OR public.can__legacy_40734('financeiro'::text, 'read'::text) OR public.can__legacy_40734('apontamentos'::text, 'write'::text)))) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (public.can__legacy_40734('admin'::text, 'manage_users'::text) OR public.can__legacy_40734('financeiro'::text, 'read'::text) OR public.can__legacy_40734('apontamentos'::text, 'write'::text))));


--
-- Name: cliente_hh_tabelas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cliente_hh_tabelas ENABLE ROW LEVEL SECURITY;

--
-- Name: cliente_hh_tabelas cliente_hh_tabelas_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cliente_hh_tabelas_delete ON public.cliente_hh_tabelas FOR DELETE TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND public.can__legacy_40734('os'::text, 'delete'::text)));


--
-- Name: cliente_hh_tabelas cliente_hh_tabelas_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cliente_hh_tabelas_insert ON public.cliente_hh_tabelas FOR INSERT TO authenticated WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND public.can__legacy_40734('os'::text, 'write'::text)));


--
-- Name: cliente_hh_tabelas cliente_hh_tabelas_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cliente_hh_tabelas_select ON public.cliente_hh_tabelas FOR SELECT TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND public.can__legacy_40734('os'::text, 'read'::text)));


--
-- Name: cliente_hh_tabelas cliente_hh_tabelas_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cliente_hh_tabelas_update ON public.cliente_hh_tabelas FOR UPDATE TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND public.can__legacy_40734('os'::text, 'write'::text))) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND public.can__legacy_40734('os'::text, 'write'::text)));


--
-- Name: clientes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.clientes ENABLE ROW LEVEL SECURITY;

--
-- Name: clientes clientes_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY clientes_delete ON public.clientes FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM (a.usuario_empresa ue
     JOIN public.empresas emp ON ((emp.id = ue.empresa_id)))
  WHERE ((ue.usuario_id = a.fn_current_usuario_id()) AND (ue.deleted_at IS NULL) AND (ue.ativo = true) AND (ue.empresa_id = clientes.empresa_id) AND (emp.tenant_id = clientes.tenant_id) AND (upper(ue.papel) = 'ADMIN'::text)))));


--
-- Name: clientes clientes_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY clientes_insert ON public.clientes FOR INSERT TO authenticated WITH CHECK (((public.can('cad_clientes'::text, 'write'::text) OR (EXISTS ( SELECT 1
   FROM (a.usuario_empresa ue
     JOIN public.empresas emp ON ((emp.id = ue.empresa_id)))
  WHERE ((ue.usuario_id = a.fn_current_usuario_id()) AND (ue.deleted_at IS NULL) AND (ue.ativo = true) AND (ue.empresa_id = clientes.empresa_id) AND (emp.tenant_id = clientes.tenant_id) AND (upper(ue.papel) = ANY (ARRAY['ADMIN'::text, 'FINANCEIRO'::text, 'COORDENACAO'::text, 'COMPRAS'::text])))))) AND (tenant_id = ( SELECT e.tenant_id
   FROM public.empresas e
  WHERE (e.id = clientes.empresa_id)
 LIMIT 1))));


--
-- Name: clientes clientes_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY clientes_select ON public.clientes FOR SELECT TO authenticated USING ((public.can('os'::text, 'read'::text) OR public.can('cad_clientes'::text, 'write'::text) OR (EXISTS ( SELECT 1
   FROM (a.usuario_empresa ue
     JOIN public.empresas emp ON ((emp.id = ue.empresa_id)))
  WHERE ((ue.usuario_id = a.fn_current_usuario_id()) AND (ue.deleted_at IS NULL) AND (ue.ativo = true) AND (ue.empresa_id = clientes.empresa_id) AND (emp.tenant_id = clientes.tenant_id) AND (upper(ue.papel) = ANY (ARRAY['ADMIN'::text, 'FINANCEIRO'::text, 'COORDENACAO'::text, 'COMPRAS'::text])))))));


--
-- Name: clientes clientes_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY clientes_update ON public.clientes FOR UPDATE TO authenticated USING ((public.can('cad_clientes'::text, 'write'::text) OR (EXISTS ( SELECT 1
   FROM (a.usuario_empresa ue
     JOIN public.empresas emp ON ((emp.id = ue.empresa_id)))
  WHERE ((ue.usuario_id = a.fn_current_usuario_id()) AND (ue.deleted_at IS NULL) AND (ue.ativo = true) AND (ue.empresa_id = clientes.empresa_id) AND (emp.tenant_id = clientes.tenant_id) AND (upper(ue.papel) = ANY (ARRAY['ADMIN'::text, 'FINANCEIRO'::text, 'COORDENACAO'::text, 'COMPRAS'::text]))))))) WITH CHECK (((public.can('cad_clientes'::text, 'write'::text) OR (EXISTS ( SELECT 1
   FROM (a.usuario_empresa ue
     JOIN public.empresas emp ON ((emp.id = ue.empresa_id)))
  WHERE ((ue.usuario_id = a.fn_current_usuario_id()) AND (ue.deleted_at IS NULL) AND (ue.ativo = true) AND (ue.empresa_id = clientes.empresa_id) AND (emp.tenant_id = clientes.tenant_id) AND (upper(ue.papel) = ANY (ARRAY['ADMIN'::text, 'FINANCEIRO'::text, 'COORDENACAO'::text, 'COMPRAS'::text])))))) AND (tenant_id = ( SELECT e.tenant_id
   FROM public.empresas e
  WHERE (e.id = clientes.empresa_id)
 LIMIT 1))));


--
-- Name: colaborador_cliente_funcao; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.colaborador_cliente_funcao ENABLE ROW LEVEL SECURITY;

--
-- Name: colaborador_cliente_funcao colaborador_cliente_funcao_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaborador_cliente_funcao_delete ON public.colaborador_cliente_funcao FOR DELETE USING (((tenant_id = public.current_tenant_id()) AND (public.can__legacy_40734('admin'::text, 'manage_users'::text) OR public.can__legacy_40734('financeiro'::text, 'read'::text))));


--
-- Name: colaborador_cliente_funcao colaborador_cliente_funcao_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaborador_cliente_funcao_insert ON public.colaborador_cliente_funcao FOR INSERT WITH CHECK (((tenant_id = public.current_tenant_id()) AND (public.can__legacy_40734('admin'::text, 'manage_users'::text) OR public.can__legacy_40734('financeiro'::text, 'read'::text) OR public.can__legacy_40734('apontamentos'::text, 'write'::text))));


--
-- Name: colaborador_cliente_funcao colaborador_cliente_funcao_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaborador_cliente_funcao_select ON public.colaborador_cliente_funcao FOR SELECT USING (((tenant_id = public.current_tenant_id()) AND (public.can__legacy_40734('admin'::text, 'manage_users'::text) OR public.can__legacy_40734('financeiro'::text, 'read'::text) OR public.can__legacy_40734('apontamentos'::text, 'read'::text) OR public.can__legacy_40734('apontamentos'::text, 'write'::text))));


--
-- Name: colaborador_cliente_funcao colaborador_cliente_funcao_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaborador_cliente_funcao_update ON public.colaborador_cliente_funcao FOR UPDATE USING (((tenant_id = public.current_tenant_id()) AND (public.can__legacy_40734('admin'::text, 'manage_users'::text) OR public.can__legacy_40734('financeiro'::text, 'read'::text) OR public.can__legacy_40734('apontamentos'::text, 'write'::text)))) WITH CHECK (((tenant_id = public.current_tenant_id()) AND (public.can__legacy_40734('admin'::text, 'manage_users'::text) OR public.can__legacy_40734('financeiro'::text, 'read'::text) OR public.can__legacy_40734('apontamentos'::text, 'write'::text))));


--
-- Name: colaborador_funcao_hh; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.colaborador_funcao_hh ENABLE ROW LEVEL SECURITY;

--
-- Name: colaborador_funcao_hh colaborador_funcao_hh_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaborador_funcao_hh_delete ON public.colaborador_funcao_hh FOR DELETE USING (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('apontamentos'::text, 'write'::text)));


--
-- Name: colaborador_funcao_hh colaborador_funcao_hh_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaborador_funcao_hh_insert ON public.colaborador_funcao_hh FOR INSERT WITH CHECK (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('apontamentos'::text, 'write'::text)));


--
-- Name: colaborador_funcao_hh colaborador_funcao_hh_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaborador_funcao_hh_select ON public.colaborador_funcao_hh FOR SELECT USING ((tenant_id = public.current_tenant_id()));


--
-- Name: colaborador_funcao_hh colaborador_funcao_hh_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaborador_funcao_hh_update ON public.colaborador_funcao_hh FOR UPDATE USING (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('apontamentos'::text, 'write'::text))) WITH CHECK (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('apontamentos'::text, 'write'::text)));


--
-- Name: colaborador_taxas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.colaborador_taxas ENABLE ROW LEVEL SECURITY;

--
-- Name: colaborador_taxas colaborador_taxas_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaborador_taxas_delete ON public.colaborador_taxas FOR DELETE TO authenticated USING (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('apontamentos'::text, 'config'::text)));


--
-- Name: colaborador_taxas colaborador_taxas_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaborador_taxas_insert ON public.colaborador_taxas FOR INSERT TO authenticated WITH CHECK (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('apontamentos'::text, 'config'::text)));


--
-- Name: colaborador_taxas colaborador_taxas_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaborador_taxas_select ON public.colaborador_taxas FOR SELECT TO authenticated USING (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('apontamentos'::text, 'read'::text)));


--
-- Name: colaborador_taxas colaborador_taxas_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaborador_taxas_update ON public.colaborador_taxas FOR UPDATE TO authenticated USING (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('apontamentos'::text, 'config'::text))) WITH CHECK (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('apontamentos'::text, 'config'::text)));


--
-- Name: colaboradores; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.colaboradores ENABLE ROW LEVEL SECURITY;

--
-- Name: colaboradores colaboradores_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaboradores_delete ON public.colaboradores FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = colaboradores.tenant_id) AND (tm.status = ANY (ARRAY['active'::text, 'ativo'::text]))))));


--
-- Name: colaboradores colaboradores_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaboradores_insert ON public.colaboradores FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = colaboradores.tenant_id) AND (tm.status = ANY (ARRAY['active'::text, 'ativo'::text]))))));


--
-- Name: colaboradores colaboradores_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaboradores_select ON public.colaboradores FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = colaboradores.tenant_id) AND (tm.status = ANY (ARRAY['active'::text, 'ativo'::text]))))));


--
-- Name: colaboradores colaboradores_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaboradores_update ON public.colaboradores FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = colaboradores.tenant_id) AND (tm.status = ANY (ARRAY['active'::text, 'ativo'::text])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = colaboradores.tenant_id) AND (tm.status = ANY (ARRAY['active'::text, 'ativo'::text]))))));


--
-- Name: empresa_memberships; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.empresa_memberships ENABLE ROW LEVEL SECURITY;

--
-- Name: empresa_memberships empresa_memberships_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY empresa_memberships_delete ON public.empresa_memberships FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = empresa_memberships.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text)))));


--
-- Name: empresa_memberships empresa_memberships_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY empresa_memberships_insert ON public.empresa_memberships FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = empresa_memberships.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text)))));


--
-- Name: empresa_memberships empresa_memberships_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY empresa_memberships_select ON public.empresa_memberships FOR SELECT USING (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = empresa_memberships.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text))))));


--
-- Name: empresa_memberships empresa_memberships_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY empresa_memberships_update ON public.empresa_memberships FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = empresa_memberships.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = empresa_memberships.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text)))));


--
-- Name: empresas empresas_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY empresas_delete ON public.empresas FOR DELETE USING (((tenant_id = public.current_tenant_id()) AND public.has_permission('admin.manage_users'::text)));


--
-- Name: empresas empresas_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY empresas_insert ON public.empresas FOR INSERT WITH CHECK (((tenant_id = public.current_tenant_id()) AND public.has_permission('admin.manage_users'::text)));


--
-- Name: empresas empresas_select_a; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY empresas_select_a ON public.empresas FOR SELECT TO authenticated USING ((public.a_is_empresa_member(id) OR public.a_is_tenant_role(tenant_id, ARRAY['admin'::text, 'estoque'::text, 'fiscal'::text, 'projetos'::text, 'financeiro'::text])));


--
-- Name: empresas empresas_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY empresas_update ON public.empresas FOR UPDATE USING (((tenant_id = public.current_tenant_id()) AND public.has_permission('admin.manage_users'::text))) WITH CHECK (((tenant_id = public.current_tenant_id()) AND public.has_permission('admin.manage_users'::text)));


--
-- Name: estoque; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.estoque ENABLE ROW LEVEL SECURITY;

--
-- Name: estoque estoque_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY estoque_delete ON public.estoque FOR DELETE TO authenticated USING (((empresa_id IS NOT NULL) AND public.can__legacy_40734('estoque'::text, 'write'::text)));


--
-- Name: estoque estoque_delete_a; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY estoque_delete_a ON public.estoque FOR DELETE TO authenticated USING (((empresa_id IS NOT NULL) AND public.a_is_tenant_role(tenant_id, ARRAY['admin'::text])));


--
-- Name: estoque estoque_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY estoque_insert ON public.estoque FOR INSERT TO authenticated WITH CHECK (((empresa_id IS NOT NULL) AND public.can__legacy_40734('estoque'::text, 'write'::text)));


--
-- Name: estoque estoque_insert_a; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY estoque_insert_a ON public.estoque FOR INSERT TO authenticated WITH CHECK (((empresa_id IS NOT NULL) AND public.a_is_tenant_role(tenant_id, ARRAY['admin'::text, 'estoque'::text, 'fiscal'::text])));


--
-- Name: estoque estoque_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY estoque_select ON public.estoque FOR SELECT TO authenticated USING (((empresa_id IS NOT NULL) AND public.can__legacy_40734('estoque'::text, 'read'::text)));


--
-- Name: estoque estoque_select_a; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY estoque_select_a ON public.estoque FOR SELECT TO authenticated USING (((empresa_id IS NOT NULL) AND public.a_is_tenant_role(tenant_id, ARRAY['admin'::text, 'estoque'::text, 'fiscal'::text])));


--
-- Name: estoque estoque_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY estoque_update ON public.estoque FOR UPDATE TO authenticated USING (((empresa_id IS NOT NULL) AND public.can__legacy_40734('estoque'::text, 'write'::text))) WITH CHECK (((empresa_id IS NOT NULL) AND public.can__legacy_40734('estoque'::text, 'write'::text)));


--
-- Name: estoque estoque_update_a; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY estoque_update_a ON public.estoque FOR UPDATE TO authenticated USING (((empresa_id IS NOT NULL) AND public.a_is_tenant_role(tenant_id, ARRAY['admin'::text, 'estoque'::text, 'fiscal'::text]))) WITH CHECK (((empresa_id IS NOT NULL) AND public.a_is_tenant_role(tenant_id, ARRAY['admin'::text, 'estoque'::text, 'fiscal'::text])));


--
-- Name: fiscal_itens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.fiscal_itens ENABLE ROW LEVEL SECURITY;

--
-- Name: fiscal_itens fiscal_itens_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fiscal_itens_delete ON public.fiscal_itens FOR DELETE TO authenticated USING (((empresa_id IS NOT NULL) AND (tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('fiscal_itens'::text, 'write'::text)));


--
-- Name: fiscal_itens fiscal_itens_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fiscal_itens_insert ON public.fiscal_itens FOR INSERT TO authenticated WITH CHECK (((empresa_id IS NOT NULL) AND (tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('fiscal_itens'::text, 'write'::text)));


--
-- Name: fiscal_itens fiscal_itens_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fiscal_itens_select ON public.fiscal_itens FOR SELECT TO authenticated USING (((empresa_id IS NOT NULL) AND (tenant_id = public.current_tenant_id()) AND (public.can__legacy_40734('fiscal_nf'::text, 'read'::text) OR public.can__legacy_40734('fiscal_itens'::text, 'write'::text))));


--
-- Name: fiscal_itens fiscal_itens_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fiscal_itens_update ON public.fiscal_itens FOR UPDATE TO authenticated USING (((empresa_id IS NOT NULL) AND (tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('fiscal_itens'::text, 'write'::text))) WITH CHECK (((empresa_id IS NOT NULL) AND (tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('fiscal_itens'::text, 'write'::text)));


--
-- Name: fornecedores; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.fornecedores ENABLE ROW LEVEL SECURITY;

--
-- Name: fornecedores fornecedores_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fornecedores_delete ON public.fornecedores FOR DELETE TO authenticated USING ((public.can__legacy_40734('cad_fornecedores'::text, 'write'::text) OR public.can__legacy_40734('estoque'::text, 'write'::text)));


--
-- Name: fornecedores fornecedores_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fornecedores_insert ON public.fornecedores FOR INSERT TO authenticated WITH CHECK ((public.can__legacy_40734('cad_fornecedores'::text, 'write'::text) OR public.can__legacy_40734('estoque'::text, 'write'::text)));


--
-- Name: fornecedores fornecedores_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fornecedores_select ON public.fornecedores FOR SELECT TO authenticated USING ((public.can__legacy_40734('estoque'::text, 'read'::text) OR public.can__legacy_40734('cad_fornecedores'::text, 'write'::text)));


--
-- Name: fornecedores fornecedores_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fornecedores_update ON public.fornecedores FOR UPDATE TO authenticated USING ((public.can__legacy_40734('cad_fornecedores'::text, 'write'::text) OR public.can__legacy_40734('estoque'::text, 'write'::text))) WITH CHECK ((public.can__legacy_40734('cad_fornecedores'::text, 'write'::text) OR public.can__legacy_40734('estoque'::text, 'write'::text)));


--
-- Name: hh_especialidades; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.hh_especialidades ENABLE ROW LEVEL SECURITY;

--
-- Name: hh_especialidades hh_especialidades_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hh_especialidades_delete ON public.hh_especialidades FOR DELETE USING (((tenant_id = public.current_tenant_id()) AND public.can('hh'::text, 'delete'::text)));


--
-- Name: hh_especialidades hh_especialidades_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hh_especialidades_insert ON public.hh_especialidades FOR INSERT WITH CHECK (((tenant_id = public.current_tenant_id()) AND public.can('hh'::text, 'write'::text)));


--
-- Name: hh_especialidades hh_especialidades_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hh_especialidades_select ON public.hh_especialidades FOR SELECT USING (((tenant_id = public.current_tenant_id()) AND public.can('hh'::text, 'read'::text)));


--
-- Name: hh_especialidades hh_especialidades_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hh_especialidades_update ON public.hh_especialidades FOR UPDATE USING (((tenant_id = public.current_tenant_id()) AND public.can('hh'::text, 'write'::text))) WITH CHECK (((tenant_id = public.current_tenant_id()) AND public.can('hh'::text, 'write'::text)));


--
-- Name: hh_lancamentos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.hh_lancamentos ENABLE ROW LEVEL SECURITY;

--
-- Name: hh_lancamentos hh_lancamentos_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hh_lancamentos_delete ON public.hh_lancamentos FOR DELETE USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND public.can__legacy_40734('os'::text, 'delete'::text)));


--
-- Name: hh_lancamentos hh_lancamentos_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hh_lancamentos_insert ON public.hh_lancamentos FOR INSERT WITH CHECK (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND public.can__legacy_40734('os'::text, 'write'::text)));


--
-- Name: hh_lancamentos hh_lancamentos_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hh_lancamentos_select ON public.hh_lancamentos FOR SELECT USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND public.can__legacy_40734('os'::text, 'read'::text)));


--
-- Name: hh_lancamentos hh_lancamentos_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hh_lancamentos_tenant_isolation ON public.hh_lancamentos USING ((tenant_id = public.current_tenant_id()));


--
-- Name: hh_lancamentos hh_lancamentos_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hh_lancamentos_update ON public.hh_lancamentos FOR UPDATE USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND public.can__legacy_40734('os'::text, 'write'::text)));


--
-- Name: itens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.itens ENABLE ROW LEVEL SECURITY;

--
-- Name: itens itens_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY itens_delete ON public.itens FOR DELETE TO authenticated USING ((public.can__legacy_40734('cad_itens'::text, 'write'::text) OR public.can__legacy_40734('estoque'::text, 'write'::text)));


--
-- Name: itens itens_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY itens_insert ON public.itens FOR INSERT TO authenticated WITH CHECK ((public.can__legacy_40734('cad_itens'::text, 'write'::text) OR public.can__legacy_40734('estoque'::text, 'write'::text)));


--
-- Name: itens itens_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY itens_select ON public.itens FOR SELECT TO authenticated USING ((public.can__legacy_40734('estoque'::text, 'read'::text) OR public.can__legacy_40734('os'::text, 'read'::text) OR public.can__legacy_40734('cad_itens'::text, 'write'::text)));


--
-- Name: itens itens_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY itens_update ON public.itens FOR UPDATE TO authenticated USING ((public.can__legacy_40734('cad_itens'::text, 'write'::text) OR public.can__legacy_40734('estoque'::text, 'write'::text))) WITH CHECK ((public.can__legacy_40734('cad_itens'::text, 'write'::text) OR public.can__legacy_40734('estoque'::text, 'write'::text)));


--
-- Name: membership_roles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.membership_roles ENABLE ROW LEVEL SECURITY;

--
-- Name: membership_roles membership_roles_delete_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY membership_roles_delete_admin ON public.membership_roles FOR DELETE TO authenticated USING ((public.has_permission('admin.users.manage'::text) AND (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.id = membership_roles.membership_id) AND (tm.tenant_id = public.current_tenant_id()))))));


--
-- Name: membership_roles membership_roles_insert_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY membership_roles_insert_admin ON public.membership_roles FOR INSERT TO authenticated WITH CHECK ((public.has_permission('admin.users.manage'::text) AND (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.id = membership_roles.membership_id) AND (tm.tenant_id = public.current_tenant_id()))))));


--
-- Name: membership_roles membership_roles_select_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY membership_roles_select_admin ON public.membership_roles FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.id = membership_roles.membership_id) AND (tm.tenant_id = public.current_tenant_id())))) AND public.can__legacy_40734('admin'::text, 'manage_users'::text)));


--
-- Name: membership_roles membership_roles_select_self; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY membership_roles_select_self ON public.membership_roles FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.id = membership_roles.membership_id) AND (tm.user_id = auth.uid())))));


--
-- Name: tenant_memberships memberships_delete_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY memberships_delete_admin ON public.tenant_memberships FOR DELETE TO authenticated USING (((tenant_id = public.current_tenant_id()) AND public.has_permission('admin.users.manage'::text)));


--
-- Name: tenant_memberships memberships_insert_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY memberships_insert_admin ON public.tenant_memberships FOR INSERT TO authenticated WITH CHECK (((tenant_id = public.current_tenant_id()) AND public.has_permission('admin.users.manage'::text)));


--
-- Name: tenant_memberships memberships_select_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY memberships_select_admin ON public.tenant_memberships FOR SELECT TO authenticated USING (((tenant_id = public.current_tenant_id()) AND public.has_permission('admin.users.manage'::text)));


--
-- Name: tenant_memberships memberships_select_self; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY memberships_select_self ON public.tenant_memberships FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: tenant_memberships memberships_update_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY memberships_update_admin ON public.tenant_memberships FOR UPDATE TO authenticated USING (((tenant_id = public.current_tenant_id()) AND public.has_permission('admin.users.manage'::text))) WITH CHECK (((tenant_id = public.current_tenant_id()) AND public.has_permission('admin.users.manage'::text)));


--
-- Name: movimentacoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.movimentacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: movimentacoes movimentacoes_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY movimentacoes_delete ON public.movimentacoes FOR DELETE TO authenticated USING (((empresa_id IS NOT NULL) AND public.can__legacy_40734('estoque'::text, 'write'::text)));


--
-- Name: movimentacoes movimentacoes_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY movimentacoes_insert ON public.movimentacoes FOR INSERT TO authenticated WITH CHECK (((empresa_id IS NOT NULL) AND public.can__legacy_40734('estoque'::text, 'write'::text)));


--
-- Name: movimentacoes movimentacoes_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY movimentacoes_select ON public.movimentacoes FOR SELECT TO authenticated USING (((empresa_id IS NOT NULL) AND public.can__legacy_40734('estoque'::text, 'read'::text)));


--
-- Name: movimentacoes movimentacoes_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY movimentacoes_update ON public.movimentacoes FOR UPDATE TO authenticated USING (((empresa_id IS NOT NULL) AND public.can__legacy_40734('estoque'::text, 'write'::text))) WITH CHECK (((empresa_id IS NOT NULL) AND public.can__legacy_40734('estoque'::text, 'write'::text)));


--
-- Name: nf_entrada; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.nf_entrada ENABLE ROW LEVEL SECURITY;

--
-- Name: nf_entrada nf_entrada_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY nf_entrada_delete ON public.nf_entrada FOR DELETE TO authenticated USING (((empresa_id IS NOT NULL) AND (tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('fiscal_nf'::text, 'delete'::text)));


--
-- Name: nf_entrada nf_entrada_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY nf_entrada_insert ON public.nf_entrada FOR INSERT TO authenticated WITH CHECK (((empresa_id IS NOT NULL) AND (tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('fiscal_nf'::text, 'write'::text)));


--
-- Name: nf_entrada_itens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.nf_entrada_itens ENABLE ROW LEVEL SECURITY;

--
-- Name: nf_entrada_itens nf_entrada_itens_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY nf_entrada_itens_delete ON public.nf_entrada_itens FOR DELETE TO authenticated USING (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('fiscal_nf'::text, 'delete'::text)));


--
-- Name: nf_entrada_itens nf_entrada_itens_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY nf_entrada_itens_insert ON public.nf_entrada_itens FOR INSERT TO authenticated WITH CHECK (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('fiscal_nf'::text, 'write'::text)));


--
-- Name: nf_entrada_itens nf_entrada_itens_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY nf_entrada_itens_select ON public.nf_entrada_itens FOR SELECT TO authenticated USING (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('fiscal_nf'::text, 'read'::text)));


--
-- Name: nf_entrada_itens nf_entrada_itens_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY nf_entrada_itens_update ON public.nf_entrada_itens FOR UPDATE TO authenticated USING (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('fiscal_nf'::text, 'write'::text))) WITH CHECK (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('fiscal_nf'::text, 'write'::text)));


--
-- Name: nf_entrada nf_entrada_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY nf_entrada_select ON public.nf_entrada FOR SELECT TO authenticated USING (((empresa_id IS NOT NULL) AND (tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('fiscal_nf'::text, 'read'::text)));


--
-- Name: nf_entrada nf_entrada_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY nf_entrada_update ON public.nf_entrada FOR UPDATE TO authenticated USING (((empresa_id IS NOT NULL) AND (tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('fiscal_nf'::text, 'write'::text))) WITH CHECK (((empresa_id IS NOT NULL) AND (tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('fiscal_nf'::text, 'write'::text)));


--
-- Name: ordens_servico; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ordens_servico ENABLE ROW LEVEL SECURITY;

--
-- Name: ordens_servico ordens_servico_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ordens_servico_delete ON public.ordens_servico FOR DELETE TO authenticated USING (public.can__legacy_40734('os'::text, 'delete'::text));


--
-- Name: ordens_servico ordens_servico_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ordens_servico_insert ON public.ordens_servico FOR INSERT TO authenticated WITH CHECK (public.can__legacy_40734('os'::text, 'write'::text));


--
-- Name: ordens_servico ordens_servico_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ordens_servico_select ON public.ordens_servico FOR SELECT TO authenticated USING (public.can__legacy_40734('os'::text, 'read'::text));


--
-- Name: ordens_servico ordens_servico_select_painel_tv; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ordens_servico_select_painel_tv ON public.ordens_servico FOR SELECT TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND (EXISTS ( SELECT 1
   FROM (a.usuario u
     JOIN a.usuario_empresa ue ON ((ue.usuario_id = u.id)))
  WHERE ((u.auth_user_id = auth.uid()) AND (u.deleted_at IS NULL) AND (ue.deleted_at IS NULL) AND (ue.ativo = true) AND (ue.empresa_id = public.current_empresa_id()) AND (ue.papel = 'PAINEL_TV'::text))))));


--
-- Name: ordens_servico ordens_servico_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ordens_servico_update ON public.ordens_servico FOR UPDATE TO authenticated USING (public.can__legacy_40734('os'::text, 'write'::text)) WITH CHECK (public.can__legacy_40734('os'::text, 'write'::text));


--
-- Name: os_gestao_itens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.os_gestao_itens ENABLE ROW LEVEL SECURITY;

--
-- Name: os_gestao_itens os_gestao_itens_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY os_gestao_itens_delete ON public.os_gestao_itens FOR DELETE TO authenticated USING (public.can__legacy_40734('os_gestao'::text, 'write'::text));


--
-- Name: os_gestao_itens os_gestao_itens_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY os_gestao_itens_insert ON public.os_gestao_itens FOR INSERT TO authenticated WITH CHECK (public.can__legacy_40734('os_gestao'::text, 'write'::text));


--
-- Name: os_gestao_itens os_gestao_itens_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY os_gestao_itens_select ON public.os_gestao_itens FOR SELECT TO authenticated USING (public.can__legacy_40734('os'::text, 'read'::text));


--
-- Name: os_gestao_itens os_gestao_itens_select_painel_tv; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY os_gestao_itens_select_painel_tv ON public.os_gestao_itens FOR SELECT TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (empresa_id = public.current_empresa_id()) AND (EXISTS ( SELECT 1
   FROM (a.usuario u
     JOIN a.usuario_empresa ue ON ((ue.usuario_id = u.id)))
  WHERE ((u.auth_user_id = auth.uid()) AND (u.deleted_at IS NULL) AND (ue.deleted_at IS NULL) AND (ue.ativo = true) AND (ue.empresa_id = public.current_empresa_id()) AND (ue.papel = 'PAINEL_TV'::text))))));


--
-- Name: os_gestao_itens os_gestao_itens_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY os_gestao_itens_update ON public.os_gestao_itens FOR UPDATE TO authenticated USING (public.can__legacy_40734('os_gestao'::text, 'write'::text)) WITH CHECK (public.can__legacy_40734('os_gestao'::text, 'write'::text));


--
-- Name: os_itens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.os_itens ENABLE ROW LEVEL SECURITY;

--
-- Name: os_itens os_itens_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY os_itens_delete ON public.os_itens FOR DELETE TO authenticated USING (public.can__legacy_40734('os_itens'::text, 'write'::text));


--
-- Name: os_itens os_itens_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY os_itens_insert ON public.os_itens FOR INSERT TO authenticated WITH CHECK (public.can__legacy_40734('os_itens'::text, 'write'::text));


--
-- Name: os_itens os_itens_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY os_itens_select ON public.os_itens FOR SELECT TO authenticated USING (public.can__legacy_40734('os'::text, 'read'::text));


--
-- Name: os_itens os_itens_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY os_itens_update ON public.os_itens FOR UPDATE TO authenticated USING (public.can__legacy_40734('os_itens'::text, 'write'::text)) WITH CHECK (public.can__legacy_40734('os_itens'::text, 'write'::text));


--
-- Name: permissions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;

--
-- Name: permissions permissions_select_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY permissions_select_all ON public.permissions FOR SELECT TO authenticated USING (true);


--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_select ON public.profiles FOR SELECT USING (((id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM (public.tenant_memberships tm_me
     JOIN public.tenant_memberships tm_target ON (((tm_target.user_id = profiles.id) AND (tm_target.tenant_id = tm_me.tenant_id))))
  WHERE ((tm_me.user_id = auth.uid()) AND (tm_me.status = 'active'::text) AND (tm_target.status = 'active'::text))))));


--
-- Name: profiles profiles_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_update ON public.profiles FOR UPDATE USING ((id = auth.uid())) WITH CHECK ((id = auth.uid()));


--
-- Name: role_access_rules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.role_access_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: role_access_rules role_access_rules_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY role_access_rules_admin ON public.role_access_rules TO authenticated USING (public.can__legacy_40734('admin'::text, 'manage_users'::text)) WITH CHECK (public.can__legacy_40734('admin'::text, 'manage_users'::text));


--
-- Name: roles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;

--
-- Name: roles roles_select_by_membership; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY roles_select_by_membership ON public.roles FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.status = 'active'::text) AND (tm.tenant_id = roles.tenant_id)))));


--
-- Name: fornecedores tenant_delete_fornecedores; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_delete_fornecedores ON public.fornecedores FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = fornecedores.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text)))));


--
-- Name: itens tenant_delete_itens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_delete_itens ON public.itens FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = itens.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text)))));


--
-- Name: nf_entrada_itens tenant_delete_nf_entrada_itens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_delete_nf_entrada_itens ON public.nf_entrada_itens FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = nf_entrada_itens.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text)))));


--
-- Name: fiscal_itens tenant_empresa_delete_fiscal_itens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_empresa_delete_fiscal_itens ON public.fiscal_itens FOR DELETE USING (((empresa_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = fiscal_itens.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text))))));


--
-- Name: movimentacoes tenant_empresa_delete_movimentacoes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_empresa_delete_movimentacoes ON public.movimentacoes FOR DELETE USING (((empresa_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = movimentacoes.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text))))));


--
-- Name: nf_entrada tenant_empresa_delete_nf_entrada; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_empresa_delete_nf_entrada ON public.nf_entrada FOR DELETE USING (((empresa_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = nf_entrada.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text))))));


--
-- Name: fiscal_itens tenant_empresa_insert_fiscal_itens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_empresa_insert_fiscal_itens ON public.fiscal_itens FOR INSERT WITH CHECK (((empresa_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = fiscal_itens.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'fiscal'::text])))))));


--
-- Name: movimentacoes tenant_empresa_insert_movimentacoes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_empresa_insert_movimentacoes ON public.movimentacoes FOR INSERT WITH CHECK (((empresa_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = movimentacoes.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'estoque'::text, 'fiscal'::text])))))));


--
-- Name: nf_entrada tenant_empresa_insert_nf_entrada; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_empresa_insert_nf_entrada ON public.nf_entrada FOR INSERT WITH CHECK (((empresa_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = nf_entrada.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'fiscal'::text])))))));


--
-- Name: fiscal_itens tenant_empresa_select_fiscal_itens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_empresa_select_fiscal_itens ON public.fiscal_itens FOR SELECT USING (((empresa_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = fiscal_itens.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'fiscal'::text])))))));


--
-- Name: movimentacoes tenant_empresa_select_movimentacoes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_empresa_select_movimentacoes ON public.movimentacoes FOR SELECT USING (((empresa_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = movimentacoes.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'estoque'::text, 'fiscal'::text])))))));


--
-- Name: nf_entrada tenant_empresa_select_nf_entrada; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_empresa_select_nf_entrada ON public.nf_entrada FOR SELECT USING (((empresa_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = nf_entrada.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'fiscal'::text])))))));


--
-- Name: fiscal_itens tenant_empresa_update_fiscal_itens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_empresa_update_fiscal_itens ON public.fiscal_itens FOR UPDATE USING (((empresa_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = fiscal_itens.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'fiscal'::text]))))))) WITH CHECK (((empresa_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = fiscal_itens.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'fiscal'::text])))))));


--
-- Name: movimentacoes tenant_empresa_update_movimentacoes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_empresa_update_movimentacoes ON public.movimentacoes FOR UPDATE USING (((empresa_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = movimentacoes.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text)))))) WITH CHECK (((empresa_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = movimentacoes.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text))))));


--
-- Name: nf_entrada tenant_empresa_update_nf_entrada; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_empresa_update_nf_entrada ON public.nf_entrada FOR UPDATE USING (((empresa_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = nf_entrada.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text)))))) WITH CHECK (((empresa_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = nf_entrada.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text))))));


--
-- Name: fornecedores tenant_insert_fornecedores; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_insert_fornecedores ON public.fornecedores FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = fornecedores.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'estoque'::text, 'fiscal'::text]))))));


--
-- Name: itens tenant_insert_itens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_insert_itens ON public.itens FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = itens.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'estoque'::text]))))));


--
-- Name: nf_entrada_itens tenant_insert_nf_entrada_itens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_insert_nf_entrada_itens ON public.nf_entrada_itens FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = nf_entrada_itens.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'fiscal'::text]))))));


--
-- Name: tenant_memberships; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tenant_memberships ENABLE ROW LEVEL SECURITY;

--
-- Name: tenant_memberships tenant_memberships_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_memberships_delete ON public.tenant_memberships FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = tenant_memberships.tenant_id) AND (tm.role = 'admin'::text) AND (tm.status = 'active'::text)))));


--
-- Name: tenant_memberships tenant_memberships_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_memberships_insert ON public.tenant_memberships FOR INSERT WITH CHECK (((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = tenant_memberships.tenant_id) AND (tm.status = 'active'::text)))) OR (auth.uid() = user_id)));


--
-- Name: tenant_memberships tenant_memberships_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_memberships_select ON public.tenant_memberships FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: tenant_memberships tenant_memberships_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_memberships_update ON public.tenant_memberships FOR UPDATE USING (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = tenant_memberships.tenant_id) AND (tm.role = 'admin'::text) AND (tm.status = 'active'::text))))));


--
-- Name: fornecedores tenant_select_fornecedores; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_select_fornecedores ON public.fornecedores FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = fornecedores.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'estoque'::text, 'fiscal'::text]))))));


--
-- Name: itens tenant_select_itens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_select_itens ON public.itens FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = itens.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'estoque'::text, 'fiscal'::text]))))));


--
-- Name: nf_entrada_itens tenant_select_nf_entrada_itens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_select_nf_entrada_itens ON public.nf_entrada_itens FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = nf_entrada_itens.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'fiscal'::text]))))));


--
-- Name: fornecedores tenant_update_fornecedores; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_update_fornecedores ON public.fornecedores FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = fornecedores.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'estoque'::text, 'fiscal'::text])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = fornecedores.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'estoque'::text, 'fiscal'::text]))))));


--
-- Name: itens tenant_update_itens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_update_itens ON public.itens FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = itens.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'estoque'::text, 'fiscal'::text])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = itens.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = ANY (ARRAY['admin'::text, 'estoque'::text, 'fiscal'::text]))))));


--
-- Name: nf_entrada_itens tenant_update_nf_entrada_itens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_update_nf_entrada_itens ON public.nf_entrada_itens FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = nf_entrada_itens.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = auth.uid()) AND (tm.tenant_id = nf_entrada_itens.tenant_id) AND (tm.status = 'active'::text) AND (tm.role = 'admin'::text)))));


--
-- Name: tenants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;

--
-- Name: tenants tenants_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenants_select_own ON public.tenants FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.tenant_id = tenants.id) AND (tm.user_id = auth.uid()) AND (tm.status = 'active'::text)))));


--
-- Name: tipos_horas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tipos_horas ENABLE ROW LEVEL SECURITY;

--
-- Name: tipos_horas tipos_horas_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tipos_horas_delete ON public.tipos_horas FOR DELETE TO authenticated USING (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('tipos_horas'::text, 'delete'::text)));


--
-- Name: tipos_horas tipos_horas_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tipos_horas_insert ON public.tipos_horas FOR INSERT TO authenticated WITH CHECK (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('tipos_horas'::text, 'create'::text)));


--
-- Name: tipos_horas tipos_horas_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tipos_horas_select ON public.tipos_horas FOR SELECT TO authenticated USING (((tenant_id = public.current_tenant_id()) AND (public.can__legacy_40734('tipos_horas'::text, 'read'::text) OR public.can__legacy_40734('apontamentos'::text, 'read'::text) OR public.can__legacy_40734('apontamentos'::text, 'create'::text) OR public.can__legacy_40734('apontamentos'::text, 'update'::text))));


--
-- Name: tipos_horas tipos_horas_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tipos_horas_update ON public.tipos_horas FOR UPDATE TO authenticated USING (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('tipos_horas'::text, 'update'::text))) WITH CHECK (((tenant_id = public.current_tenant_id()) AND public.can__legacy_40734('tipos_horas'::text, 'update'::text)));


--
-- Name: user_empresa_context; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_empresa_context ENABLE ROW LEVEL SECURITY;

--
-- Name: user_empresa_context user_empresa_context_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_empresa_context_delete ON public.user_empresa_context FOR DELETE USING (false);


--
-- Name: user_empresa_context user_empresa_context_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_empresa_context_insert ON public.user_empresa_context FOR INSERT WITH CHECK ((user_id = auth.uid()));


--
-- Name: user_empresa_context user_empresa_context_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_empresa_context_select ON public.user_empresa_context FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: user_empresa_context user_empresa_context_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_empresa_context_update ON public.user_empresa_context FOR UPDATE USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));


--
-- Name: user_profiles user_profiles_select_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_profiles_select_admin ON public.user_profiles FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = user_profiles.user_id) AND (tm.tenant_id = public.current_tenant_id())))) AND public.can__legacy_40734('admin'::text, 'manage_users'::text)));


--
-- Name: user_profiles user_profiles_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_profiles_select_own ON public.user_profiles FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: user_profiles user_profiles_update_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_profiles_update_admin ON public.user_profiles FOR UPDATE TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = user_profiles.user_id) AND (tm.tenant_id = public.current_tenant_id())))) AND public.can__legacy_40734('admin'::text, 'manage_users'::text))) WITH CHECK (((EXISTS ( SELECT 1
   FROM public.tenant_memberships tm
  WHERE ((tm.user_id = user_profiles.user_id) AND (tm.tenant_id = public.current_tenant_id())))) AND public.can__legacy_40734('admin'::text, 'manage_users'::text)));


--
-- Name: user_profiles user_profiles_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_profiles_update_own ON public.user_profiles FOR UPDATE TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));


--
-- Name: user_tenant_context; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_tenant_context ENABLE ROW LEVEL SECURITY;

--
-- Name: user_tenant_context utc_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY utc_select_own ON public.user_tenant_context FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: user_tenant_context utc_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY utc_update_own ON public.user_tenant_context FOR UPDATE USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));


--
-- Name: user_tenant_context utc_upsert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY utc_upsert_own ON public.user_tenant_context FOR INSERT WITH CHECK ((user_id = auth.uid()));


--
-- Name: messages; Type: ROW SECURITY; Schema: realtime; Owner: -
--

ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets_analytics; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.buckets_analytics ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets_vectors; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.buckets_vectors ENABLE ROW LEVEL SECURITY;

--
-- Name: migrations; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.migrations ENABLE ROW LEVEL SECURITY;

--
-- Name: objects; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

--
-- Name: prefixes; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.prefixes ENABLE ROW LEVEL SECURITY;

--
-- Name: s3_multipart_uploads; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.s3_multipart_uploads ENABLE ROW LEVEL SECURITY;

--
-- Name: s3_multipart_uploads_parts; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.s3_multipart_uploads_parts ENABLE ROW LEVEL SECURITY;

--
-- Name: vector_indexes; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.vector_indexes ENABLE ROW LEVEL SECURITY;

--
-- Name: supabase_realtime; Type: PUBLICATION; Schema: -; Owner: -
--

CREATE PUBLICATION supabase_realtime WITH (publish = 'insert, update, delete, truncate');


--
-- Name: issue_graphql_placeholder; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_graphql_placeholder ON sql_drop
         WHEN TAG IN ('DROP EXTENSION')
   EXECUTE FUNCTION extensions.set_graphql_placeholder();


--
-- Name: issue_pg_cron_access; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_pg_cron_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_cron_access();


--
-- Name: issue_pg_graphql_access; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_pg_graphql_access ON ddl_command_end
         WHEN TAG IN ('CREATE FUNCTION')
   EXECUTE FUNCTION extensions.grant_pg_graphql_access();


--
-- Name: issue_pg_net_access; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_pg_net_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_net_access();


--
-- Name: pgrst_ddl_watch; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER pgrst_ddl_watch ON ddl_command_end
   EXECUTE FUNCTION extensions.pgrst_ddl_watch();


--
-- Name: pgrst_drop_watch; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER pgrst_drop_watch ON sql_drop
   EXECUTE FUNCTION extensions.pgrst_drop_watch();


--
-- PostgreSQL database dump complete
--

\unrestrict 9RnNqkTEEiOO1VweYj7VcVQi9yhrk1FZH35hLvA8L9wvmiYhytIYGl3jZqgEply

