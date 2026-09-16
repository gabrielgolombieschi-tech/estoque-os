\set ON_ERROR_STOP on

-- Remessa para conserto emitida pelo pipeline de NF-e
-- (supabase/migrations/20260916160000_remessa_conserto_nfe.sql).
--
-- Blocos:
--   1  recusas: sem cliente, cliente sem UF, item sem fiscal, perfil sem revisao, modalidade
--      com transporte sem transportadora — e nada gravado
--   2  criacao: operacao + solicitacao + itens com a tributacao do perfil (CST 50/SC840007,
--      IPI 55/108, PIS/COFINS 08, IBS 410/410999), tPag 90, snapshot congelado sem destinacao
--   3  autorizacao em homologacao: a operacao guarda a nota; nada abre no controle de retorno
--   4  autorizacao em producao: chave na operacao, AGUARDANDO_RETORNO, remessa em aberto,
--      e a NF-e EMITIDA nao gera contas a receber
--   5  cancelar: antes da producao cancela operacao e solicitacao; depois, recusa
--
-- Tenant 1e150000-...-0001, empresa ...0002 (SC). Cliente 915001 SICK (SP, contribuinte),
-- 915002 sem UF. Itens 915001 cortina (fiscal completo, origem 2), 915002 sem origem.

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('1e150000-0000-4000-8000-000000000010', 'authenticated', 'authenticated', 'remessa@example.test',
  '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Fiscal Remessa"}'::jsonb, now(), now());
insert into public.tenants (id, nome, ativo) values ('1e150000-0000-4000-8000-000000000001', 'Teste remessa', true);
insert into c.tenant (id, codigo, nome) values ('1e150000-0000-4000-8000-000000000001', 'TESTE-REMESSA', 'Teste remessa');
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj)
values ('1e150000-0000-4000-8000-000000000002', '1e150000-0000-4000-8000-000000000001', 'REMESSA', 'EMPRESA REMESSA LTDA', 'REMESSA', '22222222000191');
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, uf, cidade)
values ('1e150000-0000-4000-8000-000000000002', '1e150000-0000-4000-8000-000000000001', '22222222000191', 'EMPRESA REMESSA LTDA', 'REMESSA', 'SC', 'JOINVILLE')
on conflict (id) do nothing;
insert into c.empresa_fiscal (empresa_id, inscricao_estadual, crt, certificado_validade_em, serie_nfe)
values ('1e150000-0000-4000-8000-000000000002', '257686835', 3, current_date + 365, 2);
insert into c.empresa_endereco (empresa_id, tipo, cep, logradouro, numero, bairro, cidade, uf, codigo_municipio_ibge)
values ('1e150000-0000-4000-8000-000000000002', 'FISCAL', '89219600', 'RUA DONA FRANCISCA', '8300', 'ZONA INDUSTRIAL NORTE', 'JOINVILLE', 'SC', '4209102');
insert into a.usuario (id, auth_user_id, nome, email, ativo)
values ('1e150000-0000-4000-8000-000000000011', '1e150000-0000-4000-8000-000000000010', 'Fiscal Remessa', 'remessa@example.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo)
values ('1e150000-0000-4000-8000-000000000011', '1e150000-0000-4000-8000-000000000001', 'ADMIN', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo)
values ('1e150000-0000-4000-8000-000000000011', '1e150000-0000-4000-8000-000000000002', 'DIRETOR', true);
insert into public.user_tenant_context (user_id, tenant_id)
values ('1e150000-0000-4000-8000-000000000010', '1e150000-0000-4000-8000-000000000001');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
values ('1e150000-0000-4000-8000-000000000010', '1e150000-0000-4000-8000-000000000001', '1e150000-0000-4000-8000-000000000002');
insert into public.municipios_ibge (codigo_ibge, nome, nome_normalizado, uf, fonte, fonte_versao, atualizado_em)
values ('3548708', 'São Bernardo do Campo', 'sao bernardo do campo', 'SP', 'teste', 'teste', now()),
       ('4209102', 'Joinville', 'joinville', 'SC', 'teste', 'teste', now())
on conflict (codigo_ibge) do nothing;

insert into public.clientes (
  id, tenant_id, empresa_id, nome, documento, razao_social, inscricao_estadual,
  cep, logradouro, numero_endereco, complemento, bairro, cidade, uf, pais, indicador_ie, codigo_ibge_municipio
) values
  (915001, '1e150000-0000-4000-8000-000000000001', '1e150000-0000-4000-8000-000000000002',
   'SICK SOLUCAO EM SENSORES LTDA', '00769222000335', 'SICK SOLUCAO EM SENSORES LTDA', '635663118113',
   '09851015', 'AV OSVALDO FREGONEZI', '171', 'GALPAO 53', 'ALVES DIAS', 'SAO BERNARDO DO CAMPO', 'SP', 'BRASIL', '1', '3548708'),
  (915002, '1e150000-0000-4000-8000-000000000001', '1e150000-0000-4000-8000-000000000002',
   'CLIENTE SEM UF', '11222333000181', 'CLIENTE SEM UF', null, null, null, null, null, null, null, null, 'BRASIL', '9', null);

insert into public.itens (id, tenant_id, empresa_id, codigo_interno, nome, tipo, unidade_medida, finalidade, ativo)
values
  (915001, '1e150000-0000-4000-8000-000000000001', '1e150000-0000-4000-8000-000000000002', '1211502', 'CORTINA DE LUZ RECEPTOR C4C-EA12030A10000', 'produto', 'UN', 'materia_prima', true),
  (915002, '1e150000-0000-4000-8000-000000000001', '1e150000-0000-4000-8000-000000000002', 'SEM-ORIGEM', 'ITEM SEM ORIGEM', 'produto', 'UN', 'materia_prima', true);
update public.fiscal_itens fi
set ncm = '85365090', origem = case when fi.item_id = 915001 then 2 end, unidade_tributavel = 'UN', aliq_ipi = 9.75
where fi.tenant_id = '1e150000-0000-4000-8000-000000000001' and fi.item_id in (915001, 915002);

-- Perfil de remessa do tenant de teste: o mesmo desenho do SEG-REMESSA-CONSERTO-6915-O2-CST50,
-- primeiro sem revisao (bloco 1) e depois revisado (blocos 2 em diante).
insert into f.perfil_operacao (
  id, tenant_id, empresa_id, codigo, nome, modelo, natureza_operacao, natureza_texto, crt,
  cfop_externo, cst_icms, aliquota_icms, cbenef, cbenef_aplicacao, beneficio_texto_legal,
  cst_ipi, ipi_codigo_enquadramento_legal, cst_pis, cst_cofins, finalidade_emissao, consumidor_final,
  ambito_destino, ufs_destino, indicador_ie_destinatario, origem_mercadoria, faixa_automacao, justificativa_faixa,
  habilitado_producao, vigencia_inicio
) values (
  '1e150000-0000-4000-8000-000000000301', '1e150000-0000-4000-8000-000000000001', '1e150000-0000-4000-8000-000000000002',
  'TESTE-REMESSA-6915-O2', 'Remessa conserto teste', 'NFE', 'REMESSA_CONSERTO_INTERESTADUAL', 'REMESSA PARA CONSERTO FORA DO ESTADO', '3',
  '6915', '50', 0, 'SC840007', 'COM_BENEFICIO', 'ICMS suspenso (teste)',
  '55', '108', '08', '08', 1, 0,
  'INTERESTADUAL', array['SP','PR']::text[], '1', 2, 'REVISAO', 'teste', false, '2026-09-16'
);

create temporary table remessa_ids (nome text primary key, id uuid not null) on commit drop;
grant all on remessa_ids to authenticated;

select set_config('request.jwt.claim.sub', '1e150000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"1e150000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;

create or replace function pg_temp.operacao_padrao() returns jsonb language sql as $$
  select '{"modalidade_frete":"0","presenca_comprador":"9","observacao":"Garantia SICK",
    "transportador":{"nome":"TRANSLIGUE TRANSP.E SERVICOS LTDA","documento":"03629957000270","inscricao_estadual":"254152732","endereco":"RUA DONA FRANCISCA","municipio":"JOINVILLE","uf":"SC"},
    "volumes":[{"quantidade":"1","especie":"CAIXA","peso_liquido":"3","peso_bruto":"3"}]}'::jsonb;
$$;

-- 1 ---------------------------------------------------------------- recusas
do $test$
declare
  v_itens jsonb := '[{"item_id":915001,"quantidade":1,"valor_unitario":2563.60}]'::jsonb;
begin
  begin
    perform f.fn_remessa_nfe_criar(null, v_itens, pg_temp.operacao_padrao());
    raise exception 'criou sem cliente';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Escolha o destinatario%' then raise; end if;
  end;
  begin
    perform f.fn_remessa_nfe_criar(915002, v_itens, pg_temp.operacao_padrao());
    raise exception 'criou com cliente sem UF';
  exception when sqlstate '22023' then
    if sqlerrm not like '%sem UF no cadastro fiscal%' then raise; end if;
  end;
  begin
    perform f.fn_remessa_nfe_criar(915001, '[{"item_id":915002,"quantidade":1,"valor_unitario":10}]'::jsonb, pg_temp.operacao_padrao());
    raise exception 'criou com item sem origem';
  exception when sqlstate '22023' then
    if sqlerrm not like '%sem origem da mercadoria%' then raise; end if;
  end;
  begin
    perform f.fn_remessa_nfe_criar(915001, v_itens, pg_temp.operacao_padrao());
    raise exception 'criou com perfil sem revisao';
  exception when sqlstate '22023' then
    if sqlerrm not like '%ainda nao foi revisado (IBS/CBS)%' then raise; end if;
  end;
  if exists (select 1 from f.operacao_fiscal where tenant_id = '1e150000-0000-4000-8000-000000000001')
     or exists (select 1 from f.solicitacao_faturamento where tenant_id = '1e150000-0000-4000-8000-000000000001') then
    raise exception 'recusa deixou operacao ou solicitacao gravada';
  end if;
end;
$test$;

-- Revisao IBS/CBS do perfil, pela mesma RPC da tela de perfis.
select f.fn_perfil_operacao_nfe_revisar('1e150000-0000-4000-8000-000000000301', '410', '410999', 'NT 2025.002 - remessas de terceiros 2026', 0, 0, 0, 'Remessa nao e fornecimento oneroso: CST 410 / 410999.');

do $test$
begin
  begin
    perform f.fn_remessa_nfe_criar(915001, '[{"item_id":915001,"quantidade":1,"valor_unitario":2563.60}]'::jsonb,
      pg_temp.operacao_padrao() - 'transportador');
    raise exception 'criou com frete 0 sem transportadora';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Quando houver transporte, informe a transportadora.%' then raise; end if;
  end;
end;
$test$;

-- 2 ---------------------------------------------------------------- criacao
do $test$
declare
  v_res jsonb;
  v_op f.operacao_fiscal%rowtype;
  v_sf f.solicitacao_faturamento%rowtype;
  v_si f.solicitacao_item%rowtype;
begin
  v_res := f.fn_remessa_nfe_criar(915001,
    '[{"item_id":915001,"quantidade":2,"valor_unitario":2563.60}]'::jsonb, pg_temp.operacao_padrao());
  insert into remessa_ids values ('op', (v_res->>'operacao_id')::uuid), ('sol', (v_res->>'solicitacao_id')::uuid);
  if v_res->>'cfop' <> '6915' or v_res->>'natureza_operacao' <> 'REMESSA_CONSERTO_INTERESTADUAL' or (v_res->>'valor_total')::numeric <> 5127.20 then
    raise exception 'retorno errado: %', v_res;
  end if;
  select * into v_op from f.operacao_fiscal where id = (v_res->>'operacao_id')::uuid;
  if v_op.tipo <> 'REMESSA' or v_op.finalidade <> 'CONSERTO' or v_op.status <> 'PRONTO_HOMOLOGACAO' or v_op.ambiente <> 'HOMOLOGACAO'
     or v_op.cfop_confirmado <> '6915' or v_op.destinatario_id <> 915001 or v_op.solicitacao_id <> (v_res->>'solicitacao_id')::uuid
     or v_op.valor_total <> 5127.20 or v_op.dados_json->>'perfil_codigo' <> 'TESTE-REMESSA-6915-O2'
     or v_op.entrega_json->>'documento' <> '00769222000335' then
    raise exception 'operacao errada: %', row_to_json(v_op);
  end if;
  select * into v_sf from f.solicitacao_faturamento where id = v_op.solicitacao_id;
  if v_sf.natureza_operacao <> 'REMESSA_CONSERTO_INTERESTADUAL' or v_sf.cliente_id <> 915001 or v_sf.status <> 'PREVIA'
     or v_sf.finalidade_emissao <> 1 or v_sf.consumidor_final <> 0 or v_sf.presenca_comprador <> 9 or v_sf.modalidade_frete <> 0
     or v_sf.pagamento_forma <> '90' or v_sf.pagamento_indicador <> 0 or v_sf.destinacao_mercadoria is not null
     or v_sf.destino_uf_confirmada <> 'SP' or v_sf.snapshot_cadastro_em is null or v_sf.revisao_fiscal_confirmada_em is null
     or v_sf.transportador_dados->>'nome' <> 'TRANSLIGUE TRANSP.E SERVICOS LTDA' or jsonb_array_length(v_sf.volumes_dados) <> 1
     or v_sf.operacao_snapshot->>'natureza_operacao' <> 'REMESSA_CONSERTO_INTERESTADUAL'
     or v_sf.operacao_snapshot#>>'{pagamento,forma}' <> '90'
     or v_sf.destinatario_snapshot->>'cidade' <> 'São Bernardo do Campo'
     or v_sf.destinatario_snapshot->>'indicador_ie' <> '1' or v_sf.observacao <> 'Garantia SICK' then
    raise exception 'solicitacao errada: %', row_to_json(v_sf);
  end if;
  select * into v_si from f.solicitacao_item where solicitacao_id = v_sf.id;
  if v_si.origem_tipo <> 'AVULSO' or v_si.item_id <> 915001 or v_si.codigo_produto <> '1211502' or v_si.cfop <> '6915'
     or v_si.cst_icms <> '50' or v_si.aliquota_icms is not null or v_si.cbenef <> 'SC840007' or v_si.reducao_base_icms_percentual <> 0
     or v_si.cst_ipi <> '55' or v_si.ipi_codigo_enquadramento_legal <> '108' or v_si.aliquota_ipi is not null
     or v_si.cst_pis <> '08' or v_si.cst_cofins <> '08' or v_si.cst_ibs_cbs <> '410' or v_si.cclass_trib <> '410999'
     or (v_si.ibs_cbs_json->>'cbs_aliquota')::numeric <> 0 or v_si.quantidade <> 2 or v_si.valor_unitario <> 2563.60
     or v_si.ncm <> '85365090' or v_si.origem_mercadoria <> 2 or v_si.unidade_tributavel <> 'UN'
     or v_si.perfil_operacao_id <> '1e150000-0000-4000-8000-000000000301' or v_si.tributacao_fonte <> 'PERFIL' or v_si.modelo <> 'NFE' then
    raise exception 'item errado: %', row_to_json(v_si);
  end if;
  if (select count(*) from f.operacao_fiscal_item where operacao_id = v_op.id and cst_icms = '50' and cbenef = 'SC840007' and cst_ipi = '55') <> 1 then
    raise exception 'item da operacao sem a tributacao';
  end if;
end;
$test$;

reset role;

-- 3 e 4 ------------------------------------------------------------ autorizacoes
-- Notas de mentira: as travas de producao (perfil liberado, claim) nao sao o assunto; ficam
-- desligadas na transacao, que termina em rollback. O gatilho da operacao continua ligado.
alter table f.documento_fiscal disable trigger aaa_nfe_bloquear_documento_dml_direto;
alter table f.documento_fiscal_emissao disable trigger trg_bloquear_nfe_producao_sem_perfil_liberado;
alter table f.documento_fiscal_emissao disable trigger trg_nfe_bloquear_producao_cancelamento_hom_pendente;
alter table f.documento_fiscal_emissao disable trigger trg_nfe_snapshot_autorizado;
alter table f.documento_fiscal_emissao disable trigger trg_nfe_snapshot_zz_aliquotas;

do $test$
declare
  v_op uuid := (select id from remessa_ids where nome = 'op');
  v_sol uuid := (select id from remessa_ids where nome = 'sol');
  v_chave_hom text := '42260913671448000189550020000000601000000001';
  v_chave_prod text := '42260913671448000189550020000000611000000002';
begin
  insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, operacao, natureza, cliente_id, nfe_status, origem, valor_total)
  values
    ('1e150000-0000-4000-8000-000000000501', '1e150000-0000-4000-8000-000000000001', '1e150000-0000-4000-8000-000000000002', 'PENDENTE:H', '55', '2', '60', 'SAIDA', 'PRODUTO', 915001, 'RASCUNHO', 'EMITIDO', 5127.20),
    ('1e150000-0000-4000-8000-000000000502', '1e150000-0000-4000-8000-000000000001', '1e150000-0000-4000-8000-000000000002', 'PENDENTE:P', '55', '2', '61', 'SAIDA', 'PRODUTO', 915001, 'RASCUNHO', 'EMITIDO', 5127.20);
  insert into f.documento_fiscal_emissao (documento_fiscal_id, solicitacao_id, tenant_id, empresa_id, referencia_externa, ambiente, status)
  values
    ('1e150000-0000-4000-8000-000000000501', v_sol, '1e150000-0000-4000-8000-000000000001', '1e150000-0000-4000-8000-000000000002', 'NFEH-REM-1', 'HOMOLOGACAO', 'RASCUNHO'),
    ('1e150000-0000-4000-8000-000000000502', v_sol, '1e150000-0000-4000-8000-000000000001', '1e150000-0000-4000-8000-000000000002', 'NFEP-REM-1', 'PRODUCAO', 'RASCUNHO');

  -- 3: homologacao autorizada
  update f.documento_fiscal_emissao set status = 'AUTORIZADA', chave_acesso = v_chave_hom, numero = 60, serie = 2, autorizado_em = now()
  where documento_fiscal_id = '1e150000-0000-4000-8000-000000000501';
  if (select dados_json#>>'{homologacao,chave}' from f.operacao_fiscal where id = v_op) is distinct from v_chave_hom
     or (select status from f.operacao_fiscal where id = v_op) <> 'PRONTO_HOMOLOGACAO'
     or exists (select 1 from f.remessa_controle where operacao_remessa_id = v_op) then
    raise exception 'homologacao nao ficou registrada na operacao (ou abriu controle indevido)';
  end if;

  -- 4: producao autorizada abre o controle de retorno
  update f.documento_fiscal_emissao set status = 'AUTORIZADA', chave_acesso = v_chave_prod, numero = 61, serie = 2, autorizado_em = now()
  where documento_fiscal_id = '1e150000-0000-4000-8000-000000000502';
  if (select chave_primeira_nota from f.operacao_fiscal where id = v_op) is distinct from v_chave_prod
     or (select status from f.operacao_fiscal where id = v_op) <> 'AGUARDANDO_RETORNO'
     or (select ambiente from f.operacao_fiscal where id = v_op) <> 'PRODUCAO'
     or (select documento_primeira_nota_id from f.operacao_fiscal where id = v_op) <> '1e150000-0000-4000-8000-000000000502' then
    raise exception 'producao nao ficou registrada na operacao: %', (select row_to_json(o) from f.operacao_fiscal o where o.id = v_op);
  end if;
  if not exists (
    select 1 from f.v_remessas_abertas r
    where r.operacao_remessa_id = v_op and r.chave_remessa = v_chave_prod and r.finalidade = 'CONSERTO'
      and r.destinatario_nome = 'SICK SOLUCAO EM SENSORES LTDA' and r.destinatario_documento = '00769222000335'
  ) then
    raise exception 'remessa nao apareceu em aberto';
  end if;

  -- NF-e de producao EMITIDA: sem contas a receber para remessa.
  update f.documento_fiscal set nfe_status = 'EMITIDA', chave_acesso = v_chave_prod where id = '1e150000-0000-4000-8000-000000000502';
  if exists (select 1 from f.titulo t where t.documento_fiscal_id = '1e150000-0000-4000-8000-000000000502') then
    raise exception 'remessa gerou contas a receber';
  end if;
end;
$test$;

-- 5 ---------------------------------------------------------------- cancelar
select set_config('request.jwt.claim.sub', '1e150000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"1e150000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;

do $test$
declare
  v_op uuid := (select id from remessa_ids where nome = 'op');
  v_res jsonb;
  v_nova uuid;
begin
  begin
    perform f.fn_remessa_nfe_cancelar(v_op, 'Cancelamento indevido depois da producao');
    raise exception 'cancelou remessa com producao';
  exception when sqlstate '55000' then
    if sqlerrm not like 'Remessa com NF-e de producao%' then raise; end if;
  end;
  v_res := f.fn_remessa_nfe_criar(915001, '[{"item_id":915001,"quantidade":1,"valor_unitario":100}]'::jsonb, pg_temp.operacao_padrao());
  v_nova := (v_res->>'operacao_id')::uuid;
  begin
    perform f.fn_remessa_nfe_cancelar(v_nova, 'curto');
    raise exception 'cancelou sem motivo';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Informe o motivo%' then raise; end if;
  end;
  perform f.fn_remessa_nfe_cancelar(v_nova, 'Remessa criada por engano no teste');
  if (select status from f.operacao_fiscal where id = v_nova) <> 'CANCELADA'
     or (select status from f.solicitacao_faturamento where id = (v_res->>'solicitacao_id')::uuid) <> 'CANCELADA' then
    raise exception 'cancelamento nao aplicado';
  end if;
end;
$test$;

reset role;
rollback;
