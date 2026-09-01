do $$
declare
  v_sql text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(
    'public.import_nf_entrada(uuid,item_finalidade,bigint,jsonb,jsonb,uuid,text,boolean,jsonb,integer,boolean,uuid,uuid)'::regprocedure
  )
    into v_sql;

  v_old := $old$
  if coalesce(p_gerar_contas_pagar, false) then
    if not (public.can('financeiro','write') or public.can('financeiro','config')) then
      raise exception 'Sem permissao para gerar contas a pagar';
    end if;
  end if;
$old$;

  v_new := $new$
  if coalesce(p_gerar_contas_pagar, false) then
    if not (
      public.can('financeiro','write')
      or public.can('financeiro','config')
      or public.can('xml_import','execute')
      or public.can('xml_import_faturamento','execute')
      or public.can('nf_entrada','import')
    ) then
      raise exception 'Sem permissao para gerar contas a pagar';
    end if;
  end if;
$new$;

  if position(v_new in v_sql) > 0 then
    return;
  end if;

  if position(v_old in v_sql) = 0 then
    raise exception 'Nao foi possivel localizar o bloco de permissao de AP em public.import_nf_entrada.';
  end if;

  v_sql := replace(v_sql, v_old, v_new);
  execute v_sql;
end;
$$;

notify pgrst, 'reload schema';
