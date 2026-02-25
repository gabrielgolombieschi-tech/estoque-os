begin;

-- Admin deve poder criar e gerenciar colaboradores
insert into public.role_permissions (role, permission) values
  ('admin', 'apontamentos.config')
on conflict do nothing;

commit;
