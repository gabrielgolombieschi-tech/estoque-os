begin;

with roles_norm as (
  select
    id,
    lower(coalesce(name, '')) as name_norm
  from public.roles
),
target_roles as (
  select id
  from roles_norm
  where name_norm like 'admin%'
     or name_norm like 'financeir%'
     or name_norm like 'coord%'
     or name_norm like 'coorden%'
     or name_norm like 'compras%'
     or name_norm like 'almox%'
     or name_norm like 'estoque%'
),
rules(resource, action) as (
  values
    ('xml_import', 'execute'),
    ('nf_entrada', 'import')
)
insert into public.role_access_rules (role_id, resource, action)
select tr.id, r.resource, r.action
from target_roles tr
cross join rules r
on conflict do nothing;

commit;
