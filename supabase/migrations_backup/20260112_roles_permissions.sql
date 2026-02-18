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

-- Garantir tabela/colunas mesmo se existir com schema antigo
-- Zera tabelas legadas com colunas incompatÃ­veis
DROP TABLE IF EXISTS public.role_permissions CASCADE;

create table if not exists public.role_permissions (
  role text not null,
  permission text not null,
  primary key (role, permission)
);

alter table public.role_permissions
  add column if not exists role text;

alter table public.role_permissions
  add column if not exists permission text;

-- Normaliza valores nulos herdados
update public.role_permissions
set role = coalesce(role, 'admin')
where role is null;

update public.role_permissions
set permission = coalesce(permission, '')
where permission is null;

-- Remove registros invÃ¡lidos e duplicados de schema antigo
delete from public.role_permissions
where permission = '';

delete from public.role_permissions rp
using public.role_permissions rp2
where rp.ctid < rp2.ctid
  and rp.role = rp2.role
  and rp.permission = rp2.permission;

-- Recria a PK correta se vier de schema legado
alter table public.role_permissions
  drop constraint if exists role_permissions_pkey;

alter table public.role_permissions
  add constraint role_permissions_pkey primary key (role, permission);

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
