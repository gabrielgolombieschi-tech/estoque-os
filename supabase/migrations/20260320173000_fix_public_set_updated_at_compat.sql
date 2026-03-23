create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
declare
  v_now timestamptz := now();
begin
  if to_jsonb(new) ? 'updated_at' then
    new := jsonb_populate_record(new, jsonb_build_object('updated_at', v_now::text));
  end if;

  if to_jsonb(new) ? 'atualizado_em' then
    new := jsonb_populate_record(new, jsonb_build_object('atualizado_em', v_now::text));
  end if;

  return new;
end;
$$;
