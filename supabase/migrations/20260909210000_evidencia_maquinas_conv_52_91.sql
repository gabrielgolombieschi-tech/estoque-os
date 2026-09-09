-- Evidencia fiscal do perfil de maquina industrial (Convenio 52/91).
--
-- Gabriel, 09/09/2026. A liberacao de producao do perfil
-- SEG-IND-SC-5101-O0-CST20-CONV5291 fica bloqueada com "Nao ha evidencia fiscal
-- vinculada": a tela exige que a decisao tributaria esteja ancorada em nota observada,
-- e o perfil nasceu por migration sem esse lastro.
--
-- A evidencia sao as duas NF-e reais da ARCELORMITTAL emitidas pelo ERP antigo, 3804
-- (03/09/2026) e 3805 (04/09/2026): 25 itens cada, todas NCM 8479.81.90, CFOP 5101,
-- CST 020, ICMS 17% sobre base reduzida e cBenef SC820028. A 3804 esta importada neste
-- sistema (nf_entrada 2289) e foi conferida item a item; a 3805 foi conferida pelo
-- DANFE que a contabilidade enviou. Nas duas a carga efetiva fecha em 8,80% — no item
-- de 9.800,00 a base sai 5.072,94 e o ICMS 862,40.
--
-- Fica em REVISAO: a evidencia sustenta a decisao, e a liberacao de producao continua
-- sendo ato humano na tela, vinculado a uma homologacao autorizada.

insert into f.perfil_operacao_evidencia (
  id, tenant_id, empresa_id, fonte, fonte_linha, natureza_texto, cfop, origem,
  cst_completo, cst_icms, aliquota_icms_observada, aliquota_ipi_observada,
  base_reduzida_observada, itens_observados, notas_observadas, ncms, notas_exemplo,
  leitura_operacional, faixa, justificativa_faixa, perfil_operacao_id
)
select
  gen_random_uuid(), p.tenant_id, p.empresa_id,
  'NF-e 3804 e 3805 da ARCELORMITTAL (ERP antigo, 03 e 04/09/2026) + orientacao da contabilidade de 09/09/2026',
  1,
  'VENDA INDUSTRIALIZACAO DENTRO ESTADO',
  '5101', 0, '020', '20',
  17.0000, 0.0000, true,
  50, 2,
  array['84798190'],
  array[3804, 3805],
  'Venda de producao propria dentro de SC de maquinas, aparelhos e equipamentos industriais. '
    || 'ICMS com CST 20 e base reduzida para a carga efetiva de 8,80% (Convenio ICMS 52/91, '
    || 'RICMS/SC-01, Anexo 2, Art. 9o, I), cBenef SC820028 e a base legal em dados adicionais. '
    || 'Sem IPI: os itens saem com CST 51.',
  'REVISAO',
  'Decisao tributaria ancorada em duas notas reais do ERP antigo com o mesmo NCM, CFOP, CST e carga; '
    || 'primeira nota assistida no sistema novo.',
  p.id
from f.perfil_operacao p
where p.codigo = 'SEG-IND-SC-5101-O0-CST20-CONV5291'
  and p.evidencia_id is null
  and not exists (
    select 1 from f.perfil_operacao_evidencia e where e.perfil_operacao_id = p.id
  );

update f.perfil_operacao p
   set evidencia_id = e.id
  from f.perfil_operacao_evidencia e
 where e.perfil_operacao_id = p.id
   and p.codigo = 'SEG-IND-SC-5101-O0-CST20-CONV5291'
   and p.evidencia_id is null;
