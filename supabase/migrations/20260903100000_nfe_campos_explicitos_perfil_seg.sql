begin;

-- cEnq vinha sendo criado pelo builder como 999 quando a solicitacao nao
-- possuia dado algum. A partir daqui ele faz parte da conferencia explicita.
alter table f.solicitacao_item
  add column ipi_codigo_enquadramento_legal text
    check (
      ipi_codigo_enquadramento_legal is null
      or ipi_codigo_enquadramento_legal ~ '^[0-9]{3}$'
    );

comment on column f.solicitacao_item.ipi_codigo_enquadramento_legal is
  'cEnq do IPI confirmado na solicitacao. Nunca recebe 999 por fallback.';

create or replace function f.fn_solicitacao_nfe_salvar_conferencia(
  p_solicitacao_id uuid,
  p_operacao jsonb,
  p_itens jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_item record;
  v_total_itens integer;
  v_usuario_id uuid := a.fn_current_usuario_id();
begin
  select * into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Rascunho de NF-e nao encontrado.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para conferir esta NF-e.';
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = 'Esta solicitacao nao pode mais ser alterada.';
  end if;

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.tenant_id = v_sf.tenant_id
    and dfe.empresa_id = v_sf.empresa_id
    and dfe.solicitacao_id = v_sf.id
  order by case when dfe.ambiente = 'PRODUCAO' then 0 else 1 end,
           dfe.created_at desc,
           dfe.documento_fiscal_id
  limit 1
  for update;

  if found and v_emissao.status not in ('REJEITADA', 'ERRO', 'RASCUNHO') then
    raise exception using errcode = '22023', message = 'Somente uma emissao rejeitada, com erro ou ainda em rascunho pode ser corrigida.';
  end if;
  if jsonb_typeof(p_operacao) <> 'object' or jsonb_typeof(p_itens) <> 'array' then
    raise exception using errcode = '22023', message = 'Operacao e itens da conferencia sao obrigatorios.';
  end if;
  if nullif(btrim(p_operacao->>'finalidade_emissao'), '') is null
     or nullif(btrim(p_operacao->>'consumidor_final'), '') is null
     or nullif(btrim(p_operacao->>'presenca_comprador'), '') is null
     or nullif(btrim(p_operacao->>'modalidade_frete'), '') is null
     or nullif(btrim(p_operacao->>'valor_frete'), '') is null
     or nullif(btrim(p_operacao->>'valor_seguro'), '') is null
     or nullif(btrim(p_operacao->>'valor_outras_despesas'), '') is null then
    raise exception using errcode = '22023', message = 'Finalidade, consumidor, presenca, frete, seguro e outras despesas devem ser confirmados explicitamente.';
  end if;

  select count(*) into v_total_itens
  from f.solicitacao_item si
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id;

  if v_total_itens = 0
     or jsonb_array_length(p_itens) <> v_total_itens
     or (select count(distinct x.id) from jsonb_to_recordset(p_itens) x(id uuid)) <> v_total_itens then
    raise exception using errcode = '22023', message = 'A conferencia deve conter todas as linhas da solicitacao, sem duplicidade.';
  end if;

  update f.solicitacao_faturamento
  set finalidade_emissao = nullif(p_operacao->>'finalidade_emissao', '')::smallint,
      consumidor_final = nullif(p_operacao->>'consumidor_final', '')::smallint,
      presenca_comprador = nullif(p_operacao->>'presenca_comprador', '')::smallint,
      modalidade_frete = nullif(p_operacao->>'modalidade_frete', '')::smallint,
      valor_frete = nullif(p_operacao->>'valor_frete', '')::numeric,
      valor_seguro = nullif(p_operacao->>'valor_seguro', '')::numeric,
      valor_outras_despesas = nullif(p_operacao->>'valor_outras_despesas', '')::numeric,
      revisao_fiscal_confirmada_em = case when v_usuario_id is null then null else now() end,
      revisao_fiscal_confirmada_por = v_usuario_id,
      emitente_snapshot = null,
      destinatario_snapshot = null,
      operacao_snapshot = null,
      snapshot_cadastro_em = null,
      status = 'PREVIA',
      updated_at = now()
  where id = v_sf.id;

  for v_item in
    select *
    from jsonb_to_recordset(p_itens) as x(
      id uuid,
      cfop text,
      cst_icms text,
      csosn text,
      cst_ipi text,
      ipi_codigo_enquadramento_legal text,
      cst_pis text,
      cst_cofins text,
      cbenef text,
      reducao_base_icms_percentual numeric,
      icms_modalidade_base_calculo text,
      aliquota_icms numeric,
      aliquota_ipi numeric,
      aliquota_pis numeric,
      aliquota_cofins numeric,
      cst_ibs_cbs text,
      cclass_trib text,
      cclass_trib_versao text,
      ibs_cbs_json jsonb
    )
  loop
    if nullif(btrim(v_item.ipi_codigo_enquadramento_legal), '') is null
       or v_item.reducao_base_icms_percentual is null then
      raise exception using errcode = '22023', message = 'cEnq do IPI e reducao da base de ICMS devem ser confirmados em cada item; informe zero quando nao houver reducao.';
    end if;
    if v_item.reducao_base_icms_percentual not between 0 and 100 then
      raise exception using errcode = '22023', message = 'Reducao da base de ICMS deve estar entre 0 e 100.';
    end if;
    if nullif(btrim(v_item.cst_ibs_cbs), '') is null
       or nullif(btrim(v_item.cclass_trib), '') is null
       or nullif(btrim(v_item.cclass_trib_versao), '') is null
       or jsonb_typeof(v_item.ibs_cbs_json) is distinct from 'object'
       or v_item.ibs_cbs_json->>'ibs_uf_aliquota' is null
       or v_item.ibs_cbs_json->>'ibs_mun_aliquota' is null
       or v_item.ibs_cbs_json->>'cbs_aliquota' is null then
      raise exception using errcode = '22023', message = 'CST, cClassTrib, versao e aliquotas de IBS/CBS sao obrigatorios em cada item.';
    end if;

    update f.solicitacao_item si
    set cfop = nullif(regexp_replace(coalesce(v_item.cfop, ''), '[^0-9]', '', 'g'), ''),
        cst_icms = nullif(btrim(v_item.cst_icms), ''),
        csosn = nullif(btrim(v_item.csosn), ''),
        cst_ipi = nullif(btrim(v_item.cst_ipi), ''),
        ipi_codigo_enquadramento_legal = nullif(regexp_replace(coalesce(v_item.ipi_codigo_enquadramento_legal, ''), '[^0-9]', '', 'g'), ''),
        cst_pis = nullif(btrim(v_item.cst_pis), ''),
        cst_cofins = nullif(btrim(v_item.cst_cofins), ''),
        cbenef = nullif(btrim(v_item.cbenef), ''),
        reducao_base_icms_percentual = v_item.reducao_base_icms_percentual,
        icms_modalidade_base_calculo = nullif(btrim(v_item.icms_modalidade_base_calculo), ''),
        aliquota_icms = v_item.aliquota_icms,
        aliquota_ipi = v_item.aliquota_ipi,
        aliquota_pis = v_item.aliquota_pis,
        aliquota_cofins = v_item.aliquota_cofins,
        cst_ibs_cbs = nullif(regexp_replace(coalesce(v_item.cst_ibs_cbs, ''), '[^0-9]', '', 'g'), ''),
        cclass_trib = nullif(regexp_replace(coalesce(v_item.cclass_trib, ''), '[^0-9]', '', 'g'), ''),
        cclass_trib_versao = nullif(btrim(v_item.cclass_trib_versao), ''),
        ibs_cbs_json = v_item.ibs_cbs_json
    where si.tenant_id = v_sf.tenant_id
      and si.empresa_id = v_sf.empresa_id
      and si.solicitacao_id = v_sf.id
      and si.id = v_item.id;

    if not found then
      raise exception using errcode = '22023', message = format('Item %s nao pertence a esta solicitacao.', v_item.id);
    end if;
  end loop;

  if v_emissao.documento_fiscal_id is not null then
    update f.documento_fiscal_emissao
    set status = 'RASCUNHO', codigo_status = null, mensagem = null, updated_at = now()
    where documento_fiscal_id = v_emissao.documento_fiscal_id;
  end if;

  return jsonb_build_object('ok', true, 'solicitacao_id', v_sf.id, 'itens', v_total_itens);
end;
$function$;

comment on function f.fn_solicitacao_nfe_salvar_conferencia(uuid, jsonb, jsonb) is
  'Salva somente dados explicitamente confirmados; nao cria defaults fiscais de IPI, ICMS ou IBS/CBS.';

revoke all on function f.fn_solicitacao_nfe_salvar_conferencia(uuid, jsonb, jsonb) from public, anon;
grant execute on function f.fn_solicitacao_nfe_salvar_conferencia(uuid, jsonb, jsonb) to authenticated, service_role;

-- A evidencia preserva exatamente o que foi autorizado: a NF-e saiu com
-- origem 1. O perfil usa origem 2 por decisao posterior, registrada como
-- inferencia no cadastro do item; essa divergencia fica explicita no texto.
insert into f.perfil_operacao_evidencia (
  id, tenant_id, empresa_id, fonte, fonte_linha, natureza_texto, cfop,
  origem, cst_completo, cst_icms, aliquota_icms_observada,
  aliquota_ipi_observada, base_reduzida_observada, itens_observados,
  notas_observadas, ncms, notas_exemplo, leitura_operacional, faixa,
  justificativa_faixa, divergencia_ipi, divergencia_fabricado_revenda,
  divergencia_cabo_beneficio, xml_notas, xml_itens, xml_pis_csts,
  xml_cofins_csts, xml_pis_aliquotas, xml_cofins_aliquotas,
  xml_ipi_csts, xml_cbenef_valores, xml_cbenef_ausente_itens,
  xml_fci_itens, xml_divergente, xml_extraido_em
)
select
  'a999d56c-67eb-4a56-8dd7-44ba4d76bcbf',
  '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7',
  'f0e74f49-a127-46b4-901b-f7b37e43c690',
  'NF-E HOMOLOGACAO 42260913671448000189550020000000011615133155',
  1,
  'VENDA_MERCADORIA_TERCEIROS',
  '5102', 1, '100', '00', 12, 0, false, 1, 1,
  array['85371020']::text[], array[1]::integer[],
  'NF-e 55 serie 2 numero 1, autorizada em homologacao em 02/09/2026, protocolo 342260000892595. A nota prova CFOP 5102, CST 00, ICMS 12%, IPI 53, PIS/COFINS 01 e a chave informada. Ela saiu com origem 1. A origem 2 do perfil foi definida depois, por inferencia documentada no cadastro do item, e nao deve ser atribuida retroativamente ao XML. Os dados IBS/CBS dessa nota vieram de defaults removidos e nao sao evidencia fiscal para o perfil.',
  'REVISAO',
  'Uma unica NF-e de homologacao; origem do perfil diverge da nota e IBS/CBS ainda exigem confirmacao fiscal explicita.',
  false, false, false, 1, 1,
  array['01']::text[], array['01']::text[], array[1.65]::numeric[],
  array[7.6]::numeric[], array['53']::text[], '{}'::text[], 1, 0,
  false, '2026-09-02 21:56:11.955359+00'::timestamptz
where exists (
  select 1
  from c.empresa e
  where e.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
    and e.id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
)
on conflict (tenant_id, empresa_id, fonte, fonte_linha) do update
set natureza_texto = excluded.natureza_texto,
    cfop = excluded.cfop,
    origem = excluded.origem,
    cst_completo = excluded.cst_completo,
    cst_icms = excluded.cst_icms,
    aliquota_icms_observada = excluded.aliquota_icms_observada,
    aliquota_ipi_observada = excluded.aliquota_ipi_observada,
    itens_observados = excluded.itens_observados,
    notas_observadas = excluded.notas_observadas,
    ncms = excluded.ncms,
    notas_exemplo = excluded.notas_exemplo,
    leitura_operacional = excluded.leitura_operacional,
    faixa = excluded.faixa,
    justificativa_faixa = excluded.justificativa_faixa,
    xml_notas = excluded.xml_notas,
    xml_itens = excluded.xml_itens,
    xml_pis_csts = excluded.xml_pis_csts,
    xml_cofins_csts = excluded.xml_cofins_csts,
    xml_pis_aliquotas = excluded.xml_pis_aliquotas,
    xml_cofins_aliquotas = excluded.xml_cofins_aliquotas,
    xml_ipi_csts = excluded.xml_ipi_csts,
    xml_cbenef_ausente_itens = excluded.xml_cbenef_ausente_itens,
    xml_extraido_em = excluded.xml_extraido_em;

insert into f.perfil_operacao (
  id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao,
  natureza_texto, crt, cfop_interno, cfop_externo, cst_icms, csosn,
  cst_ipi, cst_pis, cst_cofins, cbenef, reducao_base_icms_percentual,
  beneficio_texto_legal, cst_ibs_cbs, cclass_trib, cclass_trib_versao,
  exige_referencia, exige_motivo, observacao, vigencia_inicio,
  evidencia_id, faixa_automacao, justificativa_faixa, origem_mercadoria,
  aliquota_icms, aliquota_ipi, aliquota_pis, aliquota_cofins,
  percentual_base_calculo, informacoes_complementares_modelo,
  habilitado_producao
)
select
  'bb34e0ad-e77b-458c-b8eb-7141ac5204dd',
  '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7',
  'f0e74f49-a127-46b4-901b-f7b37e43c690',
  'SEG-VENDA-TERCEIROS-SC-5102-O2-CST00',
  'SEG - venda de mercadoria de terceiros em SC - CFOP 5102 - origem 2 - CST 00',
  'NFE', 'VENDA_MERCADORIA_TERCEIROS',
  'VENDA DE MERCADORIA ADQUIRIDA OU RECEBIDA DE TERCEIROS',
  '3', '5102', null, '00', null, '53', '01', '01', null, null,
  null, null, null, null, false, false,
  'Perfil criado a partir da NF-e de homologacao 42260913671448000189550020000000011615133155. IBS/CBS nao foi copiado porque esses valores eram defaults silenciosos. A origem 2 foi inferida depois da autorizacao e esta registrada na evidencia.',
  '2026-09-03',
  (
    select ev.id
    from f.perfil_operacao_evidencia ev
    where ev.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
      and ev.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
      and ev.fonte = 'NF-E HOMOLOGACAO 42260913671448000189550020000000011615133155'
      and ev.fonte_linha = 1
  ),
  'REVISAO',
  'Exige confirmacao humana; uma unica nota de homologacao, origem corrigida depois e IBS/CBS ainda sem confirmacao.',
  2, 12, null, 1.65, 7.6, null, null, false
where exists (
  select 1
  from c.empresa e
  where e.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
    and e.id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
)
on conflict (tenant_id, empresa_id, codigo, vigencia_inicio) do update
set nome = excluded.nome,
    modelo = excluded.modelo,
    natureza_operacao = excluded.natureza_operacao,
    natureza_texto = excluded.natureza_texto,
    crt = excluded.crt,
    cfop_interno = excluded.cfop_interno,
    cfop_externo = excluded.cfop_externo,
    cst_icms = excluded.cst_icms,
    csosn = excluded.csosn,
    cst_ipi = excluded.cst_ipi,
    cst_pis = excluded.cst_pis,
    cst_cofins = excluded.cst_cofins,
    cbenef = excluded.cbenef,
    reducao_base_icms_percentual = excluded.reducao_base_icms_percentual,
    beneficio_texto_legal = excluded.beneficio_texto_legal,
    cst_ibs_cbs = excluded.cst_ibs_cbs,
    cclass_trib = excluded.cclass_trib,
    cclass_trib_versao = excluded.cclass_trib_versao,
    observacao = excluded.observacao,
    evidencia_id = excluded.evidencia_id,
    faixa_automacao = excluded.faixa_automacao,
    justificativa_faixa = excluded.justificativa_faixa,
    origem_mercadoria = excluded.origem_mercadoria,
    aliquota_icms = excluded.aliquota_icms,
    aliquota_ipi = excluded.aliquota_ipi,
    aliquota_pis = excluded.aliquota_pis,
    aliquota_cofins = excluded.aliquota_cofins,
    habilitado_producao = false;

update f.perfil_operacao_evidencia ev
set perfil_operacao_id = po.id
from f.perfil_operacao po
where ev.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and ev.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
  and ev.fonte = 'NF-E HOMOLOGACAO 42260913671448000189550020000000011615133155'
  and ev.fonte_linha = 1
  and po.tenant_id = ev.tenant_id
  and po.empresa_id = ev.empresa_id
  and po.codigo = 'SEG-VENDA-TERCEIROS-SC-5102-O2-CST00'
  and po.vigencia_inicio = '2026-09-03';

commit;
