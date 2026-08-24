-- hh_lancamentos.hh_tipo_id possui FK para cliente_hh_servicos(id).
-- O mapeamento legado de tipo pode conter IDs sem registro nessa tabela;
-- nas RPCs móveis, a especialidade já validada é a referência compatível com a FK.

do $$
declare
  v_original text;
  v_ajustada text;
begin
  select pg_get_functiondef('public.app_lancar_hh(integer,uuid,date,bigint,time,time,time,time,smallint,numeric,numeric,text)'::regprocedure)
    into v_original;
  v_ajustada := replace(
    v_original,
    $trecho$    v_tenant_id,
    v_empresa_id,
    p_os_id,
    p_colaborador_id,
    v_hh_tipo_id,
    p_hh_servico_id,$trecho$,
    $trecho$    v_tenant_id,
    v_empresa_id,
    p_os_id,
    p_colaborador_id,
    p_hh_servico_id,
    p_hh_servico_id,$trecho$
  );
  if v_ajustada = v_original then
    raise exception 'Não foi possível ajustar app_lancar_hh para a FK de hh_tipo_id.';
  end if;
  execute v_ajustada;

  select pg_get_functiondef('public.app_lancar_hh_lote(integer,date,time,time,time,time,smallint,text,jsonb)'::regprocedure)
    into v_original;
  v_ajustada := replace(
    v_original,
    $trecho$    v_tenant_id, v_empresa_id, p_os_id, v_colaborador_ids[i], v_hh_tipo_id, v_servico_ids[i],$trecho$,
    $trecho$    v_tenant_id, v_empresa_id, p_os_id, v_colaborador_ids[i], v_servico_ids[i], v_servico_ids[i],$trecho$
  );
  if v_ajustada = v_original then
    raise exception 'Não foi possível ajustar app_lancar_hh_lote para a FK de hh_tipo_id.';
  end if;
  execute v_ajustada;
end;
$$;
