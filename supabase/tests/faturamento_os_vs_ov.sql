\set ON_ERROR_STOP on

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values (
  '15200000-0000-4000-8000-000000000010',
  'authenticated', 'authenticated', 'faturamento-os-vs-ov@example.test',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"nome":"Teste OS versus OV"}'::jsonb, now(), now()
);

insert into public.tenants (id, nome, ativo)
values ('15200000-0000-4000-8000-000000000001', 'Teste OS com linhas livres', true);

insert into c.tenant (id, codigo, nome)
values ('15200000-0000-4000-8000-000000000001', 'TESTE-OS-LIVRE', 'Teste OS com linhas livres');

insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj)
values (
  '15200000-0000-4000-8000-000000000002',
  '15200000-0000-4000-8000-000000000001',
  'OSLIVRE', 'EMPRESA TESTE OS LIVRE LTDA', 'OS LIVRE', '22222222000191'
);

insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, uf, cidade)
values (
  '15200000-0000-4000-8000-000000000002',
  '15200000-0000-4000-8000-000000000001',
  '22222222000191', 'EMPRESA TESTE OS LIVRE LTDA', 'OS LIVRE', 'SC', 'JOINVILLE'
)
on conflict (id) do nothing;

insert into c.empresa_fiscal (empresa_id, inscricao_estadual, crt, certificado_validade_em, serie_nfe)
values ('15200000-0000-4000-8000-000000000002', '257686835', 3, current_date + 365, 2);

insert into c.empresa_endereco (
  empresa_id, tipo, cep, logradouro, numero, bairro, cidade, uf, codigo_municipio_ibge
) values (
  '15200000-0000-4000-8000-000000000002', 'FISCAL', '89219600',
  'RUA DONA FRANCISCA', '8300', 'ZONA INDUSTRIAL NORTE', 'JOINVILLE', 'SC', '4209102'
);

insert into a.usuario (id, auth_user_id, nome, email, ativo)
values (
  '15200000-0000-4000-8000-000000000011',
  '15200000-0000-4000-8000-000000000010',
  'Teste OS versus OV', 'faturamento-os-vs-ov@example.test', true
);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo)
values (
  '15200000-0000-4000-8000-000000000011',
  '15200000-0000-4000-8000-000000000001', 'ADMIN', true
);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo)
values (
  '15200000-0000-4000-8000-000000000011',
  '15200000-0000-4000-8000-000000000002', 'DIRETOR', true
);
insert into public.user_tenant_context (user_id, tenant_id)
values (
  '15200000-0000-4000-8000-000000000010',
  '15200000-0000-4000-8000-000000000001'
);
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
values (
  '15200000-0000-4000-8000-000000000010',
  '15200000-0000-4000-8000-000000000001',
  '15200000-0000-4000-8000-000000000002'
);

insert into public.clientes (
  id, tenant_id, empresa_id, nome, documento, razao_social, inscricao_estadual,
  cep, logradouro, numero_endereco, bairro, cidade, uf, pais, indicador_ie,
  codigo_ibge_municipio
)
values (
  915200,
  '15200000-0000-4000-8000-000000000001',
  '15200000-0000-4000-8000-000000000002',
  'CLIENTE TESTE OS LIVRE', '22333444000181', 'CLIENTE TESTE OS LIVRE LTDA',
  '111111111', '88000000', 'RUA TESTE', '1', 'CENTRO', 'FLORIANOPOLIS',
  'SC', 'BRASIL', '1', '4205407'
);

insert into public.itens (
  id, tenant_id, empresa_id, codigo_interno, nome, tipo,
  unidade_medida, finalidade, ativo
)
values (
  915200,
  '15200000-0000-4000-8000-000000000001',
  '15200000-0000-4000-8000-000000000002',
  'KIT-OS', 'KIT DE INSTALACAO', 'produto', 'UN', 'revenda', true
);

update public.fiscal_itens
set ncm = '85371020', origem = 0, unidade_tributavel = 'UN', cst_ipi = '53'
where tenant_id = '15200000-0000-4000-8000-000000000001'
  and empresa_id = '15200000-0000-4000-8000-000000000002'
  and item_id = 915200;

insert into f.tributacao_provisoria_homologacao (
  tenant_id, empresa_id, cfop, cst_ipi, c_enq, aliquota_ipi, pendencia_contador
) values (
  '15200000-0000-4000-8000-000000000001',
  '15200000-0000-4000-8000-000000000002',
  '5102', '53', '999', null, 'Fixture de teste com rollback.'
);

insert into f.perfil_operacao (
  id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto,
  crt, ambito_destino, ufs_destino, indicador_ie_destinatario, origem_mercadoria,
  cfop_interno, cfop_externo, cst_icms, icms_modalidade_base_calculo,
  aliquota_icms, reducao_base_icms_percentual, cbenef_aplicacao, cst_pis,
  cst_cofins, finalidade_emissao, consumidor_final, faixa_automacao,
  habilitado_producao, cst_ibs_cbs, cclass_trib, cclass_trib_versao, ibs_cbs_json
) values (
  '15200000-0000-4000-8000-000000000301',
  '15200000-0000-4000-8000-000000000001',
  '15200000-0000-4000-8000-000000000002',
  'TESTE-OV-SC-5102-O0-CST00', 'Venda interna para teste da OV', 'NFE',
  'VENDA_MERCADORIA_TERCEIROS', 'VENDA', '3', 'INTERNA', array['SC'], '1', 0,
  '5102', null, '00', '3', 17, 0, 'SEM_BENEFICIO', '49', '49', 1, 0,
  'REVISAO', false, '000', '000001', 'Informe Técnico 2025.002 v1.60',
  '{"ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9}'::jsonb
);

insert into public.ordens_servico (
  id, numero_os, cliente_nome, cliente_id, status, os_num,
  tenant_id, empresa_id, status_fluxo, tipo_documento, codigo,
  numero_doc, descricao_servico, orcado
)
values
  (
    915200, 'OS-LIVRE-1', 'CLIENTE TESTE OS LIVRE', 915200,
    'em_andamento', 915200,
    '15200000-0000-4000-8000-000000000001',
    '15200000-0000-4000-8000-000000000002',
    'em_andamento', 'OS', 'OS-LIVRE-001', 1,
    'PAINEL MONTADO EXTRUSORA 14', 1000
  ),
  (
    915201, 'OS-LIVRE-2', 'CLIENTE TESTE OS LIVRE', 915200,
    'em_andamento', 915201,
    '15200000-0000-4000-8000-000000000001',
    '15200000-0000-4000-8000-000000000002',
    'em_andamento', 'OS', 'OS-LIVRE-002', 2,
    'START-UP LINHA 2', 500
  ),
  (
    915202, 'OV-CONTROLE-1', 'CLIENTE TESTE OS LIVRE', 915200,
    'em_andamento', 915202,
    '15200000-0000-4000-8000-000000000001',
    '15200000-0000-4000-8000-000000000002',
    'em_andamento', 'OV', 'OV-CONTROLE-001', 3,
    'VENDA DE KIT', 200
  ),
  (
    915203, 'OV-RPC-1', 'CLIENTE TESTE OS LIVRE', 915200,
    'em_andamento', 915203,
    '15200000-0000-4000-8000-000000000001',
    '15200000-0000-4000-8000-000000000002',
    'em_andamento', 'OV', 'OV-RPC-001', 4,
    'VENDA CRIADA PELA RPC', 200
  );

-- A OV 915202 veio de um orcamento com preco comercial 50. O valor 20 que
-- O orcamento prova que nem ele nem o custo da OV substituem o preco digitado
-- pela pessoa que esta compondo o rascunho.
insert into m.orcamento (
  id, tenant_id, empresa_id, numero, codigo, status, titulo,
  cliente_id, vendedor_usuario_id, total_produtos, total_bruto,
  total_liquido, valor_fechado, os_id
)
values (
  '15200000-0000-4000-8000-000000000100',
  '15200000-0000-4000-8000-000000000001',
  '15200000-0000-4000-8000-000000000002',
  1, 'ORC-OV-001', 'FECHADO', 'VENDA DE KIT', 915200,
  '15200000-0000-4000-8000-000000000011', 500, 500, 500, 500, 915202
);

insert into m.orcamento_item (
  id, tenant_id, empresa_id, orcamento_id, seq, item_id, item_tipo,
  item_nome, unidade, quantidade, valor_unitario, valor_total_bruto,
  valor_total, valor_unitario_liquido
)
values (
  '15200000-0000-4000-8000-000000000101',
  '15200000-0000-4000-8000-000000000001',
  '15200000-0000-4000-8000-000000000002',
  '15200000-0000-4000-8000-000000000100', 1, 915200, 'PRODUTO',
  'KIT DE INSTALACAO', 'UN', 10, 50, 500, 500, 50
);

-- Este e consumo da OS. Nenhuma composicao livre pode depender dele.
insert into public.os_itens (
  id, os_id, item_id, quantidade, valor_unitario, valor_total,
  tenant_id, empresa_id, finalidade
)
values
  (
    915200, 915200, 915200, 7, 10, 70,
    '15200000-0000-4000-8000-000000000001',
    '15200000-0000-4000-8000-000000000002', null
  ),
  (
    915202, 915202, 915200, 10, 20, 200,
    '15200000-0000-4000-8000-000000000001',
    '15200000-0000-4000-8000-000000000002', 'venda'
  );

create temporary table faturamento_os_test_ids (
  nome text primary key,
  solicitacao_id uuid not null
) on commit drop;

insert into faturamento_os_test_ids (nome, solicitacao_id)
select 'paineis', f.fn_solicitacao_faturamento_criar_os_livre(
  '15200000-0000-4000-8000-000000000001',
  '15200000-0000-4000-8000-000000000002',
  915200,
  '[{"descricao":"PAINEIS MONTADOS EXTRUSORA 14","quantidade":1,"unidade":"UN","valor_unitario":300}]'::jsonb
);

insert into faturamento_os_test_ids (nome, solicitacao_id)
select 'kit', f.fn_solicitacao_faturamento_criar_os_livre(
  '15200000-0000-4000-8000-000000000001',
  '15200000-0000-4000-8000-000000000002',
  915200,
  '[{"descricao":"KIT DE INSTALACAO ESPECIAL","quantidade":2,"unidade":"UN","valor_unitario":100,"item_id":915200}]'::jsonb
);

insert into faturamento_os_test_ids (nome, solicitacao_id)
select 'mao_obra', f.fn_solicitacao_faturamento_criar_os_livre(
  '15200000-0000-4000-8000-000000000001',
  '15200000-0000-4000-8000-000000000002',
  915200,
  '[{"descricao":"MAO DE OBRA DE INSTALACAO","quantidade":5,"unidade":"H","valor_unitario":50}]'::jsonb
);

do $test$
declare
  v_descricoes integer;
  v_origens_invalidas integer;
  v_com_item integer;
  v_saldo record;
begin
  select count(distinct si.descricao),
         count(*) filter (where si.origem_tipo <> 'OS' or si.origem_id <> '915200' or si.origem_item_id is not null),
         count(*) filter (where si.item_id is not null)
  into v_descricoes, v_origens_invalidas, v_com_item
  from f.solicitacao_item si
  where si.solicitacao_id in (select solicitacao_id from faturamento_os_test_ids);

  if v_descricoes <> 3 or v_origens_invalidas <> 0 or v_com_item <> 1 then
    raise exception 'Linhas livres incorretas: descricoes %, origens invalidas %, com item %.',
      v_descricoes, v_origens_invalidas, v_com_item;
  end if;

  select * into v_saldo
  from f.fn_os_saldo_a_faturar(
    '15200000-0000-4000-8000-000000000001',
    '15200000-0000-4000-8000-000000000002',
    915200
  );
  if v_saldo.valor_pedido <> 1000
     or v_saldo.valor_faturado <> 0
     or v_saldo.valor_reservado <> 750
     or v_saldo.saldo <> 250 then
    raise exception 'Reserva por valor incorreta: pedido %, faturado %, reservado %, saldo %.',
      v_saldo.valor_pedido, v_saldo.valor_faturado, v_saldo.valor_reservado, v_saldo.saldo;
  end if;

  begin
    perform f.fn_solicitacao_faturamento_criar_parcial(
      '15200000-0000-4000-8000-000000000001',
      '15200000-0000-4000-8000-000000000002',
      915200,
      '[{"os_item_id":915200,"quantidade":1}]'::jsonb
    );
    raise exception 'OS foi aceita indevidamente no caminho de quantidade da OV.';
  exception when sqlstate '22023' then
    if sqlerrm not like 'A origem 915200 nao e uma OV.%' then raise; end if;
  end;
end;
$test$;

-- Ultrapassar o orcado e permitido: o banco reserva e a tela apenas avisa.
insert into faturamento_os_test_ids (nome, solicitacao_id)
select 'aditivo', f.fn_solicitacao_faturamento_criar_os_livre(
  '15200000-0000-4000-8000-000000000001',
  '15200000-0000-4000-8000-000000000002',
  915200,
  '[{"descricao":"ADITIVO DE ESCOPO","quantidade":1,"unidade":"UN","valor_unitario":500}]'::jsonb
);

do $test$
declare
  v_saldo record;
begin
  select * into v_saldo
  from f.fn_os_saldo_a_faturar(
    '15200000-0000-4000-8000-000000000001',
    '15200000-0000-4000-8000-000000000002',
    915200
  );
  if v_saldo.valor_reservado <> 1250 or v_saldo.saldo <> -250 then
    raise exception 'Valor acima do orcado deveria ser aceito: reservado %, saldo %.',
      v_saldo.valor_reservado, v_saldo.saldo;
  end if;
end;
$test$;

-- O pipeline completo tambem aceita OS sem item_id: cria o documento e mantem
-- a descricao livre. A emissao fiscal exigira produto fiscal antes da Focus.
select *
from f.fn_faturar_documento(
  '15200000-0000-4000-8000-000000000001',
  '15200000-0000-4000-8000-000000000002',
  915201,
  null,
  '15200000-0000-4000-8000-000000000201',
  'HOMOLOGACAO',
  'FATURAMENTO_OS',
  null,
  '[{"descricao":"START-UP DA LINHA 2","quantidade":1,"unidade":"UN","valor_unitario":650}]'::jsonb
);

do $test$
declare
  v_item record;
  v_total numeric;
  v_contexto jsonb;
  v_saldo record;
  v_ov_solicitacao uuid;
  v_ov_solicitacao_item uuid;
begin
  select descricao, quantidade, valor_total, item_id
  into v_item
  from f.documento_fiscal_item
  where documento_fiscal_id = '15200000-0000-4000-8000-000000000201';
  select valor_total into v_total
  from f.documento_fiscal
  where id = '15200000-0000-4000-8000-000000000201';
  select f.fn_nfe_contexto_emissao_impl('15200000-0000-4000-8000-000000000201') into v_contexto;
  select * into v_saldo
  from f.fn_os_saldo_a_faturar(
    '15200000-0000-4000-8000-000000000001',
    '15200000-0000-4000-8000-000000000002',
    915201
  );

  if v_item.descricao <> 'START-UP DA LINHA 2'
     or v_item.quantidade <> 1
     or v_item.valor_total <> 650
     or v_item.item_id is not null
     or v_total <> 650
     or jsonb_array_length(v_contexto->'itens') <> 1
     or (v_contexto->'itens'->0->'os_item') <> 'null'::jsonb
     or v_saldo.valor_reservado <> 650
     or v_saldo.saldo <> -150 then
    raise exception 'Pipeline de OS livre nao preservou linha, contexto ou reserva.';
  end if;

  -- Controle de regressao: a OV continua criando reserva por os_item.
  v_ov_solicitacao := f.fn_solicitacao_faturamento_criar_parcial(
    '15200000-0000-4000-8000-000000000001',
    '15200000-0000-4000-8000-000000000002',
    915202,
    '[{"os_item_id":915202,"quantidade":4,"valor_unitario":73.25}]'::jsonb
  );
  if not exists (
    select 1 from f.solicitacao_item si
    where si.solicitacao_id = v_ov_solicitacao
      and si.origem_tipo = 'OV'
      and si.origem_item_id = '915202'
      and si.quantidade = 4
      and si.valor_unitario = 73.25
  ) then
    raise exception 'A OV nao preservou quantidade e preco de venda digitado no rascunho.';
  end if;

  begin
    perform f.fn_solicitacao_faturamento_criar_parcial(
      '15200000-0000-4000-8000-000000000001',
      '15200000-0000-4000-8000-000000000002',
      915202,
      '[{"os_item_id":915202,"quantidade":1}]'::jsonb
    );
    raise exception 'A OV aceitou criar rascunho sem preco de venda.';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Informe o preco unitario de venda da linha 915202.%' then raise; end if;
  end;

  select si.id into v_ov_solicitacao_item
  from f.solicitacao_item si
  where si.solicitacao_id = v_ov_solicitacao;

  perform f.fn_solicitacao_nfe_salvar_conferencia(
    v_ov_solicitacao,
    '{"destino_uf_confirmada":"SC","finalidade_emissao":"1","consumidor_final":"0","presenca_comprador":"9","modalidade_frete":"9","valor_frete":0,"valor_seguro":0,"valor_outras_despesas":0,"destinacao_mercadoria":"REVENDA","pagamento_forma":"15","pagamento_indicador":1}'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', v_ov_solicitacao_item,
      'perfil_operacao_id', '15200000-0000-4000-8000-000000000301',
      'cfop', '5102',
      'cst_icms', '00',
      'csosn', '',
      'cst_ipi', '53',
      'ipi_codigo_enquadramento_legal', '999',
      'cst_pis', '49',
      'cst_cofins', '49',
      'reducao_base_icms_percentual', 0,
      'icms_modalidade_base_calculo', '3',
      'aliquota_icms', 17,
      'cst_ibs_cbs', '000',
      'cclass_trib', '000001',
      'cclass_trib_versao', 'Informe Técnico 2025.002 v1.60',
      'ibs_cbs_json', '{"ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9}'::jsonb
    ))
  );

  if not exists (
    select 1
    from f.solicitacao_faturamento sf
    join f.solicitacao_item si on si.solicitacao_id = sf.id
    where sf.id = v_ov_solicitacao
      and sf.status = 'PREVIA'
      and sf.finalidade_emissao = 1
      and sf.modalidade_frete = 9
      and si.cfop = '5102'
      and si.cst_icms = '00'
      and si.cst_ipi = '53'
      and si.cst_ibs_cbs = '000'
      and si.cclass_trib = '000001'
      and si.valor_unitario = 73.25
  ) then
    raise exception 'A conferencia atomica da NF-e nao preservou operacao, tributos e preco de venda.';
  end if;
end;
$test$;

do $test$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'os_itens'
      and column_name in ('valor_unitario_venda', 'orcamento_item_id')
  ) then
    raise exception 'Preco de venda por item foi implementado em os_itens, mas deve continuar como pendencia.';
  end if;
end;
$test$;

-- A RPC usada pela tela de OV grava finalidade=venda na mesma transacao.
select set_config('request.jwt.claim.sub', '15200000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"15200000-0000-4000-8000-000000000010","role":"authenticated"}',
  true
);
set local role authenticated;

do $test$
declare
  v_linha public.os_itens%rowtype;
  v_resumo record;
  v_solicitacao uuid;
begin
  v_linha := public.add_ov_item_baixa_imediata(
    915203, 915200, 1, 20, 0, 0, false,
    'Teste automatizado', 'Item da OV',
    '15200000-0000-4000-8000-000000000002'
  );
  if v_linha.finalidade <> 'venda' then
    raise exception 'Item criado pela tela de OV nao recebeu finalidade=venda.';
  end if;

  v_solicitacao := f.fn_solicitacao_faturamento_criar_parcial(
    '15200000-0000-4000-8000-000000000001',
    '15200000-0000-4000-8000-000000000002',
    915203,
    jsonb_build_array(jsonb_build_object(
      'os_item_id', v_linha.id,
      'quantidade', 1,
      'valor_unitario', 88.90
    ))
  );
  if not exists (
    select 1 from f.solicitacao_item si
    where si.solicitacao_id = v_solicitacao
      and si.valor_unitario = 88.90
  ) then
    raise exception 'RPC autenticada nao preservou o preco digitado.';
  end if;

  select * into v_resumo
  from f.fn_os_saldo_a_faturar(
    '15200000-0000-4000-8000-000000000001',
    '15200000-0000-4000-8000-000000000002',
    915202
  );
  if v_resumo.valor_reservado <> 293 then
    raise exception 'Resumo compativel da OV nao contabilizou a reserva: %.', v_resumo.valor_reservado;
  end if;
end;
$test$;

reset role;

rollback;
