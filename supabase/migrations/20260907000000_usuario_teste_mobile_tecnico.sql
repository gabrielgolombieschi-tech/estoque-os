-- Conta de teste do app mobile (gabrielgolombieschi@gmail.com / colaborador
-- "GABRIEL MENDES TESTE") passa de APONTADOR para TECNICO na ELETRICA SEGAU,
-- para a proxima rodada de testes.
--
-- Atencao a diferenca: no app, ehPapelApontador() trata TECNICO como
-- apontador, entao a tela continua restrita. No banco, porem, a guarda de
-- 20260823130000_apontador_guardas_autorizacao.sql so corta permissao para o
-- papel literal APONTADOR — com TECNICO valem as permissoes do papel de
-- tenant, que nesta conta e OWNER.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

update a.usuario_empresa ue
   set papel = 'TECNICO'
  from a.usuario u
 where u.id = ue.usuario_id
   and u.email = 'gabrielgolombieschi@gmail.com'
   and ue.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
   and ue.deleted_at is null
   and ue.papel <> 'TECNICO';

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

  if v_papel is distinct from 'TECNICO' then
    raise exception 'usuario_teste_mobile_papel_invalido: %', coalesce(v_papel, '<nulo>');
  end if;
end;
$assert$;

commit;
