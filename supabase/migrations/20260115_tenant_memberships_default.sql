begin;

create or replace function public.get_default_tenant_id()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'tenant_memberships_unique'
  ) then
    alter table public.tenant_memberships
      add constraint tenant_memberships_unique unique (tenant_id, user_id);
  end if;
end$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  default_tenant_id uuid;
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

  default_tenant_id := public.get_default_tenant_id();

  insert into public.tenant_memberships (tenant_id, user_id, status)
  values (default_tenant_id, new.id, 'active')
  on conflict (tenant_id, user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

with default_tenant as (
  select public.get_default_tenant_id() as tenant_id
)
insert into public.tenant_memberships (tenant_id, user_id, status)
select dt.tenant_id, u.id, 'active'
from auth.users u
cross join default_tenant dt
left join public.tenant_memberships tm
  on tm.tenant_id = dt.tenant_id
 and tm.user_id = u.id
where tm.user_id is null
on conflict (tenant_id, user_id) do nothing;

alter table public.tenant_memberships enable row level security;

drop policy if exists tenant_memberships_select on public.tenant_memberships;
drop policy if exists tenant_memberships_insert on public.tenant_memberships;
drop policy if exists tenant_memberships_update on public.tenant_memberships;
drop policy if exists tenant_memberships_delete on public.tenant_memberships;

create policy tenant_memberships_select on public.tenant_memberships
  for select
  using (user_id = auth.uid());

create policy tenant_memberships_insert on public.tenant_memberships
  for insert
  with check (false);

create policy tenant_memberships_update on public.tenant_memberships
  for update
  using (false)
  with check (false);

create policy tenant_memberships_delete on public.tenant_memberships
  for delete
  using (false);

commit;
