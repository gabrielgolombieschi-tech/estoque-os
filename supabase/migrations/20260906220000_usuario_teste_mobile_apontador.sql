-- Conta de teste do app mobile (gabrielgolombieschi@gmail.com / colaborador
-- "GABRIEL MENDES TESTE") passa de ADMIN para APONTADOR na ELETRICA SEGAU.
-- O papel de empresa e a fonte do app_meu_papel_empresa() usado pelo mobile e,
-- pelas guardas de 20260823130000_apontador_guardas_autorizacao.sql, APONTADOR
-- vence o papel de tenant (OWNER) em can()/get_full_permissions.
-- A projecao (trg_sync_usuario_empresa_projection) reescreve tenant_memberships
-- e membership_roles sozinha.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

update a.usuario_empresa ue
   set papel = 'APONTADOR'
  from a.usuario u
 where u.id = ue.usuario_id
   and u.email = 'gabrielgolombieschi@gmail.com'
   and ue.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
   and ue.deleted_at is null
   and ue.papel <> 'APONTADOR';

do $assert$
declare
  v_papel text;
begin
  select upper(ue.papel)
    into v_papel
  from a.usuario u
  join a.usuario_empresa ue
    on ue.usuario_id = u.id
   and ue.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
   and ue.ativo is true
   and ue.deleted_at is null
  where u.email = 'gabrielgolombieschi@gmail.com'
    and u.ativo is true
    and u.deleted_at is null;

  if v_papel is distinct from 'APONTADOR' then
    raise exception 'usuario_teste_mobile_papel_invalido: %', coalesce(v_papel, '<nulo>');
  end if;
end;
$assert$;

commit;
