-- Conta de teste do app mobile (gabrielgolombieschi@gmail.com / colaborador
-- "GABRIEL MENDES TESTE") volta de TECNICO para COORDENACAO na ELETRICA SEGAU.
--
-- Com GESTOR no tenant e COORDENACAO na empresa, a conta fica igual aos
-- coordenadores de verdade (Clarice, Cleiton, Douglas, Everton, Lucas, Mateus
-- e Vagner).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

update a.usuario_empresa ue
   set papel = 'COORDENACAO'
  from a.usuario u
 where u.id = ue.usuario_id
   and u.email = 'gabrielgolombieschi@gmail.com'
   and ue.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
   and ue.deleted_at is null
   and ue.papel <> 'COORDENACAO';

do $assert$
declare
  v_papel_tenant text;
  v_papel_empresa text;
begin
  select upper(ut.papel), upper(ue.papel)
    into v_papel_tenant, v_papel_empresa
  from a.usuario u
  join a.usuario_tenant ut
    on ut.usuario_id = u.id
   and ut.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
   and ut.ativo is true
   and ut.deleted_at is null
  join a.usuario_empresa ue
    on ue.usuario_id = u.id
   and ue.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
   and ue.ativo is true
   and ue.deleted_at is null
  where u.email = 'gabrielgolombieschi@gmail.com'
    and u.ativo is true
    and u.deleted_at is null;

  if v_papel_empresa is distinct from 'COORDENACAO' or v_papel_tenant is distinct from 'GESTOR' then
    raise exception 'usuario_teste_mobile_papeis_invalidos: tenant=% empresa=%',
      coalesce(v_papel_tenant, '<nulo>'), coalesce(v_papel_empresa, '<nulo>');
  end if;
end;
$assert$;

commit;
