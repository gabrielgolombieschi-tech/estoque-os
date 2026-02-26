begin;
insert into public.role_permissions (role, permission) values
  ('admin', 'apontamentos.lancar')
on conflict do nothing;
commit;
