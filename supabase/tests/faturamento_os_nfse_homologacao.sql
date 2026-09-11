\set ON_ERROR_STOP on
begin;

-- NFS-e Padrao Nacional a partir da OS, em HOMOLOGACAO (05/09/2026).
-- Cobre: perfil bloqueado (07.02); conferencia 17.09 com ISS retido + IRRF +
-- PCC; 14.06 na planta do cliente sem retencao; duas OS do mesmo tomador numa
-- nota; tomador de Joinville sem IM (bloqueia); iss_retido indefinido
-- (bloqueia) e override com justificativa; valor acima do saldo (bloqueia);
-- preparo idempotente com DPS numerada; rejeicao queima a DPS e devolve o
-- saldo; retry com numero novo; autorizacao em homologacao sem titulo;
-- webhook duplicado; cancelamento devolvendo o saldo; substituicao migrando
-- saldo; titulo liquido com f.titulo_retencao pelo caminho de producao; RLS.

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('15400000-0000-4000-8000-000000000010', 'authenticated', 'authenticated', 'os-nfse@example.test',
        '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Teste OS NFS-e"}'::jsonb, now(), now());
insert into public.tenants (id, nome, ativo) values ('15400000-0000-4000-8000-000000000001', 'Teste OS NFS-e', true);
insert into c.tenant (id, codigo, nome) values ('15400000-0000-4000-8000-000000000001', 'TESTE-OS-NFSE', 'Teste OS NFS-e');
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, telefone, email)
values ('15400000-0000-4000-8000-000000000002', '15400000-0000-4000-8000-000000000001', 'OSNFSE', 'EMPRESA TESTE OS NFSE LTDA', 'OS NFSE', '33333333000191', '4734735171', 'contato@teste.test'),
       ('15400000-0000-4000-8000-000000000003', '15400000-0000-4000-8000-000000000001', 'OUTRA', 'OUTRA EMPRESA LTDA', 'OUTRA', '44444444000191', null, null);
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, uf, cidade)
values ('15400000-0000-4000-8000-000000000002', '15400000-0000-4000-8000-000000000001', '33333333000191', 'EMPRESA TESTE OS NFSE LTDA', 'OS NFSE', 'SC', 'JOINVILLE'),
       ('15400000-0000-4000-8000-000000000003', '15400000-0000-4000-8000-000000000001', '44444444000191', 'OUTRA EMPRESA LTDA', 'OUTRA', 'SC', 'JOINVILLE')
on conflict (id) do nothing;
insert into c.empresa_fiscal (empresa_id, inscricao_estadual, inscricao_municipal, crt, certificado_validade_em, serie_nfe, serie_dps, proximo_numero_dps, codigo_opcao_simples_nacional, regime_especial_tributacao, prazo_cancelamento_nfse_regra)
values ('15400000-0000-4000-8000-000000000002', '257686835', '152836', 3, current_date + 365, 2, 2, 1, 1, 0, 'MES_EMISSAO'),
       ('15400000-0000-4000-8000-000000000003', '257686836', null, 3, current_date + 365, 2, 2, 1, 1, 0, 'HORAS');
insert into c.empresa_endereco (empresa_id, tipo, cep, logradouro, numero, bairro, cidade, uf, codigo_municipio_ibge)
values ('15400000-0000-4000-8000-000000000002', 'FISCAL', '89219600', 'RUA DONA FRANCISCA', '8300', 'ZONA INDUSTRIAL NORTE', 'JOINVILLE', 'SC', '4209102'),
       ('15400000-0000-4000-8000-000000000003', 'FISCAL', '89219600', 'RUA DONA FRANCISCA', '8300', 'ZONA INDUSTRIAL NORTE', 'JOINVILLE', 'SC', '4209102');
insert into a.usuario (id, auth_user_id, nome, email, ativo)
values ('15400000-0000-4000-8000-000000000011', '15400000-0000-4000-8000-000000000010', 'Teste OS NFS-e', 'os-nfse@example.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo)
values ('15400000-0000-4000-8000-000000000011', '15400000-0000-4000-8000-000000000001', 'ADMIN', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo)
values ('15400000-0000-4000-8000-000000000011', '15400000-0000-4000-8000-000000000002', 'FINANCEIRO', true);
insert into public.user_tenant_context (user_id, tenant_id)
values ('15400000-0000-4000-8000-000000000010', '15400000-0000-4000-8000-000000000001');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
values ('15400000-0000-4000-8000-000000000010', '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002');
insert into f.plano_contas (tenant_id, codigo, nome, natureza, tipo, ativo)
values ('15400000-0000-4000-8000-000000000001', '3.01', 'RECEITA DE SERVICOS', 'CREDITO', 'ANALITICA', true);

-- Tomadores: 915400 Joinville com IM e retencoes decididas; 915401 Tijucas sem
-- retencao; 915402 Joinville sem IM; 915403 Joinville com iss_retido indefinido.
insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social, inscricao_estadual, inscricao_municipal,
  cep, logradouro, numero_endereco, bairro, cidade, uf, pais, indicador_ie, codigo_ibge_municipio, iss_retido, retem_pcc, retem_irrf, retem_inss, email_nfse, optante_simples, iss_substituto_tributario)
values
  (915400, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'TOMADOR JOINVILLE', '84689090000240', 'TOMADOR JOINVILLE S/A', '222222222', '998877',
   '89239270', 'RUA DONA FRANCISCA', '11700', 'PIRABEIRABA', 'JOINVILLE', 'SC', 'BRASIL', '1', '4209102', true, true, true, false, 'fiscal@tomador.test', false, false),
  (915401, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'TOMADOR TIJUCAS', '83475913000272', 'TOMADOR TIJUCAS SA', '333333333', null,
   '88200000', 'BR 101', 'S/N', 'CENTRO', 'TIJUCAS', 'SC', 'BRASIL', '1', '4218004', false, false, false, false, null, false, false),
  -- 915402: optante do Simples e substituto tributario do ISS (ex.: concessionaria) — testa as duas excecoes do contador.
  (915402, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'TOMADOR SEM IM', '03818222000104', 'TOMADOR SEM IM LTDA', '444444444', null,
   '89237780', 'RUA DOS PORTUGUESES', '2240', 'VILA NOVA', 'JOINVILLE', 'SC', 'BRASIL', '1', '4209102', false, false, false, false, null, true, true),
  (915403, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'TOMADOR INDEFINIDO', '78872397000107', 'TOMADOR INDEFINIDO SA', '555555555', '112233',
   '89219600', 'RUA DONA FRANCISCA', '7650', 'ZONA INDUSTRIAL NORTE', 'JOINVILLE', 'SC', 'BRASIL', '1', '4209102', null, false, false, false, null, null, false);

-- Perfis de servico sem valor + fixture provisoria (a migration so semeia empresas ja existentes).
insert into f.perfil_operacao (id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto, crt, item_servico, faixa_automacao, justificativa_faixa, habilitado_producao, vigencia_inicio)
values
  ('15400000-0000-4000-8000-000000000101', '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'SEG-NFSE-1406', 'Servico 14.06', 'NFSE', 'PRESTACAO_SERVICO', 'PRESTACAO DE SERVICO', '3', '14.06', 'REVISAO', null, false, current_date),
  ('15400000-0000-4000-8000-000000000102', '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'SEG-NFSE-1709', 'Servico 17.09', 'NFSE', 'PRESTACAO_SERVICO', 'PRESTACAO DE SERVICO', '3', '17.09', 'REVISAO', null, false, current_date),
  ('15400000-0000-4000-8000-000000000103', '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'SEG-NFSE-0702', 'Servico 07.02', 'NFSE', 'PRESTACAO_SERVICO', 'PRESTACAO DE SERVICO', '3', '07.02', 'BLOQUEADO', 'Obra: aguarda o contador.', false, current_date),
  ('15400000-0000-4000-8000-000000000104', '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'SEG-NFSE-1401', 'Servico 14.01', 'NFSE', 'PRESTACAO_SERVICO', 'PRESTACAO DE SERVICO', '3', '14.01', 'REVISAO', null, false, current_date),
  ('15400000-0000-4000-8000-000000000105', '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'SEG-NFSE-1706', 'Servico 17.06', 'NFSE', 'PRESTACAO_SERVICO', 'PRESTACAO DE SERVICO', '3', '17.06', 'REVISAO', null, false, current_date),
  ('15400000-0000-4000-8000-000000000106', '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'SEG-NFSE-0702-T', 'Servico 07.02 (teste, nao bloqueado)', 'NFSE', 'PRESTACAO_SERVICO', 'PRESTACAO DE SERVICO', '3', '07.02', 'REVISAO', null, false, current_date);
insert into f.tributacao_provisoria_nfse_homologacao (tenant_id, empresa_id, item_servico, codigo_tributacao_nacional, codigo_nbs, descricao_servico_padrao, local_prestacao_regra,
  aliquota_iss, iss_retido_regra, aliquota_pis, aliquota_cofins, retencao_pcc_regra, aliquota_pcc, retencao_irrf_regra, aliquota_irrf, retencao_inss_regra, aliquota_inss,
  texto_sem_retencao, texto_com_retencao, pendencia_contador, fonte)
values
  ('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', '14.06', '140601', '120032900', 'SERVICOS DE INSTALACAO E MONTAGEM', 'CLIENTE', 5, 'POR_TOMADOR', 1.65, 7.6, 'POR_TOMADOR', 4.65, 'POR_TOMADOR', 1.5, 'POR_TOMADOR', 11, 'NAO HA INCIDENCIA DAS RETENCOES FEDERAIS CONFORME IN SRF N 459/2004', null, 'teste', 'teste'),
  ('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', '17.09', '170901', '114044900', 'LAUDO TECNICO', 'SEDE', 5, 'POR_TOMADOR', 1.65, 7.6, 'POR_TOMADOR', 4.65, 'POR_TOMADOR', 1.5, 'NUNCA', 11, 'NAO HA INCIDENCIA DAS RETENCOES FEDERAIS CONFORME IN SRF N 459/2004',
   'PARA OS SERVICOS DE LAUDOS E PERICIAS, DEVERA SER RETIDO IRRF A ALIQUOTA DE 1,5% E CRF A ALIQUOTA DE 4,65% (PIS 0,65%; COFINS 3,0%; CSLL 1%). TRIBUTOS APROXIMADOS LEI 12.741/2012: {VTOTTRIB}', 'teste', 'teste');
insert into f.nfse_tributos_aproximados (tenant_id, empresa_id, item_servico, vigencia_inicio, federal_pct, estadual_pct, municipal_pct, fonte)
values ('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', '17.09', date '2026-08-01', 13.45, 0, 3.64, 'teste'),
       ('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', '14.01', date '2026-08-01', 13.45, 0, 4.69, 'teste');
insert into f.nfse_aliquota_iss (tenant_id, empresa_id, item_servico, municipio_ibge, aliquota, fonte)
values ('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', '14.01', '4209102', 5, 'teste'),
       ('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', '14.01', '4218004', 2, 'teste: se a incidencia fosse no local, Tijucas cobraria 2%'),
       ('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', '07.02', '4218004', 3, 'teste: obra em Tijucas a 3%');

insert into public.ordens_servico (id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id, empresa_id, status_fluxo, tipo_documento, codigo, numero_doc, descricao_servico, orcado, pedido_compra)
values
  (915400, 'OS-NFSE-1', 'TOMADOR JOINVILLE', 915400, 'concluida', 915400, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'concluida', 'OS', 'OS-NFSE-001', 1, 'LAUDO NR-12 ANALISE DE RISCO', 10000, '136785'),
  (915401, 'OS-NFSE-2', 'TOMADOR JOINVILLE', 915400, 'concluida', 915401, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'concluida', 'OS', 'OS-NFSE-002', 2, 'LAUDO COMPLEMENTAR', 2000, null),
  (915402, 'OS-NFSE-3', 'TOMADOR TIJUCAS', 915401, 'em_andamento', 915402, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'em_andamento', 'OS', 'OS-NFSE-003', 3, 'INSTALACAO ELETRICA DA LINHA 3', 3000, '1306628'),
  (915406, 'OS-NFSE-6', 'TOMADOR TIJUCAS', 915401, 'concluida', 915406, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'concluida', 'OS', 'OS-NFSE-006', 7, 'MANUTENCAO DO PAINEL', 3500, '1306700'),
  (915403, 'OS-NFSE-4', 'TOMADOR SEM IM', 915402, 'concluida', 915403, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'concluida', 'OS', 'OS-NFSE-004', 4, 'ASSESSORIA', 1000, null),
  (915404, 'OS-NFSE-5', 'TOMADOR INDEFINIDO', 915403, 'concluida', 915404, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'concluida', 'OS', 'OS-NFSE-005', 5, 'LAUDO', 1000, null),
  (915405, 'OS-OUTRA', 'OUTRA', null, 'concluida', 915405, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000003', 'concluida', 'OS', 'OS-OUTRA-001', 6, 'OS DA OUTRA', 500, null);

-- ---------------------------------------------------------------------------
-- Como o usuario FINANCEIRO da empresa
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '15400000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"15400000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;

create temp table ctx (sol_a uuid, sol_b uuid, sol_c uuid, sol_d uuid, sol_e uuid, sol_f uuid, sol_sub uuid, doc_a uuid, doc_b uuid, doc_c uuid, doc_sub uuid, chave_b text);
insert into ctx default values;

do $perfil_bloqueado$
begin
  begin
    perform f.fn_solicitacao_faturamento_criar_os_servico('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002',
      '15400000-0000-4000-8000-000000000103', jsonb_build_array(jsonb_build_object('os_id', 915400, 'descricao_servico', 'OBRA', 'valor_servico', 100)));
    raise exception 'Perfil 07.02 bloqueado foi aceito.';
  exception when sqlstate '22023' then
    if sqlerrm not like '%bloqueado%' then raise exception 'Erro inesperado: %', sqlerrm; end if;
  end;
  begin
    perform f.fn_solicitacao_faturamento_criar_os_servico('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002',
      '15400000-0000-4000-8000-000000000102', jsonb_build_array(jsonb_build_object('os_id', 915400, 'descricao_servico', 'A', 'valor_servico', 100), jsonb_build_object('os_id', 915402, 'descricao_servico', 'B', 'valor_servico', 100)));
    raise exception 'Duas OS de tomadores diferentes foram aceitas.';
  exception when sqlstate '22023' then
    if sqlerrm not like '%outro tomador%' then raise exception 'Erro inesperado: %', sqlerrm; end if;
  end;
end;
$perfil_bloqueado$;

-- A: 17.09 com ISS retido, IRRF e PCC (tomador de Joinville com IM).
update ctx set sol_a = f.fn_solicitacao_faturamento_criar_os_servico('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002',
  '15400000-0000-4000-8000-000000000102', jsonb_build_array(jsonb_build_object('os_id', 915400, 'descricao_servico', 'LAUDO NR-12 ANALISE DE RISCO', 'valor_servico', 6000)));
do $conferir_a$
declare v_r jsonb; v_si f.solicitacao_item%rowtype; v_sf f.solicitacao_faturamento%rowtype; v_s record; v_serv jsonb;
begin
  v_r := f.fn_os_nfse_conferir_homologacao((select sol_a from ctx),
    '{"pagamento_forma":"15","pagamento_indicador":1,"pagamento_parcelas":[{"dias":21}],"observacao":"Conforme proposta 77"}'::jsonb);
  if coalesce((v_r->>'ok')::boolean, false) is not true then raise exception 'Conferencia A devolveu pendencias: %', v_r; end if;
  select * into v_si from f.solicitacao_item where solicitacao_id = (select sol_a from ctx);
  if v_si.codigo_tributacao_nacional <> '170901' or v_si.codigo_nbs <> '114044900' or v_si.aliquota_iss <> 5 or v_si.iss_retido is not true
     or v_si.aliquota_irrf <> 1.5 or v_si.aliquota_pcc <> 4.65 or v_si.aliquota_inss is not null or v_si.local_prestacao_ibge <> '4209102'
     or v_si.cst_ibs_cbs <> '000' or v_si.cclass_trib <> '000001' or v_si.tributacao_fonte <> 'FIXTURE_HOMOLOGACAO' or v_si.modelo <> 'NFSE' then
    raise exception 'Linha A nao recebeu a fixture 17.09: %', row_to_json(v_si);
  end if;
  select * into v_sf from f.solicitacao_faturamento where id = (select sol_a from ctx);
  v_serv := v_sf.operacao_snapshot->'servico';
  if v_sf.iss_retido is not true or v_sf.retem_pcc is not true or v_sf.retem_irrf is not true or v_sf.retem_inss is not false
     or v_sf.municipio_prestacao_ibge <> '4209102' or v_sf.data_competencia <> current_date or v_sf.snapshot_cadastro_em is null
     or v_sf.destino_uf_confirmada <> 'SC' or v_sf.pedido_cliente <> '136785' then
    raise exception 'Cabecalho A incompleto: %', row_to_json(v_sf);
  end if;
  if (v_serv->>'valor_bruto')::numeric <> 6000 or (v_serv->>'valor_iss')::numeric <> 300 or (v_serv->>'valor_irrf')::numeric <> 90
     or (v_serv->>'valor_pcc')::numeric <> 279 or (v_serv->>'valor_liquido')::numeric <> 5331 or jsonb_array_length(v_serv->'retencoes') <> 5 then
    raise exception 'Valores A errados: %', v_serv;
  end if;
  -- {VTOTTRIB} = 6.000 x (13,45% + 3,64%) = R$ 1.025,40 (tabela por subitem, contador 06/09/2026).
  if v_serv->>'descricao_servico' <> 'LAUDO NR-12 ANALISE DE RISCO. PEDIDO DE COMPRA: 136785. VENCIMENTO: 21 DDL. OS OS-NFSE-1. "PARA OS SERVICOS DE LAUDOS E PERICIAS, DEVERA SER RETIDO IRRF A ALIQUOTA DE 1,5% E CRF A ALIQUOTA DE 4,65% (PIS 0,65%; COFINS 3,0%; CSLL 1%). TRIBUTOS APROXIMADOS LEI 12.741/2012: R$ 1.025,40" Conforme proposta 77.' then
    raise exception 'Discriminacao A fora do padrao: %', v_serv->>'descricao_servico';
  end if;
  if (v_serv->>'tributos_aprox_valor')::numeric <> 1025.40 then raise exception 'tributos_aprox_valor A errado: %', v_serv->>'tributos_aprox_valor'; end if;
  -- vTotTrib vem da tabela por subitem (17.09: 13,45% federal, 3,64% municipal), nao do calculo.
  if (v_serv->>'tributos_aprox_federal_pct')::numeric <> 13.45 or (v_serv->>'tributos_aprox_municipal_pct')::numeric <> 3.64 or (v_serv->>'tributos_aprox_estadual_pct')::numeric <> 0 then
    raise exception 'vTotTrib A nao veio da tabela: %', v_serv;
  end if;
  -- IBS/CBS: base = servico - ISS (6000 - 300 = 5700); IBS UF 0,10% = 5,70; CBS 0,90% = 51,30.
  if (v_serv->'ibs_cbs'->>'base')::numeric <> 5700 or (v_serv->'ibs_cbs'->>'ibs_uf')::numeric <> 5.70 or (v_serv->'ibs_cbs'->>'cbs')::numeric <> 51.30 then
    raise exception 'IBS/CBS A errado: %', v_serv->'ibs_cbs';
  end if;
  if v_sf.emitente_snapshot->>'inscricao_municipal' <> '152836' or (v_sf.emitente_snapshot->>'codigo_opcao_simples_nacional')::int <> 1
     or v_sf.destinatario_snapshot->>'inscricao_municipal' <> '998877' or v_sf.destinatario_snapshot->>'email' <> 'fiscal@tomador.test' then
    raise exception 'Snapshots A incompletos: % / %', v_sf.emitente_snapshot, v_sf.destinatario_snapshot;
  end if;
  select * into v_s from f.fn_os_saldo_a_faturar('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 915400);
  if v_s.valor_reservado <> 6000 or v_s.saldo <> 4000 then raise exception 'Saldo apos conferencia A: %', row_to_json(v_s); end if;
end;
$conferir_a$;

-- B: 14.06 na planta do cliente (Tijucas), sem retencao, a vista.
update ctx set sol_b = f.fn_solicitacao_faturamento_criar_os_servico('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002',
  '15400000-0000-4000-8000-000000000101', jsonb_build_array(jsonb_build_object('os_id', 915402, 'descricao_servico', 'INSTALACAO ELETRICA DA LINHA 3', 'valor_servico', 3000)));
do $conferir_b$
declare v_r jsonb; v_sf f.solicitacao_faturamento%rowtype; v_serv jsonb;
begin
  v_r := f.fn_os_nfse_conferir_homologacao((select sol_b from ctx), '{"pagamento_forma":"17","pagamento_indicador":0}'::jsonb);
  if coalesce((v_r->>'ok')::boolean, false) is not true then raise exception 'Conferencia B devolveu pendencias: %', v_r; end if;
  select * into v_sf from f.solicitacao_faturamento where id = (select sol_b from ctx);
  v_serv := v_sf.operacao_snapshot->'servico';
  if v_sf.municipio_prestacao_ibge <> '4218004' or v_sf.iss_retido is not false or (v_serv->>'valor_liquido')::numeric <> 3000 or jsonb_array_length(v_serv->'retencoes') <> 0 then
    raise exception 'Conferencia B errada: %', row_to_json(v_sf);
  end if;
  -- A vista: o segmento VENCIMENTO some; a frase legal fecha o texto.
  if v_serv->>'descricao_servico' <> 'INSTALACAO ELETRICA DA LINHA 3. PEDIDO DE COMPRA: 1306628. OS OS-NFSE-3. "NAO HA INCIDENCIA DAS RETENCOES FEDERAIS CONFORME IN SRF N 459/2004"' then
    raise exception 'Discriminacao B fora do padrao: %', v_serv->>'descricao_servico';
  end if;
  -- 14.06: ISS incide na sede do prestador mesmo com prestacao em Tijucas (LC 116 art. 3 caput).
  if v_serv->>'municipio_incidencia_iss' <> '4209102' or (v_serv->>'aliquota_iss')::numeric <> 5 then
    raise exception 'Incidencia do ISS no 14.06 errada: %', v_serv;
  end if;
  if not exists (select 1 from jsonb_array_elements(v_r->'avisos') a where a->>'campo' = 'email_nfse')
     or not exists (select 1 from jsonb_array_elements(v_r->'avisos') a where a->>'campo' = 'status_fluxo') then
    raise exception 'Avisos B (email_nfse, OS em andamento) ausentes: %', v_r->'avisos';
  end if;
  -- Municipio de prestacao editavel na tela.
  v_r := f.fn_os_nfse_conferir_homologacao((select sol_b from ctx), '{"pagamento_forma":"17","pagamento_indicador":0,"municipio_prestacao_ibge":"4209102"}'::jsonb);
  if (select municipio_prestacao_ibge from f.solicitacao_faturamento where id = (select sol_b from ctx)) <> '4209102' then
    raise exception 'Municipio de prestacao editado nao foi gravado.';
  end if;
  v_r := f.fn_os_nfse_conferir_homologacao((select sol_b from ctx), '{"pagamento_forma":"17","pagamento_indicador":0}'::jsonb);
end;
$conferir_b$;

-- C: duas OS do mesmo tomador numa NFS-e; cada linha reserva a propria OS.
update ctx set sol_c = f.fn_solicitacao_faturamento_criar_os_servico('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002',
  '15400000-0000-4000-8000-000000000102', jsonb_build_array(
    jsonb_build_object('os_id', 915400, 'descricao_servico', 'LAUDO ADICIONAL', 'valor_servico', 1000),
    jsonb_build_object('os_id', 915401, 'descricao_servico', 'LAUDO COMPLEMENTAR', 'valor_servico', 1500)));
do $conferir_c$
declare v_r jsonb; v_s1 record; v_s2 record; v_serv jsonb;
begin
  v_r := f.fn_os_nfse_conferir_homologacao((select sol_c from ctx), '{"pagamento_forma":"15","pagamento_indicador":1,"pagamento_parcelas":[{"dias":14,"valor":1000},{"dias":28,"valor":1132.75}]}'::jsonb);
  if coalesce((v_r->>'ok')::boolean, false) is not true then raise exception 'Conferencia C devolveu pendencias: %', v_r; end if;
  v_serv := (select operacao_snapshot->'servico' from f.solicitacao_faturamento where id = (select sol_c from ctx));
  if (v_serv->>'valor_bruto')::numeric <> 2500 or (v_serv->>'valor_liquido')::numeric <> 2221.25 or jsonb_array_length(v_serv->'os_numeros') <> 2 then
    raise exception 'Valores C errados: %', v_serv;
  end if;
  if v_serv->>'descricao_servico' not like 'LAUDO ADICIONAL; LAUDO COMPLEMENTAR. PEDIDO DE COMPRA: 136785. VENCIMENTO: 14/28 DDL. OS OS-NFSE-1/OS-NFSE-2. "PARA OS SERVICOS DE LAUDOS%' then
    raise exception 'Discriminacao C fora do padrao: %', v_serv->>'descricao_servico';
  end if;
  select * into v_s1 from f.fn_os_saldo_a_faturar('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 915400);
  select * into v_s2 from f.fn_os_saldo_a_faturar('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 915401);
  if v_s1.valor_reservado <> 7000 or v_s1.saldo <> 3000 or v_s2.valor_reservado <> 1500 or v_s2.saldo <> 500 then
    raise exception 'Reserva por OS errada: % / %', row_to_json(v_s1), row_to_json(v_s2);
  end if;
end;
$conferir_c$;

-- D: tomador de Joinville sem IM bloqueia antes da Focus, nomeando campo e rota.
update ctx set sol_d = f.fn_solicitacao_faturamento_criar_os_servico('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002',
  '15400000-0000-4000-8000-000000000102', jsonb_build_array(jsonb_build_object('os_id', 915403, 'descricao_servico', 'ASSESSORIA', 'valor_servico', 500)));
-- E: iss_retido indefinido bloqueia; override sem justificativa bloqueia; com justificativa passa.
update ctx set sol_e = f.fn_solicitacao_faturamento_criar_os_servico('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002',
  '15400000-0000-4000-8000-000000000102', jsonb_build_array(jsonb_build_object('os_id', 915404, 'descricao_servico', 'LAUDO', 'valor_servico', 500)));
-- F: valor acima do saldo da OS 915401 (saldo 500) bloqueia.
update ctx set sol_f = f.fn_solicitacao_faturamento_criar_os_servico('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002',
  '15400000-0000-4000-8000-000000000102', jsonb_build_array(jsonb_build_object('os_id', 915401, 'descricao_servico', 'EXCEDENTE', 'valor_servico', 600)));
do $bloqueios$
declare v_r jsonb;
begin
  -- Tomador de Joinville sem IM: aviso com rota (as NFS-e reais nunca enviam a IM do tomador; matriz de 05/09/2026).
  v_r := f.fn_os_nfse_conferir_homologacao((select sol_d from ctx), '{"pagamento_forma":"15","pagamento_indicador":1}'::jsonb);
  if not (v_r->>'ok')::boolean or not exists (select 1 from jsonb_array_elements(v_r->'avisos') p where p->>'campo' = 'inscricao_municipal' and p->>'rota' = '/clientes/cadastro-fiscal?cliente_id=915402') then
    raise exception 'Tomador de Joinville sem IM deveria passar com aviso e rota: %', v_r;
  end if;
  v_r := f.fn_os_nfse_conferir_homologacao((select sol_e from ctx), '{"pagamento_forma":"15","pagamento_indicador":1}'::jsonb);
  if (v_r->>'ok')::boolean or not exists (select 1 from jsonb_array_elements(v_r->'pendencias') p where p->>'campo' = 'iss_retido') then
    raise exception 'iss_retido indefinido nao bloqueou: %', v_r;
  end if;
  v_r := f.fn_os_nfse_conferir_homologacao((select sol_e from ctx), '{"pagamento_forma":"15","pagamento_indicador":1,"iss_retido":false}'::jsonb);
  if (v_r->>'ok')::boolean or not exists (select 1 from jsonb_array_elements(v_r->'pendencias') p where p->>'campo' = 'retencao_justificativa') then
    raise exception 'Override sem justificativa nao bloqueou: %', v_r;
  end if;
  v_r := f.fn_os_nfse_conferir_homologacao((select sol_e from ctx), '{"pagamento_forma":"15","pagamento_indicador":1,"iss_retido":false,"retencao_justificativa":"Tomador confirmou por e-mail que nao retem ISS"}'::jsonb);
  if coalesce((v_r->>'ok')::boolean, false) is not true then raise exception 'Override com justificativa nao passou: %', v_r; end if;
  if (select operacao_snapshot->'servico'->>'descricao_servico' from f.solicitacao_faturamento where id = (select sol_e from ctx)) not like '%RETENCAO AJUSTADA: Tomador confirmou%' then
    raise exception 'Justificativa nao foi para a discriminacao.';
  end if;
  if (select iss_retido from public.clientes where id = 915403) is not null then
    raise exception 'Override gravou clientes.iss_retido por deducao.';
  end if;
  v_r := f.fn_os_nfse_conferir_homologacao((select sol_f from ctx), '{"pagamento_forma":"15","pagamento_indicador":1}'::jsonb);
  if (v_r->>'ok')::boolean or not exists (select 1 from jsonb_array_elements(v_r->'pendencias') p where p->>'mensagem' like '%acima do saldo%') then
    raise exception 'Valor acima do saldo nao bloqueou: %', v_r;
  end if;
  perform f.fn_solicitacao_nfe_cancelar_rascunho((select sol_d from ctx), 'Rascunho D descartado no teste');
  perform f.fn_solicitacao_nfe_cancelar_rascunho((select sol_e from ctx), 'Rascunho E descartado no teste');
  perform f.fn_solicitacao_nfe_cancelar_rascunho((select sol_f from ctx), 'Rascunho F descartado no teste');
end;
$bloqueios$;

-- Regras dos perfis de servico (06/09/2026): "MAO DE OBRA" proibido; dispensa <= R$ 10; competencia
-- do mes anterior; IBS/CBS no centavo (nota 32: 3.500 -> 3.325; 3,32; 29,92); 14.01 com CRF por padrao,
-- excecao de conserto isolado e tomador do Simples; campos travados barram a producao; NBS x subitem; 17.06.
do $regras_perfil$
declare v_sol uuid; v_sol2 uuid; v_r jsonb; v_sf f.solicitacao_faturamento%rowtype; v_serv jsonb; v_msg text;
begin
  -- "MAO DE OBRA" (com e sem til/hifen) na descricao bloqueia antes da Focus.
  v_sol := f.fn_solicitacao_faturamento_criar_os_servico('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002',
    '15400000-0000-4000-8000-000000000102', jsonb_build_array(jsonb_build_object('os_id', 915403, 'descricao_servico', 'SERVICOS DE MAO DE OBRA ELETRICISTA', 'valor_servico', 100)));
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol, '{"pagamento_forma":"15","pagamento_indicador":1}'::jsonb);
  if (v_r->>'ok')::boolean or not exists (select 1 from jsonb_array_elements(v_r->'pendencias') p where p->>'campo' = 'descricao_servico' and p->>'mensagem' like '%MAO DE OBRA%') then
    raise exception 'MAO DE OBRA na descricao nao bloqueou: %', v_r;
  end if;
  perform f.fn_solicitacao_nfe_cancelar_rascunho(v_sol, 'Rascunho MAO DE OBRA descartado no teste');
  v_sol := f.fn_solicitacao_faturamento_criar_os_servico('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002',
    '15400000-0000-4000-8000-000000000102', jsonb_build_array(jsonb_build_object('os_id', 915403, 'descricao_servico', 'Mão-de-obra de manutencao', 'valor_servico', 100)));
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol, '{"pagamento_forma":"15","pagamento_indicador":1}'::jsonb);
  if (v_r->>'ok')::boolean then raise exception 'Mao-de-obra com til e hifen passou: %', v_r; end if;
  -- ... e tambem quando entra pela observacao ou pelo template do tomador.
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol, '{"pagamento_forma":"15","pagamento_indicador":1,"observacao":"inclui mao de obra"}'::jsonb);
  if (v_r->>'ok')::boolean or not exists (select 1 from jsonb_array_elements(v_r->'pendencias') p where p->>'campo' = 'observacao') then
    raise exception 'MAO DE OBRA na observacao nao bloqueou: %', v_r;
  end if;
  perform f.fn_solicitacao_nfe_cancelar_rascunho(v_sol, 'Rascunho descartado no teste');
  if f.fn_nfse_texto_proibido('Fornecimento de MAO DE OBRA') is null or f.fn_nfse_texto_proibido('Mão de Obra') is null or f.fn_nfse_texto_proibido('mao-de-obra') is null
     or f.fn_nfse_texto_proibido('MANUTENCAO DE PAINEL') is not null then
    raise exception 'fn_nfse_texto_proibido errada.';
  end if;

  -- Dispensa de retencao <= R$ 10,00: 17.09 de R$ 500 -> IRRF 7,50 dispensado; CRF 23,25 e ISS 25,00 ficam.
  -- Competencia do mes anterior e aceita; no futuro nao.
  v_sol := f.fn_solicitacao_faturamento_criar_os_servico('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002',
    '15400000-0000-4000-8000-000000000102', jsonb_build_array(jsonb_build_object('os_id', 915400, 'descricao_servico', 'LAUDO SIMPLES', 'valor_servico', 500)));
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol, jsonb_build_object('pagamento_forma', '15', 'pagamento_indicador', 1, 'data_competencia', (current_date + 1)::text));
  if (v_r->>'ok')::boolean or not exists (select 1 from jsonb_array_elements(v_r->'pendencias') p where p->>'campo' = 'data_competencia') then
    raise exception 'Competencia futura nao bloqueou: %', v_r;
  end if;
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol, jsonb_build_object('pagamento_forma', '15', 'pagamento_indicador', 1, 'data_competencia', (date_trunc('month', current_date) - interval '1 month')::date::text));
  if coalesce((v_r->>'ok')::boolean, false) is not true then raise exception 'Dispensa/competencia devolveu pendencias: %', v_r; end if;
  select * into v_sf from f.solicitacao_faturamento where id = v_sol;
  v_serv := v_sf.operacao_snapshot->'servico';
  if v_sf.data_competencia <> (date_trunc('month', current_date) - interval '1 month')::date then raise exception 'Competencia do mes anterior nao gravada: %', v_sf.data_competencia; end if;
  if v_sf.retem_irrf is not false or (v_serv->>'valor_irrf')::numeric <> 0 or v_sf.retem_pcc is not true or (v_serv->>'valor_pcc')::numeric <> 23.25
     or (v_serv->>'valor_iss')::numeric <> 25 or (v_serv->>'valor_liquido')::numeric <> 451.75
     or not exists (select 1 from jsonb_array_elements(v_r->'avisos') a where a->>'campo' = 'retem_irrf' and a->>'mensagem' like '%10,00%') then
    raise exception 'Dispensa <= R$ 10 errada: % / %', v_serv, v_r->'avisos';
  end if;
  if (select iss_retido from public.clientes where id = 915400) is not true or (select retem_irrf from public.clientes where id = 915400) is not true then
    raise exception 'Dispensa alterou o cadastro do tomador.';
  end if;
  perform f.fn_solicitacao_nfe_cancelar_rascunho(v_sol, 'Rascunho dispensa descartado no teste');

  -- IBS/CBS no centavo (nota 32 real): 3.500 - ISS 175 = 3.325; IBS UF 3,32; CBS 29,92; total 33,24 (meio-par).
  v_sol := f.fn_solicitacao_faturamento_criar_os_servico('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002',
    '15400000-0000-4000-8000-000000000101', jsonb_build_array(jsonb_build_object('os_id', 915406, 'descricao_servico', 'MANUTENCAO DO PAINEL', 'valor_servico', 3500)));
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol, '{"pagamento_forma":"15","pagamento_indicador":1,"pagamento_parcelas":[{"dias":28}]}'::jsonb);
  if coalesce((v_r->>'ok')::boolean, false) is not true then raise exception 'Conferencia IBS/CBS devolveu pendencias: %', v_r; end if;
  v_serv := v_r->'previa'->'ibs_cbs';
  if (v_serv->>'base')::numeric <> 3325 or (v_serv->>'ibs_uf')::numeric <> 3.32 or (v_serv->>'ibs_mun')::numeric <> 0 or (v_serv->>'cbs')::numeric <> 29.92 or (v_serv->>'total')::numeric <> 33.24 then
    raise exception 'IBS/CBS da nota 32 nao reproduzido: %', v_serv;
  end if;
  -- Nota 37 real (07.02, 42.298,75; ISS 3% = 1.268,96): base 41.029,79; IBS 41,03; CBS 369,27.
  if f.fn_round_half_even(41029.79 * 0.10 / 100) <> 41.03 or f.fn_round_half_even(41029.79 * 0.90 / 100) <> 369.27 or f.fn_round_half_even(42298.75 * 3 / 100, 2) <> 1268.96 then
    raise exception 'Arredondamento da nota 37 errado: % / %', f.fn_round_half_even(41029.79 * 0.10 / 100), f.fn_round_half_even(41029.79 * 0.90 / 100);
  end if;
  perform f.fn_solicitacao_nfe_cancelar_rascunho(v_sol, 'Rascunho IBS/CBS descartado no teste');

  -- NBS x subitem e 17.06 na revisao do perfil.
  begin
    perform f.fn_perfil_operacao_nfse_revisar('15400000-0000-4000-8000-000000000101',
      '{"codigo_tributacao_nacional":"140601","codigo_nbs":"101026900","local_prestacao_regra":"CLIENTE","tributacao_iss":1,"aliquota_iss":5,"iss_retido_regra":"NUNCA","retencao_pcc_regra":"NUNCA","retencao_irrf_regra":"NUNCA","retencao_inss_regra":"NUNCA","cst_pis":"01","cst_cofins":"01","cst_ibs_cbs":"000","cclass_trib":"000001","ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9,"codigo_indicador_operacao":"050103"}'::jsonb,
      'NBS de outro capitulo deve ser recusado');
    raise exception 'NBS 1.0102.69.00 aceito no 14.06.';
  exception when sqlstate '22023' then
    if sqlerrm not like '%NBS%' then raise exception 'Erro inesperado: %', sqlerrm; end if;
  end;
  if f.fn_nfse_nbs_compativel('14.06', '120032900') is not true or f.fn_nfse_nbs_compativel('14.06', '101026900') is not false
     or f.fn_nfse_nbs_compativel('17.09', '114044900') is not true or f.fn_nfse_nbs_compativel('07.02', '101069000') is not true or f.fn_nfse_nbs_compativel('07.02', '120015000') is not false then
    raise exception 'fn_nfse_nbs_compativel errada.';
  end if;
  begin
    perform f.fn_perfil_operacao_nfse_revisar('15400000-0000-4000-8000-000000000105',
      '{"codigo_tributacao_nacional":"170601","local_prestacao_regra":"SEDE","tributacao_iss":1,"aliquota_iss":5,"iss_retido_regra":"NUNCA","retencao_pcc_regra":"NUNCA","retencao_irrf_regra":"NUNCA","retencao_inss_regra":"NUNCA","cst_pis":"01","cst_cofins":"01","cst_ibs_cbs":"000","cclass_trib":"000001","ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9}'::jsonb,
      'Tentativa de revisar o 17.06 deve falhar');
    raise exception 'Perfil 17.06 foi revisado.';
  exception when sqlstate '22023' then
    if sqlerrm not like '%17.06%' then raise exception 'Erro inesperado: %', sqlerrm; end if;
  end;

  -- 14.01 revisado: CRF SEMPRE (4,65%), excecao de conserto isolado, ISS travado (CONFERIR_08_09), incidencia no prestador.
  -- Frases do contador (06/09/2026): a da regra geral (com CRF) em texto_complementar; a generica sem retencao em texto_sem_retencao.
  v_r := f.fn_perfil_operacao_nfse_revisar('15400000-0000-4000-8000-000000000104',
    '{"codigo_tributacao_nacional":"140101","codigo_nbs":"120015000","descricao_servico_padrao":"MANUTENCAO CORRETIVA","local_prestacao_regra":"CLIENTE","incidencia_iss_regra":"PRESTADOR","tributacao_iss":1,"aliquota_iss":5,"iss_retido_regra":"NUNCA","retencao_pcc_regra":"SEMPRE","aliquota_pcc":4.65,"retencao_irrf_regra":"NUNCA","retencao_inss_regra":"NUNCA","excecao_conserto_isolado":true,"texto_complementar":"Serviço sujeito à retenção de CRF (4,65%) conforme IN RFB nº 2.141/2023.","texto_sem_retencao":"Serviço não sujeito à retenção de PIS/COFINS/CSLL, conforme IN RFB nº 2.141/2023.","cst_pis":"01","cst_cofins":"01","aliquota_pis":1.65,"aliquota_cofins":7.6,"cst_ibs_cbs":"000","cclass_trib":"000001","ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9,"codigo_indicador_operacao":"050103","campos_conferir":[{"campo":"iss_retido_regra","motivo":"CONFERIR_08_09: nenhuma nota real de 14.01 com ISS retido","prazo":"2026-09-08"}]}'::jsonb,
    'Perfil 14.01 conforme estudo das notas 31-32 de agosto/2026');
  if jsonb_array_length(v_r->'campos_conferir') <> 1 then raise exception 'campos_conferir nao gravado: %', v_r; end if;
  -- OS de Tijucas: CRF entra por padrao (regra SEMPRE, cadastro do tomador diz que nao retem); ISS incide em Joinville (5%), nao em Tijucas (2%).
  v_sol := f.fn_solicitacao_faturamento_criar_os_servico('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002',
    '15400000-0000-4000-8000-000000000104', jsonb_build_array(jsonb_build_object('os_id', 915406, 'descricao_servico', 'MANUTENCAO DO PAINEL', 'valor_servico', 3500)));
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol, '{"pagamento_forma":"15","pagamento_indicador":1,"pagamento_parcelas":[{"dias":28}]}'::jsonb);
  if coalesce((v_r->>'ok')::boolean, false) is not true then raise exception 'Conferencia 14.01 devolveu pendencias: %', v_r; end if;
  select * into v_sf from f.solicitacao_faturamento where id = v_sol;
  v_serv := v_sf.operacao_snapshot->'servico';
  if v_sf.retem_pcc is not true or (v_serv->>'valor_pcc')::numeric <> 162.75
     or (v_serv->>'aliquota_iss')::numeric <> 5 or v_serv->>'municipio_incidencia_iss' <> '4209102' or v_sf.municipio_prestacao_ibge <> '4218004'
     or (v_serv->>'tributos_aprox_municipal_pct')::numeric <> 4.69 or (v_serv->>'valor_liquido')::numeric <> 3337.25
     or (select tributacao_fonte from f.solicitacao_item where solicitacao_id = v_sol) <> 'PERFIL' then
    raise exception 'CRF padrao do 14.01 errada: % / %', row_to_json(v_sf), v_serv;
  end if;
  if not exists (select 1 from jsonb_array_elements(v_r->'avisos') a where a->>'campo' = 'campos_conferir') then raise exception 'Aviso de campos travados ausente: %', v_r->'avisos'; end if;
  -- Com CRF retida, a frase da nota e a da regra geral (IN RFB 2.141/2023), nunca a de "nao incidencia".
  if v_serv->>'descricao_servico' not like '%"Serviço sujeito à retenção de CRF (4,65%) conforme IN RFB nº 2.141/2023."%' then
    raise exception 'Frase da regra geral do 14.01 ausente: %', v_serv->>'descricao_servico';
  end if;
  -- Conserto isolado marcado na OS: CRF cai e a frase legal passa a ser a do conserto isolado (art. 2 §2 II).
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol, '{"pagamento_forma":"15","pagamento_indicador":1,"pagamento_parcelas":[{"dias":28}],"conserto_isolado":true}'::jsonb);
  select * into v_sf from f.solicitacao_faturamento where id = v_sol;
  if v_sf.retem_pcc is not false or (v_sf.operacao_snapshot->'servico'->>'valor_pcc')::numeric <> 0 or (select conserto_isolado from public.ordens_servico where id = 915406) is not true
     or v_sf.operacao_snapshot->'servico'->>'descricao_servico' not like '%Serviço de conserto isolado não sujeito à retenção de PIS/COFINS/CSLL, conforme art. 2º, § 2º, inciso II, da IN RFB nº 2.141/2023.%'
     or v_sf.operacao_snapshot->'servico'->>'motivo_dispensa_pcc' <> 'CONSERTO_ISOLADO' then
    raise exception 'Excecao de conserto isolado nao aplicada: %', row_to_json(v_sf);
  end if;
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol, '{"pagamento_forma":"15","pagamento_indicador":1,"pagamento_parcelas":[{"dias":28}],"conserto_isolado":false}'::jsonb);
  if (select retem_pcc from f.solicitacao_faturamento where id = v_sol) is not true then raise exception 'Desmarcar conserto isolado nao devolveu a CRF.'; end if;
  perform f.fn_solicitacao_nfe_cancelar_rascunho(v_sol, 'Rascunho 14.01 descartado no teste');
  -- Tomador optante do Simples: CRF nao se aplica, com aviso.
  v_sol2 := f.fn_solicitacao_faturamento_criar_os_servico('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002',
    '15400000-0000-4000-8000-000000000104', jsonb_build_array(jsonb_build_object('os_id', 915403, 'descricao_servico', 'MANUTENCAO CORRETIVA DO CLP', 'valor_servico', 300)));
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol2, '{"pagamento_forma":"15","pagamento_indicador":1,"pagamento_parcelas":[{"dias":28}]}'::jsonb);
  if coalesce((v_r->>'ok')::boolean, false) is not true then raise exception 'Conferencia Simples devolveu pendencias: %', v_r; end if;
  if (select retem_pcc from f.solicitacao_faturamento where id = v_sol2) is not false
     or not exists (select 1 from jsonb_array_elements(v_r->'avisos') a where a->>'campo' = 'retem_pcc' and a->>'mensagem' like '%Simples%') then
    raise exception 'CRF cobrada de tomador do Simples: %', v_r;
  end if;
  select * into v_sf from f.solicitacao_faturamento where id = v_sol2;
  if v_sf.operacao_snapshot->'servico'->>'descricao_servico' not like '%Tomador optante pelo Simples Nacional: dispensada a retenção%' or v_sf.operacao_snapshot->'servico'->>'motivo_dispensa_pcc' <> 'SIMPLES' then
    raise exception 'Frase do Simples ausente: %', v_sf.operacao_snapshot->'servico'->>'descricao_servico';
  end if;
  -- Substituto tributario do ISS (contador 06/09/2026): regra NUNCA do 14.01, mas o tomador 915402 retem por lei.
  if v_sf.iss_retido is not true or (v_sf.operacao_snapshot->'servico'->>'iss_substituto_tributario')::boolean is not true
     or (v_sf.operacao_snapshot->'servico'->>'valor_liquido')::numeric <> 285
     or not exists (select 1 from jsonb_array_elements(v_r->'avisos') a where a->>'campo' = 'iss_substituto_tributario') then
    raise exception 'Substituto tributario do ISS nao aplicado: % / %', row_to_json(v_sf), v_r->'avisos';
  end if;
  -- A tela pode desligar o substituto com justificativa; sem justificativa bloqueia.
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol2, '{"pagamento_forma":"15","pagamento_indicador":1,"pagamento_parcelas":[{"dias":28}],"iss_retido":false}'::jsonb);
  if (v_r->>'ok')::boolean or not exists (select 1 from jsonb_array_elements(v_r->'pendencias') p where p->>'campo' = 'retencao_justificativa') then
    raise exception 'Desligar o substituto sem justificativa passou: %', v_r;
  end if;
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol2, '{"pagamento_forma":"15","pagamento_indicador":1,"pagamento_parcelas":[{"dias":28}],"iss_retido":false,"retencao_justificativa":"Tomador deixou de ser substituto em 2026"}'::jsonb);
  if coalesce((v_r->>'ok')::boolean, false) is not true or (select iss_retido from f.solicitacao_faturamento where id = v_sol2) is not false then
    raise exception 'Desligar o substituto com justificativa falhou: %', v_r;
  end if;
  perform f.fn_solicitacao_nfe_cancelar_rascunho(v_sol2, 'Rascunho Simples descartado no teste');
  -- Campo travado barra a liberacao e o portao de producao; a confirmacao destrava com auditoria.
  begin
    perform f.fn_perfil_operacao_nfse_liberar_producao('15400000-0000-4000-8000-000000000104', v_sol, 'Tentativa de liberar com campo travado', true);
    raise exception 'Perfil com campo travado foi liberado.';
  exception when sqlstate '55000' then
    if sqlerrm not like '%travados%' then raise exception 'Erro inesperado: %', sqlerrm; end if;
  end;
  v_r := f.fn_perfil_operacao_nfse_confirmar_campo('15400000-0000-4000-8000-000000000104', 'iss_retido_regra', 'Conferido em 08/09 com as notas reais: ISS nunca retido no 14.01');
  if v_r->'campos_conferir' is distinct from 'null'::jsonb and v_r->'campos_conferir' is not null then raise exception 'Confirmacao nao limpou campos_conferir: %', v_r; end if;
  begin
    perform f.fn_perfil_operacao_nfse_liberar_producao('15400000-0000-4000-8000-000000000104', v_sol, 'Liberacao apos confirmacao (falha por outro motivo)', true);
    raise exception 'Perfil liberado sem NFS-e de homologacao.';
  exception when sqlstate '55000' then
    raise exception 'Campo confirmado ainda bloqueia: %', sqlerrm;
  when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like '%travados%' then raise exception 'Campo confirmado ainda bloqueia: %', v_msg; end if;
  end;
  if (select count(*) from f.perfil_operacao_revisao_evento where perfil_operacao_id = '15400000-0000-4000-8000-000000000104' and justificativa like 'CONFIRMACAO DO CAMPO iss_retido_regra%') <> 1 then
    raise exception 'Confirmacao do campo sem evento de auditoria.';
  end if;
end;
$regras_perfil$;

-- Obra (07.02, contador 06/09/2026), no fim para nao deslocar a numeracao da DPS dos cenarios seguintes:
-- material incorporado sai da base do ISS e do INSS (LC 116 art. 7 §2 I); ISS no municipio da obra retido
-- pelo tomador; INSS 11%; sem IRRF/CRF; cIndOp 020201; NBS 1.0102.41.00.
create or replace function pg_temp.cenario_obra() returns void language plpgsql as $obra$
declare v_sol uuid; v_sol2 uuid; v_r jsonb; v_sf f.solicitacao_faturamento%rowtype; v_serv jsonb;
begin
  v_r := f.fn_perfil_operacao_nfse_revisar('15400000-0000-4000-8000-000000000106',
    '{"codigo_tributacao_nacional":"070201","codigo_nbs":"101024100","descricao_servico_padrao":"EXECUCAO DE INSTALACAO ELETRICA EM OBRA","local_prestacao_regra":"CLIENTE","incidencia_iss_regra":"LOCAL_PRESTACAO","tributacao_iss":1,"aliquota_iss":3,"iss_retido_regra":"SEMPRE","retencao_pcc_regra":"NUNCA","retencao_irrf_regra":"NUNCA","retencao_inss_regra":"SEMPRE","aliquota_inss":11,"permite_deducao_material":true,"cst_pis":"01","cst_cofins":"01","aliquota_pis":1.65,"aliquota_cofins":7.6,"cst_ibs_cbs":"000","cclass_trib":"000001","ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9,"codigo_indicador_operacao":"020201"}'::jsonb,
    'Perfil 07.02 de teste conforme respostas do contador de 06/09/2026');
  -- Material real da obra: R$ 1.200,00 de produto aplicado na OS. O item de venda (R$ 500,00) sai por NF-e e nao conta.
  insert into public.itens (id, codigo_interno, nome, tipo, tenant_id, empresa_id, finalidade)
  values (915490, 'MAT-OBRA-1', 'CABO PARA OBRA', 'produto', '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'materia_prima');
  insert into public.os_itens (os_id, item_id, quantidade, valor_unitario, valor_total, tenant_id, empresa_id, finalidade, baixa_estoque)
  values (915406, 915490, 10, 120, 1200, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'componente', false),
         (915406, 915490, 5, 100, 500, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'venda', false);
  v_sol := f.fn_solicitacao_faturamento_criar_os_servico('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002',
    '15400000-0000-4000-8000-000000000106', jsonb_build_array(jsonb_build_object('os_id', 915406, 'descricao_servico', 'AMPLIACAO DA REDE ELETRICA DO GALPAO 2', 'valor_servico', 3500)));
  -- Deducao acima do material real (1.500 > 1.200) bloqueia: vale o que foi aplicado na obra, nao um percentual.
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol, '{"pagamento_forma":"15","pagamento_indicador":1,"pagamento_parcelas":[{"dias":28}],"valor_deducao_material":1500,"obra":{"cep":"88200-000","logradouro":"RUA DA OBRA","numero":"100","bairro":"CENTRO"}}'::jsonb);
  if (v_r->>'ok')::boolean or not exists (select 1 from jsonb_array_elements(v_r->'pendencias') p where p->>'campo' = 'valor_deducao_material' and p->>'mensagem' like '%material real da obra%R$ 1.200,00%') then
    raise exception 'Deducao acima do material real nao bloqueou: %', v_r;
  end if;
  -- Obra em municipio sem aliquota cadastrada (Joinville nao esta na tabela do teste) bloqueia: nada de chute.
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol, '{"pagamento_forma":"15","pagamento_indicador":1,"pagamento_parcelas":[{"dias":28}],"municipio_prestacao_ibge":"4209102"}'::jsonb);
  if (v_r->>'ok')::boolean or not exists (select 1 from jsonb_array_elements(v_r->'pendencias') p where p->>'campo' = 'aliquota_iss' and p->>'mensagem' like '%4209102%') then
    raise exception 'Obra em municipio sem aliquota cadastrada nao bloqueou: %', v_r;
  end if;
  -- Material maior que o servico bloqueia.
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol, '{"pagamento_forma":"15","pagamento_indicador":1,"pagamento_parcelas":[{"dias":28}],"valor_deducao_material":3500}'::jsonb);
  if (v_r->>'ok')::boolean or not exists (select 1 from jsonb_array_elements(v_r->'pendencias') p where p->>'campo' = 'valor_deducao_material') then
    raise exception 'Material igual ao servico nao bloqueou: %', v_r;
  end if;
  -- Sem o local da obra, o 070201 bloqueia antes de gastar DPS (E0370 do ambiente nacional, OS 139, 11/09/2026).
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol, '{"pagamento_forma":"15","pagamento_indicador":1,"pagamento_parcelas":[{"dias":28}],"valor_deducao_material":1000}'::jsonb);
  if (v_r->>'ok')::boolean or not exists (select 1 from jsonb_array_elements(v_r->'pendencias') p where p->>'campo' = 'obra' and p->>'mensagem' like '%E0370%') then
    raise exception 'Obra sem local nao bloqueou: %', v_r;
  end if;
  -- Endereco incompleto (sem bairro) tambem bloqueia.
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol, '{"pagamento_forma":"15","pagamento_indicador":1,"pagamento_parcelas":[{"dias":28}],"valor_deducao_material":1000,"obra":{"cep":"88200-000","logradouro":"RUA DA OBRA","numero":"100"}}'::jsonb);
  if (v_r->>'ok')::boolean or not exists (select 1 from jsonb_array_elements(v_r->'pendencias') p where p->>'campo' = 'obra') then
    raise exception 'Obra com endereco incompleto nao bloqueou: %', v_r;
  end if;
  -- CNO fora do formato bloqueia (o ambiente nacional aceitou "123" na NFS-e 13 de homologacao).
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol, '{"pagamento_forma":"15","pagamento_indicador":1,"pagamento_parcelas":[{"dias":28}],"valor_deducao_material":1000,"obra":{"codigo_obra":"123"}}'::jsonb);
  if (v_r->>'ok')::boolean or not exists (select 1 from jsonb_array_elements(v_r->'pendencias') p where p->>'campo' = 'obra' and p->>'mensagem' like '%12 digitos%') then
    raise exception 'CNO invalido nao bloqueou: %', v_r;
  end if;
  -- 3.500 de servico com 1.000 de material: ISS 3% sobre 2.500 = 75 (retido, obra em Tijucas); INSS 11% sobre 2.500 = 275; liquido 3.150.
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol, '{"pagamento_forma":"15","pagamento_indicador":1,"pagamento_parcelas":[{"dias":28}],"valor_deducao_material":1000,"obra":{"cep":"88200-000","logradouro":"RUA DA OBRA","numero":"100","complemento":"","bairro":"CENTRO"}}'::jsonb);
  if coalesce((v_r->>'ok')::boolean, false) is not true then raise exception 'Conferencia da obra devolveu pendencias: %', v_r; end if;
  select * into v_sf from f.solicitacao_faturamento where id = v_sol;
  v_serv := v_sf.operacao_snapshot->'servico';
  -- O local vai para a solicitacao e para o snapshot, com o CEP so em digitos e sem complemento vazio.
  if v_sf.obra_dados is distinct from '{"cep":"88200000","logradouro":"RUA DA OBRA","numero":"100","complemento":null,"bairro":"CENTRO"}'::jsonb
     or v_serv->'obra' is distinct from v_sf.obra_dados then
    raise exception 'Local da obra gravado errado: % / %', v_sf.obra_dados, v_serv->'obra';
  end if;
  -- Com os 1.000 reservados nesta solicitacao, sobram 200 de material para as proximas NFS-e da OS.
  v_r := f.fn_os_nfse_material_disponivel('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', array[915406], null);
  if (v_r->>'material_aplicado')::numeric <> 1200 or (v_r->>'reservado_em_solicitacoes')::numeric <> 1000 or (v_r->>'material_disponivel')::numeric <> 200 then
    raise exception 'Material disponivel errado: %', v_r;
  end if;
  -- Tijucas sem marcacao: o municipio parametriza nos dois ambientes, a aliquota nao vai na DPS (E0617).
  if v_serv->'aliquota_iss_na_dps' is distinct from '{"HOMOLOGACAO": false, "PRODUCAO": false}'::jsonb then
    raise exception 'Situacao do municipio na DPS errada: %', v_serv->'aliquota_iss_na_dps';
  end if;
  if v_sf.valor_deducao_material <> 1000 or (v_serv->>'valor_deducoes')::numeric <> 1000 or (v_serv->>'base_iss')::numeric <> 2500
     or (v_serv->>'valor_iss')::numeric <> 75 or v_sf.iss_retido is not true or v_serv->>'municipio_incidencia_iss' <> '4218004'
     or (v_serv->>'valor_inss')::numeric <> 275 or (v_serv->>'valor_liquido')::numeric <> 3150 or v_serv->>'codigo_indicador_operacao' <> '020201'
     or v_serv->>'descricao_servico' not like '%MATERIAL APLICADO: R$ 1.000,00 (28,57% do serviço), deduzido da base do ISS e do INSS (LC 116/2003, art. 7º, § 2º, I)%' then
    raise exception 'Deducao de material errada: % / %', row_to_json(v_sf), v_serv;
  end if;
  -- A deducao vai para a emissao no preparo.
  declare v_p record; v_e f.documento_fiscal_emissao%rowtype;
  begin
    select * into v_p from f.fn_nfse_preparar_documento_solicitacao(v_sol);
    select * into v_e from f.documento_fiscal_emissao where documento_fiscal_id = v_p.documento_fiscal_id;
    if v_e.valor_deducoes <> 1000 or v_e.valor_iss <> 75 or v_e.valor_liquido <> 3150 then raise exception 'Emissao da obra sem a deducao: %', row_to_json(v_e); end if;
    perform f.fn_nfse_abandonar_homologacao(v_sol, 'Obra de teste abandonada apos o preparo');
  end;
  -- Perfil sem permissao (14.01) recusa material.
  v_sol2 := f.fn_solicitacao_faturamento_criar_os_servico('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002',
    '15400000-0000-4000-8000-000000000104', jsonb_build_array(jsonb_build_object('os_id', 915406, 'descricao_servico', 'MANUTENCAO DO PAINEL', 'valor_servico', 500)));
  v_r := f.fn_os_nfse_conferir_homologacao(v_sol2, '{"pagamento_forma":"15","pagamento_indicador":1,"pagamento_parcelas":[{"dias":28}],"valor_deducao_material":100}'::jsonb);
  if (v_r->>'ok')::boolean or not exists (select 1 from jsonb_array_elements(v_r->'pendencias') p where p->>'campo' = 'permite_deducao_material') then
    raise exception 'Material em perfil sem permissao nao bloqueou: %', v_r;
  end if;
  perform f.fn_solicitacao_nfe_cancelar_rascunho(v_sol2, 'Rascunho de material descartado no teste');
end;
$obra$;

-- Preparo: documento RASCUNHO + emissao + DPS numerada, idempotente; producao fechada.
do $preparar$
declare v_1 record; v_2 record; v_doc f.documento_fiscal%rowtype; v_e f.documento_fiscal_emissao%rowtype; v_p jsonb;
begin
  select * into v_1 from f.fn_nfse_preparar_documento_solicitacao((select sol_a from ctx));
  select * into v_2 from f.fn_nfse_preparar_documento_solicitacao((select sol_a from ctx));
  if v_1.documento_fiscal_id <> v_2.documento_fiscal_id or v_1.dps_numero <> v_2.dps_numero then
    raise exception 'Preparo nao foi idempotente: % / %', row_to_json(v_1), row_to_json(v_2);
  end if;
  if v_1.referencia_externa <> 'NFSH-' || (select sol_a from ctx)::text or v_1.dps_serie <> 2 or v_1.dps_numero <> 1 then
    raise exception 'Referencia/DPS inesperadas: %', row_to_json(v_1);
  end if;
  update ctx set doc_a = v_1.documento_fiscal_id;
  select * into v_doc from f.documento_fiscal where id = v_1.documento_fiscal_id;
  if v_doc.modelo <> 'NFSE' or v_doc.natureza <> 'SERVICO' or v_doc.nfse_status <> 'RASCUNHO' or v_doc.origem <> 'EMITIDO'
     or v_doc.valor_servicos <> 6000 or v_doc.valor_total <> 5331 or v_doc.os_id_import <> 915400 or v_doc.nfse_municipio_codigo <> '4209102'
     or v_doc.competencia_date <> date_trunc('month', current_date)::date then
    raise exception 'Documento NFS-e preparado errado: %', row_to_json(v_doc);
  end if;
  select * into v_e from f.documento_fiscal_emissao where documento_fiscal_id = v_1.documento_fiscal_id;
  if v_e.modelo <> 'NFSE' or v_e.dps_serie <> 2 or v_e.dps_numero <> 1 or v_e.iss_retido is not true or v_e.valor_iss <> 300 or v_e.valor_liquido <> 5331 or jsonb_array_length(v_e.retencoes) <> 5 then
    raise exception 'Emissao NFS-e preparada errada: %', row_to_json(v_e);
  end if;
  if (select resultado from f.dps_numero_log where documento_fiscal_id = v_1.documento_fiscal_id) <> 'RESERVADO' then
    raise exception 'DPS nao ficou RESERVADO no log.';
  end if;
  if (select count(*) from f.documento_fiscal_imposto where documento_fiscal_id = v_1.documento_fiscal_id and deleted_at is null) <> 0 then
    raise exception 'Documento de homologacao gerou debito de PIS/COFINS.';
  end if;
  select * into v_1 from f.fn_nfse_preparar_documento_solicitacao((select sol_b from ctx));
  update ctx set doc_b = v_1.documento_fiscal_id;
  if v_1.dps_numero <> 2 then raise exception 'Segunda DPS deveria ser 2: %', row_to_json(v_1); end if;
  select * into v_1 from f.fn_nfse_preparar_documento_solicitacao((select sol_c from ctx));
  update ctx set doc_c = v_1.documento_fiscal_id;
  v_p := f.fn_nfe_producao_pronta((select sol_a from ctx));
  if coalesce((v_p->>'pronta')::boolean, true) then
    raise exception 'Producao considerada pronta com fixture de servico: %', v_p;
  end if;
  -- Depois do preparo a conferencia nao muda mais (material congelado).
  begin
    perform f.fn_os_nfse_conferir_homologacao((select sol_a from ctx), '{"pagamento_forma":"15","pagamento_indicador":1}'::jsonb);
  exception when others then null;
  end;
end;
$preparar$;

reset role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

-- Rejeicao: DPS 1 queimada, saldo devolvido; retry ganha DPS 3 e o claim exige o numero novo.
select f.fn_nfe_registrar_envio((select doc_a from ctx), '{"serie_dps":2,"numero_dps":1}'::jsonb, '{"status":"processando_autorizacao"}'::jsonb, 'PROCESSANDO');
select f.fn_nfse_aplicar_retorno('NFSH-' || (select sol_a from ctx)::text, '{"status":"erro_autorizacao","erros":[{"codigo":"E0014","mensagem":"DPS ja existe"}]}'::jsonb,
  'REJEITADA', null, null, null, null, 422, 'E0014: DPS ja existe', null, null, null, 'CALLBACK');
do $rejeicao$
declare v_s record; v_r jsonb; v_e f.documento_fiscal_emissao%rowtype;
begin
  select * into v_s from f.fn_os_saldo_a_faturar('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 915400);
  if v_s.valor_reservado <> 1000 or v_s.saldo <> 9000 then raise exception 'Rejeicao nao devolveu o saldo: %', row_to_json(v_s); end if;
  if (select resultado from f.dps_numero_log where serie = 2 and numero = 1 and tenant_id = '15400000-0000-4000-8000-000000000001') <> 'REJEITADO' then
    raise exception 'DPS rejeitada nao ficou queimada no log.';
  end if;
  v_r := f.fn_nfse_renumerar_dps((select doc_a from ctx));
  if (v_r->>'dps_numero')::int <> 4 or (v_r->>'renumerada')::boolean is not true then raise exception 'Renumeracao errada: %', v_r; end if;
  begin
    perform f.fn_nfse_homologacao_claimar((select doc_a from ctx), '{"serie_dps":2,"numero_dps":1}'::jsonb, true);
    raise exception 'Claim aceitou numero de DPS antigo.';
  exception when sqlstate '22023' then null;
  end;
  v_r := f.fn_nfse_homologacao_claimar((select doc_a from ctx), '{"serie_dps":2,"numero_dps":4}'::jsonb, true);
  if (v_r->>'deve_enviar')::boolean is not true then raise exception 'Claim do retry nao liberou o envio: %', v_r; end if;
  select * into v_e from f.documento_fiscal_emissao where documento_fiscal_id = (select doc_a from ctx);
  if v_e.status <> 'ENVIANDO' or v_e.dps_numero <> 4 or (v_e.payload_enviado->>'numero_dps')::int <> 4 then
    raise exception 'Emissao apos claim do retry errada: %', row_to_json(v_e);
  end if;
  select * into v_s from f.fn_os_saldo_a_faturar('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 915400);
  if v_s.valor_reservado <> 7000 then raise exception 'Retry nao voltou a reservar: %', row_to_json(v_s); end if;
end;
$rejeicao$;

-- Autorizacao em homologacao: emissao AUTORIZADA, documento continua RASCUNHO, sem titulo; webhook duplicado ignorado.
select f.fn_nfe_registrar_envio((select doc_a from ctx), '{"serie_dps":2,"numero_dps":4}'::jsonb, '{"status":"processando_autorizacao"}'::jsonb, 'PROCESSANDO');
select f.fn_nfse_aplicar_retorno('NFSH-' || (select sol_a from ctx)::text, '{"status":"autorizado","numero":"101"}'::jsonb,
  'AUTORIZADA', repeat('1', 50), '101', 'ABC123', null, null, null, 'teste/nfse.xml', 'teste/danfse.pdf',
  '<NFSe xmlns="http://www.sped.fazenda.gov.br/nfse"><infNFSe><nNFSe>101</nNFSe></infNFSe></NFSe>', 'CALLBACK');
select f.fn_nfse_aplicar_retorno('NFSH-' || (select sol_a from ctx)::text, '{"status":"autorizado","numero":"101"}'::jsonb,
  'AUTORIZADA', repeat('1', 50), '101', 'ABC123', null, null, null, 'teste/nfse.xml', 'teste/danfse.pdf', '<NFSe/>', 'CALLBACK');
do $autorizada$
declare v_e f.documento_fiscal_emissao%rowtype; v_doc f.documento_fiscal%rowtype; v_s record;
begin
  select * into v_e from f.documento_fiscal_emissao where documento_fiscal_id = (select doc_a from ctx);
  select * into v_doc from f.documento_fiscal where id = (select doc_a from ctx);
  if v_e.status <> 'AUTORIZADA' or v_e.chave_nfse <> repeat('1', 50) or v_e.nfse_numero <> '101' or v_e.codigo_verificacao <> 'ABC123' or v_e.numero <> 101 then
    raise exception 'Emissao autorizada errada: %', row_to_json(v_e);
  end if;
  -- DPS e NFS-e sao numeracoes independentes: a nota 101 nao arrasta a DPS 4 (nas reais, DPS 44 x NFS-e 40).
  if v_e.dps_numero <> 4 or v_e.dps_serie <> 2 or v_e.nfse_numero::int = v_e.dps_numero then
    raise exception 'Numero da DPS foi contaminado pelo numero da NFS-e: %', row_to_json(v_e);
  end if;
  if v_doc.nfse_status <> 'RASCUNHO' or v_doc.chave_acesso <> repeat('1', 50) or v_doc.numero <> '101' then
    raise exception 'Homologacao alterou o documento: %', row_to_json(v_doc);
  end if;
  if exists (select 1 from f.titulo where documento_fiscal_id = (select doc_a from ctx) and deleted_at is null) then
    raise exception 'Homologacao criou titulo.';
  end if;
  if (select count(*) from f.documento_fiscal_evento where documento_fiscal_id = (select doc_a from ctx) and tipo = 'AUTORIZACAO') <> 1 then
    raise exception 'Webhook duplicado gerou segunda autorizacao.';
  end if;
  if (select resultado from f.dps_numero_log where serie = 2 and numero = 4 and tenant_id = '15400000-0000-4000-8000-000000000001') <> 'AUTORIZADO' then
    raise exception 'DPS autorizada nao ficou AUTORIZADO no log.';
  end if;
  if (select xml_raw from f.documento_fiscal_xml where documento_fiscal_id = (select doc_a from ctx)) not like '%nNFSe>101%' then
    raise exception 'XML da NFS-e nao foi guardado (ou foi sobrescrito pelo webhook duplicado).';
  end if;
  select * into v_s from f.fn_os_saldo_a_faturar('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 915400);
  if v_s.valor_faturado <> 0 or v_s.valor_reservado <> 7000 then raise exception 'Saldo apos autorizacao HOM: %', row_to_json(v_s); end if;
  if not exists (select 1 from f.fn_os_notas('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 915400) where modelo = 'NFSE' and numero = '101' and serie = '2') then
    raise exception 'fn_os_notas nao listou a NFS-e com modelo/numero.';
  end if;
  if (select status from f.solicitacao_faturamento where id = (select sol_a from ctx)) <> 'EMITIDA' then
    raise exception 'Solicitacao A nao ficou EMITIDA.';
  end if;
end;
$autorizada$;

-- Cancelamento: regra MES_EMISSAO (Joinville, Decreto 30.798/2018): direto ate o fim do mes de emissao; depois, substituicao.
do $cancelar$
declare v_c jsonb; v_r jsonb; v_s record; v_e f.documento_fiscal_emissao%rowtype;
begin
  update f.documento_fiscal_emissao set autorizado_em = now() - interval '45 days' where documento_fiscal_id = (select doc_a from ctx);
  begin
    perform f.fn_nfse_cancelamento_claim((select doc_a from ctx), 'Cancelamento fora do mes de emissao', null);
    raise exception 'Cancelamento de nota do mes anterior foi aceito.';
  exception when sqlstate '55000' then
    if sqlerrm not like '%fim do mes de emissao%' then raise exception 'Erro inesperado: %', sqlerrm; end if;
  end;
  update f.documento_fiscal_emissao set autorizado_em = now() where documento_fiscal_id = (select doc_a from ctx);
  if f.fn_nfse_cancelamento_limite('15400000-0000-4000-8000-000000000002', now()) <= now() then raise exception 'Limite do mes de emissao no passado.'; end if;
  v_c := f.fn_nfse_cancelamento_claim((select doc_a from ctx), 'Cancelamento no cenario de homologacao 12', null);
  if (v_c->>'deve_cancelar')::boolean is not true then raise exception 'Claim de cancelamento nao liberou: %', v_c; end if;
  v_r := f.fn_nfse_cancelamento_finalizar((select doc_a from ctx), (v_c->>'evento_claim_id')::uuid, 'AUTORIZADA', 'Cancelamento no cenario de homologacao 12', null, '{"status":"cancelado"}'::jsonb);
  select * into v_e from f.documento_fiscal_emissao where documento_fiscal_id = (select doc_a from ctx);
  if v_e.status <> 'CANCELADA' or (select status from f.solicitacao_faturamento where id = (select sol_a from ctx)) <> 'CANCELADA' then
    raise exception 'Cancelamento nao refletiu na emissao/solicitacao.';
  end if;
  if (select resultado from f.dps_numero_log where serie = 2 and numero = 4 and tenant_id = '15400000-0000-4000-8000-000000000001') <> 'CANCELADO' then
    raise exception 'Log da DPS nao ficou CANCELADO.';
  end if;
  select * into v_s from f.fn_os_saldo_a_faturar('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 915400);
  if v_s.valor_reservado <> 1000 or v_s.saldo <> 9000 then raise exception 'Cancelamento nao devolveu o saldo: %', row_to_json(v_s); end if;
  -- Resposta tardia do mesmo claim e idempotente; retorno tardio da Focus nao reabre.
  v_r := f.fn_nfse_cancelamento_finalizar((select doc_a from ctx), (v_c->>'evento_claim_id')::uuid, 'AUTORIZADA', 'Cancelamento no cenario de homologacao 12', null, '{"status":"cancelado"}'::jsonb);
  if (v_r->>'idempotente')::boolean is not true then raise exception 'Finalizacao repetida nao foi idempotente: %', v_r; end if;
  perform f.fn_nfse_aplicar_retorno('NFSH-' || (select sol_a from ctx)::text, '{"status":"autorizado"}'::jsonb, 'AUTORIZADA', repeat('1', 50), '101', null, null, null, null, null, null, '<x/>', 'CALLBACK');
  if (select status from f.documento_fiscal_emissao where documento_fiscal_id = (select doc_a from ctx)) <> 'CANCELADA' then
    raise exception 'Retorno tardio reabriu a emissao cancelada.';
  end if;
end;
$cancelar$;

-- B autorizada, depois substituida por uma nova NFS-e (saldo migra, antiga SUBSTITUIDA).
select f.fn_nfe_registrar_envio((select doc_b from ctx), '{"serie_dps":2,"numero_dps":2}'::jsonb, '{"status":"processando_autorizacao"}'::jsonb, 'PROCESSANDO');
select f.fn_nfse_aplicar_retorno('NFSH-' || (select sol_b from ctx)::text, '{"status":"autorizado","numero":"102"}'::jsonb,
  'AUTORIZADA', repeat('2', 50), '102', 'DEF456', null, null, null, 'teste/b.xml', 'teste/b.pdf', '<NFSe><nNFSe>102</nNFSe></NFSe>', 'RECONCILIACAO');
update ctx set chave_b = repeat('2', 50);

select set_config('request.jwt.claim.sub', '15400000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"15400000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;
do $substituir_preparar$
declare v_r jsonb; v_sf f.solicitacao_faturamento%rowtype; v_p record; v_e f.documento_fiscal_emissao%rowtype; v_s record;
begin
  begin
    perform f.fn_nfse_substituir_preparar((select doc_b from ctx), '77', 'Motivo qualquer com quinze letras');
    raise exception 'Codigo de substituicao invalido aceito.';
  exception when sqlstate '22023' then null;
  end;
  update ctx set sol_sub = f.fn_nfse_substituir_preparar((select doc_b from ctx), '99', 'Descricao do servico corrigida a pedido do tomador');
  select * into v_sf from f.solicitacao_faturamento where id = (select sol_sub from ctx);
  if v_sf.substitui_documento_fiscal_id <> (select doc_b from ctx) or v_sf.substituicao_codigo <> '99' or v_sf.status <> 'RASCUNHO' or v_sf.snapshot_cadastro_em is not null then
    raise exception 'Clone da substituicao errado: %', row_to_json(v_sf);
  end if;
  if (select count(*) from f.solicitacao_item where solicitacao_id = (select sol_sub from ctx)) <> 1 then raise exception 'Clone sem linhas.'; end if;
  -- Saldo da OS 915402 esta zerado pela B; a reserva da substituida conta a favor.
  v_r := f.fn_os_nfse_conferir_homologacao((select sol_sub from ctx), '{"pagamento_forma":"17","pagamento_indicador":0,"observacao":"Servico executado em 28/08/2026"}'::jsonb);
  if coalesce((v_r->>'ok')::boolean, false) is not true then raise exception 'Conferencia da substituta devolveu pendencias: %', v_r; end if;
  if (select operacao_snapshot->'substituicao'->>'chave' from f.solicitacao_faturamento where id = (select sol_sub from ctx)) <> repeat('2', 50) then
    raise exception 'Snapshot da substituta sem a chave substituida.';
  end if;
  select * into v_p from f.fn_nfse_preparar_documento_solicitacao((select sol_sub from ctx));
  update ctx set doc_sub = v_p.documento_fiscal_id;
  select * into v_e from f.documento_fiscal_emissao where documento_fiscal_id = v_p.documento_fiscal_id;
  if v_e.chave_nfse_substituida <> repeat('2', 50) or v_e.substituicao_codigo <> '99' or v_e.dps_numero <> 5 then
    raise exception 'Emissao substituta errada: %', row_to_json(v_e);
  end if;
  begin
    perform f.fn_nfse_substituir_preparar((select doc_b from ctx), '99', 'Segunda substituicao concorrente da mesma nota');
    raise exception 'Segunda substituicao concorrente foi aceita.';
  exception when sqlstate '55000' then null;
  end;
end;
$substituir_preparar$;
reset role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select f.fn_nfe_registrar_envio((select doc_sub from ctx), '{"serie_dps":2,"numero_dps":5}'::jsonb, '{"status":"processando_autorizacao"}'::jsonb, 'PROCESSANDO');
select f.fn_nfse_aplicar_retorno('NFSH-' || (select sol_sub from ctx)::text, '{"status":"autorizado","numero":"103"}'::jsonb,
  'AUTORIZADA', repeat('3', 50), '103', 'GHI789', null, null, null, 'teste/sub.xml', 'teste/sub.pdf', '<NFSe><nNFSe>103</nNFSe></NFSe>', 'CALLBACK');
do $substituida$
declare v_s record;
begin
  if (select nfse_status from f.documento_fiscal where id = (select doc_b from ctx)) <> 'SUBSTITUIDA' then raise exception 'Antiga nao ficou SUBSTITUIDA.'; end if;
  if (select status from f.solicitacao_faturamento where id = (select sol_b from ctx)) <> 'CANCELADA' then raise exception 'Solicitacao antiga nao foi encerrada.'; end if;
  if (select resultado from f.dps_numero_log where serie = 2 and numero = 2 and tenant_id = '15400000-0000-4000-8000-000000000001') <> 'SUBSTITUIDO' then raise exception 'Log da DPS antiga nao ficou SUBSTITUIDO.'; end if;
  if (select count(*) from f.documento_fiscal_evento where tipo = 'SUBSTITUICAO' and chave_nova = repeat('3', 50) and chave_substituida = repeat('2', 50) and codigo_motivo = '99') <> 2 then
    raise exception 'Eventos SUBSTITUICAO nos dois documentos ausentes.';
  end if;
  select * into v_s from f.fn_os_saldo_a_faturar('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 915402);
  if v_s.valor_reservado <> 3000 or v_s.saldo <> 0 then raise exception 'Saldo apos substituicao (so a nova reserva): %', row_to_json(v_s); end if;
end;
$substituida$;

-- Titulo liquido pelo caminho de producao: C autorizada em HOM; simula o efeito de producao
-- (documento EMITIDA) e chama a mesma funcao que o retorno de producao chama.
select f.fn_nfe_registrar_envio((select doc_c from ctx), '{"serie_dps":2,"numero_dps":3}'::jsonb, '{"status":"processando_autorizacao"}'::jsonb, 'PROCESSANDO');
do $titulo$
declare v_t f.titulo%rowtype; v_titulo_id uuid; v_parcelas integer; v_ret record;
begin
  update f.documento_fiscal set nfse_status = 'EMITIDA', chave_acesso = repeat('5', 50), numero = '105', updated_at = now() where id = (select doc_c from ctx);
  v_titulo_id := f.fn_nfse_titulo_liquido_sincronizar((select doc_c from ctx));
  select * into v_t from f.titulo where id = v_titulo_id;
  if v_t.valor_total <> 2221.25 or v_t.valor_aberto <> 2221.25 or v_t.tipo <> 'AR' or v_t.cliente_id <> 915400 then
    raise exception 'Titulo nao nasceu liquido: %', row_to_json(v_t);
  end if;
  select count(*) into v_parcelas from f.titulo_parcela where titulo_id = v_titulo_id and deleted_at is null;
  if v_parcelas <> 2 then raise exception 'Parcelas do liquido: esperado 2, veio %', v_parcelas; end if;
  if (select sum(valor) from f.titulo_parcela where titulo_id = v_titulo_id and deleted_at is null) <> 2221.25 then raise exception 'Soma das parcelas difere do liquido.'; end if;
  if (select valor from f.titulo_parcela where titulo_id = v_titulo_id and deleted_at is null and numero = '001') <> 1000 then raise exception 'Primeira parcela deveria ser 1000.'; end if;
  if (select count(*) from f.titulo_retencao where titulo_id = v_titulo_id) <> 5 then raise exception 'titulo_retencao deveria ter 5 tributos (ISS, IRRF, PIS, COFINS, CSLL).'; end if;
  select sum(valor) as total into v_ret from f.titulo_retencao where titulo_id = v_titulo_id;
  if v_ret.total <> 278.75 then raise exception 'Soma das retencoes deveria ser 278,75: %', v_ret.total; end if;
  if (select valor from f.titulo_retencao where titulo_id = v_titulo_id and tributo = 'ISS') <> 125 then raise exception 'ISS retido deveria ser 125.'; end if;
  if (select count(*) from f.documento_fiscal_imposto where documento_fiscal_id = (select doc_c from ctx) and deleted_at is null) < 2 then
    raise exception 'Documento EMITIDA deveria ter debito de PIS/COFINS.';
  end if;
  perform f.fn_nfse_titulo_cancelar((select doc_c from ctx), 'NFS-e cancelada no teste');
  select * into v_t from f.titulo where id = v_titulo_id;
  if v_t.status <> 'CANCELADO' or v_t.valor_aberto <> 0 then raise exception 'Titulo nao foi cancelado: %', row_to_json(v_t); end if;
end;
$titulo$;

-- RLS: a outra empresa nao ve nada.
select set_config('request.jwt.claim.sub', '15400000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"15400000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;
do $rls$
begin
  if (select count(*) from f.fn_os_notas('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000003', 915405)) <> 0 then
    raise exception 'fn_os_notas vazou notas de outra empresa.';
  end if;
  if (select count(*) from f.dps_numero_log where empresa_id = '15400000-0000-4000-8000-000000000003') <> 0 then
    raise exception 'dps_numero_log vazou outra empresa.';
  end if;
  if (select count(*) from f.dps_numero_log where empresa_id = '15400000-0000-4000-8000-000000000002') < 4 then
    raise exception 'dps_numero_log da propria empresa nao visivel ao financeiro.';
  end if;
  begin
    perform f.fn_proximo_numero_dps('15400000-0000-4000-8000-000000000002');
    raise exception 'authenticated conseguiu numerar DPS diretamente.';
  exception when sqlstate '42501' then null;
  end;
end;
$rls$;

-- Obra com deducao de material (funcao temporaria definida no bloco de regras), como o financeiro.
select pg_temp.cenario_obra();

rollback;
