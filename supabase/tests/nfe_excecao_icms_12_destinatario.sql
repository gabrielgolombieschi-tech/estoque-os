\set ON_ERROR_STOP on

-- Excecao "ICMS 12% por exigencia do destinatario"
-- (supabase/migrations/20260916140000_nfe_excecao_icms_12_destinatario.sql).
--
-- Blocos:
--   1  ativar: recusa sem OC, sem evidencia, destinacao revenda, destinatario nao
--      contribuinte e operacao interestadual — e nada gravado
--   2  ativar: grava OC, evidencia, usuario e data; reativar guarda o historico; anexo
--   3  conferencia da OV: item sem SC820006 a 12% CST 00 e indFinal 1 passam mesmo com o
--      perfil dizendo outra coisa; item SC820006 segue o perfil; 17% ou indFinal 0 recusam
--   4  congelamento: a excecao vai para o snapshot; desativada, some e a trava do perfil volta
--   5  conferencia da OS: FAB com perfil 17% sai CST 00 a 12%, indFinal 1, IPI igual
--   6  relatorio mensal: vBC, ICMS e diferenca para 17% so dos itens da excecao
--   7  xMun: codigo IBGE na cidade do cliente vira o nome; snapshot com o nome do IBGE
--      (20260916150000_nfe_xmun_nome_do_municipio.sql)
--
-- Tenant 1e120000-...-0001, empresa ...0002 (SC). Clientes:
--   912001 PBG contribuinte SC        912002 nao contribuinte SC
--   912003 contribuinte PR
-- Itens: 912001 REV-1 (NCM 90328911, revenda), 912002 CONT-1 (NCM 85364900, SC820006),
--        912003 FAB-0001 (NCM 90328989, IPI 9,75%).

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('1e120000-0000-4000-8000-000000000010', 'authenticated', 'authenticated', 'excecao-icms@example.test',
  '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Fiscal Excecao"}'::jsonb, now(), now());

insert into public.tenants (id, nome, ativo) values ('1e120000-0000-4000-8000-000000000001', 'Teste excecao ICMS', true);
insert into c.tenant (id, codigo, nome) values ('1e120000-0000-4000-8000-000000000001', 'TESTE-EXC-ICMS', 'Teste excecao ICMS');
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj)
values ('1e120000-0000-4000-8000-000000000002', '1e120000-0000-4000-8000-000000000001', 'EXCICMS', 'EMPRESA EXCECAO ICMS LTDA', 'EXC ICMS', '22222222000191');
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, uf, cidade)
values ('1e120000-0000-4000-8000-000000000002', '1e120000-0000-4000-8000-000000000001', '22222222000191', 'EMPRESA EXCECAO ICMS LTDA', 'EXC ICMS', 'SC', 'JOINVILLE')
on conflict (id) do nothing;
insert into c.empresa_fiscal (empresa_id, inscricao_estadual, crt, certificado_validade_em, serie_nfe)
values ('1e120000-0000-4000-8000-000000000002', '257686835', 3, current_date + 365, 2);
insert into c.empresa_endereco (empresa_id, tipo, cep, logradouro, numero, bairro, cidade, uf, codigo_municipio_ibge)
values ('1e120000-0000-4000-8000-000000000002', 'FISCAL', '89219600', 'RUA DONA FRANCISCA', '8300', 'ZONA INDUSTRIAL NORTE', 'JOINVILLE', 'SC', '4209102');

insert into a.usuario (id, auth_user_id, nome, email, ativo)
values ('1e120000-0000-4000-8000-000000000011', '1e120000-0000-4000-8000-000000000010', 'Fiscal Excecao', 'excecao-icms@example.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo)
values ('1e120000-0000-4000-8000-000000000011', '1e120000-0000-4000-8000-000000000001', 'ADMIN', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo)
values ('1e120000-0000-4000-8000-000000000011', '1e120000-0000-4000-8000-000000000002', 'DIRETOR', true);
insert into public.user_tenant_context (user_id, tenant_id)
values ('1e120000-0000-4000-8000-000000000010', '1e120000-0000-4000-8000-000000000001');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
values ('1e120000-0000-4000-8000-000000000010', '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002');

insert into public.clientes (
  id, tenant_id, empresa_id, nome, documento, razao_social, inscricao_estadual,
  cep, logradouro, numero_endereco, bairro, cidade, uf, pais, indicador_ie, codigo_ibge_municipio
) values
  (912001, '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002',
   'PBG S/A', '83475913000191', 'PBG S/A', '250355050', '88840000', 'RUA MANOEL DOS SANTOS', '1', 'CENTRO', 'TIJUCAS', 'SC', 'BRASIL', '1', '4218004'),
  (912002, '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002',
   'CONDOMINIO SEM IE', '11222333000181', 'CONDOMINIO SEM IE', null, '89200000', 'RUA A', '2', 'CENTRO', 'JOINVILLE', 'SC', 'BRASIL', '9', '4209102'),
  (912003, '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002',
   'INDUSTRIA PR', '22333444000181', 'INDUSTRIA PR LTDA', '9012345678', '80000000', 'RUA B', '3', 'CENTRO', 'CURITIBA', 'PR', 'BRASIL', '1', '4106902');

insert into public.itens (id, tenant_id, empresa_id, codigo_interno, nome, tipo, unidade_medida, finalidade, ativo)
values
  (912001, '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 'REV-1', 'SOFT-STARTER REVENDA', 'produto', 'UN', 'revenda', true),
  (912002, '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 'CONT-1', 'CONTATOR AUTOMACAO', 'produto', 'UN', 'revenda', true),
  (912003, '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 'FAB-0001', 'PAINEL FABRICADO', 'produto', 'UN', 'revenda', true);

update public.fiscal_itens fi
set ncm = v.ncm, origem = 0, unidade_tributavel = 'UN', cst_ipi = v.cst_ipi, aliq_ipi = v.aliq_ipi
from (values (912001, '90328911', '53', null::numeric), (912002, '85364900', '53', null), (912003, '90328989', '50', 9.75)) v(item_id, ncm, cst_ipi, aliq_ipi)
where fi.tenant_id = '1e120000-0000-4000-8000-000000000001'
  and fi.empresa_id = '1e120000-0000-4000-8000-000000000002'
  and fi.item_id = v.item_id;

insert into f.tributacao_provisoria_homologacao (tenant_id, empresa_id, cfop, cst_ipi, c_enq, aliquota_ipi, pendencia_contador)
values ('1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', '5102', '53', '999', null, 'Fixture de teste com rollback.');

-- Perfis: o de revenda a 12% com indFinal 0 e o que a PBG pegou na venda de manutencao; o
-- de automacao leva SC820006; o da OS e o de manutencao a 17%.
insert into f.perfil_operacao (
  id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto,
  crt, ambito_destino, ufs_destino, indicador_ie_destinatario, origem_mercadoria,
  cfop_interno, cfop_externo, cst_icms, icms_modalidade_base_calculo,
  aliquota_icms, reducao_base_icms_percentual, cbenef_aplicacao, cbenef, cst_pis,
  cst_cofins, finalidade_emissao, consumidor_final, faixa_automacao,
  habilitado_producao, cst_ibs_cbs, cclass_trib, cclass_trib_versao, ibs_cbs_json,
  ncms, ncms_elegiveis, destinacoes_mercadoria, revisao_fiscal_em, beneficio_texto_legal, percentual_base_calculo
) values
  ('1e120000-0000-4000-8000-000000000301', '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002',
   'TESTE-OV-5102-CST00-12', 'Venda interna 12%', 'NFE', 'VENDA_MERCADORIA_TERCEIROS', 'VENDA', '3', 'INTERNA', array['SC'], '1', 0,
   '5102', null, '00', '3', 12, 0, 'SEM_BENEFICIO', null, '49', '49', 1, 0, 'REVISAO', false, '000', '000001',
   'Informe Técnico 2025.002 v1.60', '{"ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9}'::jsonb, null, null, null, now(), null, null),
  ('1e120000-0000-4000-8000-000000000302', '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002',
   'TESTE-OV-5102-CST20-AUTOMACAO', 'Venda interna automacao', 'NFE', 'VENDA_MERCADORIA_TERCEIROS', 'VENDA', '3', 'INTERNA', array['SC'], '1', 0,
   '5102', null, '20', '3', 17, 29.412, 'COM_BENEFICIO', 'SC820006', '49', '49', 1, 0, 'REVISAO', false, '000', '000001',
   'Informe Técnico 2025.002 v1.60', '{"ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9}'::jsonb, array['85364900'], array['85364900'], null, now(), 'RICMS/SC-01, Anexo 2, Art. 7o, VII', 70.588),
  ('1e120000-0000-4000-8000-000000000303', '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002',
   'TESTE-OS-5101-MANUTENCAO-17', 'Industrializacao manutencao 17%', 'NFE', 'VENDA_INDUSTRIALIZACAO_INTERNA', 'VENDA', '3', 'INTERNA', array['SC'], '1', 0,
   '5101', null, '00', '3', 17, 0, 'SEM_BENEFICIO', null, '49', '49', 1, null, 'REVISAO', false, '000', '000001',
   'Informe Técnico 2025.002 v1.60', '{"ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9}'::jsonb, null, null, array['MANUTENCAO'], now(), null, null);

insert into public.ordens_servico (
  id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id, empresa_id,
  status_fluxo, tipo_documento, codigo, numero_doc, descricao_servico, orcado
) values
  (912001, 'OV-EXC-1', 'PBG S/A', 912001, 'em_andamento', 912001, '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 'em_andamento', 'OV', 'OV-EXC-001', 1, 'VENDA MANUTENCAO', 5000),
  (912002, 'OV-EXC-2', 'CONDOMINIO SEM IE', 912002, 'em_andamento', 912002, '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 'em_andamento', 'OV', 'OV-EXC-002', 2, 'VENDA NAO CONTRIBUINTE', 5000),
  (912003, 'OV-EXC-3', 'INDUSTRIA PR', 912003, 'em_andamento', 912003, '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 'em_andamento', 'OV', 'OV-EXC-003', 3, 'VENDA PR', 5000),
  (912004, 'OS-EXC-4', 'PBG S/A', 912001, 'em_andamento', 912004, '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 'em_andamento', 'OS', 'OS-EXC-004', 4, 'PAINEL PARA MANUTENCAO', 5000);

insert into public.os_itens (id, os_id, item_id, quantidade, valor_unitario, valor_total, tenant_id, empresa_id, finalidade)
values
  (912001, 912001, 912001, 1, 4821, 4821, '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 'venda'),
  (912002, 912001, 912002, 1, 100, 100, '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 'venda'),
  (912003, 912002, 912001, 1, 100, 100, '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 'venda'),
  (912004, 912003, 912001, 1, 100, 100, '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 'venda');

create temporary table excecao_ids (nome text primary key, id uuid not null) on commit drop;
grant all on excecao_ids to authenticated;

insert into excecao_ids values
  ('ov_pbg', f.fn_solicitacao_faturamento_criar_parcial('1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 912001,
     '[{"os_item_id":912001,"quantidade":1,"valor_unitario":4821},{"os_item_id":912002,"quantidade":1,"valor_unitario":100}]'::jsonb)),
  ('ov_sem_ie', f.fn_solicitacao_faturamento_criar_parcial('1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 912002,
     '[{"os_item_id":912003,"quantidade":1,"valor_unitario":100}]'::jsonb)),
  ('ov_pr', f.fn_solicitacao_faturamento_criar_parcial('1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 912003,
     '[{"os_item_id":912004,"quantidade":1,"valor_unitario":100}]'::jsonb)),
  ('os_fab', f.fn_solicitacao_faturamento_criar_os_livre('1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 912004,
     '[{"descricao":"PAINEL FABRICADO","quantidade":1,"unidade":"UN","valor_unitario":1000,"item_id":912003}]'::jsonb));

-- A partir daqui, como a pessoa logada: ativar registra quem ativou.
select set_config('request.jwt.claim.sub', '1e120000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"1e120000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;

-- 1 ---------------------------------------------------------------- recusas ao ativar
do $test$
declare
  v_ov uuid := (select id from excecao_ids where nome = 'ov_pbg');
  procedure_ok boolean;
begin
  begin
    perform f.fn_nfe_excecao_aliquota_ativar(v_ov, '  ', 'e-mail do comprador', null, null, null, 'MANUTENCAO');
    raise exception 'ativou sem OC';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Informe o numero da OC do cliente%' then raise; end if;
  end;
  begin
    perform f.fn_nfe_excecao_aliquota_ativar(v_ov, '4500123456', '   ', null, null, null, 'MANUTENCAO');
    raise exception 'ativou sem evidencia';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Informe a evidencia%' then raise; end if;
  end;
  begin
    perform f.fn_nfe_excecao_aliquota_ativar(v_ov, '4500123456', 'e-mail', null, null, null, 'REVENDA');
    raise exception 'ativou em revenda';
  exception when sqlstate '22023' then
    if sqlerrm not like '%vale so para manutencao, uso e consumo ou ativo imobilizado (destinacao REVENDA).' then raise; end if;
  end;
  begin
    perform f.fn_nfe_excecao_aliquota_ativar((select id from excecao_ids where nome = 'ov_sem_ie'), '4500123456', 'e-mail', null, null, null, 'MANUTENCAO');
    raise exception 'ativou para nao contribuinte';
  exception when sqlstate '22023' then
    if sqlerrm not like '%indisponivel: destinatario nao contribuinte (indIEDest 9).' then raise; end if;
  end;
  begin
    perform f.fn_nfe_excecao_aliquota_ativar((select id from excecao_ids where nome = 'ov_pr'), '4500123456', 'e-mail', null, null, null, 'MANUTENCAO');
    raise exception 'ativou em operacao interestadual';
  exception when sqlstate '22023' then
    if sqlerrm not like '%so vale em operacao interna.' then raise; end if;
  end;
  if exists (select 1 from f.nfe_excecao_aliquota_destinatario) then
    raise exception 'recusa gravou excecao';
  end if;
  if (f.fn_nfe_excecao_aliquota_consultar((select id from excecao_ids where nome = 'ov_sem_ie'))->>'destinatario_contribuinte')::boolean then
    raise exception 'consulta disse que nao contribuinte e contribuinte';
  end if;
end;
$test$;

-- 2 ---------------------------------------------------------------- ativar e reativar
do $test$
declare
  v_ov uuid := (select id from excecao_ids where nome = 'ov_pbg');
  v_consulta jsonb;
  v_primeira uuid;
  v_evidencia jsonb;
begin
  v_consulta := f.fn_nfe_excecao_aliquota_ativar(v_ov, ' 4500000001 ', 'Compras PBG: aplicar 12% conforme OC.', null, null, null, 'MANUTENCAO');
  v_primeira := (v_consulta#>>'{excecao,id}')::uuid;
  if not (v_consulta->>'ativa')::boolean
     or v_consulta#>>'{excecao,numero_oc}' <> '4500000001'
     or v_consulta#>>'{excecao,ativada_por_nome}' <> 'Fiscal Excecao'
     or (v_consulta#>>'{excecao,ativada_por}')::uuid <> '1e120000-0000-4000-8000-000000000011' then
    raise exception 'ativacao nao gravou OC ou usuario: %', v_consulta;
  end if;
  if (select pedido_cliente from f.solicitacao_faturamento where id = v_ov) is distinct from '4500000001' then
    raise exception 'OC nao virou pedido de compra da nota';
  end if;

  -- Reativar com anexo: a anterior fica no historico, desativada.
  v_consulta := f.fn_nfe_excecao_aliquota_ativar(v_ov, '4500123456', null, 'email-compras.eml', 'message/rfc822', encode(convert_to('From: compras@pbg', 'UTF8'), 'base64'), 'MANUTENCAO');
  if v_consulta#>>'{excecao,numero_oc}' <> '4500123456'
     or (v_consulta#>>'{excecao,evidencia_arquivo_tamanho}')::integer <> 17
     or (select count(*) from f.nfe_excecao_aliquota_destinatario where solicitacao_id = v_ov) <> 2
     or (select count(*) from f.nfe_excecao_aliquota_destinatario where solicitacao_id = v_ov and desativada_em is null) <> 1
     or not exists (select 1 from f.nfe_excecao_aliquota_destinatario where id = v_primeira and desativada_em is not null) then
    raise exception 'reativacao nao preservou historico: %', v_consulta;
  end if;
  -- A OC da nota nao e sobrescrita por uma segunda ativacao.
  if (select pedido_cliente from f.solicitacao_faturamento where id = v_ov) is distinct from '4500000001' then
    raise exception 'segunda ativacao sobrescreveu o pedido de compra';
  end if;
  v_evidencia := f.fn_nfe_excecao_aliquota_evidencia((v_consulta#>>'{excecao,id}')::uuid);
  if convert_from(decode(v_evidencia->>'base64', 'base64'), 'UTF8') <> 'From: compras@pbg' or v_evidencia->>'nome' <> 'email-compras.eml' then
    raise exception 'anexo nao voltou igual: %', v_evidencia;
  end if;
end;
$test$;

reset role;

-- 3 ---------------------------------------------------------------- conferencia da OV
create or replace function pg_temp.itens_ov(p_solicitacao uuid, p_aliquota_rev numeric)
returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object(
    'id', si.id,
    'perfil_operacao_id', case when si.item_id = 912002 then '1e120000-0000-4000-8000-000000000302' else '1e120000-0000-4000-8000-000000000301' end,
    'cfop', '5102',
    'cst_icms', case when si.item_id = 912002 then '20' else '00' end,
    'csosn', '',
    'cst_ipi', '53', 'ipi_codigo_enquadramento_legal', '999',
    'cst_pis', '49', 'cst_cofins', '49',
    'reducao_base_icms_percentual', case when si.item_id = 912002 then 29.412 else 0 end,
    'icms_modalidade_base_calculo', '3',
    'aliquota_icms', case when si.item_id = 912002 then 17 else p_aliquota_rev end,
    'cbenef', case when si.item_id = 912002 then 'SC820006' else '' end,
    'cst_ibs_cbs', '000', 'cclass_trib', '000001', 'cclass_trib_versao', 'Informe Técnico 2025.002 v1.60',
    'ibs_cbs_json', '{"ibs_uf_aliquota":0.1,"ibs_mun_aliquota":0,"cbs_aliquota":0.9}'::jsonb
  ) order by si.ordem)
  from f.solicitacao_item si where si.solicitacao_id = p_solicitacao;
$$;

create or replace function pg_temp.operacao_ov(p_consumidor text)
returns jsonb language sql as $$
  select jsonb_build_object('destino_uf_confirmada','SC','finalidade_emissao','1','consumidor_final',p_consumidor,
    'presenca_comprador','9','modalidade_frete','9','valor_frete',0,'valor_seguro',0,'valor_outras_despesas',0,
    'destinacao_mercadoria','MANUTENCAO','pagamento_forma','15','pagamento_indicador',0);
$$;

do $test$
declare
  v_ov uuid := (select id from excecao_ids where nome = 'ov_pbg');
begin
  -- Item comum a 17% com a excecao ativa: recusa.
  begin
    perform f.fn_solicitacao_nfe_salvar_conferencia(v_ov, pg_temp.operacao_ov('1'), pg_temp.itens_ov(v_ov, 17));
    raise exception 'conferencia aceitou item comum a 17%% com a excecao';
  exception when sqlstate '22023' then
    if sqlerrm not like '%sai com CST 00 a 12%% sem reducao e sem cBenef.' then raise; end if;
  end;
  -- indFinal 0 com a excecao: recusa.
  begin
    perform f.fn_solicitacao_nfe_salvar_conferencia(v_ov, pg_temp.operacao_ov('0'), pg_temp.itens_ov(v_ov, 12));
    raise exception 'conferencia aceitou indFinal 0 com a excecao';
  exception when sqlstate '22023' then
    if sqlerrm <> 'A excecao de ICMS 12% por exigencia do destinatario mantem o consumidor final = 1.' then raise; end if;
  end;

  -- 12% CST 00 e indFinal 1 (o perfil diz 0): passa. SC820006 fica CST 20 do perfil.
  perform f.fn_solicitacao_nfe_salvar_conferencia(v_ov, pg_temp.operacao_ov('1'), pg_temp.itens_ov(v_ov, 12));
  if (select consumidor_final from f.solicitacao_faturamento where id = v_ov) <> 1
     or not exists (select 1 from f.solicitacao_item where solicitacao_id = v_ov and item_id = 912001 and cst_icms = '00' and aliquota_icms = 12 and reducao_base_icms_percentual = 0 and cbenef is null)
     or not exists (select 1 from f.solicitacao_item where solicitacao_id = v_ov and item_id = 912002 and cst_icms = '20' and aliquota_icms = 17 and reducao_base_icms_percentual = 29.412 and cbenef = 'SC820006') then
    raise exception 'conferencia da OV nao gravou a excecao como esperado';
  end if;
end;
$test$;

-- 4 ---------------------------------------------------------------- congelamento
do $test$
declare
  v_ov uuid := (select id from excecao_ids where nome = 'ov_pbg');
  v_resultado jsonb;
begin
  v_resultado := f.fn_solicitacao_nfe_congelar_cadastro(v_ov);
  if not (v_resultado->>'ok')::boolean then
    raise exception 'congelamento com pendencias: %', v_resultado;
  end if;
  if (select operacao_snapshot#>>'{excecao_aliquota_destinatario,numero_oc}' from f.solicitacao_faturamento where id = v_ov) is distinct from '4500123456'
     or (select operacao_snapshot->>'consumidor_final' from f.solicitacao_faturamento where id = v_ov) is distinct from '1' then
    raise exception 'snapshot sem a excecao: %', (select operacao_snapshot from f.solicitacao_faturamento where id = v_ov);
  end if;

  -- Desativada: o snapshot cai, a trava do perfil volta a valer para o indFinal.
  perform f.fn_nfe_excecao_aliquota_desativar(v_ov);
  if (select operacao_snapshot from f.solicitacao_faturamento where id = v_ov) is not null then
    raise exception 'desativar nao invalidou o snapshot';
  end if;
  begin
    perform f.fn_solicitacao_nfe_salvar_conferencia(v_ov, pg_temp.operacao_ov('1'), pg_temp.itens_ov(v_ov, 12));
    raise exception 'sem a excecao, aceitou indFinal diferente do perfil';
  exception when sqlstate '22023' then
    if sqlerrm not like 'O consumidor final deve permanecer igual ao perfil%' then raise; end if;
  end;
  perform f.fn_solicitacao_nfe_salvar_conferencia(v_ov, pg_temp.operacao_ov('0'), pg_temp.itens_ov(v_ov, 12));
  perform f.fn_solicitacao_nfe_congelar_cadastro(v_ov);
  if (select operacao_snapshot ? 'excecao_aliquota_destinatario' from f.solicitacao_faturamento where id = v_ov) then
    raise exception 'snapshot sem excecao ativa ainda traz a chave';
  end if;
end;
$test$;

-- 5 ---------------------------------------------------------------- conferencia da OS (FAB)
do $test$
declare
  v_os uuid := (select id from excecao_ids where nome = 'os_fab');
  v_item record;
begin
  perform f.fn_nfe_excecao_aliquota_ativar(v_os, 'OC-FAB-77', 'e-mail do cliente', null, null, null, 'MANUTENCAO');
  perform f.fn_os_nfe_conferir_homologacao(v_os, '{"destino_uf_confirmada":"SC","destinacao_mercadoria":"MANUTENCAO","presenca_comprador":"9","pagamento_forma":"15","pagamento_indicador":"0","modalidade_frete":"9"}'::jsonb);
  select si.* into v_item from f.solicitacao_item si where si.solicitacao_id = v_os;
  if v_item.cfop <> '5101' or v_item.cst_icms <> '00' or v_item.aliquota_icms <> 12
     or v_item.reducao_base_icms_percentual <> 0 or v_item.cbenef is not null
     or v_item.cst_ipi <> '50' or v_item.aliquota_ipi <> 9.75 then
    raise exception 'OS FAB nao saiu CST 00 a 12%% com IPI intacto: cfop %, cst %, aliq %, ipi % %',
      v_item.cfop, v_item.cst_icms, v_item.aliquota_icms, v_item.cst_ipi, v_item.aliquota_ipi;
  end if;
  if (select consumidor_final from f.solicitacao_faturamento where id = v_os) <> 1
     or (select operacao_snapshot#>>'{excecao_aliquota_destinatario,numero_oc}' from f.solicitacao_faturamento where id = v_os) is distinct from 'OC-FAB-77' then
    raise exception 'OS FAB sem indFinal 1 ou sem a excecao no snapshot';
  end if;

  -- Sem a excecao a mesma OS volta aos 17% do perfil de manutencao e indFinal 0.
  perform f.fn_nfe_excecao_aliquota_desativar(v_os);
  perform f.fn_os_nfe_conferir_homologacao(v_os, '{"destino_uf_confirmada":"SC","destinacao_mercadoria":"MANUTENCAO","presenca_comprador":"9","pagamento_forma":"15","pagamento_indicador":"0","modalidade_frete":"9"}'::jsonb);
  if (select aliquota_icms from f.solicitacao_item where solicitacao_id = v_os) <> 17
     or (select consumidor_final from f.solicitacao_faturamento where id = v_os) <> 0 then
    raise exception 'OS sem excecao nao voltou ao perfil';
  end if;
end;
$test$;

-- 6 ---------------------------------------------------------------- relatorio mensal
-- Notas autorizadas de mentira: as travas de producao (perfil liberado, homologacao) nao sao
-- o assunto aqui. Desligadas dentro da transacao, que termina em rollback.
alter table f.documento_fiscal disable trigger aaa_nfe_bloquear_documento_dml_direto;
alter table f.documento_fiscal_emissao disable trigger trg_bloquear_nfe_producao_sem_perfil_liberado;
alter table f.documento_fiscal_emissao disable trigger trg_nfe_bloquear_producao_cancelamento_hom_pendente;
alter table f.documento_fiscal_emissao disable trigger trg_nfe_snapshot_autorizado;
alter table f.documento_fiscal_emissao disable trigger trg_nfe_snapshot_zz_aliquotas;

do $test$
declare
  v_os uuid := (select id from excecao_ids where nome = 'os_fab');
  v_linha record;
  v_total integer;
begin
  perform f.fn_nfe_excecao_aliquota_ativar(v_os, 'OC-FAB-77', 'e-mail do cliente', null, null, null, 'MANUTENCAO');
  perform f.fn_os_nfe_conferir_homologacao(v_os, '{"destino_uf_confirmada":"SC","destinacao_mercadoria":"MANUTENCAO","presenca_comprador":"9","pagamento_forma":"15","pagamento_indicador":"0","modalidade_frete":"9"}'::jsonb);

  update f.solicitacao_faturamento
  set operacao_snapshot = '{"excecao_aliquota_destinatario":{"numero_oc":"OC-OUTUBRO"}}'::jsonb
  where id = (select id from excecao_ids where nome = 'ov_pr');

  insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero)
  values
    ('1e120000-0000-4000-8000-000000000501', '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 'CHAVE-EXC-1', '55', '2', '901'),
    ('1e120000-0000-4000-8000-000000000502', '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 'CHAVE-EXC-2', '55', '2', '902');
  insert into f.documento_fiscal_emissao (documento_fiscal_id, solicitacao_id, tenant_id, empresa_id, referencia_externa, ambiente, status, numero, serie, chave_acesso, autorizado_em, payload_enviado)
  values
    ('1e120000-0000-4000-8000-000000000501', v_os, '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 'NFEP-EXC-1', 'PRODUCAO', 'AUTORIZADA', 901, 2, 'CHAVE-EXC-1',
     '2026-09-16 10:00:00-03',
     '{"items":[{"numero_item":1,"icms_situacao_tributaria":"00","icms_aliquota":12,"icms_base_calculo":1097.5,"icms_valor":131.7},{"numero_item":2,"icms_situacao_tributaria":"20","icms_aliquota":17,"icms_base_calculo":70.59,"icms_valor":12,"codigo_beneficio_fiscal":"SC820006"}]}'::jsonb),
    -- Outra nota com excecao, autorizada em outubro: fora do mes pedido.
    ('1e120000-0000-4000-8000-000000000502', (select id from excecao_ids where nome = 'ov_pr'), '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 'NFEP-EXC-2', 'PRODUCAO', 'AUTORIZADA', 902, 2, 'CHAVE-EXC-2',
     '2026-10-01 00:30:00-03',
     '{"items":[{"numero_item":1,"icms_situacao_tributaria":"00","icms_aliquota":12,"icms_base_calculo":500,"icms_valor":60}]}'::jsonb);

  select count(*) into v_total from f.fn_nfe_excecao_aliquota_relatorio('2026-09-01', 'PRODUCAO');
  select * into v_linha from f.fn_nfe_excecao_aliquota_relatorio('2026-09-20', 'PRODUCAO');
  if v_total <> 1 or v_linha.numero <> 901 or v_linha.numero_oc <> 'OC-FAB-77' or v_linha.destinatario <> 'PBG S/A'
     or v_linha.itens <> '1' or v_linha.valor_base_calculo <> 1097.5 or v_linha.valor_icms <> 131.7
     or v_linha.valor_icms_17 <> 186.58 or v_linha.diferenca_17 <> 54.88 then
    raise exception 'relatorio errado: total %, linha %', v_total, row_to_json(v_linha);
  end if;
  if (select count(*) from f.fn_nfe_excecao_aliquota_relatorio('2026-09-01', 'HOMOLOGACAO')) <> 0 then
    raise exception 'relatorio misturou ambientes';
  end if;
end;
$test$;

-- 7 ---------------------------------------------------------------- xMun (NF-e 2/55)
-- Cidade com o codigo IBGE vira o nome pelo gatilho, e o snapshot leva o nome da tabela IBGE
-- pelo cMun (supabase/migrations/20260916150000_nfe_xmun_nome_do_municipio.sql).
do $test$
declare
  v_ov uuid := (select id from excecao_ids where nome = 'ov_pbg');
begin
  -- O banco local pode estar sem a tabela IBGE carregada: as duas linhas usadas entram aqui.
  insert into public.municipios_ibge (codigo_ibge, nome, nome_normalizado, uf, fonte, fonte_versao, atualizado_em)
  values ('4218004', 'Tijucas', 'tijucas', 'SC', 'teste', 'teste', now()),
         ('4209102', 'Joinville', 'joinville', 'SC', 'teste', 'teste', now())
  on conflict (codigo_ibge) do nothing;
  update public.clientes set cidade = '4218004' where id = 912001;
  if (select cidade from public.clientes where id = 912001) <> 'Tijucas' then
    raise exception 'gatilho nao trocou o codigo pelo nome: %', (select cidade from public.clientes where id = 912001);
  end if;
  insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social, cidade, uf, indicador_ie)
  values (912009, '1e120000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000002', 'CLIENTE NFSE', '44555666000181', 'CLIENTE NFSE', ' 4209102 ', 'SC', '9');
  if (select cidade || '/' || codigo_ibge_municipio from public.clientes where id = 912009) <> 'Joinville/4209102' then
    raise exception 'insert com codigo na cidade: %', (select cidade || '/' || coalesce(codigo_ibge_municipio, '-') from public.clientes where id = 912009);
  end if;

  -- Nome do cadastro diferente do IBGE: o snapshot usa o da tabela pelo cMun.
  update public.clientes set cidade = 'TIJUCAS SC' where id = 912001;
  perform f.fn_solicitacao_nfe_congelar_cadastro(v_ov);
  if (select destinatario_snapshot->>'cidade' from f.solicitacao_faturamento where id = v_ov) is distinct from 'Tijucas'
     or (select emitente_snapshot->>'cidade' from f.solicitacao_faturamento where id = v_ov) is distinct from 'Joinville' then
    raise exception 'snapshot sem o nome do IBGE: dest %, emit %',
      (select destinatario_snapshot->>'cidade' from f.solicitacao_faturamento where id = v_ov),
      (select emitente_snapshot->>'cidade' from f.solicitacao_faturamento where id = v_ov);
  end if;
end;
$test$;

rollback;
