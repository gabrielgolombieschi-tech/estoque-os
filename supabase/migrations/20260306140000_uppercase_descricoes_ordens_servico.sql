-- Padroniza descricoes de OS em maiusculas, respeitando escopo tenant/empresa.
update public.ordens_servico
set
  descricao_servico = upper(descricao_servico),
  atualizado_em = now()
where tenant_id is not null
  and empresa_id is not null
  and descricao_servico is not null
  and descricao_servico <> upper(descricao_servico);
