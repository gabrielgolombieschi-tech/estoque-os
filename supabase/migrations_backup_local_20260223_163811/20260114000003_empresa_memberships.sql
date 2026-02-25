begin;

create table if not exists public.empresa_memberships (
  id bigserial primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'user',
  status text not null default 'active',
  criado_em timestamptz not null default now()
);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'empresa_memberships_unique'
  ) then
    alter table public.empresa_memberships
      add constraint empresa_memberships_unique unique (tenant_id, empresa_id, user_id);
  end if;
end$$;

create index if not exists idx_empresa_memberships_tenant_user
  on public.empresa_memberships(tenant_id, user_id);

create index if not exists idx_empresa_memberships_empresa_user
  on public.empresa_memberships(empresa_id, user_id);

alter table public.empresa_memberships enable row level security;

drop policy if exists empresa_memberships_select on public.empresa_memberships;
drop policy if exists empresa_memberships_insert on public.empresa_memberships;
drop policy if exists empresa_memberships_update on public.empresa_memberships;
drop policy if exists empresa_memberships_delete on public.empresa_memberships;

create policy empresa_memberships_select on public.empresa_memberships
  for select
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = empresa_memberships.tenant_id
        and tm.status = 'active'
        and tm.role = 'admin'
    )
  );

create policy empresa_memberships_insert on public.empresa_memberships
  for insert
  with check (
    exists (
      select 1
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = empresa_memberships.tenant_id
        and tm.status = 'active'
        and tm.role = 'admin'
    )
  );

create policy empresa_memberships_update on public.empresa_memberships
  for update
  using (
    exists (
      select 1
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = empresa_memberships.tenant_id
        and tm.status = 'active'
        and tm.role = 'admin'
    )
  )
  with check (
    exists (
      select 1
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = empresa_memberships.tenant_id
        and tm.status = 'active'
        and tm.role = 'admin'
    )
  );

create policy empresa_memberships_delete on public.empresa_memberships
  for delete
  using (
    exists (
      select 1
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = empresa_memberships.tenant_id
        and tm.status = 'active'
        and tm.role = 'admin'
    )
  );

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  nome text,
  criado_em timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists profiles_select on public.profiles;
drop policy if exists profiles_update on public.profiles;

create policy profiles_select on public.profiles
  for select
  using (
    id = auth.uid()
    or exists (
      select 1
      from public.tenant_memberships tm_me
      join public.tenant_memberships tm_target
        on tm_target.user_id = profiles.id
       and tm_target.tenant_id = tm_me.tenant_id
      where tm_me.user_id = auth.uid()
        and tm_me.status = 'active'
        and tm_target.status = 'active'
    )
  );

create policy profiles_update on public.profiles
  for update
  using (id = auth.uid())
  with check (id = auth.uid());

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

commit;
