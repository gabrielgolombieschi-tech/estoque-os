begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- Novos usuarios nao recebem tenant/empresa implicitamente. O acesso somente
-- nasce nas RPCs administrativas, depois da escolha explicita de papeis.
drop trigger if exists on_auth_user_created_assign_empresa on auth.users;
drop trigger if exists on_auth_user_login_set_context on auth.users;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  insert into public.profiles (id, email, nome)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'nome', new.raw_user_meta_data ->> 'name')
  )
  on conflict (id)
  do update set
    email = excluded.email,
    nome = excluded.nome;

  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.get_default_tenant_id() from public, anon, authenticated;

do $$
declare
  v_name text;
begin
  foreach v_name in array array['auto_assign_empresa_segau', 'auto_set_context_on_login']
  loop
    if to_regprocedure(format('public.%I()', v_name)) is not null then
      execute format(
        'revoke execute on function public.%I() from public, anon, authenticated',
        v_name
      );
    end if;
  end loop;
end;
$$;

-- Funcoes futuras nao devem nascer executaveis por PUBLIC por acidente.
alter default privileges for role postgres in schema public revoke execute on functions from public;
alter default privileges for role postgres in schema a revoke execute on functions from public;
alter default privileges for role postgres in schema c revoke execute on functions from public;
alter default privileges for role postgres in schema f revoke execute on functions from public;
alter default privileges for role postgres in schema m revoke execute on functions from public;

create or replace function public.has_active_tenant_access(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select p_tenant_id is not null
    and auth.uid() is not null
    and exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut on ut.usuario_id = u.id
      join public.tenants t on t.id = ut.tenant_id
      where u.auth_user_id = auth.uid()
        and u.ativo is true
        and u.deleted_at is null
        and ut.tenant_id = p_tenant_id
        and ut.ativo is true
        and ut.deleted_at is null
        and t.ativo is true
    );
$$;

create or replace function public.has_active_empresa_access(
  p_tenant_id uuid,
  p_empresa_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select p_tenant_id is not null
    and p_empresa_id is not null
    and auth.uid() is not null
    and exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut on ut.usuario_id = u.id
      join a.usuario_empresa ue on ue.usuario_id = u.id
      join c.empresa ce on ce.id = ue.empresa_id
      join public.empresas pe
        on pe.id = ce.id
       and pe.tenant_id = ce.tenant_id
      join public.tenants t on t.id = ce.tenant_id
      where u.auth_user_id = auth.uid()
        and u.ativo is true
        and u.deleted_at is null
        and ut.tenant_id = p_tenant_id
        and ut.ativo is true
        and ut.deleted_at is null
        and ue.empresa_id = p_empresa_id
        and ue.ativo is true
        and ue.deleted_at is null
        and ce.tenant_id = p_tenant_id
        and ce.ativo is true
        and ce.deleted_at is null
        and pe.ativo is true
        and t.ativo is true
    );
$$;

create or replace function public.has_any_active_empresa_access(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select exists (
    select 1
    from a.usuario u
    join a.usuario_tenant ut on ut.usuario_id = u.id
    join a.usuario_empresa ue on ue.usuario_id = u.id
    join c.empresa ce on ce.id = ue.empresa_id
    join public.empresas pe on pe.id = ce.id and pe.tenant_id = ce.tenant_id
    join public.tenants t on t.id = ce.tenant_id
    where u.auth_user_id = auth.uid()
      and u.ativo is true
      and u.deleted_at is null
      and ut.tenant_id = p_tenant_id
      and ut.ativo is true
      and ut.deleted_at is null
      and ue.ativo is true
      and ue.deleted_at is null
      and ce.tenant_id = p_tenant_id
      and ce.ativo is true
      and ce.deleted_at is null
      and pe.ativo is true
      and t.ativo is true
  );
$$;

-- Alias curto para codigo legado e novas policies.
create or replace function public.has_empresa_access(p_tenant_id uuid, p_empresa_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select public.has_active_empresa_access(p_tenant_id, p_empresa_id);
$$;

revoke all on function public.has_active_tenant_access(uuid) from public, anon;
revoke all on function public.has_active_empresa_access(uuid, uuid) from public, anon;
revoke all on function public.has_any_active_empresa_access(uuid) from public, anon;
revoke all on function public.has_empresa_access(uuid, uuid) from public, anon;
grant execute on function public.has_active_tenant_access(uuid) to authenticated, service_role;
grant execute on function public.has_active_empresa_access(uuid, uuid) to authenticated, service_role;
grant execute on function public.has_any_active_empresa_access(uuid) to authenticated, service_role;
grant execute on function public.has_empresa_access(uuid, uuid) to authenticated, service_role;

comment on function public.has_active_empresa_access(uuid, uuid) is
  'Fronteira canonica: exige usuario, tenant, empresa e vinculo a.usuario_empresa ativos.';

-- a.* e a fonte canonica. As memberships publicas sao apenas uma projecao
-- compatível com telas antigas e nunca sao usadas para autorizar dados.
create or replace function a.sync_usuario_access_projection(p_usuario_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_auth_user_id uuid;
begin
  select u.auth_user_id
    into v_auth_user_id
  from a.usuario u
  where u.id = p_usuario_id;

  if v_auth_user_id is null then
    return;
  end if;

  if exists (
    select 1
    from a.usuario u
    join a.usuario_tenant ut on ut.usuario_id = u.id
    join a.usuario_empresa ue on ue.usuario_id = u.id
    join c.empresa ce on ce.id = ue.empresa_id
    left join public.empresas pe
      on pe.id = ce.id
     and pe.tenant_id = ce.tenant_id
    where u.id = p_usuario_id
      and u.ativo is true
      and u.deleted_at is null
      and ut.tenant_id = ce.tenant_id
      and ut.ativo is true
      and ut.deleted_at is null
      and ue.ativo is true
      and ue.deleted_at is null
      and ce.ativo is true
      and ce.deleted_at is null
      and pe.id is null
  ) then
    raise exception 'empresa_projection_missing_or_inactive';
  end if;

  insert into public.tenant_memberships (tenant_id, user_id, status, role)
  select
    ut.tenant_id,
    v_auth_user_id,
    case
      when u.ativo is true
       and u.deleted_at is null
       and ut.ativo is true
       and ut.deleted_at is null
       and t.ativo is true
      then 'active'
      else 'inactive'
    end,
    a.fn_map_papel_tenant_to_role(ut.papel)
  from a.usuario u
  join (
    select distinct on (ut.usuario_id, ut.tenant_id) ut.*
    from a.usuario_tenant ut
    where ut.usuario_id = p_usuario_id
    order by
      ut.usuario_id,
      ut.tenant_id,
      (ut.deleted_at is null) desc,
      ut.updated_at desc,
      ut.created_at desc,
      ut.id desc
  ) ut on ut.usuario_id = u.id
  join public.tenants t on t.id = ut.tenant_id
  where u.id = p_usuario_id
  on conflict (tenant_id, user_id)
  do update set
    status = excluded.status,
    role = excluded.role;

  update public.tenant_memberships tm
     set status = 'inactive'
   where tm.user_id = v_auth_user_id
     and not exists (
       select 1
       from a.usuario u
       join a.usuario_tenant ut on ut.usuario_id = u.id
       join public.tenants t on t.id = ut.tenant_id
       where u.id = p_usuario_id
         and ut.tenant_id = tm.tenant_id
         and u.ativo is true
         and u.deleted_at is null
         and ut.ativo is true
         and ut.deleted_at is null
         and t.ativo is true
     );

  insert into public.empresa_memberships (
    tenant_id,
    empresa_id,
    user_id,
    role,
    status
  )
  select
    ce.tenant_id,
    ue.empresa_id,
    v_auth_user_id,
    a.fn_map_papel_empresa_to_role(ue.papel),
    case
      when u.ativo is true
       and u.deleted_at is null
       and ut.ativo is true
       and ut.deleted_at is null
       and ue.ativo is true
       and ue.deleted_at is null
       and ce.ativo is true
       and ce.deleted_at is null
       and pe.ativo is true
       and t.ativo is true
      then 'active'
      else 'inactive'
    end
  from a.usuario u
  join (
    select distinct on (ue.usuario_id, ue.empresa_id) ue.*
    from a.usuario_empresa ue
    where ue.usuario_id = p_usuario_id
    order by
      ue.usuario_id,
      ue.empresa_id,
      (ue.deleted_at is null) desc,
      ue.updated_at desc,
      ue.created_at desc,
      ue.id desc
  ) ue on ue.usuario_id = u.id
  join c.empresa ce on ce.id = ue.empresa_id
  join public.empresas pe on pe.id = ce.id and pe.tenant_id = ce.tenant_id
  join public.tenants t on t.id = ce.tenant_id
  left join (
    select distinct on (ut.usuario_id, ut.tenant_id) ut.*
    from a.usuario_tenant ut
    where ut.usuario_id = p_usuario_id
    order by
      ut.usuario_id,
      ut.tenant_id,
      (ut.deleted_at is null) desc,
      ut.updated_at desc,
      ut.created_at desc,
      ut.id desc
  ) ut
    on ut.usuario_id = u.id
   and ut.tenant_id = ce.tenant_id
  where u.id = p_usuario_id
  on conflict (tenant_id, empresa_id, user_id)
  do update set
    role = excluded.role,
    status = excluded.status;

  update public.empresa_memberships em
     set status = 'inactive'
   where em.user_id = v_auth_user_id
     and not exists (
       select 1
       from a.usuario u
       join a.usuario_tenant ut
         on ut.usuario_id = u.id
        and ut.tenant_id = em.tenant_id
       join a.usuario_empresa ue
         on ue.usuario_id = u.id
        and ue.empresa_id = em.empresa_id
       join c.empresa ce
         on ce.id = ue.empresa_id
        and ce.tenant_id = em.tenant_id
       join public.empresas pe
         on pe.id = ce.id
        and pe.tenant_id = ce.tenant_id
       join public.tenants t on t.id = ce.tenant_id
       where u.id = p_usuario_id
         and u.ativo is true
         and u.deleted_at is null
         and ut.ativo is true
         and ut.deleted_at is null
         and ue.ativo is true
         and ue.deleted_at is null
         and ce.ativo is true
         and ce.deleted_at is null
         and pe.ativo is true
         and t.ativo is true
     );

  delete from public.user_empresa_context uec
   where uec.user_id = v_auth_user_id
     and not exists (
       select 1
       from a.usuario u
       join a.usuario_tenant ut
         on ut.usuario_id = u.id
        and ut.tenant_id = uec.tenant_id
       join a.usuario_empresa ue
         on ue.usuario_id = u.id
        and ue.empresa_id = uec.empresa_id
       join c.empresa ce
         on ce.id = ue.empresa_id
        and ce.tenant_id = uec.tenant_id
       join public.empresas pe
         on pe.id = ce.id
        and pe.tenant_id = ce.tenant_id
       join public.tenants t on t.id = ce.tenant_id
       where u.id = p_usuario_id
         and u.ativo is true
         and u.deleted_at is null
         and ut.ativo is true
         and ut.deleted_at is null
         and ue.ativo is true
         and ue.deleted_at is null
         and ce.ativo is true
         and ce.deleted_at is null
         and pe.ativo is true
         and t.ativo is true
     );

  delete from public.user_tenant_context utc
   where utc.user_id = v_auth_user_id
     and not exists (
       select 1
       from a.usuario u
       join a.usuario_tenant ut
         on ut.usuario_id = u.id
        and ut.tenant_id = utc.tenant_id
       join public.tenants t on t.id = ut.tenant_id
       where u.id = p_usuario_id
         and u.ativo is true
         and u.deleted_at is null
         and ut.ativo is true
         and ut.deleted_at is null
         and t.ativo is true
     );
end;
$$;

create or replace function a.trg_sync_usuario_access_projection()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if tg_op = 'DELETE' then
    update public.tenant_memberships set status = 'inactive' where user_id = old.auth_user_id;
    update public.empresa_memberships set status = 'inactive' where user_id = old.auth_user_id;
    delete from public.user_empresa_context where user_id = old.auth_user_id;
    delete from public.user_tenant_context where user_id = old.auth_user_id;
    return old;
  end if;

  if tg_op = 'UPDATE' and old.auth_user_id is distinct from new.auth_user_id then
    update public.tenant_memberships set status = 'inactive' where user_id = old.auth_user_id;
    update public.empresa_memberships set status = 'inactive' where user_id = old.auth_user_id;
    delete from public.user_empresa_context where user_id = old.auth_user_id;
    delete from public.user_tenant_context where user_id = old.auth_user_id;
  end if;

  perform a.sync_usuario_access_projection(new.id);
  return new;
end;
$$;

create or replace function a.trg_sync_usuario_vinculo_projection()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform a.sync_usuario_access_projection(old.usuario_id);
  end if;

  if tg_op in ('INSERT', 'UPDATE')
     and (tg_op = 'INSERT' or new.usuario_id is distinct from old.usuario_id) then
    perform a.sync_usuario_access_projection(new.usuario_id);
  elsif tg_op = 'UPDATE' then
    perform a.sync_usuario_access_projection(new.usuario_id);
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists trg_sync_usuario_access_projection on a.usuario;
create trigger trg_sync_usuario_access_projection
after insert or update or delete on a.usuario
for each row execute function a.trg_sync_usuario_access_projection();

drop trigger if exists trg_sync_usuario_tenant_projection on a.usuario_tenant;
create trigger trg_sync_usuario_tenant_projection
after insert or update or delete on a.usuario_tenant
for each row execute function a.trg_sync_usuario_vinculo_projection();

drop trigger if exists trg_sync_usuario_empresa_projection on a.usuario_empresa;
create trigger trg_sync_usuario_empresa_projection
after insert or update or delete on a.usuario_empresa
for each row execute function a.trg_sync_usuario_vinculo_projection();

create or replace function a.trg_sync_empresa_catalog_projection()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  r record;
begin
  if tg_op = 'DELETE'
     or (tg_op = 'UPDATE' and old.id is distinct from new.id) then
    update public.empresa_memberships
       set status = 'inactive'
     where empresa_id = old.id;
    delete from public.user_empresa_context where empresa_id = old.id;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  for r in
    select distinct ue.usuario_id
    from a.usuario_empresa ue
    where ue.empresa_id = new.id
  loop
    perform a.sync_usuario_access_projection(r.usuario_id);
  end loop;

  return new;
end;
$$;

create or replace function a.trg_sync_tenant_catalog_projection()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  r record;
begin
  if tg_op = 'DELETE'
     or (tg_op = 'UPDATE' and old.id is distinct from new.id) then
    update public.tenant_memberships
       set status = 'inactive'
     where tenant_id = old.id;
    update public.empresa_memberships
       set status = 'inactive'
     where tenant_id = old.id;
    delete from public.user_empresa_context where tenant_id = old.id;
    delete from public.user_tenant_context where tenant_id = old.id;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  for r in
    select distinct ut.usuario_id
    from a.usuario_tenant ut
    where ut.tenant_id = new.id
  loop
    perform a.sync_usuario_access_projection(r.usuario_id);
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_sync_c_empresa_projection on c.empresa;
create trigger trg_sync_c_empresa_projection
after insert or update or delete on c.empresa
for each row execute function a.trg_sync_empresa_catalog_projection();

drop trigger if exists trg_sync_public_empresa_projection on public.empresas;
create trigger trg_sync_public_empresa_projection
after insert or update or delete on public.empresas
for each row execute function a.trg_sync_empresa_catalog_projection();

drop trigger if exists trg_sync_tenant_catalog_projection on public.tenants;
create trigger trg_sync_tenant_catalog_projection
after insert or update or delete on public.tenants
for each row execute function a.trg_sync_tenant_catalog_projection();

revoke all on function a.sync_usuario_access_projection(uuid) from public, anon, authenticated;
revoke all on function a.trg_sync_usuario_access_projection() from public, anon, authenticated;
revoke all on function a.trg_sync_usuario_vinculo_projection() from public, anon, authenticated;
revoke all on function a.trg_sync_empresa_catalog_projection() from public, anon, authenticated;
revoke all on function a.trg_sync_tenant_catalog_projection() from public, anon, authenticated;
grant execute on function a.sync_usuario_access_projection(uuid) to service_role;

-- Reconcilia o estado atual antes de tornar os contextos estritos.
do $$
declare
  r record;
begin
  for r in select id from a.usuario loop
    perform a.sync_usuario_access_projection(r.id);
  end loop;

  update public.tenant_memberships tm
     set status = 'inactive'
   where not exists (
     select 1
     from a.usuario u
     join a.usuario_tenant ut on ut.usuario_id = u.id
     join public.tenants t on t.id = ut.tenant_id
     where u.auth_user_id = tm.user_id
       and ut.tenant_id = tm.tenant_id
       and u.ativo is true
       and u.deleted_at is null
       and ut.ativo is true
       and ut.deleted_at is null
       and t.ativo is true
   );

  update public.empresa_memberships em
     set status = 'inactive'
   where not exists (
     select 1
     from a.usuario u
     join a.usuario_tenant ut
       on ut.usuario_id = u.id
      and ut.tenant_id = em.tenant_id
     join a.usuario_empresa ue
       on ue.usuario_id = u.id
      and ue.empresa_id = em.empresa_id
     join c.empresa ce
       on ce.id = ue.empresa_id
      and ce.tenant_id = em.tenant_id
     join public.empresas pe on pe.id = ce.id and pe.tenant_id = ce.tenant_id
     join public.tenants t on t.id = ce.tenant_id
     where u.auth_user_id = em.user_id
       and u.ativo is true
       and u.deleted_at is null
       and ut.ativo is true
       and ut.deleted_at is null
       and ue.ativo is true
       and ue.deleted_at is null
       and ce.ativo is true
       and ce.deleted_at is null
       and pe.ativo is true
       and t.ativo is true
   );
end;
$$;

-- Memberships/contextos publicos sao somente leitura para o cliente.
revoke insert, update, delete on table public.tenant_memberships from public, anon, authenticated;
revoke insert, update, delete on table public.empresa_memberships from public, anon, authenticated;
revoke insert, update, delete on table public.user_tenant_context from public, anon, authenticated;
revoke insert, update, delete on table public.user_empresa_context from public, anon, authenticated;
grant select on table public.tenant_memberships to authenticated;
grant select on table public.empresa_memberships to authenticated;
grant select on table public.user_tenant_context to authenticated;
grant select on table public.user_empresa_context to authenticated;


-- Clona as implementacoes antes de substituir os OIDs publicos por guards.
do $$
declare
  v_definition text;
begin
  if to_regprocedure('f.nfe_gravar_impostos_do_documento_unscoped_20260810(uuid)') is null then
    select pg_get_functiondef('f.nfe_gravar_impostos_do_documento(uuid)'::regprocedure) into v_definition;
    execute replace(v_definition, 'FUNCTION f.nfe_gravar_impostos_do_documento(', 'FUNCTION f.nfe_gravar_impostos_do_documento_unscoped_20260810(');
  end if;
  if to_regprocedure('m.fn_compra_varredura_unscoped_20260810(uuid,uuid,boolean,boolean)') is null then
    select pg_get_functiondef('m.fn_compra_varredura(uuid,uuid,boolean,boolean)'::regprocedure) into v_definition;
    execute replace(v_definition, 'FUNCTION m.fn_compra_varredura(', 'FUNCTION m.fn_compra_varredura_unscoped_20260810(');
  end if;
  if to_regprocedure('m.fn_pedido_compra_definir_destacar_ipi_unscoped_20260810(uuid,uuid,uuid,boolean)') is null then
    select pg_get_functiondef('m.fn_pedido_compra_definir_destacar_ipi(uuid,uuid,uuid,boolean)'::regprocedure) into v_definition;
    execute replace(v_definition, 'FUNCTION m.fn_pedido_compra_definir_destacar_ipi(', 'FUNCTION m.fn_pedido_compra_definir_destacar_ipi_unscoped_20260810(');
  end if;
  if to_regprocedure('m.fn_pedido_compra_transicionar_unscoped_20260810(uuid,text,text)') is null then
    select pg_get_functiondef('m.fn_pedido_compra_transicionar(uuid,text,text)'::regprocedure) into v_definition;
    execute replace(v_definition, 'FUNCTION m.fn_pedido_compra_transicionar(', 'FUNCTION m.fn_pedido_compra_transicionar_unscoped_20260810(');
  end if;
  if to_regprocedure('m.fn_pedido_compra_receber_unscoped_20260810(uuid,date,text,text,jsonb,boolean)') is null then
    select pg_get_functiondef('m.fn_pedido_compra_receber(uuid,date,text,text,jsonb,boolean)'::regprocedure) into v_definition;
    execute replace(v_definition, 'FUNCTION m.fn_pedido_compra_receber(', 'FUNCTION m.fn_pedido_compra_receber_unscoped_20260810(');
  end if;
  if to_regprocedure('public.list_itens_auditoria_unscoped_20260810(uuid,uuid,integer[])') is null then
    select pg_get_functiondef('public.list_itens_auditoria(uuid,uuid,integer[])'::regprocedure) into v_definition;
    execute replace(v_definition, 'FUNCTION public.list_itens_auditoria(', 'FUNCTION public.list_itens_auditoria_unscoped_20260810(');
  end if;
  if to_regprocedure('m.fn_orcamento_preco_sugerido_item_unscoped_20260810(uuid,uuid,numeric,numeric)') is null then
    select pg_get_functiondef('m.fn_orcamento_preco_sugerido_item(uuid,uuid,numeric,numeric)'::regprocedure) into v_definition;
    execute replace(v_definition, 'FUNCTION m.fn_orcamento_preco_sugerido_item(', 'FUNCTION m.fn_orcamento_preco_sugerido_item_unscoped_20260810(');
  end if;
  if to_regprocedure('public.estornar_movimentacao_unscoped_20260810(integer,text)') is null then
    select pg_get_functiondef('public.estornar_movimentacao(integer,text)'::regprocedure) into v_definition;
    execute replace(v_definition, 'FUNCTION public.estornar_movimentacao(', 'FUNCTION public.estornar_movimentacao_unscoped_20260810(');
  end if;
  if to_regprocedure('public.gerar_relatorio_hh_os_unscoped_20260810(integer,date,date)') is null then
    select pg_get_functiondef('public.gerar_relatorio_hh_os(integer,date,date)'::regprocedure) into v_definition;
    execute replace(v_definition, 'FUNCTION public.gerar_relatorio_hh_os(', 'FUNCTION public.gerar_relatorio_hh_os_unscoped_20260810(');
  end if;
  if to_regprocedure('public.ensure_orcamento_item_generico_unscoped_20260810(uuid,uuid,text)') is null then
    select pg_get_functiondef('public.ensure_orcamento_item_generico(uuid,uuid,text)'::regprocedure) into v_definition;
    execute replace(v_definition, 'FUNCTION public.ensure_orcamento_item_generico(', 'FUNCTION public.ensure_orcamento_item_generico_unscoped_20260810(');
  end if;
end;
$$;

create or replace function f.nfe_gravar_impostos_do_documento(p_documento_fiscal_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
begin
  select d.tenant_id, d.empresa_id
    into v_tenant_id, v_empresa_id
  from f.documento_fiscal d
  where d.id = p_documento_fiscal_id
    and d.deleted_at is null;

  if not found then
    raise exception 'documento_fiscal_not_found';
  end if;
  if v_empresa_id is distinct from public.current_empresa_id__by_tenant(v_tenant_id)
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id)
     or not (
       f.has_finance_access(v_tenant_id, v_empresa_id)
       or public.can('nf_entrada', 'import', v_tenant_id)
     ) then
    raise exception 'not_allowed';
  end if;

  perform f.nfe_gravar_impostos_do_documento_unscoped_20260810(p_documento_fiscal_id);
end;
$$;

create or replace function m.fn_compra_varredura(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_incluir_os boolean default true,
  p_incluir_estoque boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if not exists (
    select 1 from c.empresa e
    where e.id = p_empresa_id
      and e.tenant_id = p_tenant_id
      and e.ativo is true
      and e.deleted_at is null
  )
  or p_empresa_id is distinct from public.current_empresa_id__by_tenant(p_tenant_id)
  or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
  or not c.has_compras_access(p_tenant_id, p_empresa_id) then
    raise exception 'not_allowed';
  end if;

  return m.fn_compra_varredura_unscoped_20260810(
    p_tenant_id,
    p_empresa_id,
    p_incluir_os,
    p_incluir_estoque
  );
end;
$$;

create or replace function m.fn_pedido_compra_definir_destacar_ipi(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_pedido_id uuid,
  p_destacar boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
begin
  select p.tenant_id, p.empresa_id
    into v_tenant_id, v_empresa_id
  from m.pedido_compra p
  where p.id = p_pedido_id
    and p.deleted_at is null;
  if not found then
    raise exception 'pedido_compra_not_found';
  end if;

  if p_tenant_id is distinct from v_tenant_id
     or p_empresa_id is distinct from v_empresa_id
     or v_empresa_id is distinct from public.current_empresa_id__by_tenant(v_tenant_id)
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id)
     or not public.can('compras', 'write', v_tenant_id) then
    raise exception 'not_allowed';
  end if;

  return m.fn_pedido_compra_definir_destacar_ipi_unscoped_20260810(
    p_tenant_id, p_empresa_id, p_pedido_id, p_destacar
  );
end;
$$;

create or replace function m.fn_pedido_compra_transicionar(
  p_pedido_id uuid,
  p_status_para text,
  p_mensagem text default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_action text;
begin
  select p.tenant_id, p.empresa_id
    into v_tenant_id, v_empresa_id
  from m.pedido_compra p
  where p.id = p_pedido_id
    and p.deleted_at is null;
  if not found then
    raise exception 'pedido_compra_not_found';
  end if;

  v_action := case
    when upper(trim(coalesce(p_status_para, ''))) in ('APROVADO', 'REPROVADO') then 'approve'
    when upper(trim(coalesce(p_status_para, ''))) in ('PARCIAL_RECEBIDO', 'RECEBIDO') then 'receive'
    else 'write'
  end;

  if v_empresa_id is distinct from public.current_empresa_id__by_tenant(v_tenant_id)
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id)
     or not public.can('compras', v_action, v_tenant_id) then
    raise exception 'not_allowed';
  end if;

  perform m.fn_pedido_compra_transicionar_unscoped_20260810(
    p_pedido_id, p_status_para, p_mensagem
  );
end;
$$;

create or replace function m.fn_pedido_compra_receber(
  p_pedido_id uuid,
  p_recebimento_date date,
  p_documento_ref text,
  p_observacoes text,
  p_itens jsonb,
  p_skip_movimentacao boolean
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
begin
  select p.tenant_id, p.empresa_id
    into v_tenant_id, v_empresa_id
  from m.pedido_compra p
  where p.id = p_pedido_id
    and p.deleted_at is null;
  if not found then
    raise exception 'pedido_compra_not_found';
  end if;

  if v_empresa_id is distinct from public.current_empresa_id__by_tenant(v_tenant_id)
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id)
     or not (
       public.can('compras', 'receive', v_tenant_id)
       or (coalesce(p_skip_movimentacao, false) and public.can('estoque', 'write', v_tenant_id))
     ) then
    raise exception 'not_allowed';
  end if;

  return m.fn_pedido_compra_receber_unscoped_20260810(
    p_pedido_id,
    p_recebimento_date,
    p_documento_ref,
    p_observacoes,
    p_itens,
    p_skip_movimentacao
  );
end;
$$;

create or replace function public.list_itens_auditoria(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_item_ids integer[]
)
returns table (
  item_id integer,
  acao text,
  data_acao timestamp without time zone,
  autor_nome text,
  autor_identificador text
)
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if p_empresa_id is distinct from public.current_empresa_id__by_tenant(p_tenant_id)
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id) then
    return;
  end if;

  return query
  select *
  from public.list_itens_auditoria_unscoped_20260810(
    p_tenant_id, p_empresa_id, p_item_ids
  );
end;
$$;

create or replace function m.fn_orcamento_preco_sugerido_item(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_custo_ultima_compra numeric,
  p_preco_unitario numeric
)
returns numeric
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if p_empresa_id is distinct from public.current_empresa_id__by_tenant(p_tenant_id)
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or not c.has_comercial_access(p_tenant_id, p_empresa_id) then
    raise exception 'not_allowed';
  end if;

  return m.fn_orcamento_preco_sugerido_item_unscoped_20260810(
    p_tenant_id, p_empresa_id, p_custo_ultima_compra, p_preco_unitario
  );
end;
$$;

create or replace function public.estornar_movimentacao(
  p_mov_id integer,
  p_motivo text default null
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
begin
  select mov.tenant_id, mov.empresa_id
    into v_tenant_id, v_empresa_id
  from public.movimentacoes mov
  where mov.id = p_mov_id;

  if not found then
    raise exception 'movimentacao_not_found';
  end if;
  if v_empresa_id is distinct from public.current_empresa_id__by_tenant(v_tenant_id)
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'not_allowed';
  end if;

  return public.estornar_movimentacao_unscoped_20260810(p_mov_id, p_motivo);
end;
$$;

create or replace function public.gerar_relatorio_hh_os(
  p_os_id integer,
  p_periodo_inicio date,
  p_periodo_fim date
)
returns table (relatorio_id bigint, total numeric)
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
begin
  select os.tenant_id, os.empresa_id
    into v_tenant_id, v_empresa_id
  from public.ordens_servico os
  where os.id = p_os_id;

  if not found then
    raise exception 'ordem_servico_not_found';
  end if;
  if v_empresa_id is distinct from public.current_empresa_id__by_tenant(v_tenant_id)
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'not_allowed';
  end if;

  return query
  select r.relatorio_id, r.total
  from public.gerar_relatorio_hh_os_unscoped_20260810(
    p_os_id, p_periodo_inicio, p_periodo_fim
  ) r;
end;
$$;

create or replace function public.ensure_orcamento_item_generico(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_codigo text default '9999'
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if p_empresa_id is distinct from public.current_empresa_id__by_tenant(p_tenant_id)
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or not c.has_comercial_access(p_tenant_id, p_empresa_id) then
    raise exception 'not_allowed';
  end if;

  return public.ensure_orcamento_item_generico_unscoped_20260810(
    p_tenant_id, p_empresa_id, p_codigo
  );
end;
$$;

do $$
declare
  v_definition text;
begin
  if to_regprocedure('f.fn_pagamentos_aplicados_unscoped_20260810()') is null then
    select pg_get_functiondef('f.fn_pagamentos_aplicados()'::regprocedure) into v_definition;
    execute replace(
      v_definition,
      'FUNCTION f.fn_pagamentos_aplicados(',
      'FUNCTION f.fn_pagamentos_aplicados_unscoped_20260810('
    );
  end if;

  if to_regprocedure('f.ignorar_extrato_linha_unscoped_20260810(uuid,text)') is null then
    select pg_get_functiondef('f.ignorar_extrato_linha(uuid,text)'::regprocedure) into v_definition;
    execute replace(
      v_definition,
      'FUNCTION f.ignorar_extrato_linha(',
      'FUNCTION f.ignorar_extrato_linha_unscoped_20260810('
    );
  end if;
end;
$$;

create or replace function f.fn_pagamentos_aplicados()
returns table (
  tenant_id uuid,
  empresa_id uuid,
  conta_bancaria_id uuid,
  pagamento_id uuid,
  data_pagamento date,
  forma_pagamento text,
  valor_pagamento numeric,
  titulo_id uuid,
  titulo_parcela_id uuid,
  valor_aplicado numeric
)
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select p.*
  from f.fn_pagamentos_aplicados_unscoped_20260810() p
  where p.tenant_id = public.current_tenant_id()
    and p.empresa_id = public.current_empresa_id()
    and f.has_finance_access(p.tenant_id, p.empresa_id);
$$;

create or replace function f.ignorar_extrato_linha(
  p_extrato_linha_id uuid,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_tenant_id uuid;
  v_extrato_id uuid;
  v_conta_id uuid;
begin
  select l.tenant_id, l.extrato_bancario_id, l.conta_bancaria_id
    into v_tenant_id, v_extrato_id, v_conta_id
  from f.extrato_bancario_linha l
  where l.id = p_extrato_linha_id
    and l.deleted_at is null;
  if not found then
    raise exception 'extrato_linha_not_found';
  end if;

  if not f.has_extrato_linha_row_access(v_tenant_id, v_extrato_id, v_conta_id) then
    raise exception 'not_allowed';
  end if;

  perform f.ignorar_extrato_linha_unscoped_20260810(p_extrato_linha_id, p_motivo);
end;
$$;

revoke all on function f.nfe_gravar_impostos_do_documento_unscoped_20260810(uuid) from public, anon, authenticated;
revoke all on function m.fn_compra_varredura_unscoped_20260810(uuid, uuid, boolean, boolean) from public, anon, authenticated;
revoke all on function m.fn_pedido_compra_definir_destacar_ipi_unscoped_20260810(uuid, uuid, uuid, boolean) from public, anon, authenticated;
revoke all on function m.fn_pedido_compra_transicionar_unscoped_20260810(uuid, text, text) from public, anon, authenticated;
revoke all on function m.fn_pedido_compra_receber_unscoped_20260810(uuid, date, text, text, jsonb, boolean) from public, anon, authenticated;
revoke all on function public.list_itens_auditoria_unscoped_20260810(uuid, uuid, integer[]) from public, anon, authenticated;
revoke all on function m.fn_orcamento_preco_sugerido_item_unscoped_20260810(uuid, uuid, numeric, numeric) from public, anon, authenticated;
revoke all on function public.estornar_movimentacao_unscoped_20260810(integer, text) from public, anon, authenticated;
revoke all on function public.gerar_relatorio_hh_os_unscoped_20260810(integer, date, date) from public, anon, authenticated;
revoke all on function public.ensure_orcamento_item_generico_unscoped_20260810(uuid, uuid, text) from public, anon, authenticated;
revoke all on function f.fn_pagamentos_aplicados_unscoped_20260810() from public, anon, authenticated;
revoke all on function f.ignorar_extrato_linha_unscoped_20260810(uuid, text) from public, anon, authenticated;

revoke all on function f.nfe_gravar_impostos_do_documento(uuid) from public, anon;
revoke all on function m.fn_compra_varredura(uuid, uuid, boolean, boolean) from public, anon;
revoke all on function m.fn_pedido_compra_definir_destacar_ipi(uuid, uuid, uuid, boolean) from public, anon;
revoke all on function m.fn_pedido_compra_transicionar(uuid, text, text) from public, anon;
revoke all on function m.fn_pedido_compra_receber(uuid, date, text, text, jsonb, boolean) from public, anon;
revoke all on function m.fn_pedido_compra_receber(uuid, date, text, text, jsonb) from public, anon;
revoke all on function public.list_itens_auditoria(uuid, uuid, integer[]) from public, anon;
revoke all on function m.fn_orcamento_preco_sugerido_item(uuid, uuid, numeric, numeric) from public, anon;
revoke all on function public.estornar_movimentacao(integer, text) from public, anon;
revoke all on function public.gerar_relatorio_hh_os(integer, date, date) from public, anon;
revoke all on function public.ensure_orcamento_item_generico(uuid, uuid, text) from public, anon;
revoke all on function f.fn_pagamentos_aplicados() from public, anon;
revoke all on function f.ignorar_extrato_linha(uuid, text) from public, anon;

grant execute on function f.nfe_gravar_impostos_do_documento(uuid) to authenticated, service_role;
grant execute on function m.fn_compra_varredura(uuid, uuid, boolean, boolean) to authenticated, service_role;
grant execute on function m.fn_pedido_compra_definir_destacar_ipi(uuid, uuid, uuid, boolean) to authenticated, service_role;
grant execute on function m.fn_pedido_compra_transicionar(uuid, text, text) to authenticated, service_role;
grant execute on function m.fn_pedido_compra_receber(uuid, date, text, text, jsonb, boolean) to authenticated, service_role;
grant execute on function m.fn_pedido_compra_receber(uuid, date, text, text, jsonb) to authenticated, service_role;
grant execute on function public.list_itens_auditoria(uuid, uuid, integer[]) to authenticated, service_role;
grant execute on function m.fn_orcamento_preco_sugerido_item(uuid, uuid, numeric, numeric) to authenticated, service_role;
grant execute on function public.estornar_movimentacao(integer, text) to authenticated, service_role;
grant execute on function public.gerar_relatorio_hh_os(integer, date, date) to authenticated, service_role;
grant execute on function public.ensure_orcamento_item_generico(uuid, uuid, text) to authenticated, service_role;
grant execute on function f.fn_pagamentos_aplicados() to authenticated, service_role;
grant execute on function f.ignorar_extrato_linha(uuid, text) to authenticated, service_role;

-- Helpers mutadores sem chamada direta no app ficam internos. Chamadas entre
-- funcoes SECURITY DEFINER continuam funcionando como owner.
do $$
declare
  r record;
begin
  for r in
    select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where (n.nspname, p.proname) in (
      ('public', 'reclassificar_mov_saida_para_os'),
      ('public', 'os_sync_itens_from_nf_entrada'),
      ('f', 'fn_upsert_ar_from_documento_fiscal_v2'),
      ('f', 'fn_upsert_ar_from_nfe_venda'),
      ('f', 'nfe_gravar_impostos_da_nf_entrada'),
      ('f', 'seed_financeiro_defaults'),
      ('m', 'fn_pedido_compra_recalcular_totais'),
      ('public', 'admin_merge_fornecedores')
    )
  loop
    execute format(
      'revoke execute on function %I.%I(%s) from public, anon, authenticated',
      r.nspname,
      r.proname,
      r.args
    );
  end loop;
end;
$$;



create or replace function f.has_documento_fiscal_row_access(
  p_tenant_id uuid,
  p_documento_fiscal_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select exists (
    select 1
    from f.documento_fiscal d
    where d.id = p_documento_fiscal_id
      and d.tenant_id = p_tenant_id
      and d.empresa_id = public.current_empresa_id__by_tenant(p_tenant_id)
      and d.deleted_at is null
      and f.has_finance_access(d.tenant_id, d.empresa_id)
  );
$$;

create or replace function f.has_titulo_row_access(
  p_tenant_id uuid,
  p_titulo_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select exists (
    select 1
    from f.titulo t
    where t.id = p_titulo_id
      and t.tenant_id = p_tenant_id
      and t.empresa_id = public.current_empresa_id__by_tenant(p_tenant_id)
      and t.deleted_at is null
      and f.has_finance_access(t.tenant_id, t.empresa_id)
  );
$$;

create or replace function f.has_conciliacao_lancamento_row_access(
  p_tenant_id uuid,
  p_conciliacao_id uuid,
  p_pagamento_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select exists (
    select 1
    from f.conciliacao_bancaria cb
    where cb.id = p_conciliacao_id
      and cb.tenant_id = p_tenant_id
      and cb.empresa_id = public.current_empresa_id__by_tenant(p_tenant_id)
      and cb.deleted_at is null
      and f.has_finance_access(cb.tenant_id, cb.empresa_id)
      and (
        p_pagamento_id is null
        or exists (
          select 1 from f.pagamento p
          where p.id = p_pagamento_id
            and p.tenant_id = cb.tenant_id
            and p.empresa_id = cb.empresa_id
            and p.deleted_at is null
        )
      )
  );
$$;

create or replace function f.has_extrato_linha_row_access(
  p_tenant_id uuid,
  p_extrato_id uuid,
  p_conta_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select exists (
    select 1
    from f.extrato_bancario eb
    join f.conta_bancaria cb
      on cb.id = p_conta_id
     and cb.tenant_id = eb.tenant_id
     and cb.empresa_id = eb.empresa_id
    where eb.id = p_extrato_id
      and eb.tenant_id = p_tenant_id
      and eb.empresa_id = public.current_empresa_id__by_tenant(p_tenant_id)
      and eb.deleted_at is null
      and cb.deleted_at is null
      and f.has_finance_access(eb.tenant_id, eb.empresa_id)
  );
$$;

create or replace function f.has_imposto_retencao_row_access(
  p_tenant_id uuid,
  p_titulo_id uuid,
  p_documento_fiscal_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select exists (
    select 1
    from f.titulo t
    where t.id = p_titulo_id
      and t.tenant_id = p_tenant_id
      and t.empresa_id = public.current_empresa_id__by_tenant(p_tenant_id)
      and t.deleted_at is null
      and f.has_finance_access(t.tenant_id, t.empresa_id)
      and (
        p_documento_fiscal_id is null
        or exists (
          select 1 from f.documento_fiscal d
          where d.id = p_documento_fiscal_id
            and d.tenant_id = t.tenant_id
            and d.empresa_id = t.empresa_id
            and d.deleted_at is null
        )
      )
  );
$$;

create or replace function f.has_regra_rateio_item_row_access(
  p_tenant_id uuid,
  p_regra_rateio_id uuid,
  p_centro_custo_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select exists (
    select 1
    from f.regra_rateio r
    join f.centro_custo cc
      on cc.id = p_centro_custo_id
     and cc.tenant_id = r.tenant_id
     and cc.empresa_id = r.empresa_id
    where r.id = p_regra_rateio_id
      and r.tenant_id = p_tenant_id
      and r.empresa_id = public.current_empresa_id__by_tenant(p_tenant_id)
      and r.deleted_at is null
      and cc.deleted_at is null
      and f.has_finance_access(r.tenant_id, r.empresa_id)
  );
$$;

create or replace function f.has_titulo_agendamento_row_access(
  p_tenant_id uuid,
  p_titulo_id uuid,
  p_conta_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select exists (
    select 1
    from f.titulo t
    join f.conta_bancaria cb
      on cb.id = p_conta_id
     and cb.tenant_id = t.tenant_id
     and cb.empresa_id = t.empresa_id
    where t.id = p_titulo_id
      and t.tenant_id = p_tenant_id
      and t.empresa_id = public.current_empresa_id__by_tenant(p_tenant_id)
      and t.deleted_at is null
      and cb.deleted_at is null
      and f.has_finance_access(t.tenant_id, t.empresa_id)
  );
$$;

create or replace function f.has_titulo_aprovacao_row_access(
  p_tenant_id uuid,
  p_titulo_id uuid,
  p_os_id integer
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select exists (
    select 1
    from f.titulo t
    where t.id = p_titulo_id
      and t.tenant_id = p_tenant_id
      and t.empresa_id = public.current_empresa_id__by_tenant(p_tenant_id)
      and t.deleted_at is null
      and f.has_finance_access(t.tenant_id, t.empresa_id)
      and (
        p_os_id is null
        or exists (
          select 1 from public.ordens_servico os
          where os.id = p_os_id
            and os.tenant_id = t.tenant_id
            and os.empresa_id = t.empresa_id
        )
      )
  );
$$;

create or replace function f.has_pagamento_item_row_access(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_pagamento_id uuid,
  p_titulo_parcela_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select public.has_active_empresa_access(p_tenant_id, p_empresa_id)
    and p_empresa_id = public.current_empresa_id__by_tenant(p_tenant_id)
    and f.has_finance_access(p_tenant_id, p_empresa_id)
    and exists (
      select 1 from f.pagamento p
      where p.id = p_pagamento_id
        and p.tenant_id = p_tenant_id
        and p.empresa_id = p_empresa_id
        and p.deleted_at is null
    )
    and exists (
      select 1
      from f.titulo_parcela tp
      join f.titulo t on t.id = tp.titulo_id
      where tp.id = p_titulo_parcela_id
        and tp.tenant_id = p_tenant_id
        and tp.deleted_at is null
        and t.tenant_id = p_tenant_id
        and t.empresa_id = p_empresa_id
        and t.deleted_at is null
    );
$$;

revoke all on function f.has_documento_fiscal_row_access(uuid, uuid) from public, anon;
revoke all on function f.has_titulo_row_access(uuid, uuid) from public, anon;
revoke all on function f.has_conciliacao_lancamento_row_access(uuid, uuid, uuid) from public, anon;
revoke all on function f.has_extrato_linha_row_access(uuid, uuid, uuid) from public, anon;
revoke all on function f.has_imposto_retencao_row_access(uuid, uuid, uuid) from public, anon;
revoke all on function f.has_regra_rateio_item_row_access(uuid, uuid, uuid) from public, anon;
revoke all on function f.has_titulo_agendamento_row_access(uuid, uuid, uuid) from public, anon;
revoke all on function f.has_titulo_aprovacao_row_access(uuid, uuid, integer) from public, anon;
revoke all on function f.has_pagamento_item_row_access(uuid, uuid, uuid, uuid) from public, anon;
grant execute on function f.has_documento_fiscal_row_access(uuid, uuid) to authenticated, service_role;
grant execute on function f.has_titulo_row_access(uuid, uuid) to authenticated, service_role;
grant execute on function f.has_conciliacao_lancamento_row_access(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function f.has_extrato_linha_row_access(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function f.has_imposto_retencao_row_access(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function f.has_regra_rateio_item_row_access(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function f.has_titulo_agendamento_row_access(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function f.has_titulo_aprovacao_row_access(uuid, uuid, integer) to authenticated, service_role;
grant execute on function f.has_pagamento_item_row_access(uuid, uuid, uuid, uuid) to authenticated, service_role;

alter table f.conciliacao_lancamento enable row level security;
drop policy if exists enforce_parent_empresa_scope on f.conciliacao_lancamento;
create policy enforce_parent_empresa_scope
on f.conciliacao_lancamento as restrictive
for all to authenticated
using (f.has_conciliacao_lancamento_row_access(tenant_id, conciliacao_id, pagamento_id))
with check (f.has_conciliacao_lancamento_row_access(tenant_id, conciliacao_id, pagamento_id));

alter table f.documento_fiscal_item enable row level security;
drop policy if exists enforce_parent_empresa_scope on f.documento_fiscal_item;
create policy enforce_parent_empresa_scope
on f.documento_fiscal_item as restrictive
for all to authenticated
using (f.has_documento_fiscal_row_access(tenant_id, documento_fiscal_id))
with check (f.has_documento_fiscal_row_access(tenant_id, documento_fiscal_id));

alter table f.documento_fiscal_imposto enable row level security;
drop policy if exists enforce_parent_empresa_scope on f.documento_fiscal_imposto;
create policy enforce_parent_empresa_scope
on f.documento_fiscal_imposto as restrictive
for all to authenticated
using (f.has_documento_fiscal_row_access(tenant_id, documento_fiscal_id))
with check (f.has_documento_fiscal_row_access(tenant_id, documento_fiscal_id));

alter table f.documento_fiscal_xml enable row level security;
drop policy if exists enforce_parent_empresa_scope on f.documento_fiscal_xml;
create policy enforce_parent_empresa_scope
on f.documento_fiscal_xml as restrictive
for all to authenticated
using (f.has_documento_fiscal_row_access(tenant_id, documento_fiscal_id))
with check (f.has_documento_fiscal_row_access(tenant_id, documento_fiscal_id));

alter table f.extrato_bancario_linha enable row level security;
drop policy if exists enforce_parent_empresa_scope on f.extrato_bancario_linha;
create policy enforce_parent_empresa_scope
on f.extrato_bancario_linha as restrictive
for all to authenticated
using (f.has_extrato_linha_row_access(tenant_id, extrato_bancario_id, conta_bancaria_id))
with check (f.has_extrato_linha_row_access(tenant_id, extrato_bancario_id, conta_bancaria_id));

alter table f.imposto_retencao enable row level security;
drop policy if exists enforce_parent_empresa_scope on f.imposto_retencao;
create policy enforce_parent_empresa_scope
on f.imposto_retencao as restrictive
for all to authenticated
using (f.has_imposto_retencao_row_access(tenant_id, titulo_id, documento_fiscal_id))
with check (f.has_imposto_retencao_row_access(tenant_id, titulo_id, documento_fiscal_id));

alter table f.regra_rateio_item enable row level security;
drop policy if exists enforce_parent_empresa_scope on f.regra_rateio_item;
create policy enforce_parent_empresa_scope
on f.regra_rateio_item as restrictive
for all to authenticated
using (f.has_regra_rateio_item_row_access(tenant_id, regra_rateio_id, centro_custo_id))
with check (f.has_regra_rateio_item_row_access(tenant_id, regra_rateio_id, centro_custo_id));

alter table f.titulo_agendamento enable row level security;
drop policy if exists enforce_parent_empresa_scope on f.titulo_agendamento;
create policy enforce_parent_empresa_scope
on f.titulo_agendamento as restrictive
for all to authenticated
using (f.has_titulo_agendamento_row_access(tenant_id, titulo_id, conta_bancaria_id))
with check (f.has_titulo_agendamento_row_access(tenant_id, titulo_id, conta_bancaria_id));

alter table f.titulo_aprovacao enable row level security;
drop policy if exists enforce_parent_empresa_scope on f.titulo_aprovacao;
create policy enforce_parent_empresa_scope
on f.titulo_aprovacao as restrictive
for all to authenticated
using (f.has_titulo_aprovacao_row_access(tenant_id, titulo_id, os_id))
with check (f.has_titulo_aprovacao_row_access(tenant_id, titulo_id, os_id));

alter table f.titulo_parcela enable row level security;
drop policy if exists enforce_parent_empresa_scope on f.titulo_parcela;
create policy enforce_parent_empresa_scope
on f.titulo_parcela as restrictive
for all to authenticated
using (f.has_titulo_row_access(tenant_id, titulo_id))
with check (f.has_titulo_row_access(tenant_id, titulo_id));

alter table f.titulo_rateio enable row level security;
drop policy if exists enforce_parent_empresa_scope on f.titulo_rateio;
create policy enforce_parent_empresa_scope
on f.titulo_rateio as restrictive
for all to authenticated
using (f.has_titulo_row_access(tenant_id, titulo_id))
with check (f.has_titulo_row_access(tenant_id, titulo_id));

alter table f.pagamento_item enable row level security;
drop policy if exists enforce_parent_consistency_scope on f.pagamento_item;
create policy enforce_parent_consistency_scope
on f.pagamento_item as restrictive
for all to authenticated
using (f.has_pagamento_item_row_access(tenant_id, empresa_id, pagamento_id, titulo_parcela_id))
with check (f.has_pagamento_item_row_access(tenant_id, empresa_id, pagamento_id, titulo_parcela_id));

-- A tabela polimorfica esta vazia e nao e usada pelo app. Ate possuir
-- empresa_id/FKs verificaveis, nenhum cliente pode acessa-la diretamente.
revoke all on table f.anexo from public, anon, authenticated;

create or replace function public.current_tenant_id()
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_tenant_id uuid;
begin
  if auth.uid() is null then
    return null;
  end if;

  select utc.tenant_id
    into v_tenant_id
  from public.user_tenant_context utc
  where utc.user_id = auth.uid()
    and public.has_active_tenant_access(utc.tenant_id)
  limit 1;

  if v_tenant_id is not null then
    return v_tenant_id;
  end if;

  select ut.tenant_id
    into v_tenant_id
  from a.usuario u
  join a.usuario_tenant ut on ut.usuario_id = u.id
  join public.tenants t on t.id = ut.tenant_id
  where u.auth_user_id = auth.uid()
    and u.ativo is true
    and u.deleted_at is null
    and ut.ativo is true
    and ut.deleted_at is null
    and t.ativo is true
  order by ut.created_at asc, ut.tenant_id
  limit 1;

  return v_tenant_id;
end;
$$;

create or replace function public.current_empresa_id__by_tenant(
  p_tenant_id uuid default public.current_tenant_id()
)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_empresa_id uuid;
begin
  if not public.has_active_tenant_access(p_tenant_id) then
    return null;
  end if;

  select uec.empresa_id
    into v_empresa_id
  from public.user_empresa_context uec
  where uec.user_id = auth.uid()
    and uec.tenant_id = p_tenant_id
    and public.has_active_empresa_access(uec.tenant_id, uec.empresa_id)
  limit 1;

  if v_empresa_id is not null then
    return v_empresa_id;
  end if;

  select ue.empresa_id
    into v_empresa_id
  from a.usuario u
  join a.usuario_tenant ut on ut.usuario_id = u.id
  join a.usuario_empresa ue on ue.usuario_id = u.id
  join c.empresa ce on ce.id = ue.empresa_id
  join public.empresas pe on pe.id = ce.id and pe.tenant_id = ce.tenant_id
  where u.auth_user_id = auth.uid()
    and u.ativo is true
    and u.deleted_at is null
    and ut.tenant_id = p_tenant_id
    and ut.ativo is true
    and ut.deleted_at is null
    and ue.ativo is true
    and ue.deleted_at is null
    and ce.tenant_id = p_tenant_id
    and ce.ativo is true
    and ce.deleted_at is null
    and pe.ativo is true
  order by ue.created_at asc, ue.empresa_id
  limit 1;

  return v_empresa_id;
end;
$$;

create or replace function public.current_empresa_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select public.current_empresa_id__by_tenant(public.current_tenant_id());
$$;

create or replace function public.current_empresa_id(p_tenant_id uuid)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select public.current_empresa_id__by_tenant(p_tenant_id);
$$;

create or replace function public.set_current_tenant(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  if not public.has_active_tenant_access(p_tenant_id) then
    raise exception 'Sem acesso ativo a este tenant';
  end if;

  insert into public.user_tenant_context (user_id, tenant_id)
  values (auth.uid(), p_tenant_id)
  on conflict (user_id)
  do update set
    tenant_id = excluded.tenant_id,
    updated_at = now();

  perform set_config('app.current_tenant_id', p_tenant_id::text, true);
end;
$$;

create or replace function public.set_current_empresa(p_empresa_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_tenant_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  if p_empresa_id is null then
    raise exception 'Empresa nao informada';
  end if;

  v_tenant_id := public.current_tenant_id();
  if v_tenant_id is null then
    raise exception 'Tenant atual nao definido';
  end if;

  if not public.has_active_empresa_access(v_tenant_id, p_empresa_id) then
    raise exception 'Sem acesso ativo a esta empresa';
  end if;

  insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
  values (auth.uid(), v_tenant_id, p_empresa_id)
  on conflict (user_id, tenant_id)
  do update set
    empresa_id = excluded.empresa_id,
    updated_at = now();

  perform set_config('app.current_empresa_id', p_empresa_id::text, true);
end;
$$;

-- Preserva exatamente a matriz de papeis existente e adiciona a fronteira
-- canonica antes de qualquer atalho OWNER/ADMIN/GESTOR.
do $$
declare
  v_definition text;
begin
  if to_regprocedure('public.get_full_permissions_unscoped_20260810(uuid,uuid)') is null then
    select pg_get_functiondef('public.get_full_permissions(uuid,uuid)'::regprocedure)
      into v_definition;
    v_definition := replace(
      v_definition,
      'FUNCTION public.get_full_permissions(',
      'FUNCTION public.get_full_permissions_unscoped_20260810('
    );
    execute v_definition;
  end if;

  if to_regprocedure('public.can_unscoped_20260810(text,text,uuid)') is null then
    select pg_get_functiondef('public.can(text,text,uuid)'::regprocedure)
      into v_definition;
    v_definition := replace(
      v_definition,
      'FUNCTION public.can(',
      'FUNCTION public.can_unscoped_20260810('
    );
    execute v_definition;
  end if;

  if to_regprocedure('f.has_finance_access_unscoped_20260810(uuid,uuid)') is null then
    select pg_get_functiondef('f.has_finance_access(uuid,uuid)'::regprocedure)
      into v_definition;
    v_definition := replace(
      v_definition,
      'FUNCTION f.has_finance_access(',
      'FUNCTION f.has_finance_access_unscoped_20260810('
    );
    execute v_definition;
  end if;

  if to_regprocedure('c.has_imobilizado_access_unscoped_20260810(uuid,uuid)') is null then
    select pg_get_functiondef('c.has_imobilizado_access(uuid,uuid)'::regprocedure)
      into v_definition;
    v_definition := replace(
      v_definition,
      'FUNCTION c.has_imobilizado_access(',
      'FUNCTION c.has_imobilizado_access_unscoped_20260810('
    );
    execute v_definition;
  end if;

  if to_regprocedure('c.has_comercial_access_unscoped_20260810(uuid,uuid)') is null then
    select pg_get_functiondef('c.has_comercial_access(uuid,uuid)'::regprocedure)
      into v_definition;
    v_definition := replace(
      v_definition,
      'FUNCTION c.has_comercial_access(',
      'FUNCTION c.has_comercial_access_unscoped_20260810('
    );
    execute v_definition;
  end if;

  if to_regprocedure('c.has_compras_access_unscoped_20260810(uuid,uuid)') is null then
    select pg_get_functiondef('c.has_compras_access(uuid,uuid)'::regprocedure)
      into v_definition;
    v_definition := replace(
      v_definition,
      'FUNCTION c.has_compras_access(',
      'FUNCTION c.has_compras_access_unscoped_20260810('
    );
    execute v_definition;
  end if;
end;
$$;

create or replace function public.admin_is_owner(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select public.has_active_tenant_access(p_tenant_id)
    and exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut on ut.usuario_id = u.id
      where u.auth_user_id = auth.uid()
        and u.ativo is true
        and u.deleted_at is null
        and ut.tenant_id = p_tenant_id
        and ut.papel = 'OWNER'
        and ut.ativo is true
        and ut.deleted_at is null
    );
$$;

revoke all on function public.admin_is_owner(uuid) from public, anon;
grant execute on function public.admin_is_owner(uuid) to authenticated, service_role;

create or replace function public.admin_can_manage_users(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select public.has_active_tenant_access(p_tenant_id)
    and exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut on ut.usuario_id = u.id
      where u.auth_user_id = auth.uid()
        and u.ativo is true
        and u.deleted_at is null
        and ut.tenant_id = p_tenant_id
        and ut.ativo is true
        and ut.deleted_at is null
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

revoke all on function public.admin_can_manage_users(uuid) from public, anon;
grant execute on function public.admin_can_manage_users(uuid) to authenticated, service_role;

create or replace function public.get_full_permissions(p_tenant_id uuid, p_empresa_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select case
    when public.has_active_empresa_access(p_tenant_id, p_empresa_id)
      then public.get_full_permissions_unscoped_20260810(p_tenant_id, p_empresa_id)
    else '{}'::jsonb
  end;
$$;

create or replace function public.can(p_resource text, p_action text, p_tenant_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_empresa_id uuid;
begin
  if auth.uid() is null or p_tenant_id is null then
    return false;
  end if;

  if p_resource = 'admin' and p_action = 'manage_users' then
    return public.admin_can_manage_users(p_tenant_id);
  end if;

  if public.current_tenant_id() is distinct from p_tenant_id then
    return false;
  end if;

  v_empresa_id := public.current_empresa_id__by_tenant(p_tenant_id);
  if not public.has_active_empresa_access(p_tenant_id, v_empresa_id) then
    return false;
  end if;

  return public.can_unscoped_20260810(p_resource, p_action, p_tenant_id);
end;
$$;

create or replace function f.has_finance_access(
  p_tenant uuid default public.current_tenant_id(),
  p_empresa uuid default public.current_empresa_id()
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select public.has_active_empresa_access(p_tenant, p_empresa)
     and f.has_finance_access_unscoped_20260810(p_tenant, p_empresa);
$$;

create or replace function c.has_imobilizado_access(
  p_tenant uuid default public.current_tenant_id(),
  p_empresa uuid default public.current_empresa_id()
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select public.has_active_empresa_access(p_tenant, p_empresa)
     and c.has_imobilizado_access_unscoped_20260810(p_tenant, p_empresa);
$$;

create or replace function c.has_comercial_access(
  p_tenant uuid default public.current_tenant_id(),
  p_empresa uuid default public.current_empresa_id()
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select public.has_active_empresa_access(p_tenant, p_empresa)
     and c.has_comercial_access_unscoped_20260810(p_tenant, p_empresa);
$$;

create or replace function c.has_compras_access(
  p_tenant uuid default public.current_tenant_id(),
  p_empresa uuid default public.current_empresa_id()
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select public.has_active_empresa_access(p_tenant, p_empresa)
     and c.has_compras_access_unscoped_20260810(p_tenant, p_empresa);
$$;

create or replace function f.has_motivo_compra_access(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select exists (
    select 1
    from a.usuario u
    join a.usuario_empresa ue on ue.usuario_id = u.id
    join c.empresa ce on ce.id = ue.empresa_id
    where u.auth_user_id = auth.uid()
      and u.ativo is true
      and u.deleted_at is null
      and ue.empresa_id = public.current_empresa_id__by_tenant(p_tenant_id)
      and ue.ativo is true
      and ue.deleted_at is null
      and ce.tenant_id = p_tenant_id
      and public.has_active_empresa_access(p_tenant_id, ue.empresa_id)
      and upper(trim(coalesce(ue.papel, ''))) in (
        'ADMIN','FINANCEIRO','FATURAMENTO','COORDENACAO',
        'COMPRAS','ALMOXARIFADO','APONTAMENTO_RH'
      )
  );
$$;

revoke all on function public.get_full_permissions_unscoped_20260810(uuid, uuid) from public, anon, authenticated;
revoke all on function public.can_unscoped_20260810(text, text, uuid) from public, anon, authenticated;
revoke all on function f.has_finance_access_unscoped_20260810(uuid, uuid) from public, anon, authenticated;
revoke all on function c.has_imobilizado_access_unscoped_20260810(uuid, uuid) from public, anon, authenticated;
revoke all on function c.has_comercial_access_unscoped_20260810(uuid, uuid) from public, anon, authenticated;
revoke all on function c.has_compras_access_unscoped_20260810(uuid, uuid) from public, anon, authenticated;

create or replace function public.get_default_empresa_id(p_tenant_id uuid)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select e.id
  from public.empresas e
  where e.tenant_id = p_tenant_id
    and e.ativo is true
    and public.has_active_empresa_access(e.tenant_id, e.id)
  order by e.criado_em asc nulls last, e.id
  limit 1;
$$;

create or replace function public.list_user_empresas(p_tenant_id uuid)
returns table(id uuid, nome text, ativo boolean)
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select
    e.id,
    coalesce(e.nome_fantasia, e.razao_social, 'Empresa ' || e.id::text) as nome,
    e.ativo
  from public.empresas e
  where e.tenant_id = p_tenant_id
    and e.ativo is true
    and public.has_active_empresa_access(e.tenant_id, e.id)
  order by e.criado_em asc, e.id;
$$;

create or replace function public.faturamento_empresas_disponiveis()
returns table (
  empresa_id uuid,
  tenant_id uuid,
  nome_fantasia text,
  razao_social text,
  cnpj text
)
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select e.id, e.tenant_id, e.nome_fantasia, e.razao_social, e.cnpj
  from public.empresas e
  where e.tenant_id = public.current_tenant_id()
    and e.ativo is true
    and public.has_active_empresa_access(e.tenant_id, e.id)
    and f.has_finance_access(e.tenant_id, e.id)
  order by coalesce(nullif(trim(e.nome_fantasia), ''), nullif(trim(e.razao_social), ''), e.id::text);
$$;

create or replace function public.pick_fiscal_regra_admin(
  p_tenant uuid,
  p_empresa uuid,
  p_ncm text,
  p_cfop text,
  p_cst_icms text,
  p_cst_pis text,
  p_cst_cofins text,
  p_origem smallint,
  p_tipo_item text
)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
  select r.id
  from public.fiscal_regras r
  where public.has_active_empresa_access(p_tenant, p_empresa)
    and r.tenant_id = p_tenant
    and r.empresa_id = p_empresa
    and r.ativo is true
    and (r.ncm is null or r.ncm = p_ncm)
    and (r.cfop is null or r.cfop = p_cfop)
    and (r.cst_icms is null or r.cst_icms = p_cst_icms)
    and (r.cst_pis is null or r.cst_pis = p_cst_pis)
    and (r.cst_cofins is null or r.cst_cofins = p_cst_cofins)
    and (r.origem is null or r.origem = p_origem)
    and (r.tipo_item is null or r.tipo_item = p_tipo_item)
  order by coalesce(r.prioridade, 0) desc, r.atualizado_em desc
  limit 1;
$$;

revoke all on function public.list_user_empresas(text) from public, anon, authenticated;

create or replace function a.validate_empresa_vinculos_payload(
  p_tenant_id uuid,
  p_empresa_vinculos jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if p_tenant_id is null
     or p_empresa_vinculos is null
     or jsonb_typeof(p_empresa_vinculos) <> 'array' then
    raise exception 'invalid_empresa_vinculos_payload';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_empresa_vinculos) item
    where jsonb_typeof(item) <> 'object'
       or jsonb_typeof(item -> 'empresa_id') <> 'string'
       or jsonb_typeof(item -> 'papel') <> 'string'
       or jsonb_typeof(item -> 'ativo') <> 'boolean'
  ) then
    raise exception 'invalid_empresa_vinculo_item';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_empresa_vinculos) item
    group by (item ->> 'empresa_id')::uuid
    having count(*) > 1
  ) then
    raise exception 'duplicate_empresa_id';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_empresa_vinculos) item
    where upper(trim(item ->> 'papel')) not in (
      'ADMIN','FINANCEIRO','FATURAMENTO','COORDENACAO','COMPRAS',
      'ALMOXARIFADO','TECNICO','APONTAMENTO_RH','PAINEL_TV'
    )
  ) then
    raise exception 'invalid_empresa_role';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_empresa_vinculos) item
    left join c.empresa ce
      on ce.id = (item ->> 'empresa_id')::uuid
     and ce.tenant_id = p_tenant_id
    left join public.empresas pe
      on pe.id = (item ->> 'empresa_id')::uuid
     and pe.tenant_id = p_tenant_id
    where ce.id is null
       or pe.id is null
       or ((item ->> 'ativo')::boolean and (
         ce.ativo is not true
         or ce.deleted_at is not null
         or pe.ativo is not true
       ))
  ) then
    raise exception 'empresa_not_in_tenant_or_inactive';
  end if;
end;
$$;

revoke all on function a.validate_empresa_vinculos_payload(uuid, jsonb) from public, anon, authenticated;

create or replace function a.validate_admin_empresa_scope(
  p_tenant_id uuid,
  p_empresa_vinculos jsonb
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if public.admin_is_owner(p_tenant_id) then
    return;
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_empresa_vinculos) item
    where not public.has_active_empresa_access(
      p_tenant_id,
      (item ->> 'empresa_id')::uuid
    )
  ) then
    raise exception 'empresa_scope_not_allowed';
  end if;
end;
$$;

revoke all on function a.validate_admin_empresa_scope(uuid, jsonb) from public, anon, authenticated;

create or replace function public.admin_save_user_access(
  p_tenant_id uuid,
  p_usuario_id uuid,
  p_nome text,
  p_telefone text,
  p_usuario_ativo boolean,
  p_tenant_papel text,
  p_tenant_ativo boolean,
  p_empresa_vinculos jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_tenant_papel text;
  v_old_tenant_papel text;
  v_old_tenant_ativo boolean;
  v_item jsonb;
begin
  if not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;

  if p_usuario_ativo is null or p_tenant_ativo is null then
    raise exception 'active_flag_required';
  end if;

  if nullif(trim(coalesce(p_nome, '')), '') is null then
    raise exception 'user_name_required';
  end if;

  v_tenant_papel := upper(trim(coalesce(p_tenant_papel, '')));
  if v_tenant_papel not in ('OWNER','ADMIN','CONTADOR','GESTOR') then
    raise exception 'invalid_tenant_role: %', v_tenant_papel;
  end if;

  perform a.validate_empresa_vinculos_payload(p_tenant_id, p_empresa_vinculos);
  perform a.validate_admin_empresa_scope(p_tenant_id, p_empresa_vinculos);

  perform 1
  from public.tenants t
  where t.id = p_tenant_id
    and t.ativo is true
  for update;
  if not found then
    raise exception 'tenant_not_found_or_inactive';
  end if;

  perform 1
  from a.usuario u
  where u.id = p_usuario_id
    and u.deleted_at is null
  for update;
  if not found then
    raise exception 'user_not_found';
  end if;

  select ut.papel, ut.ativo
    into v_old_tenant_papel, v_old_tenant_ativo
  from a.usuario_tenant ut
  where ut.usuario_id = p_usuario_id
    and ut.tenant_id = p_tenant_id
    and ut.deleted_at is null
  for update;
  if not found then
    raise exception 'user_not_in_tenant';
  end if;

  if (v_tenant_papel = 'OWNER' or v_old_tenant_papel = 'OWNER')
     and not public.admin_is_owner(p_tenant_id) then
    raise exception 'owner_change_requires_owner';
  end if;

  if v_old_tenant_papel = 'OWNER'
     and v_old_tenant_ativo is true
     and (p_usuario_ativo is false or p_tenant_ativo is false or v_tenant_papel <> 'OWNER')
     and not exists (
       select 1
       from a.usuario_tenant other_ut
       join a.usuario other_u on other_u.id = other_ut.usuario_id
       where other_ut.tenant_id = p_tenant_id
         and other_ut.usuario_id <> p_usuario_id
         and other_ut.papel = 'OWNER'
         and other_ut.ativo is true
         and other_ut.deleted_at is null
         and other_u.ativo is true
         and other_u.deleted_at is null
     ) then
    raise exception 'last_active_owner';
  end if;

  update a.usuario
     set nome = trim(p_nome),
         telefone = nullif(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), ''),
         ativo = p_usuario_ativo,
         updated_at = now(),
         updated_by = auth.uid()
   where id = p_usuario_id;

  update a.usuario_tenant
     set papel = v_tenant_papel,
         ativo = p_tenant_ativo,
         updated_at = now(),
         updated_by = auth.uid(),
         deleted_at = null
   where usuario_id = p_usuario_id
     and tenant_id = p_tenant_id
     and deleted_at is null;

  for v_item in select value from jsonb_array_elements(p_empresa_vinculos)
  loop
    insert into a.usuario_empresa (
      id, usuario_id, empresa_id, papel, ativo,
      permissoes_extra, permissoes_negadas,
      created_at, updated_at, created_by, updated_by, deleted_at
    )
    values (
      gen_random_uuid(),
      p_usuario_id,
      (v_item ->> 'empresa_id')::uuid,
      upper(trim(v_item ->> 'papel')),
      (v_item ->> 'ativo')::boolean,
      null,
      null,
      now(),
      now(),
      auth.uid(),
      auth.uid(),
      null
    )
    on conflict (usuario_id, empresa_id) where deleted_at is null
    do update set
      papel = excluded.papel,
      ativo = excluded.ativo,
      updated_at = now(),
      updated_by = auth.uid(),
      deleted_at = null;
  end loop;

  perform a.sync_usuario_access_projection(p_usuario_id);
end;
$$;

grant execute on function public.admin_save_user_access(
  uuid, uuid, text, text, boolean, text, boolean, jsonb
) to authenticated, service_role;

create or replace function public.admin_update_user(
  p_tenant_id uuid,
  p_usuario_id uuid,
  p_nome text,
  p_telefone text,
  p_ativo boolean
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;
  if p_ativo is null then
    raise exception 'active_flag_required';
  end if;
  if not exists (
    select 1 from a.usuario_tenant ut
    where ut.usuario_id = p_usuario_id
      and ut.tenant_id = p_tenant_id
      and ut.deleted_at is null
  ) then
    raise exception 'user_not_in_tenant';
  end if;

  update a.usuario
     set nome = nullif(trim(p_nome), ''),
         telefone = nullif(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), ''),
         ativo = p_ativo,
         updated_at = now(),
         updated_by = auth.uid()
   where id = p_usuario_id
     and deleted_at is null;
  if not found then
    raise exception 'user_not_found';
  end if;

  perform a.sync_usuario_access_projection(p_usuario_id);
end;
$$;

create or replace function public.admin_set_user_tenant_role(
  p_tenant_id uuid,
  p_usuario_id uuid,
  p_papel text,
  p_ativo boolean
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_papel text := upper(trim(coalesce(p_papel, '')));
begin
  if not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;
  if p_ativo is null then
    raise exception 'active_flag_required';
  end if;
  if v_papel not in ('OWNER','ADMIN','CONTADOR','GESTOR') then
    raise exception 'invalid_tenant_role: %', v_papel;
  end if;
  if not exists (
    select 1 from a.usuario_tenant ut
    where ut.usuario_id = p_usuario_id
      and ut.tenant_id = p_tenant_id
      and ut.deleted_at is null
  ) then
    raise exception 'user_not_in_tenant';
  end if;

  update a.usuario_tenant
     set papel = v_papel,
         ativo = p_ativo,
         updated_at = now(),
         updated_by = auth.uid(),
         deleted_at = null
   where usuario_id = p_usuario_id
     and tenant_id = p_tenant_id
     and deleted_at is null;

  perform a.sync_usuario_access_projection(p_usuario_id);
end;
$$;

create or replace function public.admin_set_user_empresa(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_usuario_id uuid,
  p_papel text,
  p_ativo boolean
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_payload jsonb;
begin
  if not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;
  if p_ativo is null then
    raise exception 'active_flag_required';
  end if;
  if not exists (
    select 1 from a.usuario_tenant ut
    where ut.usuario_id = p_usuario_id
      and ut.tenant_id = p_tenant_id
      and ut.deleted_at is null
  ) then
    raise exception 'user_not_in_tenant';
  end if;

  v_payload := jsonb_build_array(jsonb_build_object(
    'empresa_id', p_empresa_id::text,
    'papel', p_papel,
    'ativo', p_ativo
  ));
  perform a.validate_empresa_vinculos_payload(p_tenant_id, v_payload);
  perform a.validate_admin_empresa_scope(p_tenant_id, v_payload);

  insert into a.usuario_empresa (
    id, usuario_id, empresa_id, papel, ativo,
    permissoes_extra, permissoes_negadas,
    created_at, updated_at, created_by, updated_by, deleted_at
  )
  values (
    gen_random_uuid(), p_usuario_id, p_empresa_id,
    upper(trim(p_papel)), p_ativo,
    null, null, now(), now(), auth.uid(), auth.uid(), null
  )
  on conflict (usuario_id, empresa_id) where deleted_at is null
  do update set
    papel = excluded.papel,
    ativo = excluded.ativo,
    updated_at = now(),
    updated_by = auth.uid(),
    deleted_at = null;

  perform a.sync_usuario_access_projection(p_usuario_id);
end;
$$;

create or replace function public.admin_finalize_invited_user(
  p_tenant_id uuid,
  p_auth_user_id uuid,
  p_email text,
  p_nome text,
  p_telefone text,
  p_tenant_papel text,
  p_empresa_vinculos jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_usuario_id uuid;
  v_existing_usuario_id uuid;
  v_old_tenant_papel text;
  v_old_tenant_ativo boolean;
  v_tenant_papel text := upper(trim(coalesce(p_tenant_papel, '')));
  v_auth_email text;
  v_item jsonb;
begin
  if not public.admin_can_manage_users(p_tenant_id) then
    raise exception 'not_allowed';
  end if;

  if p_auth_user_id is null
     or nullif(trim(coalesce(p_nome, '')), '') is null then
    raise exception 'invalid_user_payload';
  end if;

  if v_tenant_papel not in ('OWNER','ADMIN','CONTADOR','GESTOR') then
    raise exception 'invalid_tenant_role: %', v_tenant_papel;
  end if;

  perform 1
  from public.tenants t
  where t.id = p_tenant_id
    and t.ativo is true
  for update;
  if not found then
    raise exception 'tenant_not_found_or_inactive';
  end if;

  if v_tenant_papel = 'OWNER'
     and not public.admin_is_owner(p_tenant_id) then
    raise exception 'owner_change_requires_owner';
  end if;

  perform a.validate_empresa_vinculos_payload(p_tenant_id, p_empresa_vinculos);
  perform a.validate_admin_empresa_scope(p_tenant_id, p_empresa_vinculos);

  select lower(au.email)
    into v_auth_email
  from auth.users au
  where au.id = p_auth_user_id
  for update;
  if not found then
    raise exception 'auth_user_not_found';
  end if;

  if v_auth_email is null
     or lower(trim(coalesce(p_email, ''))) is distinct from v_auth_email then
    raise exception 'auth_user_email_mismatch';
  end if;

  select u.id
    into v_existing_usuario_id
  from a.usuario u
  where u.auth_user_id = p_auth_user_id
  for update;

  if v_existing_usuario_id is not null then
    select ut.papel, ut.ativo
      into v_old_tenant_papel, v_old_tenant_ativo
    from a.usuario_tenant ut
    where ut.usuario_id = v_existing_usuario_id
      and ut.tenant_id = p_tenant_id
      and ut.deleted_at is null
    for update;

    if v_old_tenant_papel = 'OWNER'
       and not public.admin_is_owner(p_tenant_id) then
      raise exception 'owner_change_requires_owner';
    end if;

    if v_old_tenant_papel = 'OWNER'
       and v_old_tenant_ativo is true
       and v_tenant_papel <> 'OWNER'
       and not exists (
         select 1
         from a.usuario_tenant other_ut
         join a.usuario other_u on other_u.id = other_ut.usuario_id
         where other_ut.tenant_id = p_tenant_id
           and other_ut.usuario_id <> v_existing_usuario_id
           and other_ut.papel = 'OWNER'
           and other_ut.ativo is true
           and other_ut.deleted_at is null
           and other_u.ativo is true
           and other_u.deleted_at is null
       ) then
      raise exception 'last_active_owner';
    end if;
  end if;

  insert into a.usuario (
    id, auth_user_id, nome, email, telefone, ativo,
    created_at, updated_at, created_by, updated_by, deleted_at
  )
  values (
    gen_random_uuid(),
    p_auth_user_id,
    trim(p_nome),
    v_auth_email,
    nullif(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), ''),
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

  for v_item in select value from jsonb_array_elements(p_empresa_vinculos)
  loop
    insert into a.usuario_empresa (
      id, usuario_id, empresa_id, papel, ativo,
      permissoes_extra, permissoes_negadas,
      created_at, updated_at, created_by, updated_by, deleted_at
    )
    values (
      gen_random_uuid(),
      v_usuario_id,
      (v_item ->> 'empresa_id')::uuid,
      upper(trim(v_item ->> 'papel')),
      (v_item ->> 'ativo')::boolean,
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

  perform a.sync_usuario_access_projection(v_usuario_id);
  return v_usuario_id;
end;
$$;

revoke all on function public.admin_update_user(uuid, uuid, text, text, boolean)
  from public, anon, authenticated;
revoke all on function public.admin_set_user_tenant_role(uuid, uuid, text, boolean)
  from public, anon, authenticated;
revoke all on function public.admin_set_user_empresa(uuid, uuid, uuid, text, boolean)
  from public, anon, authenticated;
grant execute on function public.admin_update_user(uuid, uuid, text, text, boolean)
  to service_role;
grant execute on function public.admin_set_user_tenant_role(uuid, uuid, text, boolean)
  to service_role;
grant execute on function public.admin_set_user_empresa(uuid, uuid, uuid, text, boolean)
  to service_role;

revoke all on function public.admin_finalize_invited_user(
  uuid, uuid, text, text, text, text, jsonb
) from public, anon;
grant execute on function public.admin_finalize_invited_user(
  uuid, uuid, text, text, text, text, jsonb
) to authenticated, service_role;

-- P0: contatos de clientes estavam sem RLS e com ALL para anon.
revoke all on table public.cliente_contatos from public, anon;
revoke all on sequence public.cliente_contatos_id_seq from public, anon;
grant select, insert, update, delete on table public.cliente_contatos to authenticated;
grant usage, select on sequence public.cliente_contatos_id_seq to authenticated;
alter table public.cliente_contatos enable row level security;

drop policy if exists cliente_contatos_select on public.cliente_contatos;
drop policy if exists cliente_contatos_insert on public.cliente_contatos;
drop policy if exists cliente_contatos_update on public.cliente_contatos;
drop policy if exists cliente_contatos_delete on public.cliente_contatos;

create policy cliente_contatos_select
on public.cliente_contatos
for select to authenticated
using (
  c.has_comercial_access(tenant_id, empresa_id)
  and exists (
    select 1
    from public.clientes cli
    where cli.id = cliente_contatos.cliente_id
      and cli.tenant_id = cliente_contatos.tenant_id
      and cli.empresa_id = cliente_contatos.empresa_id
  )
);

create policy cliente_contatos_insert
on public.cliente_contatos
for insert to authenticated
with check (
  c.has_comercial_access(tenant_id, empresa_id)
  and exists (
    select 1
    from public.clientes cli
    where cli.id = cliente_contatos.cliente_id
      and cli.tenant_id = cliente_contatos.tenant_id
      and cli.empresa_id = cliente_contatos.empresa_id
  )
);

create policy cliente_contatos_update
on public.cliente_contatos
for update to authenticated
using (
  c.has_comercial_access(tenant_id, empresa_id)
  and exists (
    select 1
    from public.clientes cli
    where cli.id = cliente_contatos.cliente_id
      and cli.tenant_id = cliente_contatos.tenant_id
      and cli.empresa_id = cliente_contatos.empresa_id
  )
)
with check (
  c.has_comercial_access(tenant_id, empresa_id)
  and exists (
    select 1
    from public.clientes cli
    where cli.id = cliente_contatos.cliente_id
      and cli.tenant_id = cliente_contatos.tenant_id
      and cli.empresa_id = cliente_contatos.empresa_id
  )
);

create policy cliente_contatos_delete
on public.cliente_contatos
for delete to authenticated
using (
  c.has_comercial_access(tenant_id, empresa_id)
  and exists (
    select 1
    from public.clientes cli
    where cli.id = cliente_contatos.cliente_id
      and cli.tenant_id = cliente_contatos.tenant_id
      and cli.empresa_id = cliente_contatos.empresa_id
  )
);

-- Remove somente catch-alls comprovadamente acidentais. As policies de acao
-- continuam existindo e recebem abaixo um AND restritivo por empresa.
drop policy if exists hh_lancamentos_tenant_isolation on public.hh_lancamentos;
drop policy if exists cliente_hh_servicos_tenant_empresa_policy on public.cliente_hh_servicos;

drop policy if exists enforce_apontamentos_read_role on public.apontamentos_horas;
create policy enforce_apontamentos_read_role
on public.apontamentos_horas as restrictive
for select to authenticated
using (public.can('apontamentos', 'read', tenant_id));

drop policy if exists enforce_apontamentos_insert_role on public.apontamentos_horas;
create policy enforce_apontamentos_insert_role
on public.apontamentos_horas as restrictive
for insert to authenticated
with check (public.can('apontamentos', 'write', tenant_id));

drop policy if exists enforce_apontamentos_update_role on public.apontamentos_horas;
create policy enforce_apontamentos_update_role
on public.apontamentos_horas as restrictive
for update to authenticated
using (public.can('apontamentos', 'write', tenant_id))
with check (public.can('apontamentos', 'write', tenant_id));

drop policy if exists enforce_apontamentos_delete_role on public.apontamentos_horas;
create policy enforce_apontamentos_delete_role
on public.apontamentos_horas as restrictive
for delete to authenticated
using (public.can('apontamentos', 'delete', tenant_id));

-- Cinturao global: policies permissivas antigas passam a ser obrigatoriamente
-- combinadas com tenant atual, empresa atual e vinculo canonico ativo.
do $$
declare
  r record;
  v_using text;
begin
  for r in
    select
      n.nspname as schema_name,
      cls.relname as table_name,
      empresa_col.attnotnull as empresa_not_null
    from pg_class cls
    join pg_namespace n on n.oid = cls.relnamespace
    join pg_attribute tenant_col
      on tenant_col.attrelid = cls.oid
     and tenant_col.attname = 'tenant_id'
     and tenant_col.attnum > 0
     and not tenant_col.attisdropped
    join pg_attribute empresa_col
      on empresa_col.attrelid = cls.oid
     and empresa_col.attname = 'empresa_id'
     and empresa_col.attnum > 0
     and not empresa_col.attisdropped
    where cls.relkind in ('r', 'p')
      and cls.relrowsecurity is true
      and n.nspname in ('public', 'c', 'f', 'm')
      and not (n.nspname = 'public' and cls.relname in (
        'empresa_memberships', 'user_empresa_context'
      ))
  loop
    if r.schema_name = 'f'
       and r.table_name = 'credito_fiscal_manual_regra'
       and not r.empresa_not_null then
      v_using := format(
        'tenant_id = public.current_tenant_id() and ((empresa_id is null and public.has_any_active_empresa_access(tenant_id)) or (empresa_id = public.current_empresa_id() and public.has_active_empresa_access(tenant_id, empresa_id)))'
      );
    else
      v_using := format(
        'tenant_id = public.current_tenant_id() and empresa_id = public.current_empresa_id() and public.has_active_empresa_access(tenant_id, empresa_id)'
      );
    end if;

    execute format(
      'drop policy if exists enforce_active_empresa_scope on %I.%I',
      r.schema_name,
      r.table_name
    );
    execute format(
      'create policy enforce_active_empresa_scope on %I.%I as restrictive for all to authenticated using (%s) with check (%s)',
      r.schema_name,
      r.table_name,
      v_using,
      v_using
    );
  end loop;
end;
$$;

do $$
begin
  if exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'auth.users'::regclass
      and not t.tgisinternal
      and t.tgname in (
        'on_auth_user_created_assign_empresa',
        'on_auth_user_login_set_context'
      )
  ) then
    raise exception 'unsafe_auth_trigger_still_present';
  end if;

  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.cliente_contatos'::regclass)
     or has_table_privilege('anon', 'public.cliente_contatos', 'select') then
    raise exception 'cliente_contatos_not_closed';
  end if;

  if exists (
    select 1
    from public.tenant_memberships tm
    where tm.status = 'active'
      and not exists (
        select 1
        from a.usuario u
        join a.usuario_tenant ut on ut.usuario_id = u.id
        join public.tenants t on t.id = ut.tenant_id
        where u.auth_user_id = tm.user_id
          and ut.tenant_id = tm.tenant_id
          and u.ativo is true
          and u.deleted_at is null
          and ut.ativo is true
          and ut.deleted_at is null
          and t.ativo is true
      )
  ) then
    raise exception 'active_public_tenant_membership_without_canonical_link';
  end if;

  if exists (
    select 1
    from public.empresa_memberships em
    where em.status = 'active'
      and not exists (
        select 1
        from a.usuario u
        join a.usuario_tenant ut
          on ut.usuario_id = u.id
         and ut.tenant_id = em.tenant_id
        join a.usuario_empresa ue
          on ue.usuario_id = u.id
         and ue.empresa_id = em.empresa_id
        join c.empresa ce
          on ce.id = ue.empresa_id
         and ce.tenant_id = em.tenant_id
        join public.empresas pe on pe.id = ce.id and pe.tenant_id = ce.tenant_id
        join public.tenants t on t.id = ce.tenant_id
        where u.auth_user_id = em.user_id
          and u.ativo is true
          and u.deleted_at is null
          and ut.ativo is true
          and ut.deleted_at is null
          and ue.ativo is true
          and ue.deleted_at is null
          and ce.ativo is true
          and ce.deleted_at is null
          and pe.ativo is true
          and t.ativo is true
      )
  ) then
    raise exception 'active_public_empresa_membership_without_canonical_link';
  end if;

  if exists (
    select 1
    from public.user_empresa_context uec
    where not exists (
      select 1
      from a.usuario u
      join a.usuario_tenant ut
        on ut.usuario_id = u.id
       and ut.tenant_id = uec.tenant_id
      join a.usuario_empresa ue
        on ue.usuario_id = u.id
       and ue.empresa_id = uec.empresa_id
      join c.empresa ce
        on ce.id = ue.empresa_id
       and ce.tenant_id = uec.tenant_id
      join public.empresas pe on pe.id = ce.id and pe.tenant_id = ce.tenant_id
      where u.auth_user_id = uec.user_id
        and u.ativo is true
        and u.deleted_at is null
        and ut.ativo is true
        and ut.deleted_at is null
        and ue.ativo is true
        and ue.deleted_at is null
        and ce.ativo is true
        and ce.deleted_at is null
        and pe.ativo is true
    )
  ) then
    raise exception 'stale_empresa_context';
  end if;

  if exists (
    select 1
    from pg_class cls
    join pg_namespace n on n.oid = cls.relnamespace
    join pg_attribute tenant_col
      on tenant_col.attrelid = cls.oid
     and tenant_col.attname = 'tenant_id'
     and tenant_col.attnum > 0
     and not tenant_col.attisdropped
    join pg_attribute empresa_col
      on empresa_col.attrelid = cls.oid
     and empresa_col.attname = 'empresa_id'
     and empresa_col.attnum > 0
     and not empresa_col.attisdropped
    where cls.relkind in ('r', 'p')
      and cls.relrowsecurity is true
      and n.nspname in ('public', 'c', 'f', 'm')
      and not (n.nspname = 'public' and cls.relname in (
        'empresa_memberships', 'user_empresa_context'
      ))
      and not exists (
        select 1
        from pg_policy pol
        where pol.polrelid = cls.oid
          and pol.polname = 'enforce_active_empresa_scope'
          and pol.polpermissive is false
      )
  ) then
    raise exception 'missing_restrictive_empresa_policy';
  end if;

  if has_function_privilege(
       'authenticated',
       'public.admin_merge_fornecedores(uuid,bigint,bigint,boolean)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.admin_update_user(uuid,uuid,text,text,boolean)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.admin_set_user_tenant_role(uuid,uuid,text,boolean)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.admin_set_user_empresa(uuid,uuid,uuid,text,boolean)',
       'execute'
     ) then
    raise exception 'unsafe_admin_rpc_still_executable';
  end if;

  if has_function_privilege(
       'authenticated',
       'public.ensure_orcamento_item_generico_unscoped_20260810(uuid,uuid,text)',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.ensure_orcamento_item_generico(uuid,uuid,text)',
       'execute'
     ) then
    raise exception 'unsafe_orcamento_item_rpc_acl';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'c.empresa'::regclass
      and tgname = 'trg_sync_c_empresa_projection'
      and not tgisinternal
  )
  or not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.empresas'::regclass
      and tgname = 'trg_sync_public_empresa_projection'
      and not tgisinternal
  )
  or not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.tenants'::regclass
      and tgname = 'trg_sync_tenant_catalog_projection'
      and not tgisinternal
  ) then
    raise exception 'catalog_projection_trigger_missing';
  end if;
end;
$$;


notify pgrst, 'reload schema';

commit;
