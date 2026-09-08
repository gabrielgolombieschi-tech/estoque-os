-- Perfil de industrializacao propria dentro de SC a 12%: destinatario contribuinte
-- do ICMS que declara revenda, insumo, manutencao ou consignado.
--
-- Motivo (08/09/2026): a OC 1311071 da Portobello (OS 319, KIT SENSOR-FLUXOMETRO
-- 30LT, R$ 18.166,99) traz "Utilizacao: COMPRA MANUT (ICMS)" e a propria OC diz,
-- na pagina 2, que para essas utilizacoes a aliquota interna e de 12% pela Lei
-- 17.878/2019, recusando a nota com aliquota divergente. Ate aqui so existia o
-- perfil de 17% (SEG-IND-SC-5101-O0-CST00-17), restrito a uso e consumo e ativo
-- imobilizado, entao uma nota real de manutencao nao tinha perfil e caia na
-- fixture — que so serve a homologacao.
--
-- Base legal da aliquota (nao e beneficio, entao nao leva cBenef): Lei 10.297/96,
-- art. 19, III, "n", e Lei 17.878/2019. Confirmado pelo contador em 06/09/2026:
-- "ICMS SC 17% ou 12% pela mesma regra de destinacao".
--
-- Nasce em REVISAO e sem producao: exige revisao fiscal, homologacao com o perfil
-- e liberacao amarrada aquela homologacao, como o de 17%.

insert into f.perfil_operacao (
  tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto, crt, cfop_interno, cfop_externo,
  cst_icms, cst_pis, cst_cofins, cbenef, reducao_base_icms_percentual, cbenef_aplicacao,
  observacao, vigencia_inicio, faixa_automacao, justificativa_faixa, origem_mercadoria, aliquota_icms, aliquota_pis, aliquota_cofins,
  habilitado_producao, ambito_destino, ufs_destino, indicador_ie_destinatario, icms_modalidade_base_calculo, finalidade_emissao, consumidor_final,
  destinacoes_mercadoria, exige_referencia, exige_motivo
)
select e.tenant_id, e.id, 'SEG-IND-SC-5101-O0-CST00-12',
  'SEG - venda de producao propria em SC - CFOP 5101 - origem 0 - CST 00 - 12% contribuinte',
  'NFE', 'VENDA_INDUSTRIALIZACAO_INTERNA', 'VENDA INDUSTRIALIZACAO DENTRO ESTADO', '3', '5101', null,
  '00', '01', '01', null, 0, 'SEM_BENEFICIO',
  'Aliquota interna de 12% para destinatario contribuinte do ICMS que declara revenda, insumo, manutencao ou consignado (Lei 10.297/96, art. 19, III, "n", e Lei 17.878/2019). Base cheia, sem reducao e sem cBenef: o produto fabricado nao esta no Anexo 2, art. 7, VII do RICMS/SC. IPI e atributo do NCM no cadastro do item e integra a base do ICMS somente quando o destinatario e consumidor final — o que nao e o caso aqui.',
  date '2026-09-08', 'REVISAO', 'Perfil de industrializacao a 12%; primeira nota assistida.', 0, 12.0000, 1.6500, 7.6000,
  false, 'INTERNA', array['SC'], '1', '3', 1, 0,
  array['REVENDA', 'INSUMO', 'MANUTENCAO', 'CONSIGNADO'], false, false
from c.empresa e
where e.codigo = 'SEG' and e.deleted_at is null
  and not exists (select 1 from f.perfil_operacao po where po.empresa_id = e.id and po.codigo = 'SEG-IND-SC-5101-O0-CST00-12');

-- Evidencia fiscal exigida pela liberacao para producao.
insert into f.perfil_operacao_evidencia (
  tenant_id, empresa_id, fonte, fonte_linha, natureza_texto, cfop, origem, cst_completo, cst_icms,
  aliquota_icms_observada, aliquota_ipi_observada, base_reduzida_observada, itens_observados, notas_observadas,
  ncms, notas_exemplo, leitura_operacional, faixa, justificativa_faixa,
  divergencia_ipi, divergencia_fabricado_revenda, divergencia_cabo_beneficio
)
select e.tenant_id, e.id,
  'regras-nfe-63-combinacoes.csv linha 20 (CFOP 5101, origem 0, CST 00, 12%: 3 itens em 2 NF-e de agosto/2026) + carta da PORTOBELLO (Lei 17.878/2019) + OC 1311071 de 08/09/2026', 20,
  'VENDA INDUSTRIALIZACAO DENTRO ESTADO', '5101', 0, '000', '00',
  -- Observacao real da linha 20 da matriz (mesma base da evidencia do CSV63-020): a
  -- evidencia exige itens e notas observados maiores que zero.
  12.0000, 0.0000, false, 3, 2,
  array['85371019','85372090','85389090','90328929'],
  array[3743, 3768],
  'Saida interna de producao propria para destinatario contribuinte do ICMS que declara revenda, insumo, manutencao ou consignado: 12% pela Lei 10.297/96, art. 19, III, "n", e Lei 17.878/2019. A carta da PORTOBELLO e a OC 1311071 ("COMPRA MANUT (ICMS)") listam manutencao entre as utilizacoes de 12% e recusam nota com aliquota divergente. Base cheia, sem cBenef: e aliquota, nao beneficio.',
  'REVISAO', 'Perfil de industrializacao a 12%; primeira nota assistida.',
  false, false, false
from c.empresa e
where e.codigo = 'SEG' and e.deleted_at is null
  -- A evidencia e identificada pela fonte, nao por CFOP/origem/aliquota: a linha 20 da
  -- matriz CSV63 ja tem evidencia 5101/origem 0/12% ligada ao perfil CSV63-020, e o
  -- vinculo perfil <-> evidencia e um-para-um (perfil_operacao_evidencia_id_ux).
  and not exists (select 1 from f.perfil_operacao_evidencia ev where ev.empresa_id = e.id and ev.fonte like '%OC 1311071 de 08/09/2026%');

update f.perfil_operacao po
set evidencia_id = ev.id
from f.perfil_operacao_evidencia ev
where po.codigo = 'SEG-IND-SC-5101-O0-CST00-12' and po.empresa_id = ev.empresa_id and po.evidencia_id is null
  and ev.fonte like '%OC 1311071 de 08/09/2026%' and ev.perfil_operacao_id is null;

update f.perfil_operacao_evidencia ev
set perfil_operacao_id = po.id
from f.perfil_operacao po
where po.evidencia_id = ev.id and ev.perfil_operacao_id is null and po.codigo = 'SEG-IND-SC-5101-O0-CST00-12';
