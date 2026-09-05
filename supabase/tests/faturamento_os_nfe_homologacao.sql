\set ON_ERROR_STOP on
begin;

-- NF-e de industrializacao a partir da OS, em HOMOLOGACAO (05/09/2026).
-- Cobre: produto fabricado criado da OS; conferencia pela fixture 5101 sem
-- perfil; total acima do saldo; produto sem NCM; UF divergente; preparo
-- idempotente; retorno autorizado sem titulo (homologacao); saldo reservado,
-- devolvido no abandono; portao de producao fechado; Faturada so com
-- documento emitido e saldo zero; RLS entre empresas.

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('15300000-0000-4000-8000-000000000010', 'authenticated', 'authenticated', 'os-nfe@example.test',
        '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Teste OS NF-e"}'::jsonb, now(), now());
insert into public.tenants (id, nome, ativo) values ('15300000-0000-4000-8000-000000000001', 'Teste OS NF-e', true);
insert into c.tenant (id, codigo, nome) values ('15300000-0000-4000-8000-000000000001', 'TESTE-OS-NFE', 'Teste OS NF-e');
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj)
values ('15300000-0000-4000-8000-000000000002', '15300000-0000-4000-8000-000000000001', 'OSNFE', 'EMPRESA TESTE OS NFE LTDA', 'OS NFE', '33333333000191'),
       ('15300000-0000-4000-8000-000000000003', '15300000-0000-4000-8000-000000000001', 'OUTRA', 'OUTRA EMPRESA LTDA', 'OUTRA', '44444444000191');
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, uf, cidade)
values ('15300000-0000-4000-8000-000000000002', '15300000-0000-4000-8000-000000000001', '33333333000191', 'EMPRESA TESTE OS NFE LTDA', 'OS NFE', 'SC', 'JOINVILLE'),
       ('15300000-0000-4000-8000-000000000003', '15300000-0000-4000-8000-000000000001', '44444444000191', 'OUTRA EMPRESA LTDA', 'OUTRA', 'SC', 'JOINVILLE')
on conflict (id) do nothing;
insert into c.empresa_fiscal (empresa_id, inscricao_estadual, crt, certificado_validade_em, serie_nfe)
values ('15300000-0000-4000-8000-000000000002', '257686835', 3, current_date + 365, 2),
       ('15300000-0000-4000-8000-000000000003', '257686836', 3, current_date + 365, 2);
insert into c.empresa_endereco (empresa_id, tipo, cep, logradouro, numero, bairro, cidade, uf, codigo_municipio_ibge)
values ('15300000-0000-4000-8000-000000000002', 'FISCAL', '89219600', 'RUA DONA FRANCISCA', '8300', 'ZONA INDUSTRIAL NORTE', 'JOINVILLE', 'SC', '4209102'),
       ('15300000-0000-4000-8000-000000000003', 'FISCAL', '89219600', 'RUA DONA FRANCISCA', '8300', 'ZONA INDUSTRIAL NORTE', 'JOINVILLE', 'SC', '4209102');
insert into a.usuario (id, auth_user_id, nome, email, ativo)
values ('15300000-0000-4000-8000-000000000011', '15300000-0000-4000-8000-000000000010', 'Teste OS NF-e', 'os-nfe@example.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo)
values ('15300000-0000-4000-8000-000000000011', '15300000-0000-4000-8000-000000000001', 'ADMIN', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo)
values ('15300000-0000-4000-8000-000000000011', '15300000-0000-4000-8000-000000000002', 'FINANCEIRO', true);
insert into public.user_tenant_context (user_id, tenant_id)
values ('15300000-0000-4000-8000-000000000010', '15300000-0000-4000-8000-000000000001');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
values ('15300000-0000-4000-8000-000000000010', '15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000002');

insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social, inscricao_estadual,
  cep, logradouro, numero_endereco, bairro, cidade, uf, pais, indicador_ie, codigo_ibge_municipio)
values (915300, '15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000002',
        'CLIENTE INDUSTRIA', '55666777000181', 'CLIENTE INDUSTRIA LTDA', '222222222',
        '89240000', 'RODOVIA BR 280', 'S/N', 'MORRO GRANDE', 'SAO FRANCISCO DO SUL', 'SC', 'BRASIL', '1', '4216206'),
       (915301, '15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000003',
        'CLIENTE DA OUTRA', '55666777000262', 'CLIENTE DA OUTRA LTDA', '333333333',
        '89240000', 'RUA X', '1', 'CENTRO', 'JOINVILLE', 'SC', 'BRASIL', '1', '4209102');

-- Produto sem NCM, inserido direto (o "criar da OS" nao permite isso).
insert into public.itens (id, tenant_id, empresa_id, codigo_interno, nome, tipo, unidade_medida, finalidade, ativo)
values (915310, '15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000002', 'SEM-NCM', 'ITEM SEM NCM', 'produto', 'UN', 'revenda', true);

insert into f.tributacao_provisoria_homologacao (
  tenant_id, empresa_id, cfop, cst_ipi, c_enq, aliquota_ipi, pendencia_contador,
  natureza_operacao, cst_icms, aliquota_icms_contribuinte, aliquota_icms_consumo,
  aliquota_icms_interestadual_sul_sudeste, aliquota_icms_interestadual_demais, aliquota_icms_importado,
  cst_pis, aliquota_pis, cst_cofins, aliquota_cofins, fonte
) values (
  '15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000002',
  '5101', null, '999', null, 'Fixture de teste com rollback.',
  'VENDA_INDUSTRIALIZACAO_INTERNA', '00', 12, 17, 12, 7, 4, '01', 1.65, '01', 7.6, 'teste'
);

insert into public.ordens_servico (id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id, empresa_id,
  status_fluxo, tipo_documento, codigo, numero_doc, descricao_servico, orcado)
values (915300, 'OS-NFE-1', 'CLIENTE INDUSTRIA', 915300, 'em_andamento', 915300,
        '15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000002',
        'em_andamento', 'OS', 'OS-NFE-001', 1, 'ADICIONAL BARRA NO CARRO', 1000),
       (915301, 'OS-OUTRA-1', 'CLIENTE DA OUTRA', 915301, 'em_andamento', 915301,
        '15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000003',
        'em_andamento', 'OS', 'OS-OUTRA-001', 1, 'OS DA OUTRA EMPRESA', 500);

-- ---------------------------------------------------------------------------
-- Como o usuario FINANCEIRO da empresa
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '15300000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"15300000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;

create temp table ctx (item_id integer, sol_a uuid, sol_b uuid, sol_c uuid, doc_a uuid);
insert into ctx (item_id) values (null);

do $criar_item$
declare v_id integer; v_fi public.fiscal_itens%rowtype; v_item public.itens%rowtype;
begin
  -- Origem e obrigatoria e nunca deduzida.
  begin
    perform public.criar_item_fabricado_da_os(915300, 'PAINEL MONTADO', '85371019', null, 'UN', '50', 9.75, null);
    raise exception 'criar_item_fabricado_da_os aceitou origem nula.';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.criar_item_fabricado_da_os(915300, 'PAINEL MONTADO', '8537', 0, 'UN', '50', 9.75, null);
    raise exception 'criar_item_fabricado_da_os aceitou NCM invalido.';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.criar_item_fabricado_da_os(915300, 'PAINEL MONTADO', '85371019', 0, 'UN', '50', null, null);
    raise exception 'criar_item_fabricado_da_os aceitou IPI tributado sem aliquota.';
  exception when sqlstate '22023' then null;
  end;
  v_id := public.criar_item_fabricado_da_os(915300, 'Painel montado da OS', '8537.10.19', 0, 'un', '50', 9.75, null);
  update ctx set item_id = v_id;
  select * into v_item from public.itens where id = v_id;
  select * into v_fi from public.fiscal_itens where item_id = v_id;
  if not v_item.fabricado or v_item.origem_os_id <> 915300 or v_item.codigo_interno <> 'FAB-OSOS-NFE-1-01' then
    raise exception 'Produto fabricado sem marca/origem/codigo esperados: %', row_to_json(v_item);
  end if;
  if v_fi.ncm <> '85371019' or v_fi.origem <> 0 or v_fi.unidade_tributavel <> 'UN' or v_fi.cst_ipi <> '50' or v_fi.aliq_ipi <> 9.75 then
    raise exception 'fiscal_itens do produto fabricado incompleto: %', row_to_json(v_fi);
  end if;
end;
$criar_item$;

-- Rascunho A: 600 de 1000, com o produto fabricado.
update ctx set sol_a = f.fn_solicitacao_faturamento_criar_os_livre(
  '15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000002', 915300,
  jsonb_build_array(jsonb_build_object('descricao', 'ADICIONAL BARRA NO CARRO', 'quantidade', 1, 'unidade', 'UN', 'valor_unitario', 600, 'item_id', (select item_id from ctx))),
  'VENDA_INDUSTRIALIZACAO_INTERNA');

do $conferir_a$
declare v_r jsonb; v_si f.solicitacao_item%rowtype; v_sf f.solicitacao_faturamento%rowtype; v_s record;
begin
  -- UF divergente do cadastro bloqueia.
  begin
    perform f.fn_os_nfe_conferir_homologacao((select sol_a from ctx),
      '{"destino_uf_confirmada":"PR","destinacao_mercadoria":"USO_CONSUMO","presenca_comprador":9,"pagamento_forma":"15","pagamento_indicador":1}'::jsonb);
    raise exception 'Conferencia aceitou UF divergente.';
  exception when sqlstate '22023' then null;
  end;
  -- Presenca 0 nao vale em venda normal.
  begin
    perform f.fn_os_nfe_conferir_homologacao((select sol_a from ctx),
      '{"destino_uf_confirmada":"SC","destinacao_mercadoria":"USO_CONSUMO","presenca_comprador":0,"pagamento_forma":"15","pagamento_indicador":1}'::jsonb);
    raise exception 'Conferencia aceitou presenca 0.';
  exception when sqlstate '22023' then null;
  end;

  v_r := f.fn_os_nfe_conferir_homologacao((select sol_a from ctx),
    '{"destino_uf_confirmada":"SC","destinacao_mercadoria":"USO_CONSUMO","presenca_comprador":9,"pagamento_forma":"15","pagamento_indicador":1,"pedido_cliente":"749919","observacao":"Entrega combinada"}'::jsonb);
  if coalesce((v_r->>'ok')::boolean, false) is not true then
    raise exception 'Conferencia da OS devolveu pendencias: %', v_r;
  end if;
  if v_r->>'cfop' <> '5101' or v_r->>'natureza_operacao' <> 'VENDA_INDUSTRIALIZACAO_INTERNA' or v_r->>'tributacao_fonte' <> 'FIXTURE_HOMOLOGACAO' then
    raise exception 'Conferencia da OS nao resolveu 5101/fixture: %', v_r;
  end if;
  select * into v_si from f.solicitacao_item where solicitacao_id = (select sol_a from ctx);
  if v_si.cfop <> '5101' or v_si.cst_icms <> '00' or v_si.aliquota_icms <> 17 or v_si.cst_ipi <> '50' or v_si.aliquota_ipi <> 9.75
     or v_si.ipi_codigo_enquadramento_legal <> '999' or v_si.ncm <> '85371019' or v_si.origem_mercadoria <> 0
     or v_si.cst_ibs_cbs <> '000' or v_si.cclass_trib <> '000001' or v_si.perfil_operacao_id is not null
     or v_si.tributacao_fonte <> 'FIXTURE_HOMOLOGACAO' then
    raise exception 'Linha da OS nao recebeu a fixture completa: %', row_to_json(v_si);
  end if;
  select * into v_sf from f.solicitacao_faturamento where id = (select sol_a from ctx);
  if v_sf.natureza_operacao <> 'VENDA_INDUSTRIALIZACAO_INTERNA' or v_sf.consumidor_final <> 1 or v_sf.destino_uf_confirmada <> 'SC'
     or v_sf.snapshot_cadastro_em is null or v_sf.operacao_snapshot->'pagamento'->'parcelas' is null
     or v_sf.pedido_cliente <> '749919' or v_sf.observacao <> 'Entrega combinada' then
    raise exception 'Cabecalho da solicitacao da OS incompleto: %', row_to_json(v_sf);
  end if;
  if (select pedido_compra from public.ordens_servico where id = 915300) <> '749919' then
    raise exception 'Pedido de compra nao foi gravado na OS.';
  end if;
  select * into v_s from f.fn_os_saldo_a_faturar('15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000002', 915300);
  if v_s.valor_reservado <> 600 or v_s.saldo <> 400 then
    raise exception 'Saldo apos rascunho conferido incorreto: %', row_to_json(v_s);
  end if;

  -- Destinacao de contribuinte muda a aliquota para 12 na reconferencia.
  v_r := f.fn_os_nfe_conferir_homologacao((select sol_a from ctx),
    '{"destino_uf_confirmada":"SC","destinacao_mercadoria":"REVENDA","presenca_comprador":9,"pagamento_forma":"15","pagamento_indicador":1}'::jsonb);
  if (select aliquota_icms from f.solicitacao_item where solicitacao_id = (select sol_a from ctx)) <> 12 then
    raise exception 'Destinacao REVENDA nao levou a 12%%.';
  end if;
  v_r := f.fn_os_nfe_conferir_homologacao((select sol_a from ctx),
    '{"destino_uf_confirmada":"SC","destinacao_mercadoria":"USO_CONSUMO","presenca_comprador":9,"pagamento_forma":"15","pagamento_indicador":1}'::jsonb);
end;
$conferir_a$;

-- Rascunho B: 500 (acima do saldo de 400). A conferencia bloqueia antes de qualquer envio.
update ctx set sol_b = f.fn_solicitacao_faturamento_criar_os_livre(
  '15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000002', 915300,
  jsonb_build_array(jsonb_build_object('descricao', 'EXCEDENTE', 'quantidade', 1, 'unidade', 'UN', 'valor_unitario', 500, 'item_id', (select item_id from ctx))),
  'VENDA_INDUSTRIALIZACAO_INTERNA');
do $acima_saldo$
begin
  begin
    perform f.fn_os_nfe_conferir_homologacao((select sol_b from ctx),
      '{"destino_uf_confirmada":"SC","destinacao_mercadoria":"USO_CONSUMO","presenca_comprador":9,"pagamento_forma":"15","pagamento_indicador":1}'::jsonb);
    raise exception 'Conferencia aceitou total acima do saldo.';
  exception when sqlstate '22023' then
    if sqlerrm not like '%acima do saldo%' then raise exception 'Erro inesperado: %', sqlerrm; end if;
  end;
  perform f.fn_solicitacao_nfe_cancelar_rascunho((select sol_b from ctx), 'Rascunho acima do saldo descartado no teste');
end;
$acima_saldo$;

-- Rascunho C: produto sem NCM bloqueia nomeando linha e campo.
update ctx set sol_c = f.fn_solicitacao_faturamento_criar_os_livre(
  '15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000002', 915300,
  jsonb_build_array(jsonb_build_object('descricao', 'SEM NCM', 'quantidade', 1, 'unidade', 'UN', 'valor_unitario', 100, 'item_id', 915310)),
  'VENDA_INDUSTRIALIZACAO_INTERNA');
do $sem_ncm$
begin
  begin
    perform f.fn_os_nfe_conferir_homologacao((select sol_c from ctx),
      '{"destino_uf_confirmada":"SC","destinacao_mercadoria":"USO_CONSUMO","presenca_comprador":9,"pagamento_forma":"15","pagamento_indicador":1}'::jsonb);
    raise exception 'Conferencia aceitou produto sem NCM.';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Linha 1: produto SEM-NCM sem NCM%' then raise exception 'Erro inesperado: %', sqlerrm; end if;
  end;
  perform f.fn_solicitacao_nfe_cancelar_rascunho((select sol_c from ctx), 'Rascunho sem NCM descartado no teste');
end;
$sem_ncm$;

-- Preparo do documento: RASCUNHO com referencia antes de qualquer chamada, os_id_import na OS, idempotente.
do $preparar$
declare v_1 record; v_2 record; v_doc f.documento_fiscal%rowtype;
begin
  select * into v_1 from f.fn_nfe_preparar_documento_solicitacao((select sol_a from ctx));
  select * into v_2 from f.fn_nfe_preparar_documento_solicitacao((select sol_a from ctx));
  if v_1.documento_fiscal_id <> v_2.documento_fiscal_id or v_1.referencia_externa <> v_2.referencia_externa then
    raise exception 'Preparo nao foi idempotente: % / %', row_to_json(v_1), row_to_json(v_2);
  end if;
  if v_1.referencia_externa <> 'NFEH-' || (select sol_a from ctx)::text then
    raise exception 'Referencia inesperada: %', v_1.referencia_externa;
  end if;
  update ctx set doc_a = v_1.documento_fiscal_id;
  select * into v_doc from f.documento_fiscal where id = v_1.documento_fiscal_id;
  if v_doc.os_id_import <> 915300 or v_doc.nfe_status <> 'RASCUNHO' or v_doc.origem <> 'EMITIDO' or v_doc.valor_produtos <> 600 then
    raise exception 'Documento da OS preparado errado: %', row_to_json(v_doc);
  end if;
  if (select count(*) from f.documento_fiscal_emissao where solicitacao_id = (select sol_a from ctx)) <> 1 then
    raise exception 'Duas chamadas com a mesma referencia produziram mais de uma emissao.';
  end if;
end;
$preparar$;

-- Portao de producao: linha de fixture nunca esta pronta para producao.
do $producao$
declare v_p jsonb;
begin
  v_p := f.fn_nfe_producao_pronta((select sol_a from ctx));
  if coalesce((v_p->>'pronta')::boolean, true) then
    raise exception 'Producao considerada pronta com linha de fixture: %', v_p;
  end if;
end;
$producao$;

reset role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

-- Retorno autorizado em homologacao (simulando a Focus): documento continua
-- RASCUNHO, nenhum titulo, saldo segue reservado.
select f.fn_nfe_registrar_envio((select doc_a from ctx), '{"teste":true}'::jsonb, '{"status":"processando_autorizacao"}'::jsonb, 'PROCESSANDO');
select f.fn_nfe_aplicar_retorno(
  'NFEH-' || (select sol_a from ctx)::text, '{"status":"autorizado"}'::jsonb,
  'AUTORIZADA', repeat('3', 44), '333456789012345', 1, 2, 100,
  'Autorizado o uso da NF-e', 'teste/os.xml', 'teste/os.pdf',
  '<NFe xmlns="http://www.portalfiscal.inf.br/nfe"><infNFe><emit><CNPJ>33333333000191</CNPJ></emit></infNFe></NFe>',
  'CALLBACK'
);
do $retorno$
declare v_s record; v_doc f.documento_fiscal%rowtype; v_e f.documento_fiscal_emissao%rowtype;
begin
  select * into v_doc from f.documento_fiscal where id = (select doc_a from ctx);
  select * into v_e from f.documento_fiscal_emissao where documento_fiscal_id = (select doc_a from ctx);
  if v_e.status <> 'AUTORIZADA' or v_doc.nfe_status <> 'RASCUNHO' then
    raise exception 'Homologacao alterou o documento: emissao %, documento %', v_e.status, v_doc.nfe_status;
  end if;
  if exists (select 1 from f.titulo where documento_fiscal_id = (select doc_a from ctx) and deleted_at is null) then
    raise exception 'Homologacao criou titulo financeiro.';
  end if;
  select * into v_s from f.fn_os_saldo_a_faturar('15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000002', 915300);
  if v_s.valor_faturado <> 0 or v_s.valor_reservado <> 600 or v_s.saldo <> 400 then
    raise exception 'Saldo apos autorizacao em homologacao incorreto: %', row_to_json(v_s);
  end if;
  if (select count(*) from f.fn_os_notas('15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000002', 915300)) <> 1 then
    raise exception 'fn_os_notas nao listou a nota da OS.';
  end if;
  -- Faturada exige documento emitido E saldo zero: nenhum dos dois ainda.
  if f.fn_os_pronta_para_faturada('15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000002', 915300) then
    raise exception 'OS considerada pronta para Faturada sem documento emitido.';
  end if;
end;
$retorno$;

-- Abandono da homologacao devolve o saldo (mesma acao da OV).
select set_config('request.jwt.claim.sub', '15300000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"15300000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;
select f.fn_solicitacao_nfe_abandonar_homologacao((select sol_a from ctx), 'Homologacao abandonada no teste da OS');
do $abandono$
declare v_s record;
begin
  select * into v_s from f.fn_os_saldo_a_faturar('15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000002', 915300);
  if v_s.valor_reservado <> 0 or v_s.saldo <> 1000 then
    raise exception 'Abandono nao devolveu o saldo: %', row_to_json(v_s);
  end if;
  -- A lista da OS mostra a homologacao abandonada (emissao AUTORIZADA, solicitacao CANCELADA).
  if not exists (
    select 1 from f.fn_os_notas('15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000002', 915300)
    where emissao_status = 'AUTORIZADA' and solicitacao_status = 'CANCELADA'
  ) then
    raise exception 'fn_os_notas nao expos o status CANCELADA da solicitacao abandonada.';
  end if;
  -- RLS: a OS da outra empresa nao aparece para este usuario.
  if (select count(*) from f.fn_os_notas('15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000003', 915301)) <> 0 then
    raise exception 'fn_os_notas vazou notas de outra empresa.';
  end if;
  -- O bloqueio por tenant/empresa das RPCs usa session_user, que aqui continua
  -- 'postgres' mesmo com set local role; a isolacao por RLS das tabelas esta
  -- coberta em faturamento_rls_authenticated.sql.
end;
$abandono$;
reset role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

-- Faturada: documento vinculado (importado, sem nfe_status, como os XMLs de saida
-- carregados) E saldo zero. EMITIDA dispararia o AR e exigiria plano de contas.
insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, emissao_date,
  valor_total, valor_produtos, operacao, natureza, origem, nfe_status, cliente_id, os_id_import)
values ('15300000-0000-4000-8000-000000000900', '15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000002',
  repeat('4', 44), '55', '1', '900', current_date, 1000, 1000, 'SAIDA', 'PRODUTO', 'IMPORTADO', null, 915300, 915300);
update public.ordens_servico set status_fluxo = 'concluida', status = 'concluida' where id = 915300;
do $faturada$
declare v_s record;
begin
  select * into v_s from f.fn_os_saldo_a_faturar('15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000002', 915300);
  if v_s.saldo <> 0 then raise exception 'Saldo esperado zero apos documento emitido: %', row_to_json(v_s); end if;
  if not f.fn_os_pronta_para_faturada('15300000-0000-4000-8000-000000000001', '15300000-0000-4000-8000-000000000002', 915300) then
    raise exception 'OS com documento emitido e saldo zero nao ficou pronta para Faturada.';
  end if;
end;
$faturada$;
select set_config('request.jwt.claim.sub', '15300000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"15300000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;
select public.os_faturar(915300);
do $faturada_ok$
begin
  if (select status_fluxo from public.ordens_servico where id = 915300) <> 'faturada' then
    raise exception 'os_faturar nao marcou a OS como faturada.';
  end if;
end;
$faturada_ok$;
reset role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select 'OS NF-e homologacao: produto fabricado, fixture 5101, saldo, bloqueios, idempotencia, portao de producao e Faturada passaram.' as resultado;
rollback;
