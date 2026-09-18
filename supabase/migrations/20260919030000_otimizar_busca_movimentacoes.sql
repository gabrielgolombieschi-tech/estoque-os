-- As funcoes de contexto nao dependem da linha. Consultas escalares fazem o
-- PostgreSQL avalia-las uma vez por consulta (InitPlan), em vez de repetir as
-- verificacoes de usuario/empresa para cada movimento e NF do historico.
-- Preserva SECURITY INVOKER na RPC e todos os gates das politicas existentes.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

alter policy movimentacoes_select on public.movimentacoes
using (
  tenant_id = (select public.current_tenant_id())
  and empresa_id = (select public.current_empresa_id())
  and (
    (select public.can('estoque', 'read'))
    or (select public.can('estoque', 'write'))
  )
);

alter policy nf_entrada_select on public.nf_entrada
using (
  empresa_id is not null
  and tenant_id = (select public.current_tenant_id())
  and (select public.can__legacy_40734('fiscal_nf', 'read'))
);

alter policy ordens_servico_select_painel_tv on public.ordens_servico
using (
  tenant_id = (select public.current_tenant_id())
  and empresa_id = (select public.current_empresa_id())
  and tipo_documento = 'OS'
  and exists (
    select 1
    from a.usuario u
    join a.usuario_empresa ue on ue.usuario_id = u.id
    where u.auth_user_id = (select auth.uid())
      and u.deleted_at is null
      and ue.deleted_at is null
      and ue.ativo = true
      and ue.empresa_id = (select public.current_empresa_id())
      and ue.papel = 'PAINEL_TV'
  )
);

commit;
