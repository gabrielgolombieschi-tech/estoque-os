begin;

-- Sustenta o filtro obrigatório por tenant/empresa e já entrega os registros
-- na ordem usada pela tela, evitando sort e varredura do histórico inteiro.
create index if not exists idx_apontamentos_horas_tenant_empresa_data_criado
  on public.apontamentos_horas (tenant_id, empresa_id, data desc, criado_em desc);

-- A policy anterior passava tenant_id da própria linha para can(), fazendo a
-- checagem completa de permissões milhares de vezes. O cinturão restritivo
-- enforce_active_empresa_scope já garante que cada linha pertence ao contexto
-- corrente; o SELECT escalar abaixo transforma a permissão em InitPlan e a
-- avalia uma única vez por consulta, sem alterar a autorização efetiva.
drop policy if exists enforce_apontamentos_read_role on public.apontamentos_horas;
create policy enforce_apontamentos_read_role
on public.apontamentos_horas as restrictive
for select to authenticated
using (
  (select public.can('apontamentos', 'read', public.current_tenant_id()))
);

analyze public.apontamentos_horas;

commit;

notify pgrst, 'reload schema';
