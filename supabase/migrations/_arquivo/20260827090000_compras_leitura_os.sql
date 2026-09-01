begin;

set local role postgres;

-- A interface de OS ja permite que COMPRAS visualize as ordens em modo
-- somente leitura. A permissao efetiva, usada pela RLS de ordens_servico,
-- precisava refletir essa mesma regra.
--
-- A alteracao e propositalmente limitada a os.read. Permissoes negadas
-- individualmente continuam sendo aplicadas pela funcao original.
do $patch_get_full_permissions$
declare
  v_definition text;
  v_needle text := $needle$
  if v_empresa_papel_norm in ('ADMIN','COORDENACAO','FATURAMENTO') then
    extra_perms := extra_perms || jsonb_build_object(
      'os.read', true,
      'os.write', true,
      'os.delete', true,
      'os_itens.write', true,
      'os_gestao.write', true,
      'os_rpcs.execute', true
    );
  elsif v_empresa_papel_norm = 'APONTAMENTO_RH' then
$needle$;
  v_replacement text := $replacement$
  if v_empresa_papel_norm in ('ADMIN','COORDENACAO','FATURAMENTO') then
    extra_perms := extra_perms || jsonb_build_object(
      'os.read', true,
      'os.write', true,
      'os.delete', true,
      'os_itens.write', true,
      'os_gestao.write', true,
      'os_rpcs.execute', true
    );
  elsif v_empresa_papel_norm = 'COMPRAS' then
    extra_perms := extra_perms || jsonb_build_object('os.read', true);
  elsif v_empresa_papel_norm = 'APONTAMENTO_RH' then
$replacement$;
begin
  select pg_get_functiondef('public.get_full_permissions_unscoped_20260810(uuid,uuid)'::regprocedure)
    into v_definition;

  if position(v_needle in v_definition) = 0 then
    raise exception 'compras_os_read_patch_token_not_found';
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$patch_get_full_permissions$;

commit;
