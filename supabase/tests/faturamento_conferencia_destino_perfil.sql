\set ON_ERROR_STOP on
begin;

insert into c.tenant (id, codigo, nome)
values ('16000000-0000-4000-8000-000000000001', 'TESTE-DESTINO', 'Teste destino e perfil NF-e');

insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj)
values (
  '16000000-0000-4000-8000-000000000002',
  '16000000-0000-4000-8000-000000000001',
  'SEGTESTE', 'SEG TESTE LTDA', 'SEG TESTE', '13671448000189'
);

insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, uf, cidade)
values (
  '16000000-0000-4000-8000-000000000002',
  '16000000-0000-4000-8000-000000000001',
  '13671448000189', 'SEG TESTE LTDA', 'SEG TESTE', 'SC', 'JOINVILLE'
) on conflict (id) do nothing;

insert into c.empresa_fiscal (empresa_id, inscricao_estadual, crt, certificado_validade_em)
values ('16000000-0000-4000-8000-000000000002', '257686835', 3, current_date + 365);

insert into c.empresa_endereco (
  empresa_id, tipo, cep, logradouro, numero, bairro, cidade, uf, codigo_municipio_ibge
) values (
  '16000000-0000-4000-8000-000000000002', 'FISCAL', '89219600',
  'RUA DONA FRANCISCA', '8300', 'ZONA INDUSTRIAL NORTE', 'JOINVILLE', 'SC', '4209102'
);

insert into public.clientes (
  id, tenant_id, empresa_id, nome, documento, razao_social, inscricao_estadual,
  cep, logradouro, numero_endereco, bairro, cidade, uf, pais, indicador_ie, codigo_ibge_municipio
) values
  (916001, '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'CLIENTE SC', '11111111000191', 'CLIENTE SC LTDA', '111111111', '88000000', 'RUA SC', '1', 'CENTRO', 'FLORIANOPOLIS', 'SC', 'BRASIL', '1', '4205407'),
  (916002, '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'CLIENTE SC NAO CONTRIBUINTE', '22222222000191', 'CLIENTE SC NAO CONTRIBUINTE LTDA', null, '88000000', 'RUA SC', '2', 'CENTRO', 'FLORIANOPOLIS', 'SC', 'BRASIL', '9', '4205407'),
  (916003, '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'CLIENTE SP', '33333333000191', 'CLIENTE SP LTDA', '222222222', '01000000', 'RUA SP', '3', 'CENTRO', 'SAO PAULO', 'SP', 'BRASIL', '1', '3550308'),
  (916004, '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'CLIENTE BA', '44444444000191', 'CLIENTE BA LTDA', '333333333', '40000000', 'RUA BA', '4', 'CENTRO', 'SALVADOR', 'BA', 'BRASIL', '1', '2927408'),
  (916005, '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'CLIENTE SP NAO CONTRIBUINTE', '55555555000191', 'CLIENTE SP NAO CONTRIBUINTE LTDA', null, '01000000', 'RUA SP', '5', 'CENTRO', 'SAO PAULO', 'SP', 'BRASIL', '9', '3550308');

insert into public.itens (
  id, tenant_id, empresa_id, codigo_interno, nome, tipo, unidade_medida, finalidade, ativo
) values
  (916001, '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'ORIG-0', 'ITEM ORIGEM ZERO', 'produto', 'UN', 'revenda', true),
  (916002, '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'ORIG-1', 'ITEM ORIGEM UM', 'produto', 'UN', 'revenda', true),
  (916003, '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'ORIG-2', 'ITEM ORIGEM DOIS', 'produto', 'UN', 'revenda', true),
  (916004, '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'ORIG-6', 'ITEM ORIGEM SEIS', 'produto', 'UN', 'revenda', true),
  (916005, '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'SEM-ORIG', 'ITEM SEM ORIGEM', 'produto', 'UN', 'revenda', true);

update public.fiscal_itens
set ncm = '85371020', unidade_tributavel = 'UN', cst_ipi = '53'
where tenant_id = '16000000-0000-4000-8000-000000000001'
  and empresa_id = '16000000-0000-4000-8000-000000000002';

insert into f.tributacao_provisoria_homologacao (
  tenant_id, empresa_id, cfop, cst_ipi, c_enq, aliquota_ipi, pendencia_contador
) values
  ('16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', '5102', '53', '999', null, 'Fixture de teste com rollback.'),
  ('16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', '6102', '53', '999', null, 'Fixture de teste com rollback.');
update public.fiscal_itens set origem = 0
where tenant_id = '16000000-0000-4000-8000-000000000001'
  and empresa_id = '16000000-0000-4000-8000-000000000002'
  and item_id = 916001;
update public.fiscal_itens set origem = 1
where tenant_id = '16000000-0000-4000-8000-000000000001'
  and empresa_id = '16000000-0000-4000-8000-000000000002'
  and item_id = 916002;
update public.fiscal_itens set origem = 2
where tenant_id = '16000000-0000-4000-8000-000000000001'
  and empresa_id = '16000000-0000-4000-8000-000000000002'
  and item_id = 916003;
update public.fiscal_itens set origem = 6
where tenant_id = '16000000-0000-4000-8000-000000000001'
  and empresa_id = '16000000-0000-4000-8000-000000000002'
  and item_id = 916004;

insert into f.perfil_operacao (
  id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto,
  crt, ambito_destino, ufs_destino, indicador_ie_destinatario, origem_mercadoria,
  cfop_interno, cfop_externo, cst_icms, icms_modalidade_base_calculo, aliquota_icms,
  reducao_base_icms_percentual, cbenef_aplicacao, cst_pis, aliquota_pis,
  cst_cofins, aliquota_cofins, finalidade_emissao, consumidor_final,
  faixa_automacao, habilitado_producao
) values
  ('16100000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'SEG-VENDA-TERCEIROS-SC-5102-O2-CST00', 'Venda interna origem 2', 'NFE', 'VENDA_MERCADORIA_TERCEIROS', 'VENDA', '3', 'INTERNA', array['SC'], '1', 2, '5102', null, '00', '3', 12, 0, 'SEM_BENEFICIO', '01', 1.65, '01', 7.6, 1, 0, 'REVISAO', false),
  ('16100000-0000-4000-8000-000000000002', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'SEG-INTERNA-NCONTRIB-O0', 'Venda interna nao contribuinte', 'NFE', 'VENDA_MERCADORIA_TERCEIROS', 'VENDA', '3', 'INTERNA', array['SC'], '9', 0, '5102', null, '00', '3', 12, 0, 'SEM_BENEFICIO', '01', 1.65, '01', 7.6, 1, 1, 'REVISAO', false),
  ('16100000-0000-4000-8000-000000000003', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'SEG-SP-6102-O0-12', 'Venda SP nacional', 'NFE', 'VENDA_MERCADORIA_TERCEIROS', 'VENDA', '3', 'INTERESTADUAL', array['SP'], '1', 0, null, '6102', '00', '3', 12, 0, 'SEM_BENEFICIO', '01', 1.65, '01', 7.6, 1, 0, 'REVISAO', false),
  ('16100000-0000-4000-8000-000000000004', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'SEG-BA-6102-O0-7', 'Venda BA nacional', 'NFE', 'VENDA_MERCADORIA_TERCEIROS', 'VENDA', '3', 'INTERESTADUAL', array['BA'], '1', 0, null, '6102', '00', '3', 7, 0, 'SEM_BENEFICIO', '01', 1.65, '01', 7.6, 1, 0, 'REVISAO', false),
  ('16100000-0000-4000-8000-000000000005', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'SEG-SP-6102-O1-4', 'Venda SP origem 1', 'NFE', 'VENDA_MERCADORIA_TERCEIROS', 'VENDA', '3', 'INTERESTADUAL', array['SP'], '1', 1, null, '6102', '00', '3', 4, 0, 'SEM_BENEFICIO', '01', 1.65, '01', 7.6, 1, 0, 'REVISAO', false),
  ('16100000-0000-4000-8000-000000000006', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'SEG-SP-6102-O2-4', 'Venda SP origem 2', 'NFE', 'VENDA_MERCADORIA_TERCEIROS', 'VENDA', '3', 'INTERESTADUAL', array['SP'], '1', 2, null, '6102', '00', '3', 4, 0, 'SEM_BENEFICIO', '01', 1.65, '01', 7.6, 1, 0, 'REVISAO', false),
  ('16100000-0000-4000-8000-000000000007', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'SEG-SP-6102-O6-4', 'Venda SP origem 6', 'NFE', 'VENDA_MERCADORIA_TERCEIROS', 'VENDA', '3', 'INTERESTADUAL', array['SP'], '1', 6, null, '6102', '00', '3', 4, 0, 'SEM_BENEFICIO', '01', 1.65, '01', 7.6, 1, 0, 'REVISAO', false);

insert into f.solicitacao_faturamento (
  id, tenant_id, empresa_id, cliente_id, status, natureza_operacao
) values
  ('16200000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 916001, 'RASCUNHO', 'VENDA_MERCADORIA_TERCEIROS'),
  ('16200000-0000-4000-8000-000000000002', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 916002, 'RASCUNHO', 'VENDA_MERCADORIA_TERCEIROS'),
  ('16200000-0000-4000-8000-000000000003', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 916003, 'RASCUNHO', 'VENDA_MERCADORIA_TERCEIROS'),
  ('16200000-0000-4000-8000-000000000004', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 916004, 'RASCUNHO', 'VENDA_MERCADORIA_TERCEIROS'),
  ('16200000-0000-4000-8000-000000000005', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 916003, 'RASCUNHO', 'VENDA_MERCADORIA_TERCEIROS'),
  ('16200000-0000-4000-8000-000000000006', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 916003, 'RASCUNHO', 'VENDA_MERCADORIA_TERCEIROS'),
  ('16200000-0000-4000-8000-000000000007', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 916003, 'RASCUNHO', 'VENDA_MERCADORIA_TERCEIROS'),
  ('16200000-0000-4000-8000-000000000008', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 916005, 'RASCUNHO', 'VENDA_MERCADORIA_TERCEIROS'),
  ('16200000-0000-4000-8000-000000000009', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 916001, 'RASCUNHO', 'VENDA_MERCADORIA_TERCEIROS'),
  ('16200000-0000-4000-8000-000000000010', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 916001, 'RASCUNHO', 'VENDA_MERCADORIA_TERCEIROS'),
  ('16200000-0000-4000-8000-000000000011', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 916004, 'RASCUNHO', 'VENDA_MERCADORIA_TERCEIROS'),
  ('16200000-0000-4000-8000-000000000012', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 916003, 'RASCUNHO', 'VENDA_MERCADORIA_TERCEIROS');

insert into f.solicitacao_item (
  id, solicitacao_id, tenant_id, empresa_id, origem_tipo, origem_id, item_id,
  codigo_produto, descricao, quantidade, unidade, valor_unitario, valor_desconto, ordem
) values
  ('16300000-0000-4000-8000-000000000001', '16200000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'OV', '1', 916003, 'ORIG-2', 'ITEM ORIGEM DOIS', 1, 'UN', 100, 0, 1),
  ('16300000-0000-4000-8000-000000000002', '16200000-0000-4000-8000-000000000002', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'OV', '2', 916001, 'ORIG-0', 'ITEM ORIGEM ZERO', 1, 'UN', 100, 0, 1),
  ('16300000-0000-4000-8000-000000000003', '16200000-0000-4000-8000-000000000003', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'OV', '3', 916001, 'ORIG-0', 'ITEM ORIGEM ZERO', 1, 'UN', 100, 0, 1),
  ('16300000-0000-4000-8000-000000000004', '16200000-0000-4000-8000-000000000004', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'OV', '4', 916001, 'ORIG-0', 'ITEM ORIGEM ZERO', 1, 'UN', 100, 0, 1),
  ('16300000-0000-4000-8000-000000000005', '16200000-0000-4000-8000-000000000005', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'OV', '5', 916002, 'ORIG-1', 'ITEM ORIGEM UM', 1, 'UN', 100, 0, 1),
  ('16300000-0000-4000-8000-000000000006', '16200000-0000-4000-8000-000000000006', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'OV', '6', 916003, 'ORIG-2', 'ITEM ORIGEM DOIS', 1, 'UN', 100, 0, 1),
  ('16300000-0000-4000-8000-000000000007', '16200000-0000-4000-8000-000000000007', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'OV', '7', 916004, 'ORIG-6', 'ITEM ORIGEM SEIS', 1, 'UN', 100, 0, 1),
  ('16300000-0000-4000-8000-000000000008', '16200000-0000-4000-8000-000000000008', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'OV', '8', 916001, 'ORIG-0', 'ITEM ORIGEM ZERO', 1, 'UN', 100, 0, 1),
  ('16300000-0000-4000-8000-000000000009', '16200000-0000-4000-8000-000000000009', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'OV', '9', 916001, 'ORIG-0', 'ITEM ORIGEM ZERO', 1, 'UN', 100, 0, 1),
  ('16300000-0000-4000-8000-000000000010', '16200000-0000-4000-8000-000000000010', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'OV', '10', 916005, 'SEM-ORIG', 'ITEM SEM ORIGEM', 1, 'UN', 100, 0, 1),
  ('16300000-0000-4000-8000-000000000011', '16200000-0000-4000-8000-000000000011', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'OV', '11', 916003, 'ORIG-2', 'ITEM ORIGEM DOIS', 1, 'UN', 100, 0, 1),
  ('16300000-0000-4000-8000-000000000012', '16200000-0000-4000-8000-000000000012', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'OV', '12', 916001, 'ORIG-0', 'ITEM ORIGEM ZERO', 1, 'UN', 100, 0, 1),
  ('16300000-0000-4000-8000-000000000013', '16200000-0000-4000-8000-000000000012', '16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000002', 'OV', '12', 916003, 'ORIG-2', 'ITEM ORIGEM DOIS', 1, 'UN', 100, 0, 2);

do $test$
declare
  r jsonb;
  item jsonb;
begin
  -- 1: interna SC contribuinte resolve o perfil e leva IPI somente da fixture.
  r := f.fn_solicitacao_nfe_resolver_perfis('16200000-0000-4000-8000-000000000001', 'SC');
  item := r->'itens'->0;
  if item->>'perfil_codigo' <> 'SEG-VENDA-TERCEIROS-SC-5102-O2-CST00'
     or item#>>'{ipi_operacao,cst}' <> '53'
     or item#>>'{ipi_operacao,c_enq}' <> '999'
     or item#>>'{ipi_operacao,fonte}' <> 'FIXTURE_HOMOLOGACAO'
     then raise exception 'Cenario 1 falhou: %', r; end if;

  -- 2: interna SC nao contribuinte pode ter perfil proprio sem DIFAL.
  r := f.fn_solicitacao_nfe_resolver_perfis('16200000-0000-4000-8000-000000000002', 'SC');
  if r->'itens'->0->>'perfil_codigo' <> 'SEG-INTERNA-NCONTRIB-O0' then raise exception 'Cenario 2 falhou: %', r; end if;

  -- 3 e 4: interestadual nacional encontra faixa 12 para SP e 7 para BA.
  r := f.fn_solicitacao_nfe_resolver_perfis('16200000-0000-4000-8000-000000000003', 'SP');
  if (r->'itens'->0->>'aliquota_referencia_busca')::numeric <> 12 or r->'itens'->0->>'perfil_codigo' <> 'SEG-SP-6102-O0-12' then raise exception 'Cenario 3 falhou: %', r; end if;
  r := f.fn_solicitacao_nfe_resolver_perfis('16200000-0000-4000-8000-000000000004', 'BA');
  if (r->'itens'->0->>'aliquota_referencia_busca')::numeric <> 7 or r->'itens'->0->>'perfil_codigo' <> 'SEG-BA-6102-O0-7' then raise exception 'Cenario 4 falhou: %', r; end if;

  -- 5, 6 e 7: origens 1, 2 e 6 procuram exclusivamente faixa de 4%.
  r := f.fn_solicitacao_nfe_resolver_perfis('16200000-0000-4000-8000-000000000005', 'SP'); if (r->'itens'->0->>'aliquota_referencia_busca')::numeric <> 4 or r->'itens'->0->>'perfil_codigo' <> 'SEG-SP-6102-O1-4' then raise exception 'Cenario 5 falhou: %', r; end if;
  r := f.fn_solicitacao_nfe_resolver_perfis('16200000-0000-4000-8000-000000000006', 'SP'); if (r->'itens'->0->>'aliquota_referencia_busca')::numeric <> 4 or r->'itens'->0->>'perfil_codigo' <> 'SEG-SP-6102-O2-4' then raise exception 'Cenario 6 falhou: %', r; end if;
  r := f.fn_solicitacao_nfe_resolver_perfis('16200000-0000-4000-8000-000000000007', 'SP'); if (r->'itens'->0->>'aliquota_referencia_busca')::numeric <> 4 or r->'itens'->0->>'perfil_codigo' <> 'SEG-SP-6102-O6-4' then raise exception 'Cenario 7 falhou: %', r; end if;

  -- 8: interestadual nao contribuinte bloqueia e nomeia DIFAL.
  r := f.fn_solicitacao_nfe_resolver_perfis('16200000-0000-4000-8000-000000000008', 'SP');
  if coalesce((r->>'ok')::boolean, true) or position('DIFAL' in coalesce(r->>'bloqueio','')) = 0 then raise exception 'Cenario 8 falhou: %', r; end if;

  -- 9: UF divergente bloqueia e oferece a tela do cliente; nao altera cadastro.
  r := f.fn_solicitacao_nfe_resolver_perfis('16200000-0000-4000-8000-000000000009', 'SP');
  if coalesce((r->>'ok')::boolean, true) or r->>'rota_cliente' not like '/clientes/cadastro-fiscal?cliente_id=%'
     or (select uf from public.clientes
         where tenant_id = '16000000-0000-4000-8000-000000000001'
           and empresa_id = '16000000-0000-4000-8000-000000000002'
           and id = 916001) <> 'SC' then raise exception 'Cenario 9 falhou: %', r; end if;

  -- 10: origem ausente e 11: perfil ausente produzem diagnosticos diferentes.
  r := f.fn_solicitacao_nfe_resolver_perfis('16200000-0000-4000-8000-000000000010', 'SC');
  if r->'itens'->0->>'status' <> 'PRODUTO_INCOMPLETO' then raise exception 'Cenario 10 falhou: %', r; end if;
  r := f.fn_solicitacao_nfe_resolver_perfis('16200000-0000-4000-8000-000000000011', 'BA');
  if r->'itens'->0->>'status' <> 'SEM_PERFIL' then raise exception 'Cenario 11 falhou: %', r; end if;

  -- 12: uma nota mista resolve perfil por linha, sem perfil unico incorreto.
  r := f.fn_solicitacao_nfe_resolver_perfis('16200000-0000-4000-8000-000000000012', 'SP');
  if jsonb_array_length(r->'itens') <> 2
     or not (r->'itens' @> '[{"perfil_codigo":"SEG-SP-6102-O0-12"}]'::jsonb)
     or not (r->'itens' @> '[{"perfil_codigo":"SEG-SP-6102-O2-4"}]'::jsonb) then raise exception 'Cenario 12 falhou: %', r; end if;

  -- 13: a RPC rejeita adulteracao de campo bloqueado pelo perfil.
  begin
    perform f.fn_solicitacao_nfe_salvar_conferencia(
      '16200000-0000-4000-8000-000000000001',
      '{"destino_uf_confirmada":"SC","finalidade_emissao":1,"consumidor_final":0,"presenca_comprador":9,"modalidade_frete":9,"valor_frete":0,"valor_seguro":0,"valor_outras_despesas":0}',
      '[{"id":"16300000-0000-4000-8000-000000000001","perfil_operacao_id":"16100000-0000-4000-8000-000000000001","cfop":"5102","cst_icms":"00","cst_ipi":"53","ipi_codigo_enquadramento_legal":"999","cst_pis":"01","cst_cofins":"01","reducao_base_icms_percentual":0,"icms_modalidade_base_calculo":"3","aliquota_icms":13,"aliquota_ipi":null,"aliquota_pis":1.65,"aliquota_cofins":7.6,"cst_ibs_cbs":"000","cclass_trib":"000001","cclass_trib_versao":"TESTE","ibs_cbs_json":{"ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9},"numero_fci":null}]'
    );
    raise exception 'Cenario 13 aceitou ICMS adulterado.';
  exception when sqlstate '22023' then null;
  end;

  -- 14: IBS/CBS sem default continua vazio e bloqueia ate confirmacao humana.
  if (item->'perfil'->>'cst_ibs_cbs') is not null
     or (item->'perfil'->>'cclass_trib') is not null
     or jsonb_typeof(item->'perfil'->'ibs_cbs_json') is distinct from 'null' then raise exception 'Cenario 14 encontrou default IBS/CBS no perfil: %', item; end if;
  begin
    perform f.fn_solicitacao_nfe_salvar_conferencia(
      '16200000-0000-4000-8000-000000000001',
      '{"destino_uf_confirmada":"SC","finalidade_emissao":1,"consumidor_final":0,"presenca_comprador":9,"modalidade_frete":9,"valor_frete":0,"valor_seguro":0,"valor_outras_despesas":0}',
      '[{"id":"16300000-0000-4000-8000-000000000001","perfil_operacao_id":"16100000-0000-4000-8000-000000000001","cfop":"5102","cst_icms":"00","cst_ipi":"53","ipi_codigo_enquadramento_legal":"999","cst_pis":"01","cst_cofins":"01","reducao_base_icms_percentual":0,"icms_modalidade_base_calculo":"3","aliquota_icms":12,"aliquota_ipi":null,"aliquota_pis":1.65,"aliquota_cofins":7.6,"cst_ibs_cbs":"","cclass_trib":"","cclass_trib_versao":"","ibs_cbs_json":{},"numero_fci":null}]'
    );
    raise exception 'Cenario 14 aceitou IBS/CBS vazio.';
  exception when sqlstate '22023' then null;
  end;

  -- 15: chamar a RPC diretamente nao permite salvar linha sem perfil resolvido.
  begin
    perform f.fn_solicitacao_nfe_salvar_conferencia(
      '16200000-0000-4000-8000-000000000011',
      '{"destino_uf_confirmada":"BA","finalidade_emissao":1,"consumidor_final":0,"presenca_comprador":9,"modalidade_frete":9,"valor_frete":0,"valor_seguro":0,"valor_outras_despesas":0}',
      '[{"id":"16300000-0000-4000-8000-000000000011","perfil_operacao_id":null,"cfop":"6102","cst_icms":"00","cst_ipi":"53","ipi_codigo_enquadramento_legal":"999","cst_pis":"01","cst_cofins":"01","reducao_base_icms_percentual":0,"icms_modalidade_base_calculo":"3","aliquota_icms":7,"aliquota_ipi":null,"aliquota_pis":1.65,"aliquota_cofins":7.6,"cst_ibs_cbs":"000","cclass_trib":"000001","cclass_trib_versao":"TESTE","ibs_cbs_json":{"ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9},"numero_fci":null}]'
    );
    raise exception 'Cenario 15 aceitou item sem perfil resolvido.';
  exception when sqlstate '22023' then null;
  end;
end;
$test$;

-- Um salvamento valido prova o carimbo de destino/perfil e que zero explicito e preservado.
select f.fn_solicitacao_nfe_salvar_conferencia(
  '16200000-0000-4000-8000-000000000001',
  '{"destino_uf_confirmada":"SC","finalidade_emissao":1,"consumidor_final":0,"presenca_comprador":9,"modalidade_frete":9,"valor_frete":0,"valor_seguro":0,"valor_outras_despesas":0}'::jsonb,
  '[{"id":"16300000-0000-4000-8000-000000000001","perfil_operacao_id":"16100000-0000-4000-8000-000000000001","cfop":"5102","cst_icms":"00","cst_ipi":"53","ipi_codigo_enquadramento_legal":"999","cst_pis":"01","cst_cofins":"01","reducao_base_icms_percentual":0,"icms_modalidade_base_calculo":"3","aliquota_icms":12,"aliquota_ipi":null,"aliquota_pis":1.65,"aliquota_cofins":7.6,"cst_ibs_cbs":"000","cclass_trib":"000001","cclass_trib_versao":"TESTE","ibs_cbs_json":{"ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9},"numero_fci":null}]'::jsonb
);

do $audit$
begin
  if not exists (
    select 1 from f.solicitacao_faturamento sf
    where sf.id = '16200000-0000-4000-8000-000000000001'
      and sf.destino_uf_confirmada = 'SC' and sf.destino_confirmado_em is not null
      and sf.perfil_aplicado_em is not null and sf.valor_frete = 0
  ) or not exists (
    select 1 from f.solicitacao_item si
    where si.id = '16300000-0000-4000-8000-000000000001'
      and si.perfil_operacao_id = '16100000-0000-4000-8000-000000000001'
      and si.perfil_aplicado_em is not null
  ) then raise exception 'Auditoria de destino/perfil nao foi gravada.'; end if;
end;
$audit$;

rollback;
