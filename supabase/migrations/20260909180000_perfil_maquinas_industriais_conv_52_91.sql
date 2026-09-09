-- Perfil de NF-e para maquina industrial com reducao de base (Convenio ICMS 52/91).
--
-- Orientacao da contabilidade em 09/09/2026, sobre a NF-e da ARCELORMITTAL: aliquota
-- 17%, CST 20, reducao da base de 48,23%, cBenef SC820028 e, em dados adicionais, a
-- base legal "ARTIGO 9o INCISO I, DO ANEXO 2 DO RICMS/SC". A referencia foi a NF-e
-- 3805 do ERP antigo (04/09/2026), que saiu exatamente assim.
--
-- 17% sobre base reduzida em 48,2353% da a carga efetiva de 8,80% que o convenio
-- estabelece; os 48,23% da contabilidade caem dentro da tolerancia de 0,01 ponto que o
-- builder ja aplica, entao fica o numero que ela passou. Conferindo pela 3805: item de
-- 9.800,00 com base 5.072,94 e ICMS 862,40 — 8,8% de carga.
--
-- Escopo deliberadamente estreito: CFOP 5101 (saida interna) e destinacoes de 17%
-- (uso e consumo, ativo imobilizado), que e o caso da ARCELORMITTAL. Operacao
-- interestadual e destinatario contribuinte a 12% tem carga propria no convenio e
-- ficam de fora ate a contabilidade definir cada uma.
--
-- Nasce em REVISAO e sem producao liberada: serve para homologar agora, e a liberacao
-- de producao continua passando pelo fluxo auditado de sempre.

insert into f.perfil_operacao (
  id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto,
  cfop_interno, ambito_destino, destinacoes_mercadoria, indicador_ie_destinatario,
  consumidor_final, finalidade_emissao,
  cst_icms, aliquota_icms, reducao_base_icms_percentual, percentual_base_calculo,
  icms_modalidade_base_calculo, cbenef, cbenef_aplicacao, beneficio_texto_legal,
  cst_pis, cst_cofins, aliquota_pis, aliquota_cofins,
  faixa_automacao, habilitado_producao, vigencia_inicio,
  revisao_fiscal_em, revisao_fiscal_justificativa, justificativa_faixa
)
select
  gen_random_uuid(),
  p.tenant_id, p.empresa_id,
  'SEG-IND-SC-5101-O0-CST20-CONV5291',
  'SEG - venda de producao propria em SC - CFOP 5101 - origem 0 - CST 20 - maquina industrial Conv. 52/91 (carga 8,8%)',
  p.modelo, p.natureza_operacao, p.natureza_texto,
  p.cfop_interno, p.ambito_destino, p.destinacoes_mercadoria, p.indicador_ie_destinatario,
  p.consumidor_final, p.finalidade_emissao,
  '20', 17.0000, 48.2300, 51.7700,
  coalesce(p.icms_modalidade_base_calculo, '3'), 'SC820028', 'COM_BENEFICIO',
  'BASE LEGAL DO BENEFICIO ARTIGO 9O INCISO I, DO ANEXO 2 DO RICMS/SC.',
  p.cst_pis, p.cst_cofins, p.aliquota_pis, p.aliquota_cofins,
  'REVISAO', false, current_date,
  now(),
  'Convenio ICMS 52/91, RICMS/SC-01, Anexo 2, Art. 9o, I. Aliquota 17% com base reduzida em 48,23% (carga 8,8%) e cBenef SC820028, conforme a contabilidade em 09/09/2026 e a NF-e 3805 do ERP antigo.',
  'Maquina industrial com reducao de base; primeira nota assistida.'
from f.perfil_operacao p
where p.codigo = 'SEG-IND-SC-5101-O0-CST00-17'
  and not exists (
    select 1 from f.perfil_operacao x
    where x.tenant_id = p.tenant_id and x.empresa_id = p.empresa_id
      and x.codigo = 'SEG-IND-SC-5101-O0-CST20-CONV5291'
  );
