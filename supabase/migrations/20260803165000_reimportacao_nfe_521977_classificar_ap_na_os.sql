do $$
declare
  v_definition text;
  v_old text := $needle$
    p_motivo_compra_id => v_motivo_id,
    p_os_id => null,
    p_aprovado_por => v_solicitante_id
  $needle$;
  v_new text := $replacement$
    p_motivo_compra_id => v_motivo_id,
    p_os_id => v_os_id,
    p_aprovado_por => v_solicitante_id
  $replacement$;
begin
  select pg_get_functiondef(
    'public.corrigir_reimportacao_nfe_521977(text)'::regprocedure
  ) into v_definition;

  if position(v_old in v_definition) = 0 then
    raise exception 'Trecho de classificacao do AP nao encontrado na rotina de reimportacao';
  end if;

  execute replace(v_definition, v_old, v_new);
end;
$$;

