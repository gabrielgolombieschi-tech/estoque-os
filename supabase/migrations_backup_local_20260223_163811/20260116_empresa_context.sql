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
    or (
      tenant_id = public.current_tenant_id()
      and public.has_permission('admin.users.manage')
    )
  );

create policy empresa_memberships_insert on public.empresa_memberships
  for insert
  with check (
    tenant_id = public.current_tenant_id()
    and public.has_permission('admin.users.manage')
  );

create policy empresa_memberships_update on public.empresa_memberships
  for update
  using (
    tenant_id = public.current_tenant_id()
    and public.has_permission('admin.users.manage')
  )
  with check (
    tenant_id = public.current_tenant_id()
    and public.has_permission('admin.users.manage')
  );

create policy empresa_memberships_delete on public.empresa_memberships
  for delete
  using (
    tenant_id = public.current_tenant_id()
    and public.has_permission('admin.users.manage')
  );

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  nome text,
  criado_em timestamptz not null default now()
);

alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists nome text;
alter table public.profiles add column if not exists criado_em timestamptz not null default now();

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

create table if not exists public.user_empresa_context (
  user_id uuid not null references auth.users(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  updated_at timestamptz not null default now(),
  primary key (user_id, tenant_id)
);

create index if not exists idx_user_empresa_context_user
  on public.user_empresa_context(user_id);

create index if not exists idx_user_empresa_context_tenant
  on public.user_empresa_context(tenant_id);

alter table public.user_empresa_context enable row level security;

drop policy if exists user_empresa_context_select on public.user_empresa_context;
drop policy if exists user_empresa_context_insert on public.user_empresa_context;
drop policy if exists user_empresa_context_update on public.user_empresa_context;
drop policy if exists user_empresa_context_delete on public.user_empresa_context;

create policy user_empresa_context_select on public.user_empresa_context
  for select
  using (user_id = auth.uid());

create policy user_empresa_context_insert on public.user_empresa_context
  for insert
  with check (user_id = auth.uid());

create policy user_empresa_context_update on public.user_empresa_context
  for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy user_empresa_context_delete on public.user_empresa_context
  for delete
  using (false);

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

create or replace function public.get_default_empresa_id(p_tenant_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select e.id
  from public.empresas e
  where e.tenant_id = p_tenant_id
    and e.ativo = true
  order by e.criado_em asc nulls last
  limit 1;
$$;

create or replace function public.current_empresa_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
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
    nullif(current_setting('app.current_empresa_id', true), '')::uuid
  );
$$;

create or replace function public.set_current_empresa(p_empresa_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
  default_empresa_id uuid;
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

  default_empresa_id := public.get_default_empresa_id(default_tenant_id);
  if default_empresa_id is not null then
    insert into public.empresa_memberships (tenant_id, empresa_id, user_id, role, status)
    values (default_tenant_id, default_empresa_id, new.id, 'user', 'active')
    on conflict (tenant_id, empresa_id, user_id) do nothing;

    insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
    values (new.id, default_tenant_id, default_empresa_id)
    on conflict (user_id, tenant_id) do update
      set empresa_id = excluded.empresa_id,
          updated_at = now();
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

insert into public.profiles (id, email, nome)
select
  u.id,
  u.email,
  coalesce(u.raw_user_meta_data->>'nome', u.raw_user_meta_data->>'name')
from auth.users u
on conflict (id) do update
  set email = excluded.email,
      nome = excluded.nome;

with default_empresas as (
  select distinct on (e.tenant_id) e.tenant_id, e.id as empresa_id
  from public.empresas e
  where e.ativo = true
  order by e.tenant_id, e.criado_em asc nulls last
)
insert into public.empresa_memberships (tenant_id, empresa_id, user_id, role, status)
select tm.tenant_id, de.empresa_id, tm.user_id, 'user', 'active'
from public.tenant_memberships tm
join default_empresas de on de.tenant_id = tm.tenant_id
where tm.status = 'active'
on conflict (tenant_id, empresa_id, user_id) do nothing;

with default_empresas as (
  select distinct on (e.tenant_id) e.tenant_id, e.id as empresa_id
  from public.empresas e
  where e.ativo = true
  order by e.tenant_id, e.criado_em asc nulls last
)
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
select tm.user_id, de.tenant_id, de.empresa_id
from public.tenant_memberships tm
join default_empresas de on de.tenant_id = tm.tenant_id
left join public.user_empresa_context uec
  on uec.user_id = tm.user_id
 and uec.tenant_id = tm.tenant_id
where tm.status = 'active'
  and uec.user_id is null
on conflict (user_id, tenant_id) do nothing;

commit;
