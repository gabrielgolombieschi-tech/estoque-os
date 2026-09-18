-- Perfil de automacao para mercadoria de origem 1 (importada pela propria Segau, direto ou por
-- conta e ordem): SEG-VENDA-TERCEIROS-SC-5102-O1-CST20-AUTOMACAO.
--
-- Ate agora o beneficio do RICMS/SC-01, Anexo 2, Art. 7o, VII (CST 20, 17% com base reduzida em
-- 29,412%, carga efetiva de 12%, cBenef SC820006) so existia para origem 2
-- (SEG-VENDA-TERCEIROS-SC-5102-O2-CST20-AUTOMACAO, criado em 10/09/2026 sobre a NF-e 3607). Um item
-- importado por nos, com o MESMO NCM da lista, caia no perfil generico de origem 1
-- (SEG-VENDA-TERCEIROS-SC-5102-O1-CST00, 12% pela aliquota da Lei 10.297/96, art. 19, III, "n").
--
-- Decisao do Gabriel em 18/09/2026 para a OV-SEG-00012-026: a venda sai pelo beneficio, como a de
-- origem 2. Este perfil espelha o O2 em tudo que e ICMS (CST, aliquota, reducao, cBenef, texto
-- legal, NCMs elegiveis e destinacoes) e muda so o que a origem 1 exige: origem_mercadoria = 1 e o
-- IPI destacado (CST 50, cEnq 999), com a aliquota vinda do cadastro do produto / TIPI, porque a
-- Segau e adquirente na DI e equiparada a industrial (RIPI art. 9o, I).
--
-- NAO mexe no resolvedor. A regra de NCM ja existe desde 20260910190000 e e por origem: um perfil
-- com ncms_elegiveis so vale para os NCM da lista, e o perfil generico (sem lista) da MESMA origem
-- so entra quando nenhum perfil com lista casa com o NCM da linha. Logo:
--   NCM da lista + origem 1  -> este perfil (o O1-CST00 sai de cena);
--   NCM fora da lista (ex.: 85371020, da NF-e 2/33) + origem 1 -> segue no O1-CST00.
--
-- Nasce em REVISAO e com producao desabilitada: a revisao fiscal e do Gabriel, pela tela. Nenhum
-- snapshot de solicitacao existente muda; snapshots sao gravados por solicitacao.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

do $perfil$
declare
  v_o2 f.perfil_operacao%rowtype;
  v_perfil_id constant uuid := 'a6e1c3d2-5102-4c01-9a2b-000000000013';
  v_evidencia_id constant uuid := '4c0a5e1e-9f0b-4c7a-9b2e-5102a1000013';
  v_codigo constant text := 'SEG-VENDA-TERCEIROS-SC-5102-O1-CST20-AUTOMACAO';
begin
  select * into v_o2
  from f.perfil_operacao
  where codigo = 'SEG-VENDA-TERCEIROS-SC-5102-O2-CST20-AUTOMACAO';
  if v_o2.id is null then
    raise notice 'perfil de automacao de origem 2 nao existe neste banco: nada a espelhar.';
    return;
  end if;

  if exists (select 1 from f.perfil_operacao where codigo = v_codigo) then
    raise notice 'perfil % ja existe.', v_codigo;
    return;
  end if;

  -- O beneficio e dos tres NCM do Anexo 2, Art. 7o, VII; sem a lista o perfil viraria o generico.
  if v_o2.ncms_elegiveis is null or array_length(v_o2.ncms_elegiveis, 1) is null then
    raise exception 'o perfil de origem 2 esta sem ncms_elegiveis: espelhar agora criaria um perfil generico com beneficio';
  end if;

  insert into f.perfil_operacao_evidencia (
    id, tenant_id, empresa_id, fonte, fonte_linha, natureza_texto, cfop, origem,
    cst_completo, cst_icms, aliquota_icms_observada, aliquota_ipi_observada, base_reduzida_observada,
    itens_observados, notas_observadas, ncms, notas_exemplo, leitura_operacional,
    faixa, justificativa_faixa
  )
  values (
    v_evidencia_id, v_o2.tenant_id, v_o2.empresa_id,
    'Espelho do perfil SEG-VENDA-TERCEIROS-SC-5102-O2-CST20-AUTOMACAO (evidencia: NF-e 3607 de 07/04/2026, '
      || 'conferida com a contabilidade da Segau) para mercadoria de origem 1; caso de uso: OV-SEG-00012-026 '
      || '(OC 1312773, PBG S/A), item importado por conta e ordem pela NF-e 8509/1 da PRANA, DI 2422904512',
    1, v_o2.natureza_texto, v_o2.cfop_interno, 1,
    '1' || v_o2.cst_icms, v_o2.cst_icms, v_o2.aliquota_icms, 9.7500, true,
    -- A observacao e a mesma nota do perfil espelhado: NF-e 3607 de 07/04/2026, um item.
    1, 1, v_o2.ncms_elegiveis, array[3607]::integer[],
    'Venda em SC, para contribuinte, de equipamento de automacao com NCM da lista do Anexo 2, Art. 7o, VII, '
      || 'importado pela propria Segau (origem 1): CST 20 a 17% com base reduzida em 29,412% (carga efetiva de '
      || '12%) e cBenef SC820006, exatamente como no perfil de origem 2. A unica diferenca e o IPI: a Segau e '
      || 'adquirente na DI e equiparada a industrial (RIPI art. 9o, I), entao a revenda destaca o IPI do NCM '
      || '(CST 50, cEnq 999, aliquota do cadastro do produto conferida contra f.tipi_ncm), fora da base do ICMS '
      || 'quando o destinatario nao e consumidor final. Pendente de confirmacao da contabilidade: se o beneficio '
      || 'alcanca mercadoria importada e se a chave de seguranca com trava atende a descricao da Secao XIX do '
      || 'Anexo 1 (registrado em docs/faturamento/nfe-ov-012-chave-pizzato.md).',
    'REVISAO',
    'Perfil novo de 18/09/2026, criado por decisao do Gabriel para a OV-SEG-00012-026. Primeira nota assistida.'
  );

  insert into f.perfil_operacao (
    id, tenant_id, empresa_id, codigo, nome, modelo, crt,
    natureza_operacao, natureza_texto, ambito_destino, ufs_destino,
    cfop_interno, cfop_externo, indicador_ie_destinatario,
    cst_icms, aliquota_icms, reducao_base_icms_percentual, percentual_base_calculo,
    icms_modalidade_base_calculo, cbenef, cbenef_aplicacao, beneficio_texto_legal,
    cst_ipi, ipi_codigo_enquadramento_legal, aliquota_ipi,
    cst_pis, aliquota_pis, cst_cofins, aliquota_cofins,
    cst_ibs_cbs, cclass_trib, cclass_trib_versao, ibs_cbs_json,
    ncms_elegiveis, destinacoes_mercadoria, origem_mercadoria,
    finalidade_emissao, consumidor_final, exige_referencia, exige_motivo,
    faixa_automacao, justificativa_faixa, habilitado_producao, vigencia_inicio,
    evidencia_id, observacao
  )
  values (
    v_perfil_id, v_o2.tenant_id, v_o2.empresa_id, v_codigo,
    'SEG - venda de mercadoria de terceiros em SC - CFOP 5102 - origem 1 - CST 20 - base reduzida do Anexo 2, Art. 7o, VII',
    v_o2.modelo, v_o2.crt,
    v_o2.natureza_operacao, v_o2.natureza_texto, v_o2.ambito_destino, v_o2.ufs_destino,
    v_o2.cfop_interno, v_o2.cfop_externo, v_o2.indicador_ie_destinatario,
    v_o2.cst_icms, v_o2.aliquota_icms, v_o2.reducao_base_icms_percentual, v_o2.percentual_base_calculo,
    v_o2.icms_modalidade_base_calculo, v_o2.cbenef, v_o2.cbenef_aplicacao, v_o2.beneficio_texto_legal,
    -- IPI: o que muda na origem 1. A aliquota nao vem do perfil; vem do produto/TIPI (resolvedor).
    '50', '999', null,
    v_o2.cst_pis, v_o2.aliquota_pis, v_o2.cst_cofins, v_o2.aliquota_cofins,
    v_o2.cst_ibs_cbs, v_o2.cclass_trib, v_o2.cclass_trib_versao, v_o2.ibs_cbs_json,
    v_o2.ncms_elegiveis, v_o2.destinacoes_mercadoria, 1,
    v_o2.finalidade_emissao, v_o2.consumidor_final, v_o2.exige_referencia, v_o2.exige_motivo,
    'REVISAO',
    'Perfil novo de 18/09/2026: espelho do perfil de automacao de origem 2 para mercadoria importada pela '
      || 'propria Segau. Decisao do Gabriel na OV-SEG-00012-026. Producao so depois da revisao pela tela.',
    false, current_date,
    v_evidencia_id,
    'Espelha SEG-VENDA-TERCEIROS-SC-5102-O2-CST20-AUTOMACAO em todo o ICMS (CST 20, 17%, reducao de 29,412%, '
      || 'cBenef SC820006 e o mesmo texto legal do Anexo 2, Art. 7o, VII) e vale para os mesmos tres NCM. Muda '
      || 'so a origem (1) e o IPI: CST 50 com cEnq 999, aliquota do cadastro do produto / TIPI, porque a Segau '
      || 'e equiparada a industrial (RIPI art. 9o, I). O IPI fica fora da base do ICMS quando a destinacao segue '
      || 'em operacao tributada (revenda, insumo, consignacao). A trava de cBenef de automacao continua valendo: '
      || 'nota a 12% sem cBenef so passa quando os 12% sao aliquota (Lei 10.297/96, art. 19, III, "n"), o que e '
      || 'o caso do perfil O1-CST00, nao deste.'
  );

  update f.perfil_operacao_evidencia
     set perfil_operacao_id = v_perfil_id
   where id = v_evidencia_id;
end;
$perfil$;

do $assertions$
declare
  v_novo f.perfil_operacao%rowtype;
  v_o2 f.perfil_operacao%rowtype;
begin
  select * into v_novo from f.perfil_operacao where codigo = 'SEG-VENDA-TERCEIROS-SC-5102-O1-CST20-AUTOMACAO';
  if v_novo.id is null then return; end if;
  select * into v_o2 from f.perfil_operacao where codigo = 'SEG-VENDA-TERCEIROS-SC-5102-O2-CST20-AUTOMACAO';

  if v_novo.origem_mercadoria <> 1 then
    raise exception 'perfil novo nao ficou com origem 1: %', v_novo.origem_mercadoria;
  end if;
  if v_novo.cst_icms <> '20' or v_novo.aliquota_icms <> 17 or v_novo.reducao_base_icms_percentual <> 29.4120
     or v_novo.cbenef <> 'SC820006' then
    raise exception 'ICMS do perfil novo nao espelhou o O2: % % % %',
      v_novo.cst_icms, v_novo.aliquota_icms, v_novo.reducao_base_icms_percentual, v_novo.cbenef;
  end if;
  if v_novo.beneficio_texto_legal is distinct from v_o2.beneficio_texto_legal then
    raise exception 'texto legal do beneficio nao e o mesmo do perfil de origem 2';
  end if;
  if v_novo.ncms_elegiveis is distinct from v_o2.ncms_elegiveis then
    raise exception 'lista de NCM do perfil novo nao e a mesma do perfil de origem 2';
  end if;
  if v_novo.destinacoes_mercadoria is distinct from v_o2.destinacoes_mercadoria then
    raise exception 'destinacoes do perfil novo nao sao as mesmas do perfil de origem 2';
  end if;
  if v_novo.cst_ipi <> '50' or v_novo.ipi_codigo_enquadramento_legal <> '999' then
    raise exception 'IPI do perfil novo devia ser CST 50 / cEnq 999: % / %',
      v_novo.cst_ipi, v_novo.ipi_codigo_enquadramento_legal;
  end if;
  if v_novo.aliquota_ipi is not null then
    raise exception 'aliquota de IPI no perfil fixaria o percentual; ela tem de vir do produto/TIPI';
  end if;
  -- Revisao e liberacao sao do Gabriel, pela tela.
  if v_novo.habilitado_producao is not false or v_novo.revisao_fiscal_em is not null then
    raise exception 'perfil novo tem de nascer sem revisao e sem producao';
  end if;
  if v_novo.faixa_automacao <> 'REVISAO' then
    raise exception 'perfil novo tem de nascer em REVISAO';
  end if;
  if not exists (select 1 from f.perfil_operacao_evidencia e where e.perfil_operacao_id = v_novo.id) then
    raise exception 'evidencia do perfil novo nao ficou ligada';
  end if;
end;
$assertions$;

commit;
