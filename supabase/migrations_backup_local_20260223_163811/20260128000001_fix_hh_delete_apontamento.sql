begin;

-- Fix: deleting public.hh_lancamentos was failing because the trigger function
-- public.fn_hh_delete_apontamento() referenced public.apontamentos_horas.deleted_at,
-- but the table does not have this column in the current schema.
--
-- apountamentos_horas already has FK (hh_lancamento_id) ON DELETE CASCADE, so no extra
-- action is required on delete.

create or replace function public.fn_hh_delete_apontamento() returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  return old;
end;
$$;

commit;

