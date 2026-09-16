-- Remessa para conserto emitida pelo ERP (CFOP 5915 / 6915).
--
-- Pedido do Gabriel em 16/09/2026: mandar duas cortinas de luz SICK para analise em
-- garantia, em Sao Bernardo do Campo/SP, com NF-e de remessa para conserto (o e-mail da
-- SICK pede "remessa para conserto CFOP 5915 ou 6915", sem impostos destacados). Ate hoje a
-- tela /faturamento/operacoes so registrava a remessa e pedia a chave digitada: nada era
-- transmitido, e f.operacao_fiscal so aceitava HOMOLOGACAO. O emissor de NF-e (solicitacao
-- -> conferencia -> homologacao -> liberacao do perfil -> producao) era so de venda.
--
-- O que muda:
--   1. f.operacao_fiscal aceita PRODUCAO e aponta para a solicitacao de NF-e que a emite.
--   2. Perfis SEG-REMESSA-CONSERTO-6915-O2-CST50 e -5915-O2-CST50 (origem 2), com a
--      tributacao da Status Contabilidade (docs/faturamento/regras-icms-sc-contabilidade.md):
--      ICMS CST 50 + cBenef SC840007 (RICMS/SC-01, Anexo 2, Art. 27, I), IPI CST 55 cEnq 108
--      (RIPI/10, art. 43, VI), PIS/COFINS 08. IBS/CBS fica para a revisao na tela de perfis
--      (CST 410 / cClassTrib 410999, o que as remessas de terceiros trazem em 2026).
--   3. f.fn_remessa_nfe_criar: cria a operacao, a solicitacao de NF-e com a tributacao do
--      perfil, o transporte e congela o cadastro. Dali em diante e o pipeline de sempre
--      (nfe-emitir, liberacao do perfil, nfe-emitir-producao).
--   4. Autorizacao: gatilho em f.documento_fiscal_emissao liga a nota a operacao; em producao
--      abre f.remessa_controle (prazo de retorno) — o que antes dependia de digitar a chave.
--   5. Congelar cadastro nao exige destinacao em remessa; contas a receber ignora remessa.
--
-- O montador da nota (supabase/functions/_shared/fiscal/remessa-conserto.ts) confere que cada
-- item saiu com essa tributacao, poe os textos legais no infCpl e manda tPag 90 (sem pagamento).

-- ---------------------------------------------------------------------------
-- 1. Operacao fiscal: producao permitida, vinculo com a solicitacao de NF-e
-- ---------------------------------------------------------------------------
alter table f.operacao_fiscal drop constraint if exists operacao_fiscal_ambiente_check;
alter table f.operacao_fiscal
  add constraint operacao_fiscal_ambiente_check check (ambiente in ('HOMOLOGACAO', 'PRODUCAO'));
alter table f.operacao_fiscal add column if not exists solicitacao_id uuid;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'operacao_fiscal_solicitacao_fk') then
    alter table f.operacao_fiscal
      add constraint operacao_fiscal_solicitacao_fk
      foreign key (tenant_id, empresa_id, solicitacao_id)
      references f.solicitacao_faturamento(tenant_id, empresa_id, id) on delete set null;
  end if;
end $$;
create unique index if not exists operacao_fiscal_solicitacao_uk
  on f.operacao_fiscal (solicitacao_id) where solicitacao_id is not null;
comment on column f.operacao_fiscal.solicitacao_id is
  'Solicitacao de NF-e que emite esta operacao pelo pipeline fiscal (remessa para conserto desde 16/09/2026).';

-- ---------------------------------------------------------------------------
-- 2. Perfis de remessa para conserto (origem 2) e a evidencia deles
-- ---------------------------------------------------------------------------
insert into f.perfil_operacao_evidencia (
  id, tenant_id, empresa_id, fonte, fonte_linha, natureza_texto, cfop, origem, cst_completo, cst_icms,
  aliquota_icms_observada, aliquota_ipi_observada, base_reduzida_observada, itens_observados,
  notas_observadas, ncms, notas_exemplo, leitura_operacional, faixa, justificativa_faixa,
  divergencia_ipi, divergencia_fabricado_revenda, divergencia_cabo_beneficio,
  xml_notas, xml_itens, xml_pis_csts, xml_cofins_csts, xml_pis_aliquotas, xml_cofins_aliquotas,
  xml_ipi_csts, xml_cbenef_valores, xml_cbenef_ausente_itens, xml_fci_itens, xml_divergente
)
select
  v.id, '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7', 'f0e74f49-a127-46b4-901b-f7b37e43c690',
  'NF-e 3539 serie 1 (VertexERP, 28/01/2026, remessa das cortinas SICK) + XMLs de remessa de terceiros em 2026 (WEG 878640 CFOP 5901, Keyence 4260 CFOP 6916) + regras da Status Contabilidade',
  v.linha, v.natureza, v.cfop, 2, '250', '50', 0, 0, false, 2, 1,
  array['85365090']::text[], array[3539]::integer[],
  'Remessa para conserto (garantia) de mercadoria de terceiros. A NF 3539 saiu do emissor antigo com CST 050, sem ICMS, IPI, PIS e COFINS, citando RICMS/2000 art. 7 IX e RIPI art. 5 XI. '
    || 'A parametrizacao segue a contabilidade: ICMS 50 com cBenef SC840007 (Anexo 2, Art. 27, I) e IPI 55 (RIPI art. 43, VI); PIS/COFINS 08 e IBS/CBS 410/410999 sao o que as remessas de terceiros trazem em 2026. '
    || 'Origem 2 porque as cortinas sao importadas pela SICK e revendidas pela SEGAU.',
  'REVISAO',
  'Primeira remessa emitida pelo ERP: homologar antes de liberar producao.',
  false, false, false,
  0, 0, '{}'::text[], '{}'::text[], '{}'::numeric[], '{}'::numeric[], '{}'::text[], '{}'::text[], 0, 0, false
from (values
  ('4c0a5e1e-9f0b-4c7a-9b2e-6915a0000001'::uuid, 6915, 'REMESSA_CONSERTO_INTERESTADUAL', '6915'),
  ('4c0a5e1e-9f0b-4c7a-9b2e-5915a0000001'::uuid, 5915, 'REMESSA_CONSERTO_INTERNA', '5915')
) as v(id, linha, natureza, cfop)
where exists (
  select 1 from c.empresa e
  where e.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7' and e.id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
)
on conflict (tenant_id, empresa_id, fonte, fonte_linha) do nothing;

insert into f.perfil_operacao (
  id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto, crt,
  cfop_interno, cfop_externo, cst_icms, csosn, aliquota_icms, icms_modalidade_base_calculo,
  cbenef, cbenef_aplicacao, beneficio_texto_legal, reducao_base_icms_percentual,
  cst_ipi, ipi_codigo_enquadramento_legal, aliquota_ipi, cst_pis, cst_cofins, aliquota_pis, aliquota_cofins,
  finalidade_emissao, consumidor_final, ambito_destino, ufs_destino, indicador_ie_destinatario, origem_mercadoria,
  exige_referencia, exige_motivo, observacao, informacoes_complementares_modelo, vigencia_inicio,
  evidencia_id, faixa_automacao, justificativa_faixa, habilitado_producao
)
select
  v.id, '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7', 'f0e74f49-a127-46b4-901b-f7b37e43c690',
  v.codigo, v.nome, 'NFE', v.natureza, v.natureza_texto, '3',
  v.cfop_interno, v.cfop_externo, '50', null, 0, null,
  'SC840007', 'COM_BENEFICIO',
  'ICMS suspenso, conforme o inciso I do art. 27 do Anexo 2 do Decreto nº 2.870/01 - RICMS-SC/01 (cBenef SC840007)',
  null,
  '55', '108', null, '08', '08', null, null,
  1, 0, v.ambito, v.ufs, '1', 2,
  false, false,
  'Remessa para conserto ou analise em garantia de mercadoria de terceiros (origem 2). Tributacao da Status Contabilidade (docs/faturamento/regras-icms-sc-contabilidade.md); IBS/CBS 410/410999 conforme as remessas de terceiros de 2026. Retorno em 180 dias (Anexo 2, Art. 27, I).',
  'IPI suspenso, conforme o inciso VI do art. 43 do Decreto nº 7.212/10 - RIPI/10',
  '2026-09-16',
  v.evidencia_id, 'REVISAO', 'Primeira remessa emitida pelo ERP: homologar antes de liberar producao.', false
from (values
  (
    'a6e1c3d2-6915-4c50-9a2b-000000000001'::uuid, 'SEG-REMESSA-CONSERTO-6915-O2-CST50',
    'SEG - remessa para conserto fora do estado - CFOP 6915 - origem 2 - CST 50',
    'REMESSA_CONSERTO_INTERESTADUAL', 'REMESSA PARA CONSERTO FORA DO ESTADO',
    null, '6915', 'INTERESTADUAL',
    array['AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SP','SE','TO']::text[],
    '4c0a5e1e-9f0b-4c7a-9b2e-6915a0000001'::uuid
  ),
  (
    'a6e1c3d2-5915-4c50-9a2b-000000000001'::uuid, 'SEG-REMESSA-CONSERTO-5915-O2-CST50',
    'SEG - remessa para conserto dentro do estado - CFOP 5915 - origem 2 - CST 50',
    'REMESSA_CONSERTO_INTERNA', 'REMESSA PARA CONSERTO DENTRO DO ESTADO',
    '5915', null, 'INTERNA', array['SC']::text[],
    '4c0a5e1e-9f0b-4c7a-9b2e-5915a0000001'::uuid
  )
) as v(id, codigo, nome, natureza, natureza_texto, cfop_interno, cfop_externo, ambito, ufs, evidencia_id)
where exists (
  select 1 from f.perfil_operacao_evidencia ev where ev.id = v.evidencia_id
)
on conflict (tenant_id, empresa_id, codigo, vigencia_inicio) do nothing;

update f.perfil_operacao_evidencia ev
   set perfil_operacao_id = po.id
  from f.perfil_operacao po
 where po.evidencia_id = ev.id
   and po.codigo like 'SEG-REMESSA-CONSERTO-%'
   and ev.perfil_operacao_id is null;

-- ---------------------------------------------------------------------------
-- 3. Criar a remessa e a solicitacao de NF-e dela
-- ---------------------------------------------------------------------------
create or replace function f.fn_remessa_nfe_criar(p_cliente_id integer, p_itens jsonb, p_operacao jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_scope record;
  v_cliente public.clientes%rowtype;
  v_uf_emitente text;
  v_uf_destino text;
  v_ambito text;
  v_cfop text;
  v_natureza text;
  v_perfil f.perfil_operacao%rowtype;
  v_perfil_unico uuid;
  v_perfil_misto boolean := false;
  v_item jsonb;
  v_ordem integer := 0;
  v_it public.itens%rowtype;
  v_fi public.fiscal_itens%rowtype;
  v_qtd numeric;
  v_valor numeric;
  v_op_id uuid := gen_random_uuid();
  v_sol_id uuid := gen_random_uuid();
  v_total numeric(14,2) := 0;
  v_modalidade smallint;
  v_presenca smallint;
  v_observacao text;
  v_congelado jsonb;
  v_pendencias text;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();

  if p_cliente_id is null then
    raise exception using errcode = '22023', message = 'Escolha o destinatario da remessa no cadastro de clientes.';
  end if;
  select c.* into v_cliente
  from public.clientes c
  where c.tenant_id = v_scope.tenant_id and c.empresa_id = v_scope.empresa_id and c.id = p_cliente_id and c.ativo;
  if not found then
    raise exception using errcode = 'P0002', message = 'Destinatario nao encontrado (ou inativo) nesta empresa.';
  end if;
  v_uf_destino := upper(btrim(coalesce(v_cliente.uf, '')));
  if v_uf_destino !~ '^[A-Z]{2}$' then
    raise exception using errcode = '22023', message = format('%s esta sem UF no cadastro fiscal do cliente.', coalesce(v_cliente.razao_social, v_cliente.nome));
  end if;
  if coalesce(v_cliente.indicador_ie, '') not in ('1', '2', '9') then
    raise exception using errcode = '22023', message = format('Confirme o indicador de IE de %s no cadastro fiscal do cliente.', coalesce(v_cliente.razao_social, v_cliente.nome));
  end if;

  select upper(ee.uf::text) into v_uf_emitente
  from c.empresa_endereco ee
  where ee.empresa_id = v_scope.empresa_id and ee.tipo = 'FISCAL' and ee.deleted_at is null
  order by ee.created_at limit 1;
  if v_uf_emitente is null then
    raise exception using errcode = '22023', message = 'A UF fiscal do emitente nao esta cadastrada.';
  end if;
  v_ambito := case when v_uf_destino = v_uf_emitente then 'INTERNA' else 'INTERESTADUAL' end;
  v_cfop := case v_ambito when 'INTERNA' then '5915' else '6915' end;
  v_natureza := case v_ambito when 'INTERNA' then 'REMESSA_CONSERTO_INTERNA' else 'REMESSA_CONSERTO_INTERESTADUAL' end;

  if jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception using errcode = '22023', message = 'A remessa exige ao menos um item do catalogo.';
  end if;
  if jsonb_typeof(p_operacao) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'Informe frete, transporte e presenca da remessa.';
  end if;
  v_modalidade := coalesce(nullif(btrim(p_operacao->>'modalidade_frete'), '')::smallint, 9);
  if v_modalidade not in (0, 1, 2, 3, 4, 9) then
    raise exception using errcode = '22023', message = 'Modalidade do frete invalida.';
  end if;
  v_presenca := coalesce(nullif(btrim(p_operacao->>'presenca_comprador'), '')::smallint, 9);
  if v_presenca not in (1, 2, 3, 4, 5, 9) then
    raise exception using errcode = '22023', message = 'Presenca do comprador deve ser 1 a 5 ou 9.';
  end if;
  v_observacao := nullif(btrim(coalesce(p_operacao->>'observacao', '')), '');

  insert into f.operacao_fiscal (
    id, tenant_id, empresa_id, tipo, finalidade, status, ambiente,
    cfop_proposto, cfop_confirmado, cfop_confirmado_em, cfop_confirmado_por,
    destinatario_id, entrega_json, justificativa_fisco, criado_por, preparado_homologacao_em, dados_json
  ) values (
    v_op_id, v_scope.tenant_id, v_scope.empresa_id, 'REMESSA', 'CONSERTO', 'PRONTO_HOMOLOGACAO', 'HOMOLOGACAO',
    v_cfop, v_cfop, now(), v_scope.usuario_id,
    v_cliente.id,
    jsonb_build_object(
      'cliente_id', v_cliente.id,
      'documento', regexp_replace(coalesce(v_cliente.documento, ''), '\D', '', 'g'),
      'nome', coalesce(nullif(btrim(v_cliente.razao_social), ''), v_cliente.nome),
      'uf', v_uf_destino
    ),
    v_observacao, v_scope.usuario_id, now(),
    jsonb_build_object('natureza_operacao', v_natureza, 'ambito', v_ambito, 'operacao', p_operacao - 'observacao')
  );

  insert into f.solicitacao_faturamento (
    id, tenant_id, empresa_id, cliente_id, status, natureza_operacao, observacao, criado_por,
    finalidade_emissao, consumidor_final, presenca_comprador, modalidade_frete,
    valor_frete, valor_seguro, valor_outras_despesas,
    destino_uf_confirmada, destino_confirmado_em, destino_confirmado_por,
    pagamento_forma, pagamento_indicador, pagamento_parcelas,
    revisao_fiscal_confirmada_em, revisao_fiscal_confirmada_por
  ) values (
    v_sol_id, v_scope.tenant_id, v_scope.empresa_id, v_cliente.id, 'PREVIA', v_natureza, v_observacao, v_scope.usuario_id,
    1, 0, v_presenca, v_modalidade,
    0, 0, 0,
    v_uf_destino, now(), v_scope.usuario_id,
    '90', 0, null,
    now(), v_scope.usuario_id
  );

  for v_item in select value from jsonb_array_elements(p_itens) loop
    v_ordem := v_ordem + 1;
    select i.* into v_it
    from public.itens i
    where i.tenant_id = v_scope.tenant_id and i.empresa_id = v_scope.empresa_id
      and i.id = nullif(btrim(v_item->>'item_id'), '')::integer and i.ativo;
    if not found then
      raise exception using errcode = '22023', message = format('Linha %s: item nao encontrado no catalogo desta empresa.', v_ordem);
    end if;
    select fi.* into v_fi
    from public.fiscal_itens fi
    where fi.tenant_id = v_scope.tenant_id and fi.empresa_id = v_scope.empresa_id and fi.item_id = v_it.id;
    if not found or regexp_replace(coalesce(v_fi.ncm, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then
      raise exception using errcode = '22023', message = format('Linha %s: %s sem NCM no cadastro fiscal (Cadastros > Itens, aba Fiscal).', v_ordem, v_it.codigo_interno);
    end if;
    if v_fi.origem is null then
      raise exception using errcode = '22023', message = format('Linha %s: %s sem origem da mercadoria no cadastro fiscal (Cadastros > Itens, aba Fiscal).', v_ordem, v_it.codigo_interno);
    end if;
    v_qtd := nullif(btrim(v_item->>'quantidade'), '')::numeric;
    v_valor := nullif(btrim(v_item->>'valor_unitario'), '')::numeric;
    if v_qtd is null or v_qtd <= 0 then
      raise exception using errcode = '22023', message = format('Linha %s: quantidade deve ser maior que zero.', v_ordem);
    end if;
    if v_valor is null or v_valor <= 0 then
      raise exception using errcode = '22023', message = format('Linha %s: informe o valor unitario da mercadoria (valor de compra).', v_ordem);
    end if;

    -- O perfil e por origem do item: sem ele nao ha tributacao para a linha.
    select po.* into v_perfil
    from f.perfil_operacao po
    where po.tenant_id = v_scope.tenant_id
      and (po.empresa_id = v_scope.empresa_id or po.empresa_id is null)
      and po.modelo = 'NFE'
      and po.natureza_operacao = v_natureza
      and po.ambito_destino = v_ambito
      and po.ufs_destino is not null and v_uf_destino = any(po.ufs_destino)
      and po.origem_mercadoria = v_fi.origem
      and (po.indicador_ie_destinatario is null or po.indicador_ie_destinatario = v_cliente.indicador_ie)
      and po.faixa_automacao <> 'BLOQUEADO'
      and po.vigencia_inicio <= current_date and (po.vigencia_fim is null or po.vigencia_fim >= current_date)
    order by po.habilitado_producao desc, po.revisao_fiscal_em desc nulls last
    limit 1;
    if not found then
      raise exception using errcode = '22023', message = format(
        'Linha %s: nenhum perfil fiscal de remessa para conserto para %s, origem %s, indicador IE %s. Cadastre ou ajuste o perfil em Faturamento > Perfis fiscais.',
        v_ordem, v_ambito, v_fi.origem, v_cliente.indicador_ie);
    end if;
    if v_perfil.revisao_fiscal_em is null or v_perfil.cst_ibs_cbs is null or v_perfil.cclass_trib is null
       or f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_uf_aliquota') is null
       or f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_mun_aliquota') is null
       or f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'cbs_aliquota') is null then
      raise exception using errcode = '22023', message = format(
        'O perfil %s ainda nao foi revisado (IBS/CBS). Revise em Faturamento > Perfis fiscais antes de criar a remessa.', v_perfil.codigo);
    end if;
    if v_perfil_unico is null then v_perfil_unico := v_perfil.id;
    elsif v_perfil_unico <> v_perfil.id then v_perfil_misto := true;
    end if;

    insert into f.operacao_fiscal_item (
      operacao_id, tenant_id, empresa_id, ordem, item_id, codigo, descricao, ncm, unidade,
      quantidade_original, quantidade, valor_unitario, valor_total, cfop_proposto, cfop_confirmado,
      origem_mercadoria, cst_icms, cst_ipi, cst_pis, cst_cofins, cbenef, reducao_base_icms_percentual,
      unidade_tributavel, cst_ibs_cbs, cclass_trib, cclass_trib_versao, ibs_cbs_json, xml_validado
    ) values (
      v_op_id, v_scope.tenant_id, v_scope.empresa_id, v_ordem, v_it.id, v_it.codigo_interno, v_it.nome,
      regexp_replace(v_fi.ncm, '[^0-9]', '', 'g'), coalesce(nullif(btrim(v_it.unidade_medida), ''), 'UN'),
      v_qtd, v_qtd, v_valor, round(v_qtd * v_valor, 2), v_cfop, v_cfop,
      v_fi.origem, v_perfil.cst_icms, v_perfil.cst_ipi, v_perfil.cst_pis, v_perfil.cst_cofins,
      case when v_perfil.cbenef_aplicacao = 'COM_BENEFICIO' then v_perfil.cbenef end, 0,
      coalesce(nullif(btrim(v_fi.unidade_tributavel), ''), nullif(btrim(v_it.unidade_medida), ''), 'UN'),
      v_perfil.cst_ibs_cbs, v_perfil.cclass_trib, v_perfil.cclass_trib_versao, v_perfil.ibs_cbs_json, false
    );

    insert into f.solicitacao_item (
      id, solicitacao_id, tenant_id, empresa_id, origem_tipo, origem_id, item_id, descricao, ncm, cfop,
      cst_icms, csosn, cst_ipi, cst_pis, cst_cofins, cbenef, reducao_base_icms_percentual,
      cst_ibs_cbs, cclass_trib, cclass_trib_versao, ibs_cbs_json,
      quantidade, unidade, valor_unitario, ordem, codigo_produto, cest, origem_mercadoria, unidade_tributavel,
      valor_desconto, icms_modalidade_base_calculo, aliquota_icms, aliquota_ipi, aliquota_pis, aliquota_cofins,
      ipi_codigo_enquadramento_legal, perfil_operacao_id, perfil_aplicado_em, perfil_aplicado_por,
      numero_fci, ipi_fonte, tributacao_fonte, modelo
    ) values (
      gen_random_uuid(), v_sol_id, v_scope.tenant_id, v_scope.empresa_id, 'AVULSO', v_op_id::text, v_it.id, v_it.nome,
      regexp_replace(v_fi.ncm, '[^0-9]', '', 'g'), v_cfop,
      v_perfil.cst_icms, null, v_perfil.cst_ipi, v_perfil.cst_pis, v_perfil.cst_cofins,
      case when v_perfil.cbenef_aplicacao = 'COM_BENEFICIO' then v_perfil.cbenef end, 0,
      v_perfil.cst_ibs_cbs, v_perfil.cclass_trib, v_perfil.cclass_trib_versao,
      jsonb_build_object(
        'ibs_uf_aliquota', f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_uf_aliquota'),
        'ibs_mun_aliquota', f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'ibs_mun_aliquota'),
        'cbs_aliquota', f.fn_perfil_operacao_jsonb_numeric_seguro(v_perfil.ibs_cbs_json, 'cbs_aliquota')
      ),
      v_qtd, coalesce(nullif(btrim(v_it.unidade_medida), ''), 'UN'), v_valor, v_ordem,
      coalesce(nullif(btrim(v_it.codigo_interno), ''), v_it.id::text),
      nullif(regexp_replace(coalesce(v_fi.cest, ''), '[^0-9]', '', 'g'), ''), v_fi.origem,
      coalesce(nullif(btrim(v_fi.unidade_tributavel), ''), nullif(btrim(v_it.unidade_medida), ''), 'UN'),
      0, null, null, null, null, null,
      v_perfil.ipi_codigo_enquadramento_legal, v_perfil.id, now(), v_scope.usuario_id,
      v_fi.numero_fci, 'PERFIL_OPERACAO', 'PERFIL', 'NFE'
    );
    v_total := v_total + round(v_qtd * v_valor, 2);
  end loop;

  update f.solicitacao_faturamento
     set perfil_operacao_id = case when v_perfil_misto then null else v_perfil_unico end,
         perfil_aplicado_em = now(), perfil_aplicado_por = v_scope.usuario_id
   where id = v_sol_id;
  update f.operacao_fiscal
     set valor_total = v_total,
         perfil_operacao_id = case when v_perfil_misto then null else v_perfil_unico end,
         solicitacao_id = v_sol_id,
         dados_json = dados_json || jsonb_build_object(
           'perfil_codigo', case when v_perfil_misto then null else v_perfil.codigo end,
           'valor_total', v_total
         )
   where id = v_op_id;

  -- Transporte com as mesmas regras da conferencia da OV (transportadora e volumes fora do 9).
  perform f.fn_solicitacao_nfe_salvar_transporte(v_sol_id, jsonb_build_object(
    'transportador', case when v_modalidade = 9 then null else p_operacao->'transportador' end,
    'volumes', case when v_modalidade = 9 then '[]'::jsonb else coalesce(p_operacao->'volumes', '[]'::jsonb) end
  ));

  -- Congela emitente, destinatario, operacao e itens. Pendencia de cadastro derruba tudo,
  -- com a lista no erro: a pessoa corrige o cadastro e cria a remessa de novo.
  v_congelado := f.fn_solicitacao_nfe_congelar_cadastro(v_sol_id);
  if not coalesce((v_congelado->>'ok')::boolean, false) then
    select string_agg(p->>'mensagem', ' ') into v_pendencias
    from jsonb_array_elements(coalesce(v_congelado->'pendencias', '[]'::jsonb)) p;
    raise exception using errcode = '22023', message = 'Cadastro com pendencias: ' || coalesce(v_pendencias, 'sem detalhe');
  end if;

  return jsonb_build_object(
    'operacao_id', v_op_id, 'solicitacao_id', v_sol_id, 'natureza_operacao', v_natureza,
    'cfop', v_cfop, 'ambito', v_ambito, 'perfil', v_perfil.codigo, 'valor_total', v_total,
    'itens', v_ordem
  );
end;
$$;
revoke all on function f.fn_remessa_nfe_criar(integer, jsonb, jsonb) from public, anon;
grant execute on function f.fn_remessa_nfe_criar(integer, jsonb, jsonb) to authenticated, service_role;

-- Cancela uma remessa ainda nao autorizada em producao: a operacao e a solicitacao viram CANCELADA.
create or replace function f.fn_remessa_nfe_cancelar(p_operacao_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_scope record;
  v_op f.operacao_fiscal%rowtype;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if char_length(btrim(coalesce(p_motivo, ''))) < 15 then
    raise exception using errcode = '22023', message = 'Informe o motivo do cancelamento (ao menos 15 caracteres).';
  end if;
  select * into v_op
  from f.operacao_fiscal o
  where o.tenant_id = v_scope.tenant_id and o.empresa_id = v_scope.empresa_id and o.id = p_operacao_id and o.deleted_at is null
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Remessa nao encontrada.';
  end if;
  if v_op.tipo <> 'REMESSA' or v_op.solicitacao_id is null then
    raise exception using errcode = '22023', message = 'Somente remessa emitida pelo pipeline de NF-e pode ser cancelada aqui.';
  end if;
  if v_op.chave_primeira_nota is not null or exists (
    select 1 from f.documento_fiscal_emissao e
    where e.solicitacao_id = v_op.solicitacao_id
      and (e.ambiente = 'PRODUCAO' or e.status in ('ENVIANDO', 'PROCESSANDO'))
  ) then
    raise exception using errcode = '55000', message = 'Remessa com NF-e de producao ou envio em andamento: cancele a nota pelo ciclo de vida da NF-e.';
  end if;
  update f.operacao_fiscal
     set status = 'CANCELADA', justificativa_fisco = coalesce(justificativa_fisco || ' | ', '') || 'Cancelada: ' || btrim(p_motivo), updated_at = now()
   where id = v_op.id;
  update f.solicitacao_faturamento
     set status = 'CANCELADA', updated_at = now()
   where id = v_op.solicitacao_id and status <> 'EMITIDA';
  return jsonb_build_object('operacao_id', v_op.id, 'status', 'CANCELADA');
end;
$$;
revoke all on function f.fn_remessa_nfe_cancelar(uuid, text) from public, anon;
grant execute on function f.fn_remessa_nfe_cancelar(uuid, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Autorizacao da NF-e liga a operacao e, em producao, abre o controle de retorno
-- ---------------------------------------------------------------------------
create or replace function f.fn_operacao_fiscal_apos_autorizacao()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_op f.operacao_fiscal%rowtype;
begin
  if new.status <> 'AUTORIZADA' or coalesce(old.status, '') = 'AUTORIZADA' or new.solicitacao_id is null then
    return new;
  end if;
  select * into v_op
  from f.operacao_fiscal op
  where op.tenant_id = new.tenant_id and op.empresa_id = new.empresa_id
    and op.solicitacao_id = new.solicitacao_id and op.deleted_at is null
  for update;
  if not found then return new; end if;

  if new.ambiente = 'HOMOLOGACAO' then
    update f.operacao_fiscal
       set dados_json = dados_json || jsonb_build_object('homologacao', jsonb_build_object(
             'documento_fiscal_id', new.documento_fiscal_id, 'chave', new.chave_acesso,
             'numero', new.numero, 'serie', new.serie, 'autorizado_em', new.autorizado_em)),
           updated_at = now()
     where id = v_op.id;
    return new;
  end if;

  update f.operacao_fiscal
     set ambiente = 'PRODUCAO',
         chave_primeira_nota = new.chave_acesso,
         documento_primeira_nota_id = new.documento_fiscal_id,
         status = case when v_op.tipo = 'REMESSA' and v_op.finalidade in ('INDUSTRIALIZACAO', 'CONSERTO')
                       then 'AGUARDANDO_RETORNO' else 'CONCLUIDA' end,
         updated_at = now()
   where id = v_op.id;
  if v_op.tipo = 'REMESSA' and new.chave_acesso ~ '^[0-9]{44}$' then
    insert into f.remessa_controle (
      tenant_id, empresa_id, operacao_remessa_id, finalidade, chave_remessa,
      destinatario_documento, destinatario_nome, remessa_em
    ) values (
      v_op.tenant_id, v_op.empresa_id, v_op.id, v_op.finalidade, new.chave_acesso,
      regexp_replace(coalesce(v_op.entrega_json->>'documento', ''), '\D', '', 'g'),
      coalesce(v_op.entrega_json->>'nome', 'DESTINATARIO'),
      (coalesce(new.autorizado_em, now()) at time zone 'America/Sao_Paulo')::date
    )
    on conflict (tenant_id, empresa_id, chave_remessa) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function f.fn_operacao_fiscal_apos_autorizacao() from public, anon, authenticated;

drop trigger if exists trg_operacao_fiscal_apos_autorizacao on f.documento_fiscal_emissao;
create trigger trg_operacao_fiscal_apos_autorizacao
  after update of status on f.documento_fiscal_emissao
  for each row execute function f.fn_operacao_fiscal_apos_autorizacao();

-- ---------------------------------------------------------------------------
-- 5. Congelar cadastro: destinacao so na venda
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION f.fn_solicitacao_nfe_congelar_cadastro(p_solicitacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET row_security TO 'off'
AS $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_empresa c.empresa%rowtype;
  v_fiscal c.empresa_fiscal%rowtype;
  v_endereco c.empresa_endereco%rowtype;
  v_cliente public.clientes%rowtype;
  v_item record;
  v_documento text;
  v_pendencias jsonb := '[]'::jsonb;
  v_rota_cliente text;
  v_excecao_motivo text;
  v_municipio_emitente text;
  v_municipio_destinatario text;
begin
  select * into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitacao de faturamento nao encontrada.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para validar esta solicitacao.';
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = 'Somente solicitacao ainda nao emitida pode congelar cadastro.';
  end if;

  select * into v_empresa
  from c.empresa e
  where e.tenant_id = v_sf.tenant_id
    and e.id = v_sf.empresa_id
    and e.deleted_at is null
    and e.ativo;
  if not found then
    v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object(
      'entidade', 'empresa', 'id', v_sf.empresa_id, 'campo', 'empresa',
      'mensagem', 'Empresa ativa nao encontrada no cadastro corporativo.', 'rota', '/configuracoes'
    ));
  else
    select * into v_fiscal
    from c.empresa_fiscal ef
    where ef.empresa_id = v_empresa.id and ef.deleted_at is null
    order by ef.updated_at desc
    limit 1;
    select * into v_endereco
    from c.empresa_endereco ee
    where ee.empresa_id = v_empresa.id and ee.deleted_at is null
    order by (ee.tipo = 'FISCAL') desc, ee.updated_at desc
    limit 1;

    if length(regexp_replace(coalesce(v_empresa.cnpj, ''), '[^0-9]', '', 'g')) <> 14
       or not public.cnpj_valido(v_empresa.cnpj) then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','cnpj','mensagem','CNPJ do emitente e invalido.','rota','/configuracoes'));
    end if;
    if nullif(btrim(v_empresa.razao_social), '') is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','razao_social','mensagem','Razao social do emitente nao informada.','rota','/configuracoes'));
    end if;
    if v_fiscal.id is null or nullif(btrim(v_fiscal.inscricao_estadual), '') is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','inscricao_estadual','mensagem','IE do emitente nao informada.','rota','/configuracoes'));
    end if;
    if v_fiscal.id is null or v_fiscal.crt is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','crt','mensagem','CRT do emitente nao informado.','rota','/configuracoes'));
    end if;
    if v_fiscal.id is null or v_fiscal.serie_nfe is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','serie_nfe','mensagem','Serie da NF-e do emitente nao informada.','rota','/configuracoes'));
    end if;
    if v_endereco.id is null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','endereco_fiscal','mensagem','Endereco fiscal do emitente nao informado.','rota','/configuracoes'));
    else
      if nullif(btrim(v_endereco.logradouro), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','logradouro','mensagem','Logradouro do emitente nao informado.','rota','/configuracoes')); end if;
      if nullif(btrim(v_endereco.numero), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','numero','mensagem','Numero do emitente nao informado.','rota','/configuracoes')); end if;
      if nullif(btrim(v_endereco.bairro), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','bairro','mensagem','Bairro do emitente nao informado.','rota','/configuracoes')); end if;
      if nullif(btrim(v_endereco.cidade), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','cidade','mensagem','Municipio do emitente nao informado.','rota','/configuracoes')); end if;
      if nullif(btrim(v_endereco.uf::text), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','uf','mensagem','UF do emitente nao informada.','rota','/configuracoes')); end if;
      if regexp_replace(coalesce(v_endereco.cep, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','cep','mensagem','CEP do emitente deve ter 8 digitos.','rota','/configuracoes')); end if;
      if regexp_replace(coalesce(v_endereco.codigo_municipio_ibge, ''), '[^0-9]', '', 'g') !~ '^[0-9]{7}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','codigo_municipio_ibge','mensagem','Codigo IBGE do emitente deve ter 7 digitos.','rota','/configuracoes')); end if;
    end if;
  end if;

  v_rota_cliente := '/clientes/cadastro-fiscal?cliente_id=' || coalesce(v_sf.cliente_id::text, '');
  select * into v_cliente
  from public.clientes c
  where c.tenant_id = v_sf.tenant_id
    and c.empresa_id = v_sf.empresa_id
    and c.id = v_sf.cliente_id
    and c.ativo is true;
  if not found then
    v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_sf.cliente_id,'campo','cliente','mensagem','Destinatario ativo nao encontrado nesta empresa.','rota',v_rota_cliente));
  else
    v_documento := regexp_replace(coalesce(v_cliente.documento, ''), '[^0-9]', '', 'g');
    if not ((length(v_documento) = 14 and public.cnpj_valido(v_documento)) or (length(v_documento) = 11 and public.cpf_valido(v_documento))) then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','documento','mensagem','CPF/CNPJ do destinatario e invalido.','rota',v_rota_cliente));
    end if;
    if nullif(btrim(v_cliente.razao_social), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','razao_social','mensagem','Razao social ou nome completo nao informado.','rota',v_rota_cliente)); end if;
    if v_cliente.indicador_ie is null or v_cliente.indicador_ie not in ('1','2','9') then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','indicador_ie','mensagem','Confirme manualmente o indicador de IE (1, 2 ou 9).','rota',v_rota_cliente)); end if;
    if v_cliente.indicador_ie = '1' and nullif(btrim(v_cliente.inscricao_estadual), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','inscricao_estadual','mensagem','Contribuinte do ICMS deve ter IE informada.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.logradouro), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','logradouro','mensagem','Logradouro do destinatario nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.numero_endereco), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','numero_endereco','mensagem','Numero do destinatario nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.bairro), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','bairro','mensagem','Bairro do destinatario nao informado.','rota',v_rota_cliente)); end if;
    if nullif(btrim(v_cliente.cidade), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','cidade','mensagem','Municipio do destinatario nao informado.','rota',v_rota_cliente)); end if;
    if coalesce(v_cliente.uf, '') !~ '^[A-Za-z]{2}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','uf','mensagem','UF do destinatario deve ter 2 letras.','rota',v_rota_cliente)); end if;
    if regexp_replace(coalesce(v_cliente.cep, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','cep','mensagem','CEP do destinatario deve ter 8 digitos.','rota',v_rota_cliente)); end if;
    if regexp_replace(coalesce(v_cliente.codigo_ibge_municipio, ''), '[^0-9]', '', 'g') !~ '^[0-9]{7}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','codigo_ibge_municipio','mensagem','Codigo IBGE do destinatario deve ter 7 digitos.','rota',v_rota_cliente)); end if;
  end if;

  -- Copia apenas atributos permanentes do produto. CFOP, CST/CSOSN e aliquotas
  -- continuam exclusivamente sob responsabilidade da solicitacao.
  update f.solicitacao_item si
  set codigo_produto = coalesce(si.codigo_produto, nullif(btrim(i.codigo_interno), '')),
      ncm = coalesce(si.ncm, nullif(regexp_replace(coalesce(fi.ncm, ''), '[^0-9]', '', 'g'), '')),
      cest = coalesce(si.cest, nullif(regexp_replace(coalesce(fi.cest, ''), '[^0-9]', '', 'g'), '')),
      origem_mercadoria = coalesce(si.origem_mercadoria, fi.origem),
      unidade_tributavel = coalesce(si.unidade_tributavel, nullif(btrim(fi.unidade_tributavel), ''), nullif(btrim(si.unidade), '')),
      valor_desconto = coalesce(si.valor_desconto, 0)
  from public.itens i
  left join public.fiscal_itens fi
    on fi.tenant_id = i.tenant_id and fi.empresa_id = i.empresa_id and fi.item_id = i.id
  where si.tenant_id = v_sf.tenant_id
    and si.empresa_id = v_sf.empresa_id
    and si.solicitacao_id = v_sf.id
    and i.tenant_id = si.tenant_id
    and i.empresa_id = si.empresa_id
    and i.id = si.item_id;

  if not exists (select 1 from f.solicitacao_item si where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id) then
    v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','itens','mensagem','A solicitacao nao possui itens.','rota','/faturamento/solicitacoes/' || v_sf.id));
  end if;

  for v_item in
    select si.*
    from f.solicitacao_item si
    where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id and si.solicitacao_id = v_sf.id
    order by si.ordem, si.id
  loop
    if nullif(btrim(v_item.codigo_produto), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','codigo_produto','mensagem',format('Linha %s: codigo do produto nao informado.',v_item.ordem),'rota','/estoque/itens')); end if;
    if nullif(btrim(v_item.descricao), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','descricao','mensagem',format('Linha %s: descricao nao informada.',v_item.ordem),'rota','/estoque/itens')); end if;
    if regexp_replace(coalesce(v_item.ncm, ''), '[^0-9]', '', 'g') !~ '^[0-9]{8}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','ncm','mensagem',format('Linha %s: NCM deve ter 8 digitos.',v_item.ordem),'rota','/estoque/itens')); end if;
    if regexp_replace(coalesce(v_item.cfop, ''), '[^0-9]', '', 'g') !~ '^[0-9]{4}$' then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cfop','mensagem',format('Linha %s: CFOP nao confirmado na solicitacao.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if v_item.origem_mercadoria is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','origem_mercadoria','mensagem',format('Linha %s: origem da mercadoria nao informada.',v_item.ordem),'rota','/estoque/itens')); end if;
    if nullif(btrim(v_item.unidade), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','unidade','mensagem',format('Linha %s: unidade comercial nao informada.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if nullif(btrim(v_item.unidade_tributavel), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','item','id',v_item.item_id,'campo','unidade_tributavel','mensagem',format('Linha %s: unidade tributavel nao informada.',v_item.ordem),'rota','/estoque/itens')); end if;
    if v_item.quantidade <= 0 then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','quantidade','mensagem',format('Linha %s: quantidade deve ser maior que zero.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if v_item.valor_unitario <= 0 then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','valor_unitario','mensagem',format('Linha %s: valor unitario deve ser maior que zero.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if (case when nullif(btrim(v_item.cst_icms), '') is null then 0 else 1 end + case when nullif(btrim(v_item.csosn), '') is null then 0 else 1 end) <> 1 then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_icms_csosn','mensagem',format('Linha %s: informe CST de ICMS ou CSOSN, nunca ambos.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if v_fiscal.crt = 1 and nullif(btrim(v_item.csosn), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','csosn','mensagem',format('Linha %s: emitente do Simples exige CSOSN.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if v_fiscal.crt is not null and v_fiscal.crt <> 1 and nullif(btrim(v_item.cst_icms), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_icms','mensagem',format('Linha %s: regime normal exige CST de ICMS.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if nullif(btrim(v_item.cst_ipi), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_ipi','mensagem',format('Linha %s: CST de IPI nao confirmado.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if nullif(btrim(v_item.cst_pis), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_pis','mensagem',format('Linha %s: CST de PIS nao confirmado.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
    if nullif(btrim(v_item.cst_cofins), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao_item','id',v_item.id,'campo','cst_cofins','mensagem',format('Linha %s: CST de COFINS nao confirmado.',v_item.ordem),'rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  end loop;

  if v_sf.finalidade_emissao is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','finalidade_emissao','mensagem','Finalidade de emissao nao confirmada.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.consumidor_final is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','consumidor_final','mensagem','Indicador de consumidor final nao confirmado.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.presenca_comprador is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','presenca_comprador','mensagem','Indicador de presenca do comprador nao confirmado.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.modalidade_frete is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','modalidade_frete','mensagem','Modalidade do frete nao confirmada.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.valor_frete is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','valor_frete','mensagem','Valor do frete nao confirmado; informe zero quando nao houver.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.valor_seguro is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','valor_seguro','mensagem','Valor do seguro nao confirmado; informe zero quando nao houver.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.valor_outras_despesas is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','valor_outras_despesas','mensagem','Outras despesas nao confirmadas; informe zero quando nao houver.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  -- Remessa nao tem destinacao: a mercadoria volta. So a venda precisa dela.
  if v_sf.natureza_operacao not like 'REMESSA%' and nullif(btrim(v_sf.destinacao_mercadoria), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','destinacao_mercadoria','mensagem','Destinacao da mercadoria nao confirmada; ela decide a aliquota interna de ICMS.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if nullif(btrim(v_sf.pagamento_forma), '') is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','pagamento_forma','mensagem','Forma de pagamento nao confirmada; sem ela o provedor assume dinheiro.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;
  if v_sf.pagamento_indicador is null then v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','pagamento_indicador','mensagem','Indicador de pagamento (a vista ou a prazo) nao confirmado.','rota','/faturamento/solicitacoes/' || v_sf.id)); end if;

  -- xMun e o NOME do municipio: vem da tabela IBGE pelo cMun, e o texto do cadastro so
  -- entra quando o codigo nao esta na tabela. Um nome que ainda seja so digitos e o codigo
  -- no lugar do nome (NF-e 2/55) e vira pendencia antes de a nota existir.
  v_municipio_emitente := coalesce(
    (select mi.nome from public.municipios_ibge mi
      where mi.codigo_ibge = regexp_replace(coalesce(v_endereco.codigo_municipio_ibge, ''), '[^0-9]', '', 'g')),
    nullif(btrim(v_endereco.cidade), '')
  );
  v_municipio_destinatario := coalesce(
    (select mi.nome from public.municipios_ibge mi
      where mi.codigo_ibge = regexp_replace(coalesce(v_cliente.codigo_ibge_municipio, ''), '[^0-9]', '', 'g')),
    nullif(btrim(v_cliente.cidade), '')
  );
  if v_endereco.id is not null and v_municipio_emitente ~ '^[0-9 .-]+$' then
    v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','empresa','id',v_empresa.id,'campo','cidade','mensagem',format('Municipio do emitente esta como %s, o codigo IBGE no lugar do nome.', v_municipio_emitente),'rota','/configuracoes'));
  end if;
  if v_cliente.id is not null and v_municipio_destinatario ~ '^[0-9 .-]+$' then
    v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','cliente','id',v_cliente.id,'campo','cidade','mensagem',format('Municipio do destinatario esta como %s, o codigo IBGE no lugar do nome.', v_municipio_destinatario),'rota',v_rota_cliente));
  end if;

  -- Excecao ICMS 12% por exigencia do destinatario: continua cabendo nesta nota?
  if exists (
    select 1 from f.nfe_excecao_aliquota_destinatario ex
    where ex.solicitacao_id = v_sf.id and ex.desativada_em is null
  ) then
    v_excecao_motivo := f.fn_nfe_excecao_aliquota_indisponivel(
      v_cliente.indicador_ie,
      v_sf.destinacao_mercadoria,
      upper(coalesce(v_sf.destino_uf_confirmada, v_cliente.uf, '')) = upper(coalesce(v_endereco.uf::text, ''))
    );
    if v_excecao_motivo is not null then
      v_pendencias := v_pendencias || jsonb_build_array(jsonb_build_object('entidade','solicitacao','id',v_sf.id,'campo','excecao_aliquota_destinatario','mensagem',v_excecao_motivo || ' Desative a excecao ou corrija a conferencia.','rota','/faturamento/solicitacoes/' || v_sf.id));
    end if;
  end if;

  if jsonb_array_length(v_pendencias) = 0 then
    update f.solicitacao_faturamento
    set emitente_snapshot = jsonb_build_object(
          'cnpj', regexp_replace(v_empresa.cnpj, '[^0-9]', '', 'g'),
          'razao_social', v_empresa.razao_social, 'nome_fantasia', v_empresa.nome_fantasia,
          'telefone', v_empresa.telefone, 'inscricao_estadual', v_fiscal.inscricao_estadual,
          'crt', v_fiscal.crt, 'serie_nfe', v_fiscal.serie_nfe,
          'logradouro', v_endereco.logradouro, 'numero', v_endereco.numero,
          'complemento', v_endereco.complemento, 'bairro', v_endereco.bairro,
          'cidade', v_municipio_emitente, 'uf', upper(v_endereco.uf::text),
          'codigo_municipio_ibge', regexp_replace(v_endereco.codigo_municipio_ibge, '[^0-9]', '', 'g'),
          'cep', regexp_replace(v_endereco.cep, '[^0-9]', '', 'g')
        ),
        destinatario_snapshot = jsonb_build_object(
          'id', v_cliente.id, 'documento', v_documento, 'nome', v_cliente.razao_social,
          'inscricao_estadual', nullif(btrim(v_cliente.inscricao_estadual), ''),
          'indicador_ie', v_cliente.indicador_ie, 'email', v_cliente.email,
          'telefone', v_cliente.telefone, 'logradouro', v_cliente.logradouro,
          'numero_endereco', v_cliente.numero_endereco, 'complemento', v_cliente.complemento,
          'bairro', v_cliente.bairro, 'cidade', v_municipio_destinatario, 'uf', upper(v_cliente.uf),
          'codigo_ibge_municipio', regexp_replace(v_cliente.codigo_ibge_municipio, '[^0-9]', '', 'g'),
          'cep', regexp_replace(v_cliente.cep, '[^0-9]', '', 'g')
        ),
        operacao_snapshot = jsonb_build_object(
          'natureza_operacao', natureza_operacao, 'finalidade_emissao', finalidade_emissao,
          'consumidor_final', consumidor_final, 'presenca_comprador', presenca_comprador,
          'modalidade_frete', modalidade_frete, 'valor_frete', valor_frete,
          'valor_seguro', valor_seguro, 'valor_outras_despesas', valor_outras_despesas,
          'destinacao_mercadoria', destinacao_mercadoria,
          'pagamento', jsonb_build_object(
            'forma', pagamento_forma,
            'indicador', pagamento_indicador,
            'descricao', pagamento_descricao,
            'parcelas', case when pagamento_indicador = 1 then pagamento_parcelas else null end,
            'fatura_numero', (
              select os.codigo
              from f.solicitacao_item si
              join public.ordens_servico os on os.id::text = si.origem_id
              where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id
                and si.solicitacao_id = v_sf.id and si.origem_tipo = 'OV'
              order by si.ordem limit 1
            )
          )
        ) || coalesce((
          -- Chave so existe com a excecao ativa: snapshot de nota sem excecao nao muda.
          select jsonb_build_object('excecao_aliquota_destinatario', jsonb_build_object(
            'id', ex.id, 'numero_oc', ex.numero_oc, 'ativada_em', ex.ativada_em
          ))
          from f.nfe_excecao_aliquota_destinatario ex
          where ex.solicitacao_id = v_sf.id and ex.desativada_em is null
        ), '{}'::jsonb),
        snapshot_cadastro_em = now(), updated_at = now()
    where id = v_sf.id;
  else
    update f.solicitacao_faturamento
    set emitente_snapshot = null, destinatario_snapshot = null,
        operacao_snapshot = null, snapshot_cadastro_em = null, updated_at = now()
    where id = v_sf.id;
  end if;

  return jsonb_build_object(
    'ok', jsonb_array_length(v_pendencias) = 0,
    'solicitacao_id', v_sf.id,
    'cliente_id', v_sf.cliente_id,
    'rota_cliente', v_rota_cliente,
    'pendencias', v_pendencias
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6. Contas a receber: remessa nao gera titulo
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION f.fn_upsert_ar_from_nfe_venda(p_documento_fiscal_id uuid, p_old_valor_total numeric DEFAULT NULL::numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'f', 'public', 'a'
AS $function$
 declare
   v_df record;
   v_titulo_id uuid;
   v_valor numeric(15,2);
   v_desc text;
   v_venc date;
  v_parcelas jsonb;
  v_parcela jsonb;
  v_n integer := 0;
  v_pvalor numeric(15,2);
   v_plano_contas_id uuid;
   v_rateio_count integer;
 begin
   select * into v_df
   from f.documento_fiscal
   where id = p_documento_fiscal_id
     and deleted_at is null;

   if not found then return null; end if;

   if coalesce(v_df.operacao,'') <> 'SAIDA' then return null; end if;
   if coalesce(v_df.natureza,'') <> 'PRODUTO' then return null; end if;
   if coalesce(v_df.nfe_status,'') <> 'EMITIDA' then return null; end if;

   -- Remessa (conserto, industrializacao) nao e venda: sai sem pagamento (tPag 90) e nao
   -- gera titulo. Antes de 16/09/2026 toda NF-e de saida EMITIDA com cliente virava AR.
   if exists (
     select 1
     from f.documento_fiscal_emissao dfe
     join f.solicitacao_faturamento sf
       on sf.tenant_id = dfe.tenant_id and sf.empresa_id = dfe.empresa_id and sf.id = dfe.solicitacao_id
     where dfe.tenant_id = v_df.tenant_id
       and dfe.empresa_id = v_df.empresa_id
       and dfe.documento_fiscal_id = v_df.id
       and (sf.natureza_operacao like 'REMESSA%' or sf.pagamento_forma = '90')
   ) then return null; end if;

   if v_df.cliente_id is null then
     raise exception 'NF-e de faturamento precisa de cliente_id para gerar Contas a Receber.';
   end if;

   v_valor := coalesce(v_df.valor_total, 0);
   v_desc := concat('NFE ', coalesce(v_df.numero,''), '/', coalesce(v_df.serie,''));
   if btrim(v_desc) = '' then v_desc := 'FATURAMENTO NFE'; end if;

   v_venc := coalesce(v_df.emissao_date, current_date) + 15;

  -- Parcelas confirmadas na conferencia da NF-e (mesma fonte das duplicatas
  -- enviadas a SEFAZ). Sem snapshot, vale o padrao historico de 15 dias.
  select sf.operacao_snapshot->'pagamento'->'parcelas' into v_parcelas
  from f.documento_fiscal_emissao dfe
  join f.solicitacao_faturamento sf
    on sf.tenant_id = dfe.tenant_id and sf.empresa_id = dfe.empresa_id and sf.id = dfe.solicitacao_id
  where dfe.tenant_id = v_df.tenant_id
    and dfe.empresa_id = v_df.empresa_id
    and dfe.documento_fiscal_id = v_df.id
    and dfe.ambiente = 'PRODUCAO'
  limit 1;
  if jsonb_typeof(v_parcelas) is distinct from 'array' or jsonb_array_length(v_parcelas) = 0 then
    v_parcelas := null;
  end if;

   select pc.id into v_plano_contas_id
   from f.plano_contas pc
   where pc.tenant_id = v_df.tenant_id
     and pc.codigo = '3.01'
     and pc.deleted_at is null
   limit 1;

   if v_plano_contas_id is null then
     raise exception 'Plano de contas padrao (codigo=3.01) nao encontrado para tenant %', v_df.tenant_id;
   end if;

   select t.id into v_titulo_id
   from f.titulo t
   where t.tenant_id = v_df.tenant_id
     and t.empresa_id = v_df.empresa_id
     and t.tipo = 'AR'
     and t.documento_fiscal_id = v_df.id
     and t.deleted_at is null
   limit 1;

   if v_titulo_id is null then
     insert into f.titulo (
       tenant_id, empresa_id,
       tipo, status, origem,
       cliente_id,
       documento_fiscal_id,
       descricao,
       emissao_date, competencia_date,
       valor_total, valor_aberto
     ) values (
       v_df.tenant_id, v_df.empresa_id,
       'AR', 'PENDENTE', 'FATURAMENTO',
       v_df.cliente_id,
       v_df.id,
       v_desc,
       v_df.emissao_date, v_df.competencia_date,
       v_valor, v_valor
     )
     returning id into v_titulo_id;

     if v_parcelas is null then
       insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
       values (v_df.tenant_id, v_titulo_id, '1', v_venc, v_valor, v_valor);
     else
       for v_parcela in select * from jsonb_array_elements(v_parcelas) loop
         v_n := v_n + 1;
         v_pvalor := coalesce(nullif(v_parcela->>'valor', '')::numeric,
                              case when jsonb_array_length(v_parcelas) = 1 then v_valor end);
         if v_pvalor is null then
           raise exception 'Parcela % da NF-e sem valor no snapshot fiscal.', v_n;
         end if;
         insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
         values (
           v_df.tenant_id, v_titulo_id, v_n::text,
           coalesce(v_df.emissao_date, current_date) + coalesce((v_parcela->>'dias')::integer, 15),
           v_pvalor, v_pvalor
         );
       end loop;
     end if;

     insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, os_id, percentual, valor)
     values (v_df.tenant_id, v_titulo_id, v_plano_contas_id, v_df.os_id_import, 100.0000, v_valor);

   else
     update f.titulo
     set
       cliente_id = v_df.cliente_id,
       descricao = v_desc,
       emissao_date = v_df.emissao_date,
       competencia_date = v_df.competencia_date,
       valor_total = v_valor,
       valor_aberto = case
         when p_old_valor_total is not null and coalesce(valor_aberto,0) = coalesce(p_old_valor_total,0) then v_valor
         when coalesce(valor_aberto,0) = coalesce(valor_total,0) then v_valor
         else valor_aberto
       end
     where id = v_titulo_id;

     update f.titulo_parcela
     set
       vencimento_date = v_venc,
       valor = v_valor,
       valor_aberto = case
         when p_old_valor_total is not null and coalesce(valor_aberto,0) = coalesce(p_old_valor_total,0) then v_valor
         when coalesce(valor_aberto,0) = coalesce(valor,0) then v_valor
         else valor_aberto
       end
     where titulo_id = v_titulo_id
       and tenant_id = v_df.tenant_id
       and numero = '1'
       and deleted_at is null;

     select count(*)
       into v_rateio_count
     from f.titulo_rateio
     where titulo_id = v_titulo_id
       and tenant_id = v_df.tenant_id
       and deleted_at is null;

     if coalesce(v_rateio_count, 0) = 0 then
       insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, os_id, percentual, valor)
       values (v_df.tenant_id, v_titulo_id, v_plano_contas_id, v_df.os_id_import, 100.0000, v_valor);
     elsif v_rateio_count = 1 then
       update f.titulo_rateio
       set
         percentual = 100.0000,
         valor = v_valor,
         plano_contas_id = v_plano_contas_id,
         os_id = v_df.os_id_import
       where titulo_id = v_titulo_id
         and tenant_id = v_df.tenant_id
         and deleted_at is null;
     else
       update f.titulo_rateio
       set valor = case
         when percentual is not null
           then round(v_valor * percentual / 100.0, 2)
         when valor is not null
              and coalesce(p_old_valor_total, 0) > 0
           then round(v_valor * valor / p_old_valor_total, 2)
         else valor
       end
       where titulo_id = v_titulo_id
         and tenant_id = v_df.tenant_id
         and deleted_at is null;
     end if;
   end if;

   return v_titulo_id;
 end;
 $function$;
