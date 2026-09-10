-- Perfil de automacao: evidencia da NF-e 3607 e as decisoes que faltavam para liberar producao.
--
-- O perfil SEG-VENDA-TERCEIROS-SC-5102-O2-CST20-AUTOMACAO nasceu na 20260910210000 com a
-- tributacao certa (CST 20, 17% sobre base reduzida em 29,412%, carga efetiva de 12%,
-- cBenef SC820006 do RICMS/SC-01, Anexo 2, Art. 7o, VII), mas sem tres coisas que a tela
-- de perfis nao edita e sem as quais f.fn_nfe_producao_pronta nunca abre o portao:
--
--   1. evidencia_id            — "Nao ha evidencia fiscal vinculada."
--   2. cbenef_aplicacao        — "A aplicacao de cBenef nao foi decidida."
--   3. finalidade/consumidor   — "Finalidade da emissao e consumidor final nao estao confirmados."
--
-- A evidencia e a propria NF-e 3607, de 07/04/2026 — a nota que o Gabriel anexou e que a
-- contabilidade aprovou, e que a homologacao 2/45 reproduziu numero a numero: base 169,20
-- com reducao de 29,412%, ICMS 28,76 a 17%, cBenef SC820006, IPI CST 50 a 9,75% (23,37),
-- total 263,07 na chave de seguranca Pizzato FD-2083, NCM 8536.50.90.
--
-- cbenef_aplicacao = COM_BENEFICIO porque o perfil de fato carrega o cBenef; a check
-- perfil_operacao_cbenef_aplicacao_ck exige que os dois andem juntos.
--
-- finalidade_emissao = 1 (normal) e consumidor_final = 0: e revenda a contribuinte que
-- declara insumo de producao. indFinal 1 aqui mudaria a base do ICMS, porque o IPI so
-- entra nela quando o destinatario e consumidor final (LC 87/96, art. 13, §2o).

do $configurar$
declare
  v_perfil f.perfil_operacao%rowtype;
  v_evidencia uuid;
begin
  select * into v_perfil
  from f.perfil_operacao
  where codigo = 'SEG-VENDA-TERCEIROS-SC-5102-O2-CST20-AUTOMACAO';
  if not found then
    raise notice 'Perfil de automacao nao existe neste banco; nada a fazer.';
    return;
  end if;

  if v_perfil.evidencia_id is null then
    insert into f.perfil_operacao_evidencia (
      tenant_id, empresa_id, fonte, fonte_linha, natureza_texto, cfop, origem, cst_completo, cst_icms,
      aliquota_icms_observada, aliquota_ipi_observada, base_reduzida_observada,
      itens_observados, notas_observadas, ncms, notas_exemplo,
      leitura_operacional, faixa, justificativa_faixa, perfil_operacao_id
    ) values (
      v_perfil.tenant_id,
      v_perfil.empresa_id,
      'NF-e 3607 (07/04/2026), conferida com a contabilidade da Segau',
      1, -- a linha da chave de seguranca FD-2083 dentro da nota
      'VENDA MERCADORIA ADQ. REC. DE TERCEIROS',
      '5102',
      2,
      '220', -- origem 2 + CST 20, como as outras linhas de evidencia
      '20',
      17.0000,
      9.7500,
      true,
      1,
      1,
      array['85365090'],
      array[3607],
      'Revenda em SC de equipamento de automacao importado (origem 2) para contribuinte: '
        || 'CST 20 a 17% com base reduzida em 29,412%, o que da a carga efetiva de 12% que o '
        || 'RICMS/SC-01, Anexo 2, Art. 7o, VII autoriza, com o cBenef SC820006 que a SEFAZ '
        || 'passou a exigir em 03/02/2025. O IPI e atributo do NCM no cadastro do item, '
        || 'conferido contra f.tipi_ncm: 8536.50.90 e tributado a 9,75%, CST 50. O IPI fica '
        || 'fora da base do ICMS porque o destinatario nao e consumidor final. Espelha a '
        || 'NF-e 3607, aprovada pela contabilidade e reproduzida na homologacao 2/45.',
      'REVISAO',
      'Primeira nota real por este perfil; emissao acompanhada, como a faixa do proprio perfil.',
      v_perfil.id
    )
    returning id into v_evidencia;
  else
    v_evidencia := v_perfil.evidencia_id;
    raise notice 'Perfil ja tinha evidencia %; mantida.', v_evidencia;
  end if;

  update f.perfil_operacao po
     set evidencia_id = v_evidencia,
         cbenef_aplicacao = 'COM_BENEFICIO',
         finalidade_emissao = 1,
         consumidor_final = 0
   where po.id = v_perfil.id;

  select * into v_perfil from f.perfil_operacao where id = v_perfil.id;
  if v_perfil.evidencia_id is null
     or v_perfil.cbenef_aplicacao <> 'COM_BENEFICIO'
     or v_perfil.finalidade_emissao is distinct from 1
     or v_perfil.consumidor_final is distinct from 0 then
    raise exception 'O perfil de automacao nao ficou configurado como esperado.';
  end if;
  raise notice 'Perfil de automacao com evidencia %, cBenef decidido e indFinal 0.', v_perfil.evidencia_id;
end
$configurar$;
