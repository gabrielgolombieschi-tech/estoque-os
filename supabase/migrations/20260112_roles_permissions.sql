begin;

alter table public.tenant_memberships
  add column if not exists role text;

update public.tenant_memberships
set role = 'admin'
where role is null;

alter table public.tenant_memberships
  alter column role set default 'admin';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'tenant_memberships_role_check'
  ) then
    alter table public.tenant_memberships
      add constraint tenant_memberships_role_check
      check (role in ('admin', 'fiscal', 'estoque', 'projetos'));
  end if;
end$$;

create table if not exists public.role_permissions (
  role text not null,
  permission text not null,
  primary key (role, permission)
);

insert into public.role_permissions (role, permission) values
  ('admin', 'estoque.view'),
  ('admin', 'estoque.ajuste.create'),
  ('admin', 'itens.view'),
  ('admin', 'itens.create'),
  ('admin', 'fornecedores.create'),
  ('admin', 'nf_entrada.import'),
  ('admin', 'movimentacoes.view'),
  ('admin', 'fiscal.edit'),
  ('admin', 'projetos.view'),
  ('estoque', 'estoque.view'),
  ('estoque', 'estoque.ajuste.create'),
  ('estoque', 'itens.view'),
  ('estoque', 'itens.create'),
  ('estoque', 'fornecedores.create'),
  ('estoque', 'movimentacoes.view'),
  ('fiscal', 'itens.view'),
  ('fiscal', 'fornecedores.create'),
  ('fiscal', 'nf_entrada.import'),
  ('fiscal', 'movimentacoes.view'),
  ('fiscal', 'fiscal.edit'),
  ('projetos', 'projetos.view')
on conflict do nothing;

create or replace view public.v_user_permissions as
select tm.tenant_id, rp.permission
from public.tenant_memberships tm
join public.role_permissions rp
  on rp.role = tm.role
where tm.user_id = auth.uid()
  and tm.status = 'active';

commit;
