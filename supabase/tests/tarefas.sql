\set ON_ERROR_STOP on

-- Tarefas com reserva de dia (20260912100000): criar, conflito de data,
-- reagendar, trocar colaborador, cancelar, concluir, liberar reserva,
-- permissoes por perfil, tablet, isolamento por empresa, idempotencia,
-- auditoria e o indice unico que segura a concorrencia.
--
-- Contas do fixture (tenant 1b00...0010, empresa A 1b00...0020, empresa B 1b00...0021):
--   ...0001  tablet@tarefas.test       APONTADOR sem colaborador -> conta do tablet
--   ...0002  coordenacao@tarefas.test  COORDENACAO               -> gestao
--   ...0003  tecnico@tarefas.test      TECNICO, colaborador PEDRO, responsavel da OS TAR-2
--   ...0004  pessoa@tarefas.test       APONTADOR, colaboradora ANA -> colaborador comum
--   ...0005  diretor@tarefas.test      DIRETOR                   -> gestao, autoriza tablet e PIN
--   ...0006  faturamento@tarefas.test  FATURAMENTO, responsavel da OS TAR-3 (nao e gestao)
-- Colaboradores A: ANA (...0101, pessoa), BRUNO (...0102, PIN 1234), CARLA (...0103, inativa), PEDRO (...0105, tecnico).
-- Colaborador B: ZECA (...0106).
-- OS A: TAR-1 929001 (sem responsavel), TAR-2 929002 (resp. tecnico), TAR-3 929003 (resp. faturamento),
--       TAR-4 929004 (concluida), TAR-OV 929005 (venda), TAR-HH 929006 (HH). OS B: TAR-B 929007.

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('1b000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'tablet@tarefas.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Tablet"}'::jsonb, now(), now()),
  ('1b000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'coordenacao@tarefas.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Coordenacao"}'::jsonb, now(), now()),
  ('1b000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'tecnico@tarefas.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Tecnico"}'::jsonb, now(), now()),
  ('1b000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'pessoa@tarefas.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Pessoa"}'::jsonb, now(), now()),
  ('1b000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'diretor@tarefas.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Diretor"}'::jsonb, now(), now()),
  ('1b000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'faturamento@tarefas.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Faturamento"}'::jsonb, now(), now());

insert into public.tenants (id, nome, ativo) values ('1b000000-0000-4000-8000-000000000010', 'Tenant tarefas', true);
insert into c.tenant (id, codigo, nome, ativo) values ('1b000000-0000-4000-8000-000000000010', 'TAREFAS', 'Tenant tarefas', true);
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo) values
  ('1b000000-0000-4000-8000-000000000020', '1b000000-0000-4000-8000-000000000010', 'TAR-A', 'Empresa tarefas A', 'Empresa A', '27000000000100', true),
  ('1b000000-0000-4000-8000-000000000021', '1b000000-0000-4000-8000-000000000010', 'TAR-B', 'Empresa tarefas B', 'Empresa B', '27000000000200', true);
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo) values
  ('1b000000-0000-4000-8000-000000000020', '1b000000-0000-4000-8000-000000000010', '27000000000100', 'Empresa tarefas A', 'Empresa A', true),
  ('1b000000-0000-4000-8000-000000000021', '1b000000-0000-4000-8000-000000000010', '27000000000200', 'Empresa tarefas B', 'Empresa B', true);

insert into a.usuario (id, auth_user_id, nome, email, ativo) values
  ('1b000000-0000-4000-8000-000000000041', '1b000000-0000-4000-8000-000000000001', 'Tablet da producao', 'tablet@tarefas.test', true),
  ('1b000000-0000-4000-8000-000000000042', '1b000000-0000-4000-8000-000000000002', 'Coordenacao', 'coordenacao@tarefas.test', true),
  ('1b000000-0000-4000-8000-000000000043', '1b000000-0000-4000-8000-000000000003', 'Tecnico Pedro', 'tecnico@tarefas.test', true),
  ('1b000000-0000-4000-8000-000000000044', '1b000000-0000-4000-8000-000000000004', 'Pessoa Ana', 'pessoa@tarefas.test', true),
  ('1b000000-0000-4000-8000-000000000045', '1b000000-0000-4000-8000-000000000005', 'Diretor', 'diretor@tarefas.test', true),
  ('1b000000-0000-4000-8000-000000000046', '1b000000-0000-4000-8000-000000000006', 'Faturamento', 'faturamento@tarefas.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo) values
  ('1b000000-0000-4000-8000-000000000041', '1b000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('1b000000-0000-4000-8000-000000000042', '1b000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('1b000000-0000-4000-8000-000000000043', '1b000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('1b000000-0000-4000-8000-000000000044', '1b000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('1b000000-0000-4000-8000-000000000045', '1b000000-0000-4000-8000-000000000010', 'ADMIN', true),
  ('1b000000-0000-4000-8000-000000000046', '1b000000-0000-4000-8000-000000000010', 'GESTOR', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo) values
  ('1b000000-0000-4000-8000-000000000041', '1b000000-0000-4000-8000-000000000020', 'APONTADOR', true),
  ('1b000000-0000-4000-8000-000000000042', '1b000000-0000-4000-8000-000000000020', 'COORDENACAO', true),
  ('1b000000-0000-4000-8000-000000000043', '1b000000-0000-4000-8000-000000000020', 'TECNICO', true),
  ('1b000000-0000-4000-8000-000000000044', '1b000000-0000-4000-8000-000000000020', 'APONTADOR', true),
  ('1b000000-0000-4000-8000-000000000045', '1b000000-0000-4000-8000-000000000020', 'DIRETOR', true),
  ('1b000000-0000-4000-8000-000000000046', '1b000000-0000-4000-8000-000000000020', 'FATURAMENTO', true);
insert into public.user_tenant_context (user_id, tenant_id)
select ('1b000000-0000-4000-8000-00000000000' || n)::uuid, '1b000000-0000-4000-8000-000000000010' from generate_series(1, 6) as n;
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
select ('1b000000-0000-4000-8000-00000000000' || n)::uuid, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020' from generate_series(1, 6) as n;

insert into public.colaboradores (id, nome, ativo, tenant_id, empresa_id, user_id) values
  ('1b000000-0000-4000-8000-000000000101', 'ANA', true, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', '1b000000-0000-4000-8000-000000000004'),
  ('1b000000-0000-4000-8000-000000000102', 'BRUNO', true, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', null),
  ('1b000000-0000-4000-8000-000000000103', 'CARLA', false, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', null),
  ('1b000000-0000-4000-8000-000000000105', 'PEDRO', true, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', '1b000000-0000-4000-8000-000000000003'),
  ('1b000000-0000-4000-8000-000000000106', 'ZECA', true, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000021', null);

insert into public.tipos_horas (id, codigo, descricao, fator, ativo, tenant_id) values
  ('1b000000-0000-4000-8000-000000000301', 'NORMAL', 'Hora normal', 1, true, '1b000000-0000-4000-8000-000000000010');
insert into public.colaborador_taxas (colaborador_id, valor_hora, vigencia_inicio, tenant_id, empresa_id)
select c.id, 60, '2020-01-01', c.tenant_id, c.empresa_id from public.colaboradores c where c.tenant_id = '1b000000-0000-4000-8000-000000000010';

insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social) values
  (929001, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', 'CLIENTE TAREFA', '27111111000191', 'CLIENTE TAREFA LTDA'),
  (929002, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000021', 'CLIENTE B', '27111111000192', 'CLIENTE B LTDA');
insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social, habilita_hh) values
  (929003, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', 'CLIENTE HH', '27111111000193', 'CLIENTE HH LTDA', true);

insert into public.ordens_servico (id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id, empresa_id,
  status_fluxo, tipo_documento, codigo, numero_doc, descricao_servico, orcado, responsavel_aprovacao_id, usa_relatorio_hh)
values
  (929001, 'TAR-1', 'CLIENTE TAREFA', 929001, 'em_andamento', 929001, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-TAR-001', 1, 'Montagem do painel', 100, null, false),
  (929002, 'TAR-2', 'CLIENTE TAREFA', 929001, 'em_andamento', 929002, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-TAR-002', 1, 'Manutencao (resp. tecnico)', 100, '1b000000-0000-4000-8000-000000000003', false),
  (929003, 'TAR-3', 'CLIENTE TAREFA', 929001, 'em_andamento', 929003, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-TAR-003', 1, 'Instalacao (resp. faturamento)', 100, '1b000000-0000-4000-8000-000000000006', false),
  (929004, 'TAR-4', 'CLIENTE TAREFA', 929001, 'concluida', 929004, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', 'concluida', 'OS', 'OS-TAR-004', 1, 'OS encerrada', 100, null, false),
  (929005, 'TAR-OV', 'CLIENTE TAREFA', 929001, 'em_andamento', 929005, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', 'em_andamento', 'OV', 'OV-TAR-005', 1, 'Venda', 100, null, false),
  (929006, 'TAR-HH', 'CLIENTE HH', 929003, 'em_andamento', 929006, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-TAR-006', 1, 'OS de HH', 0, null, true),
  (929007, 'TAR-B', 'CLIENTE B', 929002, 'em_andamento', 929007, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000021', 'em_andamento', 'OS', 'OS-TAR-007', 1, 'OS da empresa B', 100, null, false);

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

-- Ids das tarefas criadas ao longo do teste, para os blocos seguintes.
create temp table ids (nome text primary key, id uuid not null);
grant select, insert on ids to authenticated;

-- 1. Diretor (gestao): criar, idempotencia, conflito de dia, coexistencia, elegibilidade. --
select pg_temp.como('1b000000-0000-4000-8000-000000000005');
set local role authenticated;
do $criar$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  r jsonb;
  r2 jsonb;
  ctx jsonb;
  chave uuid := '1b000000-0000-4000-8000-0000000000c1';
begin
  ctx := public.app_tarefas_contexto();
  if not (ctx->>'gestao')::boolean or not (ctx->>'pode_criar')::boolean then raise exception 'diretor devia ser gestao: %', ctx; end if;

  -- Validacoes de entrada.
  r := public.app_tarefas_criar('qualquer', '1b000000-0000-4000-8000-000000000101', 929001, 'x', hoje);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'tipo_invalido' then raise exception 'tipo invalido aceito: %', r; end if;
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000101', 929001, 'x', null);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'data_obrigatoria' then raise exception 'agendada sem data aceita: %', r; end if;
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000101', 929001, '   ', hoje);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'descricao_obrigatoria' then raise exception 'descricao vazia aceita: %', r; end if;
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000101', 929004, 'OS encerrada', hoje);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'os_encerrada' then raise exception 'OS encerrada aceitou tarefa: %', r; end if;
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000101', 929005, 'OV', hoje);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'os_invalida' then raise exception 'OV aceitou tarefa: %', r; end if;
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000101', 929007, 'OS de outra empresa', hoje);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'os_invalida' then raise exception 'OS de outra empresa aceita: %', r; end if;
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000103', 929001, 'Inativa', hoje);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'colaborador_invalido' then raise exception 'colaboradora inativa aceita: %', r; end if;
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000106', 929001, 'Colaborador de outra empresa', hoje);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'colaborador_invalido' then raise exception 'colaborador de outra empresa aceito: %', r; end if;

  -- T1: ANA, amanha, TAR-1, com chave. Repetir a chave nao cria outra.
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000101', 929001, 'Montar painel', hoje + 1, chave);
  if not (r->>'sucesso')::boolean then raise exception 'T1 recusada: %', r; end if;
  if not (r->'tarefa'->>'reserva_ativa')::boolean or r->'tarefa'->>'situacao' <> 'pendente' then raise exception 'T1 sem reserva: %', r; end if;
  insert into ids values ('T1', (r->'tarefa'->>'id')::uuid);
  r2 := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000101', 929001, 'Montar painel', hoje + 1, chave);
  if not (r2->>'sucesso')::boolean or not (r2->>'repetido')::boolean or r2->'tarefa'->>'id' <> r->'tarefa'->>'id' then raise exception 'chave repetida criou outra tarefa: %', r2; end if;
  if (select count(*) from public.app_tarefas_listar('agendadas')) <> 1 then raise exception 'devia haver 1 tarefa agendada'; end if;

  -- ANA no mesmo dia, outra OS: bloqueado, e a gestao ve qual tarefa ocupa o dia.
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000101', 929002, 'Outra OS mesmo dia', hoje + 1);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'colaborador_reservado' then raise exception 'ANA foi agendada duas vezes no mesmo dia: %', r; end if;
  if r->'erros'->0->>'mensagem' not like 'ANA já está reservado(a) em %' then raise exception 'mensagem de conflito: %', r; end if;
  if r->'conflito'->>'numero_os' <> 'TAR-1' or (r->'conflito'->>'tarefa_id')::uuid <> (select id from ids where nome = 'T1') then raise exception 'gestao devia ver o detalhe do conflito: %', r; end if;
  if (select count(*) from public.app_tarefas_listar('todas')) <> 1 then raise exception 'conflito deixou tarefa gravada'; end if;

  -- T2: BRUNO no mesmo dia: pode (outro colaborador).
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000102', 929002, 'Manutencao', hoje + 1);
  if not (r->>'sucesso')::boolean then raise exception 'T2 recusada: %', r; end if;
  insert into ids values ('T2', (r->'tarefa'->>'id')::uuid);

  -- T3: ANA sem data, convive com a agendada.
  r := public.app_tarefas_criar('sem_data', '1b000000-0000-4000-8000-000000000101', 929002, 'Quando der, revisar o quadro', hoje + 1);
  if not (r->>'sucesso')::boolean or r->'tarefa'->>'tipo' <> 'sem_data' or r->'tarefa'->>'data' is not null or (r->'tarefa'->>'reserva_ativa')::boolean then raise exception 'T3 sem data errada: %', r; end if;
  insert into ids values ('T3', (r->'tarefa'->>'id')::uuid);

  -- T4: OS de HH aceita tarefa (a restricao de HH e do tablet de horas, nao das tarefas).
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000105', 929006, 'Acompanhar HH', hoje + 2);
  if not (r->>'sucesso')::boolean then raise exception 'T4 (HH) recusada: %', r; end if;
  insert into ids values ('T4', (r->'tarefa'->>'id')::uuid);

  -- T5: ANA em hoje+3, para os conflitos de reagendamento.
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000101', 929001, 'Teste final', hoje + 3);
  if not (r->>'sucesso')::boolean then raise exception 'T5 recusada: %', r; end if;
  insert into ids values ('T5', (r->'tarefa'->>'id')::uuid);

  -- Data no passado e permitida (registro de tarefa de ontem) e aparece como atrasada.
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000102', 929001, 'Ontem', hoje - 1);
  if not (r->>'sucesso')::boolean or not (r->'tarefa'->>'atrasada')::boolean then raise exception 'tarefa de ontem: %', r; end if;
  insert into ids values ('T_ONTEM', (r->'tarefa'->>'id')::uuid);

  r := public.app_tarefas_contar();
  if (r->>'agendadas')::int <> 5 or (r->>'sem_data')::int <> 1 or (r->>'atrasadas')::int <> 1 or (r->>'atencao')::int <> 1 then raise exception 'contadores: %', r; end if;
end $criar$;
reset role;
select pg_temp.sistema();

-- 2. Reagendar: libera o dia antigo e reserva o novo; em conflito nada muda. ------------
select pg_temp.como('1b000000-0000-4000-8000-000000000005');
set local role authenticated;
do $reagendar$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  t1 uuid := (select id from ids where nome = 'T1');
  r jsonb;
begin
  r := public.app_tarefas_reagendar(t1, hoje + 2);
  if not (r->>'sucesso')::boolean or (r->'tarefa'->>'data')::date <> hoje + 2 or not (r->'tarefa'->>'reserva_ativa')::boolean then raise exception 'reagendar T1: %', r; end if;
  if (r->'anterior'->>'data')::date <> hoje + 1 then raise exception 'reagendar devia devolver a data anterior: %', r; end if;

  -- Dia antigo liberado: BRUNO... nao, ANA pode ser agendada de novo em hoje+1? Sim, esta livre.
  -- (Confere pela lista de colaboradores: ANA livre em hoje+1, ocupada em hoje+2.)
  if (select ocupado from public.app_tarefas_colaboradores(hoje + 1) where id = '1b000000-0000-4000-8000-000000000101') then raise exception 'ANA continuou reservada no dia antigo'; end if;
  if not (select ocupado from public.app_tarefas_colaboradores(hoje + 2) where id = '1b000000-0000-4000-8000-000000000101') then raise exception 'ANA nao ficou reservada no dia novo'; end if;
  if (select ocupado_resumo from public.app_tarefas_colaboradores(hoje + 2) where id = '1b000000-0000-4000-8000-000000000101') not like 'OS TAR-1%' then raise exception 'resumo do dia ocupado para a gestao'; end if;

  -- Conflito: hoje+3 e da propria ANA (T5). T1 fica exatamente como estava.
  r := public.app_tarefas_reagendar(t1, hoje + 3);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'colaborador_reservado' then raise exception 'reagendar para dia ocupado passou: %', r; end if;
  r := public.app_tarefas_detalhe(t1);
  if (r->'tarefa'->>'data')::date <> hoje + 2 or not (r->'tarefa'->>'reserva_ativa')::boolean then raise exception 'conflito alterou T1: %', r; end if;
  if (select count(*) from public.app_tarefas_agenda(hoje + 3, hoje + 3) where tarefa_id = t1) <> 0 then raise exception 'conflito deixou reserva de T1 em hoje+3'; end if;

  -- Mesma data: nada a fazer.
  r := public.app_tarefas_reagendar(t1, hoje + 2);
  if not (r->>'sucesso')::boolean or not (r->>'repetido')::boolean then raise exception 'reagendar para a mesma data: %', r; end if;

  -- Agendada -> sem data: libera o dia.
  r := public.app_tarefas_reagendar(t1, null);
  if not (r->>'sucesso')::boolean or r->'tarefa'->>'tipo' <> 'sem_data' or r->'tarefa'->>'data' is not null or (r->'tarefa'->>'reserva_ativa')::boolean then raise exception 'T1 nao virou sem data: %', r; end if;
  if r->'tarefa'->>'reserva_liberacao_motivo' <> 'passou_para_sem_data' then raise exception 'motivo da liberacao: %', r; end if;
  if (select ocupado from public.app_tarefas_colaboradores(hoje + 2) where id = '1b000000-0000-4000-8000-000000000101') then raise exception 'sem data nao liberou o dia'; end if;

  -- Sem data -> agendada exige dia livre.
  r := public.app_tarefas_reagendar(t1, hoje + 3);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'colaborador_reservado' then raise exception 'sem data virou agendada em dia ocupado: %', r; end if;
  if (select tipo from public.app_tarefas_listar('todas') where id = t1) <> 'sem_data' then raise exception 'conflito mudou o tipo de T1'; end if;
  r := public.app_tarefas_reagendar(t1, hoje + 2);
  if not (r->>'sucesso')::boolean or r->'tarefa'->>'tipo' <> 'agendada' or not (r->'tarefa'->>'reserva_ativa')::boolean then raise exception 'sem data -> agendada em dia livre: %', r; end if;

  -- Historico de reservas de T1: 3 linhas, 1 ativa.
  r := public.app_tarefas_detalhe(t1);
  if jsonb_array_length(r->'reservas') <> 3 or (select count(*) from jsonb_array_elements(r->'reservas') as e where (e->>'ativa')::boolean) <> 1 then raise exception 'historico de reservas de T1: %', r->'reservas'; end if;
end $reagendar$;
reset role;
select pg_temp.sistema();

-- 3. Trocar colaborador e cancelar. -------------------------------------------------------
select pg_temp.como('1b000000-0000-4000-8000-000000000005');
set local role authenticated;
do $trocar$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  t1 uuid := (select id from ids where nome = 'T1');
  t2 uuid := (select id from ids where nome = 'T2');
  t6 uuid;
  r jsonb;
begin
  -- T6: BRUNO em hoje+2 (mesmo dia de T1, da ANA).
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000102', 929002, 'Bruno amanha+1', hoje + 2);
  if not (r->>'sucesso')::boolean then raise exception 'T6 recusada: %', r; end if;
  t6 := (r->'tarefa'->>'id')::uuid;
  insert into ids values ('T6', t6);

  -- T1 (ANA, hoje+2) -> BRUNO: BRUNO ja esta em hoje+2 (T6). Nada muda.
  r := public.app_tarefas_trocar_colaborador(t1, '1b000000-0000-4000-8000-000000000102');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'colaborador_reservado' then raise exception 'troca para colaborador ocupado passou: %', r; end if;
  if (select colaborador_id from public.app_tarefas_listar('todas') where id = t1) <> '1b000000-0000-4000-8000-000000000101' then raise exception 'conflito trocou o colaborador de T1'; end if;

  -- Mesmo colaborador: nada a fazer.
  r := public.app_tarefas_trocar_colaborador(t1, '1b000000-0000-4000-8000-000000000101');
  if not (r->>'sucesso')::boolean or not (r->>'repetido')::boolean then raise exception 'troca para o mesmo colaborador: %', r; end if;

  -- Inativa: recusada.
  r := public.app_tarefas_trocar_colaborador(t1, '1b000000-0000-4000-8000-000000000103');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'colaborador_invalido' then raise exception 'troca para inativa passou: %', r; end if;

  -- Cancelar T6 libera o dia e mantem o historico.
  r := public.app_tarefas_cancelar(t6, 'Cliente adiou');
  if not (r->>'sucesso')::boolean or r->'tarefa'->>'situacao' <> 'cancelada' or (r->'tarefa'->>'reserva_ativa')::boolean then raise exception 'cancelar T6: %', r; end if;
  if r->'tarefa'->>'cancelamento_motivo' <> 'Cliente adiou' or r->'tarefa'->>'cancelada_por_nome' <> 'Diretor' then raise exception 'rastro do cancelamento: %', r; end if;
  r := public.app_tarefas_detalhe(t6);
  if jsonb_array_length(r->'reservas') <> 1 or (r->'reservas'->0->>'ativa')::boolean then raise exception 'cancelar apagou a reserva: %', r->'reservas'; end if;
  if r->'reservas'->0->>'liberacao_motivo' <> 'cancelada' then raise exception 'motivo da liberacao no cancelamento: %', r->'reservas'; end if;
  r := public.app_tarefas_cancelar(t6, 'de novo');
  if not (r->>'sucesso')::boolean or not (r->>'repetido')::boolean then raise exception 'cancelar de novo devia ser repetido: %', r; end if;
  if (select count(*) from public.app_tarefas_listar('historico') where id = t6) <> 1 then raise exception 'cancelada fora do historico'; end if;
  if (select count(*) from public.app_tarefas_listar('agendadas') where id = t6) <> 0 then raise exception 'cancelada ainda nas agendadas'; end if;

  -- Agora BRUNO esta livre em hoje+2: a troca de T2 (BRUNO, hoje+1) para ANA e a de T1 para BRUNO passam.
  r := public.app_tarefas_trocar_colaborador(t1, '1b000000-0000-4000-8000-000000000102');
  if not (r->>'sucesso')::boolean or (r->'anterior'->>'colaborador_id')::uuid <> '1b000000-0000-4000-8000-000000000101' then raise exception 'troca de T1 para BRUNO: %', r; end if;
  if (select ocupado from public.app_tarefas_colaboradores(hoje + 2) where id = '1b000000-0000-4000-8000-000000000101') then raise exception 'troca nao liberou a ANA'; end if;
  if not (select ocupado from public.app_tarefas_colaboradores(hoje + 2) where id = '1b000000-0000-4000-8000-000000000102') then raise exception 'troca nao reservou o BRUNO'; end if;
  -- E volta para a ANA, para o resto do teste.
  r := public.app_tarefas_trocar_colaborador(t1, '1b000000-0000-4000-8000-000000000101');
  if not (r->>'sucesso')::boolean then raise exception 'troca de volta: %', r; end if;

  -- Alterar descricao (gestao).
  r := public.app_tarefas_alterar(t1, 'Montar painel (revisado)');
  if not (r->>'sucesso')::boolean or r->'tarefa'->>'descricao' <> 'Montar painel (revisado)' then raise exception 'alterar descricao: %', r; end if;
  r := public.app_tarefas_alterar(t6, 'nao pode');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'tarefa_encerrada' then raise exception 'alterou cancelada: %', r; end if;
end $trocar$;
reset role;
select pg_temp.sistema();

-- 4. Concluir mantem a reserva; liberar e acao explicita da gestao. -------------------------
select pg_temp.como('1b000000-0000-4000-8000-000000000005');
set local role authenticated;
do $concluir$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  t1 uuid := (select id from ids where nome = 'T1');
  t2 uuid := (select id from ids where nome = 'T2');
  chave uuid := '1b000000-0000-4000-8000-0000000000c2';
  r jsonb;
begin
  r := public.app_tarefas_concluir(t2, chave);
  if not (r->>'sucesso')::boolean or r->'tarefa'->>'situacao' <> 'concluida' or coalesce((r->>'repetido')::boolean, false) then raise exception 'concluir T2: %', r; end if;
  if not (r->'tarefa'->>'reserva_ativa')::boolean then raise exception 'concluir liberou a reserva'; end if;
  if r->'tarefa'->>'concluida_por_nome' <> 'Diretor' or (r->'tarefa'->>'concluida_pelo_tablet')::boolean then raise exception 'rastro da conclusao: %', r; end if;
  if not (select ocupado from public.app_tarefas_colaboradores(hoje + 1) where id = '1b000000-0000-4000-8000-000000000102') then raise exception 'dia de tarefa concluida devia continuar ocupado'; end if;

  -- Idempotente pela chave e pelo estado.
  r := public.app_tarefas_concluir(t2, chave);
  if not (r->>'sucesso')::boolean or not (r->>'repetido')::boolean then raise exception 'concluir com a mesma chave: %', r; end if;
  r := public.app_tarefas_concluir(t2);
  if not (r->>'sucesso')::boolean or not (r->>'repetido')::boolean then raise exception 'concluir de novo: %', r; end if;
  if (select count(*) from public.app_tarefas_listar('historico') where id = t2 and situacao = 'concluida') <> 1 then raise exception 'T2 duplicada ou nao concluida'; end if;

  -- Concluida nao cancela, nao reagenda, nao troca.
  r := public.app_tarefas_cancelar(t2);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'tarefa_concluida' then raise exception 'cancelou concluida: %', r; end if;
  r := public.app_tarefas_reagendar(t2, hoje + 9);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'tarefa_encerrada' then raise exception 'reagendou concluida: %', r; end if;
  r := public.app_tarefas_trocar_colaborador(t2, '1b000000-0000-4000-8000-000000000101');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'tarefa_encerrada' then raise exception 'trocou colaborador de concluida: %', r; end if;

  -- Liberar reserva: so de concluida; pendente usa reagendar.
  r := public.app_tarefas_liberar_reserva(t1, 'teste');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'tarefa_pendente' then raise exception 'liberou reserva de pendente: %', r; end if;
  r := public.app_tarefas_liberar_reserva(t2, 'Voltou mais cedo');
  if not (r->>'sucesso')::boolean or (r->>'liberadas')::int <> 1 or (r->'tarefa'->>'reserva_ativa')::boolean then raise exception 'liberar reserva de T2: %', r; end if;
  if r->'tarefa'->>'reserva_liberacao_motivo' <> 'Voltou mais cedo' or r->'tarefa'->>'reserva_liberada_por_nome' <> 'Diretor' then raise exception 'rastro da liberacao: %', r; end if;
  if r->'tarefa'->>'situacao' <> 'concluida' then raise exception 'liberar mudou a situacao'; end if;
  r := public.app_tarefas_liberar_reserva(t2, 'de novo');
  if not (r->>'sucesso')::boolean or not (r->>'repetido')::boolean or (r->>'liberadas')::int <> 0 then raise exception 'liberar de novo: %', r; end if;

  -- Dia liberado: BRUNO pode ser agendado em hoje+1 de novo (T7).
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000102', 929002, 'Segunda visita', hoje + 1);
  if not (r->>'sucesso')::boolean then raise exception 'T7 depois da liberacao: %', r; end if;
  insert into ids values ('T7', (r->'tarefa'->>'id')::uuid);

  -- Historico e agenda.
  if (select count(*) from public.app_tarefas_listar('historico')) <> 2 then raise exception 'historico devia ter T2 (concluida) e T6 (cancelada)'; end if;
  if (select count(*) from public.app_tarefas_listar('historico', hoje, hoje)) <> 2 then raise exception 'historico filtrado por hoje'; end if;
  if (select count(*) from public.app_tarefas_listar('historico', hoje + 1, hoje + 1)) <> 0 then raise exception 'historico filtrado por amanha'; end if;
  if (select count(*) from public.app_tarefas_agenda(hoje - 1, hoje + 5)) <> 5 then
    raise exception 'agenda devia ter 5 reservas ativas (T_ONTEM, T7, T1, T4, T5), tem %', (select count(*) from public.app_tarefas_agenda(hoje - 1, hoje + 5));
  end if;
  if (select count(*) from public.app_tarefas_agenda(hoje - 1, hoje + 5) where not detalhe_visivel) <> 0 then raise exception 'gestao devia ver todos os detalhes na agenda'; end if;
  if (select count(*) from public.app_tarefas_listar('todas', null, null, '1b000000-0000-4000-8000-000000000101')) <> 3 then raise exception 'filtro por colaborador (ANA: T1, T3, T5)'; end if;
  if (select count(*) from public.app_tarefas_listar('todas', null, null, null, 929002)) <> 4 then raise exception 'filtro por OS (TAR-2: T2, T3, T6, T7)'; end if;
  if (select count(*) from public.app_tarefas_listar('todas', null, null, null, null, 'revisado')) <> 1 then raise exception 'busca por descricao'; end if;
  begin
    perform public.app_tarefas_agenda(hoje, hoje + 200);
    raise exception 'agenda aceitou periodo enorme';
  exception when others then
    if sqlerrm not like 'Informe um período%' then raise; end if;
  end;
end $concluir$;
reset role;
select pg_temp.sistema();

-- 5. Coordenacao tambem e gestao. ---------------------------------------------------------
select pg_temp.como('1b000000-0000-4000-8000-000000000002');
set local role authenticated;
do $coord$
declare r jsonb;
begin
  r := public.app_tarefas_contexto();
  if not (r->>'gestao')::boolean then raise exception 'coordenacao devia ser gestao: %', r; end if;
  r := public.app_tarefas_criar('sem_data', '1b000000-0000-4000-8000-000000000105', 929003, 'Pedro: conferir material', null);
  if not (r->>'sucesso')::boolean or r->'tarefa'->>'criado_por_nome' <> 'Coordenacao' then raise exception 'coordenacao nao criou: %', r; end if;
  insert into ids values ('T8', (r->'tarefa'->>'id')::uuid);
  if (select count(*) from public.app_tarefas_listar('todas')) <> 9 then raise exception 'coordenacao devia ver as 9 tarefas, viu %', (select count(*) from public.app_tarefas_listar('todas')); end if;
end $coord$;
reset role;
select pg_temp.sistema();

-- 6. Responsavel da OS sem ser gestao (faturamento, TAR-3). --------------------------------
select pg_temp.como('1b000000-0000-4000-8000-000000000006');
set local role authenticated;
do $responsavel$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  t1 uuid := (select id from ids where nome = 'T1');
  r jsonb;
begin
  r := public.app_tarefas_contexto();
  if (r->>'gestao')::boolean or not (r->>'pode_criar')::boolean then raise exception 'faturamento responsavel: %', r; end if;

  -- Cria na OS dele; nao cria em OS de outro.
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000105', 929003, 'Instalar quadro', hoje + 4);
  if not (r->>'sucesso')::boolean then raise exception 'responsavel nao criou na propria OS: %', r; end if;
  insert into ids values ('T9', (r->'tarefa'->>'id')::uuid);
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000105', 929001, 'OS de outro', hoje + 5);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sem_permissao' then raise exception 'responsavel criou em OS alheia: %', r; end if;

  -- So ve as tarefas da OS dele (T8, T9).
  if (select count(*) from public.app_tarefas_listar('todas')) <> 2 then raise exception 'responsavel devia ver 2 tarefas, viu %', (select count(*) from public.app_tarefas_listar('todas')); end if;
  if (select count(*) from public.app_tarefas_os_elegiveis(null)) <> 1 then raise exception 'OS elegiveis do responsavel devia ser so TAR-3'; end if;

  -- Conflito com tarefa que ele nao pode ver: mensagem sem detalhe.
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000101', 929003, 'Ana no dia da TAR-1', hoje + 2);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'colaborador_reservado' then raise exception 'conflito nao detectado para responsavel: %', r; end if;
  if r->'conflito' is not null and jsonb_typeof(r->'conflito') <> 'null' then raise exception 'responsavel viu detalhe de tarefa alheia: %', r; end if;
  if (select ocupado_resumo from public.app_tarefas_colaboradores(hoje + 2) where id = '1b000000-0000-4000-8000-000000000101') <> 'Reservado(a) neste dia' then raise exception 'resumo do dia ocupado devia ser generico'; end if;
  if (select ocupado_tarefa_id from public.app_tarefas_colaboradores(hoje + 2) where id = '1b000000-0000-4000-8000-000000000101') is not null then raise exception 'id da tarefa alheia vazou'; end if;
  if (select count(*) from public.app_tarefas_agenda(hoje - 1, hoje + 5) where not detalhe_visivel) <> 5 then raise exception 'agenda do responsavel devia esconder 5 detalhes'; end if;
  if (select count(*) from public.app_tarefas_agenda(hoje - 1, hoje + 5) where detalhe_visivel and numero_os = 'TAR-3') <> 1 then raise exception 'agenda do responsavel devia mostrar a dele'; end if;

  -- Nao administra nem conclui tarefa de OS alheia (nem fica sabendo que existe).
  r := public.app_tarefas_cancelar(t1);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sem_permissao' then raise exception 'responsavel cancelou tarefa alheia: %', r; end if;
  r := public.app_tarefas_concluir(t1);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'tarefa_nao_encontrada' then raise exception 'responsavel concluiu tarefa alheia: %', r; end if;
  r := public.app_tarefas_detalhe(t1);
  if (r->>'sucesso')::boolean then raise exception 'responsavel abriu detalhe de tarefa alheia'; end if;
end $responsavel$;
reset role;
select pg_temp.sistema();

-- 7. Colaborador comum (ANA): so as proprias; conclui as proprias; nao administra. --------
select pg_temp.como('1b000000-0000-4000-8000-000000000004');
set local role authenticated;
do $pessoa$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  t1 uuid := (select id from ids where nome = 'T1');
  t5 uuid := (select id from ids where nome = 'T5');
  t7 uuid := (select id from ids where nome = 'T7');
  r jsonb;
begin
  r := public.app_tarefas_contexto();
  if (r->>'gestao')::boolean or (r->>'pode_criar')::boolean or (r->>'colaborador_id')::uuid <> '1b000000-0000-4000-8000-000000000101' then raise exception 'contexto da ANA: %', r; end if;

  if (select count(*) from public.app_tarefas_listar('todas')) <> 3 then raise exception 'ANA devia ver 3 tarefas (T1, T3, T5), viu %', (select count(*) from public.app_tarefas_listar('todas')); end if;
  if (select count(*) from public.app_tarefas_listar('todas') where not minha) <> 0 then raise exception 'ANA viu tarefa de outro'; end if;
  if (select count(*) from public.app_tarefas_listar('todas') where pode_gerir) <> 0 then raise exception 'ANA nao devia poder gerir'; end if;
  if (select count(*) from public.app_tarefas_listar('agendadas') where not pode_concluir) <> 0 then raise exception 'ANA devia poder concluir as proprias'; end if;
  if (select count(*) from public.app_tarefas_agenda(hoje - 1, hoje + 5)) <> 2 then raise exception 'agenda da ANA devia ter so as dela (T1, T5)'; end if;
  r := public.app_tarefas_contar();
  if (r->>'minhas_pendentes')::int <> 3 or (r->>'agendadas')::int <> 2 or (r->>'sem_data')::int <> 1 then raise exception 'contadores da ANA: %', r; end if;

  r := public.app_tarefas_criar('sem_data', '1b000000-0000-4000-8000-000000000101', 929001, 'Eu mesma', null);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sem_permissao' then raise exception 'ANA criou tarefa: %', r; end if;
  begin
    perform public.app_tarefas_colaboradores(hoje);
    raise exception 'ANA listou colaboradores para agendar';
  exception when others then
    if sqlerrm not like 'Seu perfil não cria tarefas%' then raise; end if;
  end;
  r := public.app_tarefas_cancelar(t1);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sem_permissao' then raise exception 'ANA cancelou: %', r; end if;
  r := public.app_tarefas_reagendar(t1, hoje + 8);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sem_permissao' then raise exception 'ANA reagendou: %', r; end if;
  r := public.app_tarefas_trocar_colaborador(t1, '1b000000-0000-4000-8000-000000000102');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sem_permissao' then raise exception 'ANA trocou colaborador: %', r; end if;
  r := public.app_tarefas_alterar(t1, 'outra');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sem_permissao' then raise exception 'ANA alterou descricao: %', r; end if;
  r := public.app_tarefas_liberar_reserva(t1);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sem_permissao' then raise exception 'ANA liberou reserva: %', r; end if;

  -- Conclui a propria; nao conclui a do BRUNO (nem sabe que existe).
  r := public.app_tarefas_concluir(t5);
  if not (r->>'sucesso')::boolean or r->'tarefa'->>'situacao' <> 'concluida' or r->'tarefa'->>'concluida_por_nome' <> 'Pessoa Ana' then raise exception 'ANA nao concluiu a propria: %', r; end if;
  if not (r->'tarefa'->>'reserva_ativa')::boolean then raise exception 'conclusao da ANA liberou o dia'; end if;
  r := public.app_tarefas_concluir(t7);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'tarefa_nao_encontrada' then raise exception 'ANA concluiu tarefa do BRUNO: %', r; end if;

  -- Tabela fechada para o role authenticated.
  begin
    perform count(*) from public.tarefas;
    raise exception 'authenticated leu public.tarefas direto';
  exception when insufficient_privilege then null;
  end;
end $pessoa$;
reset role;
select pg_temp.sistema();

-- 8. Tecnico: responsavel da TAR-2 e colaborador (PEDRO). ---------------------------------
select pg_temp.como('1b000000-0000-4000-8000-000000000003');
set local role authenticated;
do $tecnico$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  t8 uuid := (select id from ids where nome = 'T8');
  r jsonb;
begin
  r := public.app_tarefas_contexto();
  if (r->>'gestao')::boolean or not (r->>'pode_criar')::boolean then raise exception 'contexto do tecnico: %', r; end if;
  r := public.app_tarefas_criar('agendada', '1b000000-0000-4000-8000-000000000102', 929002, 'Bruno na TAR-2', hoje + 5);
  if not (r->>'sucesso')::boolean then raise exception 'tecnico nao criou na TAR-2: %', r; end if;
  insert into ids values ('T10', (r->'tarefa'->>'id')::uuid);
  -- Ve: TAR-2 (T2, T3, T6, T7, T10) + as proprias (T4, T8, T9) = 8.
  if (select count(*) from public.app_tarefas_listar('todas')) <> 8 then raise exception 'tecnico devia ver 8 tarefas, viu %', (select count(*) from public.app_tarefas_listar('todas')); end if;
  -- Conclui a propria mesmo sem ser responsavel da OS (T8 e da TAR-3).
  r := public.app_tarefas_concluir(t8);
  if not (r->>'sucesso')::boolean or r->'tarefa'->>'situacao' <> 'concluida' then raise exception 'tecnico nao concluiu a propria: %', r; end if;
  -- Mas nao cancela T9 (TAR-3, dele como colaborador, nao como responsavel).
  r := public.app_tarefas_cancelar((select id from ids where nome = 'T9'));
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sem_permissao' then raise exception 'tecnico cancelou tarefa de OS alheia: %', r; end if;
end $tecnico$;
reset role;
select pg_temp.sistema();

-- 9. Tablet: conta do tablet nao usa app_tarefas_*; pelo PIN ve e conclui as do colaborador. --
select pg_temp.como('1b000000-0000-4000-8000-000000000005');
set local role authenticated;
do $autorizar$
declare r jsonb;
begin
  r := public.web_tablet_salvar('1b000000-0000-4000-8000-000000000001', 'Tablet da producao', 45, true);
  if not (r->>'sucesso')::boolean then raise exception 'tablet nao autorizado: %', r; end if;
  r := public.web_tablet_pin_definir('1b000000-0000-4000-8000-000000000102', '1234');
  if not (r->>'sucesso')::boolean then raise exception 'PIN do BRUNO recusado: %', r; end if;
end $autorizar$;
reset role;
select pg_temp.sistema();

select pg_temp.como('1b000000-0000-4000-8000-000000000001');
set local role authenticated;
do $tablet$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  t1 uuid := (select id from ids where nome = 'T1');
  t7 uuid := (select id from ids where nome = 'T7');
  t10 uuid := (select id from ids where nome = 'T10');
  t_ontem uuid := (select id from ids where nome = 'T_ONTEM');
  chave uuid := '1b000000-0000-4000-8000-0000000000c3';
  r jsonb;
  token text;
begin
  begin
    perform public.app_tarefas_contexto();
    raise exception 'conta do tablet entrou nas app_tarefas_*';
  exception when others then
    if sqlerrm not like 'A conta do tablet não acessa tarefas%' then raise; end if;
  end;
  begin
    perform public.app_tarefas_listar('agendadas');
    raise exception 'conta do tablet listou tarefas';
  exception when others then
    if sqlerrm not like 'A conta do tablet não acessa tarefas%' then raise; end if;
  end;

  r := public.app_tablet_tarefas('token-invalido');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sessao_invalida' then raise exception 'token invalido listou tarefas: %', r; end if;

  r := public.app_tablet_identificar('1234');
  if not (r->>'sucesso')::boolean then raise exception 'PIN 1234 recusado: %', r; end if;
  token := r->>'sessao_token';

  r := public.app_tablet_tarefas(token);
  if not (r->>'sucesso')::boolean or r->>'colaborador_nome' <> 'BRUNO' then raise exception 'tarefas do tablet: %', r; end if;
  -- BRUNO pendentes agendadas: T_ONTEM (atrasada), T7 (hoje+1), T10 (hoje+5). Sem data: nenhuma. Concluida hoje: T2.
  if jsonb_array_length(r->'agendadas') <> 3 or jsonb_array_length(r->'sem_data') <> 0 or jsonb_array_length(r->'concluidas_hoje') <> 1 then raise exception 'listas do BRUNO no tablet: %', r; end if;
  if not (r->'agendadas'->0->>'atrasada')::boolean or (r->'agendadas'->0->>'id')::uuid <> t_ontem then raise exception 'atrasada devia vir primeiro: %', r->'agendadas'; end if;
  if r->'agendadas'->1->>'numero_os' <> 'TAR-2' or r->'agendadas'->1->>'cliente_nome' <> 'CLIENTE TAREFA' then raise exception 'dados da OS no tablet: %', r->'agendadas'->1; end if;

  -- Conclui T7 com chave; repete com a mesma chave e sem chave: nada grava de novo.
  r := public.app_tablet_tarefa_concluir(token, t7, chave);
  if not (r->>'sucesso')::boolean or (r->>'repetido')::boolean or r->'tarefa'->>'situacao' <> 'concluida' then raise exception 'concluir pelo tablet: %', r; end if;
  r := public.app_tablet_tarefa_concluir(token, t7, chave);
  if not (r->>'sucesso')::boolean or not (r->>'repetido')::boolean then raise exception 'concluir pelo tablet com a mesma chave: %', r; end if;
  r := public.app_tablet_tarefa_concluir(token, t7, null);
  if not (r->>'sucesso')::boolean or not (r->>'repetido')::boolean then raise exception 'concluir pelo tablet de novo: %', r; end if;

  -- Tarefa de outro colaborador: nao e dele.
  r := public.app_tablet_tarefa_concluir(token, t1, null);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'tarefa_nao_encontrada' then raise exception 'tablet concluiu tarefa de outro: %', r; end if;

  r := public.app_tablet_tarefas(token);
  if jsonb_array_length(r->'agendadas') <> 2 or jsonb_array_length(r->'concluidas_hoje') <> 2 then raise exception 'listas depois de concluir: %', r; end if;

  -- Sessao encerrada nao serve mais.
  perform public.app_tablet_encerrar(token, 'finalizado');
  r := public.app_tablet_tarefas(token);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sessao_invalida' then raise exception 'sessao encerrada ainda lista tarefas: %', r; end if;
  r := public.app_tablet_tarefa_concluir(token, t10, null);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sessao_invalida' then raise exception 'sessao encerrada ainda conclui: %', r; end if;
end $tablet$;
reset role;
select pg_temp.sistema();

-- A conclusao pelo tablet fica amarrada a sessao do PIN e mantem a reserva.
do $rastro$
declare
  t7 uuid := (select id from ids where nome = 'T7');
  v public.tarefas;
begin
  select * into v from public.tarefas where id = t7;
  if v.concluida_por_sessao_id is null or v.concluida_por_user_id <> '1b000000-0000-4000-8000-000000000001' then raise exception 'conclusao do tablet sem sessao/conta'; end if;
  if (select count(*) from public.tarefas_reservas where tarefa_id = t7 and liberada_em is null) <> 1 then raise exception 'conclusao pelo tablet liberou a reserva'; end if;
end $rastro$;

select pg_temp.como('1b000000-0000-4000-8000-000000000005');
set local role authenticated;
do $rastro_gestao$
declare
  t7 uuid := (select id from ids where nome = 'T7');
  r jsonb;
begin
  r := public.app_tarefas_detalhe(t7);
  if not (r->'tarefa'->>'concluida_pelo_tablet')::boolean or r->'tarefa'->>'concluida_por_nome' <> 'BRUNO (pelo tablet)' then raise exception 'rastro do tablet na lista: %', r->'tarefa'; end if;
end $rastro_gestao$;
reset role;
select pg_temp.sistema();

-- 10. Isolamento por empresa: tarefa da empresa B nao aparece nem se conclui pela A. --------
insert into public.tarefas (id, tenant_id, empresa_id, os_id, tipo, data, descricao)
values ('1b000000-0000-4000-8000-0000000000b1', '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000021', 929007, 'agendada', (now() at time zone 'America/Sao_Paulo')::date + 1, 'Tarefa da empresa B');
insert into public.tarefas_participantes (tarefa_id, colaborador_id)
values ('1b000000-0000-4000-8000-0000000000b1', '1b000000-0000-4000-8000-000000000106');
insert into public.tarefas_reservas (tenant_id, empresa_id, tarefa_id, colaborador_id, data)
values ('1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000021', '1b000000-0000-4000-8000-0000000000b1', '1b000000-0000-4000-8000-000000000106', (now() at time zone 'America/Sao_Paulo')::date + 1);

select pg_temp.como('1b000000-0000-4000-8000-000000000005');
set local role authenticated;
do $isolamento$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  r jsonb;
begin
  if (select count(*) from public.app_tarefas_listar('todas') where id = '1b000000-0000-4000-8000-0000000000b1') <> 0 then raise exception 'tarefa da empresa B apareceu na A'; end if;
  if (select count(*) from public.app_tarefas_agenda(hoje + 1, hoje + 1) where colaborador_nome = 'ZECA') <> 0 then raise exception 'reserva da empresa B apareceu na agenda da A'; end if;
  r := public.app_tarefas_concluir('1b000000-0000-4000-8000-0000000000b1');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'tarefa_nao_encontrada' then raise exception 'diretor da A concluiu tarefa da B: %', r; end if;
  r := public.app_tarefas_cancelar('1b000000-0000-4000-8000-0000000000b1');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'tarefa_nao_encontrada' then raise exception 'diretor da A cancelou tarefa da B: %', r; end if;
  if (select count(*) from public.app_tarefas_colaboradores(hoje + 1) where nome = 'ZECA') <> 0 then raise exception 'colaborador da B listado na A'; end if;
end $isolamento$;
reset role;
select pg_temp.sistema();

-- 11. Concorrencia: o indice unico segura o segundo pedido mesmo por fora das funcoes. ----
do $indice$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  t1 uuid := (select id from ids where nome = 'T1');
begin
  begin
    insert into public.tarefas_reservas (tenant_id, empresa_id, tarefa_id, colaborador_id, data)
    values ('1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', t1, '1b000000-0000-4000-8000-000000000101', hoje + 2);
    raise exception 'indice unico deixou duplicar a reserva de ANA em hoje+2';
  exception when unique_violation then null;
  end;
  -- Reserva liberada nao conta: pode existir outra ativa no mesmo dia.
  if (select count(*) from public.tarefas_reservas where colaborador_id = '1b000000-0000-4000-8000-000000000101' and data = hoje + 2) < 2 then
    raise exception 'historico de reservas da ANA em hoje+2 devia ter a liberada e a ativa';
  end if;

  -- A mesma pessoa (usuario) nao pode ser reservada duas vezes no mesmo dia,
  -- mesmo que apareca como dois colaboradores (hoje colaboradores.user_id e
  -- unico, mas a reserva nao depende disso para valer).
  begin
    insert into public.tarefas_reservas (tenant_id, empresa_id, tarefa_id, colaborador_id, usuario_id, data)
    values ('1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', t1, '1b000000-0000-4000-8000-000000000102', '1b000000-0000-4000-8000-000000000004', hoje + 2);
    raise exception 'indice por usuario deixou reservar a mesma pessoa duas vezes em hoje+2';
  exception when unique_violation then null;
  end;
end $indice$;

-- 11b. Tarefa nao gera hora, e o apontamento normal segue independente. ---------------------
select pg_temp.como('1b000000-0000-4000-8000-000000000005');
set local role authenticated;
do $independencia$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  t1 uuid := (select id from ids where nome = 'T1');
  r jsonb;
  apontamento_id uuid;
begin
  -- Nenhuma das operacoes acima (criar, concluir, cancelar) lancou hora.
  if (select count(*) from public.apontamentos_horas where tenant_id = '1b000000-0000-4000-8000-000000000010') <> 0 then
    raise exception 'tarefa gerou apontamento de horas';
  end if;

  -- E lancar hora continua funcionando com tarefas no mesmo dia/colaborador/OS.
  r := public.web_criar_apontamentos_horas(jsonb_build_array(jsonb_build_object(
    'os_id', 929001, 'colaborador_id', '1b000000-0000-4000-8000-000000000101', 'data', hoje, 'horas', 4,
    'tipo_hora_id', '1b000000-0000-4000-8000-000000000301', 'descricao', 'Hora lancada no dia da tarefa', 'confirmar_os_encerrada', false)));
  if not (r->>'sucesso')::boolean then raise exception 'apontamento normal recusado com tarefa no mesmo dia: %', r; end if;
  select id into apontamento_id from public.apontamentos_horas
   where tenant_id = '1b000000-0000-4000-8000-000000000010' and os_id = 929001 limit 1;
  if apontamento_id is null then raise exception 'apontamento nao gravou'; end if;

  -- A tarefa nao foi tocada pelo apontamento.
  if (select situacao from public.app_tarefas_listar('todas') where id = t1) <> 'pendente' then
    raise exception 'o apontamento mexeu na tarefa';
  end if;
end $independencia$;
reset role;
select pg_temp.sistema();

-- 11c. Aprovacao de horas segue intacta: quem aprova e o responsavel da OS. ----------------
select pg_temp.como('1b000000-0000-4000-8000-000000000003');
set local role authenticated;
do $aprovacao$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  r jsonb;
  apontamento_id uuid;
  pendentes integer;
begin
  -- O tecnico e responsavel da TAR-2: lanca uma hora la e ela cai na fila dele.
  r := public.web_criar_apontamentos_horas(jsonb_build_array(jsonb_build_object(
    'os_id', 929002, 'colaborador_id', '1b000000-0000-4000-8000-000000000102', 'data', hoje, 'horas', 2,
    'tipo_hora_id', '1b000000-0000-4000-8000-000000000301', 'descricao', 'Hora para aprovar', 'confirmar_os_encerrada', false)));
  if not (r->>'sucesso')::boolean then raise exception 'lancamento na TAR-2 recusado: %', r; end if;

  pendentes := public.app_contar_aprovacoes_pendentes();
  if pendentes < 1 then raise exception 'a hora nao entrou na fila de aprovacao do responsavel (%).', pendentes; end if;

  select id into apontamento_id from public.app_listar_aprovacoes_pendentes() limit 1;
  if apontamento_id is null then raise exception 'app_listar_aprovacoes_pendentes vazia'; end if;

  perform public.aprovar_apontamento(apontamento_id);
  if (select status_aprovacao from public.apontamentos_horas where id = apontamento_id) <> 'aprovado' then
    raise exception 'aprovar_apontamento nao aprovou';
  end if;
  if public.app_contar_aprovacoes_pendentes() <> pendentes - 1 then
    raise exception 'a fila de aprovacao nao diminuiu depois de aprovar';
  end if;
end $aprovacao$;
reset role;
select pg_temp.sistema();

-- Rejeitar tambem continua: outra hora, recusada com motivo.
select pg_temp.como('1b000000-0000-4000-8000-000000000003');
set local role authenticated;
do $rejeicao$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  r jsonb;
  apontamento_id uuid;
begin
  r := public.web_criar_apontamentos_horas(jsonb_build_array(jsonb_build_object(
    'os_id', 929002, 'colaborador_id', '1b000000-0000-4000-8000-000000000105', 'data', hoje, 'horas', 3,
    'tipo_hora_id', '1b000000-0000-4000-8000-000000000301', 'descricao', 'Hora para recusar', 'confirmar_os_encerrada', false)));
  if not (r->>'sucesso')::boolean then raise exception 'segundo lancamento recusado: %', r; end if;
  select id into apontamento_id from public.app_listar_aprovacoes_pendentes() limit 1;
  perform public.rejeitar_apontamento(apontamento_id, 'Hora fora do combinado');
  if (select status_aprovacao from public.apontamentos_horas where id = apontamento_id) <> 'rejeitado' then
    raise exception 'rejeitar_apontamento nao rejeitou';
  end if;
  if (select motivo_devolucao from public.apontamentos_horas where id = apontamento_id) <> 'Hora fora do combinado' then
    raise exception 'motivo da recusa nao gravou';
  end if;
end $rejeicao$;
reset role;
select pg_temp.sistema();

-- 12. Auditoria: tarefas e reservas passam pelo audit_log com quem fez. ----------------------
do $auditoria$
begin
  if (select count(*) from public.audit_log where table_name = 'tarefas' and tenant_id = '1b000000-0000-4000-8000-000000000010' and action = 'INSERT') < 10 then raise exception 'audit_log sem os inserts de tarefas'; end if;
  if (select count(*) from public.audit_log where table_name = 'tarefas' and tenant_id = '1b000000-0000-4000-8000-000000000010' and action = 'UPDATE' and new_data->>'situacao' = 'cancelada' and actor_user_id = '1b000000-0000-4000-8000-000000000005') <> 1 then raise exception 'audit_log sem o cancelamento pelo diretor'; end if;
  if (select count(*) from public.audit_log where table_name = 'tarefas_reservas' and tenant_id = '1b000000-0000-4000-8000-000000000010' and action = 'UPDATE' and new_data->>'liberacao_motivo' = 'reagendada') < 1 then raise exception 'audit_log sem a liberacao por reagendamento'; end if;
  -- A conclusao agora mora no participante: e la que fica o rastro da sessao do
  -- PIN. A tarefa so vira 'concluida' quando a ultima parte fecha, e ai o autor
  -- daquele update e quem fechou por ultimo.
  if (select count(*) from public.audit_log
      where table_name = 'tarefas_participantes' and action = 'UPDATE'
        and new_data->>'concluida_em' is not null
        and new_data->>'concluida_por_sessao_id' is not null
        and actor_user_id = '1b000000-0000-4000-8000-000000000001') <> 1 then
    raise exception 'audit_log sem a conclusao pelo tablet';
  end if;
  if (select count(*) from public.audit_log
      where table_name = 'tarefas' and action = 'UPDATE'
        and new_data->>'situacao' = 'concluida'
        and actor_user_id = '1b000000-0000-4000-8000-000000000001') < 1 then
    raise exception 'audit_log sem a tarefa fechando pelo tablet';
  end if;
end $auditoria$;

-- 13. Modelo novo (20260912220000): varias pessoas, dias, ausencia e compat. ----------------
--
-- As datas daqui para frente saem do banco: a primeira segunda-feira util a partir
-- de hoje+10. Segunda-feira para o intervalo de dois dias cair em dois dias uteis,
-- e depois de hoje+5 porque as secoes anteriores nao reservaram nada la. Assim o
-- teste nao depende do dia da semana em que roda.

-- 13a. Varios participantes de uma vez, duracao em dias e conflito parcial. -----------------
select pg_temp.como('1b000000-0000-4000-8000-000000000005');
set local role authenticated;
do $varios$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_seg date;
  v_ana uuid := '1b000000-0000-4000-8000-000000000101';
  v_bruno uuid := '1b000000-0000-4000-8000-000000000102';
  v_pedro uuid := '1b000000-0000-4000-8000-000000000105';
  t_varios uuid;
  t_dias uuid;
  t_bloq uuid;
  r jsonb;
begin
  select d::date into v_seg
  from generate_series(v_hoje + 10, v_hoje + 24, interval '1 day') as s(d)
  where extract(dow from d) = 1
    and not exists (select 1 from public.feriados as f where f.data = d::date)
  order by d
  limit 1;
  if v_seg is null then raise exception 'nao achei uma segunda-feira util a partir de hoje+10'; end if;

  -- T_VARIOS: ANA, BRUNO e PEDRO na mesma tarefa, de uma vez, um dia.
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana, v_bruno, v_pedro],
    p_tipo => 'agendada',
    p_data => v_seg + 7,
    p_dias => 1,
    p_descricao => 'Montagem a tres',
    p_categoria => 'os',
    p_os_id => 929001);
  if not (r->>'sucesso')::boolean then raise exception 'T_VARIOS recusada: %', r; end if;
  t_varios := (r->'tarefa'->>'id')::uuid;
  insert into ids values ('T_VARIOS', t_varios);
  if (r->'tarefa'->>'participantes')::int <> 3 then raise exception 'T_VARIOS devia nascer com 3 participantes: %', r; end if;
  if (r->'tarefa'->>'dias')::int <> 1 or r->'tarefa'->>'categoria' <> 'os' or r->'tarefa'->>'medida' <> 'dias' then raise exception 'T_VARIOS: %', r; end if;

  r := public.app_tarefas_detalhe(t_varios);
  if jsonb_array_length(r->'participantes') <> 3 then raise exception 'devia haver 3 linhas em tarefas_participantes: %', r->'participantes'; end if;
  if jsonb_array_length(r->'reservas') <> 3 then raise exception 'devia haver 3 reservas, uma por pessoa: %', r->'reservas'; end if;
  if (select count(distinct e->>'colaborador_id') from jsonb_array_elements(r->'reservas') as e) <> 3 then raise exception 'as 3 reservas deviam ser de pessoas diferentes: %', r->'reservas'; end if;
  if (select count(*) from jsonb_array_elements(r->'reservas') as e where (e->>'data')::date <> v_seg + 7 or not (e->>'ativa')::boolean) <> 0 then raise exception 'reservas de T_VARIOS fora do dia ou inativas: %', r->'reservas'; end if;
  -- Leitura: uma linha por participante.
  if (select count(*) from public.app_tarefas_listar('agendadas') where id = t_varios) <> 3 then raise exception 'T_VARIOS devia aparecer 3 vezes, uma por participante'; end if;
  if (select count(distinct colaborador_id) from public.app_tarefas_listar('agendadas') where id = t_varios) <> 3 then raise exception 'as 3 linhas de T_VARIOS deviam ser de pessoas diferentes'; end if;

  -- T_DIAS: duas pessoas por dois dias. Reservas = pessoas x dias.
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana, v_bruno],
    p_tipo => 'agendada',
    p_data => v_seg,
    p_dias => 2,
    p_descricao => 'Parada de dois dias',
    p_categoria => 'os',
    p_os_id => 929002);
  if not (r->>'sucesso')::boolean then raise exception 'T_DIAS recusada: %', r; end if;
  t_dias := (r->'tarefa'->>'id')::uuid;
  insert into ids values ('T_DIAS', t_dias);
  if (r->'tarefa'->>'dias')::int <> 2 or (r->'tarefa'->>'data_fim')::date <> v_seg + 1 then raise exception 'T_DIAS devia ocupar v_seg e v_seg+1: %', r; end if;

  r := public.app_tarefas_detalhe(t_dias);
  if jsonb_array_length(r->'reservas') <> 4 then raise exception 'duas pessoas por dois dias sao 4 reservas: %', r->'reservas'; end if;
  if (select count(*) from jsonb_array_elements(r->'reservas') as e where e->>'colaborador_id' = v_ana::text) <> 2 then raise exception 'ANA devia ter os dois dias reservados: %', r->'reservas'; end if;
  if (select count(*) from jsonb_array_elements(r->'reservas') as e where e->>'colaborador_id' = v_bruno::text) <> 2 then raise exception 'BRUNO devia ter os dois dias reservados: %', r->'reservas'; end if;
  if (select count(*) from public.app_tarefas_colaboradores(v_seg + 1) where id in (v_ana, v_bruno) and ocupado) <> 2 then raise exception 'o segundo dia do intervalo devia ficar ocupado para as duas'; end if;

  -- O dia do meio do intervalo esta reservado de verdade.
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana], p_tipo => 'agendada', p_data => v_seg + 1, p_dias => 1,
    p_descricao => 'Dia de dentro do intervalo', p_categoria => 'os', p_os_id => 929001);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'colaborador_reservado' then raise exception 'agendou dentro do intervalo de T_DIAS: %', r; end if;
  if (r->'conflito'->>'tarefa_id')::uuid <> t_dias or r->'conflito'->>'descricao' <> 'Parada de dois dias' then raise exception 'o conflito devia apontar T_DIAS: %', r; end if;

  -- T_BLOQ: BRUNO sozinho no dia em que o conflito parcial vai bater.
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_bruno], p_tipo => 'agendada', p_data => v_seg + 8, p_dias => 1,
    p_descricao => 'Bruno ja tem esse dia', p_categoria => 'os', p_os_id => 929001);
  if not (r->>'sucesso')::boolean then raise exception 'T_BLOQ recusada: %', r; end if;
  t_bloq := (r->'tarefa'->>'id')::uuid;
  insert into ids values ('T_BLOQ', t_bloq);

  -- Conflito parcial: um dia ocupado de UMA pessoa derruba a criacao inteira. O
  -- erro e o jsonb de fn_tarefas_erro mais conflito, data e colaborador_id.
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana, v_bruno, v_pedro], p_tipo => 'agendada', p_data => v_seg + 8, p_dias => 1,
    p_descricao => 'Conflito parcial: nao deve nascer', p_categoria => 'os', p_os_id => 929002);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'colaborador_reservado' then raise exception 'conflito parcial passou: %', r; end if;
  if r->'erros'->0->>'mensagem' not like 'BRUNO já está reservado(a) em %' then raise exception 'mensagem do conflito parcial: %', r; end if;
  if (r->>'colaborador_id')::uuid <> v_bruno or (r->>'data')::date <> v_seg + 8 then raise exception 'o erro devia dizer quem e o dia: %', r; end if;
  if (r->'conflito'->>'tarefa_id')::uuid <> t_bloq or r->'conflito'->>'categoria' <> 'os' or r->'conflito'->>'numero_os' <> 'TAR-1' then raise exception 'detalhe do conflito parcial: %', r; end if;
  if jsonb_typeof(r->'avisos') <> 'array' then raise exception 'o erro devia trazer avisos: %', r; end if;
  -- Nada gravado: nem a tarefa, nem a reserva de quem vinha antes do BRUNO.
  if (select count(*) from public.app_tarefas_listar('todas') where descricao = 'Conflito parcial: nao deve nascer') <> 0 then raise exception 'conflito parcial gravou a tarefa'; end if;
  if (select count(*) from public.app_tarefas_colaboradores(v_seg + 8) where id in (v_ana, v_pedro) and ocupado) <> 0 then raise exception 'conflito parcial deixou reserva das outras pessoas'; end if;
end $varios$;
reset role;
select pg_temp.sistema();

-- 13b. Quem decide os dias e fn_tarefas_dias (helper: so o dono das funcoes chama). ---------
do $dias_reservados$
declare
  t_dias uuid := (select id from ids where nome = 'T_DIAS');
  t_varios uuid := (select id from ids where nome = 'T_VARIOS');
  v public.tarefas;
  v_conf date;
  v_dias integer;
  v_pessoas integer;
  v_ativas integer;
begin
  select * into v from public.tarefas where id = t_dias;
  select count(*) into v_dias from public.fn_tarefas_dias(v.data, v.dias, v.medida);
  if v_dias <> 2 then raise exception 'fn_tarefas_dias devia dar 2 dias para dias = 2, deu %', v_dias; end if;
  select count(*) into v_pessoas from public.tarefas_participantes where tarefa_id = t_dias;
  select count(*) into v_ativas from public.tarefas_reservas where tarefa_id = t_dias and liberada_em is null;
  if v_ativas <> v_pessoas * v_dias then raise exception 'reservas de T_DIAS: % (esperado % pessoas x % dias)', v_ativas, v_pessoas, v_dias; end if;
  -- Os dias reservados sao exatamente os que fn_tarefas_dias manda, nem mais nem menos.
  if exists (
       select 1 from public.tarefas_reservas as r
       where r.tarefa_id = t_dias and r.liberada_em is null
         and r.data not in (select s.dia from public.fn_tarefas_dias(v.data, v.dias, v.medida) as s(dia))
     ) or exists (
       select 1 from public.fn_tarefas_dias(v.data, v.dias, v.medida) as s(dia)
       where not exists (select 1 from public.tarefas_reservas as r
                         where r.tarefa_id = t_dias and r.liberada_em is null and r.data = s.dia)
     ) then
    raise exception 'as reservas de T_DIAS nao batem com fn_tarefas_dias';
  end if;

  -- Tarefa de um dia: um dia por pessoa.
  select * into v from public.tarefas where id = t_varios;
  select count(*) into v_dias from public.fn_tarefas_dias(v.data, v.dias, v.medida);
  select count(*) into v_ativas from public.tarefas_reservas where tarefa_id = t_varios and liberada_em is null;
  if v_dias <> 1 or v_ativas <> 3 then raise exception 'T_VARIOS: % dias e % reservas', v_dias, v_ativas; end if;

  -- O conflito parcial nao deixou rastro nenhum no dia do BRUNO.
  select t.data into v_conf from public.tarefas as t where t.id = (select id from ids where nome = 'T_BLOQ');
  if exists (select 1 from public.tarefas where descricao = 'Conflito parcial: nao deve nascer') then
    raise exception 'conflito parcial gravou tarefa';
  end if;
  if (select count(*) from public.tarefas_reservas
      where tenant_id = '1b000000-0000-4000-8000-000000000010' and data = v_conf and liberada_em is null) <> 1 then
    raise exception 'o dia do conflito devia ter so a reserva do BRUNO';
  end if;
  if (select count(*) from public.tarefas_participantes as p
      join public.tarefas as t on t.id = p.tarefa_id
      where t.tenant_id = '1b000000-0000-4000-8000-000000000010' and t.data = v_conf) <> 1 then
    raise exception 'o conflito parcial deixou participante gravado';
  end if;
end $dias_reservados$;

-- 13c. Entrar e sair da tarefa: quem entra reserva os dias dele, quem sai libera. ----------
select pg_temp.como('1b000000-0000-4000-8000-000000000005');
set local role authenticated;
do $entra_sai$
declare
  t_dias uuid := (select id from ids where nome = 'T_DIAS');
  t_meio uuid;
  t_solo uuid;
  v_inicio date;
  v_ana uuid := '1b000000-0000-4000-8000-000000000101';
  v_bruno uuid := '1b000000-0000-4000-8000-000000000102';
  v_carla uuid := '1b000000-0000-4000-8000-000000000103';
  v_pedro uuid := '1b000000-0000-4000-8000-000000000105';
  r jsonb;
begin
  v_inicio := (public.app_tarefas_detalhe(t_dias)->'tarefa'->>'data')::date;

  -- PEDRO entra: reserva os DOIS dias dele.
  r := public.app_tarefas_adicionar_participante(t_dias, v_pedro);
  if not (r->>'sucesso')::boolean then raise exception 'PEDRO nao entrou em T_DIAS: %', r; end if;
  if (r->'tarefa'->>'participantes')::int <> 3 then raise exception 'T_DIAS devia ficar com 3 participantes: %', r; end if;
  r := public.app_tarefas_detalhe(t_dias);
  if jsonb_array_length(r->'participantes') <> 3 then raise exception 'participantes de T_DIAS: %', r->'participantes'; end if;
  if (select count(*) from jsonb_array_elements(r->'reservas') as e where e->>'colaborador_id' = v_pedro::text and (e->>'ativa')::boolean) <> 2 then raise exception 'entrar devia reservar os dois dias de PEDRO: %', r->'reservas'; end if;
  if (select count(*) from jsonb_array_elements(r->'reservas') as e where (e->>'ativa')::boolean) <> 6 then raise exception 'T_DIAS devia ter 6 reservas ativas (3 pessoas x 2 dias): %', r->'reservas'; end if;
  if (select count(*) from public.app_tarefas_listar('agendadas') where id = t_dias) <> 3 then raise exception 'a linha nova de PEDRO nao apareceu na lista'; end if;

  -- Entrar de novo: repetido, sem reservar duas vezes.
  r := public.app_tarefas_adicionar_participante(t_dias, v_pedro);
  if not (r->>'sucesso')::boolean or not (r->>'repetido')::boolean then raise exception 'entrar duas vezes: %', r; end if;
  if (select count(*) from jsonb_array_elements(public.app_tarefas_detalhe(t_dias)->'reservas') as e where (e->>'ativa')::boolean) <> 6 then raise exception 'entrar de novo reservou outra vez'; end if;

  -- PEDRO sai: libera os dias dele e deixa o historico com o motivo.
  r := public.app_tarefas_remover_participante(t_dias, v_pedro);
  if not (r->>'sucesso')::boolean then raise exception 'PEDRO nao saiu de T_DIAS: %', r; end if;
  r := public.app_tarefas_detalhe(t_dias);
  if jsonb_array_length(r->'participantes') <> 2 then raise exception 'T_DIAS devia voltar a 2 participantes: %', r->'participantes'; end if;
  if (select count(*) from jsonb_array_elements(r->'reservas') as e where e->>'colaborador_id' = v_pedro::text and (e->>'ativa')::boolean) <> 0 then raise exception 'sair nao liberou os dias de PEDRO: %', r->'reservas'; end if;
  if (select count(*) from jsonb_array_elements(r->'reservas') as e where e->>'colaborador_id' = v_pedro::text and e->>'liberacao_motivo' = 'saiu_da_tarefa') <> 2 then raise exception 'motivo da liberacao de quem saiu: %', r->'reservas'; end if;
  if (select count(*) from public.app_tarefas_colaboradores(v_inicio) where id = v_pedro and ocupado) <> 0 then raise exception 'PEDRO continuou reservado depois de sair'; end if;

  -- Quem nao participa nao sai; inativa nao entra.
  r := public.app_tarefas_remover_participante(t_dias, v_pedro);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'participante_invalido' then raise exception 'removeu quem nao participa: %', r; end if;
  r := public.app_tarefas_adicionar_participante(t_dias, v_carla);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'colaborador_invalido' then raise exception 'colaboradora inativa entrou na tarefa: %', r; end if;

  -- Um unico dia ocupado tambem derruba a entrada: PEDRO no segundo dia da parada.
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_pedro], p_tipo => 'agendada', p_data => v_inicio + 1, p_dias => 1,
    p_descricao => 'Pedro no segundo dia', p_categoria => 'os', p_os_id => 929001);
  if not (r->>'sucesso')::boolean then raise exception 'T_MEIO recusada: %', r; end if;
  t_meio := (r->'tarefa'->>'id')::uuid;
  insert into ids values ('T_MEIO', t_meio);
  r := public.app_tarefas_adicionar_participante(t_dias, v_pedro);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'colaborador_reservado' then raise exception 'PEDRO entrou com um dos dias ocupado: %', r; end if;
  if (r->>'data')::date <> v_inicio + 1 or (r->'conflito'->>'tarefa_id')::uuid <> t_meio then raise exception 'o conflito da entrada devia ser o segundo dia: %', r; end if;
  r := public.app_tarefas_detalhe(t_dias);
  if jsonb_array_length(r->'participantes') <> 2 then raise exception 'a entrada recusada deixou PEDRO na tarefa: %', r->'participantes'; end if;
  if (select count(*) from jsonb_array_elements(r->'reservas') as e where e->>'colaborador_id' = v_pedro::text and (e->>'ativa')::boolean) <> 0 then raise exception 'a entrada recusada deixou reserva do primeiro dia: %', r->'reservas'; end if;

  -- T_SOLO: uma pessoa so. Remover o ultimo participante e recusado.
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_bruno], p_tipo => 'agendada', p_data => v_inicio + 14, p_dias => 1,
    p_descricao => 'Bruno sozinho', p_categoria => 'os', p_os_id => 929001);
  if not (r->>'sucesso')::boolean then raise exception 'T_SOLO recusada: %', r; end if;
  t_solo := (r->'tarefa'->>'id')::uuid;
  insert into ids values ('T_SOLO', t_solo);
  r := public.app_tarefas_remover_participante(t_solo, v_bruno);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'ultimo_participante' then raise exception 'removeu o ultimo participante: %', r; end if;
  if (select count(*) from public.app_tarefas_listar('agendadas') where id = t_solo) <> 1 then raise exception 'a recusa mexeu em T_SOLO'; end if;
  if not (select reserva_ativa from public.app_tarefas_listar('agendadas') where id = t_solo) then raise exception 'a recusa liberou a reserva de T_SOLO'; end if;

  if (select count(*) from public.app_tarefas_listar('agendadas') where id = t_dias and colaborador_id = v_ana) <> 1 then raise exception 'ANA devia continuar em T_DIAS'; end if;
end $entra_sai$;
reset role;
select pg_temp.sistema();

-- Colaborador comum nao mexe em quem participa e so fecha a propria parte.
select pg_temp.como('1b000000-0000-4000-8000-000000000004');
set local role authenticated;
do $parte_da_ana$
declare
  t_dias uuid := (select id from ids where nome = 'T_DIAS');
  v_ana uuid := '1b000000-0000-4000-8000-000000000101';
  v_bruno uuid := '1b000000-0000-4000-8000-000000000102';
  v_pedro uuid := '1b000000-0000-4000-8000-000000000105';
  r jsonb;
begin
  r := public.app_tarefas_adicionar_participante(t_dias, v_pedro);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sem_permissao' then raise exception 'ANA colocou gente na tarefa: %', r; end if;
  r := public.app_tarefas_remover_participante(t_dias, v_bruno);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sem_permissao' then raise exception 'ANA tirou gente da tarefa: %', r; end if;
  -- A parte do outro nao e dela.
  r := public.app_tarefas_concluir(t_dias, null, v_bruno);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sem_permissao' then raise exception 'ANA fechou a parte do BRUNO: %', r; end if;
  -- A dela e: fecha sem p_colaborador_id, e a tarefa continua pendente pelo BRUNO.
  r := public.app_tarefas_concluir(t_dias);
  if not (r->>'sucesso')::boolean or (r->>'colaborador_id')::uuid <> v_ana then raise exception 'ANA nao fechou a propria parte: %', r; end if;
  if r->'tarefa'->>'situacao' <> 'pendente' then raise exception 'a parte da ANA fechou a tarefa toda: %', r; end if;
  if (select count(*) from public.app_tarefas_listar('agendadas') where id = t_dias and pode_concluir) <> 0 then raise exception 'ANA devia ver a propria parte fechada'; end if;
  if not (select reserva_ativa from public.app_tarefas_listar('todas') where id = t_dias and colaborador_id = v_ana) then raise exception 'a conclusao da parte da ANA liberou os dias dela'; end if;
end $parte_da_ana$;
reset role;
select pg_temp.sistema();

-- 13d. Conclusao por participante; a gestao fecha a de uma pessoa so sem perguntar. --------
select pg_temp.como('1b000000-0000-4000-8000-000000000005');
set local role authenticated;
do $conclusao$
declare
  t_dias uuid := (select id from ids where nome = 'T_DIAS');
  t_solo uuid := (select id from ids where nome = 'T_SOLO');
  t_par uuid;
  v_inicio date;
  v_ana uuid := '1b000000-0000-4000-8000-000000000101';
  v_bruno uuid := '1b000000-0000-4000-8000-000000000102';
  v_pedro uuid := '1b000000-0000-4000-8000-000000000105';
  r jsonb;
begin
  v_inicio := (public.app_tarefas_detalhe(t_dias)->'tarefa'->>'data')::date;

  -- T_PAR: ANA e PEDRO.
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana, v_pedro], p_tipo => 'agendada', p_data => v_inicio + 15, p_dias => 1,
    p_descricao => 'Servico a dois', p_categoria => 'os', p_os_id => 929001);
  if not (r->>'sucesso')::boolean then raise exception 'T_PAR recusada: %', r; end if;
  t_par := (r->'tarefa'->>'id')::uuid;
  insert into ids values ('T_PAR', t_par);

  -- Com duas pessoas, a gestao que nao participa precisa dizer de quem e a parte.
  r := public.app_tarefas_concluir(t_par);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'participante_invalido' then raise exception 'gestao fechou tarefa de duas pessoas sem dizer de quem: %', r; end if;

  -- A parte de uma nao fecha a tarefa.
  r := public.app_tarefas_concluir(t_par, null, v_ana);
  if not (r->>'sucesso')::boolean or (r->>'colaborador_id')::uuid <> v_ana then raise exception 'conclusao da parte da ANA: %', r; end if;
  if r->'tarefa'->>'situacao' <> 'pendente' then raise exception 'a tarefa fechou com uma parte ainda aberta: %', r; end if;
  if (select count(*) from public.app_tarefas_listar('agendadas') where id = t_par) <> 2 then raise exception 'T_PAR devia continuar nas agendadas com as duas linhas'; end if;
  if (select count(*) from public.app_tarefas_listar('agendadas') where id = t_par and participante_concluida_em is not null) <> 1 then raise exception 'so a parte da ANA devia estar concluida'; end if;
  if (select count(*) from public.app_tarefas_listar('agendadas') where id = t_par and pode_concluir) <> 1 then raise exception 'quem ja fechou a parte dele nao deveria mais poder concluir'; end if;
  if (select count(*) from public.app_tarefas_listar('historico') where id = t_par) <> 0 then raise exception 'T_PAR entrou no historico com uma parte aberta'; end if;
  if (select count(*) from jsonb_array_elements(public.app_tarefas_detalhe(t_par)->'participantes') as e where e->>'concluida_em' is not null) <> 1 then raise exception 'detalhe devia mostrar so uma parte concluida'; end if;

  -- Repetir a parte dela: repetido, sem gravar de novo.
  r := public.app_tarefas_concluir(t_par, null, v_ana);
  if not (r->>'sucesso')::boolean or not (r->>'repetido')::boolean then raise exception 'concluir a mesma parte de novo: %', r; end if;

  -- A ultima parte fecha a tarefa, e as reservas continuam de pe.
  r := public.app_tarefas_concluir(t_par, null, v_pedro);
  if not (r->>'sucesso')::boolean or r->'tarefa'->>'situacao' <> 'concluida' then raise exception 'a ultima parte nao fechou a tarefa: %', r; end if;
  if (select count(*) from public.app_tarefas_listar('historico') where id = t_par) <> 2 then raise exception 'T_PAR devia estar no historico com as duas linhas'; end if;
  if (select count(*) from public.app_tarefas_listar('historico') where id = t_par and not reserva_ativa) <> 0 then raise exception 'concluir liberou a reserva de alguem'; end if;
  if (select count(*) from public.app_tarefas_listar('agendadas') where id = t_par) <> 0 then raise exception 'T_PAR concluida continuou nas agendadas'; end if;

  -- Uma pessoa so: a gestao que nao participa conclui sem informar p_colaborador_id.
  r := public.app_tarefas_concluir(t_solo);
  if not (r->>'sucesso')::boolean or (r->>'colaborador_id')::uuid <> v_bruno then raise exception 'gestao nao concluiu a tarefa de uma pessoa so: %', r; end if;
  if r->'tarefa'->>'situacao' <> 'concluida' or not (r->'tarefa'->>'reserva_ativa')::boolean then raise exception 'T_SOLO concluida: %', r; end if;

  -- Quem chega depois reabre a tarefa que ja estava fechada.
  r := public.app_tarefas_adicionar_participante(t_par, v_bruno);
  if not (r->>'sucesso')::boolean or r->'tarefa'->>'situacao' <> 'pendente' then raise exception 'entrar numa tarefa fechada devia reabri-la: %', r; end if;
  if (select count(*) from public.app_tarefas_listar('agendadas') where id = t_par) <> 3 then raise exception 'T_PAR reaberta devia voltar as agendadas com 3 linhas'; end if;
end $conclusao$;
reset role;
select pg_temp.sistema();

-- A tarefa fecha com a conclusao mais recente entre as partes (fn_tarefas_sincronizar_conclusao).
do $sincronizacao$
declare
  t_par uuid := (select id from ids where nome = 'T_PAR');
  v_tarefa timestamptz;
  v_ultima timestamptz;
begin
  -- Reaberta em 13d: nenhuma das tres partes pode ter ficado marcada como fechada
  -- por engano, e a tarefa nao pode ter data de conclusao.
  select concluida_em into v_tarefa from public.tarefas where id = t_par;
  if v_tarefa is not null then raise exception 'tarefa reaberta ficou com concluida_em'; end if;
  if (select count(*) from public.tarefas_participantes where tarefa_id = t_par and concluida_em is not null) <> 2 then
    raise exception 'reabrir a tarefa apagou a conclusao das partes';
  end if;
  -- E a tarefa de uma pessoa so fechou com a conclusao da parte dela.
  select t.concluida_em, p.concluida_em
    into v_tarefa, v_ultima
  from public.tarefas as t
  join public.tarefas_participantes as p on p.tarefa_id = t.id
  where t.id = (select id from ids where nome = 'T_SOLO');
  if v_tarefa is distinct from v_ultima then raise exception 'a tarefa nao fechou com a hora da parte concluida'; end if;
end $sincronizacao$;

-- 13e. Ausencia: folga em horas nao reserva, ferias em dias reservam. -----------------------
select pg_temp.como('1b000000-0000-4000-8000-000000000005');
set local role authenticated;
do $ausencias$
declare
  t_dias uuid := (select id from ids where nome = 'T_DIAS');
  t_folga uuid;
  t_ferias uuid;
  v_inicio date;
  v_ana uuid := '1b000000-0000-4000-8000-000000000101';
  v_pedro uuid := '1b000000-0000-4000-8000-000000000105';
  r jsonb;
begin
  v_inicio := (public.app_tarefas_detalhe(t_dias)->'tarefa'->>'data')::date;

  -- Folga de 4 horas, sem OS: a pessoa trabalha o resto do dia, entao nao reserva.
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana], p_tipo => 'agendada', p_data => v_inicio + 21, p_dias => 1,
    p_descricao => 'Folga da tarde', p_categoria => 'folga', p_medida => 'horas', p_horas => 4);
  if not (r->>'sucesso')::boolean then raise exception 'folga em horas recusada: %', r; end if;
  t_folga := (r->'tarefa'->>'id')::uuid;
  insert into ids values ('T_FOLGA', t_folga);
  if r->'tarefa'->>'categoria' <> 'folga' or r->'tarefa'->>'medida' <> 'horas' or (r->'tarefa'->>'horas')::numeric <> 4 then raise exception 'folga em horas: %', r; end if;
  if (r->'tarefa'->>'dias')::int <> 1 then raise exception 'folga em horas devia ocupar um dia so: %', r; end if;
  if r->'tarefa'->>'os_id' is not null or r->'tarefa'->>'numero_os' is not null or r->'tarefa'->>'cliente_nome' is not null then raise exception 'ausencia nao tem OS: %', r; end if;
  if (r->'tarefa'->>'reserva_ativa')::boolean then raise exception 'folga em horas nao devia reservar o dia: %', r; end if;
  if (select count(*) from public.app_tarefas_colaboradores(v_inicio + 21) where id = v_ana and ocupado) <> 0 then raise exception 'folga em horas ocupou o dia'; end if;
  -- E por isso da para trabalhar no resto daquele dia.
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana], p_tipo => 'agendada', p_data => v_inicio + 21, p_dias => 1,
    p_descricao => 'Resto do dia da folga', p_categoria => 'os', p_os_id => 929001);
  if not (r->>'sucesso')::boolean then raise exception 'nao deu para trabalhar no dia da folga em horas: %', r; end if;

  -- Ferias de tres dias, sem OS: reserva os tres.
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_pedro], p_tipo => 'agendada', p_data => v_inicio + 22, p_dias => 3,
    p_descricao => 'Ferias do Pedro', p_categoria => 'ferias');
  if not (r->>'sucesso')::boolean then raise exception 'ferias em dias recusadas: %', r; end if;
  t_ferias := (r->'tarefa'->>'id')::uuid;
  insert into ids values ('T_FERIAS', t_ferias);
  if r->'tarefa'->>'categoria' <> 'ferias' or r->'tarefa'->>'medida' <> 'dias' or (r->'tarefa'->>'dias')::int <> 3 then raise exception 'ferias: %', r; end if;
  if r->'tarefa'->>'horas' is not null or (r->'tarefa'->>'data_fim')::date <> v_inicio + 24 then raise exception 'ferias de tres dias: %', r; end if;
  if not (r->'tarefa'->>'reserva_ativa')::boolean then raise exception 'ferias em dias deviam reservar: %', r; end if;
  if jsonb_array_length(public.app_tarefas_detalhe(t_ferias)->'reservas') <> 3 then raise exception 'ferias de tres dias sao 3 reservas'; end if;

  -- E ninguem agenda trabalho no meio das ferias.
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_pedro], p_tipo => 'agendada', p_data => v_inicio + 23, p_dias => 1,
    p_descricao => 'No meio das ferias', p_categoria => 'os', p_os_id => 929001);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'colaborador_reservado' then raise exception 'agendou trabalho no meio das ferias: %', r; end if;
  if r->'conflito'->>'categoria' <> 'ferias' or r->'conflito'->>'numero_os' is not null then raise exception 'o conflito devia dizer que o dia e de ferias: %', r; end if;

  -- Recusas da RPC (antes de chegar nos checks da tabela).
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana], p_tipo => 'agendada', p_data => v_inicio + 25, p_dias => 1,
    p_descricao => 'Folga com OS', p_categoria => 'folga', p_os_id => 929001);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'os_invalida' then raise exception 'folga com OS aceita: %', r; end if;
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana], p_tipo => 'agendada', p_data => v_inicio + 25, p_dias => 1,
    p_descricao => 'Trabalho sem OS', p_categoria => 'os');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'os_invalida' then raise exception 'tarefa de OS sem OS aceita: %', r; end if;
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana], p_tipo => 'agendada', p_data => v_inicio + 25, p_dias => 1,
    p_descricao => 'Folga sem horas', p_categoria => 'folga', p_medida => 'horas');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'duracao_invalida' then raise exception 'medida em horas sem horas aceita: %', r; end if;
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana], p_tipo => 'agendada', p_data => v_inicio + 25, p_dias => 1,
    p_descricao => 'Folga de 30 horas', p_categoria => 'folga', p_medida => 'horas', p_horas => 30);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'duracao_invalida' then raise exception 'folga de 30 horas aceita: %', r; end if;
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana], p_tipo => 'sem_data', p_data => null, p_dias => 1,
    p_descricao => 'Ferias sem data', p_categoria => 'ferias');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'data_obrigatoria' then raise exception 'ausencia sem data aceita: %', r; end if;
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana], p_tipo => 'sem_data', p_data => null, p_dias => 2,
    p_descricao => 'Sem data de dois dias', p_categoria => 'os', p_os_id => 929001);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'duracao_invalida' then raise exception 'tarefa sem data de dois dias aceita: %', r; end if;
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana], p_tipo => 'agendada', p_data => v_inicio + 25, p_dias => 61,
    p_descricao => 'Muito longa', p_categoria => 'os', p_os_id => 929001);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'duracao_invalida' then raise exception '61 dias aceitos: %', r; end if;
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana], p_tipo => 'agendada', p_data => v_inicio + 25, p_dias => 0,
    p_descricao => 'Zero dias', p_categoria => 'os', p_os_id => 929001);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'duracao_invalida' then raise exception 'zero dias aceito: %', r; end if;
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana], p_tipo => 'agendada', p_data => v_inicio + 25, p_dias => 1,
    p_descricao => 'Categoria inventada', p_categoria => 'churrasco');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'categoria_invalida' then raise exception 'categoria inventada aceita: %', r; end if;
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana], p_tipo => 'agendada', p_data => v_inicio + 25, p_dias => 1,
    p_descricao => 'Medida inventada', p_categoria => 'folga', p_medida => 'minutos', p_horas => 30);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'medida_invalida' then raise exception 'medida inventada aceita: %', r; end if;
  r := public.app_tarefas_criar(
    p_colaboradores => array[v_ana, v_ana], p_tipo => 'agendada', p_data => v_inicio + 25, p_dias => 1,
    p_descricao => 'ANA duas vezes', p_categoria => 'os', p_os_id => 929001);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'colaborador_invalido' then raise exception 'a mesma pessoa duas vezes na tarefa: %', r; end if;
  r := public.app_tarefas_criar(
    p_colaboradores => array[]::uuid[], p_tipo => 'agendada', p_data => v_inicio + 25, p_dias => 1,
    p_descricao => 'Ninguem', p_categoria => 'os', p_os_id => 929001);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'colaborador_invalido' then raise exception 'tarefa sem ninguem aceita: %', r; end if;

  -- Nenhuma das recusas gravou tarefa no dia que elas usaram.
  if (select count(*) from public.app_tarefas_listar('todas') where data = v_inicio + 25) <> 0 then raise exception 'uma das recusas gravou tarefa'; end if;
end $ausencias$;
reset role;
select pg_temp.sistema();

-- Ausencia e da coordenacao: nao existe responsavel pelas ferias de alguem.
select pg_temp.como('1b000000-0000-4000-8000-000000000003');
set local role authenticated;
do $ausencia_permissao$
declare
  v_inicio date := (public.app_tarefas_detalhe((select id from ids where nome = 'T_DIAS'))->'tarefa'->>'data')::date;
  r jsonb;
begin
  r := public.app_tarefas_criar(
    p_colaboradores => array['1b000000-0000-4000-8000-000000000102'::uuid], p_tipo => 'agendada',
    p_data => v_inicio + 26, p_dias => 1, p_descricao => 'Folga dada pelo tecnico', p_categoria => 'folga');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sem_permissao' then raise exception 'responsavel de OS registrou ausencia: %', r; end if;
end $ausencia_permissao$;
reset role;
select pg_temp.sistema();

-- 13f. Os checks da tabela recusam as combinacoes invalidas, com nome e tudo. ---------------
do $checks_tarefas$
declare
  v_tenant uuid := '1b000000-0000-4000-8000-000000000010';
  v_empresa uuid := '1b000000-0000-4000-8000-000000000020';
  v_dia date := (now() at time zone 'America/Sao_Paulo')::date + 60;
  v_constraint text;
begin
  -- Ausencia com OS.
  begin
    insert into public.tarefas (tenant_id, empresa_id, os_id, tipo, data, descricao, categoria)
    values (v_tenant, v_empresa, 929001, 'agendada', v_dia, 'Folga com OS', 'folga');
    raise exception 'tarefas aceitou folga com os_id';
  exception when check_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint <> 'chk_tarefas_os_por_categoria' then raise exception 'folga com os_id caiu em %', v_constraint; end if;
  end;

  -- Trabalho sem OS.
  begin
    insert into public.tarefas (tenant_id, empresa_id, os_id, tipo, data, descricao, categoria)
    values (v_tenant, v_empresa, null, 'agendada', v_dia, 'Trabalho sem OS', 'os');
    raise exception 'tarefas aceitou categoria os sem os_id';
  exception when check_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint <> 'chk_tarefas_os_por_categoria' then raise exception 'os sem os_id caiu em %', v_constraint; end if;
  end;

  -- Medida em horas SEM as horas. O check antigo deixava passar: o ramo de horas
  -- era "medida = 'horas' and dias = 1 and horas > 0 and horas <= 24" e, com horas
  -- nula, isso da NULO, o outro ramo da falso, e um check que resulta em NULO
  -- passa. A Parte 6 da migration acrescentou "horas is not null", entao agora o
  -- banco recusa mesmo por escrita direta, e nao so pela RPC.
  begin
    insert into public.tarefas (tenant_id, empresa_id, os_id, tipo, data, descricao, categoria, medida, horas)
    values (v_tenant, v_empresa, null, 'agendada', v_dia, 'Folga sem horas', 'folga', 'horas', null);
    raise exception 'tarefas aceitou medida horas sem as horas';
  exception when check_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint <> 'chk_tarefas_duracao' then raise exception 'horas sem horas caiu em %', v_constraint; end if;
  end;

  -- Medida em dias com horas preenchidas.
  begin
    insert into public.tarefas (tenant_id, empresa_id, os_id, tipo, data, descricao, categoria, medida, horas)
    values (v_tenant, v_empresa, 929001, 'agendada', v_dia, 'Dias com horas', 'os', 'dias', 4);
    raise exception 'tarefas aceitou medida dias com horas';
  exception when check_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint <> 'chk_tarefas_duracao' then raise exception 'dias com horas caiu em %', v_constraint; end if;
  end;

  -- Duracao invalida em dias.
  begin
    insert into public.tarefas (tenant_id, empresa_id, os_id, tipo, data, descricao, categoria, dias)
    values (v_tenant, v_empresa, 929001, 'agendada', v_dia, 'Zero dias', 'os', 0);
    raise exception 'tarefas aceitou dias = 0';
  exception when check_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint <> 'chk_tarefas_duracao' then raise exception 'dias = 0 caiu em %', v_constraint; end if;
  end;

  -- Duracao so faz sentido com data: sem data ocupa um dia so.
  begin
    insert into public.tarefas (tenant_id, empresa_id, os_id, tipo, data, descricao, categoria, dias)
    values (v_tenant, v_empresa, 929001, 'sem_data', null, 'Sem data de dois dias', 'os', 2);
    raise exception 'tarefas aceitou sem_data com dois dias';
  exception when check_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint <> 'chk_tarefas_dias_por_tipo' then raise exception 'sem_data com dois dias caiu em %', v_constraint; end if;
  end;

  -- Nao existe ferias sem data.
  begin
    insert into public.tarefas (tenant_id, empresa_id, os_id, tipo, data, descricao, categoria)
    values (v_tenant, v_empresa, null, 'sem_data', null, 'Ferias sem data', 'ferias');
    raise exception 'tarefas aceitou ausencia sem data';
  exception when check_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint <> 'chk_tarefas_ausencia_agendada' then raise exception 'ausencia sem data caiu em %', v_constraint; end if;
  end;

  -- Categoria e medida so aceitam o que o modelo conhece.
  begin
    insert into public.tarefas (tenant_id, empresa_id, os_id, tipo, data, descricao, categoria)
    values (v_tenant, v_empresa, null, 'agendada', v_dia, 'Categoria inventada', 'churrasco');
    raise exception 'tarefas aceitou categoria inventada';
  exception when check_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint <> 'chk_tarefas_categoria' then raise exception 'categoria inventada caiu em %', v_constraint; end if;
  end;
  -- Medida inventada fere chk_tarefas_medida e tambem chk_tarefas_duracao (nenhum
  -- dos dois ramos do check vale), e o Postgres nao promete qual dos dois avisa.
  begin
    insert into public.tarefas (tenant_id, empresa_id, os_id, tipo, data, descricao, categoria, medida)
    values (v_tenant, v_empresa, 929001, 'agendada', v_dia, 'Medida inventada', 'os', 'minutos');
    raise exception 'tarefas aceitou medida inventada';
  exception when check_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint not in ('chk_tarefas_medida', 'chk_tarefas_duracao') then raise exception 'medida inventada caiu em %', v_constraint; end if;
  end;

  if (select count(*) from public.tarefas where data = v_dia) <> 0 then raise exception 'algum insert invalido entrou'; end if;
end $checks_tarefas$;

-- 13g. Listagem: a secao ausencias e as tarefas de OS nas secoes delas. ---------------------
select pg_temp.como('1b000000-0000-4000-8000-000000000005');
set local role authenticated;
do $listagem$
declare
  t_dias uuid := (select id from ids where nome = 'T_DIAS');
  t_folga uuid := (select id from ids where nome = 'T_FOLGA');
  t_ferias uuid := (select id from ids where nome = 'T_FERIAS');
  t_solo uuid := (select id from ids where nome = 'T_SOLO');
  v_pedro uuid := '1b000000-0000-4000-8000-000000000105';
  r jsonb;
begin
  -- A secao nova traz folga e ferias, e nenhuma tarefa de OS.
  if (select count(*) from public.app_tarefas_listar('ausencias')) <> 2 then raise exception 'a secao ausencias devia ter a folga e as ferias, tem %', (select count(*) from public.app_tarefas_listar('ausencias')); end if;
  if (select count(*) from public.app_tarefas_listar('ausencias') where categoria = 'os') <> 0 then raise exception 'a secao ausencias trouxe tarefa de OS'; end if;
  if (select count(*) from public.app_tarefas_listar('ausencias') where id = t_folga and categoria = 'folga' and medida = 'horas') <> 1 then raise exception 'a folga nao apareceu nas ausencias'; end if;
  if (select count(*) from public.app_tarefas_listar('ausencias') where id = t_ferias and categoria = 'ferias' and dias = 3) <> 1 then raise exception 'as ferias nao apareceram nas ausencias'; end if;
  if (select count(*) from public.app_tarefas_listar('ausencias') where numero_os is not null) <> 0 then raise exception 'ausencia com numero de OS na lista'; end if;

  -- As tarefas de OS continuam nas secoes delas, uma linha por participante.
  if (select count(*) from public.app_tarefas_listar('agendadas') where id = t_dias and categoria = 'os') <> 2 then raise exception 'T_DIAS devia estar nas agendadas com as duas linhas'; end if;
  if (select count(*) from public.app_tarefas_listar('historico') where id = t_solo and categoria = 'os') <> 1 then raise exception 'T_SOLO concluida devia estar no historico'; end if;
  if (select count(*) from public.app_tarefas_listar('sem_data') where categoria <> 'os') <> 0 then raise exception 'ausencia apareceu nas tarefas sem data'; end if;
  if (select count(*) from public.app_tarefas_listar('todas') where id = t_ferias) <> 1 then raise exception 'as ferias deviam aparecer em todas'; end if;

  -- Procurar pelo que a ausencia e acha a ausencia.
  if (select count(*) from public.app_tarefas_listar('ausencias', null, null, null, null, 'folga')) <> 1 then raise exception 'busca por folga'; end if;
  if (select count(*) from public.app_tarefas_listar('ausencias', null, null, null, null, 'férias')) <> 1 then raise exception 'busca por ferias com acento'; end if;
  if (select count(*) from public.app_tarefas_listar('ausencias', null, null, v_pedro)) <> 1 then raise exception 'filtro por colaborador nas ausencias'; end if;

  r := public.app_tarefas_contar();
  if (r->>'ausencias')::int <> 2 then raise exception 'contador de ausencias: %', r; end if;
end $listagem$;
reset role;
select pg_temp.sistema();

-- 13h. Compat: a assinatura antiga do aplicativo publicado continua de pe. ------------------
select pg_temp.como('1b000000-0000-4000-8000-000000000005');
set local role authenticated;
do $compat$
declare
  v_inicio date := (public.app_tarefas_detalhe((select id from ids where nome = 'T_DIAS'))->'tarefa'->>'data')::date;
  v_ana uuid := '1b000000-0000-4000-8000-000000000101';
  v_bruno uuid := '1b000000-0000-4000-8000-000000000102';
  v_pedro uuid := '1b000000-0000-4000-8000-000000000105';
  chave uuid := '1b000000-0000-4000-8000-0000000000c4';
  r jsonb;
  r2 jsonb;
  t_compat uuid;
begin
  -- A chamada do build 22 (p_tipo, p_colaborador_id, p_os_id, p_descricao, p_data, p_chave).
  r := public.app_tarefas_criar('agendada', v_bruno, 929001, 'Compat: uma pessoa e um dia', v_inicio + 28);
  if not (r->>'sucesso')::boolean then raise exception 'a assinatura antiga foi recusada: %', r; end if;
  t_compat := (r->'tarefa'->>'id')::uuid;
  insert into ids values ('T_COMPAT', t_compat);
  if (r->'tarefa'->>'participantes')::int <> 1 or (r->'tarefa'->>'colaborador_id')::uuid <> v_bruno then raise exception 'o atalho devia criar tarefa de uma pessoa: %', r; end if;
  if (r->'tarefa'->>'dias')::int <> 1 or r->'tarefa'->>'categoria' <> 'os' or r->'tarefa'->>'medida' <> 'dias' or r->'tarefa'->>'horas' is not null then raise exception 'o atalho devia criar tarefa de um dia em OS: %', r; end if;
  if not (r->'tarefa'->>'reserva_ativa')::boolean or (r->'tarefa'->>'data')::date <> v_inicio + 28 then raise exception 'o atalho nao reservou o dia: %', r; end if;
  if (select count(*) from public.app_tarefas_listar('agendadas') where id = t_compat) <> 1 then raise exception 'a tarefa do atalho devia ter uma linha so'; end if;
  if jsonb_array_length(public.app_tarefas_detalhe(t_compat)->'reservas') <> 1 then raise exception 'a tarefa do atalho devia ter uma reserva so'; end if;

  -- Sem data pelo atalho tambem.
  r := public.app_tarefas_criar('sem_data', v_ana, 929001, 'Compat: sem data', null);
  if not (r->>'sucesso')::boolean or r->'tarefa'->>'tipo' <> 'sem_data' or (r->'tarefa'->>'reserva_ativa')::boolean then raise exception 'sem data pelo atalho: %', r; end if;

  -- E a chave de idempotencia continua valendo no atalho.
  r := public.app_tarefas_criar('agendada', v_pedro, 929001, 'Compat: com chave', v_inicio + 29, chave);
  if not (r->>'sucesso')::boolean then raise exception 'atalho com chave: %', r; end if;
  r2 := public.app_tarefas_criar('agendada', v_pedro, 929001, 'Compat: com chave', v_inicio + 29, chave);
  if not (r2->>'sucesso')::boolean or not (r2->>'repetido')::boolean or r2->'tarefa'->>'id' <> r->'tarefa'->>'id' then raise exception 'a chave repetida no atalho criou outra tarefa: %', r2; end if;

  -- O atalho recusa o que a funcao nova recusa.
  r := public.app_tarefas_criar('agendada', v_bruno, 929001, 'Compat: dia ocupado', v_inicio + 28);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'colaborador_reservado' then raise exception 'o atalho aceitou dia ocupado: %', r; end if;
  r := public.app_tarefas_criar('agendada', v_bruno, 929005, 'Compat: OV', v_inicio + 30);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'os_invalida' then raise exception 'o atalho aceitou OV: %', r; end if;
end $compat$;
reset role;
select pg_temp.sistema();

-- As duas assinaturas precisam coexistir: sem o atalho, o aplicativo publicado quebra.
do $compat_assinaturas$
declare
  v_nova text := 'p_colaboradores uuid[], p_tipo text, p_data date, p_dias integer, p_descricao text, p_categoria text, p_os_id integer, p_medida text, p_horas numeric, p_chave uuid';
  v_antiga text := 'p_tipo text, p_colaborador_id uuid, p_os_id integer, p_descricao text, p_data date, p_chave uuid';
  v_proc record;
  v_oid_nova oid;
  v_oid_antiga oid;
begin
  for v_proc in
    select p.oid as id, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc as p
    join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'app_tarefas_criar'
  loop
    if v_proc.args = v_nova then v_oid_nova := v_proc.id; end if;
    if v_proc.args = v_antiga then v_oid_antiga := v_proc.id; end if;
  end loop;
  if v_oid_nova is null then raise exception 'a assinatura nova de app_tarefas_criar mudou'; end if;
  if v_oid_antiga is null then raise exception 'o atalho da assinatura antiga de app_tarefas_criar saiu: o aplicativo publicado quebra sem ele'; end if;
  if not has_function_privilege('authenticated', v_oid_antiga, 'execute') then
    raise exception 'o atalho da assinatura antiga nao esta liberado para authenticated';
  end if;
  if has_function_privilege('anon', v_oid_antiga, 'execute') then
    raise exception 'o atalho da assinatura antiga esta aberto para anon';
  end if;
end $compat_assinaturas$;

-- 14. O aplicativo publicado continua funcionando de ponta a ponta. ------------------------
-- Nao basta a assinatura antiga existir: o build 22 faz o ciclo inteiro sem saber
-- o que sao participantes nem dias. Reagendar e concluir tem argumento novo, e o
-- padrao deles e o que deixa a chamada curta resolver no PostgREST. Estas tres
-- chamadas sao exatamente as que o aparelho que nao atualizou manda.

select pg_temp.como('1b000000-0000-4000-8000-000000000005');

do $compat_ciclo$
declare
  v_ana uuid := '1b000000-0000-4000-8000-000000000101';
  v_dia date := public.fn_tablet_data_hoje() + 45;
  v_resp jsonb;
  v_tarefa uuid;
begin
  v_resp := public.app_tarefas_criar('agendada', v_ana, 929001, 'COMPAT build 22', v_dia);
  if coalesce((v_resp->>'sucesso')::boolean, false) is not true then
    raise exception 'a assinatura antiga de app_tarefas_criar falhou: %', v_resp;
  end if;
  v_tarefa := (v_resp->'tarefa'->>'id')::uuid;

  -- Os campos que a tela do build 22 le tem que continuar vindo preenchidos.
  if (v_resp->'tarefa'->>'colaborador_id') is null then raise exception 'colaborador_id saiu do retorno'; end if;
  if (v_resp->'tarefa'->>'colaborador_nome') is null then raise exception 'colaborador_nome saiu do retorno'; end if;
  if (v_resp->'tarefa'->>'numero_os') is null then raise exception 'numero_os saiu do retorno'; end if;
  if (v_resp->'tarefa'->>'situacao') <> 'pendente' then raise exception 'a tarefa nasceu em %', v_resp->'tarefa'->>'situacao'; end if;

  -- Reagendar sem dizer os dias.
  v_resp := public.app_tarefas_reagendar(v_tarefa, v_dia + 1);
  if coalesce((v_resp->>'sucesso')::boolean, false) is not true then
    raise exception 'reagendar sem p_dias falhou: %', v_resp;
  end if;
  if (v_resp->'tarefa'->>'data') <> (v_dia + 1)::text then
    raise exception 'reagendar sem p_dias nao mudou a data: %', v_resp->'tarefa'->>'data';
  end if;

  -- Concluir sem dizer de quem e a parte: com uma pessoa so nao ha ambiguidade.
  v_resp := public.app_tarefas_concluir(v_tarefa, gen_random_uuid());
  if coalesce((v_resp->>'sucesso')::boolean, false) is not true then
    raise exception 'concluir sem p_colaborador_id falhou: %', v_resp;
  end if;
  if (v_resp->'tarefa'->>'situacao') <> 'concluida' then
    raise exception 'a tarefa de uma pessoa nao fechou: %', v_resp->'tarefa'->>'situacao';
  end if;
end $compat_ciclo$;

select pg_temp.sistema();

-- 15. A Agenda mostra a ausência medida em HORAS. -----------------------------------------
-- Folga em horas não reserva o dia, de propósito. A Agenda era montada só das
-- reservas, então essas horas não apareciam em célula nenhuma: invisível na tela
-- onde a coordenação planeja a semana. Agora a função devolve também essas linhas,
-- com reserva_dia = false, e o dia continua livre para trabalho.

select pg_temp.como('1b000000-0000-4000-8000-000000000005');

do $agenda_horas$
declare
  v_ana uuid := '1b000000-0000-4000-8000-000000000101';
  v_bruno uuid := '1b000000-0000-4000-8000-000000000102';
  v_dia date := public.fn_tablet_data_hoje() + 60;
  v_resp jsonb;
  v_linha record;
  v_qtd integer;
begin
  -- Folga de 4h da ANA, e trabalho do BRUNO no mesmo dia (que reserva).
  v_resp := public.app_tarefas_criar(
    array[v_ana]::uuid[], 'agendada', v_dia, 1, 'Folga de quatro horas',
    'folga', null, 'horas', 4
  );
  if coalesce((v_resp->>'sucesso')::boolean, false) is not true then
    raise exception 'nao criei a folga em horas: %', v_resp;
  end if;

  v_resp := public.app_tarefas_criar(
    array[v_bruno]::uuid[], 'agendada', v_dia, 1, 'Trabalho que reserva o dia', 'os', 929001
  );
  if coalesce((v_resp->>'sucesso')::boolean, false) is not true then
    raise exception 'nao criei o trabalho do BRUNO: %', v_resp;
  end if;

  -- A folga em horas aparece, com reserva_dia = false e as horas.
  select count(*) into v_qtd
  from public.app_tarefas_agenda(v_dia, v_dia)
  where colaborador_id = v_ana and categoria = 'folga' and reserva_dia is false and horas = 4;
  if v_qtd <> 1 then
    raise exception 'a folga em horas devia aparecer uma vez na agenda com reserva_dia false, apareceu %', v_qtd;
  end if;

  -- E ela nao pode aparecer como reserva.
  if exists (
    select 1 from public.app_tarefas_agenda(v_dia, v_dia)
    where colaborador_id = v_ana and reserva_dia is true
  ) then
    raise exception 'a folga em horas apareceu como reserva do dia';
  end if;

  -- O dia da ANA continua livre: da para agendar trabalho nele.
  v_resp := public.app_tarefas_criar(
    array[v_ana]::uuid[], 'agendada', v_dia, 1, 'Trabalho no resto do dia da folga', 'os', 929001
  );
  if coalesce((v_resp->>'sucesso')::boolean, false) is not true then
    raise exception 'a folga em horas bloqueou o dia, e nao devia: %', v_resp;
  end if;

  -- Agora a ANA tem duas linhas no mesmo dia: a folga (sem reserva) e o trabalho
  -- (com reserva). As duas naturezas convivem na mesma celula.
  select count(*) into v_qtd from public.app_tarefas_agenda(v_dia, v_dia) where colaborador_id = v_ana;
  if v_qtd <> 2 then
    raise exception 'a ANA devia ter 2 linhas na agenda daquele dia (folga e trabalho), tem %', v_qtd;
  end if;

  -- Trabalho e ausencia em dias continuam com reserva_dia = true e horas nulo.
  for v_linha in
    select colaborador_id, categoria, reserva_dia, horas
    from public.app_tarefas_agenda(v_dia, v_dia)
    where colaborador_id = v_bruno
  loop
    if v_linha.reserva_dia is not true then raise exception 'trabalho devia vir com reserva_dia true'; end if;
    if v_linha.horas is not null then raise exception 'trabalho devia vir com horas nulo, veio %', v_linha.horas; end if;
  end loop;

  -- A linha com reserva vem antes da sem reserva na mesma celula: o que toma o dia
  -- e o que a coordenacao precisa ler primeiro. A ordem e a que a funcao devolve,
  -- por isso o WITH ORDINALITY — um "order by 1" reordenaria empates a esmo.
  if (select a.reserva_dia
      from public.app_tarefas_agenda(v_dia, v_dia) with ordinality
        as a(data, colaborador_id, colaborador_nome, tarefa_id, situacao, detalhe_visivel,
             numero_os, cliente_nome, descricao, categoria, reserva_dia, horas, n)
      where a.colaborador_id = v_ana
      order by a.n
      limit 1) is not true then
    raise exception 'na mesma celula, a linha que reserva o dia devia vir primeiro';
  end if;
end $agenda_horas$;

select pg_temp.sistema();

rollback;
