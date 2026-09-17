\set ON_ERROR_STOP on

-- Devolucao de compra pelo pipeline de NF-e (supabase/migrations/20260917190000_devolucao_compra_nfe.sql).
--
-- Como rodar (o XML da NF-e 121481/3 da Acos America entra por variavel do psql):
--   XML=$(cat docs/fiscal/exemplos/42260808819200000182550030001214811001242895.xml)
--   docker exec -i supabase_db_estoque-os psql -U postgres -d postgres -v xml="$XML" < supabase/tests/devolucao_compra_nfe.sql
--
-- Blocos:
--   1  recusas: sem item, modalidade invalida, quantidade acima do XML, nItem inexistente, CFOP
--      fora do ambito, transporte sem volume; nada gravado
--   2  gerar: operacao DEVOLUCAO_COMPRA (finNFe 4, NFref) + solicitacao com destinatario do XML,
--      item espelho proporcional (41,55 kg a R$ 7,30; ICMS 00 12%, IPI 50/999 3,25%, PIS/COFINS 01,
--      IBS 000/000001), tPag 90, volumes da tela; gerar de novo cancela o rascunho anterior; o
--      pipeline prepara o documento de homologacao
--   3  autorizacoes: homologacao so carimba a operacao; producao conclui a operacao e da baixa
--      no estoque (saida de 41,55); NF-e EMITIDA nao gera contas a receber; devolucao acumulada
--      acima do XML e recusada; cancelamento da nota real estorna a saida
--   4  sem saldo: a nota real sai, a baixa fica como pendencia na operacao
--
-- Tenant 1e170000-...-0001, empresa ...0002 (SC, CNPJ 22222222000191 — o XML e reescrito com
-- esse destinatario). Usuario ...0011 ADMIN.

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('1e170000-0000-4000-8000-000000000010', 'authenticated', 'authenticated', 'devolucao@example.test',
        '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Fiscal Devolucao"}'::jsonb, now(), now());
insert into public.tenants (id, nome, ativo) values ('1e170000-0000-4000-8000-000000000001', 'Teste devolucao', true);
insert into c.tenant (id, codigo, nome) values ('1e170000-0000-4000-8000-000000000001', 'TESTE-DEVOLUCAO', 'Teste devolucao');
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj)
values ('1e170000-0000-4000-8000-000000000002', '1e170000-0000-4000-8000-000000000001', 'DEVOLUCAO', 'EMPRESA DEVOLUCAO LTDA', 'DEVOLUCAO', '22222222000191');
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, uf, cidade)
values ('1e170000-0000-4000-8000-000000000002', '1e170000-0000-4000-8000-000000000001', '22222222000191', 'EMPRESA DEVOLUCAO LTDA', 'DEVOLUCAO', 'SC', 'JOINVILLE')
on conflict (id) do nothing;
insert into c.empresa_fiscal (empresa_id, inscricao_estadual, crt, certificado_validade_em, serie_nfe)
values ('1e170000-0000-4000-8000-000000000002', '257686835', 3, current_date + 365, 2);
insert into c.empresa_endereco (empresa_id, tipo, cep, logradouro, numero, bairro, cidade, uf, codigo_municipio_ibge)
values ('1e170000-0000-4000-8000-000000000002', 'FISCAL', '89219600', 'RUA DONA FRANCISCA', '8300', 'ZONA INDUSTRIAL NORTE', 'JOINVILLE', 'SC', '4209102');
insert into a.usuario (id, auth_user_id, nome, email, ativo) values
  ('1e170000-0000-4000-8000-000000000011', '1e170000-0000-4000-8000-000000000010', 'Fiscal Devolucao', 'devolucao@example.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo) values
  ('1e170000-0000-4000-8000-000000000011', '1e170000-0000-4000-8000-000000000001', 'ADMIN', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo) values
  ('1e170000-0000-4000-8000-000000000011', '1e170000-0000-4000-8000-000000000002', 'ADMIN', true);
insert into public.user_tenant_context (user_id, tenant_id) values
  ('1e170000-0000-4000-8000-000000000010', '1e170000-0000-4000-8000-000000000001');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id) values
  ('1e170000-0000-4000-8000-000000000010', '1e170000-0000-4000-8000-000000000001', '1e170000-0000-4000-8000-000000000002');
insert into public.municipios_ibge (codigo_ibge, nome, nome_normalizado, uf, fonte, fonte_versao, atualizado_em)
values ('4209102', 'Joinville', 'joinville', 'SC', 'teste', 'teste', now())
on conflict (codigo_ibge) do nothing;

-- Item do catalogo ligado a linha 2 da entrada, com 100 kg em estoque.
insert into public.itens (id, tenant_id, empresa_id, codigo_interno, nome, tipo, unidade_medida, controla_estoque, ativo, finalidade)
values (917001, '1e170000-0000-4000-8000-000000000001', '1e170000-0000-4000-8000-000000000002', '401014', 'TUBO DE ACO REDONDO 76,10X3,75 2.1/2"', 'produto', 'KG', true, true, 'materia_prima');
insert into public.estoque (tenant_id, empresa_id, item_id, quantidade_atual)
values ('1e170000-0000-4000-8000-000000000001', '1e170000-0000-4000-8000-000000000002', 917001, 100);

-- NF-e 121481/3 da Acos America (docs/fiscal/exemplos/42260808819200000182550030001214811001242895.xml),
-- com o destinatario trocado pela empresa de teste.
insert into public.nf_entrada (id, tenant_id, empresa_id, chave, numero, serie, modelo, emitente_nome, emitente_cnpj, data_emissao, valor_produtos, valor_frete, valor_total, xml_raw)
values (917101, '1e170000-0000-4000-8000-000000000001', '1e170000-0000-4000-8000-000000000002',
        '42260808819200000182550030001214811001242895', '121481', '3', '55', 'ACOS AMERICA LTDA', '08819200000182',
        '2026-08-24T19:43:18-03:00', 28635.24, 0, 29565.89,
        replace(:'xml', '<dest><CNPJ>13671448000189</CNPJ>', '<dest><CNPJ>22222222000191</CNPJ>'));
insert into public.nf_entrada_itens (id, tenant_id, empresa_id, nf_entrada_id, item_id, codigo_fornecedor, descricao, ncm, cfop, qtd, v_unit, v_prod)
values (917201, '1e170000-0000-4000-8000-000000000001', '1e170000-0000-4000-8000-000000000002', 917101, 917001, '401014', 'TB RED 76,10x3,75 NBR5580 2.1/2" (66)', '73063090', '5102', 2742.3, 7.3, 20018.79);

-- Perfil da devolucao (mesmo desenho do SEG-DEVOLUCAO-COMPRA-5201-O0-CST00), sem revisao.
insert into f.perfil_operacao (
  id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto, crt,
  cfop_interno, cst_icms, aliquota_icms, cst_ipi, ipi_codigo_enquadramento_legal, aliquota_ipi, cst_pis, cst_cofins,
  finalidade_emissao, consumidor_final, ambito_destino, ufs_destino, indicador_ie_destinatario, origem_mercadoria,
  exige_referencia, faixa_automacao, justificativa_faixa, habilitado_producao, vigencia_inicio
) values (
  '1e170000-0000-4000-8000-000000000301', '1e170000-0000-4000-8000-000000000001', '1e170000-0000-4000-8000-000000000002',
  'TESTE-DEVOLUCAO-5201-O0', 'Devolucao de compra teste', 'NFE', 'DEVOLUCAO_COMPRA', 'DEVOLUCAO DE COMPRA PARA INDUSTRIALIZACAO', '3',
  '5201', '00', 12, '50', '999', 3.25, '01', '01',
  4, 0, 'INTERNA', array['SC']::text[], '1', 0,
  true, 'REVISAO', 'teste', false, '2026-09-16'
);

create temporary table dev_ids (nome text primary key, id uuid not null) on commit drop;
grant all on dev_ids to authenticated;

select set_config('request.jwt.claim.sub', '1e170000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"1e170000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;

-- 1 ---------------------------------------------------------------- recusas
do $test$
declare
  v_vol constant jsonb := '[{"quantidade":1,"peso_liquido":41.55,"peso_bruto":41.55}]'::jsonb;
begin
  begin
    perform f.fn_devolucao_compra_nfe_criar(917101, '[]'::jsonb, 0::smallint, v_vol, null, null, null);
    raise exception 'aceitou sem itens';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Informe ao menos um item%' then raise; end if;
  end;
  begin
    perform f.fn_devolucao_compra_nfe_criar(917101, '[{"nitem":2,"quantidade":41.55}]'::jsonb, 5::smallint, v_vol, null, null, null);
    raise exception 'aceitou modalidade 5';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Modalidade do frete deve ser%' then raise; end if;
  end;
  begin
    perform f.fn_devolucao_compra_nfe_criar(917101, '[{"nitem":2,"quantidade":3000}]'::jsonb, 0::smallint, v_vol, null, null, null);
    raise exception 'aceitou quantidade acima do XML';
  exception when others then
    if sqlerrm not like 'Quantidade divergente no item 2%' then raise; end if;
  end;
  begin
    perform f.fn_devolucao_compra_nfe_criar(917101, '[{"nitem":9,"quantidade":1}]'::jsonb, 0::smallint, v_vol, null, null, null);
    raise exception 'aceitou nItem inexistente';
  exception when others then
    if sqlerrm not like 'Item nItem 9 nao existe%' then raise; end if;
  end;
  begin
    perform f.fn_devolucao_compra_nfe_criar(917101, '[{"nitem":2,"quantidade":41.55}]'::jsonb, 0::smallint, v_vol, null, null, '6201');
    raise exception 'aceitou CFOP interestadual dentro de SC';
  exception when sqlstate '22023' then
    if sqlerrm not like 'CFOP 6201 nao vale para esta devolucao (INTERNA). Use 5201 ou 5553.' then raise; end if;
  end;
  begin
    perform f.fn_devolucao_compra_nfe_criar(917101, '[{"nitem":2,"quantidade":41.55}]'::jsonb, 0::smallint, null, null, null, null);
    raise exception 'aceitou transporte sem volume';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Informe ao menos um volume%' then raise; end if;
  end;
  if exists (select 1 from f.operacao_fiscal where tenant_id = '1e170000-0000-4000-8000-000000000001')
     or exists (select 1 from f.solicitacao_faturamento where tenant_id = '1e170000-0000-4000-8000-000000000001') then
    raise exception 'recusa deixou operacao ou solicitacao gravada';
  end if;
end;
$test$;

-- 2 ---------------------------------------------------------------- gerar
do $test$
declare
  v_res jsonb;
  v_op f.operacao_fiscal%rowtype;
  v_sf f.solicitacao_faturamento%rowtype;
  v_si f.solicitacao_item%rowtype;
  v_primeira_op uuid;
  v_primeira_sol uuid;
begin
  v_res := f.fn_devolucao_compra_nfe_criar(917101, '[{"nitem":2,"quantidade":41.55}]'::jsonb, 0::smallint,
    '[{"quantidade":1,"peso_liquido":41.55,"peso_bruto":41.55}]'::jsonb, 'Tubo fora de medida', null, null);
  v_primeira_op := (v_res->>'operacao_id')::uuid;
  v_primeira_sol := (v_res->>'solicitacao_id')::uuid;
  if v_res->>'cfop' <> '5201' or v_res->>'ambito' <> 'INTERNA' or v_res->>'natureza_operacao' <> 'DEVOLUCAO_COMPRA'
     or (v_res->>'valor_produtos')::numeric <> 303.32 or (v_res->>'valor_total')::numeric <> 313.18 or (v_res->>'itens')::integer <> 1
     or v_res->>'perfil_id' <> '1e170000-0000-4000-8000-000000000301' or v_res->>'destinatario' <> 'ACOS AMERICA LTDA'
     or v_res->>'cliente_id' is not null then
    raise exception 'retorno da criacao errado: %', v_res;
  end if;
  select * into v_op from f.operacao_fiscal where id = v_primeira_op;
  if v_op.tipo <> 'DEVOLUCAO_COMPRA' or v_op.finalidade <> 'DEVOLUCAO_COMPRA' or v_op.status <> 'PRONTO_HOMOLOGACAO' or v_op.ambiente <> 'HOMOLOGACAO'
     or v_op.nf_entrada_origem_id <> 917101 or v_op.nfe_referenciada <> '42260808819200000182550030001214811001242895'
     or v_op.cfop_confirmado <> '5201' or v_op.finalidade_emissao <> 4 or v_op.solicitacao_id <> v_primeira_sol
     or v_op.valor_total <> 313.18 or v_op.destinatario_id is not null
     or v_op.dados_json->>'origem_numero' <> '121481' or v_op.dados_json->>'origem_serie' <> '3' or v_op.dados_json->>'origem_data_emissao' <> '24/08/2026'
     or v_op.dados_json->>'perfil_codigo' <> 'TESTE-DEVOLUCAO-5201-O0' or v_op.dados_json->>'chave_origem' <> '42260808819200000182550030001214811001242895'
     or v_op.entrega_json->>'documento' <> '08819200000182' or v_op.entrega_json->>'nome' <> 'ACOS AMERICA LTDA'
     or v_op.justificativa_fisco <> 'Tubo fora de medida' or v_op.perfil_operacao_id <> '1e170000-0000-4000-8000-000000000301' then
    raise exception 'operacao errada: %', row_to_json(v_op);
  end if;
  select * into v_sf from f.solicitacao_faturamento where id = v_primeira_sol;
  if v_sf.natureza_operacao <> 'DEVOLUCAO_COMPRA' or v_sf.cliente_id is not null or v_sf.status <> 'PREVIA'
     or v_sf.finalidade_emissao <> 4 or v_sf.consumidor_final <> 0 or v_sf.presenca_comprador <> 9 or v_sf.modalidade_frete <> 0
     or v_sf.valor_frete <> 0 or v_sf.pagamento_forma <> '90' or v_sf.pagamento_indicador <> 0 or v_sf.destinacao_mercadoria is not null
     or v_sf.destino_uf_confirmada <> 'SC' or v_sf.snapshot_cadastro_em is null or v_sf.revisao_fiscal_confirmada_em is null
     or v_sf.transportador_dados is not null or jsonb_array_length(v_sf.volumes_dados) <> 1
     or (v_sf.volumes_dados#>>'{0,quantidade}')::integer <> 1 or (v_sf.volumes_dados#>>'{0,peso_bruto}')::numeric <> 41.55
     or v_sf.observacao <> 'Tubo fora de medida' or v_sf.perfil_operacao_id <> '1e170000-0000-4000-8000-000000000301' then
    raise exception 'solicitacao errada: %', row_to_json(v_sf);
  end if;
  -- Destinatario = emitente da entrada, do XML.
  if v_sf.destinatario_snapshot->>'documento' <> '08819200000182' or v_sf.destinatario_snapshot->>'nome' <> 'ACOS AMERICA LTDA'
     or v_sf.destinatario_snapshot->>'inscricao_estadual' <> '255387644' or v_sf.destinatario_snapshot->>'indicador_ie' <> '1'
     or v_sf.destinatario_snapshot->>'logradouro' <> 'RUA DONA FRANCISCA' or v_sf.destinatario_snapshot->>'numero_endereco' <> '7796'
     or v_sf.destinatario_snapshot->>'bairro' <> 'DISTRITO INDUSTRIAL' or v_sf.destinatario_snapshot->>'cidade' <> 'Joinville'
     or v_sf.destinatario_snapshot->>'uf' <> 'SC' or v_sf.destinatario_snapshot->>'codigo_ibge_municipio' <> '4209102'
     or v_sf.destinatario_snapshot->>'cep' <> '89219600' or v_sf.destinatario_snapshot->>'telefone' <> '4734179500'
     or v_sf.destinatario_snapshot->>'id' is not null then
    raise exception 'destinatario_snapshot errado: %', v_sf.destinatario_snapshot;
  end if;
  if v_sf.emitente_snapshot->>'cnpj' <> '22222222000191' or v_sf.emitente_snapshot->>'cidade' <> 'Joinville'
     or (v_sf.emitente_snapshot->>'serie_nfe')::integer <> 2 then
    raise exception 'emitente_snapshot errado: %', v_sf.emitente_snapshot;
  end if;
  if v_sf.operacao_snapshot->>'natureza_operacao' <> 'DEVOLUCAO_COMPRA' or (v_sf.operacao_snapshot->>'finalidade_emissao')::integer <> 4
     or v_sf.operacao_snapshot->>'nfe_referenciada' <> '42260808819200000182550030001214811001242895'
     or v_sf.operacao_snapshot#>>'{pagamento,forma}' <> '90' or (v_sf.operacao_snapshot#>>'{pagamento,indicador}')::integer <> 0
     or (v_sf.operacao_snapshot->>'modalidade_frete')::integer <> 0 or v_sf.operacao_snapshot->>'destinacao_mercadoria' is not null
     or jsonb_array_length(v_sf.operacao_snapshot->'volumes') <> 1 or v_sf.operacao_snapshot->'transportador' <> 'null'::jsonb
     or v_sf.operacao_snapshot#>>'{devolucao_compra,numero}' <> '121481' or v_sf.operacao_snapshot#>>'{devolucao_compra,serie}' <> '3'
     or v_sf.operacao_snapshot#>>'{devolucao_compra,data_emissao}' <> '24/08/2026'
     or v_sf.operacao_snapshot#>>'{devolucao_compra,chave}' <> '42260808819200000182550030001214811001242895'
     or v_sf.operacao_snapshot#>>'{devolucao_compra,operacao_id}' <> v_primeira_op::text
     or (v_sf.operacao_snapshot#>>'{devolucao_compra,nf_entrada_id}')::bigint <> 917101
     or v_sf.operacao_snapshot#>>'{devolucao_compra,itens_texto}' <> 'ITEM 2 (401014): 41,55 KG DE 2.742,30 KG' then
    raise exception 'operacao_snapshot errado: %', v_sf.operacao_snapshot;
  end if;
  select * into v_si from f.solicitacao_item where solicitacao_id = v_sf.id;
  if v_si.origem_tipo <> 'DEVOLUCAO_COMPRA' or v_si.origem_id <> v_primeira_op::text or v_si.item_id <> 917001
     or v_si.codigo_produto <> '401014' or v_si.descricao <> 'TB RED 76,10x3,75 NBR5580 2.1/2" (66)' or v_si.ncm <> '73063090'
     or v_si.cfop <> '5201' or v_si.cst_icms <> '00' or v_si.csosn is not null or v_si.aliquota_icms <> 12 or v_si.icms_modalidade_base_calculo <> '3'
     or v_si.cbenef is not null or v_si.reducao_base_icms_percentual <> 0
     or v_si.cst_ipi <> '50' or v_si.ipi_codigo_enquadramento_legal <> '999' or v_si.aliquota_ipi <> 3.25
     or v_si.cst_pis <> '01' or v_si.cst_cofins <> '01' or v_si.aliquota_pis <> 1.65 or v_si.aliquota_cofins <> 7.6
     or v_si.cst_ibs_cbs <> '000' or v_si.cclass_trib <> '000001' or (v_si.ibs_cbs_json->>'cbs_aliquota')::numeric <> 0.9
     or v_si.quantidade <> 41.55 or v_si.unidade <> 'KG' or v_si.unidade_tributavel <> 'KG' or v_si.valor_unitario <> 7.3
     or v_si.valor_desconto <> 0 or v_si.ordem <> 1 or v_si.origem_mercadoria <> 0
     or v_si.perfil_operacao_id <> '1e170000-0000-4000-8000-000000000301' or v_si.tributacao_fonte <> 'PERFIL' or v_si.modelo <> 'NFE' then
    raise exception 'item errado: %', row_to_json(v_si);
  end if;
  -- Item da operacao: proporcional ao XML.
  if (select (quantidade, valor_total, valor_icms, valor_ipi, valor_pis, valor_cofins, nf_entrada_item_id, item_id)
        from f.operacao_fiscal_item where operacao_id = v_primeira_op)
     is distinct from (41.55::numeric, 303.32::numeric, 36.40::numeric, 9.86::numeric, 4.40::numeric, 20.29::numeric, 917201::bigint, 917001) then
    raise exception 'item da operacao errado: %', (select row_to_json(i) from f.operacao_fiscal_item i where i.operacao_id = v_primeira_op);
  end if;

  -- Gerar de novo (outra quantidade): o rascunho anterior sai do caminho.
  v_res := f.fn_devolucao_compra_nfe_criar(917101, '[{"nitem":2,"quantidade":41.55}]'::jsonb, 1::smallint,
    '[{"quantidade":1,"especie":"FEIXE","peso_liquido":41.55,"peso_bruto":41.55}]'::jsonb, null,
    '{"nome":"EXPRESSO SAO MIGUEL","documento":"01234567000189","uf":"SC"}'::jsonb, null);
  if (select status from f.operacao_fiscal where id = v_primeira_op) <> 'CANCELADA'
     or (select status from f.solicitacao_faturamento where id = v_primeira_sol) <> 'CANCELADA' then
    raise exception 'devolucao anterior continuou ativa';
  end if;
  select * into v_sf from f.solicitacao_faturamento where id = (v_res->>'solicitacao_id')::uuid;
  if v_sf.modalidade_frete <> 1 or v_sf.transportador_dados->>'nome' <> 'EXPRESSO SAO MIGUEL'
     or v_sf.volumes_dados#>>'{0,especie}' <> 'FEIXE' or v_sf.operacao_snapshot#>>'{transportador,nome}' <> 'EXPRESSO SAO MIGUEL' then
    raise exception 'transporte da tela nao entrou: %', row_to_json(v_sf);
  end if;
  insert into dev_ids values ('op', (v_res->>'operacao_id')::uuid), ('sol', (v_res->>'solicitacao_id')::uuid);
end;
$test$;

reset role;
-- O pipeline prepara o documento de homologacao a partir dessa solicitacao (a Edge chama
-- com service_role).
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $test$
declare
  v_sol uuid := (select id from dev_ids where nome = 'sol');
  v_prep record;
  v_ctx jsonb;
begin
  select * into v_prep from f.fn_nfe_preparar_documento_solicitacao(v_sol);
  if not v_prep.criado or v_prep.status <> 'RASCUNHO' then
    raise exception 'preparacao nao criou o documento: %', row_to_json(v_prep);
  end if;
  insert into dev_ids values ('doc_hom', v_prep.documento_fiscal_id);
  if (select count(*) from f.documento_fiscal_item where documento_fiscal_id = v_prep.documento_fiscal_id) <> 1 then
    raise exception 'documento preparado errado';
  end if;
  v_ctx := f.fn_nfe_contexto_emissao_impl(v_prep.documento_fiscal_id);
  if jsonb_array_length(v_ctx->'itens') <> 1
     or v_ctx#>>'{solicitacao,operacao_snapshot,nfe_referenciada}' <> '42260808819200000182550030001214811001242895'
     or (v_ctx#>>'{solicitacao,operacao_snapshot,finalidade_emissao}')::integer <> 4
     or v_ctx#>>'{itens,0,solicitacao_item,cst_icms}' <> '00' or (v_ctx#>>'{itens,0,solicitacao_item,aliquota_ipi}')::numeric <> 3.25 then
    raise exception 'contexto de emissao errado';
  end if;
end;
$test$;

-- 3 ---------------------------------------------------------------- autorizacoes
-- Notas de mentira: as travas de producao (perfil liberado, claim) nao sao o assunto; ficam
-- desligadas na transacao, que termina em rollback. Os gatilhos da operacao e do estoque
-- continuam ligados.
alter table f.documento_fiscal disable trigger aaa_nfe_bloquear_documento_dml_direto;
alter table f.documento_fiscal_emissao disable trigger trg_bloquear_nfe_producao_sem_perfil_liberado;
alter table f.documento_fiscal_emissao disable trigger trg_nfe_bloquear_producao_cancelamento_hom_pendente;
alter table f.documento_fiscal_emissao disable trigger trg_nfe_snapshot_autorizado;
alter table f.documento_fiscal_emissao disable trigger trg_nfe_snapshot_zz_aliquotas;

do $test$
declare
  v_op uuid := (select id from dev_ids where nome = 'op');
  v_sol uuid := (select id from dev_ids where nome = 'sol');
  v_doc_hom uuid := (select id from dev_ids where nome = 'doc_hom');
  v_chave_hom text := '42260913671448000189550020000000721000000001';
  v_chave_prod text := '42260913671448000189550020000000731000000002';
  v_o f.operacao_fiscal%rowtype;
  v_movimentos bigint := (select count(*) from public.movimentacoes);
  v_mov public.movimentacoes%rowtype;
begin
  -- Homologacao autorizada: so o carimbo; nada de estoque.
  update f.documento_fiscal_emissao set status = 'AUTORIZADA', chave_acesso = v_chave_hom, numero = 72, serie = 2, autorizado_em = now()
  where documento_fiscal_id = v_doc_hom;
  select * into v_o from f.operacao_fiscal where id = v_op;
  if v_o.dados_json#>>'{homologacao,chave}' is distinct from v_chave_hom or v_o.status <> 'PRONTO_HOMOLOGACAO'
     or v_o.dados_json ? 'estoque_movimentacoes' then
    raise exception 'homologacao nao ficou na operacao (ou mexeu no estoque): %', row_to_json(v_o);
  end if;
  if (select count(*) from public.movimentacoes) <> v_movimentos then
    raise exception 'homologacao mexeu no estoque';
  end if;

  -- Producao autorizada: conclui a operacao e da baixa de 41,55 kg.
  insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, operacao, natureza, nfe_status, origem, valor_total)
  values ('1e170000-0000-4000-8000-000000000502', '1e170000-0000-4000-8000-000000000001', '1e170000-0000-4000-8000-000000000002', 'PENDENTE:P', '55', '2', '73', 'SAIDA', 'PRODUTO', 'RASCUNHO', 'EMITIDO', 313.18);
  insert into f.documento_fiscal_emissao (documento_fiscal_id, solicitacao_id, tenant_id, empresa_id, referencia_externa, ambiente, status)
  values ('1e170000-0000-4000-8000-000000000502', v_sol, '1e170000-0000-4000-8000-000000000001', '1e170000-0000-4000-8000-000000000002', 'NFEP-DEV-1', 'PRODUCAO', 'RASCUNHO');
  update f.documento_fiscal_emissao set status = 'AUTORIZADA', chave_acesso = v_chave_prod, numero = 73, serie = 2, autorizado_em = now()
  where documento_fiscal_id = '1e170000-0000-4000-8000-000000000502';
  select * into v_o from f.operacao_fiscal where id = v_op;
  if v_o.status <> 'CONCLUIDA' or v_o.chave_primeira_nota <> v_chave_prod or v_o.ambiente <> 'PRODUCAO'
     or jsonb_array_length(v_o.dados_json->'estoque_movimentacoes') <> 1 or v_o.dados_json->'estoque_pendencias' <> '[]'::jsonb
     or v_o.dados_json->>'estoque_baixado_em' is null then
    raise exception 'producao nao concluiu a operacao ou nao baixou o estoque: %', row_to_json(v_o);
  end if;
  if (select count(*) from public.movimentacoes) <> v_movimentos + 1 then
    raise exception 'baixa nao gerou uma movimentacao';
  end if;
  select * into v_mov from public.movimentacoes where id = (v_o.dados_json#>>'{estoque_movimentacoes,0,movimentacao_id}')::bigint;
  if v_mov.item_id <> 917001 or v_mov.tipo <> 'saida' or v_mov.quantidade <> 41.55 or v_mov.realizado_por <> 'devolucao@example.test'
     or v_mov.motivo not like 'Devolucao de compra NF-e 2/73 ao fornecedor ACOS AMERICA LTDA (NF entrada 121481) [DEVOLUCAO %' then
    raise exception 'movimentacao errada: %', row_to_json(v_mov);
  end if;
  if (select quantidade_atual from public.estoque where item_id = 917001) <> 58.45 then
    raise exception 'saldo nao caiu para 58,45: %', (select quantidade_atual from public.estoque where item_id = 917001);
  end if;

  -- NF-e EMITIDA: sem contas a receber (tPag 90).
  update f.documento_fiscal set nfe_status = 'EMITIDA', chave_acesso = v_chave_prod where id = '1e170000-0000-4000-8000-000000000502';
  if exists (select 1 from f.titulo t where t.documento_fiscal_id = '1e170000-0000-4000-8000-000000000502') then
    raise exception 'devolucao gerou contas a receber';
  end if;
end;
$test$;

-- Acumulado: com 41,55 kg ja devolvidos em nota real, o resto da linha (2.700,75) ainda cabe;
-- 2.742,30 nao.
select set_config('request.jwt.claim.sub', '1e170000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"1e170000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;
do $test$
declare
  v_res jsonb;
  v_vol constant jsonb := '[{"quantidade":1,"peso_liquido":41.55,"peso_bruto":41.55}]'::jsonb;
begin
  begin
    perform f.fn_devolucao_compra_nfe_criar(917101, '[{"nitem":2,"quantidade":2742.30}]'::jsonb, 0::smallint, v_vol, null, null, null);
    raise exception 'aceitou devolver a linha inteira depois da nota real';
  exception when others then
    if sqlerrm not like 'Quantidade acumulada excede o XML no item 2%' then raise; end if;
  end;
  v_res := f.fn_devolucao_compra_nfe_criar(917101, '[{"nitem":2,"quantidade":2700.75}]'::jsonb, 0::smallint, v_vol, null, null, null);
  if (select status from f.operacao_fiscal where id = (select id from dev_ids where nome = 'op')) <> 'CONCLUIDA' then
    raise exception 'gerar de novo cancelou a operacao concluida';
  end if;
  insert into dev_ids values ('op2', (v_res->>'operacao_id')::uuid), ('sol2', (v_res->>'solicitacao_id')::uuid);
end;
$test$;

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $test$
declare
  v_op uuid := (select id from dev_ids where nome = 'op');
  v_o f.operacao_fiscal%rowtype;
  v_movimentos bigint := (select count(*) from public.movimentacoes);
begin
  -- Cancelamento da nota real: estorna a saida e cancela a operacao.
  update f.documento_fiscal_emissao set status = 'CANCELADA' where documento_fiscal_id = '1e170000-0000-4000-8000-000000000502';
  select * into v_o from f.operacao_fiscal where id = v_op;
  if v_o.status <> 'CANCELADA' or jsonb_array_length(v_o.dados_json->'estoque_estornos') <> 1 or v_o.dados_json->>'estoque_estornado_em' is null then
    raise exception 'cancelamento nao estornou: %', row_to_json(v_o);
  end if;
  if (select count(*) from public.movimentacoes) <> v_movimentos + 1
     or (select quantidade_atual from public.estoque where item_id = 917001) <> 100 then
    raise exception 'estorno nao devolveu o saldo';
  end if;
end;
$test$;

-- 4 ---------------------------------------------------------------- sem saldo
do $test$
declare
  v_sol uuid := (select id from dev_ids where nome = 'sol2');
  v_op uuid := (select id from dev_ids where nome = 'op2');
  v_prep record;
  v_o f.operacao_fiscal%rowtype;
  v_movimentos bigint;
begin
  update public.estoque set quantidade_atual = 10 where item_id = 917001;
  select * into v_prep from f.fn_nfe_preparar_documento_solicitacao(v_sol);
  update f.documento_fiscal_emissao set status = 'AUTORIZADA', chave_acesso = '42260913671448000189550020000000741000000003', numero = 74, serie = 2, autorizado_em = now()
  where documento_fiscal_id = v_prep.documento_fiscal_id;
  v_movimentos := (select count(*) from public.movimentacoes);
  insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, operacao, natureza, nfe_status, origem, valor_total)
  values ('1e170000-0000-4000-8000-000000000503', '1e170000-0000-4000-8000-000000000001', '1e170000-0000-4000-8000-000000000002', 'PENDENTE:P2', '55', '2', '75', 'SAIDA', 'PRODUTO', 'RASCUNHO', 'EMITIDO', 1);
  insert into f.documento_fiscal_emissao (documento_fiscal_id, solicitacao_id, tenant_id, empresa_id, referencia_externa, ambiente, status)
  values ('1e170000-0000-4000-8000-000000000503', v_sol, '1e170000-0000-4000-8000-000000000001', '1e170000-0000-4000-8000-000000000002', 'NFEP-DEV-2', 'PRODUCAO', 'RASCUNHO');
  update f.documento_fiscal_emissao set status = 'AUTORIZADA', chave_acesso = '42260913671448000189550020000000751000000004', numero = 75, serie = 2, autorizado_em = now()
  where documento_fiscal_id = '1e170000-0000-4000-8000-000000000503';
  select * into v_o from f.operacao_fiscal where id = v_op;
  if v_o.status <> 'CONCLUIDA' or v_o.dados_json->'estoque_movimentacoes' <> '[]'::jsonb
     or jsonb_array_length(v_o.dados_json->'estoque_pendencias') <> 1
     or v_o.dados_json#>>'{estoque_pendencias,0,motivo}' not like 'saldo insuficiente%' then
    raise exception 'sem saldo: a operacao devia concluir com a pendencia: %', row_to_json(v_o);
  end if;
  if (select count(*) from public.movimentacoes) <> v_movimentos or (select quantidade_atual from public.estoque where item_id = 917001) <> 10 then
    raise exception 'sem saldo mexeu no estoque';
  end if;
end;
$test$;

reset role;
rollback;
