begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- A troca administrativa de senha usa o cliente service_role somente no
-- servidor. A rota valida o usuário autenticado, o tenant atual, o papel OWNER
-- e o vínculo do usuário alvo antes de chamar auth.admin.updateUserById.
--
-- O service_role já consegue ler a.usuario, mas perdeu o SELECT desta projeção
-- de vínculo. Sem ele, a validação segura falha com "permission denied" antes
-- de chegar à alteração da senha.
grant usage on schema a to service_role;
grant select on table a.usuario_tenant to service_role;

do $$
begin
  if not has_schema_privilege('service_role', 'a', 'usage')
     or not has_table_privilege('service_role', 'a.usuario_tenant', 'select') then
    raise exception 'admin_password_usuario_tenant_privilege_not_installed';
  end if;

  if has_table_privilege('service_role', 'a.usuario_tenant', 'insert')
     or has_table_privilege('service_role', 'a.usuario_tenant', 'update')
     or has_table_privilege('service_role', 'a.usuario_tenant', 'delete') then
    raise exception 'admin_password_usuario_tenant_unexpected_write_privilege';
  end if;
end;
$$;

comment on table a.usuario_tenant is
  'Vínculos de usuário por tenant; leitura service_role usada por rotas administrativas com validação server-side.';

commit;
