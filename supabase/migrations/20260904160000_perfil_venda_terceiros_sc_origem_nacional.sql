-- Perfil de venda de mercadoria de terceiros em SC para material NACIONAL.
--
-- O cadastro do item 3629 (CONTROLADOR PROGRAMAVEL PLC CPU, NCM 8537.10.20)
-- passou para origem 0 em 04/09/2026. So existia perfil ativo para origem 2, e
-- f.fn_solicitacao_nfe_resolver_perfis exige natureza real, ambito_destino e
-- ufs_destino. Resultado na tela da conferencia:
--
--   "Nenhum perfil fiscal para INTERNA, UF SC, indicador IE 1, origem 0."
--
-- Por que nao ativei o CSV63-008, que ja tem origem 0 / CST 00 / 12%: aquela
-- linha e matriz de evidencia, nao parametrizacao. Ela usa natureza sintetica
-- ('MATRIZ_CSV63_008'), esta em faixa BLOQUEADO com a justificativa
-- "5101/5102 depende de item.fabricado confirmado" e nao tem ambito, UF,
-- finalidade nem consumidor final. Converte-la apagaria a identidade de
-- catalogo e liberaria uma faixa que alguem bloqueou de proposito.
--
-- Este perfil e o irmao de origem 0 do SEG-VENDA-TERCEIROS-SC-5102-O2-CST00, e
-- ao contrario dele NAO se apoia em nota de homologacao propria: a evidencia
-- vem das NF-e reais de agosto/2026 (linha 8 do CSV) — CFOP 5102, origem 0,
-- CST 00, ICMS 12%, 8 notas, NCMs incluindo 85371020, exemplos 3693, 3694,
-- 3696, 3721, 3725, 3764, 3772 e 3773. A 3772 e a nota de referencia do
-- proprio usuario.
--
-- A duvida de 12% x 17% para este NCM CONTINUA aberta e esta em
-- docs/faturamento/auditoria-danfe-homologacao.md: nas notas reais desse NCM em
-- CFOP 5102 sao 23 a 17% e 8 a 12%. Fica 12% porque e a aliquota da nota de
-- referencia e a que o sistema ja vinha emitindo; trocar para 17% e decisao
-- fiscal, nao ajuste tecnico. Producao segue bloqueada
-- (habilitado_producao = false, faixa REVISAO).

-- A evidencia e derivada: f.perfil_operacao_evidencia tem unicidade por
-- (tenant, empresa, fonte, fonte_linha) e por evidencia_id do perfil, entao a
-- linha 8 do CSV nao pode ser reaproveitada. Esta copia declara a mesma leitura
-- com fonte propria, dizendo de onde veio.
insert into f.perfil_operacao_evidencia (
  tenant_id, empresa_id, fonte, fonte_linha, natureza_texto,
  cfop, origem, cst_completo, cst_icms,
  aliquota_icms_observada, aliquota_ipi_observada, base_reduzida_observada,
  itens_observados, notas_observadas, ncms, notas_exemplo,
  leitura_operacional, faixa, justificativa_faixa
)
select
  ev.tenant_id, ev.empresa_id,
  'regras-nfe-63-combinacoes.csv linha 8 + cadastro do item 3629 (origem 0)',
  ev.fonte_linha, ev.natureza_texto,
  ev.cfop, ev.origem, ev.cst_completo, ev.cst_icms,
  ev.aliquota_icms_observada, ev.aliquota_ipi_observada, ev.base_reduzida_observada,
  ev.itens_observados, ev.notas_observadas, ev.ncms, ev.notas_exemplo,
  'Evidencia do perfil ativo de material nacional, derivada do catalogo '
    || 'CSV63-008. Sao NF-e reais de agosto/2026 com CFOP 5102, origem 0, '
    || 'CST 00 e ICMS 12%, sem reducao de base: '
    || array_to_string(ev.notas_exemplo, ', ')
    || '. A 3772 e a nota de referencia do usuario, e 85371020 esta entre os '
    || 'NCMs observados. A alternativa de 17% aparece em 23 notas do mesmo NCM '
    || 'e segue em aberto com o contador.',
  'REVISAO',
  'Aliquota de 12% x 17% para o NCM 8537.10.20 ainda nao decidida.'
from f.perfil_operacao_evidencia ev
join f.perfil_operacao cat on cat.evidencia_id = ev.id
where cat.codigo = 'CSV63-008'
  and not exists (
    select 1 from f.perfil_operacao existente
    where existente.tenant_id = cat.tenant_id
      and existente.codigo = 'SEG-VENDA-TERCEIROS-SC-5102-O0-CST00'
  );

insert into f.perfil_operacao (
  tenant_id, empresa_id, codigo, nome, modelo,
  natureza_operacao, natureza_texto, crt,
  cfop_interno, ambito_destino, ufs_destino, indicador_ie_destinatario,
  origem_mercadoria, cst_icms, aliquota_icms, icms_modalidade_base_calculo,
  reducao_base_icms_percentual, cbenef, cbenef_aplicacao,
  cst_pis, aliquota_pis, cst_cofins, aliquota_cofins,
  finalidade_emissao, consumidor_final,
  exige_referencia, exige_motivo,
  faixa_automacao, justificativa_faixa, habilitado_producao,
  vigencia_inicio, evidencia_id, observacao
)
select
  base.tenant_id,
  base.empresa_id,
  'SEG-VENDA-TERCEIROS-SC-5102-O0-CST00',
  'SEG - venda de mercadoria de terceiros em SC - CFOP 5102 - origem 0 - CST 00',
  'NFE',
  base.natureza_operacao,
  base.natureza_texto,
  base.crt,
  '5102',
  'INTERNA',
  array['SC']::text[],
  '1',
  0,
  '00',
  12.0000,
  '3',
  0.0000,
  null,
  'SEM_BENEFICIO',
  '01', 1.6500,
  '01', 7.6000,
  1, 0,
  false, false,
  'REVISAO',
  'Exige confirmacao humana: a escolha entre 12% e 17% para o NCM 8537.10.20 '
    || 'ainda nao foi decidida pelo contador, e o IBS/CBS segue sem confirmacao.',
  false,
  current_date,
  (select ev.id
     from f.perfil_operacao_evidencia ev
    where ev.tenant_id = base.tenant_id
      and ev.fonte = 'regras-nfe-63-combinacoes.csv linha 8 + cadastro do item 3629 (origem 0)'),
  'Perfil de material nacional, irmao do O2-CST00. Evidencia nas NF-e reais de '
    || 'agosto/2026 (linha 8 do CSV, mesma do catalogo CSV63-008): CFOP 5102, '
    || 'origem 0, CST 00, ICMS 12%, 8 notas, NCMs incluindo 85371020, exemplos '
    || '3693 a 3773 — entre elas a 3772, nota de referencia. Nenhuma usou '
    || 'reducao de base. A alternativa de 17% aparece em 23 notas do mesmo NCM.'
from f.perfil_operacao base
where base.codigo = 'SEG-VENDA-TERCEIROS-SC-5102-O2-CST00'
  and not exists (
    select 1 from f.perfil_operacao existente
    where existente.tenant_id = base.tenant_id
      and existente.codigo = 'SEG-VENDA-TERCEIROS-SC-5102-O0-CST00'
  );
