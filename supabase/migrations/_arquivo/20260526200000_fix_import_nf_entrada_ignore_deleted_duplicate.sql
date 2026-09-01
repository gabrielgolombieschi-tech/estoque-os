do $$
declare
  v_sql text;
begin
  select pg_get_functiondef(
    'public.import_nf_entrada(uuid,item_finalidade,bigint,jsonb,jsonb,uuid,text,boolean,jsonb,integer,boolean,uuid,uuid)'::regprocedure
  )
    into v_sql;

  if position('and ne.deleted_at is null' in v_sql) = 0 then
    v_sql := replace(
      v_sql,
      '     and ne.chave = v_chave
   limit 1;',
      '     and ne.chave = v_chave
     and ne.deleted_at is null
   limit 1;'
    );

    if position('and ne.deleted_at is null' in v_sql) = 0 then
      raise exception 'Nao foi possivel atualizar public.import_nf_entrada para ignorar NF soft-deletada.';
    end if;

    execute v_sql;
  end if;
end;
$$;

notify pgrst, 'reload schema';
