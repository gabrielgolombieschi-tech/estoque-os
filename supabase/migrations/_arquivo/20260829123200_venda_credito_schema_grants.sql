begin;

grant usage on schema r to authenticated, service_role;
grant usage on schema f to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
