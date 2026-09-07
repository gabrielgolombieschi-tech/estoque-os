-- Fecha a folga do teste com o perfil TECNICO.
--
-- 20260907000000 colocou a conta de teste (gabrielgolombieschi@gmail.com) como
-- TECNICO na empresa, mas o papel de TENANT continuava OWNER. No app isso nao
-- aparece — ehPapelApontador() ja trata TECNICO como apontamento —, so que no
-- banco a guarda de 20260823130000 corta permissao apenas para o papel literal
-- APONTADOR. Com TECNICO, valia o papel de tenant, e OWNER libera tudo: o teste
-- mostraria uma tela restrita sobre uma conta que, por baixo, era admin.
--
-- Passa para GESTOR, igual aos outros apontadores/tecnicos (Samuel e Paulo
-- Andre). A projecao (trg_sync_usuario_tenant_projection) reescreve
-- tenant_memberships sozinha.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

update a.usuario_tenant ut
   set papel = 'GESTOR'
  from a.usuario u
 where u.id = ut.usuario_id
   and u.email = 'gabrielgolombieschi@gmail.com'
   and ut.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
   and ut.deleted_at is null
   and ut.papel <> 'GESTOR';

do $assert$
declare
  v_papel_tenant text;
  v_papel_empresa text;
begin
  select upper(ut.papel)
    into v_papel_tenant
  from a.usuario u
  join a.usuario_tenant ut
    on ut.usuario_id = u.id
   and ut.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
   and ut.ativo is true
   and ut.deleted_at is null
  where u.email = 'gabrielgolombieschi@gmail.com';

  select upper(ue.papel)
    into v_papel_empresa
  from a.usuario u
  join a.usuario_empresa ue
    on ue.usuario_id = u.id
   and ue.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
   and ue.ativo is true
   and ue.deleted_at is null
  where u.email = 'gabrielgolombieschi@gmail.com';

  if v_papel_tenant is distinct from 'GESTOR' or v_papel_empresa is distinct from 'TECNICO' then
    raise exception 'usuario_teste_mobile_papeis_invalidos: tenant=% empresa=%',
      coalesce(v_papel_tenant, '<nulo>'), coalesce(v_papel_empresa, '<nulo>');
  end if;
end;
$assert$;

commit;
