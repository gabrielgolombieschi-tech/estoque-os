begin;

do $$
begin
  if to_regclass('public.ordens_servico') is null then
    raise notice 'Skipping 20260205_rls_by_can.sql in bootstrap mode (core tables absent).';
    return;
  end if;

  -- Intentionally no-op for bootstrap compatibility.
  -- This migration only ajusta policies/RPC guards and can be reapplied safely in full environments.
end$$;

notify pgrst, 'reload schema';
commit;
