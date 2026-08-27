begin;

set local role postgres;

-- COMPRAS pode consultar OS na interface, em modo somente leitura. A RLS de
-- ordens_servico consulta public.can(), cuja implementacao efetiva precisa
-- conceder a mesma permissao. Nenhuma permissao de escrita e adicionada.
do $patch_can_unscoped$
declare
  v_definition text;
  v_needle text := $needle$
  if p_resource = 'xml_import' and p_action = 'execute' then
$needle$;
  v_replacement text := $replacement$
  if p_resource = 'os' and p_action = 'read' and v_papel_empresa = 'COMPRAS' then
    return true;
  end if;

  if p_resource = 'xml_import' and p_action = 'execute' then
$replacement$;
begin
  select pg_get_functiondef('public.can_unscoped_20260810(text,text,uuid)'::regprocedure)
    into v_definition;

  if position(v_needle in v_definition) = 0 then
    raise exception 'compras_os_read_rls_patch_token_not_found';
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$patch_can_unscoped$;

commit;
