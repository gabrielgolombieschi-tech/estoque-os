\set ON_ERROR_STOP on

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values (
  '10000000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', 'rls-faturamento@example.test',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"nome":"Smoke RLS"}'::jsonb, now(), now()
);

insert into public.tenants (id, nome, ativo)
values ('10000000-0000-4000-8000-000000000010', 'Tenant smoke RLS', true);
insert into c.tenant (id, codigo, nome, ativo)
values ('10000000-0000-4000-8000-000000000010', 'RLS-FAT', 'Tenant smoke RLS', true);

insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo)
values
  ('10000000-0000-4000-8000-000000000020', '10000000-0000-4000-8000-000000000010', 'RLS-A', 'Empresa RLS A', 'Empresa RLS A', '10000000000100', true),
  ('10000000-0000-4000-8000-000000000030', '10000000-0000-4000-8000-000000000010', 'RLS-B', 'Empresa RLS B', 'Empresa RLS B', '10000000000290', true);
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo)
values
  ('10000000-0000-4000-8000-000000000020', '10000000-0000-4000-8000-000000000010', '10000000000100', 'Empresa RLS A', 'Empresa RLS A', true),
  ('10000000-0000-4000-8000-000000000030', '10000000-0000-4000-8000-000000000010', '10000000000290', 'Empresa RLS B', 'Empresa RLS B', true);
insert into c.empresa_fiscal (empresa_id, serie_nfe, certificado_validade_em)
values
  ('10000000-0000-4000-8000-000000000020', 2, current_date + 20),
  ('10000000-0000-4000-8000-000000000030', 2, current_date + 5);

insert into a.usuario (id, auth_user_id, nome, email, ativo)
values ('10000000-0000-4000-8000-000000000040', '10000000-0000-4000-8000-000000000001', 'Smoke RLS', 'rls-faturamento@example.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo)
values ('10000000-0000-4000-8000-000000000040', '10000000-0000-4000-8000-000000000010', 'ADMIN', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo)
values
  ('10000000-0000-4000-8000-000000000040', '10000000-0000-4000-8000-000000000020', 'DIRETOR', true),
  ('10000000-0000-4000-8000-000000000040', '10000000-0000-4000-8000-000000000030', 'DIRETOR', true);
insert into public.user_tenant_context (user_id, tenant_id)
values ('10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000010');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
values ('10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000020');

insert into f.perfil_operacao (id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto)
values
  ('10000000-0000-4000-8000-000000000101', '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000020', 'RLS-A', 'Perfil A sem regra fiscal', 'NFE', 'TESTE_A', 'Teste A'),
  ('10000000-0000-4000-8000-000000000102', '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000030', 'RLS-B', 'Perfil B sem regra fiscal', 'NFE', 'TESTE_B', 'Teste B');

insert into f.perfil_operacao_evidencia (
  id, tenant_id, empresa_id, fonte, fonte_linha, natureza_texto, cfop,
  origem, cst_completo, cst_icms, aliquota_icms_observada,
  aliquota_ipi_observada, base_reduzida_observada, itens_observados,
  notas_observadas, ncms, notas_exemplo, leitura_operacional, faixa,
  justificativa_faixa
)
values
  ('10000000-0000-4000-8000-000000000103', '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000020', 'smoke.csv', 1, 'Teste A', '5102', 0, '000', '00', 17, 0, false, 1, 1, array['85365090'], array[1], 'Smoke A', 'REVISAO', 'Smoke'),
  ('10000000-0000-4000-8000-000000000104', '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000030', 'smoke.csv', 1, 'Teste B', '5102', 0, '000', '00', 17, 0, false, 1, 1, array['85365090'], array[1], 'Smoke B', 'REVISAO', 'Smoke');

insert into f.solicitacao_faturamento (id, tenant_id, empresa_id, status)
values
  ('10000000-0000-4000-8000-000000000111', '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000020', 'RASCUNHO'),
  ('10000000-0000-4000-8000-000000000112', '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000030', 'RASCUNHO');
insert into f.solicitacao_item (id, solicitacao_id, tenant_id, empresa_id, origem_tipo, descricao, quantidade, valor_unitario)
values
  ('10000000-0000-4000-8000-000000000121', '10000000-0000-4000-8000-000000000111', '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000020', 'AVULSO', 'Item A', 1, 1),
  ('10000000-0000-4000-8000-000000000122', '10000000-0000-4000-8000-000000000112', '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000030', 'AVULSO', 'Item B', 1, 1);

alter table f.documento_fiscal disable trigger trg_documento_fiscal__ar_nfe;
insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, valor_total, operacao, natureza, origem, nfe_status)
values
  ('10000000-0000-4000-8000-000000000131', '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000020', repeat('1', 44), '55', 1, 'SAIDA', 'PRODUTO', 'EMITIDO', 'RASCUNHO'),
  ('10000000-0000-4000-8000-000000000132', '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000030', repeat('2', 44), '55', 1, 'SAIDA', 'PRODUTO', 'EMITIDO', 'RASCUNHO');
alter table f.documento_fiscal enable trigger trg_documento_fiscal__ar_nfe;

insert into f.documento_fiscal_emissao (documento_fiscal_id, solicitacao_id, tenant_id, empresa_id, referencia_externa, ambiente, status)
values
  ('10000000-0000-4000-8000-000000000131', '10000000-0000-4000-8000-000000000111', '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000020', 'RLS-EMISSAO-A', 'HOMOLOGACAO', 'RASCUNHO'),
  ('10000000-0000-4000-8000-000000000132', '10000000-0000-4000-8000-000000000112', '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000030', 'RLS-EMISSAO-B', 'HOMOLOGACAO', 'RASCUNHO');

do $producao_bloqueada$
begin
  begin
    update f.documento_fiscal_emissao
       set ambiente = 'PRODUCAO'
     where documento_fiscal_id = '10000000-0000-4000-8000-000000000131';
    raise exception 'A producao foi aceita sem perfil explicitamente liberado';
  exception
    when others then
      if sqlerrm = 'A producao foi aceita sem perfil explicitamente liberado' then
        raise;
      end if;
  end;
end;
$producao_bloqueada$;

insert into f.documento_fiscal_evento (id, documento_fiscal_id, tenant_id, empresa_id, tipo, status)
values
  ('10000000-0000-4000-8000-000000000141', '10000000-0000-4000-8000-000000000131', '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000020', 'CONSULTA', 'OK'),
  ('10000000-0000-4000-8000-000000000142', '10000000-0000-4000-8000-000000000132', '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000030', 'CONSULTA', 'OK');

insert into f.documento_fiscal_item (
  id, tenant_id, empresa_id, documento_fiscal_id, item_n, descricao,
  ncm, cfop, quantidade, unidade, valor_unitario, valor_total
)
values (
  '10000000-0000-4000-8000-000000000151', '10000000-0000-4000-8000-000000000010',
  '10000000-0000-4000-8000-000000000020', '10000000-0000-4000-8000-000000000131',
  1, 'Item original para estorno', '85365090', '5102', 2, 'UN', 50, 100
);

insert into f.documento_fiscal_imposto (
  tenant_id, documento_fiscal_id, imposto, natureza, base_original, base_calculo, aliquota, valor_calculado
)
values (
  '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000131',
  'ICMS', 'DEBITO', 100, 100, 17, 17
);

insert into public.nf_entrada (
  id, tenant_id, empresa_id, chave, numero, emitente_nome, valor_produtos,
  valor_total, xml_raw
)
values (
  900001, '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000020',
  repeat('9', 44), '900001', 'Fornecedor XML', 100, 100,
  '<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe"><NFe><infNFe><det nItem="1"><prod><cProd>ABC</cProd><xProd>ITEM XML</xProd><NCM>85365090</NCM><CFOP>1101</CFOP><uCom>UN</uCom><uTrib>UN</uTrib><qCom>2</qCom><vUnCom>50</vUnCom><vProd>100</vProd></prod><imposto><ICMS><ICMS00><orig>0</orig><CST>00</CST><vBC>100</vBC><pICMS>17</pICMS><vICMS>17</vICMS></ICMS00></ICMS><IPI><IPITrib><CST>50</CST><vBC>100</vBC><pIPI>0</pIPI><vIPI>0</vIPI></IPITrib></IPI><PIS><PISAliq><CST>01</CST><vBC>100</vBC><pPIS>1.65</pPIS><vPIS>1.65</vPIS></PISAliq></PIS><COFINS><COFINSAliq><CST>01</CST><vBC>100</vBC><pCOFINS>7.6</pCOFINS><vCOFINS>7.6</vCOFINS></COFINSAliq></COFINS></imposto></det></infNFe></NFe></nfeProc>'
);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

do $operacoes$
declare
  v_devolucao uuid;
  v_remessa uuid;
  v_retorno uuid;
  v_controle uuid;
  v_estorno uuid;
  v_venda_ordem uuid := '10000000-0000-4000-8000-000000000160';
begin
  if jsonb_array_length(f.fn_devolucao_compra_preparar(900001)->'itens') <> 1 then
    raise exception 'Leitura do XML da devolucao nao retornou o item esperado';
  end if;
  begin
    perform f.fn_devolucao_compra_criar(900001, '[{"nitem":1,"quantidade":1,"cfop_confirmado":"5201","cst_icms":"20"}]'::jsonb);
    raise exception 'CST divergente foi aceito';
  exception when others then
    if sqlerrm = 'CST divergente foi aceito' then raise; end if;
  end;
  v_devolucao := f.fn_devolucao_compra_criar(900001, '[{"nitem":1,"quantidade":1,"cfop_confirmado":"5201"}]'::jsonb);
  perform f.fn_operacao_validar_homologacao(v_devolucao, 1::smallint);
  if not exists (
    select 1 from f.operacao_fiscal_item
    where operacao_id=v_devolucao and base_icms=50 and valor_icms=8.50 and unidade_tributavel='UN' and xml_validado
  ) then
    raise exception 'Devolucao parcial nao preservou o snapshot fiscal proporcional do XML';
  end if;

  insert into f.operacao_fiscal(id,tenant_id,empresa_id,tipo,status,cfop_confirmado,cfop_segunda_nota,entrega_json,criado_por)
  values(v_venda_ordem,'10000000-0000-4000-8000-000000000010','10000000-0000-4000-8000-000000000020','VENDA_ORDEM','AGUARDANDO_PRIMEIRA','6119','6923','{"cnpj":"12345678000190"}',a.fn_current_usuario_id());
  insert into f.operacao_fiscal_item(operacao_id,tenant_id,empresa_id,ordem,descricao,quantidade,valor_unitario,valor_total,cfop_confirmado)
  values(v_venda_ordem,'10000000-0000-4000-8000-000000000010','10000000-0000-4000-8000-000000000020',1,'Venda a ordem',1,1,1,'6119');
  begin
    perform f.fn_operacao_validar_homologacao(v_venda_ordem, 2::smallint);
    raise exception 'Segunda nota foi liberada sem chave da primeira';
  exception when others then
    if sqlerrm = 'Segunda nota foi liberada sem chave da primeira' then raise; end if;
  end;
  perform f.fn_operacao_registrar_chave(v_venda_ordem,1::smallint,repeat('7',44));
  perform f.fn_operacao_validar_homologacao(v_venda_ordem,2::smallint);

  v_remessa := f.fn_remessa_criar('CONSERTO','5915','{"documento":"12345678000190","nome":"Consertador"}'::jsonb,
    '[{"descricao":"Motor","quantidade":1,"unidade":"UN","valor_unitario":0}]'::jsonb,null);
  perform f.fn_operacao_registrar_chave(v_remessa,1::smallint,repeat('6',44));
  select id into v_controle from f.remessa_controle where operacao_remessa_id=v_remessa;
  v_retorno := f.fn_retorno_criar(v_controle,'5916');
  perform f.fn_operacao_registrar_chave(v_retorno,1::smallint,repeat('5',44));
  if not exists(select 1 from f.remessa_controle where id=v_controle and status='ENCERRADA') then
    raise exception 'Controle de remessa nao foi encerrado pelo retorno';
  end if;

  v_estorno := f.fn_estorno_criar('10000000-0000-4000-8000-000000000131','1202','ESTORNO DE TESTE APOS PRAZO LEGAL');
  perform f.fn_operacao_validar_homologacao(v_estorno,1::smallint);
  perform f.fn_operacao_vincular_documento(v_estorno,1::smallint,'10000000-0000-4000-8000-000000000131');
  if (select nfe_referenciada from f.documento_fiscal where id='10000000-0000-4000-8000-000000000131') <> repeat('1',44) then
    raise exception 'Chave referenciada nao foi copiada para documento_fiscal';
  end if;
  if (select (dados_json#>>'{snapshot_impostos,0,valor_calculado}')::numeric from f.operacao_fiscal where id=v_estorno) <> 17 then
    raise exception 'Estorno nao preservou o snapshot de impostos do documento original';
  end if;
end;
$operacoes$;

do $smoke$
declare
  v_tabela text;
  v_total integer;
  v_outra integer;
begin
  if public.empresa_certificado_alerta() ->> 'empresa_id' <> '10000000-0000-4000-8000-000000000020'
     or (public.empresa_certificado_alerta() ->> 'dias_para_vencer')::integer <> 20 then
    raise exception 'Alerta do certificado nao respeitou a empresa autenticada';
  end if;

  foreach v_tabela in array array[
    'f.perfil_operacao',
    'f.perfil_operacao_evidencia',
    'f.solicitacao_faturamento',
    'f.solicitacao_item',
    'f.documento_fiscal_emissao',
    'f.documento_fiscal_evento'
  ] loop
    execute format('select count(*) from %s', v_tabela) into v_total;
    execute format(
      'select count(*) from %s where empresa_id = %L::uuid',
      v_tabela,
      '10000000-0000-4000-8000-000000000030'
    ) into v_outra;
    if v_total <> 1 then
      raise exception 'RLS falhou em %: esperado 1 registro visivel da empresa atual, obtido %', v_tabela, v_total;
    end if;
    if v_outra <> 0 then
      raise exception 'RLS falhou em %: registro da outra empresa ficou visivel', v_tabela;
    end if;
  end loop;
end;
$smoke$;

select 'RLS authenticated: 6/6 tabelas enxergam a empresa atual e ocultam a outra.' as resultado;

rollback;
