\set ON_ERROR_STOP on

-- Painel de TV por colaborador: quem abre, o que a conta da televisao NAO enxerga
-- por fora das funcoes, filtro de area, semana/jornada, tarefas por participante,
-- horas sem hora recusada e ausencia que desconta da semana.
--
-- Cobre as quatro migrations que formam a tela:
--   20260912160000  fn_tv_contexto, fn_tv_area, tv_periodos, tv_colaboradores,
--                   tv_colaboradores_tarefas, tv_horas_periodo, colaboradores.area
--   20260912190000  jornada_padrao e horas_previstas / horas_previstas_ate_hoje
--   20260912220000  tarefas_participantes (tarefas.colaborador_id nao existe mais)
--                   e tv_ausencias_periodo
--   20260913100000  a terceira area, engenharia, na coluna e em fn_tv_area
--
-- Contas do fixture (tenant 1c00...0010, empresa A 1c00...0020, empresa B 1c00...0021):
--   ...0001  tv@tvtest.test           PAINEL_TV     -> a televisao
--   ...0002  tecnico@tvtest.test      TECNICO       -> nao abre o painel
--   ...0003  diretor@tvtest.test      DIRETOR       -> gestao, abre para conferir
--   ...0004  almoxarifado@tvtest.test ALMOXARIFADO  -> nao abre o painel
--   ...0005  coordenacao@tvtest.test  COORDENACAO   -> gestao, abre
--   ...0006  admin@tvtest.test        ADMIN         -> gestao, abre
--
-- Colaboradores da empresa A: MECANICO MARCOS (mecanica, horas e tarefas),
--   ELETRICO ELIAS (eletrica), SEM AREA SONIA (area nula), MECANICA MARIA
--   (mecanica, sem hora e sem tarefa: o cartao vazio), MECANICO MURILO (mecanica,
--   so o terceiro participante da tarefa de hoje), ENGENHEIRA ENEIDA (engenharia,
--   com hora, tarefa e ausencia) e INATIVO IVO (mecanica, inativo).
--   Empresa B: OUTRA EMPRESA OSVALDO (mecanica) -- nada dele pode vazar para a TV.
--
-- O teste nao escolhe data fixa nem depende do dia da semana em que roda: as
-- semanas usadas nas contas de jornada saem de public.feriados, lido do banco.

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('1c000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'tv@tvtest.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"TV"}'::jsonb, now(), now()),
  ('1c000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'tecnico@tvtest.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Tecnico"}'::jsonb, now(), now()),
  ('1c000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'diretor@tvtest.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Diretor"}'::jsonb, now(), now()),
  ('1c000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'almoxarifado@tvtest.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Almoxarifado"}'::jsonb, now(), now()),
  ('1c000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'coordenacao@tvtest.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Coordenacao"}'::jsonb, now(), now()),
  ('1c000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'admin@tvtest.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Admin"}'::jsonb, now(), now());

insert into public.tenants (id, nome, ativo) values ('1c000000-0000-4000-8000-000000000010', 'Tenant TV', true);
insert into c.tenant (id, codigo, nome, ativo) values ('1c000000-0000-4000-8000-000000000010', 'TVTEST', 'Tenant TV', true);
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo) values
  ('1c000000-0000-4000-8000-000000000020', '1c000000-0000-4000-8000-000000000010', 'TV-A', 'Empresa TV A', 'Empresa TV A', '31000000000100', true),
  ('1c000000-0000-4000-8000-000000000021', '1c000000-0000-4000-8000-000000000010', 'TV-B', 'Empresa TV B', 'Empresa TV B', '31000000000200', true);
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo) values
  ('1c000000-0000-4000-8000-000000000020', '1c000000-0000-4000-8000-000000000010', '31000000000100', 'Empresa TV A', 'Empresa TV A', true),
  ('1c000000-0000-4000-8000-000000000021', '1c000000-0000-4000-8000-000000000010', '31000000000200', 'Empresa TV B', 'Empresa TV B', true);

insert into a.usuario (id, auth_user_id, nome, email, ativo) values
  ('1c000000-0000-4000-8000-000000000041', '1c000000-0000-4000-8000-000000000001', 'Televisao da producao', 'tv@tvtest.test', true),
  ('1c000000-0000-4000-8000-000000000042', '1c000000-0000-4000-8000-000000000002', 'Tecnico', 'tecnico@tvtest.test', true),
  ('1c000000-0000-4000-8000-000000000043', '1c000000-0000-4000-8000-000000000003', 'Diretor', 'diretor@tvtest.test', true),
  ('1c000000-0000-4000-8000-000000000044', '1c000000-0000-4000-8000-000000000004', 'Almoxarifado', 'almoxarifado@tvtest.test', true),
  ('1c000000-0000-4000-8000-000000000045', '1c000000-0000-4000-8000-000000000005', 'Coordenacao', 'coordenacao@tvtest.test', true),
  ('1c000000-0000-4000-8000-000000000046', '1c000000-0000-4000-8000-000000000006', 'Admin', 'admin@tvtest.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo) values
  ('1c000000-0000-4000-8000-000000000041', '1c000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('1c000000-0000-4000-8000-000000000042', '1c000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('1c000000-0000-4000-8000-000000000043', '1c000000-0000-4000-8000-000000000010', 'ADMIN', true),
  ('1c000000-0000-4000-8000-000000000044', '1c000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('1c000000-0000-4000-8000-000000000045', '1c000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('1c000000-0000-4000-8000-000000000046', '1c000000-0000-4000-8000-000000000010', 'ADMIN', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo) values
  ('1c000000-0000-4000-8000-000000000041', '1c000000-0000-4000-8000-000000000020', 'PAINEL_TV', true),
  ('1c000000-0000-4000-8000-000000000042', '1c000000-0000-4000-8000-000000000020', 'TECNICO', true),
  ('1c000000-0000-4000-8000-000000000043', '1c000000-0000-4000-8000-000000000020', 'DIRETOR', true),
  ('1c000000-0000-4000-8000-000000000044', '1c000000-0000-4000-8000-000000000020', 'ALMOXARIFADO', true),
  ('1c000000-0000-4000-8000-000000000045', '1c000000-0000-4000-8000-000000000020', 'COORDENACAO', true),
  ('1c000000-0000-4000-8000-000000000046', '1c000000-0000-4000-8000-000000000020', 'ADMIN', true);
insert into public.user_tenant_context (user_id, tenant_id)
select ('1c000000-0000-4000-8000-00000000000' || n)::uuid, '1c000000-0000-4000-8000-000000000010' from generate_series(1, 6) as n;
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
select ('1c000000-0000-4000-8000-00000000000' || n)::uuid, '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020' from generate_series(1, 6) as n;

insert into public.colaboradores (id, nome, cargo, ativo, area, tenant_id, empresa_id, user_id) values
  ('1c000000-0000-4000-8000-000000000101', 'MECANICO MARCOS', 'MECANICO', true, 'mecanica', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', null),
  ('1c000000-0000-4000-8000-000000000102', 'ELETRICO ELIAS', 'ELETRICISTA', true, 'eletrica', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', null),
  ('1c000000-0000-4000-8000-000000000103', 'SEM AREA SONIA', 'AJUDANTE', true, null, '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', null),
  ('1c000000-0000-4000-8000-000000000104', 'INATIVO IVO', 'MECANICO', false, 'mecanica', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', null),
  ('1c000000-0000-4000-8000-000000000105', 'MECANICA MARIA', 'MECANICO', true, 'mecanica', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', null),
  ('1c000000-0000-4000-8000-000000000106', 'MECANICO MURILO', 'MECANICO', true, 'mecanica', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', null),
  -- O cargo da ENEIDA tem "MEC" de proposito: e o caso que fez nascer a engenharia
  -- na 20260913100000. Quem decide a area e o campo Area do cadastro, nao o cargo.
  ('1c000000-0000-4000-8000-000000000108', 'ENGENHEIRA ENEIDA', 'PROJETISTA MEC', true, 'engenharia', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', null),
  ('1c000000-0000-4000-8000-000000000107', 'OUTRA EMPRESA OSVALDO', 'MECANICO', true, 'mecanica', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000021', null);
insert into public.colaborador_taxas (colaborador_id, valor_hora, vigencia_inicio, tenant_id, empresa_id)
select c.id, 70, '2020-01-01', c.tenant_id, c.empresa_id from public.colaboradores c where c.tenant_id = '1c000000-0000-4000-8000-000000000010';

-- A jornada da fabrica: segunda a quinta 9h, sexta 8h, fim de semana zero = 44h.
-- A Parte 6 da migration 20260912220000 deu um gatilho a public.empresas, entao a
-- empresa do fixture ja nasce com a jornada. O insert abaixo continua aqui de
-- proposito: ele garante o valor que este teste espera mesmo que o padrao da
-- fabrica mude um dia, e o "on conflict" e o que aceita o gatilho ter chegado
-- primeiro.
insert into public.jornada_padrao (tenant_id, empresa_id, dow, horas)
select empresa.tenant_id, empresa.id, d.dow,
       case d.dow when 5 then 8 when 6 then 0 when 7 then 0 else 9 end
from public.empresas as empresa
cross join (select generate_series(1, 7) as dow) as d
where empresa.tenant_id = '1c000000-0000-4000-8000-000000000010'
on conflict (tenant_id, empresa_id, dow) do update set horas = excluded.horas;

insert into public.tipos_horas (id, codigo, descricao, fator, ativo, tenant_id) values
  ('1c000000-0000-4000-8000-000000000301', 'NORMAL', 'Hora normal', 1, true, '1c000000-0000-4000-8000-000000000010');

insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social) values
  (939001, '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', 'CLIENTE TV', '31111111000191', 'CLIENTE TV LTDA'),
  (939002, '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000021', 'CLIENTE TV B', '31111111000192', 'CLIENTE TV B LTDA');

insert into public.ordens_servico (id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id, empresa_id,
  status_fluxo, tipo_documento, codigo, numero_doc, descricao_servico, orcado, responsavel_aprovacao_id, usa_relatorio_hh)
values
  (939001, 'TV-1', 'CLIENTE TV', 939001, 'em_andamento', 939001, '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-TV-001', 1, 'Troca de rolamentos', 100, null, false),
  (939002, 'TV-2', 'CLIENTE TV', 939001, 'em_andamento', 939002, '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-TV-002', 2, 'Painel de comando', 100, null, false),
  (939003, 'TV-B', 'CLIENTE TV B', 939002, 'em_andamento', 939003, '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000021', 'em_andamento', 'OS', 'OS-TV-003', 3, 'OS da empresa B', 100, null, false);

-- Semanas escolhidas a partir do calendario que esta no banco, para o teste nao
-- depender do dia em que roda nem dos feriados ja cadastrados:
--   semana_passada  segunda de uma semana sem feriado, inteira no passado
--   semana_limpa    segunda de uma semana sem feriado, no futuro (a conta de 44h)
--   semana_feriado  segunda de outra semana sem feriado, onde o teste planta um
create temp table datas (nome text primary key, d date not null);
grant select on datas to authenticated;

with segundas as (
  select (date_trunc('week', public.fn_tablet_data_hoje()::timestamp)::date + (7 * n))::date as seg
  from generate_series(-60, 60) as n
),
limpas as (
  select s.seg
  from segundas as s
  where not exists (select 1 from public.feriados as f where f.data between s.seg and s.seg + 6)
),
futuras as (
  select seg, row_number() over (order by seg) as rn
  from limpas
  where seg > public.fn_tablet_data_hoje()
)
insert into datas (nome, d)
select 'semana_passada', max(seg) from limpas where seg + 6 < public.fn_tablet_data_hoje() having count(*) > 0
union all
select 'semana_limpa', seg from futuras where rn = 1
union all
select 'semana_feriado', seg from futuras where rn = 2;

do $semanas$
declare
  v_passada date := (select d from datas where nome = 'semana_passada');
  v_limpa date := (select d from datas where nome = 'semana_limpa');
  v_feriado date := (select d from datas where nome = 'semana_feriado');
begin
  if v_passada is null or v_limpa is null or v_feriado is null then
    raise exception 'nao achei tres semanas sem feriado no calendario do banco: %, %, %', v_passada, v_limpa, v_feriado;
  end if;
  if v_limpa = v_feriado or v_limpa = v_passada or v_feriado = v_passada then
    raise exception 'as tres semanas do teste tem de ser diferentes: %, %, %', v_passada, v_limpa, v_feriado;
  end if;
  if extract(isodow from v_passada) <> 1 or extract(isodow from v_limpa) <> 1 or extract(isodow from v_feriado) <> 1 then
    raise exception 'as semanas do teste tem de comecar na segunda: %, %, %', v_passada, v_limpa, v_feriado;
  end if;
end $semanas$;

-- O feriado plantado vai na tabela que o banco usa para decidir dia util, a mesma
-- que classifica a hora extra do colaborador: public.feriados.
insert into public.feriados (data, descricao, abrangencia)
select d, 'Feriado plantado pelo teste do painel', 'MUNICIPAL' from datas where nome = 'semana_feriado';

-- Horas de hoje: MARCOS tem 4h + 2h aprovadas na TV-1 (uma linha de 6h), 3h
-- pendentes na TV-2 e 5h recusadas; ELIAS tem 2h aprovadas; ENEIDA tem 5h
-- aprovadas. MARCOS tem ainda 8h aprovadas ontem, que e outra linha porque o dia e
-- outro. A recusada nao soma em lugar nenhum. IVO (inativo) e OSVALDO (empresa B)
-- nao podem aparecer.
insert into public.apontamentos_horas (id, os_id, colaborador_id, data, horas, tipo_hora_id, descricao, tenant_id, empresa_id)
values
  ('1c000000-0000-4000-8000-00000000a001', 939001, '1c000000-0000-4000-8000-000000000101', public.fn_tablet_data_hoje(), 4, '1c000000-0000-4000-8000-000000000301', 'aprovada 4h', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020'),
  ('1c000000-0000-4000-8000-00000000a002', 939001, '1c000000-0000-4000-8000-000000000101', public.fn_tablet_data_hoje(), 2, '1c000000-0000-4000-8000-000000000301', 'aprovada 2h na mesma OS e no mesmo dia', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020'),
  ('1c000000-0000-4000-8000-00000000a003', 939002, '1c000000-0000-4000-8000-000000000101', public.fn_tablet_data_hoje(), 3, '1c000000-0000-4000-8000-000000000301', 'pendente', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020'),
  ('1c000000-0000-4000-8000-00000000a004', 939002, '1c000000-0000-4000-8000-000000000101', public.fn_tablet_data_hoje(), 5, '1c000000-0000-4000-8000-000000000301', 'recusada', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020'),
  ('1c000000-0000-4000-8000-00000000a005', 939001, '1c000000-0000-4000-8000-000000000101', public.fn_tablet_data_hoje() - 1, 8, '1c000000-0000-4000-8000-000000000301', 'aprovada ontem', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020'),
  ('1c000000-0000-4000-8000-00000000a006', 939001, '1c000000-0000-4000-8000-000000000102', public.fn_tablet_data_hoje(), 2, '1c000000-0000-4000-8000-000000000301', 'eletrica', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020'),
  ('1c000000-0000-4000-8000-00000000a007', 939001, '1c000000-0000-4000-8000-000000000104', public.fn_tablet_data_hoje(), 6, '1c000000-0000-4000-8000-000000000301', 'hora de colaborador inativo', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020'),
  ('1c000000-0000-4000-8000-00000000a008', 939003, '1c000000-0000-4000-8000-000000000107', public.fn_tablet_data_hoje(), 7, '1c000000-0000-4000-8000-000000000301', 'hora da empresa B', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000021'),
  ('1c000000-0000-4000-8000-00000000a009', 939002, '1c000000-0000-4000-8000-000000000108', public.fn_tablet_data_hoje(), 5, '1c000000-0000-4000-8000-000000000301', 'engenharia', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020');

-- O gatilho de preparacao forca 'pendente' no insert; a tela e que esta em teste
-- aqui, entao os tres estados ficam fixados na mao (um update que nao toca em
-- data, horas nem tipo passa reto pelo gatilho).
update public.apontamentos_horas set status_aprovacao = 'aprovado'
where id in ('1c000000-0000-4000-8000-00000000a001', '1c000000-0000-4000-8000-00000000a002',
             '1c000000-0000-4000-8000-00000000a005', '1c000000-0000-4000-8000-00000000a006',
             '1c000000-0000-4000-8000-00000000a007', '1c000000-0000-4000-8000-00000000a008',
             '1c000000-0000-4000-8000-00000000a009');
update public.apontamentos_horas set status_aprovacao = 'pendente'
where id = '1c000000-0000-4000-8000-00000000a003';
update public.apontamentos_horas set status_aprovacao = 'rejeitado', motivo_devolucao = 'fora do combinado'
where id = '1c000000-0000-4000-8000-00000000a004';

-- Tarefas de trabalho. Quem e a pessoa esta em tarefas_participantes: a coluna
-- tarefas.colaborador_id saiu na migration 20260912220000.
insert into public.tarefas (id, tenant_id, empresa_id, os_id, tipo, data, dias, medida, descricao, situacao) values
  ('1c000000-0000-4000-8000-00000000b001', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', 939001, 'agendada', public.fn_tablet_data_hoje() - 3, 1, 'dias', 'Alinhar a bomba (atrasada)', 'pendente'),
  ('1c000000-0000-4000-8000-00000000b002', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', 939002, 'agendada', public.fn_tablet_data_hoje(), 1, 'dias', 'Montar o painel em tres', 'pendente'),
  ('1c000000-0000-4000-8000-00000000b003', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', 939002, 'sem_data', null, 1, 'dias', 'Revisar o quadro quando der', 'pendente'),
  ('1c000000-0000-4000-8000-00000000b007', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', 939001, 'agendada', public.fn_tablet_data_hoje(), 1, 'dias', 'Tarefa de colaborador inativo', 'pendente'),
  ('1c000000-0000-4000-8000-00000000b008', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000021', 939003, 'agendada', public.fn_tablet_data_hoje(), 1, 'dias', 'Tarefa da empresa B', 'pendente'),
  ('1c000000-0000-4000-8000-00000000b009', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', 939002, 'agendada', public.fn_tablet_data_hoje(), 1, 'dias', 'Detalhar o projeto do painel', 'pendente');
insert into public.tarefas (id, tenant_id, empresa_id, os_id, tipo, data, dias, medida, descricao, situacao, concluida_em) values
  ('1c000000-0000-4000-8000-00000000b004', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', 939001, 'agendada', public.fn_tablet_data_hoje() - 1, 1, 'dias', 'Trocar rolamento (fechada hoje)', 'concluida', now()),
  ('1c000000-0000-4000-8000-00000000b005', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', 939001, 'agendada', public.fn_tablet_data_hoje() - 2, 1, 'dias', 'Fechada anteontem', 'concluida', now() - interval '2 days');
insert into public.tarefas (id, tenant_id, empresa_id, os_id, tipo, data, dias, medida, descricao, situacao, cancelada_em, cancelamento_motivo) values
  ('1c000000-0000-4000-8000-00000000b006', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', 939001, 'sem_data', null, 1, 'dias', 'Cancelada', 'cancelada', now(), 'nao vai mais');

-- Ausencias: folga, ferias e outro. Nao tem OS e sempre tem data.
insert into public.tarefas (id, tenant_id, empresa_id, os_id, tipo, data, dias, medida, horas, categoria, descricao, situacao) values
  ('1c000000-0000-4000-8000-00000000b101', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', null, 'agendada', public.fn_tablet_data_hoje() + 1, 2, 'dias', null, 'ferias', 'Ferias do Marcos, dois dias', 'pendente'),
  ('1c000000-0000-4000-8000-00000000b102', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', null, 'agendada', public.fn_tablet_data_hoje(), 1, 'horas', 4, 'folga', 'Folga de quatro horas', 'pendente'),
  ('1c000000-0000-4000-8000-00000000b103', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', null, 'agendada', public.fn_tablet_data_hoje(), 1, 'dias', null, 'outro', 'Consulta medica', 'pendente'),
  ('1c000000-0000-4000-8000-00000000b104', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000021', null, 'agendada', public.fn_tablet_data_hoje(), 1, 'dias', null, 'folga', 'Folga na empresa B', 'pendente'),
  -- A folga da ENEIDA e amanha de proposito: assim ela nao mexe nas contas de
  -- "hoje" nem no recorte que vai so ate hoje, e ainda serve ao filtro de area.
  ('1c000000-0000-4000-8000-00000000b106', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', null, 'agendada', public.fn_tablet_data_hoje() + 1, 1, 'dias', null, 'folga', 'Folga da Eneida', 'pendente');
insert into public.tarefas (id, tenant_id, empresa_id, os_id, tipo, data, dias, medida, horas, categoria, descricao, situacao, cancelada_em, cancelamento_motivo) values
  ('1c000000-0000-4000-8000-00000000b105', '1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', null, 'agendada', public.fn_tablet_data_hoje(), 1, 'dias', null, 'folga', 'Folga cancelada da Maria', 'cancelada', now(), 'trabalhou');

insert into public.tarefas_participantes (tarefa_id, colaborador_id) values
  ('1c000000-0000-4000-8000-00000000b001', '1c000000-0000-4000-8000-000000000101'),
  -- b002 tem tres pessoas (a terceira entra abaixo, ja com a parte dela fechada):
  -- tem de virar tres linhas no painel.
  ('1c000000-0000-4000-8000-00000000b002', '1c000000-0000-4000-8000-000000000101'),
  ('1c000000-0000-4000-8000-00000000b002', '1c000000-0000-4000-8000-000000000102'),
  ('1c000000-0000-4000-8000-00000000b003', '1c000000-0000-4000-8000-000000000102'),
  ('1c000000-0000-4000-8000-00000000b006', '1c000000-0000-4000-8000-000000000103'),
  ('1c000000-0000-4000-8000-00000000b007', '1c000000-0000-4000-8000-000000000104'),
  ('1c000000-0000-4000-8000-00000000b008', '1c000000-0000-4000-8000-000000000107'),
  ('1c000000-0000-4000-8000-00000000b101', '1c000000-0000-4000-8000-000000000101'),
  ('1c000000-0000-4000-8000-00000000b102', '1c000000-0000-4000-8000-000000000102'),
  ('1c000000-0000-4000-8000-00000000b103', '1c000000-0000-4000-8000-000000000103'),
  ('1c000000-0000-4000-8000-00000000b104', '1c000000-0000-4000-8000-000000000107'),
  ('1c000000-0000-4000-8000-00000000b105', '1c000000-0000-4000-8000-000000000105'),
  ('1c000000-0000-4000-8000-00000000b009', '1c000000-0000-4000-8000-000000000108'),
  ('1c000000-0000-4000-8000-00000000b106', '1c000000-0000-4000-8000-000000000108');
-- A conclusao e por pessoa: b004 fechou hoje (aparece), b005 fechou anteontem (nao)
-- e, na tarefa de tres, MURILO ja fechou a parte dele hoje enquanto a tarefa
-- inteira continua pendente.
insert into public.tarefas_participantes (tarefa_id, colaborador_id, concluida_em) values
  ('1c000000-0000-4000-8000-00000000b002', '1c000000-0000-4000-8000-000000000106', now()),
  ('1c000000-0000-4000-8000-00000000b004', '1c000000-0000-4000-8000-000000000101', now()),
  ('1c000000-0000-4000-8000-00000000b005', '1c000000-0000-4000-8000-000000000103', now() - interval '2 days');

-- Reserva e uma linha por pessoa e por dia. So as que o teste confere, para nao
-- bater no indice unico de colaborador/dia.
insert into public.tarefas_reservas (tenant_id, empresa_id, tarefa_id, colaborador_id, data) values
  ('1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', '1c000000-0000-4000-8000-00000000b001', '1c000000-0000-4000-8000-000000000101', public.fn_tablet_data_hoje() - 3),
  ('1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', '1c000000-0000-4000-8000-00000000b004', '1c000000-0000-4000-8000-000000000101', public.fn_tablet_data_hoje() - 1),
  ('1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', '1c000000-0000-4000-8000-00000000b002', '1c000000-0000-4000-8000-000000000101', public.fn_tablet_data_hoje()),
  ('1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', '1c000000-0000-4000-8000-00000000b002', '1c000000-0000-4000-8000-000000000102', public.fn_tablet_data_hoje()),
  ('1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', '1c000000-0000-4000-8000-00000000b002', '1c000000-0000-4000-8000-000000000106', public.fn_tablet_data_hoje()),
  ('1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', '1c000000-0000-4000-8000-00000000b101', '1c000000-0000-4000-8000-000000000101', public.fn_tablet_data_hoje() + 1),
  ('1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', '1c000000-0000-4000-8000-00000000b101', '1c000000-0000-4000-8000-000000000101', public.fn_tablet_data_hoje() + 2),
  ('1c000000-0000-4000-8000-000000000010', '1c000000-0000-4000-8000-000000000020', '1c000000-0000-4000-8000-00000000b009', '1c000000-0000-4000-8000-000000000108', public.fn_tablet_data_hoje());

create or replace function pg_temp.como(p_sub text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_sub, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', p_sub), true);
end $$;
create or replace function pg_temp.sistema() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

-- =====================================================================================
-- A televisao (PAINEL_TV) le o painel.
-- =====================================================================================
select pg_temp.como('1c000000-0000-4000-8000-000000000001');
set local role authenticated;

-- 1. tv_periodos: semana, mes, dia util e jornada. ---------------------------------------
do $periodos$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_passada date := (select d from datas where nome = 'semana_passada');
  v_limpa date := (select d from datas where nome = 'semana_limpa');
  v_feriado date := (select d from datas where nome = 'semana_feriado');
  ctx jsonb;
begin
  ctx := public.tv_periodos();
  if ctx->>'papel' <> 'PAINEL_TV' then raise exception 'papel da televisao no painel: %', ctx; end if;
  if (ctx->>'hoje')::date <> v_hoje then raise exception 'hoje do painel: %', ctx; end if;

  -- Semana comeca na segunda; mes no dia 1.
  if extract(isodow from (ctx->>'inicio_semana')::date) <> 1 then raise exception 'semana nao comeca na segunda: %', ctx; end if;
  if (ctx->>'inicio_semana')::date > v_hoje or (ctx->>'inicio_semana')::date < v_hoje - 6 then
    raise exception 'inicio_semana nao e a segunda da semana corrente: %', ctx;
  end if;
  if (ctx->>'inicio_mes')::date <> date_trunc('month', v_hoje::timestamp)::date then raise exception 'inicio_mes: %', ctx; end if;
  if extract(day from (ctx->>'inicio_mes')::date) <> 1 then raise exception 'inicio_mes nao caiu no dia 1: %', ctx; end if;

  -- Sem argumento: os sete dias da semana corrente.
  if jsonb_array_length(ctx->'dias') <> 7 then raise exception 'dias da semana: %', ctx->'dias'; end if;
  if (ctx->'dias'->0->>'data')::date <> (ctx->>'inicio_semana')::date then raise exception 'dias nao comeca na segunda: %', ctx->'dias'; end if;

  -- Uma entrada por dia, com as cinco marcas que a tela le.
  if exists (
    select 1 from jsonb_array_elements(ctx->'dias') as d
    where d->'data' is null or d->'dow' is null or d->'eh_util' is null
       or not d ? 'feriado' or d->'passado' is null or d->'horas_previstas' is null
  ) then
    raise exception 'dia do painel sem eh_util/feriado/passado/horas_previstas: %', ctx->'dias';
  end if;

  -- A data do dia precisa vir como AAAA-MM-DD puro: se vier timestamp, a
  -- televisao acaba passando por new Date() e perde um dia no fuso.
  if exists (select 1 from jsonb_array_elements(ctx->'dias') as d where length(d->>'data') <> 10) then
    raise exception 'data do dia nao veio como AAAA-MM-DD: %', ctx->'dias';
  end if;

  -- Fim de semana e feriado nunca sao dia util, e nao tem hora prevista.
  if exists (
    select 1 from jsonb_array_elements(ctx->'dias') as d
    where (d->>'dow')::int in (6, 7) and coalesce((d->>'eh_util')::boolean, false)
  ) then
    raise exception 'fim de semana veio como dia util: %', ctx->'dias';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ctx->'dias') as d
    where d->>'feriado' is not null and coalesce((d->>'eh_util')::boolean, false)
  ) then
    raise exception 'feriado veio como dia util: %', ctx->'dias';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ctx->'dias') as d
    where not coalesce((d->>'eh_util')::boolean, false) and (d->>'horas_previstas')::numeric <> 0
  ) then
    raise exception 'dia nao util veio com hora prevista: %', ctx->'dias';
  end if;

  -- passado inclui hoje (a tela e que decide nao cobrar o dia corrente).
  if not coalesce((select (d->>'passado')::boolean from jsonb_array_elements(ctx->'dias') as d where (d->>'data')::date = v_hoje), false) then
    raise exception 'hoje nao veio como passado: %', ctx->'dias';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ctx->'dias') as d
    where (d->>'data')::date > v_hoje and coalesce((d->>'passado')::boolean, false)
  ) then
    raise exception 'dia futuro veio como passado: %', ctx->'dias';
  end if;

  -- Os dois totais sao a soma dos dias, e o ate_hoje so dos que ja passaram.
  if (ctx->>'horas_previstas')::numeric
     <> (select coalesce(sum((d->>'horas_previstas')::numeric), 0) from jsonb_array_elements(ctx->'dias') as d) then
    raise exception 'horas_previstas nao e a soma dos dias: %', ctx;
  end if;
  if (ctx->>'horas_previstas_ate_hoje')::numeric
     <> (select coalesce(sum((d->>'horas_previstas')::numeric), 0) from jsonb_array_elements(ctx->'dias') as d
         where coalesce((d->>'passado')::boolean, false)) then
    raise exception 'horas_previstas_ate_hoje nao e a soma dos dias que passaram: %', ctx;
  end if;

  -- A semana da fabrica fecha em 44 horas quando nao tem feriado.
  ctx := public.tv_periodos(v_limpa, v_limpa + 6);
  if (ctx->>'horas_previstas')::numeric <> 44 then
    raise exception 'semana sem feriado devia prever 44 horas, previu %', ctx->>'horas_previstas';
  end if;
  if (ctx->>'horas_previstas_ate_hoje')::numeric <> 0 then
    raise exception 'semana inteira no futuro nao devia ter hora prevista ate hoje: %', ctx;
  end if;

  -- Semana inteira no passado: o previsto ate hoje e o previsto inteiro.
  ctx := public.tv_periodos(v_passada, v_passada + 6);
  if (ctx->>'horas_previstas')::numeric <> 44 or (ctx->>'horas_previstas_ate_hoje')::numeric <> 44 then
    raise exception 'semana passada sem feriado: previsto % e ate hoje %', ctx->>'horas_previstas', ctx->>'horas_previstas_ate_hoje';
  end if;

  -- Feriado plantado numa segunda: a semana cai de 44 para 35.
  ctx := public.tv_periodos(v_feriado, v_feriado + 6);
  if (ctx->>'horas_previstas')::numeric <> 35 then
    raise exception 'semana com feriado na segunda devia prever 35 horas, previu %', ctx->>'horas_previstas';
  end if;
  if (select d->>'feriado' from jsonb_array_elements(ctx->'dias') as d where (d->>'data')::date = v_feriado)
     <> 'Feriado plantado pelo teste do painel' then
    raise exception 'o feriado plantado nao chegou no dia da segunda: %', ctx->'dias';
  end if;
  if coalesce((select (d->>'eh_util')::boolean from jsonb_array_elements(ctx->'dias') as d where (d->>'data')::date = v_feriado), false) then
    raise exception 'a segunda de feriado veio como dia util: %', ctx->'dias';
  end if;

  -- Periodo absurdo e recusado.
  begin
    perform public.tv_periodos(v_hoje - 400, v_hoje);
    raise exception 'tv_periodos aceitou periodo de mais de um ano';
  exception when others then
    if sqlerrm not like 'Informe um período%' then raise; end if;
  end;
end $periodos$;

-- 2. tv_colaboradores: area, inativo e quem nao tem nada. --------------------------------
do $colaboradores$
declare
  v_nomes text[];
begin
  -- Sem filtro: os seis ativos da empresa A, as tres areas juntas na mesma lista.
  -- O inativo e o da empresa B ficam fora.
  select array_agg(nome order by nome) into v_nomes from public.tv_colaboradores(null);
  if v_nomes <> array['ELETRICO ELIAS', 'ENGENHEIRA ENEIDA', 'MECANICA MARIA', 'MECANICO MARCOS', 'MECANICO MURILO', 'SEM AREA SONIA'] then
    raise exception 'lista de colaboradores sem filtro: %', v_nomes;
  end if;
  if (select count(distinct area) from public.tv_colaboradores(null) where area is not null) <> 3 then
    raise exception 'sem filtro a lista devia trazer as tres areas: %', (select array_agg(distinct area) from public.tv_colaboradores(null));
  end if;

  -- Mecanica: inclusive MECANICA MARIA, que nao tem hora nem tarefa nenhuma.
  select array_agg(nome order by nome) into v_nomes from public.tv_colaboradores('mecanica');
  if v_nomes <> array['MECANICA MARIA', 'MECANICO MARCOS', 'MECANICO MURILO'] then
    raise exception 'lista da mecanica: %', v_nomes;
  end if;
  if (select count(*) from public.tv_colaboradores('mecanica') where nome = 'MECANICA MARIA') <> 1 then
    raise exception 'colaborador sem hora e sem tarefa tem de aparecer no painel';
  end if;

  select array_agg(nome order by nome) into v_nomes from public.tv_colaboradores('eletrica');
  if v_nomes <> array['ELETRICO ELIAS'] then raise exception 'lista da eletrica: %', v_nomes; end if;

  -- Engenharia: a turma do escritorio tem a tela so dela.
  select array_agg(nome order by nome) into v_nomes from public.tv_colaboradores('engenharia');
  if v_nomes <> array['ENGENHEIRA ENEIDA'] then raise exception 'lista da engenharia: %', v_nomes; end if;
  if (select area from public.tv_colaboradores('engenharia') where nome = 'ENGENHEIRA ENEIDA') <> 'engenharia' then
    raise exception 'a linha da engenharia nao veio com a area engenharia';
  end if;

  -- Quem e da engenharia nao aparece nas duas frentes de fabrica: e por isso que a
  -- terceira area existe, para o chao de fabrica nao ver coordenacao e projeto na
  -- TV dele.
  if exists (select 1 from public.tv_colaboradores('mecanica') where nome = 'ENGENHEIRA ENEIDA')
     or exists (select 1 from public.tv_colaboradores('eletrica') where nome = 'ENGENHEIRA ENEIDA') then
    raise exception 'colaborador da engenharia apareceu na mecanica ou na eletrica';
  end if;

  -- Quem esta sem area nao aparece em nenhuma das tres areas.
  if exists (select 1 from public.tv_colaboradores('mecanica') where nome = 'SEM AREA SONIA')
     or exists (select 1 from public.tv_colaboradores('eletrica') where nome = 'SEM AREA SONIA')
     or exists (select 1 from public.tv_colaboradores('engenharia') where nome = 'SEM AREA SONIA') then
    raise exception 'colaborador sem area apareceu numa area';
  end if;

  -- A area vem na linha, e o cargo tambem (a tela mostra os dois).
  if (select area from public.tv_colaboradores('mecanica') where nome = 'MECANICO MARCOS') <> 'mecanica'
     or (select cargo from public.tv_colaboradores('mecanica') where nome = 'MECANICO MARCOS') <> 'MECANICO' then
    raise exception 'area ou cargo do colaborador no painel';
  end if;

  -- Inativo nunca entra, com ou sem filtro.
  if exists (select 1 from public.tv_colaboradores(null) where nome = 'INATIVO IVO')
     or exists (select 1 from public.tv_colaboradores('mecanica') where nome = 'INATIVO IVO') then
    raise exception 'colaborador inativo apareceu na lista';
  end if;

  -- Colaborador de outra empresa nao vaza.
  if exists (select 1 from public.tv_colaboradores(null) where nome = 'OUTRA EMPRESA OSVALDO') then
    raise exception 'colaborador de outra empresa apareceu na lista';
  end if;

  -- Abrir uma area a mais nao pode virar "aceita qualquer coisa": um valor
  -- inventado continua recusado por fn_tv_area, em todas as funcoes que a recebem.
  begin
    perform public.tv_colaboradores('hidraulica');
    raise exception 'tv_colaboradores aceitou area invalida';
  exception when others then
    if sqlerrm not like 'Área inválida:%' then raise; end if;
    -- Essa frase e o que a tela mostra para quem digitou a area na URL. Se ela nao
    -- citar a engenharia, quem abre ?area=engenharia e recebe um erro qualquer
    -- conclui que a area nao existe.
    if sqlerrm not like '%mecanica%' or sqlerrm not like '%eletrica%' or sqlerrm not like '%engenharia%' then
      raise exception 'a mensagem de area invalida devia citar as tres areas: %', sqlerrm;
    end if;
  end;
  begin
    perform public.tv_colaboradores_tarefas('hidraulica');
    raise exception 'tv_colaboradores_tarefas aceitou area invalida';
  exception when others then
    if sqlerrm not like 'Área inválida:%' then raise; end if;
  end;
  begin
    perform public.tv_horas_periodo((now() at time zone 'America/Sao_Paulo')::date, (now() at time zone 'America/Sao_Paulo')::date, 'hidraulica');
    raise exception 'tv_horas_periodo aceitou area invalida';
  exception when others then
    if sqlerrm not like 'Área inválida:%' then raise; end if;
  end;
  begin
    perform public.tv_ausencias_periodo((now() at time zone 'America/Sao_Paulo')::date, (now() at time zone 'America/Sao_Paulo')::date, 'hidraulica');
    raise exception 'tv_ausencias_periodo aceitou area invalida';
  exception when others then
    if sqlerrm not like 'Área inválida:%' then raise; end if;
  end;

  -- Espaco e caixa nao mudam o significado da area.
  if (select count(*) from public.tv_colaboradores('  MECANICA  ')) <> 3 then
    raise exception 'area com espaco e maiuscula devia valer';
  end if;
  if (select count(*) from public.tv_colaboradores('  ENGENHARIA  ')) <> 1 then
    raise exception 'engenharia com espaco e maiuscula devia valer';
  end if;
end $colaboradores$;

-- 3. tv_colaboradores_tarefas: uma linha por participante. -------------------------------
do $tarefas$
declare
  v_atrasada uuid := '1c000000-0000-4000-8000-00000000b001';
  v_tres uuid := '1c000000-0000-4000-8000-00000000b002';
  v_sem_data uuid := '1c000000-0000-4000-8000-00000000b003';
  v_fechada_hoje uuid := '1c000000-0000-4000-8000-00000000b004';
  v_linhas integer;
  v_nomes text[];
  v_pos_atrasada integer;
  v_pos_hoje integer;
begin
  -- Trabalho: b001 (MARCOS atrasada), b002 (tres pessoas hoje), b003 (ELIAS sem
  -- data), b004 (MARCOS fechada hoje) e b009 (ENEIDA hoje) = 7 linhas.
  select count(*) into v_linhas from public.tv_colaboradores_tarefas(null) where categoria = 'os';
  if v_linhas <> 7 then raise exception 'linhas de tarefa de OS no painel: % (esperado 7)', v_linhas; end if;

  -- Uma tarefa de tres participantes gera tres linhas, e cada uma diz que sao tres.
  select count(*), array_agg(colaborador_nome order by colaborador_nome)
    into v_linhas, v_nomes
  from public.tv_colaboradores_tarefas(null) where id = v_tres;
  if v_linhas <> 3 then raise exception 'tarefa de tres participantes virou % linha(s)', v_linhas; end if;
  if v_nomes <> array['ELETRICO ELIAS', 'MECANICO MARCOS', 'MECANICO MURILO'] then
    raise exception 'participantes da tarefa de tres: %', v_nomes;
  end if;
  if exists (select 1 from public.tv_colaboradores_tarefas(null) where id = v_tres and participantes <> 3) then
    raise exception 'a linha do participante devia dizer que a tarefa tem tres';
  end if;

  -- A conclusao e por pessoa: MURILO fechou a parte dele hoje e a tarefa segue
  -- pendente para os outros dois. Cada linha fala da parte da sua pessoa.
  if (select count(*) from public.tv_colaboradores_tarefas(null)
      where id = v_tres and participante_concluida_em is not null) <> 1 then
    raise exception 'so a linha do MURILO devia vir com a parte dele concluida';
  end if;
  if (select colaborador_nome from public.tv_colaboradores_tarefas(null)
      where id = v_tres and participante_concluida_em is not null) <> 'MECANICO MURILO' then
    raise exception 'a conclusao por pessoa foi para a linha errada';
  end if;
  if exists (select 1 from public.tv_colaboradores_tarefas(null) where id = v_tres and situacao <> 'pendente') then
    raise exception 'tarefa de tres com um participante fechado nao devia estar concluida';
  end if;

  -- A concluida hoje aparece, com o rastro da pessoa; a de anteontem nao.
  if (select count(*) from public.tv_colaboradores_tarefas(null) where id = v_fechada_hoje and situacao = 'concluida') <> 1 then
    raise exception 'tarefa concluida hoje devia aparecer no painel';
  end if;
  if (select participante_concluida_em from public.tv_colaboradores_tarefas(null) where id = v_fechada_hoje) is null then
    raise exception 'a linha da concluida hoje devia trazer a conclusao do participante';
  end if;
  if exists (select 1 from public.tv_colaboradores_tarefas(null) where id = '1c000000-0000-4000-8000-00000000b005') then
    raise exception 'tarefa concluida em outro dia apareceu no painel';
  end if;

  -- Cancelada, de colaborador inativo e de outra empresa ficam fora.
  if exists (select 1 from public.tv_colaboradores_tarefas(null) where situacao = 'cancelada') then
    raise exception 'tarefa cancelada apareceu no painel';
  end if;
  if exists (select 1 from public.tv_colaboradores_tarefas(null) where colaborador_nome = 'INATIVO IVO') then
    raise exception 'tarefa de colaborador inativo apareceu no painel';
  end if;
  if exists (select 1 from public.tv_colaboradores_tarefas(null) where id = '1c000000-0000-4000-8000-00000000b008')
     or exists (select 1 from public.tv_colaboradores_tarefas(null) where colaborador_nome = 'OUTRA EMPRESA OSVALDO') then
    raise exception 'tarefa de outra empresa apareceu no painel';
  end if;

  -- Marcas de atraso e de hoje.
  if (select count(*) from public.tv_colaboradores_tarefas(null) where coalesce(atrasada, false)) <> 1 then
    raise exception 'so b001 devia vir marcada como atrasada';
  end if;
  if (select id from public.tv_colaboradores_tarefas(null) where coalesce(atrasada, false)) <> v_atrasada then
    raise exception 'a atrasada do painel nao e b001';
  end if;
  -- Hoje: as tres linhas de b002 e a b009 da ENEIDA, mais a folga de horas e a
  -- ausencia de um dia.
  if (select count(*) from public.tv_colaboradores_tarefas(null) where coalesce(hoje, false)) <> 6 then
    raise exception 'linhas marcadas como de hoje: %', (select count(*) from public.tv_colaboradores_tarefas(null) where coalesce(hoje, false));
  end if;
  if (select count(*) from public.tv_colaboradores_tarefas(null) where data is null) <> 1 then
    raise exception 'so b003 devia vir sem data';
  end if;

  -- As atrasadas vem antes das de hoje.
  select max(ord) into v_pos_atrasada from (
    select l.ordinality as ord from public.tv_colaboradores_tarefas(null) with ordinality as l where coalesce(l.atrasada, false)
  ) as e;
  select min(ord) into v_pos_hoje from (
    select l.ordinality as ord from public.tv_colaboradores_tarefas(null) with ordinality as l where coalesce(l.hoje, false)
  ) as e;
  if v_pos_atrasada >= v_pos_hoje then
    raise exception 'atrasada (pos %) devia vir antes das de hoje (pos %)', v_pos_atrasada, v_pos_hoje;
  end if;
  if (select ord from (select l.ordinality as ord, l.id from public.tv_colaboradores_tarefas('mecanica') with ordinality as l) as e where id = v_atrasada) <> 1 then
    raise exception 'a atrasada devia ser a primeira linha da mecanica';
  end if;

  -- Filtro de area: na mecanica so MARCOS e MURILO.
  select count(*) into v_linhas from public.tv_colaboradores_tarefas('mecanica');
  if v_linhas <> 5 then raise exception 'linhas da mecanica: % (esperado 5)', v_linhas; end if;
  if exists (select 1 from public.tv_colaboradores_tarefas('mecanica') where colaborador_nome in ('ELETRICO ELIAS', 'SEM AREA SONIA', 'ENGENHEIRA ENEIDA')) then
    raise exception 'filtro de area nas tarefas deixou passar outra area';
  end if;
  if (select count(*) from public.tv_colaboradores_tarefas('eletrica')) <> 3 then
    raise exception 'linhas da eletrica: % (esperado 3)', (select count(*) from public.tv_colaboradores_tarefas('eletrica'));
  end if;
  if exists (select 1 from public.tv_colaboradores_tarefas('eletrica') where colaborador_nome = 'ENGENHEIRA ENEIDA') then
    raise exception 'tarefa da engenharia apareceu na eletrica';
  end if;

  -- Engenharia: a tarefa de OS de hoje e a folga de amanha, as duas da ENEIDA.
  select count(*), array_agg(distinct colaborador_nome) into v_linhas, v_nomes
  from public.tv_colaboradores_tarefas('engenharia');
  if v_linhas <> 2 then raise exception 'linhas da engenharia: % (esperado 2)', v_linhas; end if;
  if v_nomes <> array['ENGENHEIRA ENEIDA'] then raise exception 'quem apareceu na engenharia: %', v_nomes; end if;
  if (select count(*) from public.tv_colaboradores_tarefas('engenharia') where id = '1c000000-0000-4000-8000-00000000b009' and coalesce(hoje, false)) <> 1 then
    raise exception 'a tarefa de hoje da engenharia nao veio marcada como de hoje';
  end if;

  -- Reserva do dia vem por pessoa; tarefa sem data nao reserva nada.
  if exists (select 1 from public.tv_colaboradores_tarefas(null) where id = v_tres and not coalesce(reserva_ativa, false)) then
    raise exception 'a tarefa de hoje devia estar reservada para os tres';
  end if;
  if coalesce((select reserva_ativa from public.tv_colaboradores_tarefas(null) where id = v_sem_data), false) then
    raise exception 'tarefa sem data nao reserva dia';
  end if;

  -- A televisao nao age: as tres flags de acao vem sempre falsas.
  if exists (select 1 from public.tv_colaboradores_tarefas(null) where coalesce(minha, false) or coalesce(pode_gerir, false) or coalesce(pode_concluir, false)) then
    raise exception 'painel devolveu flag de acao verdadeira';
  end if;

  -- Dados da OS chegam na linha de trabalho; a ausencia nao tem OS.
  if (select numero_os from public.tv_colaboradores_tarefas(null) where id = v_atrasada) <> 'TV-1'
     or (select cliente_nome from public.tv_colaboradores_tarefas(null) where id = v_atrasada) <> 'CLIENTE TV' then
    raise exception 'dados da OS na linha do painel';
  end if;
  if exists (select 1 from public.tv_colaboradores_tarefas(null) where categoria <> 'os' and (os_id is not null or numero_os is not null)) then
    raise exception 'ausencia veio com OS';
  end if;

  -- Ausencia pendente tambem sai por aqui (a tela usa a lista como "tarefas
  -- pendentes"): quatro linhas, uma por pessoa ausente.
  if (select count(*) from public.tv_colaboradores_tarefas(null) where categoria <> 'os') <> 4 then
    raise exception 'linhas de ausencia no painel: %', (select count(*) from public.tv_colaboradores_tarefas(null) where categoria <> 'os');
  end if;
  if (select count(*) from public.tv_colaboradores_tarefas(null)) <> 11 then
    raise exception 'total de linhas do painel: % (esperado 11)', (select count(*) from public.tv_colaboradores_tarefas(null));
  end if;
end $tarefas$;

-- 4. tv_horas_periodo: soma por colaborador, OS e dia. -----------------------------------
do $horas$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_total numeric;
  v_linhas integer;
begin
  -- MARCOS: 6h aprovadas na TV-1 hoje (4 + 2), 3h pendentes na TV-2 hoje e 8h
  -- aprovadas ontem. As 5h recusadas ficam fora: 17h em tres linhas.
  select count(*), coalesce(sum(horas), 0) into v_linhas, v_total
  from public.tv_horas_periodo(v_hoje - 7, v_hoje, null)
  where colaborador_id = '1c000000-0000-4000-8000-000000000101';
  if v_total <> 17 then raise exception 'horas do MARCOS: % (esperado 17, a recusada de 5h fora)', v_total; end if;
  if v_linhas <> 3 then raise exception 'linhas do MARCOS: % (esperado 3: OS e dia)', v_linhas; end if;

  -- A soma por colaborador, OS e dia junta os dois lancamentos aprovados.
  select horas into v_total
  from public.tv_horas_periodo(v_hoje - 7, v_hoje, null)
  where colaborador_id = '1c000000-0000-4000-8000-000000000101' and os_id = 939001 and data = v_hoje;
  if v_total <> 6 then raise exception 'os dois lancamentos aprovados do dia deviam somar 6h, somaram %', v_total; end if;
  if (select numero_os from public.tv_horas_periodo(v_hoje - 7, v_hoje, null)
      where colaborador_id = '1c000000-0000-4000-8000-000000000101' and os_id = 939001 and data = v_hoje) <> 'TV-1' then
    raise exception 'numero da OS na linha de horas';
  end if;

  -- A recusada nao aparece nem como linha.
  if exists (select 1 from public.tv_horas_periodo(v_hoje - 7, v_hoje, null) where status_aprovacao = 'rejeitado') then
    raise exception 'hora recusada apareceu no painel';
  end if;

  -- A pendente entra e vem marcada como pendente.
  select count(*), coalesce(sum(horas), 0) into v_linhas, v_total
  from public.tv_horas_periodo(v_hoje - 7, v_hoje, null) where status_aprovacao = 'pendente';
  if v_linhas <> 1 or v_total <> 3 then raise exception 'a hora pendente devia vir marcada e somar 3h: % linha(s), %h', v_linhas, v_total; end if;

  -- Filtro de area.
  select coalesce(sum(horas), 0) into v_total from public.tv_horas_periodo(v_hoje - 7, v_hoje, 'eletrica');
  if v_total <> 2 then raise exception 'horas da eletrica: % (esperado 2)', v_total; end if;
  select coalesce(sum(horas), 0) into v_total from public.tv_horas_periodo(v_hoje - 7, v_hoje, 'mecanica');
  if v_total <> 17 then raise exception 'horas da mecanica: % (esperado 17)', v_total; end if;

  -- Engenharia: as 5h da ENEIDA, e so as dela. A hora dela nao pode somar junto
  -- com a mecanica, que e de onde o cargo dela viria.
  select count(*), coalesce(sum(horas), 0) into v_linhas, v_total
  from public.tv_horas_periodo(v_hoje - 7, v_hoje, 'engenharia');
  if v_linhas <> 1 or v_total <> 5 then raise exception 'horas da engenharia: % linha(s), %h (esperado 1 linha e 5h)', v_linhas, v_total; end if;
  if (select colaborador_nome from public.tv_horas_periodo(v_hoje - 7, v_hoje, 'engenharia')) <> 'ENGENHEIRA ENEIDA' then
    raise exception 'a hora da engenharia nao e da ENEIDA';
  end if;
  if exists (select 1 from public.tv_horas_periodo(v_hoje - 7, v_hoje, 'mecanica') where colaborador_nome = 'ENGENHEIRA ENEIDA')
     or exists (select 1 from public.tv_horas_periodo(v_hoje - 7, v_hoje, 'eletrica') where colaborador_nome = 'ENGENHEIRA ENEIDA') then
    raise exception 'hora da engenharia apareceu na mecanica ou na eletrica';
  end if;

  -- Hora de colaborador inativo e de outra empresa nao soma.
  if exists (select 1 from public.tv_horas_periodo(v_hoje - 7, v_hoje, null) where colaborador_nome = 'INATIVO IVO') then
    raise exception 'hora de colaborador inativo apareceu no painel';
  end if;
  if exists (select 1 from public.tv_horas_periodo(v_hoje - 7, v_hoje, null) where os_id = 939003) then
    raise exception 'hora de outra empresa apareceu no painel';
  end if;
  select coalesce(sum(horas), 0) into v_total from public.tv_horas_periodo(v_hoje - 7, v_hoje, null);
  if v_total <> 24 then raise exception 'total de horas do painel: % (esperado 24)', v_total; end if;

  -- Recorte do periodo: so hoje deixa as 8h de ontem de fora.
  select coalesce(sum(horas), 0) into v_total
  from public.tv_horas_periodo(v_hoje, v_hoje, null)
  where colaborador_id = '1c000000-0000-4000-8000-000000000101';
  if v_total <> 9 then raise exception 'horas do MARCOS so hoje: % (esperado 9)', v_total; end if;

  -- Periodo invalido e recusado.
  begin
    perform public.tv_horas_periodo(v_hoje - 400, v_hoje, null);
    raise exception 'tv_horas_periodo aceitou periodo de mais de um ano';
  exception when others then
    if sqlerrm not like 'Informe um período%' then raise; end if;
  end;
  begin
    perform public.tv_horas_periodo(v_hoje, v_hoje - 1, null);
    raise exception 'tv_horas_periodo aceitou fim antes do inicio';
  exception when others then
    if sqlerrm not like 'Informe um período%' then raise; end if;
  end;
end $horas$;

-- 5. tv_ausencias_periodo: folga, ferias e outro, por pessoa e por dia. ------------------
do $ausencias$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_linhas integer;
  v_datas date[];
begin
  -- Ferias de dois dias do MARCOS (duas linhas), folga de 4h do ELIAS, a ausencia
  -- de um dia da SONIA e a folga de amanha da ENEIDA.
  select count(*) into v_linhas from public.tv_ausencias_periodo(v_hoje - 7, v_hoje + 7, null);
  if v_linhas <> 5 then raise exception 'linhas de ausencia: % (esperado 5)', v_linhas; end if;

  -- Uma linha por dia de ausencia e por pessoa.
  select array_agg(data order by data) into v_datas
  from public.tv_ausencias_periodo(v_hoje - 7, v_hoje + 7, null)
  where colaborador_id = '1c000000-0000-4000-8000-000000000101';
  if v_datas <> array[v_hoje + 1, v_hoje + 2] then raise exception 'dias das ferias do MARCOS: %', v_datas; end if;
  if exists (
    select 1 from public.tv_ausencias_periodo(v_hoje - 7, v_hoje + 7, null)
    where colaborador_id = '1c000000-0000-4000-8000-000000000101'
      and (categoria <> 'ferias' or medida <> 'dias' or horas is not null)
  ) then
    raise exception 'ferias em dias devia vir com medida dias e sem horas';
  end if;

  -- Ausencia em horas: um dia so, com as horas liberadas.
  select count(*) into v_linhas
  from public.tv_ausencias_periodo(v_hoje - 7, v_hoje + 7, null)
  where colaborador_id = '1c000000-0000-4000-8000-000000000102'
    and categoria = 'folga' and medida = 'horas' and horas = 4 and data = v_hoje;
  if v_linhas <> 1 then raise exception 'a folga de quatro horas do ELIAS nao veio como esperado'; end if;

  -- A terceira categoria tambem sai.
  if (select count(*) from public.tv_ausencias_periodo(v_hoje - 7, v_hoje + 7, null) where categoria = 'outro') <> 1 then
    raise exception 'ausencia de categoria outro nao apareceu';
  end if;
  if (select count(distinct categoria) from public.tv_ausencias_periodo(v_hoje - 7, v_hoje + 7, null)) <> 3 then
    raise exception 'as tres categorias de ausencia deviam aparecer';
  end if;

  -- Filtro de area.
  select count(*) into v_linhas from public.tv_ausencias_periodo(v_hoje - 7, v_hoje + 7, 'mecanica');
  if v_linhas <> 2 then raise exception 'ausencias da mecanica: % (esperado 2)', v_linhas; end if;
  if exists (select 1 from public.tv_ausencias_periodo(v_hoje - 7, v_hoje + 7, 'mecanica') where colaborador_nome <> 'MECANICO MARCOS') then
    raise exception 'ausencia de outra area apareceu na mecanica';
  end if;
  if (select count(*) from public.tv_ausencias_periodo(v_hoje - 7, v_hoje + 7, 'eletrica')) <> 1 then
    raise exception 'ausencias da eletrica: % (esperado 1)', (select count(*) from public.tv_ausencias_periodo(v_hoje - 7, v_hoje + 7, 'eletrica'));
  end if;
  select count(*) into v_linhas from public.tv_ausencias_periodo(v_hoje - 7, v_hoje + 7, 'engenharia');
  if v_linhas <> 1 then raise exception 'ausencias da engenharia: % (esperado 1)', v_linhas; end if;
  if exists (select 1 from public.tv_ausencias_periodo(v_hoje - 7, v_hoje + 7, 'engenharia') where colaborador_nome <> 'ENGENHEIRA ENEIDA') then
    raise exception 'ausencia de outra area apareceu na engenharia';
  end if;
  if exists (select 1 from public.tv_ausencias_periodo(v_hoje - 7, v_hoje + 7, 'mecanica') where colaborador_nome = 'ENGENHEIRA ENEIDA') then
    raise exception 'ausencia da engenharia apareceu na mecanica';
  end if;

  -- Outra empresa nao vaza, e ausencia cancelada nao conta.
  if exists (select 1 from public.tv_ausencias_periodo(v_hoje - 7, v_hoje + 7, null) where colaborador_nome = 'OUTRA EMPRESA OSVALDO') then
    raise exception 'ausencia de outra empresa apareceu no painel';
  end if;
  if exists (select 1 from public.tv_ausencias_periodo(v_hoje - 7, v_hoje + 7, null) where colaborador_nome = 'MECANICA MARIA') then
    raise exception 'ausencia cancelada apareceu no painel';
  end if;

  -- Recorte do periodo: as ferias do MARCOS e a folga da ENEIDA sao depois de hoje.
  if (select count(*) from public.tv_ausencias_periodo(v_hoje - 7, v_hoje, null)) <> 2 then
    raise exception 'ausencias ate hoje: % (esperado 2)', (select count(*) from public.tv_ausencias_periodo(v_hoje - 7, v_hoje, null));
  end if;

  begin
    perform public.tv_ausencias_periodo(v_hoje - 400, v_hoje, null);
    raise exception 'tv_ausencias_periodo aceitou periodo de mais de um ano';
  exception when others then
    if sqlerrm not like 'Informe um período%' then raise; end if;
  end;
end $ausencias$;

-- 6. Por fora das funcoes, a conta da TV nao le nada. ------------------------------------
-- Este e o ponto central de seguranca da tela: a televisao fica aberta no chao de
-- fabrica com uma sessao de verdade. Ela le o painel por funcao SECURITY DEFINER e
-- mais nada.
do $vazamento$
declare
  v_linhas integer;
begin
  begin
    select count(*) into v_linhas from public.tarefas;
    if coalesce(v_linhas, 0) <> 0 then raise exception 'a conta de TV leu % linha(s) de public.tarefas direto', v_linhas; end if;
  exception when insufficient_privilege then null;
  end;

  begin
    select count(*) into v_linhas from public.tarefas_participantes;
    if coalesce(v_linhas, 0) <> 0 then raise exception 'a conta de TV leu % linha(s) de public.tarefas_participantes direto', v_linhas; end if;
  exception when insufficient_privilege then null;
  end;

  begin
    select count(*) into v_linhas from public.tarefas_reservas;
    if coalesce(v_linhas, 0) <> 0 then raise exception 'a conta de TV leu % linha(s) de public.tarefas_reservas direto', v_linhas; end if;
  exception when insufficient_privilege then null;
  end;

  begin
    select count(*) into v_linhas from public.apontamentos_horas;
    if coalesce(v_linhas, 0) <> 0 then raise exception 'a conta de TV leu % linha(s) de public.apontamentos_horas direto', v_linhas; end if;
  exception when insufficient_privilege then null;
  end;

  -- Os helpers de autorizacao tambem nao sao dela.
  begin
    perform public.fn_tv_contexto();
    raise exception 'a conta de TV executou fn_tv_contexto direto';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.fn_tv_area('mecanica');
    raise exception 'a conta de TV executou fn_tv_area direto';
  exception when insufficient_privilege then null;
  end;
end $vazamento$;
reset role;
select pg_temp.sistema();

-- =====================================================================================
-- 7. Quem nao e painel de TV nem gestao nao abre. --------------------------------------
-- =====================================================================================
create or replace function pg_temp.nao_abre(p_quem text) returns void language plpgsql as $$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_esperado text := 'Este painel é restrito ao perfil de painel de TV e à gestão.';
begin
  begin
    perform public.tv_periodos();
    raise exception '% abriu o contexto do painel', p_quem;
  exception when others then
    if sqlerrm <> v_esperado then raise exception '% em tv_periodos recebeu "%" em vez de "%"', p_quem, sqlerrm, v_esperado; end if;
  end;
  begin
    perform public.tv_colaboradores(null);
    raise exception '% leu a lista de colaboradores do painel', p_quem;
  exception when others then
    if sqlerrm <> v_esperado then raise exception '% em tv_colaboradores recebeu "%" em vez de "%"', p_quem, sqlerrm, v_esperado; end if;
  end;
  begin
    perform public.tv_colaboradores_tarefas(null);
    raise exception '% leu as tarefas do painel', p_quem;
  exception when others then
    if sqlerrm <> v_esperado then raise exception '% em tv_colaboradores_tarefas recebeu "%" em vez de "%"', p_quem, sqlerrm, v_esperado; end if;
  end;
  begin
    perform public.tv_horas_periodo(v_hoje - 7, v_hoje, null);
    raise exception '% leu as horas do painel', p_quem;
  exception when others then
    if sqlerrm <> v_esperado then raise exception '% em tv_horas_periodo recebeu "%" em vez de "%"', p_quem, sqlerrm, v_esperado; end if;
  end;
  begin
    perform public.tv_ausencias_periodo(v_hoje - 7, v_hoje, null);
    raise exception '% leu as ausencias do painel', p_quem;
  exception when others then
    if sqlerrm <> v_esperado then raise exception '% em tv_ausencias_periodo recebeu "%" em vez de "%"', p_quem, sqlerrm, v_esperado; end if;
  end;
end $$;

select pg_temp.como('1c000000-0000-4000-8000-000000000002');
set local role authenticated;
do $tecnico$ begin perform pg_temp.nao_abre('TECNICO'); end $tecnico$;
reset role;
select pg_temp.sistema();

select pg_temp.como('1c000000-0000-4000-8000-000000000004');
set local role authenticated;
do $almoxarifado$ begin perform pg_temp.nao_abre('ALMOXARIFADO'); end $almoxarifado$;
reset role;
select pg_temp.sistema();

-- =====================================================================================
-- 8. A gestao abre para conferir a tela sem trocar de conta. ---------------------------
-- =====================================================================================
create or replace function pg_temp.abre(p_papel text) returns void language plpgsql as $$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  ctx jsonb;
begin
  ctx := public.tv_periodos();
  if ctx->>'papel' <> p_papel then raise exception 'papel de % no painel: %', p_papel, ctx; end if;
  if (select count(*) from public.tv_colaboradores(null)) <> 6 then raise exception '% nao leu a lista de colaboradores', p_papel; end if;
  if (select count(*) from public.tv_colaboradores_tarefas(null)) <> 11 then raise exception '% nao leu as tarefas', p_papel; end if;
  if (select coalesce(sum(horas), 0) from public.tv_horas_periodo(v_hoje - 7, v_hoje, null)) <> 24 then raise exception '% nao leu as horas', p_papel; end if;
  if (select count(*) from public.tv_ausencias_periodo(v_hoje - 7, v_hoje + 7, null)) <> 5 then raise exception '% nao leu as ausencias', p_papel; end if;
  -- A gestao tambem chega na area nova sem trocar de conta.
  if (select count(*) from public.tv_colaboradores('engenharia')) <> 1 then raise exception '% nao leu a lista da engenharia', p_papel; end if;
end $$;

select pg_temp.como('1c000000-0000-4000-8000-000000000003');
set local role authenticated;
do $diretor$ begin perform pg_temp.abre('DIRETOR'); end $diretor$;
reset role;
select pg_temp.sistema();

select pg_temp.como('1c000000-0000-4000-8000-000000000005');
set local role authenticated;
do $coordenacao$ begin perform pg_temp.abre('COORDENACAO'); end $coordenacao$;
reset role;
select pg_temp.sistema();

select pg_temp.como('1c000000-0000-4000-8000-000000000006');
set local role authenticated;
do $admin$ begin perform pg_temp.abre('ADMIN'); end $admin$;
reset role;
select pg_temp.sistema();

-- =====================================================================================
-- 9. A coluna area aceita so as tres areas, ou nada. ----------------------------------
-- =====================================================================================
-- O check da coluna e fn_tv_area tem de andar juntos: se um dos dois ficar para
-- tras, existe area que o cadastro aceita e a TV recusa (ou o contrario), e o campo
-- Area do cadastro passa a gravar gente numa tela que nunca abre.
do $coluna$
begin
  begin
    update public.colaboradores set area = 'hidraulica' where id = '1c000000-0000-4000-8000-000000000101';
    raise exception 'check da coluna area aceitou valor invalido';
  exception when check_violation then null;
  end;
  -- Nulo continua valendo: sem area, MARCOS sai das tres frentes de trabalho.
  update public.colaboradores set area = null where id = '1c000000-0000-4000-8000-000000000101';
  if (select area from public.colaboradores where id = '1c000000-0000-4000-8000-000000000101') is not null then
    raise exception 'area nao aceitou nulo';
  end if;
  -- A terceira area passa pelo check igual as outras duas.
  update public.colaboradores set area = 'engenharia' where id = '1c000000-0000-4000-8000-000000000101';
  if (select area from public.colaboradores where id = '1c000000-0000-4000-8000-000000000101') <> 'engenharia' then
    raise exception 'a coluna area nao guardou engenharia';
  end if;
  -- Devolve o MARCOS para a mecanica, que e como o fixture o descreve.
  update public.colaboradores set area = 'mecanica' where id = '1c000000-0000-4000-8000-000000000101';
end $coluna$;

-- =====================================================================================
-- 10. Nada de dinheiro na televisao. --------------------------------------------------
-- =====================================================================================
-- A migration ja tem esta conferencia; o teste repete porque e regra da tela, e nao
-- detalhe de uma migration: a TV fica aberta no chao de fabrica e nao mostra
-- remuneracao de ninguem.
do $dinheiro$
declare
  v_nome text;
  v_def text;
  v_conferidas integer := 0;
begin
  for v_nome, v_def in
    select p.oid::regprocedure::text, pg_get_functiondef(p.oid)
    from pg_proc as p
    join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname like 'tv\_%' or p.proname like 'fn\_tv\_%')
  loop
    if v_def ilike '%valor_hora%'
       or v_def ilike '%custo_lancamento%'
       or v_def ilike '%fator_aplicado%'
       or v_def ilike '%vw_apontamentos_horas_custo%' then
      raise exception 'funcao de TV encostou em dinheiro: %', v_nome;
    end if;
    v_conferidas := v_conferidas + 1;
  end loop;

  -- Guarda contra laco vazio: as cinco RPCs do painel mais os dois helpers
  -- (fn_tv_contexto e fn_tv_area) tem de estar todas no banco.
  if v_conferidas < 7 then
    raise exception 'esperava conferir ao menos 7 funcoes de TV, conferi %', v_conferidas;
  end if;
end $dinheiro$;

rollback;
