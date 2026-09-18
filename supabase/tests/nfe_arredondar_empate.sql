\set ON_ERROR_STOP on

-- Ajuste de meio centavo por item (supabase/migrations/20260918270000_nfe_arredondar_empate_meio_centavo.sql).
--
-- Blocos:
--   1  f.fn_nfe_empate_meio_centavo: 405,405 e 0,005 sao empate; 405,4051, 405,41 e 498,96 nao
--   2  ativar: recusa sem motivo, com motivo curto, tributo ICMS e item sem IPI — nada gravado
--   3  ativar em empate (4.158,00 x 9,75% = 405,405): grava tributo, motivo, quem e quando;
--      desativar limpa tudo
--   4  fora do empate (4.158,01): o banco recusa e a linha continua sem ajuste
--   5  snapshots existentes: as outras linhas seguem false; a check constraint recusa
--      marca sem motivo
--
-- Tenant 1e130000-...-0001, empresa ...0002 (SC), usuario fiscal 1e130000-...-0010/11.

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('1e130000-0000-4000-8000-000000000010', 'authenticated', 'authenticated', 'empate@example.test',
  '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Fiscal Empate"}'::jsonb, now(), now());

insert into public.tenants (id, nome, ativo) values ('1e130000-0000-4000-8000-000000000001', 'Teste empate', true);
insert into c.tenant (id, codigo, nome) values ('1e130000-0000-4000-8000-000000000001', 'TESTE-EMPATE', 'Teste empate');
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj)
values ('1e130000-0000-4000-8000-000000000002', '1e130000-0000-4000-8000-000000000001', 'EMPATE', 'EMPRESA EMPATE LTDA', 'EMPATE', '33333333000191');
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, uf, cidade)
values ('1e130000-0000-4000-8000-000000000002', '1e130000-0000-4000-8000-000000000001', '33333333000191', 'EMPRESA EMPATE LTDA', 'EMPATE', 'SC', 'JOINVILLE')
on conflict (id) do nothing;
insert into c.empresa_fiscal (empresa_id, inscricao_estadual, crt, certificado_validade_em, serie_nfe)
values ('1e130000-0000-4000-8000-000000000002', '257686835', 3, current_date + 365, 2);
insert into c.empresa_endereco (empresa_id, tipo, cep, logradouro, numero, bairro, cidade, uf, codigo_municipio_ibge)
values ('1e130000-0000-4000-8000-000000000002', 'FISCAL', '89219600', 'RUA DONA FRANCISCA', '8300', 'ZONA INDUSTRIAL NORTE', 'JOINVILLE', 'SC', '4209102');

insert into a.usuario (id, auth_user_id, nome, email, ativo)
values ('1e130000-0000-4000-8000-000000000011', '1e130000-0000-4000-8000-000000000010', 'Fiscal Empate', 'empate@example.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo)
values ('1e130000-0000-4000-8000-000000000011', '1e130000-0000-4000-8000-000000000001', 'ADMIN', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo)
values ('1e130000-0000-4000-8000-000000000011', '1e130000-0000-4000-8000-000000000002', 'DIRETOR', true);
insert into public.user_tenant_context (user_id, tenant_id)
values ('1e130000-0000-4000-8000-000000000010', '1e130000-0000-4000-8000-000000000001');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
values ('1e130000-0000-4000-8000-000000000010', '1e130000-0000-4000-8000-000000000001', '1e130000-0000-4000-8000-000000000002');

insert into public.clientes (
  id, tenant_id, empresa_id, nome, documento, razao_social, inscricao_estadual,
  cep, logradouro, numero_endereco, bairro, cidade, uf, pais, indicador_ie, codigo_ibge_municipio
) values
  (913001, '1e130000-0000-4000-8000-000000000001', '1e130000-0000-4000-8000-000000000002',
   'PBG S/A', '83475913000191', 'PBG S/A', '250355050', '88840000', 'RUA MANOEL DOS SANTOS', '1', 'CENTRO', 'TIJUCAS', 'SC', 'BRASIL', '1', '4218004');

insert into public.itens (id, tenant_id, empresa_id, codigo_interno, nome, tipo, unidade_medida, finalidade, ativo)
values
  (913001, '1e130000-0000-4000-8000-000000000001', '1e130000-0000-4000-8000-000000000002', 'CQM1HCPU61', 'CONTROLADOR PROGRAMAVEL PLC CPU', 'produto', 'UN', 'revenda', true),
  (913002, '1e130000-0000-4000-8000-000000000001', '1e130000-0000-4000-8000-000000000002', 'REV-2', 'ITEM SEM IPI', 'produto', 'UN', 'revenda', true);

insert into public.ordens_servico (
  id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id, empresa_id,
  status_fluxo, tipo_documento, codigo, numero_doc, descricao_servico, orcado
) values
  (913001, 'OV-EMP-1', 'PBG S/A', 913001, 'em_andamento', 913001, '1e130000-0000-4000-8000-000000000001', '1e130000-0000-4000-8000-000000000002', 'em_andamento', 'OV', 'OV-EMP-001', 1, 'VENDA INSUMO', 4258.00);

insert into public.os_itens (id, os_id, item_id, quantidade, valor_unitario, valor_total, tenant_id, empresa_id, finalidade)
values
  (913001, 913001, 913001, 1, 4158, 4158, '1e130000-0000-4000-8000-000000000001', '1e130000-0000-4000-8000-000000000002', 'venda'),
  (913002, 913001, 913002, 1, 100, 100, '1e130000-0000-4000-8000-000000000001', '1e130000-0000-4000-8000-000000000002', 'venda');

create temporary table empate_ids (nome text primary key, id uuid not null) on commit drop;
grant all on empate_ids to authenticated;

insert into empate_ids values
  ('sol', f.fn_solicitacao_faturamento_criar_parcial('1e130000-0000-4000-8000-000000000001', '1e130000-0000-4000-8000-000000000002', 913001,
     '[{"os_item_id":913001,"quantidade":1,"valor_unitario":4158},{"os_item_id":913002,"quantidade":1,"valor_unitario":100}]'::jsonb));

-- A conferencia e quem grava CST e aliquota do IPI; aqui vao direto, como postgres.
update f.solicitacao_item si set cst_ipi = '50', aliquota_ipi = 9.75
where si.solicitacao_id = (select id from empate_ids where nome = 'sol') and si.item_id = 913001;
update f.solicitacao_item si set cst_ipi = '53', aliquota_ipi = null
where si.solicitacao_id = (select id from empate_ids where nome = 'sol') and si.item_id = 913002;
insert into empate_ids
select 'item_ipi', si.id from f.solicitacao_item si where si.solicitacao_id = (select id from empate_ids where nome = 'sol') and si.item_id = 913001;
insert into empate_ids
select 'item_sem_ipi', si.id from f.solicitacao_item si where si.solicitacao_id = (select id from empate_ids where nome = 'sol') and si.item_id = 913002;

-- 1. Funcao de empate ------------------------------------------------------------------------
do $b1$
begin
  if not f.fn_nfe_empate_meio_centavo(405.405) then raise exception '405,405 e empate'; end if;
  if not f.fn_nfe_empate_meio_centavo(0.005) then raise exception '0,005 e empate'; end if;
  if f.fn_nfe_empate_meio_centavo(405.4051) then raise exception '405,4051 nao e empate'; end if;
  if f.fn_nfe_empate_meio_centavo(405.41) then raise exception '405,41 nao e empate'; end if;
  if f.fn_nfe_empate_meio_centavo(498.96) then raise exception '498,96 nao e empate'; end if;
end;
$b1$;

-- A partir daqui, como a pessoa logada: ativar registra quem confirmou.
select set_config('request.jwt.claim.sub', '1e130000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claims', '{"sub":"1e130000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;

-- 2. Recusas sem gravar -------------------------------------------------------------------------
do $b2$
declare
  v_item uuid := (select id from empate_ids where nome = 'item_ipi');
  v_sem_ipi uuid := (select id from empate_ids where nome = 'item_sem_ipi');
  v_msg text;
begin
  begin
    perform f.fn_solicitacao_item_arredondar_empate(v_item, 'IPI', true, null);
    raise exception 'ativou sem motivo';
  exception when invalid_parameter_value then
    get stacked diagnostics v_msg = message_text;
    if v_msg not like '%motivo%' then raise exception 'mensagem sem motivo: %', v_msg; end if;
  end;
  begin
    perform f.fn_solicitacao_item_arredondar_empate(v_item, 'IPI', true, 'curto');
    raise exception 'ativou com motivo curto';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform f.fn_solicitacao_item_arredondar_empate(v_item, 'ICMS', true, 'fechar com OC 1309011, total 4.563,40');
    raise exception 'ativou para ICMS';
  exception when invalid_parameter_value then
    get stacked diagnostics v_msg = message_text;
    if v_msg not like '%so vale para o IPI%' then raise exception 'mensagem ICMS: %', v_msg; end if;
  end;
  begin
    perform f.fn_solicitacao_item_arredondar_empate(v_sem_ipi, 'IPI', true, 'fechar com OC 1309011, total 4.563,40');
    raise exception 'ativou em item sem IPI';
  exception when invalid_parameter_value then
    get stacked diagnostics v_msg = message_text;
    if v_msg not like '%nao destaca IPI%' then raise exception 'mensagem sem IPI: %', v_msg; end if;
  end;
  if exists (select 1 from f.solicitacao_item where solicitacao_id = (select id from empate_ids where nome = 'sol') and arredondar_empate_para_baixo) then
    raise exception 'recusa gravou marca';
  end if;
end;
$b2$;

-- 3. Empate: grava; desativar limpa ---------------------------------------------------------------
do $b3$
declare
  v_item uuid := (select id from empate_ids where nome = 'item_ipi');
  v_ret jsonb;
  v_si f.solicitacao_item%rowtype;
begin
  v_ret := f.fn_solicitacao_item_arredondar_empate(v_item, 'ipi', true, '  fechar com OC 1309011, total 4.563,40  ');
  if (v_ret->>'ativo')::boolean is not true
     or (v_ret->>'valor_exato')::numeric <> 405.405
     or (v_ret->>'valor_padrao')::numeric <> 405.41
     or (v_ret->>'valor_para_baixo')::numeric <> 405.40 then
    raise exception 'retorno da ativacao errado: %', v_ret;
  end if;
  select * into v_si from f.solicitacao_item where id = v_item;
  if not v_si.arredondar_empate_para_baixo or v_si.arredondar_empate_tributo <> 'IPI'
     or v_si.arredondar_empate_motivo <> 'fechar com OC 1309011, total 4.563,40'
     or v_si.arredondar_empate_por <> '1e130000-0000-4000-8000-000000000011'
     or v_si.arredondar_empate_em is null then
    raise exception 'marca gravada errada: % % % % %', v_si.arredondar_empate_para_baixo, v_si.arredondar_empate_tributo, v_si.arredondar_empate_motivo, v_si.arredondar_empate_por, v_si.arredondar_empate_em;
  end if;
  -- Reativar troca o motivo; desativar limpa tudo.
  perform f.fn_solicitacao_item_arredondar_empate(v_item, 'IPI', true, 'motivo novo para a mesma linha');
  select * into v_si from f.solicitacao_item where id = v_item;
  if v_si.arredondar_empate_motivo <> 'motivo novo para a mesma linha' then raise exception 'reativar nao trocou o motivo'; end if;
  v_ret := f.fn_solicitacao_item_arredondar_empate(v_item, 'IPI', false, null);
  select * into v_si from f.solicitacao_item where id = v_item;
  if v_si.arredondar_empate_para_baixo or v_si.arredondar_empate_tributo is not null or v_si.arredondar_empate_motivo is not null
     or v_si.arredondar_empate_por is not null or v_si.arredondar_empate_em is not null then
    raise exception 'desativar nao limpou a marca';
  end if;
end;
$b3$;

-- 3b. Conferencia da OV ainda nao gravada: CST/aliquota vem da tela e entram na linha (20260919020000)
reset role;
update f.solicitacao_item set cst_ipi = null, aliquota_ipi = null where id = (select id from empate_ids where nome = 'item_ipi');
select set_config('request.jwt.claim.sub', '1e130000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claims', '{"sub":"1e130000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;
do $b3b$
declare
  v_item uuid := (select id from empate_ids where nome = 'item_ipi');
  v_si f.solicitacao_item%rowtype;
begin
  begin
    perform f.fn_solicitacao_item_arredondar_empate(v_item, 'IPI', true, 'fechar com OC 1309011, total 4.563,40');
    raise exception 'ativou sem IPI gravado e sem os valores da conferencia';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform f.fn_solicitacao_item_arredondar_empate(v_item, 'IPI', true, 'fechar com OC 1309011, total 4.563,40', '50', null);
    raise exception 'aceitou CST sem aliquota';
  exception when invalid_parameter_value then null;
  end;
  perform f.fn_solicitacao_item_arredondar_empate(v_item, 'IPI', true, 'fechar com OC 1309011, total 4.563,40', '50', 9.75);
  select * into v_si from f.solicitacao_item where id = v_item;
  if not v_si.arredondar_empate_para_baixo or v_si.cst_ipi <> '50' or v_si.aliquota_ipi <> 9.75 then
    raise exception 'valores da conferencia nao entraram na linha: % % %', v_si.arredondar_empate_para_baixo, v_si.cst_ipi, v_si.aliquota_ipi;
  end if;
  perform f.fn_solicitacao_item_arredondar_empate(v_item, 'IPI', false);
end;
$b3b$;

-- 4. Fora do empate: o banco recusa ---------------------------------------------------------------
reset role;
update f.solicitacao_item set valor_unitario = 4158.01 where id = (select id from empate_ids where nome = 'item_ipi');
select set_config('request.jwt.claim.sub', '1e130000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claims', '{"sub":"1e130000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;
do $b4$
declare
  v_item uuid := (select id from empate_ids where nome = 'item_ipi');
  v_msg text;
begin
  begin
    perform f.fn_solicitacao_item_arredondar_empate(v_item, 'IPI', true, 'fechar com OC 1309011, total 4.563,40');
    raise exception 'ativou fora do empate (405,406)';
  exception when invalid_parameter_value then
    get stacked diagnostics v_msg = message_text;
    if v_msg not like '%nao cai em empate de meio centavo (valor exato 405,4060)%' then raise exception 'mensagem fora do empate: %', v_msg; end if;
  end;
  if (select arredondar_empate_para_baixo from f.solicitacao_item where id = v_item) then raise exception 'recusa gravou marca'; end if;
end;
$b4$;

-- 5. Snapshots existentes e a check constraint ----------------------------------------------------
reset role;
do $b5$
declare
  v_sem_ipi uuid := (select id from empate_ids where nome = 'item_sem_ipi');
begin
  if exists (select 1 from f.solicitacao_item where arredondar_empate_para_baixo) then
    raise exception 'alguma linha ficou com o ajuste ligado';
  end if;
  begin
    update f.solicitacao_item set arredondar_empate_para_baixo = true where id = v_sem_ipi;
    raise exception 'check constraint aceitou marca sem tributo/motivo/data';
  exception when check_violation then null;
  end;
end;
$b5$;

rollback;
