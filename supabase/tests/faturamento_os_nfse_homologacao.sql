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
insert into c.empresa_fiscal (empresa_id, inscricao_estadual, inscricao_municipal, crt, certificado_validade_em, serie_nfe, serie_dps, proximo_numero_dps, codigo_opcao_simples_nacional, regime_especial_tributacao)
values ('15400000-0000-4000-8000-000000000002', '257686835', '152836', 3, current_date + 365, 2, 2, 1, 1, 0),
       ('15400000-0000-4000-8000-000000000003', '257686836', null, 3, current_date + 365, 2, 2, 1, 1, 0);
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
  cep, logradouro, numero_endereco, bairro, cidade, uf, pais, indicador_ie, codigo_ibge_municipio, iss_retido, retem_pcc, retem_irrf, retem_inss, email_nfse)
values
  (915400, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'TOMADOR JOINVILLE', '84689090000240', 'TOMADOR JOINVILLE S/A', '222222222', '998877',
   '89239270', 'RUA DONA FRANCISCA', '11700', 'PIRABEIRABA', 'JOINVILLE', 'SC', 'BRASIL', '1', '4209102', true, true, true, false, 'fiscal@tomador.test'),
  (915401, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'TOMADOR TIJUCAS', '83475913000272', 'TOMADOR TIJUCAS SA', '333333333', null,
   '88200000', 'BR 101', 'S/N', 'CENTRO', 'TIJUCAS', 'SC', 'BRASIL', '1', '4218004', false, false, false, false, null),
  (915402, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'TOMADOR SEM IM', '03818222000104', 'TOMADOR SEM IM LTDA', '444444444', null,
   '89237780', 'RUA DOS PORTUGUESES', '2240', 'VILA NOVA', 'JOINVILLE', 'SC', 'BRASIL', '1', '4209102', false, false, false, false, null),
  (915403, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'TOMADOR INDEFINIDO', '78872397000107', 'TOMADOR INDEFINIDO SA', '555555555', '112233',
   '89219600', 'RUA DONA FRANCISCA', '7650', 'ZONA INDUSTRIAL NORTE', 'JOINVILLE', 'SC', 'BRASIL', '1', '4209102', null, false, false, false, null);

-- Perfis de servico sem valor + fixture provisoria (a migration so semeia empresas ja existentes).
insert into f.perfil_operacao (id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto, crt, item_servico, faixa_automacao, justificativa_faixa, habilitado_producao, vigencia_inicio)
values
  ('15400000-0000-4000-8000-000000000101', '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'SEG-NFSE-1406', 'Servico 14.06', 'NFSE', 'PRESTACAO_SERVICO', 'PRESTACAO DE SERVICO', '3', '14.06', 'REVISAO', null, false, current_date),
  ('15400000-0000-4000-8000-000000000102', '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'SEG-NFSE-1709', 'Servico 17.09', 'NFSE', 'PRESTACAO_SERVICO', 'PRESTACAO DE SERVICO', '3', '17.09', 'REVISAO', null, false, current_date),
  ('15400000-0000-4000-8000-000000000103', '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'SEG-NFSE-0702', 'Servico 07.02', 'NFSE', 'PRESTACAO_SERVICO', 'PRESTACAO DE SERVICO', '3', '07.02', 'BLOQUEADO', 'Obra: aguarda o contador.', false, current_date);
insert into f.tributacao_provisoria_nfse_homologacao (tenant_id, empresa_id, item_servico, codigo_tributacao_nacional, codigo_nbs, descricao_servico_padrao, local_prestacao_regra,
  aliquota_iss, iss_retido_regra, aliquota_pis, aliquota_cofins, retencao_pcc_regra, aliquota_pcc, retencao_irrf_regra, aliquota_irrf, retencao_inss_regra, aliquota_inss,
  texto_sem_retencao, pendencia_contador, fonte)
values
  ('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', '14.06', '140601', '120032900', 'SERVICOS DE INSTALACAO E MONTAGEM', 'CLIENTE', 5, 'POR_TOMADOR', 1.65, 7.6, 'POR_TOMADOR', 4.65, 'POR_TOMADOR', 1.5, 'POR_TOMADOR', 11, 'NAO HA INCIDENCIA DAS RETENCOES FEDERAIS CONFORME IN SRF N 459/2004', 'teste', 'teste'),
  ('15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', '17.09', '170901', '114044900', 'LAUDO TECNICO', 'SEDE', 5, 'POR_TOMADOR', 1.65, 7.6, 'POR_TOMADOR', 4.65, 'POR_TOMADOR', 1.5, 'NUNCA', 11, 'NAO HA INCIDENCIA DAS RETENCOES FEDERAIS CONFORME IN SRF N 459/2004', 'teste', 'teste');

insert into public.ordens_servico (id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id, empresa_id, status_fluxo, tipo_documento, codigo, numero_doc, descricao_servico, orcado, pedido_compra)
values
  (915400, 'OS-NFSE-1', 'TOMADOR JOINVILLE', 915400, 'concluida', 915400, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'concluida', 'OS', 'OS-NFSE-001', 1, 'LAUDO NR-12 ANALISE DE RISCO', 10000, '136785'),
  (915401, 'OS-NFSE-2', 'TOMADOR JOINVILLE', 915400, 'concluida', 915401, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'concluida', 'OS', 'OS-NFSE-002', 2, 'LAUDO COMPLEMENTAR', 2000, null),
  (915402, 'OS-NFSE-3', 'TOMADOR TIJUCAS', 915401, 'em_andamento', 915402, '15400000-0000-4000-8000-000000000001', '15400000-0000-4000-8000-000000000002', 'em_andamento', 'OS', 'OS-NFSE-003', 3, 'SERVICOS MAO DE OBRA ELETRICISTA', 3000, '1306628'),
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
  if v_serv->>'descricao_servico' not like 'LAUDO NR-12 ANALISE DE RISCO - OS OS-NFSE-1. PEDIDO DE COMPRA: 136785. VENCIMENTO: 21 DDL (%). ISS RETIDO PELO TOMADOR. RETENCOES FEDERAIS: IRRF 1,50%; PIS/COFINS/CSLL 4,65% (PIS 0,65%; COFINS 3,00%; CSLL 1,00%). Conforme proposta 77' then
    raise exception 'Discriminacao A fora do padrao: %', v_serv->>'descricao_servico';
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
  '15400000-0000-4000-8000-000000000101', jsonb_build_array(jsonb_build_object('os_id', 915402, 'descricao_servico', 'SERVICOS MAO DE OBRA ELETRICISTA', 'valor_servico', 3000)));
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
  if v_serv->>'descricao_servico' <> 'SERVICOS MAO DE OBRA ELETRICISTA - OS OS-NFSE-3. PEDIDO DE COMPRA: 1306628. PAGAMENTO A VISTA. ISS RECOLHIDO PELO PRESTADOR. NAO HA INCIDENCIA DAS RETENCOES FEDERAIS CONFORME IN SRF N 459/2004.' then
    raise exception 'Discriminacao B fora do padrao: %', v_serv->>'descricao_servico';
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
  if v_serv->>'descricao_servico' not like 'LAUDO ADICIONAL - OS OS-NFSE-1. LAUDO COMPLEMENTAR - OS OS-NFSE-2. PEDIDO DE COMPRA: 136785. VENCIMENTOS: 14/28 DDL (%' then
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
  v_r := f.fn_os_nfse_conferir_homologacao((select sol_d from ctx), '{"pagamento_forma":"15","pagamento_indicador":1}'::jsonb);
  if (v_r->>'ok')::boolean or not exists (select 1 from jsonb_array_elements(v_r->'pendencias') p where p->>'campo' = 'inscricao_municipal' and p->>'rota' = '/clientes/cadastro-fiscal?cliente_id=915402') then
    raise exception 'Tomador de Joinville sem IM nao bloqueou com campo/rota: %', v_r;
  end if;
  if exists (select 1 from f.documento_fiscal_emissao where solicitacao_id = (select sol_d from ctx)) then
    raise exception 'Bloqueio D chegou a criar emissao.';
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

-- Cancelamento (homologacao, prazo nao confirmado): claim + finalizar; saldo devolvido.
do $cancelar$
declare v_c jsonb; v_r jsonb; v_s record; v_e f.documento_fiscal_emissao%rowtype;
begin
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

rollback;
