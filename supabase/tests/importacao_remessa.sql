\set ON_ERROR_STOP on

-- Importacao por remessa expressa: NF-e de entrada pelo pipeline de NF-e
-- (supabase/migrations/20260918000000_importacao_remessa_nfe_entrada.sql).
--
-- Como rodar (o XML da DIR entra por variavel do psql; a copia de referencia fica fora do git,
-- em docs/importacao/1ZJ451C10441551106/, e uma copia anonimizada em supabase/tests/fixtures):
--   XML=$(cat supabase/tests/fixtures/dir_remessa_ups.xml)
--   docker exec -i supabase_db_estoque-os psql -U postgres -d postgres -v xml="$XML" < supabase/tests/importacao_remessa.sql
--
-- Blocos:
--   1  ler a DIR: XML invalido, XML que nao e DIR, DIR boa (valores e UA), bloqueios de CNPJ,
--      situacao e II pendente
--   2  criar: recusas (ICMS x GNRE, CFOP, NCM, fabricante, DIR bloqueada), nada gravado;
--      criar 3101 (valores, itens, solicitacao, snapshots, item fiscal); DIR repetida; gerar de novo
--   3  pipeline: o documento de homologacao nasce como ENTRADA com o II no total
--   4  autorizacoes: homologacao so carimba; producao conclui, da entrada no estoque com o custo
--      (vProd + II + courier), lanca e baixa a nota de debito do courier; cancelamento estorna;
--      3556 (sem credito) leva o ICMS ao custo e nao duplica o titulo
--
-- Tenant 1e1a0000-...-0001, empresa ...0002 (SC, CNPJ 22222222000191 — a DIR e reescrita com
-- esse destinatario). Usuario ...0011 ADMIN.

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('1e1a0000-0000-4000-8000-000000000010', 'authenticated', 'authenticated', 'importacao@example.test',
        '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Fiscal Importacao"}'::jsonb, now(), now());
insert into public.tenants (id, nome, ativo) values ('1e1a0000-0000-4000-8000-000000000001', 'Teste importacao', true);
insert into c.tenant (id, codigo, nome) values ('1e1a0000-0000-4000-8000-000000000001', 'TESTE-IMPORTACAO', 'Teste importacao');
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj)
values ('1e1a0000-0000-4000-8000-000000000002', '1e1a0000-0000-4000-8000-000000000001', 'IMPORTACAO', 'EMPRESA IMPORTACAO LTDA', 'IMPORTACAO', '22222222000191');
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, uf, cidade)
values ('1e1a0000-0000-4000-8000-000000000002', '1e1a0000-0000-4000-8000-000000000001', '22222222000191', 'EMPRESA IMPORTACAO LTDA', 'IMPORTACAO', 'SC', 'JOINVILLE')
on conflict (id) do nothing;
insert into c.empresa_fiscal (empresa_id, inscricao_estadual, crt, certificado_validade_em, serie_nfe)
values ('1e1a0000-0000-4000-8000-000000000002', '257686835', 3, current_date + 365, 2);
insert into c.empresa_endereco (empresa_id, tipo, cep, logradouro, numero, bairro, cidade, uf, codigo_municipio_ibge)
values ('1e1a0000-0000-4000-8000-000000000002', 'FISCAL', '89219600', 'RUA DONA FRANCISCA', '8300', 'ZONA INDUSTRIAL NORTE', 'JOINVILLE', 'SC', '4209102');
insert into a.usuario (id, auth_user_id, nome, email, ativo) values
  ('1e1a0000-0000-4000-8000-000000000011', '1e1a0000-0000-4000-8000-000000000010', 'Fiscal Importacao', 'importacao@example.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo) values
  ('1e1a0000-0000-4000-8000-000000000011', '1e1a0000-0000-4000-8000-000000000001', 'ADMIN', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo) values
  ('1e1a0000-0000-4000-8000-000000000011', '1e1a0000-0000-4000-8000-000000000002', 'ADMIN', true);
insert into public.user_tenant_context (user_id, tenant_id) values
  ('1e1a0000-0000-4000-8000-000000000010', '1e1a0000-0000-4000-8000-000000000001');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id) values
  ('1e1a0000-0000-4000-8000-000000000010', '1e1a0000-0000-4000-8000-000000000001', '1e1a0000-0000-4000-8000-000000000002');
insert into public.municipios_ibge (codigo_ibge, nome, nome_normalizado, uf, fonte, fonte_versao, atualizado_em)
values ('4209102', 'Joinville', 'joinville', 'SC', 'teste', 'teste', now())
on conflict (codigo_ibge) do nothing;

-- Item do catalogo (a CPU importada), sem saldo.
insert into public.itens (id, tenant_id, empresa_id, codigo_interno, nome, tipo, unidade_medida, controla_estoque, ativo, finalidade, custo_medio)
values (918001, '1e1a0000-0000-4000-8000-000000000001', '1e1a0000-0000-4000-8000-000000000002', 'CQM1HCPU61', 'CONTROLADOR PROGRAMAVEL PLC CPU', 'produto', 'UN', true, true, 'materia_prima', 0);

-- Motivo de compra e conta bancaria (nota de debito do courier).
insert into f.plano_contas (id, tenant_id, codigo, nome)
values ('1e1a0000-0000-4000-8000-000000000402', '1e1a0000-0000-4000-8000-000000000001', '3.1.01', 'Compras para estoque');
insert into f.motivo_compra (id, tenant_id, codigo, nome, aplica_em, favorito, plano_contas_id)
values ('1e1a0000-0000-4000-8000-000000000401', '1e1a0000-0000-4000-8000-000000000001', 'ESTOQUE', 'Compra para estoque', 'PRODUTO', true, '1e1a0000-0000-4000-8000-000000000402');
insert into f.conta_bancaria (id, tenant_id, empresa_id, codigo, nome, tipo)
values ('1e1a0000-0000-4000-8000-000000000501', '1e1a0000-0000-4000-8000-000000000001', '1e1a0000-0000-4000-8000-000000000002', 'SICREDI', 'SICREDI', 'BANCO');

-- Perfis de importacao (mesmo desenho dos SEG-IMPORTACAO-*), sem revisao.
insert into f.perfil_operacao (
  id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto, crt,
  cfop_externo, cst_icms, aliquota_icms, cst_ipi, ipi_codigo_enquadramento_legal, cst_pis, cst_cofins,
  finalidade_emissao, consumidor_final, ambito_destino, ufs_destino, indicador_ie_destinatario, origem_mercadoria,
  exige_referencia, faixa_automacao, justificativa_faixa, habilitado_producao, vigencia_inicio
) values
  ('1e1a0000-0000-4000-8000-000000000301', '1e1a0000-0000-4000-8000-000000000001', '1e1a0000-0000-4000-8000-000000000002',
   'TESTE-IMPORTACAO-3101', 'Importacao industrializacao teste', 'NFE', 'IMPORTACAO_INDUSTRIALIZACAO', 'COMPRA PARA INDUSTRIALIZACAO - IMPORTACAO', '3',
   '3101', '00', 17, '03', '999', '98', '98', 1, 0, 'INTERESTADUAL', array['EX']::text[], '9', 1, false, 'REVISAO', 'teste', false, '2026-09-17'),
  ('1e1a0000-0000-4000-8000-000000000302', '1e1a0000-0000-4000-8000-000000000001', '1e1a0000-0000-4000-8000-000000000002',
   'TESTE-IMPORTACAO-3556', 'Importacao consumo teste', 'NFE', 'IMPORTACAO_CONSUMO', 'COMPRA DE MATERIAL PARA USO OU CONSUMO - IMPORTACAO', '3',
   '3556', '00', 17, '03', '999', '98', '98', 1, 1, 'INTERESTADUAL', array['EX']::text[], '9', 1, false, 'REVISAO', 'teste', false, '2026-09-17');

create temporary table imp_ctx (nome text primary key, valor text not null) on commit drop;
grant all on imp_ctx to authenticated;
insert into imp_ctx values ('xml', replace(:'xml', '<documento>13671448000189</documento>', '<documento>22222222000191</documento>'));

select set_config('request.jwt.claim.sub', '1e1a0000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"1e1a0000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;

-- 1 ---------------------------------------------------------------- ler a DIR
do $test$
declare
  v_xml text := (select valor from imp_ctx where nome = 'xml');
  v_r jsonb;
begin
  begin
    perform f.fn_importacao_remessa_ler_dir('isto nao e xml');
    raise exception 'aceitou texto que nao e XML';
  exception when sqlstate '22023' then
    if sqlerrm not like 'O arquivo nao e um XML valido%' then raise; end if;
  end;
  begin
    perform f.fn_importacao_remessa_ler_dir('<nfeProc><NFe/></nfeProc>');
    raise exception 'aceitou XML que nao e DIR';
  exception when sqlstate '22023' then
    if sqlerrm not like 'O XML nao e uma DIR do Siscomex Remessa%' then raise; end if;
  end;

  v_r := f.fn_importacao_remessa_ler_dir(v_xml);
  if v_r->'bloqueios' <> '[]'::jsonb or v_r->'em_uso' <> 'null'::jsonb
     or v_r->>'awb' <> '1ZJ451C10441551106' or v_r#>>'{dir,numero}' <> '260191366846' or v_r#>>'{dir,situacao}' <> '25'
     or v_r#>>'{dir,data_registro}' <> '2026-09-09T14:34:00' or v_r#>>'{dir,data_desembaraco}' <> '2026-09-09'
     or v_r#>>'{dir,ua_entrada}' <> '0817700' or v_r#>>'{dir,uf_desembaraco}' <> 'SP' or v_r#>>'{dir,local_desembaraco}' not like 'AEROPORTO INTERNACIONAL DE VIRACOPOS%'
     or v_r#>>'{courier,nome}' <> 'UPS DO BRASIL REMESSAS EXPRESSAS LTDA' or v_r#>>'{courier,cnpj}' <> '74155052000173'
     or (v_r#>>'{remessa,valor_usd}')::numeric <> 45 or (v_r#>>'{remessa,frete_usd}')::numeric <> 41.12
     or (v_r#>>'{remessa,valor_brl}')::numeric <> 228.85 or (v_r#>>'{remessa,frete_brl}')::numeric <> 209.11
     or (v_r#>>'{remessa,tributavel_brl}')::numeric <> 437.97 or (v_r#>>'{remessa,cambio}')::numeric <> 5.0856
     or (v_r#>>'{ii,valor}')::numeric <> 262.78 or (v_r#>>'{ii,pendente}')::numeric <> 0
     or v_r#>>'{destinatario,documento}' <> '22222222000191' or v_r#>>'{remetente,nome}' <> 'SHENZHEN COOL DREAM SUPPLY CO LTD'
     or jsonb_array_length(v_r->'itens') <> 1 or (v_r#>>'{itens,0,valor_usd}')::numeric <> 45 or (v_r#>>'{itens,0,quantidade}')::numeric <> 1
     or v_r#>>'{itens,0,regime_tributacao}' <> '7' or v_r#>>'{itens,0,descricao}' <> 'PLC CPU UNIT FOR INDUSTRIAL AUTOMATION J451C1G7HNY' then
    raise exception 'leitura da DIR errada: %', v_r;
  end if;

  -- Bloqueios, todos de uma vez.
  v_r := f.fn_importacao_remessa_ler_dir(replace(v_xml, '<documento>22222222000191</documento>', '<documento>99999999000199</documento>'));
  if jsonb_array_length(v_r->'bloqueios') <> 1 or v_r#>>'{bloqueios,0}' not like 'O destinatario da DIR (CNPJ 99999999000199) nao e a empresa emitente (CNPJ 22222222000191).' then
    raise exception 'bloqueio de CNPJ nao veio: %', v_r->'bloqueios';
  end if;
  v_r := f.fn_importacao_remessa_ler_dir(replace(replace(v_xml, '<situacao>25</situacao>', '<situacao>24</situacao>'), '<valorPendente>0.00</valorPendente>', '<valorPendente>10.50</valorPendente>'));
  if jsonb_array_length(v_r->'bloqueios') <> 2
     or v_r#>>'{bloqueios,0}' not like 'A remessa esta na situacao 24%' or v_r#>>'{bloqueios,1}' not like 'Ha II pendente de R$ 10,50 na DIR%' then
    raise exception 'bloqueios de situacao/II nao vieram: %', v_r->'bloqueios';
  end if;
end;
$test$;

-- 2 ---------------------------------------------------------------- criar
create temporary table imp_ids (nome text primary key, id uuid not null) on commit drop;
grant all on imp_ids to authenticated;

do $test$
declare
  v_xml text := (select valor from imp_ctx where nome = 'xml');
  v_base jsonb;
  v_res jsonb;
  v_imp f.importacao_remessa%rowtype;
  v_it f.importacao_remessa_item%rowtype;
  v_sf f.solicitacao_faturamento%rowtype;
  v_si f.solicitacao_item%rowtype;
  v_primeira uuid;
  v_primeira_sol uuid;
begin
  v_base := jsonb_build_object(
    'xml', v_xml, 'cfop', '3101', 'aliquota_icms', 17,
    'gnre', jsonb_build_object('numero', '1234567890', 'receita', '10005-6', 'uf', 'SC', 'valor', 143.53),
    'courier', jsonb_build_object('servicos', 138.53, 'armazenagem', 12.41),
    'nota_debito', jsonb_build_object('numero', '2953830', 'valor', 557.25, 'emissao', '2026-09-10', 'pago_em', '2026-09-10',
                                      'conta_bancaria_id', '1e1a0000-0000-4000-8000-000000000501', 'forma_pagamento', 'BOLETO',
                                      'motivo_compra_id', '1e1a0000-0000-4000-8000-000000000401'),
    'exportador', jsonb_build_object('nome', 'Shenzhen Haoxin Xunji Electronic Technology Trading Co., Ltd.',
                                     'logradouro', 'Jiaxian Road, You Suowei Building, Unit B1-A6', 'numero', '2000',
                                     'complemento', 'Bantian, Longgang', 'bairro', 'Shenzhen', 'pais_codigo', '1600', 'pais_nome', 'China'),
    'itens', jsonb_build_array(jsonb_build_object('item_id', 918001, 'ncm', '8537.10.20', 'fabricante', 'OMRON')),
    'observacao', 'CPU de CLP para a bancada'
  );

  -- Recusas.
  begin
    perform f.fn_importacao_remessa_criar(v_base || jsonb_build_object('gnre', jsonb_build_object('valor', 100)));
    raise exception 'aceitou ICMS divergente da GNRE';
  exception when sqlstate '22023' then
    if sqlerrm not like 'ICMS calculado R$ 143,53 (BC R$ 844,28 a 17,00%) difere da GNRE R$ 100,00 em R$ 43,53.%' then raise; end if;
  end;
  begin
    perform f.fn_importacao_remessa_criar(v_base || jsonb_build_object('cfop', '5102'));
    raise exception 'aceitou CFOP 5102';
  exception when sqlstate '22023' then
    if sqlerrm not like 'CFOP 5102 nao vale para a importacao%' then raise; end if;
  end;
  begin
    perform f.fn_importacao_remessa_criar(v_base || jsonb_build_object('itens', jsonb_build_array(jsonb_build_object('item_id', 918001, 'ncm', '8537101190', 'fabricante', 'OMRON'))));
    raise exception 'aceitou NCM de 10 digitos';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Mercadoria 1: NCM deve ter 8 digitos%' then raise; end if;
  end;
  begin
    perform f.fn_importacao_remessa_criar(v_base || jsonb_build_object('itens', jsonb_build_array(jsonb_build_object('item_id', 918001, 'ncm', '85371020'))));
    raise exception 'aceitou item sem fabricante';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Mercadoria 1: informe o fabricante%' then raise; end if;
  end;
  begin
    perform f.fn_importacao_remessa_criar(v_base || jsonb_build_object('xml', replace(v_xml, '<situacao>25</situacao>', '<situacao>24</situacao>')));
    raise exception 'aceitou DIR bloqueada';
  exception when sqlstate '22023' then
    if sqlerrm not like 'DIR bloqueada: A remessa esta na situacao 24%' then raise; end if;
  end;
  if exists (select 1 from f.importacao_remessa where tenant_id = '1e1a0000-0000-4000-8000-000000000001')
     or exists (select 1 from f.solicitacao_faturamento where tenant_id = '1e1a0000-0000-4000-8000-000000000001') then
    raise exception 'recusa deixou importacao ou solicitacao gravada';
  end if;

  -- Criar (3101).
  v_res := f.fn_importacao_remessa_criar(v_base);
  v_primeira := (v_res->>'importacao_id')::uuid;
  v_primeira_sol := (v_res->>'solicitacao_id')::uuid;
  if v_res->>'cfop' <> '3101' or v_res->>'natureza_operacao' <> 'IMPORTACAO_INDUSTRIALIZACAO'
     or (v_res->>'valor_aduaneiro')::numeric <> 437.97 or (v_res->>'ii')::numeric <> 262.78 or (v_res->>'bc_icms')::numeric <> 844.28
     or (v_res->>'icms')::numeric <> 143.53 or (v_res->>'valor_nota')::numeric <> 844.28 or (v_res->>'itens')::integer <> 1
     or v_res->>'perfil_id' <> '1e1a0000-0000-4000-8000-000000000301' or v_res->>'perfil_codigo' <> 'TESTE-IMPORTACAO-3101'
     or v_res->>'destinatario' <> 'SHENZHEN HAOXIN XUNJI ELECTRONIC TECHNOLOGY TRADING CO., LTD.' or v_res->>'substituiu' is not null then
    raise exception 'retorno da criacao errado: %', v_res;
  end if;
  select * into v_imp from f.importacao_remessa where id = v_primeira;
  if v_imp.status <> 'RASCUNHO' or v_imp.awb <> '1ZJ451C10441551106' or v_imp.dir_numero <> '260191366846' or v_imp.dir_situacao <> '25'
     or v_imp.dir_data_registro <> '2026-09-09 14:34:00-03'::timestamptz or v_imp.ua_entrada <> '0817700'
     or v_imp.local_desembaraco not like 'AEROPORTO INTERNACIONAL DE VIRACOPOS%' or v_imp.uf_desembaraco <> 'SP' or v_imp.data_desembaraco <> '2026-09-09'
     or v_imp.via_transporte <> 4 or v_imp.forma_intermedio <> 1 or v_imp.cambio <> 5.0856
     or v_imp.valor_mercadoria_usd <> 45 or v_imp.frete_usd <> 41.12 or v_imp.valor_mercadoria_brl <> 228.85 or v_imp.frete_brl <> 209.11
     or v_imp.valor_aduaneiro_brl <> 437.97 or v_imp.ii_valor <> 262.78 or v_imp.aliquota_icms <> 17 or v_imp.bc_icms <> 844.28
     or v_imp.icms_valor <> 143.53 or v_imp.valor_nota <> 844.28 or v_imp.gnre_valor <> 143.53 or v_imp.gnre_receita <> '10005-6'
     or v_imp.courier_nome <> 'UPS DO BRASIL REMESSAS EXPRESSAS LTDA' or v_imp.courier_cnpj <> '74155052000173'
     or v_imp.courier_servicos <> 138.53 or v_imp.courier_armazenagem <> 12.41
     or v_imp.nota_debito_numero <> '2953830' or v_imp.nota_debito_valor <> 557.25 or v_imp.nota_debito_pago_em <> '2026-09-10'
     or v_imp.nota_debito_conta_bancaria_id <> '1e1a0000-0000-4000-8000-000000000501' or v_imp.nota_debito_forma_pagamento <> 'BOLETO'
     or v_imp.exportador_nome <> 'Shenzhen Haoxin Xunji Electronic Technology Trading Co., Ltd' or v_imp.exportador_codigo <> 'SHENZHEN-HAOXIN-XUNJI-ELECTRONIC-TECHNOLOGY-TRADING-CO-LTD-'
     or v_imp.exportador_pais_codigo <> '1600' or v_imp.exportador_pais_nome <> 'CHINA' or v_imp.remetente_dir_nome <> 'SHENZHEN COOL DREAM SUPPLY CO LTD'
     or v_imp.natureza_operacao <> 'IMPORTACAO_INDUSTRIALIZACAO' or v_imp.cfop <> '3101' or v_imp.consumidor_final <> 0 or not v_imp.credito_icms
     or v_imp.perfil_operacao_id <> '1e1a0000-0000-4000-8000-000000000301' or v_imp.solicitacao_id <> v_primeira_sol
     or v_imp.observacao <> 'CPU de CLP para a bancada' or v_imp.dados_json->>'perfil_codigo' <> 'TESTE-IMPORTACAO-3101' or v_imp.xml_dir is null then
    raise exception 'importacao errada: %', row_to_json(v_imp);
  end if;
  select * into v_it from f.importacao_remessa_item where importacao_id = v_primeira;
  if v_it.ordem <> 1 or v_it.sequencia_dir <> '00001' or v_it.item_id <> 918001 or v_it.codigo <> 'CQM1HCPU61' or v_it.descricao <> 'CONTROLADOR PROGRAMAVEL PLC CPU'
     or v_it.ncm <> '85371020' or v_it.unidade <> 'UN' or v_it.quantidade <> 1 or v_it.fabricante <> 'OMRON' or v_it.valor_usd <> 45
     or v_it.valor_mercadoria_brl <> 228.85 or v_it.frete_brl <> 209.11 or v_it.valor_aduaneiro_brl <> 437.97 or v_it.valor_unitario_brl <> 437.97
     or v_it.ii_valor <> 262.78 or v_it.bc_icms <> 844.28 or v_it.icms_valor <> 143.53 or v_it.courier_rateado <> 150.94
     or v_it.custo_total <> 851.69 or v_it.custo_unitario <> 851.69 then
    raise exception 'item da importacao errado: %', row_to_json(v_it);
  end if;
  select * into v_sf from f.solicitacao_faturamento where id = v_primeira_sol;
  if v_sf.natureza_operacao <> 'IMPORTACAO_INDUSTRIALIZACAO' or v_sf.cliente_id is not null or v_sf.status <> 'PREVIA'
     or v_sf.finalidade_emissao <> 1 or v_sf.consumidor_final <> 0 or v_sf.presenca_comprador <> 9 or v_sf.modalidade_frete <> 9
     or v_sf.valor_frete <> 0 or v_sf.valor_seguro <> 0 or v_sf.valor_outras_despesas <> 143.53
     or v_sf.pagamento_forma <> '90' or v_sf.pagamento_indicador <> 0 or v_sf.destinacao_mercadoria is not null
     or v_sf.destino_uf_confirmada <> 'EX' or v_sf.snapshot_cadastro_em is null or v_sf.revisao_fiscal_confirmada_em is null
     or v_sf.transportador_dados is not null or v_sf.volumes_dados is not null
     or v_sf.observacao <> 'CPU de CLP para a bancada' or v_sf.perfil_operacao_id <> '1e1a0000-0000-4000-8000-000000000301' then
    raise exception 'solicitacao errada: %', row_to_json(v_sf);
  end if;
  if v_sf.destinatario_snapshot->>'documento' is not null or v_sf.destinatario_snapshot->>'id_estrangeiro' is not null
     or v_sf.destinatario_snapshot->>'nome' <> 'SHENZHEN HAOXIN XUNJI ELECTRONIC TECHNOLOGY TRADING CO., LTD'
     or v_sf.destinatario_snapshot->>'indicador_ie' <> '9' or v_sf.destinatario_snapshot->>'inscricao_estadual' is not null
     or v_sf.destinatario_snapshot->>'logradouro' <> 'JIAXIAN ROAD, YOU SUOWEI BUILDING, UNIT B1-A6' or v_sf.destinatario_snapshot->>'numero_endereco' <> '2000'
     or v_sf.destinatario_snapshot->>'complemento' <> 'BANTIAN, LONGGANG' or v_sf.destinatario_snapshot->>'bairro' <> 'SHENZHEN'
     or v_sf.destinatario_snapshot->>'cidade' <> 'EXTERIOR' or v_sf.destinatario_snapshot->>'uf' <> 'EX'
     or v_sf.destinatario_snapshot->>'codigo_ibge_municipio' <> '9999999' or v_sf.destinatario_snapshot->>'cep' is not null
     or v_sf.destinatario_snapshot->>'pais_codigo' <> '1600' or v_sf.destinatario_snapshot->>'pais_nome' <> 'CHINA' then
    raise exception 'destinatario_snapshot errado: %', v_sf.destinatario_snapshot;
  end if;
  if v_sf.emitente_snapshot->>'cnpj' <> '22222222000191' or v_sf.emitente_snapshot->>'cidade' <> 'Joinville' or (v_sf.emitente_snapshot->>'serie_nfe')::integer <> 2 then
    raise exception 'emitente_snapshot errado: %', v_sf.emitente_snapshot;
  end if;
  if v_sf.operacao_snapshot->>'natureza_operacao' <> 'IMPORTACAO_INDUSTRIALIZACAO' or (v_sf.operacao_snapshot->>'finalidade_emissao')::integer <> 1
     or (v_sf.operacao_snapshot->>'tipo_documento')::integer <> 0 or (v_sf.operacao_snapshot->>'local_destino')::integer <> 3
     or (v_sf.operacao_snapshot->>'consumidor_final')::integer <> 0 or (v_sf.operacao_snapshot->>'modalidade_frete')::integer <> 9
     or (v_sf.operacao_snapshot->>'valor_outras_despesas')::numeric <> 143.53 or (v_sf.operacao_snapshot->>'valor_total_ii')::numeric <> 262.78
     or v_sf.operacao_snapshot#>>'{pagamento,forma}' <> '90' or v_sf.operacao_snapshot->>'nfe_referenciada' is not null
     or v_sf.operacao_snapshot#>>'{importacao,importacao_id}' <> v_primeira::text
     or v_sf.operacao_snapshot#>>'{importacao,awb}' <> '1ZJ451C10441551106' or v_sf.operacao_snapshot#>>'{importacao,dir_numero}' <> '260191366846'
     or v_sf.operacao_snapshot#>>'{importacao,dir_data_registro}' <> '2026-09-09' or v_sf.operacao_snapshot#>>'{importacao,dir_data_registro_texto}' <> '09/09/2026'
     or v_sf.operacao_snapshot#>>'{importacao,ua_entrada}' <> '0817700' or v_sf.operacao_snapshot#>>'{importacao,uf_desembaraco}' <> 'SP'
     or v_sf.operacao_snapshot#>>'{importacao,data_desembaraco}' <> '2026-09-09' or (v_sf.operacao_snapshot#>>'{importacao,via_transporte}')::integer <> 4
     or (v_sf.operacao_snapshot#>>'{importacao,forma_intermedio}')::integer <> 1
     or v_sf.operacao_snapshot#>>'{importacao,exportador_codigo}' <> 'SHENZHEN-HAOXIN-XUNJI-ELECTRONIC-TECHNOLOGY-TRADING-CO-LTD-'
     or (v_sf.operacao_snapshot#>>'{importacao,valor_aduaneiro}')::numeric <> 437.97 or (v_sf.operacao_snapshot#>>'{importacao,ii}')::numeric <> 262.78
     or (v_sf.operacao_snapshot#>>'{importacao,bc_icms}')::numeric <> 844.28 or (v_sf.operacao_snapshot#>>'{importacao,icms}')::numeric <> 143.53
     or (v_sf.operacao_snapshot#>>'{importacao,aliquota_icms}')::numeric <> 17 or (v_sf.operacao_snapshot#>>'{importacao,credito_icms}')::boolean is not true
     or v_sf.operacao_snapshot#>>'{importacao,gnre,receita}' <> '10005-6' or (v_sf.operacao_snapshot#>>'{importacao,gnre,valor}')::numeric <> 143.53
     or v_sf.operacao_snapshot#>>'{importacao,nota_debito,numero}' <> '2953830' or v_sf.operacao_snapshot#>>'{importacao,remetente_dir}' <> 'SHENZHEN COOL DREAM SUPPLY CO LTD'
     or jsonb_array_length(v_sf.operacao_snapshot#>'{importacao,itens}') <> 1
     or (v_sf.operacao_snapshot#>>'{importacao,itens,0,ordem}')::integer <> 1 or (v_sf.operacao_snapshot#>>'{importacao,itens,0,adicao}')::integer <> 1
     or (v_sf.operacao_snapshot#>>'{importacao,itens,0,sequencial_adicao}')::integer <> 1 or v_sf.operacao_snapshot#>>'{importacao,itens,0,fabricante}' <> 'OMRON'
     or (v_sf.operacao_snapshot#>>'{importacao,itens,0,valor_aduaneiro}')::numeric <> 437.97 or (v_sf.operacao_snapshot#>>'{importacao,itens,0,ii}')::numeric <> 262.78
     or (v_sf.operacao_snapshot#>>'{importacao,itens,0,bc_icms}')::numeric <> 844.28 or (v_sf.operacao_snapshot#>>'{importacao,itens,0,icms}')::numeric <> 143.53
     or (v_sf.operacao_snapshot#>>'{importacao,itens,0,outras_despesas}')::numeric <> 143.53
     or v_sf.operacao_snapshot#>>'{importacao,texto_fisco}' not like 'NF-E DE ENTRADA DE IMPORTACAO POR REMESSA EXPRESSA (RTS, REGIME DE TRIBUTACAO SIMPLIFICADA). DIR 260191366846 DE 09/09/2026.%RECEITA 10005-6.'
     or v_sf.operacao_snapshot#>>'{importacao,texto_complementar}' not like 'IMPORTACAO POR REMESSA EXPRESSA. AWB 1ZJ451C10441551106 UPS DO BRASIL REMESSAS EXPRESSAS LTDA. DIR 260191366846 REGISTRADA EM 09/09/2026, UA 0817700 (AEROPORTO INTERNACIONAL DE VIRACOPOS - CAMPINAS/SP). CAMBIO 5,0856. MERCADORIA USD 45,00; FRETE USD 41,12; VALOR ADUANEIRO R$ 437,97. II R$ 262,78. ICMS R$ 143,53 (BC R$ 844,28 A 17,00%), GNRE RECEITA 10005-6 R$ 143,53. NOTA DE DEBITO UPS DO BRASIL REMESSAS EXPRESSAS LTDA 2953830. REMETENTE CONFORME DIR: SHENZHEN COOL DREAM SUPPLY CO LTD. EXPORTADOR CONFORME INVOICE: SHENZHEN HAOXIN XUNJI ELECTRONIC TECHNOLOGY TRADING CO., LTD.. DESPESAS DO COURIER (SERVICOS R$ 138,53, ARMAZENAGEM R$ 12,41) FORA DA NOTA. SEM COBRANCA.' then
    raise exception 'operacao_snapshot errado: %', v_sf.operacao_snapshot;
  end if;
  select * into v_si from f.solicitacao_item where solicitacao_id = v_sf.id;
  if v_si.origem_tipo <> 'IMPORTACAO' or v_si.origem_id <> v_primeira::text or v_si.origem_item_id <> v_it.id::text or v_si.item_id <> 918001
     or v_si.codigo_produto <> 'CQM1HCPU61' or v_si.descricao <> 'CONTROLADOR PROGRAMAVEL PLC CPU' or v_si.ncm <> '85371020'
     or v_si.cfop <> '3101' or v_si.cst_icms <> '00' or v_si.csosn is not null or v_si.aliquota_icms <> 17 or v_si.icms_modalidade_base_calculo <> '3'
     or v_si.cbenef is not null or v_si.reducao_base_icms_percentual <> 0
     or v_si.cst_ipi <> '03' or v_si.ipi_codigo_enquadramento_legal <> '999' or v_si.aliquota_ipi is not null
     or v_si.cst_pis <> '98' or v_si.cst_cofins <> '98' or v_si.aliquota_pis is not null or v_si.aliquota_cofins is not null
     or v_si.cst_ibs_cbs <> '000' or v_si.cclass_trib <> '000001' or (v_si.ibs_cbs_json->>'cbs_aliquota')::numeric <> 0.9
     or v_si.quantidade <> 1 or v_si.unidade <> 'UN' or v_si.unidade_tributavel <> 'UN' or v_si.valor_unitario <> 437.97
     or v_si.valor_desconto <> 0 or v_si.ordem <> 1 or v_si.origem_mercadoria <> 1
     or v_si.perfil_operacao_id <> '1e1a0000-0000-4000-8000-000000000301' or v_si.tributacao_fonte <> 'PERFIL' or v_si.modelo <> 'NFE' then
    raise exception 'item fiscal errado: %', row_to_json(v_si);
  end if;

  -- A DIR agora esta em uso: a leitura avisa e a criacao recusa.
  v_res := f.fn_importacao_remessa_ler_dir(v_xml);
  if v_res#>>'{em_uso,importacao_id}' <> v_primeira::text or v_res#>>'{em_uso,status}' <> 'RASCUNHO' then
    raise exception 'leitura nao avisou a DIR em uso: %', v_res->'em_uso';
  end if;
  begin
    perform f.fn_importacao_remessa_criar(v_base);
    raise exception 'aceitou DIR repetida';
  exception when sqlstate '23505' then
    if sqlerrm not like 'A DIR 260191366846 ja esta em uso na importacao ' || v_primeira::text || ' (status RASCUNHO).%' then raise; end if;
  end;

  -- Gerar de novo: a anterior sai do caminho pelo fluxo auditado.
  v_res := f.fn_importacao_remessa_criar(v_base || jsonb_build_object('substituir', true, 'observacao', 'segunda geracao'));
  if v_res->>'substituiu' <> v_primeira::text then
    raise exception 'gerar de novo nao apontou a anterior: %', v_res;
  end if;
  if (select status from f.importacao_remessa where id = v_primeira) <> 'CANCELADA'
     or (select status from f.solicitacao_faturamento where id = v_primeira_sol) <> 'CANCELADA'
     or (select dados_json#>>'{cancelamento,motivo}' from f.importacao_remessa where id = v_primeira) <> 'Importacao gerada de novo pela tela de operacoes' then
    raise exception 'importacao anterior continuou ativa';
  end if;
  insert into imp_ids values ('imp', (v_res->>'importacao_id')::uuid), ('sol', (v_res->>'solicitacao_id')::uuid);
end;
$test$;

reset role;
-- 3 ---------------------------------------------------------------- pipeline (service_role)
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $test$
declare
  v_sol uuid := (select id from imp_ids where nome = 'sol');
  v_prep record;
  v_doc f.documento_fiscal%rowtype;
  v_ctx jsonb;
begin
  select * into v_prep from f.fn_nfe_preparar_documento_solicitacao(v_sol);
  if not v_prep.criado or v_prep.status <> 'RASCUNHO' then
    raise exception 'preparacao nao criou o documento: %', row_to_json(v_prep);
  end if;
  insert into imp_ids values ('doc_hom', v_prep.documento_fiscal_id);
  select * into v_doc from f.documento_fiscal where id = v_prep.documento_fiscal_id;
  if v_doc.operacao <> 'ENTRADA' or v_doc.valor_total <> 844.28 or v_doc.valor_produtos <> 437.97 or v_doc.valor_outros <> 143.53 or v_doc.cliente_id is not null then
    raise exception 'documento de homologacao errado (devia ser ENTRADA com o II no total): %', row_to_json(v_doc);
  end if;
  if (select status from f.importacao_remessa where id = (select id from imp_ids where nome = 'imp')) <> 'HOMOLOGACAO' then
    raise exception 'importacao nao passou para HOMOLOGACAO com a emissao criada';
  end if;
  v_ctx := f.fn_nfe_contexto_emissao_impl(v_prep.documento_fiscal_id);
  if jsonb_array_length(v_ctx->'itens') <> 1
     or (v_ctx#>>'{solicitacao,operacao_snapshot,tipo_documento}')::integer <> 0
     or v_ctx#>>'{solicitacao,operacao_snapshot,importacao,dir_numero}' <> '260191366846'
     or v_ctx#>>'{itens,0,solicitacao_item,cst_icms}' <> '00' or v_ctx#>>'{itens,0,solicitacao_item,cst_pis}' <> '98' then
    raise exception 'contexto de emissao errado';
  end if;
end;
$test$;

-- 4 ---------------------------------------------------------------- autorizacoes
-- Notas de mentira: as travas de producao (perfil liberado, claim) nao sao o assunto; ficam
-- desligadas na transacao, que termina em rollback. Os gatilhos da importacao e do estoque
-- continuam ligados.
alter table f.documento_fiscal disable trigger aaa_nfe_bloquear_documento_dml_direto;
alter table f.documento_fiscal_emissao disable trigger trg_bloquear_nfe_producao_sem_perfil_liberado;
alter table f.documento_fiscal_emissao disable trigger trg_nfe_bloquear_producao_cancelamento_hom_pendente;
alter table f.documento_fiscal_emissao disable trigger trg_nfe_snapshot_autorizado;
alter table f.documento_fiscal_emissao disable trigger trg_nfe_snapshot_zz_aliquotas;

do $test$
declare
  v_imp_id uuid := (select id from imp_ids where nome = 'imp');
  v_sol uuid := (select id from imp_ids where nome = 'sol');
  v_doc_hom uuid := (select id from imp_ids where nome = 'doc_hom');
  v_chave_hom text := '42260922222222000191550020000000791000000001';
  v_chave_prod text := '42260922222222000191550020000000801000000002';
  v_imp f.importacao_remessa%rowtype;
  v_movimentos bigint := (select count(*) from public.movimentacoes);
  v_mov public.movimentacoes%rowtype;
  v_forn public.fornecedores%rowtype;
  v_tit f.titulo%rowtype;
  v_pag f.pagamento%rowtype;
begin
  -- Homologacao autorizada: so o carimbo; nada de estoque nem financeiro.
  update f.documento_fiscal_emissao set status = 'AUTORIZADA', chave_acesso = v_chave_hom, numero = 79, serie = 2, autorizado_em = now()
  where documento_fiscal_id = v_doc_hom;
  select * into v_imp from f.importacao_remessa where id = v_imp_id;
  if v_imp.status <> 'HOMOLOGADA' or v_imp.chave_nfe is not null or v_imp.dados_json ? 'estoque_movimentacoes' then
    raise exception 'homologacao nao carimbou (ou mexeu no estoque): %', row_to_json(v_imp);
  end if;
  if (select count(*) from public.movimentacoes) <> v_movimentos or exists (select 1 from f.titulo where tenant_id = '1e1a0000-0000-4000-8000-000000000001') then
    raise exception 'homologacao mexeu no estoque ou no financeiro';
  end if;

  -- Producao autorizada: conclui, entrada de 1 UN a R$ 851,69 (437,97 + 262,78 + 150,94; ICMS com credito fica fora),
  -- nota de debito UPS lancada e baixada.
  insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, operacao, natureza, nfe_status, origem, valor_total)
  values ('1e1a0000-0000-4000-8000-000000000602', '1e1a0000-0000-4000-8000-000000000001', '1e1a0000-0000-4000-8000-000000000002', 'PENDENTE:P', '55', '2', '80', 'ENTRADA', 'PRODUTO', 'RASCUNHO', 'EMITIDO', 844.28);
  insert into f.documento_fiscal_emissao (documento_fiscal_id, solicitacao_id, tenant_id, empresa_id, referencia_externa, ambiente, status)
  values ('1e1a0000-0000-4000-8000-000000000602', v_sol, '1e1a0000-0000-4000-8000-000000000001', '1e1a0000-0000-4000-8000-000000000002', 'NFEP-IMP-1', 'PRODUCAO', 'RASCUNHO');
  update f.documento_fiscal_emissao set status = 'AUTORIZADA', chave_acesso = v_chave_prod, numero = 80, serie = 2, autorizado_em = now()
  where documento_fiscal_id = '1e1a0000-0000-4000-8000-000000000602';
  select * into v_imp from f.importacao_remessa where id = v_imp_id;
  if v_imp.status <> 'CONCLUIDA' or v_imp.chave_nfe <> v_chave_prod or v_imp.nfe_numero <> 80 or v_imp.nfe_serie <> 2 or v_imp.nfe_autorizada_em is null
     or v_imp.documento_fiscal_id <> '1e1a0000-0000-4000-8000-000000000602'
     or jsonb_array_length(v_imp.dados_json->'estoque_movimentacoes') <> 1 or v_imp.dados_json->'estoque_pendencias' <> '[]'::jsonb
     or v_imp.dados_json->>'concluida_em' is null or (v_imp.dados_json#>>'{ap,criado}')::boolean is not true
     or v_imp.dados_json#>>'{ap,erro}' is not null or v_imp.dados_json#>>'{ap,pagamento_id}' is null or v_imp.nota_debito_titulo_id is null then
    raise exception 'producao nao concluiu a importacao: %', row_to_json(v_imp);
  end if;
  if (select count(*) from public.movimentacoes) <> v_movimentos + 1 then
    raise exception 'entrada nao gerou uma movimentacao';
  end if;
  select * into v_mov from public.movimentacoes where id = (v_imp.dados_json#>>'{estoque_movimentacoes,0,movimentacao_id}')::bigint;
  if v_mov.item_id <> 918001 or v_mov.tipo <> 'entrada' or v_mov.quantidade <> 1 or v_mov.realizado_por <> 'importacao@example.test'
     or v_mov.custo_unitario_real <> 851.69 or v_mov.custo_unitario_bruto <> 437.97 or v_mov.credito_icms <> 143.53 or v_mov.v_icms <> 143.53
     or v_mov.v_frete_rateado <> 209.11 or v_mov.v_ipi <> 0 or v_mov.v_pis <> 0 or v_mov.v_cofins <> 0
     or v_mov.motivo not like 'Entrada por importacao NF-e 2/80 (AWB 1ZJ451C10441551106, DIR 260191366846) [IMPORTACAO %' then
    raise exception 'movimentacao errada: %', row_to_json(v_mov);
  end if;
  if (select quantidade_atual from public.estoque where item_id = 918001) <> 1
     or (select custo_medio from public.itens where id = 918001) <> 851.69 or (select custo_ultima_compra from public.itens where id = 918001) <> 851.69 then
    raise exception 'estoque ou custo medio nao entraram: saldo %, custo %', (select quantidade_atual from public.estoque where item_id = 918001), (select custo_medio from public.itens where id = 918001);
  end if;
  -- Fornecedor UPS criado pelo CNPJ do manifesto; titulo AP da nota de debito pago pela conta informada.
  select * into v_forn from public.fornecedores where id = (v_imp.dados_json#>>'{ap,fornecedor_id}')::integer;
  if v_forn.nome <> 'UPS DO BRASIL REMESSAS EXPRESSAS LTDA' or v_forn.cnpj_digits <> '74155052000173' or v_forn.tenant_id <> '1e1a0000-0000-4000-8000-000000000001'
     or v_forn.empresa_id <> '1e1a0000-0000-4000-8000-000000000002' then
    raise exception 'fornecedor do courier errado: %', row_to_json(v_forn);
  end if;
  select * into v_tit from f.titulo where id = v_imp.nota_debito_titulo_id;
  if v_tit.tipo <> 'AP' or v_tit.status <> 'PAGO' or v_tit.origem <> 'IMPORTACAO' or v_tit.fornecedor_id <> v_forn.id
     or v_tit.valor_total <> 557.25 or v_tit.valor_aberto <> 0 or v_tit.emissao_date <> '2026-09-10' or v_tit.competencia_date <> '2026-09-01'
     or v_tit.motivo_compra_id <> '1e1a0000-0000-4000-8000-000000000401' or v_tit.documento_fiscal_id is not null
     or v_tit.descricao <> 'NOTA DE DEBITO UPS DO BRASIL REMESSAS EXPRESSAS LTDA 2953830 - IMPORTACAO AWB 1ZJ451C10441551106 (DIR 260191366846): II, ICMS/GNRE E SERVICOS' then
    raise exception 'titulo da nota de debito errado: %', row_to_json(v_tit);
  end if;
  if (select (numero, vencimento_date, valor, valor_aberto) from f.titulo_parcela where titulo_id = v_tit.id and deleted_at is null)
     is distinct from ('001'::text, '2026-09-10'::date, 557.25::numeric, 0::numeric) then
    raise exception 'parcela errada: %', (select row_to_json(p) from f.titulo_parcela p where p.titulo_id = v_tit.id);
  end if;
  if (select count(*) from f.titulo_rateio where titulo_id = v_tit.id and deleted_at is null and percentual = 100 and valor = 557.25) <> 1 then
    raise exception 'rateio do titulo nao veio';
  end if;
  select * into v_pag from f.pagamento where id = (v_imp.dados_json#>>'{ap,pagamento_id}')::uuid;
  if v_pag.valor <> 557.25 or v_pag.data_pagamento <> '2026-09-10' or v_pag.forma_pagamento <> 'BOLETO'
     or v_pag.conta_bancaria_id <> '1e1a0000-0000-4000-8000-000000000501' or v_pag.observacoes not like 'Nota de debito 2953830 paga em 10/09/2026%' then
    raise exception 'pagamento errado: %', row_to_json(v_pag);
  end if;
  -- Idempotente: mexer de novo na emissao nao repete estoque nem financeiro.
  update f.documento_fiscal_emissao set mensagem = 'reprocessado' where documento_fiscal_id = '1e1a0000-0000-4000-8000-000000000602';
  if (select count(*) from public.movimentacoes) <> v_movimentos + 1 or (select count(*) from f.titulo where tenant_id = '1e1a0000-0000-4000-8000-000000000001') <> 1 then
    raise exception 'reprocessar duplicou estoque ou titulo';
  end if;

  -- Cancelamento da nota real: estorna a entrada; a importacao volta a ser cancelada (DIR livre).
  update f.documento_fiscal_emissao set status = 'CANCELADA' where documento_fiscal_id = '1e1a0000-0000-4000-8000-000000000602';
  select * into v_imp from f.importacao_remessa where id = v_imp_id;
  if v_imp.status <> 'CANCELADA' or jsonb_array_length(v_imp.dados_json->'estoque_estornos') <> 1
     or (select quantidade_atual from public.estoque where item_id = 918001) <> 0 then
    raise exception 'cancelamento nao estornou: %', row_to_json(v_imp);
  end if;
  if (select count(*) from public.movimentacoes) <> v_movimentos + 2
     or (select tipo from public.movimentacoes where id = (v_imp.dados_json#>>'{estoque_estornos,0,movimentacao_id}')::bigint) <> 'saida' then
    raise exception 'estorno nao gerou a saida';
  end if;
end;
$test$;

-- 3556 (uso e consumo, sem credito): o ICMS entra no custo; a nota de debito ja lancada nao duplica.
select set_config('request.jwt.claim.sub', '1e1a0000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"1e1a0000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;
do $test$
declare
  v_xml text := (select valor from imp_ctx where nome = 'xml');
  v_res jsonb;
begin
  v_res := f.fn_importacao_remessa_criar(jsonb_build_object(
    'xml', v_xml, 'cfop', '3556', 'aliquota_icms', 17,
    'gnre', jsonb_build_object('numero', '1234567890', 'receita', '10005-6', 'uf', 'SC', 'valor', 143.53),
    'courier', jsonb_build_object('servicos', 138.53, 'armazenagem', 12.41),
    'nota_debito', jsonb_build_object('numero', '2953830', 'valor', 557.25, 'pago_em', '2026-09-10', 'motivo_compra_id', '1e1a0000-0000-4000-8000-000000000401'),
    'exportador', jsonb_build_object('nome', 'Shenzhen Haoxin Xunji', 'logradouro', 'Jiaxian Road 2000', 'pais_codigo', '1600', 'pais_nome', 'China'),
    'itens', jsonb_build_array(jsonb_build_object('item_id', 918001, 'ncm', '85371020', 'fabricante', 'OMRON'))
  ));
  if v_res->>'natureza_operacao' <> 'IMPORTACAO_CONSUMO' or v_res->>'perfil_id' <> '1e1a0000-0000-4000-8000-000000000302' then
    raise exception 'criacao 3556 errada: %', v_res;
  end if;
  if (select (consumidor_final, credito_icms) from f.importacao_remessa where id = (v_res->>'importacao_id')::uuid) is distinct from (1::smallint, false) then
    raise exception '3556 devia ser consumidor final sem credito';
  end if;
  if (select (custo_total, custo_unitario) from f.importacao_remessa_item where importacao_id = (v_res->>'importacao_id')::uuid) is distinct from (995.22::numeric, 995.22::numeric) then
    raise exception 'custo 3556 devia levar o ICMS (995,22): %', (select row_to_json(i) from f.importacao_remessa_item i where i.importacao_id = (v_res->>'importacao_id')::uuid);
  end if;
  if (select consumidor_final from f.solicitacao_faturamento where id = (v_res->>'solicitacao_id')::uuid) <> 1 then
    raise exception 'solicitacao 3556 devia ter indFinal 1';
  end if;
  insert into imp_ids values ('imp2', (v_res->>'importacao_id')::uuid), ('sol2', (v_res->>'solicitacao_id')::uuid);
end;
$test$;
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $test$
declare
  v_imp_id uuid := (select id from imp_ids where nome = 'imp2');
  v_sol uuid := (select id from imp_ids where nome = 'sol2');
  v_imp f.importacao_remessa%rowtype;
  v_mov public.movimentacoes%rowtype;
begin
  insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, operacao, natureza, nfe_status, origem, valor_total)
  values ('1e1a0000-0000-4000-8000-000000000603', '1e1a0000-0000-4000-8000-000000000001', '1e1a0000-0000-4000-8000-000000000002', 'PENDENTE:P2', '55', '2', '81', 'ENTRADA', 'PRODUTO', 'RASCUNHO', 'EMITIDO', 844.28);
  insert into f.documento_fiscal_emissao (documento_fiscal_id, solicitacao_id, tenant_id, empresa_id, referencia_externa, ambiente, status)
  values ('1e1a0000-0000-4000-8000-000000000603', v_sol, '1e1a0000-0000-4000-8000-000000000001', '1e1a0000-0000-4000-8000-000000000002', 'NFEP-IMP-2', 'PRODUCAO', 'RASCUNHO');
  update f.documento_fiscal_emissao set status = 'AUTORIZADA', chave_acesso = '42260922222222000191550020000000811000000003', numero = 81, serie = 2, autorizado_em = now()
  where documento_fiscal_id = '1e1a0000-0000-4000-8000-000000000603';
  select * into v_imp from f.importacao_remessa where id = v_imp_id;
  if v_imp.status <> 'CONCLUIDA' or (v_imp.dados_json#>>'{ap,criado}')::boolean is not false or v_imp.dados_json#>>'{ap,titulo_id}' is null then
    raise exception 'segunda importacao devia concluir reaproveitando o titulo: %', row_to_json(v_imp);
  end if;
  if (select count(*) from f.titulo where tenant_id = '1e1a0000-0000-4000-8000-000000000001') <> 1 then
    raise exception 'nota de debito duplicada no contas a pagar';
  end if;
  select * into v_mov from public.movimentacoes where id = (v_imp.dados_json#>>'{estoque_movimentacoes,0,movimentacao_id}')::bigint;
  if v_mov.custo_unitario_real <> 995.22 or v_mov.credito_icms <> 0 or v_mov.v_icms <> 143.53 then
    raise exception 'custo sem credito errado: %', row_to_json(v_mov);
  end if;
  if (select custo_medio from public.itens where id = 918001) <> 995.22 then
    raise exception 'custo medio devia ser 995,22';
  end if;
end;
$test$;

reset role;
rollback;
