begin;

create or replace function f.titulo_eh_legado_implantacao(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_titulo_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path to 'pg_catalog', 'f'
as $$
  select exists (
    select 1
    from f.titulo_legado_implantacao li
    where li.tenant_id = p_tenant_id
      and li.empresa_id = p_empresa_id
      and li.titulo_id = p_titulo_id
      and li.desmarcado_em is null
  );
$$;

comment on function f.titulo_eh_legado_implantacao(uuid, uuid, uuid) is
  'Consulta a marcacao ativa de legado respeitando as politicas RLS do chamador. Em RPCs security definer, herda o escopo seguro da funcao chamadora.';

revoke all on function f.titulo_eh_legado_implantacao(uuid, uuid, uuid)
  from public;
revoke all on function f.titulo_eh_legado_implantacao(uuid, uuid, uuid)
  from anon;
grant execute on function f.titulo_eh_legado_implantacao(uuid, uuid, uuid)
  to authenticated;
grant execute on function f.titulo_eh_legado_implantacao(uuid, uuid, uuid)
  to service_role;

select pg_notify('pgrst', 'reload schema');

commit;
