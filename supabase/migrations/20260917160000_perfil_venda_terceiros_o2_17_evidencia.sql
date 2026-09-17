-- Evidencia fiscal do perfil SEG-VENDA-TERCEIROS-SC-5102-O2-CST00-17.
--
-- Em 17/09/2026 a OV 363 (cilindro pneumatico GS-22-100 para a WEG Tintas, NCM 8412.31.90,
-- origem 2, uso e consumo do adquirente: CFOP 5102, CST 00 a 17%) foi homologada (NF-e 2/62)
-- e a liberacao do perfil parou em "Nao ha evidencia fiscal vinculada": o perfil nasceu sem
-- evidencia, ao contrario dos CSV63 e dos SEG anteriores. A liberacao exige a evidencia
-- (fn_perfil_operacao_nfe_liberar_producao).
--
-- A evidencia e a mesma combinacao ja observada no Vertex — CSV63 linhas 48 e 49 (NF 3602 e
-- 3603, 5102, origem 2, CST 000, 17%) — mais a propria homologacao 2/62. Faixa REVISAO, igual
-- ao perfil (o gatilho de faixa mantem as duas iguais).

insert into f.perfil_operacao_evidencia (
  id, tenant_id, empresa_id, fonte, fonte_linha, natureza_texto, cfop, origem, cst_completo, cst_icms,
  aliquota_icms_observada, aliquota_ipi_observada, base_reduzida_observada, itens_observados,
  notas_observadas, ncms, notas_exemplo, leitura_operacional, faixa, justificativa_faixa,
  divergencia_ipi, divergencia_fabricado_revenda, divergencia_cabo_beneficio,
  xml_notas, xml_itens, xml_pis_csts, xml_cofins_csts, xml_pis_aliquotas, xml_cofins_aliquotas,
  xml_ipi_csts, xml_cbenef_valores, xml_cbenef_ausente_itens, xml_fci_itens, xml_divergente
)
select
  '4c0a5e1e-9f0b-4c7a-9b2e-5102a2170001'::uuid, po.tenant_id, po.empresa_id,
  'CSV63 linhas 48 e 49 (NF 3602 e 3603 do Vertex: 5102, origem 2, CST 000, 17%) + NF-e homologacao 42260913671448000189550020000000621256372047',
  1, 'VENDA_MERCADORIA_TERCEIROS', '5102', 2, '200', '00', 17, 0, false, 3, 3,
  array['73181300', '84123190']::text[], array[3602, 3603]::integer[],
  'Venda de mercadoria adquirida de terceiros (origem 2) dentro de SC a 17%: uso e consumo ou ativo do adquirente, sem beneficio (RICMS/SC, art. 26, I). '
    || 'NF 3602 e 3603 do Vertex (NCM 7318.13.00) e a NF-e 2/62 de homologacao de 17/09/2026 (OV 363, cilindro GS-22-100 para a WEG Tintas, NCM 8412.31.90, protocolo 342260000951661): CFOP 5102, CST 00, 17%, IPI 53, PIS/COFINS 01, IBS/CBS 000/000001.',
  po.faixa_automacao, po.justificativa_faixa,
  false, false, false,
  0, 0, '{}'::text[], '{}'::text[], '{}'::numeric[], '{}'::numeric[], '{}'::text[], '{}'::text[], 0, 0, false
from f.perfil_operacao po
where po.codigo = 'SEG-VENDA-TERCEIROS-SC-5102-O2-CST00-17'
  and po.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
on conflict (tenant_id, empresa_id, fonte, fonte_linha) do nothing;

update f.perfil_operacao po
   set evidencia_id = '4c0a5e1e-9f0b-4c7a-9b2e-5102a2170001'::uuid
 where po.codigo = 'SEG-VENDA-TERCEIROS-SC-5102-O2-CST00-17'
   and po.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
   and po.evidencia_id is null
   and exists (select 1 from f.perfil_operacao_evidencia ev where ev.id = '4c0a5e1e-9f0b-4c7a-9b2e-5102a2170001'::uuid);

update f.perfil_operacao_evidencia ev
   set perfil_operacao_id = po.id
  from f.perfil_operacao po
 where ev.id = '4c0a5e1e-9f0b-4c7a-9b2e-5102a2170001'::uuid
   and po.codigo = 'SEG-VENDA-TERCEIROS-SC-5102-O2-CST00-17'
   and po.evidencia_id = ev.id
   and ev.perfil_operacao_id is null;
