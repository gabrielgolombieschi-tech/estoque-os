-- Ellen (estoque@segau.com.br) passa de APONTAMENTO_RH para ALMOXARIFADO na
-- ELETRICA SEGAU. Decisao de Gabriel em 07/09/2026.
--
-- Alinha o papel com o trabalho: ela cuida do estoque, e APONTAMENTO_RH era
-- heranca de outra epoca. Na pratica, o que muda para ela no app:
--   - sai do grupo de apontamento, entao a OS deixa de ser a visao restrita;
--   - passa a lancar material na OS (APONTAMENTO_RH nao lancava);
--   - passa a ver preco de material (app_mobile_pode_ver_preco_material);
--   - mantem a aba Estoque, que ja tinha;
--   - continua sem ver valor de OS nem faturamento.
--
-- ATENCAO: com esta mudanca ninguem mais fica em APONTAMENTO_RH na Segau, e a
-- tela Inicio dela vira o cartao "Faturamento restrito" — ALMOXARIFADO ainda
-- nao tem home propria. E a lacuna ja mapeada, que sera tratada em seguida.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

update a.usuario_empresa ue
   set papel = 'ALMOXARIFADO'
  from a.usuario u
 where u.id = ue.usuario_id
   and u.email = 'estoque@segau.com.br'
   and ue.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
   and ue.deleted_at is null
   and ue.papel <> 'ALMOXARIFADO';

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
  where u.email = 'estoque@segau.com.br'
    and u.ativo is true
    and u.deleted_at is null;

  if v_papel is distinct from 'ALMOXARIFADO' then
    raise exception 'ellen_papel_invalido: %', coalesce(v_papel, '<nulo>');
  end if;
end;
$assert$;

commit;
