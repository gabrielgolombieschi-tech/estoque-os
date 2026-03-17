create or replace function public.trg_itens_sync_timestamps()
returns trigger
language plpgsql
as $$
declare
  v_now timestamptz := now();
  v_created_at timestamptz;
  v_updated_at timestamptz;
begin
  if tg_op = 'INSERT' then
    if to_jsonb(new) ? 'created_at' then
      v_created_at := coalesce((to_jsonb(new)->>'created_at')::timestamptz, v_now);
      new := jsonb_populate_record(new, jsonb_build_object('created_at', v_created_at));
    else
      v_created_at := v_now;
    end if;

    if to_jsonb(new) ? 'updated_at' then
      v_updated_at := coalesce((to_jsonb(new)->>'updated_at')::timestamptz, v_created_at);
      new := jsonb_populate_record(new, jsonb_build_object('updated_at', v_updated_at));
    else
      v_updated_at := v_created_at;
    end if;

    if to_jsonb(new) ? 'criado_em' then
      new := jsonb_populate_record(
        new,
        jsonb_build_object('criado_em', coalesce((to_jsonb(new)->>'criado_em')::timestamp, v_created_at::timestamp))
      );
    end if;

    if to_jsonb(new) ? 'atualizado_em' then
      new := jsonb_populate_record(
        new,
        jsonb_build_object('atualizado_em', coalesce((to_jsonb(new)->>'atualizado_em')::timestamp, v_updated_at::timestamp))
      );
    end if;
  else
    if to_jsonb(new) ? 'updated_at' then
      v_updated_at := coalesce((to_jsonb(new)->>'updated_at')::timestamptz, v_now);
      new := jsonb_populate_record(new, jsonb_build_object('updated_at', v_updated_at));
    else
      v_updated_at := v_now;
    end if;

    if to_jsonb(new) ? 'atualizado_em' then
      new := jsonb_populate_record(new, jsonb_build_object('atualizado_em', v_updated_at::timestamp));
    end if;
  end if;

  return new;
end;
$$;

do $$
begin
  if to_regclass('public.itens') is null then
    return;
  end if;

  execute 'drop trigger if exists trg_itens_sync_timestamps on public.itens';
  execute 'create trigger trg_itens_sync_timestamps before insert or update on public.itens for each row execute function public.trg_itens_sync_timestamps()';
end;
$$;
