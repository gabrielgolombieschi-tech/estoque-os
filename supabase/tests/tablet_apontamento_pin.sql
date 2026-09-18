\set ON_ERROR_STOP on

-- Modo tablet compartilhado (20260911250000 e 20260911260000): PIN, sessao,
-- lancamento por duracao com classificacao pela data, janela de 15 dias, OS
-- encerrada, idempotencia, lista sem HH e o aperto em web_criar_apontamentos_horas.
--
-- Contas do fixture:
--   ...0001  tablet@example.test        APONTADOR, sem colaborador  -> conta do tablet
--   ...0002  coordenacao@example.test   COORDENACAO                 -> nao administra PIN nem tablet
--   ...0005  diretor@example.test       DIRETOR                     -> administra PINs e tablets
--   ...0003  tecnico@example.test       TECNICO                     -> nao pode OS encerrada no web
--   ...0004  pessoa@example.test        APONTADOR com colaborador   -> conta de pessoa, nao vira tablet
-- Colaboradores: ANA (PIN 0042), BRUNO (PIN 1234), CARLA (inativa, PIN 7777), DIEGO (sem PIN).

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('19000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'tablet@example.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Tablet"}'::jsonb, now(), now()),
  ('19000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'coordenacao@example.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Coordenacao"}'::jsonb, now(), now()),
  ('19000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'tecnico@example.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Tecnico"}'::jsonb, now(), now()),
  ('19000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'pessoa@example.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Pessoa"}'::jsonb, now(), now()),
  ('19000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'diretor@example.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Diretor"}'::jsonb, now(), now());

insert into public.tenants (id, nome, ativo) values ('19000000-0000-4000-8000-000000000010', 'Tenant tablet', true);
insert into c.tenant (id, codigo, nome, ativo) values ('19000000-0000-4000-8000-000000000010', 'TABLET', 'Tenant tablet', true);
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo)
values ('19000000-0000-4000-8000-000000000020', '19000000-0000-4000-8000-000000000010', 'TAB-A', 'Empresa tablet', 'Empresa tablet', '19000000000100', true);
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo)
values ('19000000-0000-4000-8000-000000000020', '19000000-0000-4000-8000-000000000010', '19000000000100', 'Empresa tablet', 'Empresa tablet', true);

insert into a.usuario (id, auth_user_id, nome, email, ativo) values
  ('19000000-0000-4000-8000-000000000041', '19000000-0000-4000-8000-000000000001', 'Tablet da producao', 'tablet@example.test', true),
  ('19000000-0000-4000-8000-000000000042', '19000000-0000-4000-8000-000000000002', 'Coordenacao', 'coordenacao@example.test', true),
  ('19000000-0000-4000-8000-000000000043', '19000000-0000-4000-8000-000000000003', 'Tecnico', 'tecnico@example.test', true),
  ('19000000-0000-4000-8000-000000000044', '19000000-0000-4000-8000-000000000004', 'Pessoa', 'pessoa@example.test', true),
  ('19000000-0000-4000-8000-000000000045', '19000000-0000-4000-8000-000000000005', 'Diretor', 'diretor@example.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo) values
  ('19000000-0000-4000-8000-000000000041', '19000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('19000000-0000-4000-8000-000000000042', '19000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('19000000-0000-4000-8000-000000000043', '19000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('19000000-0000-4000-8000-000000000044', '19000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('19000000-0000-4000-8000-000000000045', '19000000-0000-4000-8000-000000000010', 'ADMIN', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo) values
  ('19000000-0000-4000-8000-000000000041', '19000000-0000-4000-8000-000000000020', 'APONTADOR', true),
  ('19000000-0000-4000-8000-000000000042', '19000000-0000-4000-8000-000000000020', 'COORDENACAO', true),
  ('19000000-0000-4000-8000-000000000043', '19000000-0000-4000-8000-000000000020', 'TECNICO', true),
  ('19000000-0000-4000-8000-000000000044', '19000000-0000-4000-8000-000000000020', 'APONTADOR', true),
  ('19000000-0000-4000-8000-000000000045', '19000000-0000-4000-8000-000000000020', 'DIRETOR', true);
insert into public.user_tenant_context (user_id, tenant_id) values
  ('19000000-0000-4000-8000-000000000001', '19000000-0000-4000-8000-000000000010'),
  ('19000000-0000-4000-8000-000000000002', '19000000-0000-4000-8000-000000000010'),
  ('19000000-0000-4000-8000-000000000003', '19000000-0000-4000-8000-000000000010'),
  ('19000000-0000-4000-8000-000000000004', '19000000-0000-4000-8000-000000000010'),
  ('19000000-0000-4000-8000-000000000005', '19000000-0000-4000-8000-000000000010');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id) values
  ('19000000-0000-4000-8000-000000000001', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020'),
  ('19000000-0000-4000-8000-000000000002', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020'),
  ('19000000-0000-4000-8000-000000000003', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020'),
  ('19000000-0000-4000-8000-000000000004', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020'),
  ('19000000-0000-4000-8000-000000000005', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020');

insert into public.colaboradores (id, nome, ativo, tenant_id, empresa_id, user_id) values
  ('19000000-0000-4000-8000-000000000101', 'ANA', true, '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', null),
  ('19000000-0000-4000-8000-000000000102', 'BRUNO', true, '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', null),
  ('19000000-0000-4000-8000-000000000103', 'CARLA', false, '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', null),
  ('19000000-0000-4000-8000-000000000104', 'DIEGO', true, '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', null),
  ('19000000-0000-4000-8000-000000000105', 'PESSOA', true, '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', '19000000-0000-4000-8000-000000000004');
insert into public.colaborador_taxas (colaborador_id, valor_hora, vigencia_inicio, tenant_id, empresa_id) values
  ('19000000-0000-4000-8000-000000000101', 50, '2020-01-01', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020'),
  ('19000000-0000-4000-8000-000000000102', 50, '2020-01-01', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020'),
  ('19000000-0000-4000-8000-000000000103', 50, '2020-01-01', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020'),
  ('19000000-0000-4000-8000-000000000105', 50, '2020-01-01', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020');
-- DIEGO fica sem taxa de proposito.

insert into public.tipos_horas (id, codigo, descricao, fator, ativo, tenant_id) values
  ('19000000-0000-4000-8000-000000000201', 'EXTRA_50', 'Hora extra 50%', 1.5, true, '19000000-0000-4000-8000-000000000010'),
  ('19000000-0000-4000-8000-000000000202', 'NORMAL', 'Hora normal', 1, true, '19000000-0000-4000-8000-000000000010'),
  ('19000000-0000-4000-8000-000000000203', 'EXTRA_100', 'Hora extra 100%', 2, true, '19000000-0000-4000-8000-000000000010');

insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social)
values (919001, '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 'CLIENTE TABLET', '19111111000191', 'CLIENTE TABLET LTDA');
insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social, habilita_hh)
values (919002, '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 'CLIENTE HH', '19111111000192', 'CLIENTE HH LTDA', true);

insert into public.ordens_servico (id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id, empresa_id,
  status_fluxo, tipo_documento, codigo, numero_doc, descricao_servico, orcado, responsavel_aprovacao_id)
values
  (919001, 'TAB-1', 'CLIENTE TABLET', 919001, 'em_andamento', 919001, '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-TAB-001', 1, 'OS aberta', 100, null),
  (919002, 'TAB-2', 'CLIENTE TABLET', 919001, 'em_andamento', 919002, '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-TAB-002', 1, 'OS que vai fechar', 100, null),
  (919003, 'TAB-3', 'CLIENTE TABLET', 919001, 'concluida', 919003, '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 'concluida', 'OS', 'OS-TAB-003', 1, 'OS encerrada', 100, null),
  (919004, 'TAB-4', 'CLIENTE TABLET', 919001, 'em_andamento', 919004, '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-TAB-004', 1, 'OS aberta 2', 100, null);
insert into public.ordens_servico (id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id, empresa_id,
  status_fluxo, tipo_documento, codigo, numero_doc, descricao_servico, orcado, responsavel_aprovacao_id, usa_relatorio_hh)
values (919005, 'TAB-HH', 'CLIENTE HH', 919002, 'em_andamento', 919005, '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-TAB-HH', 1, 'OS de HH (fora do tablet)', 0, null, true);

-- Helpers para trocar de usuario (e para voltar a 'ninguem', senao os triggers
-- de hierarquia de a.usuario_empresa enxergam auth.uid() nos ajustes do fixture).
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

-- 1. Administracao: diretor define PINs; coordenacao e tecnico nao. ---------------
select pg_temp.como('19000000-0000-4000-8000-000000000005');
set local role authenticated;
do $admin$
declare r jsonb;
begin
  r := public.web_tablet_pin_definir('19000000-0000-4000-8000-000000000101', '0042');
  if not (r->>'sucesso')::boolean then raise exception 'PIN 0042 da ANA recusado: %', r; end if;
  r := public.web_tablet_pin_definir('19000000-0000-4000-8000-000000000102', '1234');
  if not (r->>'sucesso')::boolean then raise exception 'PIN 1234 do BRUNO recusado: %', r; end if;
  -- PIN repetido: recusado.
  r := public.web_tablet_pin_definir('19000000-0000-4000-8000-000000000104', '1234');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'pin_em_uso' then raise exception 'PIN repetido aceito: %', r; end if;
  -- PIN com 3 digitos / letras: recusado.
  r := public.web_tablet_pin_definir('19000000-0000-4000-8000-000000000104', '123');
  if (r->>'sucesso')::boolean then raise exception 'PIN curto aceito'; end if;
  r := public.web_tablet_pin_definir('19000000-0000-4000-8000-000000000104', '12a4');
  if (r->>'sucesso')::boolean then raise exception 'PIN com letra aceito'; end if;
  -- Colaboradora inativa: recusado.
  r := public.web_tablet_pin_definir('19000000-0000-4000-8000-000000000103', '7777');
  if (r->>'sucesso')::boolean then raise exception 'PIN de inativa aceito'; end if;
  if (select count(*) from public.web_tablet_pins_listar()) <> 2 then raise exception 'web_tablet_pins_listar devia ter 2 PINs'; end if;
  if (select count(*) filter (where tem_pin) from public.app_tablet_pins_colaboradores()) <> 2
     or (select count(*) from public.app_tablet_pins_colaboradores()) <> 4 then
    raise exception 'app_tablet_pins_colaboradores devia listar 4 ativos, 2 com PIN';
  end if;
end $admin$;
reset role;
select pg_temp.sistema();

-- Coordenacao: nem PIN, nem tablet, nem a lista de colaboradores da tela de PIN.
select pg_temp.como('19000000-0000-4000-8000-000000000002');
set local role authenticated;
do $coord$
declare r jsonb;
begin
  begin
    r := public.web_tablet_pin_definir('19000000-0000-4000-8000-000000000104', '5555');
    raise exception 'COORDENACAO definiu PIN.';
  exception when others then
    if sqlerrm not like 'Seu perfil não pode administrar%' then raise; end if;
  end;
  begin
    perform public.web_tablet_pins_listar();
    raise exception 'COORDENACAO listou PINs.';
  exception when others then
    if sqlerrm not like 'Seu perfil não pode administrar%' then raise; end if;
  end;
  begin
    perform public.app_tablet_pins_colaboradores();
    raise exception 'COORDENACAO listou colaboradores da tela de PIN.';
  exception when others then
    if sqlerrm not like 'Seu perfil não pode administrar%' then raise; end if;
  end;
  begin
    r := public.web_tablet_salvar('19000000-0000-4000-8000-000000000001', 'Tablet da producao', 60, true);
    raise exception 'COORDENACAO autorizou tablet.';
  exception when others then
    if sqlerrm not like 'Seu perfil não pode administrar%' then raise; end if;
  end;
end $coord$;
reset role;
select pg_temp.sistema();

-- CARLA ganha PIN direto (era ativa quando o PIN foi definido, depois foi desativada).
insert into public.colaboradores_pin (colaborador_id, tenant_id, empresa_id, pin_hash)
values ('19000000-0000-4000-8000-000000000103', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', extensions.crypt('7777', extensions.gen_salt('bf', 6)));

select pg_temp.como('19000000-0000-4000-8000-000000000003');
set local role authenticated;
do $tecnico$
declare r jsonb;
begin
  begin
    r := public.web_tablet_pin_definir('19000000-0000-4000-8000-000000000104', '5555');
    raise exception 'TECNICO definiu PIN.';
  exception when others then
    if sqlerrm not like 'Seu perfil não pode administrar%' then raise; end if;
  end;
  if (public.app_tablet_contexto()->>'tablet')::boolean then raise exception 'TECNICO virou tablet'; end if;
end $tecnico$;
reset role;
select pg_temp.sistema();

-- 2. Autorizar o tablet: precisa de Admin/Diretor; conta APONTADOR sem colaborador.
select pg_temp.como('19000000-0000-4000-8000-000000000005');
set local role authenticated;
do $autorizar$
declare r jsonb;
begin
  -- Conta de pessoa (com colaborador): recusada.
  r := public.web_tablet_salvar('19000000-0000-4000-8000-000000000004', 'Tablet errado', 60, true);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'conta_vinculada' then raise exception 'Conta de pessoa virou tablet: %', r; end if;
  -- Conta TECNICO: recusada.
  r := public.web_tablet_salvar('19000000-0000-4000-8000-000000000003', 'Tablet errado', 60, true);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'conta_papel' then raise exception 'Conta TECNICO virou tablet: %', r; end if;
  -- Conta certa.
  r := public.web_tablet_salvar('19000000-0000-4000-8000-000000000001', 'Tablet da producao', 45, true);
  if not (r->>'sucesso')::boolean then raise exception 'Tablet nao autorizado: %', r; end if;
  if (select count(*) from public.web_tablet_contas_elegiveis() where ja_autorizado) <> 1 then raise exception 'contas_elegiveis nao marcou o tablet'; end if;
  if (select count(*) from public.web_tablet_listar()) <> 1 then raise exception 'web_tablet_listar devia ter 1'; end if;
end $autorizar$;
reset role;
select pg_temp.sistema();

-- 3. Conta de pessoa APONTADOR nao e tablet; conta do tablet e. ------------------
select pg_temp.como('19000000-0000-4000-8000-000000000004');
set local role authenticated;
do $pessoa$
begin
  if (public.app_tablet_contexto()->>'tablet')::boolean then raise exception 'Conta de pessoa entrou em modo tablet'; end if;
  if (public.app_tablet_identificar('0042')->>'sucesso')::boolean then raise exception 'Conta de pessoa identificou PIN'; end if;
  begin
    perform public.app_tablet_os_agrupado_cliente(null);
    raise exception 'Conta de pessoa listou OS do tablet';
  exception when others then
    if sqlerrm not like 'Este aparelho não está autorizado%' then raise; end if;
  end;
end $pessoa$;
reset role;
select pg_temp.sistema();

select pg_temp.como('19000000-0000-4000-8000-000000000001');
set local role authenticated;
do $tablet$
declare
  ctx jsonb;
  r jsonb;
  token text;
  token_ana text;
  chave uuid := gen_random_uuid();
  hoje date;
  v_horas numeric;
  v_qtd integer;
  v_status text;
  v_criado_por uuid;
  v_sessao uuid;
  i integer;
begin
  ctx := public.app_tablet_contexto();
  if not (ctx->>'tablet')::boolean then raise exception 'Conta do tablet nao reconhecida: %', ctx; end if;
  if (ctx->>'inatividade_segundos')::integer <> 45 then raise exception 'inatividade errada: %', ctx; end if;
  hoje := (ctx->>'hoje')::date;

  -- 3a. PIN invalido (formato), PIN de inativa, PIN sem dono, PIN com zero inicial.
  r := public.app_tablet_identificar('12');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'pin_invalido' then raise exception 'PIN curto passou: %', r; end if;
  r := public.app_tablet_identificar('7777');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'pin_nao_reconhecido' then raise exception 'PIN de inativa passou: %', r; end if;
  r := public.app_tablet_identificar('9999');
  if (r->>'sucesso')::boolean then raise exception 'PIN sem dono passou'; end if;
  if (r->>'tentativas_restantes')::integer <> 3 then raise exception 'contagem de tentativas errada: %', r; end if;
  r := public.app_tablet_identificar('0042');
  if not (r->>'sucesso')::boolean then raise exception 'PIN 0042 (zero inicial) recusado: %', r; end if;
  if r->>'colaborador_nome' <> 'ANA' then raise exception 'PIN 0042 identificou %', r->>'colaborador_nome'; end if;
  if r->>'sessao_token' is null then raise exception 'sem token'; end if;
  token_ana := r->>'sessao_token';
  -- PIN certo zera as falhas. (As tabelas do tablet nao tem policy: a conferencia
  -- direta precisa ser feita como postgres.)
  reset role;
  if exists (select 1 from public.tablet_pin_tentativas) then raise exception 'tentativas nao zeradas'; end if;
  set local role authenticated;

  -- 3b. Trocar de colaborador: PIN do BRUNO derruba a sessao da ANA.
  r := public.app_tablet_identificar('1234');
  if not (r->>'sucesso')::boolean or r->>'colaborador_nome' <> 'BRUNO' then raise exception 'PIN 1234 falhou: %', r; end if;
  token := r->>'sessao_token';
  v_sessao := (r->>'sessao_id')::uuid;
  r := public.app_tablet_apontamentos_do_dia(token_ana, 919001, hoje);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sessao_invalida' then raise exception 'token da ANA continua valido: %', r; end if;

  -- 3c. Consulta do dia (vazia) com a situacao da OS.
  r := public.app_tablet_apontamentos_do_dia(token, 919001, hoje);
  if not (r->>'sucesso')::boolean then raise exception 'do_dia falhou: %', r; end if;
  if jsonb_array_length(r->'lancamentos') <> 0 or (r->>'total_dia_horas')::numeric <> 0 then raise exception 'dia devia estar vazio: %', r; end if;
  if not (r->'os'->>'pode_lancar')::boolean then raise exception 'OS aberta marcada como bloqueada: %', r; end if;
  r := public.app_tablet_apontamentos_do_dia(token, 919003, hoje);
  if (r->'os'->>'pode_lancar')::boolean then raise exception 'OS encerrada marcada como aberta: %', r; end if;

  -- 3d. 3h30 -> 3.50, hora normal, pendente, autor = conta do tablet, sessao amarrada.
  r := public.app_tablet_lancar_horas(token, 919001, hoje, 3, 30, chave, false);
  if not (r->>'sucesso')::boolean then raise exception 'lancamento 3h30 falhou: %', r; end if;
  if (r->>'horas')::numeric <> 3.50 or (r->>'minutos')::integer <> 210 then raise exception 'conversao errada: %', r; end if;
  if (r->'resumo'->>'subtotal_os_horas')::numeric <> 3.50 or (r->'resumo'->>'total_dia_horas')::numeric <> 3.50 then raise exception 'resumo errado: %', r; end if;
  reset role;
  select horas, status_aprovacao, criado_por_user_id, tablet_sessao_id into v_horas, v_status, v_criado_por, v_sessao
  from public.apontamentos_horas where id = (r->>'apontamento_id')::uuid;
  if v_horas <> 3.50 then raise exception 'horas gravadas = %', v_horas; end if;
  if v_status <> 'pendente' then raise exception 'status_aprovacao = % (esperado pendente)', v_status; end if;
  if v_criado_por <> '19000000-0000-4000-8000-000000000001' then raise exception 'criado_por_user_id errado'; end if;
  if v_sessao is null then raise exception 'tablet_sessao_id vazio'; end if;
  if (select upper(th.codigo) from public.apontamentos_horas ah join public.tipos_horas th on th.id = ah.tipo_hora_id where ah.id = (r->>'apontamento_id')::uuid)
     <> (public.fn_tablet_classificar('19000000-0000-4000-8000-000000000010', hoje) ->> 'codigo_base') then
    raise exception 'tipo de hora nao segue a classificacao do dia';
  end if;
  if (select colaborador_id from public.apontamentos_horas where id = (r->>'apontamento_id')::uuid) <> '19000000-0000-4000-8000-000000000102' then
    raise exception 'beneficiario nao e o BRUNO';
  end if;
  set local role authenticated;

  -- 3e. Idempotencia: mesma chave nao grava de novo e devolve o mesmo apontamento.
  r := public.app_tablet_lancar_horas(token, 919001, hoje, 3, 30, chave, false);
  if not (r->>'sucesso')::boolean or not (r->>'repetido')::boolean then raise exception 'reenvio nao foi tratado como repetido: %', r; end if;
  reset role;
  select count(*) into v_qtd from public.apontamentos_horas where colaborador_id = '19000000-0000-4000-8000-000000000102';
  set local role authenticated;
  if v_qtd <> 1 then raise exception 'reenvio duplicou: % linhas', v_qtd; end if;

  -- 3f. Segundo lancamento legitimo com a mesma duracao e chave nova: grava.
  r := public.app_tablet_lancar_horas(token, 919001, hoje, 3, 30, gen_random_uuid(), false);
  if not (r->>'sucesso')::boolean then raise exception 'segundo 3h30 recusado: %', r; end if;
  if (r->'resumo'->>'subtotal_os_horas')::numeric <> 7.00 then raise exception 'subtotal errado apos 2 lancamentos: %', r; end if;
  if jsonb_array_length(r->'resumo'->'lancamentos') <> 2 then raise exception 'resumo devia listar 2'; end if;

  -- 3g. Jornada > 9h vira aviso; confirmando, grava. Total geral do dia soma as OS.
  r := public.app_tablet_lancar_horas(token, 919004, hoje, 2, 30, gen_random_uuid(), false);
  if (r->>'sucesso')::boolean or jsonb_array_length(r->'avisos') = 0 or r->'avisos'->0->>'tipo' <> 'jornada_maior_que_9h' then
    raise exception 'aviso de jornada nao veio: %', r;
  end if;
  chave := gen_random_uuid();
  r := public.app_tablet_lancar_horas(token, 919004, hoje, 2, 30, chave, true);
  if not (r->>'sucesso')::boolean then raise exception 'confirmacao de jornada falhou: %', r; end if;
  if (r->'resumo'->>'subtotal_os_horas')::numeric <> 2.50 or (r->'resumo'->>'total_dia_horas')::numeric <> 9.50 then raise exception 'totais errados: %', r; end if;
  if jsonb_array_length(r->'resumo'->'outras_os_dia') <> 1 then raise exception 'outras_os_dia devia listar a TAB-1'; end if;

  -- 3h. Retroativo (> 7 dias): aviso, depois grava. Data futura: erro.
  r := public.app_tablet_lancar_horas(token, 919001, hoje - 10, 1, 0, gen_random_uuid(), false);
  if (r->>'sucesso')::boolean or r->'avisos'->0->>'tipo' <> 'retroativo' then raise exception 'aviso retroativo nao veio: %', r; end if;
  r := public.app_tablet_lancar_horas(token, 919001, hoje - 10, 1, 0, gen_random_uuid(), true);
  if not (r->>'sucesso')::boolean then raise exception 'retroativo confirmado falhou: %', r; end if;
  r := public.app_tablet_apontamentos_do_dia(token, 919001, hoje - 10);
  if jsonb_array_length(r->'lancamentos') <> 1 or (r->>'total_dia_horas')::numeric <> 1 then raise exception 'consulta retroativa errada: %', r; end if;
  r := public.app_tablet_lancar_horas(token, 919001, hoje + 1, 1, 0, gen_random_uuid(), true);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'data_futura' then raise exception 'data futura aceita: %', r; end if;

  -- 3i. Duracao invalida.
  r := public.app_tablet_lancar_horas(token, 919001, hoje, 0, 0, gen_random_uuid(), true);
  if (r->>'sucesso')::boolean then raise exception 'duracao zero aceita'; end if;
  r := public.app_tablet_lancar_horas(token, 919001, hoje, 3, 60, gen_random_uuid(), true);
  if (r->>'sucesso')::boolean then raise exception 'minutos 60 aceitos'; end if;
  r := public.app_tablet_lancar_horas(token, 919001, hoje, 25, 0, gen_random_uuid(), true);
  if (r->>'sucesso')::boolean then raise exception '25h aceitas'; end if;

  -- 3j. OS encerrada: bloqueada para o colaborador comum.
  r := public.app_tablet_lancar_horas(token, 919003, hoje, 1, 0, gen_random_uuid(), true);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'os_encerrada' then raise exception 'OS encerrada aceita: %', r; end if;

  -- 3k. OS que fecha durante o preenchimento: a confirmacao para.
  r := public.app_tablet_apontamentos_do_dia(token, 919002, hoje);
  if not (r->'os'->>'pode_lancar')::boolean then raise exception 'TAB-2 devia estar aberta'; end if;
  reset role;
  update public.ordens_servico set status_fluxo = 'concluida', status = 'concluida' where id = 919002;
  set local role authenticated;
  r := public.app_tablet_lancar_horas(token, 919002, hoje, 1, 0, gen_random_uuid(), true);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'os_encerrada' then raise exception 'OS fechada no meio foi aceita: %', r; end if;

  -- 3p. Lista do tablet: OS abertas sem HH, agrupadas por cliente.
  if exists (select 1 from public.app_tablet_os_agrupado_cliente(null) where cliente_id = 919002) then raise exception 'cliente so de HH apareceu na lista do tablet'; end if;
  if (select quantidade_os from public.app_tablet_os_agrupado_cliente(null) where cliente_id = 919001) <> 2 then raise exception 'CLIENTE TABLET devia ter 2 OS abertas (TAB-1 e TAB-4)'; end if;
  if exists (select 1 from public.app_tablet_os_do_cliente(919002)) then raise exception 'OS de HH listada'; end if;
  if (select count(*) from public.app_tablet_os_agrupado_cliente('TAB-4')) <> 1 then raise exception 'busca por TAB-4 falhou'; end if;

  -- 3q. Janela: hoje - 15 entra; hoje - 16 nao.
  r := public.app_tablet_apontamentos_do_dia(token, 919001, hoje - 15);
  if not (r->>'sucesso')::boolean or (r->'janela'->>'de')::date <> hoje - 15 then raise exception 'do_dia em hoje-15 falhou: %', r; end if;
  r := public.app_tablet_apontamentos_do_dia(token, 919001, hoje - 16);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'data_fora_da_janela' then raise exception 'do_dia em hoje-16 passou: %', r; end if;
  r := public.app_tablet_lancar_horas(token, 919004, hoje - 15, 1, 0, gen_random_uuid(), true);
  if not (r->>'sucesso')::boolean then raise exception 'lancar em hoje-15 falhou: %', r; end if;
  r := public.app_tablet_lancar_horas(token, 919004, hoje - 16, 1, 0, gen_random_uuid(), true);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'data_fora_da_janela' then raise exception 'lancar em hoje-16 passou: %', r; end if;

  -- 3r. Classificacao pela data dentro da janela: sabado, domingo, dia util, feriado.
  declare
    v_sabado date; v_domingo date; v_util date; v_feriado date; c jsonb;
  begin
    select d::date into v_sabado from generate_series(hoje - 15, hoje - 1, interval '1 day') as s(d) where extract(dow from d) = 6 order by d desc limit 1;
    select d::date into v_domingo from generate_series(hoje - 15, hoje - 1, interval '1 day') as s(d) where extract(dow from d) = 0 order by d desc limit 1;
    select d::date into v_util from generate_series(hoje - 15, hoje - 1, interval '1 day') as s(d)
      where extract(dow from d) between 1 and 5 and not exists (select 1 from public.feriados f where f.data = d::date) order by d desc limit 1;
    select d::date into v_feriado from generate_series(hoje - 15, hoje - 1, interval '1 day') as s(d)
      where extract(dow from d) between 1 and 5 and not exists (select 1 from public.feriados f where f.data = d::date) order by d asc limit 1;
    reset role;
    insert into public.feriados (data, descricao, abrangencia) values (v_feriado, 'Feriado de teste', 'MUNICIPAL');
    set local role authenticated;

    reset role;
    c := public.fn_tablet_classificar('19000000-0000-4000-8000-000000000010', v_sabado);
    set local role authenticated;
    if c->>'dia' <> 'sabado' or c->>'codigo_base' <> 'EXTRA_50' then raise exception 'sabado mal classificado: %', c; end if;
    r := public.app_tablet_lancar_horas(token, 919004, v_sabado, 2, 0, gen_random_uuid(), true);
    if not (r->>'sucesso')::boolean or r->'partes'->0->>'codigo' <> 'EXTRA_50' or (r->>'gravados')::integer <> 1 then raise exception 'sabado nao entrou como EXTRA_50: %', r; end if;

    r := public.app_tablet_lancar_horas(token, 919004, v_domingo, 2, 0, gen_random_uuid(), true);
    if not (r->>'sucesso')::boolean or r->'partes'->0->>'codigo' <> 'EXTRA_100' then raise exception 'domingo nao entrou como EXTRA_100: %', r; end if;

    r := public.app_tablet_lancar_horas(token, 919004, v_feriado, 2, 0, gen_random_uuid(), true);
    if not (r->>'sucesso')::boolean or r->'partes'->0->>'codigo' <> 'EXTRA_100' or r->'classificacao'->>'dia' <> 'feriado' then raise exception 'feriado nao entrou como EXTRA_100: %', r; end if;

    -- dia util com 10 h: 9 h normais + 1 h extra 50%, duas linhas, uma chave.
    chave := gen_random_uuid();
    r := public.app_tablet_lancar_horas(token, 919004, v_util, 10, 0, chave, true);
    if not (r->>'sucesso')::boolean or (r->>'gravados')::integer <> 2 then raise exception 'dia util com 10h nao dividiu: %', r; end if;
    if r->'partes'->0->>'codigo' <> 'NORMAL' or (r->'partes'->0->>'horas')::numeric <> 9
       or r->'partes'->1->>'codigo' <> 'EXTRA_50' or (r->'partes'->1->>'horas')::numeric <> 1 then raise exception 'partes erradas: %', r; end if;
    reset role;
    select count(*), sum(horas) into v_qtd, v_horas from public.apontamentos_horas
    where colaborador_id = '19000000-0000-4000-8000-000000000102' and os_id = 919004 and data = v_util;
    set local role authenticated;
    if v_qtd <> 2 or v_horas <> 10 then raise exception 'linhas do dia util: % linhas, % h', v_qtd, v_horas; end if;
    r := public.app_tablet_lancar_horas(token, 919004, v_util, 10, 0, chave, true);
    if not (r->>'repetido')::boolean or jsonb_array_length(r->'apontamento_ids') <> 2 then raise exception 'reenvio da chave dividida errado: %', r; end if;

    -- dia util com 9 h: uma linha so.
    r := public.app_tablet_lancar_horas(token, 919001, v_util, 9, 0, gen_random_uuid(), true);
    if not (r->>'sucesso')::boolean or (r->>'gravados')::integer <> 1 or r->'partes'->0->>'codigo' <> 'NORMAL' then raise exception '9h em dia util devia ser uma linha NORMAL: %', r; end if;

    -- consulta do dia devolve a classificacao e o feriado pelo nome.
    r := public.app_tablet_apontamentos_do_dia(token, 919004, v_feriado);
    if r->'classificacao'->>'feriado' <> 'Feriado de teste' or r->'classificacao'->>'tipo_nome_base' <> 'Hora extra 100%' then raise exception 'do_dia sem classificacao: %', r; end if;

    -- sem o tipo EXTRA_100 ativo: erro dizendo o que falta.
    reset role;
    update public.tipos_horas set ativo = false where id = '19000000-0000-4000-8000-000000000203';
    set local role authenticated;
    r := public.app_tablet_lancar_horas(token, 919001, v_domingo, 1, 0, gen_random_uuid(), true);
    if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'configuracao' or position('EXTRA_100' in r->'erros'->0->>'mensagem') = 0 then raise exception 'falta de tipo nao acusada: %', r; end if;
    reset role;
    update public.tipos_horas set ativo = true where id = '19000000-0000-4000-8000-000000000203';
    set local role authenticated;
  end;

  -- 3l. Encerrar: token morre, e encerrar de novo nao quebra.
  r := public.app_tablet_encerrar(token, 'finalizado');
  if (r->>'encerradas')::integer <> 1 then raise exception 'encerrar nao encerrou: %', r; end if;
  r := public.app_tablet_apontamentos_do_dia(token, 919001, hoje);
  if (r->>'sucesso')::boolean then raise exception 'token encerrado continua valido'; end if;
  r := public.app_tablet_lancar_horas(token, 919001, hoje, 1, 0, gen_random_uuid(), true);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sessao_invalida' then raise exception 'lancou com token encerrado: %', r; end if;
  r := public.app_tablet_encerrar(token, 'finalizado');
  if (r->>'encerradas')::integer <> 0 then raise exception 'encerrar duas vezes contou de novo'; end if;

  -- 3m. Expiracao: sessao com expira_em no passado nao vale mais.
  r := public.app_tablet_identificar('0042');
  token := r->>'sessao_token';
  reset role;
  update public.tablet_sessoes set expira_em = now() - interval '1 second' where id = (r->>'sessao_id')::uuid;
  set local role authenticated;
  r := public.app_tablet_apontamentos_do_dia(token, 919001, hoje);
  if (r->>'sucesso')::boolean then raise exception 'sessao expirada continua valida'; end if;

  -- 3n. Colaborador sem taxa vigente (DIEGO): mensagem clara.
  reset role;
  insert into public.colaboradores_pin (colaborador_id, tenant_id, empresa_id, pin_hash)
  values ('19000000-0000-4000-8000-000000000104', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', extensions.crypt('5555', extensions.gen_salt('bf', 6)));
  set local role authenticated;
  r := public.app_tablet_identificar('5555');
  token := r->>'sessao_token';
  r := public.app_tablet_lancar_horas(token, 919001, hoje, 1, 0, gen_random_uuid(), true);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'taxa_vigente' then raise exception 'sem taxa passou: %', r; end if;
  perform public.app_tablet_encerrar(token, 'finalizado');

  -- 3o. Bloqueio: 5 erros seguidos travam o aparelho; o PIN certo tambem e recusado enquanto travado.
  for i in 1..5 loop
    r := public.app_tablet_identificar('9999');
  end loop;
  if r->'erros'->0->>'tipo' <> 'bloqueado' or (r->>'bloqueado_ate') is null then raise exception '5o erro nao bloqueou: %', r; end if;
  r := public.app_tablet_identificar('0042');
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'bloqueado' then raise exception 'PIN certo passou durante o bloqueio: %', r; end if;
  reset role;
  update public.tablet_pin_tentativas set bloqueado_ate = now() - interval '1 second';
  set local role authenticated;
  r := public.app_tablet_identificar('0042');
  if not (r->>'sucesso')::boolean then raise exception 'apos o bloqueio o PIN certo nao passou: %', r; end if;
  perform public.app_tablet_encerrar(r->>'sessao_token', 'finalizado');
end $tablet$;
reset role;
select pg_temp.sistema();

-- 4. Tablet desativado deixa de funcionar. -----------------------------------------
select pg_temp.como('19000000-0000-4000-8000-000000000005');
set local role authenticated;
select public.web_tablet_salvar('19000000-0000-4000-8000-000000000001', 'Tablet da producao', 60, false);
reset role;
select pg_temp.sistema();
select pg_temp.como('19000000-0000-4000-8000-000000000001');
set local role authenticated;
do $desativado$
begin
  if (public.app_tablet_contexto()->>'tablet')::boolean then raise exception 'tablet desativado continua ativo'; end if;
  if (public.app_tablet_identificar('0042')->>'sucesso')::boolean then raise exception 'tablet desativado identificou PIN'; end if;
end $desativado$;
reset role;
select pg_temp.sistema();

-- 5. web_criar_apontamentos_horas: OS encerrada so para coordenacao+ ou responsavel. --
select pg_temp.como('19000000-0000-4000-8000-000000000003');
set local role authenticated;
do $web_tecnico$
declare r jsonb;
begin
  -- OS aberta continua normal para o tecnico.
  r := public.web_criar_apontamentos_horas(jsonb_build_array(jsonb_build_object(
    'os_id', 919001, 'colaborador_id', '19000000-0000-4000-8000-000000000101', 'data', current_date, 'horas', 1,
    'tipo_hora_id', '19000000-0000-4000-8000-000000000202', 'descricao', 'teste', 'confirmar_os_encerrada', false)));
  if not (r->>'sucesso')::boolean then raise exception 'tecnico nao lancou em OS aberta: %', r; end if;
  -- OS encerrada: barrado mesmo confirmando.
  begin
    r := public.web_criar_apontamentos_horas(jsonb_build_array(jsonb_build_object(
      'os_id', 919003, 'colaborador_id', '19000000-0000-4000-8000-000000000101', 'data', current_date, 'horas', 1,
      'tipo_hora_id', '19000000-0000-4000-8000-000000000202', 'descricao', 'teste', 'confirmar_os_encerrada', true)));
    raise exception 'TECNICO lancou em OS encerrada.';
  exception when others then
    if sqlerrm not like 'A OS % está encerrada: somente Coordenação%' then raise; end if;
  end;
end $web_tecnico$;
reset role;
select pg_temp.sistema();

-- Tecnico responsavel da OS encerrada: passa.
update public.ordens_servico set responsavel_aprovacao_id = '19000000-0000-4000-8000-000000000003' where id = 919003;
select pg_temp.como('19000000-0000-4000-8000-000000000003');
set local role authenticated;
do $web_responsavel$
declare r jsonb;
begin
  r := public.web_criar_apontamentos_horas(jsonb_build_array(jsonb_build_object(
    'os_id', 919003, 'colaborador_id', '19000000-0000-4000-8000-000000000101', 'data', current_date, 'horas', 1,
    'tipo_hora_id', '19000000-0000-4000-8000-000000000202', 'descricao', 'teste', 'confirmar_os_encerrada', true)));
  if not (r->>'sucesso')::boolean then raise exception 'responsavel nao lancou em OS encerrada: %', r; end if;
end $web_responsavel$;
reset role;
select pg_temp.sistema();
update public.ordens_servico set responsavel_aprovacao_id = null where id = 919003;

-- Coordenacao: passa, e a linha distingue beneficiario (ANA) de executor (coordenacao).
select pg_temp.como('19000000-0000-4000-8000-000000000002');
set local role authenticated;
do $web_coord$
declare r jsonb; v_criado uuid; v_colab uuid;
begin
  r := public.web_criar_apontamentos_horas(jsonb_build_array(jsonb_build_object(
    'os_id', 919003, 'colaborador_id', '19000000-0000-4000-8000-000000000101', 'data', current_date, 'horas', 2,
    'tipo_hora_id', '19000000-0000-4000-8000-000000000202', 'descricao', 'esquecido', 'confirmar_os_encerrada', true)));
  if not (r->>'sucesso')::boolean then raise exception 'coordenacao nao lancou em OS encerrada: %', r; end if;
  reset role;
  select criado_por_user_id, colaborador_id into v_criado, v_colab from public.apontamentos_horas where id = (r->'ids'->>0)::uuid;
  set local role authenticated;
  if v_criado <> '19000000-0000-4000-8000-000000000002' or v_colab <> '19000000-0000-4000-8000-000000000101' then
    raise exception 'executor/beneficiario nao distinguidos';
  end if;
end $web_coord$;
reset role;
select pg_temp.sistema();

-- 6. app_editar_apontamento: duas linhas do tablet na mesma OS/data/tipo podem
-- ter as horas editadas (duplicidade so quando o tipo muda). Como DIRETOR, que
-- passa em can('apontamentos','write') sem depender do seed de role_permissions.
select pg_temp.como('19000000-0000-4000-8000-000000000005');
set local role authenticated;
do $editar$
declare
  v_id uuid;
  v_tipo_irmao uuid;
  v_tipo_livre uuid;
  e jsonb;
begin
  -- Uma das duas linhas de hoje na TAB-1 (as duas tem o mesmo criado_em, que e
  -- o carimbo da transacao; a de 10 dias atras fica de fora pelo filtro de data).
  -- Os tipos nao podem ser fixos aqui: o tablet classifica pela data, entao num
  -- sabado as duas linhas nascem EXTRA_50 e num dia util, NORMAL. O que importa
  -- e a regra: trocar para um tipo que a outra linha nao usa passa; trocar para
  -- o tipo da outra linha colide.
  reset role;
  select id into v_id from public.apontamentos_horas
  where colaborador_id = '19000000-0000-4000-8000-000000000102' and os_id = 919001 and tablet_sessao_id is not null
    and data = public.fn_tablet_data_hoje()
  order by id limit 1;
  select tipo_hora_id into v_tipo_irmao from public.apontamentos_horas
  where colaborador_id = '19000000-0000-4000-8000-000000000102' and os_id = 919001 and tablet_sessao_id is not null
    and data = public.fn_tablet_data_hoje() and id <> v_id
  order by id limit 1;
  select id into v_tipo_livre from public.tipos_horas
  where tenant_id = '19000000-0000-4000-8000-000000000010' and id <> v_tipo_irmao
  order by codigo limit 1;
  set local role authenticated;
  e := public.app_editar_apontamento(v_id, 4, v_tipo_livre, 'ajuste da coordenacao', true, 'conferido com o colaborador');
  if not (e->>'sucesso')::boolean then raise exception 'edicao de linha do tablet recusada: %', e; end if;
  e := public.app_editar_apontamento(v_id, 5, v_tipo_livre, 'ajuste da coordenacao', true, 'conferido com o colaborador');
  if not (e->>'sucesso')::boolean then raise exception 'segunda edicao no mesmo tipo recusada: %', e; end if;
  e := public.app_editar_apontamento(v_id, 4, v_tipo_irmao, 'ajuste da coordenacao', true, 'conferido com o colaborador');
  if (e->>'sucesso')::boolean or e->'erros'->0->>'tipo' <> 'duplicidade' then raise exception 'troca de tipo com colisao aceita: %', e; end if;
end $editar$;
reset role;
select pg_temp.sistema();

-- 7. Custo e relatorio: as linhas do tablet entram na view de custo com o fator
-- do tipo classificado pela data (taxa do BRUNO: 50/h).
do $custo$
declare
  hoje date := public.fn_tablet_data_hoje();
  v_sabado date; v_domingo date; v_util date; v_feriado date;
  v_custo numeric;
begin
  select d::date into v_sabado from generate_series(hoje - 15, hoje - 1, interval '1 day') as s(d) where extract(dow from d) = 6 order by d desc limit 1;
  select d::date into v_domingo from generate_series(hoje - 15, hoje - 1, interval '1 day') as s(d) where extract(dow from d) = 0 order by d desc limit 1;
  select data into v_feriado from public.feriados where descricao = 'Feriado de teste';
  select d::date into v_util from generate_series(hoje - 15, hoje - 1, interval '1 day') as s(d)
    where extract(dow from d) between 1 and 5 and not exists (select 1 from public.feriados f where f.data = d::date) order by d desc limit 1;

  select sum(custo_lancamento) into v_custo from public.vw_apontamentos_horas_custo
  where colaborador_id = '19000000-0000-4000-8000-000000000102' and os_id = 919004 and data = v_sabado;
  if v_custo <> 150 then raise exception 'custo do sabado: % (esperado 2h x 50 x 1,5)', v_custo; end if;

  select sum(custo_lancamento) into v_custo from public.vw_apontamentos_horas_custo
  where colaborador_id = '19000000-0000-4000-8000-000000000102' and os_id = 919004 and data = v_domingo;
  if v_custo <> 200 then raise exception 'custo do domingo: % (esperado 2h x 50 x 2)', v_custo; end if;

  select sum(custo_lancamento) into v_custo from public.vw_apontamentos_horas_custo
  where colaborador_id = '19000000-0000-4000-8000-000000000102' and os_id = 919004 and data = v_feriado
    and tipo_hora_codigo = 'EXTRA_100'; -- a 1h de 3q entrou antes de a data virar feriado
  if v_custo <> 200 then raise exception 'custo do feriado: % (esperado 2h x 50 x 2)', v_custo; end if;

  select sum(custo_lancamento) into v_custo from public.vw_apontamentos_horas_custo
  where colaborador_id = '19000000-0000-4000-8000-000000000102' and os_id = 919004 and data = v_util;
  if v_custo <> 525 then raise exception 'custo do dia util com 10h: % (esperado 9h x 50 + 1h x 50 x 1,5)', v_custo; end if;
end $custo$;

-- 8. Falta ou afastamento pela propria pessoa (20260918180000): dia inteiro ou
-- algumas horas, janela de 15 dias atras a 30 a frente, sem reservar o dia, com
-- idempotencia pela chave e sem registro em dobro do dia inteiro.
-- O bloco 5 desautorizou o tablet: o diretor autoriza de novo.
select pg_temp.como('19000000-0000-4000-8000-000000000005');
set local role authenticated;
do $reautoriza$
declare r jsonb;
begin
  r := public.web_tablet_salvar('19000000-0000-4000-8000-000000000001', 'Tablet da producao', 60, true);
  if not (r->>'sucesso')::boolean then raise exception 'reautorizar o tablet falhou: %', r; end if;
end $reautoriza$;
reset role;
select pg_temp.sistema();
select pg_temp.como('19000000-0000-4000-8000-000000000001');
set local role authenticated;
do $falta$
declare
  r jsonb;
  token text;
  hoje date;
  chave uuid := gen_random_uuid();
  v_tarefa uuid;
begin
  r := public.app_tablet_identificar('0042');
  if not (r->>'sucesso')::boolean then raise exception 'PIN da ANA recusado: %', r; end if;
  token := r->>'sessao_token';
  hoje := (r->>'hoje')::date;

  -- 8a. Nada registrado ainda; a janela vem do servidor.
  r := public.app_tablet_ausencias(token);
  if not (r->>'sucesso')::boolean then raise exception 'ausencias falhou: %', r; end if;
  if jsonb_array_length(r->'registradas') <> 0 then raise exception 'ANA ja tinha ausencia: %', r; end if;
  if (r->'janela'->>'de')::date <> hoje - 15 or (r->'janela'->>'ate')::date <> hoje + 30 then raise exception 'janela errada: %', r; end if;

  -- 8b. Recusas: sessao invalida, sem chave, medida, data fora da janela, duracao.
  r := public.app_tablet_registrar_falta('token-invalido', hoje, 'dias', null, null, 'Doente', gen_random_uuid());
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'sessao_invalida' then raise exception 'token invalido passou: %', r; end if;
  r := public.app_tablet_registrar_falta(token, hoje, 'dias', null, null, 'Doente', null);
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'chave' then raise exception 'sem chave passou: %', r; end if;
  r := public.app_tablet_registrar_falta(token, hoje, 'semana', null, null, 'Doente', gen_random_uuid());
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'medida' then raise exception 'medida invalida passou: %', r; end if;
  r := public.app_tablet_registrar_falta(token, hoje - 16, 'dias', null, null, 'Doente', gen_random_uuid());
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'data_fora_da_janela' then raise exception 'hoje-16 passou: %', r; end if;
  if (r->'janela'->>'ate')::date <> hoje + 30 then raise exception 'recusa por data sem janela: %', r; end if;
  r := public.app_tablet_registrar_falta(token, hoje + 31, 'dias', null, null, 'Doente', gen_random_uuid());
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'data_fora_da_janela' then raise exception 'hoje+31 passou: %', r; end if;
  r := public.app_tablet_registrar_falta(token, hoje, 'horas', 0, 0, 'Consulta', gen_random_uuid());
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'duracao' then raise exception 'zero horas passou: %', r; end if;
  r := public.app_tablet_registrar_falta(token, hoje, 'horas', 24, 0, 'Consulta', gen_random_uuid());
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'duracao' then raise exception '24h em horas passou (devia ser dia inteiro): %', r; end if;
  r := public.app_tablet_registrar_falta(token, hoje, 'horas', 1, 75, 'Consulta', gen_random_uuid());
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'duracao' then raise exception '75 minutos passou: %', r; end if;

  -- 8c. Dia inteiro hoje: grava falta sem atestado, sem OS, sem reserva, com o rastro da sessao.
  r := public.app_tablet_registrar_falta(token, hoje, 'dias', null, null, 'Doente', chave);
  if not (r->>'sucesso')::boolean then raise exception 'falta do dia inteiro recusada: %', r; end if;
  if r->>'medida' <> 'dias' or r->>'horas' is not null or r->>'motivo' <> 'Doente' or r->>'colaborador_nome' <> 'ANA' then raise exception 'resposta da falta: %', r; end if;
  if jsonb_array_length(r->'registradas') <> 1 then raise exception 'recibo sem a falta: %', r; end if;
  v_tarefa := (r->>'tarefa_id')::uuid;

  -- Mesma chave de novo: nada duplica.
  r := public.app_tablet_registrar_falta(token, hoje, 'dias', null, null, 'Doente', chave);
  if not (r->>'sucesso')::boolean or not (r->>'repetido')::boolean or (r->>'tarefa_id')::uuid <> v_tarefa then raise exception 'reenvio duplicou ou falhou: %', r; end if;

  -- Dia inteiro em cima do dia inteiro, ou horas em cima do dia inteiro: recusa.
  r := public.app_tablet_registrar_falta(token, hoje, 'dias', null, null, 'Doente', gen_random_uuid());
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'ja_registrada' then raise exception 'dia inteiro em dobro passou: %', r; end if;
  if r->'erros'->0->>'mensagem' not like '%uma falta registrada em%(dia inteiro)%' then raise exception 'mensagem do dobro: %', r; end if;
  r := public.app_tablet_registrar_falta(token, hoje, 'horas', 2, 0, 'Consulta médica', gen_random_uuid());
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'ja_registrada' then raise exception 'horas em cima do dia inteiro passou: %', r; end if;

  -- 8d. Algumas horas ontem (2h) e mais uma saida no mesmo dia (1h30): as duas podem.
  r := public.app_tablet_registrar_falta(token, hoje - 1, 'horas', 2, 0, 'Consulta médica ou exame', gen_random_uuid());
  if not (r->>'sucesso')::boolean then raise exception 'afastamento de 2h recusado: %', r; end if;
  if r->>'medida' <> 'horas' or (r->>'horas')::numeric <> 2 or (r->>'minutos')::integer <> 120 then raise exception 'resposta do afastamento: %', r; end if;
  r := public.app_tablet_registrar_falta(token, hoje - 1, 'horas', 1, 30, 'Saí mais cedo', gen_random_uuid());
  if not (r->>'sucesso')::boolean or (r->>'horas')::numeric <> 1.5 then raise exception 'segunda saida no mesmo dia recusada: %', r; end if;
  -- Dia inteiro em cima das horas: recusa, citando as horas que ja existem.
  r := public.app_tablet_registrar_falta(token, hoje - 1, 'dias', null, null, 'Doente', gen_random_uuid());
  if (r->>'sucesso')::boolean or r->'erros'->0->>'tipo' <> 'ja_registrada' then raise exception 'dia inteiro em cima das horas passou: %', r; end if;
  if r->'erros'->0->>'mensagem' not like '%(2 h)%' then raise exception 'mensagem devia citar as 2 h: %', r; end if;

  -- 8e. Amanha, sem motivo: entra com o texto padrao. Futuro dentro dos 30 dias vale.
  r := public.app_tablet_registrar_falta(token, hoje + 1, 'horas', 1, 0, '   ', gen_random_uuid());
  if not (r->>'sucesso')::boolean then raise exception 'afastamento de amanha recusado: %', r; end if;
  if r->>'motivo' <> 'Registrada pela própria pessoa no tablet' then raise exception 'motivo padrao: %', r; end if;

  -- 8f. A lista do tablet e "Minhas tarefas" enxergam o que foi registrado.
  r := public.app_tablet_ausencias(token);
  if jsonb_array_length(r->'registradas') <> 4 then raise exception 'esperava 4 registradas: %', r; end if;
  if not (r->'registradas'->0->>'pelo_tablet')::boolean then raise exception 'registro sem marca do tablet: %', r; end if;
  r := public.app_tablet_tarefas(token);
  if not (r->>'sucesso')::boolean then raise exception 'tarefas do tablet falhou: %', r; end if;
  if not exists (select 1 from jsonb_array_elements(r->'agendadas') as x where (x->>'id')::uuid = v_tarefa and x->>'categoria' = 'falta') then
    raise exception 'a falta nao apareceu em Minhas tarefas: %', r;
  end if;
end $falta$;
reset role;
select pg_temp.sistema();

-- O que ficou no banco: falta sem atestado, sem OS, sem reserva, criada pela conta do
-- tablet com a sessao do PIN, e a operacao guardada para o reenvio.
do $falta_banco$
declare
  v_tarefa public.tarefas;
begin
  select t.* into v_tarefa
  from public.tarefas as t
  join public.tarefas_participantes as p on p.tarefa_id = t.id
  where p.colaborador_id = '19000000-0000-4000-8000-000000000101' and t.medida = 'dias' and t.categoria = 'falta';
  if v_tarefa.id is null then raise exception 'falta da ANA nao esta no banco'; end if;
  if v_tarefa.os_id is not null or v_tarefa.tipo <> 'agendada' or v_tarefa.dias <> 1 or v_tarefa.horas is not null then raise exception 'falta gravada errada: %', to_jsonb(v_tarefa); end if;
  if v_tarefa.criado_por_user_id <> '19000000-0000-4000-8000-000000000001' then raise exception 'criado_por devia ser a conta do tablet'; end if;
  if v_tarefa.criado_por_sessao_id is null then raise exception 'sem a sessao do PIN na falta'; end if;
  if exists (select 1 from public.tablet_sessoes s where s.id = v_tarefa.criado_por_sessao_id and s.colaborador_id <> '19000000-0000-4000-8000-000000000101') then
    raise exception 'sessao da falta e de outra pessoa';
  end if;
  if exists (select 1 from public.tarefas_reservas r where r.tarefa_id = v_tarefa.id) then raise exception 'a falta reservou o dia'; end if;
  if not exists (select 1 from public.tarefas_operacoes op where op.tarefa_id = v_tarefa.id and op.operacao = 'tablet_falta') then raise exception 'operacao do tablet nao registrada'; end if;
  if (select count(*) from public.tarefas t join public.tarefas_participantes p on p.tarefa_id = t.id
      where p.colaborador_id = '19000000-0000-4000-8000-000000000101' and t.categoria = 'falta') <> 4 then
    raise exception 'esperava 4 faltas da ANA no banco';
  end if;
end $falta_banco$;

rollback;
