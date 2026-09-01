-- Fix security WARN advisories that can be handled safely by SQL.
-- Remaining authenticated SECURITY DEFINER RPCs must be reviewed per function
-- because several are intentionally used by the application with internal guards.

-- 1) Pin search_path for app functions that currently inherit the caller role path.
do $$
declare
  v record;
  v_path text;
begin
  for v in
    select n.nspname as schema_name, p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as identity_args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'a', 'c', 'f', 'm', 'r')
      and not exists (
        select 1
        from unnest(coalesce(p.proconfig, array[]::text[])) cfg
        where cfg like 'search_path=%'
      )
  loop
    v_path := case v.schema_name
      when 'a' then 'pg_catalog, a, public, c, f, m, r, auth, extensions'
      when 'c' then 'pg_catalog, c, public, a, f, m, r, auth, extensions'
      when 'f' then 'pg_catalog, f, public, a, c, m, r, auth, extensions'
      when 'm' then 'pg_catalog, m, public, a, c, f, r, auth, extensions'
      when 'r' then 'pg_catalog, r, public, a, c, f, m, auth, extensions'
      else 'pg_catalog, public, a, c, f, m, r, auth, extensions'
    end;

    execute format(
      'alter function %I.%I(%s) set search_path to %s',
      v.schema_name,
      v.proname,
      v.identity_args,
      v_path
    );
  end loop;
end;
$$;

-- 2) SECURITY DEFINER functions should not be callable by anonymous users.
-- Preserve authenticated/service_role access for callable RPCs, but remove direct
-- API access to trigger functions because they are only executed by triggers.
do $$
declare
  v record;
begin
  for v in
    select
      n.nspname as schema_name,
      p.proname,
      pg_get_function_identity_arguments(p.oid) as identity_args,
      p.prorettype = 'pg_catalog.trigger'::regtype as returns_trigger
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'a', 'c', 'f', 'm', 'r')
      and p.prosecdef = true
  loop
    execute format('revoke execute on function %I.%I(%s) from public', v.schema_name, v.proname, v.identity_args);
    execute format('revoke execute on function %I.%I(%s) from anon', v.schema_name, v.proname, v.identity_args);

    if v.returns_trigger then
      execute format('revoke execute on function %I.%I(%s) from authenticated', v.schema_name, v.proname, v.identity_args);
      execute format('grant execute on function %I.%I(%s) to service_role', v.schema_name, v.proname, v.identity_args);
    else
      execute format('grant execute on function %I.%I(%s) to authenticated, service_role', v.schema_name, v.proname, v.identity_args);
    end if;
  end loop;
end;
$$;

-- 3) Remove unrestricted WITH CHECK from m.orcamento_item update policy.
do $$
begin
  if to_regclass('m.orcamento_item') is not null then
    drop policy if exists orcamento_item_update on m.orcamento_item;
    create policy orcamento_item_update
      on m.orcamento_item
      for update
      to authenticated
      using (
        tenant_id = public.current_tenant_id()
        and empresa_id = public.current_empresa_id()
        and c.has_comercial_access(tenant_id, empresa_id)
        and deleted_at is null
      )
      with check (
        tenant_id = public.current_tenant_id()
        and empresa_id = public.current_empresa_id()
        and c.has_comercial_access(tenant_id, empresa_id)
      );
  end if;
end;
$$;

notify pgrst, 'reload schema';
