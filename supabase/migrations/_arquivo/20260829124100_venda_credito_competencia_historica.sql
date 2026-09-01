begin;

-- Ao adicionar data_competencia com default, as linhas preexistentes receberam
-- a data da migration. Para exposicoes de OS, a competencia historica correta
-- e a conclusao (com abertura/criacao como fallback).
update f.gestao_cobranca_os g
   set data_competencia = coalesce(
         os.data_conclusao::date,
         os.data_abertura::date,
         g.created_at::date
       ),
       updated_at = now()
  from public.ordens_servico os
 where os.id = g.os_id
   and os.tenant_id = g.tenant_id
   and os.empresa_id = g.empresa_id
   and g.deleted_at is null
   and g.origem = 'OS_CONCLUIDA_SEM_NF'
   and g.data_competencia is distinct from coalesce(
         os.data_conclusao::date,
         os.data_abertura::date,
         g.created_at::date
       );

notify pgrst, 'reload schema';

commit;
