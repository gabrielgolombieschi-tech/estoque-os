begin;

do $$
begin
  if to_regclass('public.tenants') is null
    or to_regclass('public.empresas') is null
    or to_regclass('public.tenant_memberships') is null
    or to_regclass('public.empresa_memberships') is null
    or to_regclass('public.user_empresa_context') is null
    or to_regclass('auth.users') is null then
    raise notice 'Skipping 20260216_fix_empresa_eletrica_segau_default.sql in bootstrap mode (required tables absent).';
    return;
  end if;

  -- no-op in local bootstrap; behavior already handled in full environments.
end$$;

commit;
