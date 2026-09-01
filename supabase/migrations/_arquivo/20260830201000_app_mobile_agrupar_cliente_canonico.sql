-- O nome historico gravado na OS pode variar entre lancamentos do mesmo
-- cliente. O agrupamento deve usar primeiro o cadastro canonico para manter
-- uma unica linha por cliente_id.

do $patch_app_mobile_cliente_canonico$
declare
  v_definition text;
  v_patched text;
begin
  select pg_get_functiondef('public.app_os_agrupado_cliente(text[],text)'::regprocedure)
    into v_definition;

  v_patched := replace(
    v_definition,
    'coalesce(nullif(btrim(os.cliente_nome), ''''), nullif(btrim(cliente.nome), ''''), ''Cliente nao informado'')',
    'coalesce(nullif(btrim(cliente.nome), ''''), nullif(btrim(os.cliente_nome), ''''), ''Cliente nao informado'')'
  );

  if v_patched = v_definition then
    raise exception 'app_mobile_cliente_canonico_patch_token_not_found';
  end if;

  execute v_patched;
end;
$patch_app_mobile_cliente_canonico$;

