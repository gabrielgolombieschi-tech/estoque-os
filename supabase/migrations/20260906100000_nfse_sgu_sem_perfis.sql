-- SGU fora do escopo da NFS-e (decisao de 05/09/2026: "nada de SGU"; criterio
-- de pronto de 06/09/2026: "nenhum perfil da SGU"). A migration de fundacao
-- (20260905190000) criou os cinco perfis de servico para toda empresa com
-- cadastro fiscal, e a de 06/09 (20260906090000) semeou as tabelas de aliquota
-- e de tributos aproximados pelo mesmo criterio. Aqui os registros da SGU
-- saem, desde que nunca tenham sido usados (nenhuma solicitacao, linha ou
-- evento de revisao apontando para eles). Local sem SGU: no-op.
do $$
declare
  v_sgu uuid;
begin
  select e.id into v_sgu from c.empresa e where e.codigo = 'SGU' and e.deleted_at is null limit 1;
  if v_sgu is null then return; end if;

  delete from f.nfse_aliquota_iss where empresa_id = v_sgu;
  delete from f.nfse_tributos_aproximados where empresa_id = v_sgu;
  delete from f.tributacao_provisoria_nfse_homologacao where empresa_id = v_sgu;
  delete from f.perfil_operacao po
  where po.empresa_id = v_sgu and po.modelo = 'NFSE'
    and not exists (select 1 from f.solicitacao_faturamento sf where sf.perfil_operacao_id = po.id)
    and not exists (select 1 from f.solicitacao_item si where si.perfil_operacao_id = po.id)
    and not exists (select 1 from f.perfil_operacao_revisao_evento re where re.perfil_operacao_id = po.id);
  if exists (select 1 from f.perfil_operacao po where po.empresa_id = v_sgu and po.modelo = 'NFSE') then
    raise exception 'Perfil de servico da SGU em uso: remover manualmente depois de revisar as referencias.';
  end if;
end;
$$;
