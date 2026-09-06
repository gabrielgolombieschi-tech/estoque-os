-- Evidencia fiscal do perfil de industrializacao SEG-IND-SC-5101-O0-CST00-17.
-- A liberacao para producao (tela /faturamento/perfis) exige perfil com
-- evidencia vinculada; o perfil nasceu sem ela na 20260906160000.
-- Fonte: 34 NF-e reais de agosto/2026 (3527-3553) com CFOP 5101, origem 0,
-- CST 00 e 17%, a NF-e 3766 (IPI do NCM 8537.10.19 integrando a base do ICMS
-- para consumidor final) e as respostas do contador de 06/09/2026 (pergunta 10).
insert into f.perfil_operacao_evidencia (
  tenant_id, empresa_id, fonte, fonte_linha, natureza_texto, cfop, origem, cst_completo, cst_icms,
  aliquota_icms_observada, aliquota_ipi_observada, base_reduzida_observada, itens_observados, notas_observadas,
  ncms, notas_exemplo, leitura_operacional, faixa, justificativa_faixa,
  divergencia_ipi, divergencia_fabricado_revenda, divergencia_cabo_beneficio
)
select e.tenant_id, e.id,
  'regras-nfe-63-combinacoes.csv linha 3 (CFOP 5101, origem 0, CST 00, 17%) + NF-e 3766 (IPI na base do ICMS) + respostas do contador de 06/09/2026', 3,
  'VENDA INDUSTRIALIZACAO DENTRO ESTADO', '5101', 0, '000', '00',
  17.0000, 0.0000, false, 37, 34,
  array['72085300','72189900','73071910','73269090','84289090','84798290','84799090','84834090','85030010','85371019','85372090','85389090','90261029','90328929'],
  array[3527,3528,3529,3530,3535,3543,3549,3553,3766],
  'Venda de producao propria dentro de SC para uso e consumo ou ativo do adquirente (consumidor final): CST 00, 17% (RICMS/SC art. 26, I), base cheia, sem reducao e sem cBenef (paineis 8537/8538 nao estao no Anexo 2 art. 7 VII). IPI e atributo do NCM no cadastro do item (3766: 9,75% no 8537.10.19; 9032.89.29 com aliquota zero, CST 51) e integra a base do ICMS quando o destinatario e consumidor final. Confirmado pelo contador em 06/09/2026.',
  'REVISAO', 'Perfil de industrializacao propria; primeira nota assistida.',
  false, false, false
from c.empresa e
where e.codigo = 'SEG' and e.deleted_at is null
  and not exists (select 1 from f.perfil_operacao_evidencia ev where ev.empresa_id = e.id and ev.cfop = '5101' and ev.origem = 0 and ev.fonte like '%respostas do contador de 06/09/2026%');

update f.perfil_operacao po
set evidencia_id = ev.id
from f.perfil_operacao_evidencia ev
where po.codigo = 'SEG-IND-SC-5101-O0-CST00-17' and po.empresa_id = ev.empresa_id and po.evidencia_id is null
  and ev.cfop = '5101' and ev.origem = 0 and ev.fonte like '%respostas do contador de 06/09/2026%';

update f.perfil_operacao_evidencia ev
set perfil_operacao_id = po.id
from f.perfil_operacao po
where po.evidencia_id = ev.id and ev.perfil_operacao_id is null and po.codigo = 'SEG-IND-SC-5101-O0-CST00-17';
