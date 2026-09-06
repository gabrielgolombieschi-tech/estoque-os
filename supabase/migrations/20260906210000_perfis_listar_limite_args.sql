-- Correcao da 20260906200000: jsonb_build_object tem limite de 100 argumentos no
-- Postgres (50 pares). Com os campos de servico o objeto do perfil passou do limite
-- e a tela quebrava com "cannot pass more than 100 arguments to a function".
-- O objeto passa a ser montado em duas partes concatenadas.
-- Baseline: f.fn_perfil_operacao_nfe_listar (20260906200000).

CREATE OR REPLACE FUNCTION f.fn_perfil_operacao_nfe_listar()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_scope record;
  v_perfis jsonb;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();

  select coalesce(
    jsonb_agg(x.perfil order by x.codigo, x.vigencia_inicio desc),
    '[]'::jsonb
  )
    into v_perfis
  from (
    select
      po.codigo,
      po.vigencia_inicio,
      jsonb_build_object(
        'id', po.id,
        'codigo', po.codigo,
        'nome', po.nome,
        'modelo', po.modelo,
        'natureza_operacao', po.natureza_operacao,
        'natureza_texto', po.natureza_texto,
        'crt', po.crt,
        'cfop_interno', po.cfop_interno,
        'cfop_externo', po.cfop_externo,
        'cst_icms', po.cst_icms,
        'csosn', po.csosn,
        'origem_mercadoria', po.origem_mercadoria,
        'icms_modalidade_base_calculo', po.icms_modalidade_base_calculo,
        'aliquota_icms', po.aliquota_icms,
        'reducao_base_icms_percentual', po.reducao_base_icms_percentual,
        'cbenef', po.cbenef,
        'cbenef_aplicacao', po.cbenef_aplicacao,
        'cst_pis', po.cst_pis,
        'aliquota_pis', po.aliquota_pis,
        'cst_cofins', po.cst_cofins,
        'aliquota_cofins', po.aliquota_cofins,
        'ambito_destino', po.ambito_destino,
        'ufs_destino', po.ufs_destino,
        'indicador_ie_destinatario', po.indicador_ie_destinatario,
        'finalidade_emissao', po.finalidade_emissao,
        'consumidor_final', po.consumidor_final,
        'faixa_automacao', po.faixa_automacao,
        'justificativa_faixa', po.justificativa_faixa,
        'evidencia_id', po.evidencia_id,
        'vigencia_inicio', po.vigencia_inicio,
        'vigencia_fim', po.vigencia_fim,
        'vigente', (
          po.vigencia_inicio <= current_date
          and (po.vigencia_fim is null or po.vigencia_fim >= current_date)
        ),
        'cst_ibs_cbs', po.cst_ibs_cbs,
        'cclass_trib', po.cclass_trib,
        'cclass_trib_versao', po.cclass_trib_versao,
        'ibs_uf_aliquota', po.ibs_cbs_json->'ibs_uf_aliquota',
        'ibs_mun_aliquota', po.ibs_cbs_json->'ibs_mun_aliquota',
        'cbs_aliquota', po.ibs_cbs_json->'cbs_aliquota',
        'habilitado_producao', po.habilitado_producao,
        'revisao_fiscal_em', po.revisao_fiscal_em,
        'revisao_fiscal_por', po.revisao_fiscal_por,
        'revisao_fiscal_justificativa', po.revisao_fiscal_justificativa,
        'producao_decidida_em', po.producao_decidida_em,
        'producao_decidida_por', po.producao_decidida_por
      ) || jsonb_build_object(
        'producao_decisao_justificativa', po.producao_decisao_justificativa,
        'producao_homologacao_solicitacao_id', po.producao_homologacao_solicitacao_id,
        'producao_homologacao_documento_id', po.producao_homologacao_documento_id,
        'item_servico', po.item_servico,
        'codigo_tributacao_nacional', po.codigo_tributacao_nacional,
        'codigo_nbs', po.codigo_nbs,
        'descricao_servico_padrao', po.descricao_servico_padrao,
        'local_prestacao_regra', po.local_prestacao_regra,
        'incidencia_iss_regra', po.incidencia_iss_regra,
        'tributacao_iss', po.tributacao_iss,
        'aliquota_iss', po.aliquota_iss,
        'iss_retido_regra', po.iss_retido_regra,
        'retencao_pcc_regra', po.retencao_pcc_regra,
        'aliquota_pcc', po.aliquota_pcc,
        'retencao_irrf_regra', po.retencao_irrf_regra,
        'aliquota_irrf', po.aliquota_irrf,
        'retencao_inss_regra', po.retencao_inss_regra,
        'aliquota_inss', po.aliquota_inss,
        'permite_deducao_material', po.permite_deducao_material,
        'excecao_conserto_isolado', po.excecao_conserto_isolado,
        'codigo_indicador_operacao', po.codigo_indicador_operacao,
        'tributos_aprox_federal_pct', po.tributos_aprox_federal_pct,
        'tributos_aprox_municipal_pct', po.tributos_aprox_municipal_pct,
        'campos_conferir', po.campos_conferir,
        'texto_complementar', po.texto_complementar,
        'texto_sem_retencao', po.texto_sem_retencao
      ) as perfil
    from f.perfil_operacao po
    where po.tenant_id = v_scope.tenant_id
      and po.empresa_id = v_scope.empresa_id
      and po.modelo in ('NFE', 'NFSE')
  ) x;

  return jsonb_build_object(
    'tenant_id', v_scope.tenant_id,
    'empresa_id', v_scope.empresa_id,
    'perfis', v_perfis
  );
end;
$function$;
