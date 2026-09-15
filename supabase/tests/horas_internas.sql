\set ON_ERROR_STOP on

-- Horas internas (supabase/migrations/20260914140000_horas_internas.sql; desenho em
-- docs/horas-internas.md): a hora aponta para uma OS ou para uma atividade interna,
-- nunca as duas nem nenhuma.
--
-- Blocos:
--   1   catalogo semeado com as seis; cadastro so de ADMIN, DIRETOR e COORDENACAO
--   1b  codigo normalizado pelo cadastro; empresa nova nascendo com o catalogo
--   2   OS ou atividade, uma so, segurado pela tabela
--   3   lancar pelo aplicativo/web: Comercial pede cliente e orcamento, cliente de
--       outra empresa, atividade inativa; nasce aprovada, nao exige taxa; classificacao
--   4   avisos de retroativo e de mais de 9 h pedem confirmacao
--   5   APONTADOR e TECNICO so para si; coordenacao para cima para qualquer um
--   6   tablet do PIN: so atividade sem cliente, idempotencia pela chave, janela de 15 dias
--   7   fora de vw_apontamentos_horas_custo
--   8   leituras: tv_horas_periodo, web_listar_apontamentos_horas,
--       app_historico_lancamentos e app_minhas_horas_mes
--   9   web_horas_internas_resumo
--   10  editar (aplicativo e web, trilha, notificacao), excluir, cancelar e descancelar
--   11  editar hora antiga depois que a atividade passou a pedir cliente ou foi desativada
--
-- Trechos marcados ">>> CENARIO QUE FALHA HOJE" conferem o que o
-- banco faz HOJE num problema ja reportado, e nao o que devia fazer: quebram de proposito
-- quando a correcao entrar, com a mensagem dizendo o que trocar (a conferencia certa fica
-- comentada ao lado).
--
-- Contas do fixture (tenant 1d00...0010, empresa A 1d00...0020, empresa B 1d00...0021):
--   ...0001  tablet@horas.test       APONTADOR sem colaborador -> conta do tablet
--   ...0002  coordenacao@horas.test  COORDENACAO               -> gestao
--   ...0003  tecnico@horas.test      TECNICO, colaborador PEDRO
--   ...0004  pessoa@horas.test       APONTADOR, colaboradora ANA -> colaborador comum
--   ...0005  diretor@horas.test      DIRETOR                   -> gestao, autoriza tablet e PIN
--   ...0006  tv@horas.test           PAINEL_TV                 -> a televisao, nao lanca
--   ...0007  admin@horas.test        ADMIN                     -> gestao
--   ...0008  faturamento@horas.test  FATURAMENTO               -> nem gestao nem aponta
-- Colaboradores A: ANA (...0101, pessoa), BRUNO (...0102, PIN 1234), CARLA (...0103, inativa),
--   DIEGO (...0104, SEM taxa de proposito, PIN 5678), PEDRO (...0105, tecnico). Colaborador B: ZECA (...0106).
-- Tipos de hora: NORMAL ...0301, EXTRA_50 ...0302, EXTRA_100 ...0303.
-- Clientes: 949001 CLIENTE HORAS (A), 949002 CLIENTE B (B). OS: HI-1 949001 (A, em andamento).
--
-- O teste nao usa data fixa nem depende do dia da semana em que roda: hoje e
-- fn_tablet_data_hoje(), sabado, domingo e dia util saem do calendario do banco
-- (public.feriados), o feriado e um dia util antigo marcado dentro da transacao, e os
-- lancamentos nessas datas confirmam o aviso de retroativo quando ele vier. O papel
-- authenticated nao executa fn_tablet_data_hoje(): os blocos leem as datas de "datas".

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('1d000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'tablet@horas.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Tablet"}'::jsonb, now(), now()),
  ('1d000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'coordenacao@horas.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Coordenacao"}'::jsonb, now(), now()),
  ('1d000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'tecnico@horas.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Tecnico"}'::jsonb, now(), now()),
  ('1d000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'pessoa@horas.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Pessoa"}'::jsonb, now(), now()),
  ('1d000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'diretor@horas.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Diretor"}'::jsonb, now(), now()),
  ('1d000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'tv@horas.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"TV"}'::jsonb, now(), now()),
  ('1d000000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'admin@horas.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Admin"}'::jsonb, now(), now()),
  ('1d000000-0000-4000-8000-000000000008', 'authenticated', 'authenticated', 'faturamento@horas.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Faturamento"}'::jsonb, now(), now());

insert into public.tenants (id, nome, ativo) values ('1d000000-0000-4000-8000-000000000010', 'Tenant horas internas', true);
insert into c.tenant (id, codigo, nome, ativo) values ('1d000000-0000-4000-8000-000000000010', 'HORAS', 'Tenant horas internas', true);
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo) values
  ('1d000000-0000-4000-8000-000000000020', '1d000000-0000-4000-8000-000000000010', 'HI-A', 'Empresa horas A', 'Empresa A', '41000000000100', true),
  ('1d000000-0000-4000-8000-000000000021', '1d000000-0000-4000-8000-000000000010', 'HI-B', 'Empresa horas B', 'Empresa B', '41000000000200', true);
-- O gatilho trg_empresas_atividades_internas e o que da o catalogo a estas duas.
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo) values
  ('1d000000-0000-4000-8000-000000000020', '1d000000-0000-4000-8000-000000000010', '41000000000100', 'Empresa horas A', 'Empresa A', true),
  ('1d000000-0000-4000-8000-000000000021', '1d000000-0000-4000-8000-000000000010', '41000000000200', 'Empresa horas B', 'Empresa B', true);

insert into a.usuario (id, auth_user_id, nome, email, ativo) values
  ('1d000000-0000-4000-8000-000000000041', '1d000000-0000-4000-8000-000000000001', 'Tablet da producao', 'tablet@horas.test', true),
  ('1d000000-0000-4000-8000-000000000042', '1d000000-0000-4000-8000-000000000002', 'Coordenacao', 'coordenacao@horas.test', true),
  ('1d000000-0000-4000-8000-000000000043', '1d000000-0000-4000-8000-000000000003', 'Tecnico Pedro', 'tecnico@horas.test', true),
  ('1d000000-0000-4000-8000-000000000044', '1d000000-0000-4000-8000-000000000004', 'Pessoa Ana', 'pessoa@horas.test', true),
  ('1d000000-0000-4000-8000-000000000045', '1d000000-0000-4000-8000-000000000005', 'Diretor', 'diretor@horas.test', true),
  ('1d000000-0000-4000-8000-000000000046', '1d000000-0000-4000-8000-000000000006', 'Televisao da producao', 'tv@horas.test', true),
  ('1d000000-0000-4000-8000-000000000047', '1d000000-0000-4000-8000-000000000007', 'Admin', 'admin@horas.test', true),
  ('1d000000-0000-4000-8000-000000000048', '1d000000-0000-4000-8000-000000000008', 'Faturamento', 'faturamento@horas.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo) values
  ('1d000000-0000-4000-8000-000000000041', '1d000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('1d000000-0000-4000-8000-000000000042', '1d000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('1d000000-0000-4000-8000-000000000043', '1d000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('1d000000-0000-4000-8000-000000000044', '1d000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('1d000000-0000-4000-8000-000000000045', '1d000000-0000-4000-8000-000000000010', 'ADMIN', true),
  ('1d000000-0000-4000-8000-000000000046', '1d000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('1d000000-0000-4000-8000-000000000047', '1d000000-0000-4000-8000-000000000010', 'ADMIN', true),
  ('1d000000-0000-4000-8000-000000000048', '1d000000-0000-4000-8000-000000000010', 'GESTOR', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo) values
  ('1d000000-0000-4000-8000-000000000041', '1d000000-0000-4000-8000-000000000020', 'APONTADOR', true),
  ('1d000000-0000-4000-8000-000000000042', '1d000000-0000-4000-8000-000000000020', 'COORDENACAO', true),
  ('1d000000-0000-4000-8000-000000000043', '1d000000-0000-4000-8000-000000000020', 'TECNICO', true),
  ('1d000000-0000-4000-8000-000000000044', '1d000000-0000-4000-8000-000000000020', 'APONTADOR', true),
  ('1d000000-0000-4000-8000-000000000045', '1d000000-0000-4000-8000-000000000020', 'DIRETOR', true),
  ('1d000000-0000-4000-8000-000000000046', '1d000000-0000-4000-8000-000000000020', 'PAINEL_TV', true),
  ('1d000000-0000-4000-8000-000000000047', '1d000000-0000-4000-8000-000000000020', 'ADMIN', true),
  ('1d000000-0000-4000-8000-000000000048', '1d000000-0000-4000-8000-000000000020', 'FATURAMENTO', true);
insert into public.user_tenant_context (user_id, tenant_id)
select ('1d000000-0000-4000-8000-00000000000' || n)::uuid, '1d000000-0000-4000-8000-000000000010' from generate_series(1, 8) as n;
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
select ('1d000000-0000-4000-8000-00000000000' || n)::uuid, '1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020' from generate_series(1, 8) as n;

insert into public.colaboradores (id, nome, ativo, tenant_id, empresa_id, user_id) values
  ('1d000000-0000-4000-8000-000000000101', 'ANA', true, '1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', '1d000000-0000-4000-8000-000000000004'),
  ('1d000000-0000-4000-8000-000000000102', 'BRUNO', true, '1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', null),
  ('1d000000-0000-4000-8000-000000000103', 'CARLA', false, '1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', null),
  ('1d000000-0000-4000-8000-000000000104', 'DIEGO', true, '1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', null),
  ('1d000000-0000-4000-8000-000000000105', 'PEDRO', true, '1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', '1d000000-0000-4000-8000-000000000003'),
  ('1d000000-0000-4000-8000-000000000106', 'ZECA', true, '1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000021', null);
-- DIEGO fica sem taxa de proposito: hora interna nao exige, hora em OS exige.
insert into public.colaborador_taxas (colaborador_id, valor_hora, vigencia_inicio, tenant_id, empresa_id)
select c.id, 60, '2020-01-01', c.tenant_id, c.empresa_id
from public.colaboradores c
where c.tenant_id = '1d000000-0000-4000-8000-000000000010' and c.id <> '1d000000-0000-4000-8000-000000000104';

insert into public.tipos_horas (id, codigo, descricao, fator, ativo, tenant_id) values
  ('1d000000-0000-4000-8000-000000000301', 'NORMAL', 'Hora normal', 1, true, '1d000000-0000-4000-8000-000000000010'),
  ('1d000000-0000-4000-8000-000000000302', 'EXTRA_50', 'Hora extra 50%', 1.5, true, '1d000000-0000-4000-8000-000000000010'),
  ('1d000000-0000-4000-8000-000000000303', 'EXTRA_100', 'Hora extra 100%', 2, true, '1d000000-0000-4000-8000-000000000010');

insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social) values
  (949001, '1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', 'CLIENTE HORAS', '41111111000191', 'CLIENTE HORAS LTDA'),
  (949002, '1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000021', 'CLIENTE B', '41111111000192', 'CLIENTE B LTDA');

insert into public.ordens_servico (id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id, empresa_id,
  status_fluxo, tipo_documento, codigo, numero_doc, descricao_servico, orcado, responsavel_aprovacao_id, usa_relatorio_hh)
values
  (949001, 'HI-1', 'CLIENTE HORAS', 949001, 'em_andamento', 949001, '1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-HI-001', 1, 'Montagem do painel', 100, null, false);

-- HI-2 sem descricao de servico, com uma hora do PEDRO sem descricao: no historico do
-- aplicativo, a hora de OS sem texto nenhum continua "Apontamento de horas".
insert into public.ordens_servico (id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id, empresa_id,
  status_fluxo, tipo_documento, codigo, numero_doc, descricao_servico, orcado, responsavel_aprovacao_id, usa_relatorio_hh)
values
  (949002, 'HI-2', 'CLIENTE HORAS', 949001, 'em_andamento', 949002, '1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-HI-002', 2, null, 100, null, false);

-- Um material lancado pelo app na HI-1, para o ramo de materiais do historico.
insert into public.itens (id, codigo_interno, nome, tipo, finalidade, tenant_id, empresa_id)
values (949001, 'HI-PAR-1', 'PARAFUSO M8', 'produto', 'consumo', '1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020');
insert into public.movimentacoes (item_id, tipo, quantidade, motivo, realizado_por, data_movimentacao, tenant_id, empresa_id, origem_os_id)
values (949001, 'saida', 4, 'Material lançado pelo app na OS HI-1', '1d000000-0000-4000-8000-000000000003',
        (now() at time zone 'America/Sao_Paulo')::timestamp, '1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', 949001);

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

-- Ids das atividades e dos apontamentos criados ao longo do teste.
create temp table ids (nome text primary key, id uuid not null);
grant select, insert on ids to authenticated;
insert into ids (nome, id)
select 'ATIV_' || upper(a.codigo), a.id
from public.atividades_internas as a
where a.tenant_id = '1d000000-0000-4000-8000-000000000010' and a.empresa_id = '1d000000-0000-4000-8000-000000000020';

-- Datas escolhidas a partir do calendario do banco: o sabado, o domingo e o dia
-- util mais recentes que nao sao feriado, todos antes de hoje.
create temp table datas (nome text primary key, d date not null);
grant select on datas to authenticated;
insert into datas (nome, d)
select 'sabado', max(s.d::date) from generate_series(public.fn_tablet_data_hoje() - 56, public.fn_tablet_data_hoje() - 1, interval '1 day') as s(d)
  where extract(dow from s.d) = 6 and not exists (select 1 from public.feriados f where f.data = s.d::date)
union all
select 'domingo', max(s.d::date) from generate_series(public.fn_tablet_data_hoje() - 56, public.fn_tablet_data_hoje() - 1, interval '1 day') as s(d)
  where extract(dow from s.d) = 0 and not exists (select 1 from public.feriados f where f.data = s.d::date)
union all
select 'util', max(s.d::date) from generate_series(public.fn_tablet_data_hoje() - 56, public.fn_tablet_data_hoje() - 1, interval '1 day') as s(d)
  where extract(dow from s.d) between 1 and 5 and not exists (select 1 from public.feriados f where f.data = s.d::date);

do $datas$
declare
  v_sabado date := (select d from datas where nome = 'sabado');
  v_domingo date := (select d from datas where nome = 'domingo');
  v_util date := (select d from datas where nome = 'util');
begin
  if v_sabado is null or v_domingo is null or v_util is null then
    raise exception 'nao achei sabado, domingo e dia util sem feriado nas ultimas 8 semanas: %, %, %', v_sabado, v_domingo, v_util;
  end if;
  if extract(dow from v_sabado) <> 6 or extract(dow from v_domingo) <> 0 or extract(dow from v_util) not between 1 and 5 then
    raise exception 'datas do teste erradas: sabado %, domingo %, util %', v_sabado, v_domingo, v_util;
  end if;
end $datas$;

-- Hoje, e um feriado de teste: o dia util mais antigo da janela, bem antes do dia util
-- escolhido acima, marcado so dentro desta transacao.
insert into datas (nome, d) values ('hoje', public.fn_tablet_data_hoje());
insert into datas (nome, d)
select 'feriado', min(s.d::date) from generate_series(public.fn_tablet_data_hoje() - 56, public.fn_tablet_data_hoje() - 1, interval '1 day') as s(d)
  where extract(dow from s.d) between 1 and 5 and not exists (select 1 from public.feriados f where f.data = s.d::date)
    and s.d::date < (select x.d from datas as x where x.nome = 'util') - 7;
insert into public.feriados (data, descricao, abrangencia)
select x.d, 'Feriado de teste das horas internas', 'MUNICIPAL' from datas as x where x.nome = 'feriado';

insert into ids (nome, id)
select 'B_TREINAMENTO', a.id
from public.atividades_internas as a
where a.tenant_id = '1d000000-0000-4000-8000-000000000010' and a.empresa_id = '1d000000-0000-4000-8000-000000000021' and a.codigo = 'treinamento';

-- A hora em OS de hoje do BRUNO: 4h na HI-1. Serve de contraste nas leituras, no
-- custo e no resumo do tablet ("OS HI-1" ao lado da atividade).
insert into public.apontamentos_horas (id, os_id, colaborador_id, data, horas, tipo_hora_id, descricao, tenant_id, empresa_id)
values ('1d000000-0000-4000-8000-00000000a001', 949001, '1d000000-0000-4000-8000-000000000102', public.fn_tablet_data_hoje(), 4,
        '1d000000-0000-4000-8000-000000000301', 'Montagem na HI-1', '1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020');
insert into public.apontamentos_horas (id, os_id, colaborador_id, data, horas, tipo_hora_id, descricao, tenant_id, empresa_id)
values ('1d000000-0000-4000-8000-00000000a002', 949002, '1d000000-0000-4000-8000-000000000105', public.fn_tablet_data_hoje() - 2, 2,
        '1d000000-0000-4000-8000-000000000301', null, '1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020');

-- O custo antes de qualquer hora interna existir, para comparar no bloco 6.
create temp table custo_antes as
select
  (select count(*) from public.vw_apontamentos_horas_custo as v
     join public.colaboradores as c on c.id = v.colaborador_id
    where c.tenant_id = '1d000000-0000-4000-8000-000000000010') as linhas_fixture,
  (select coalesce(sum(v.total_horas), 0) from public.vw_custo_mao_obra_os as v where v.os_id = 949001) as horas_os,
  (select coalesce(sum(v.custo_mao_obra), 0) from public.vw_custo_mao_obra_os as v where v.os_id = 949001) as custo_os,
  (select count(*) from public.vw_custo_mao_obra_os as v where v.os_id is null) as grupos_sem_os,
  (select coalesce(sum(v.total_horas), 0) from public.vw_custo_mao_obra_os as v where v.os_id is null) as horas_sem_os;

create or replace function pg_temp.tem_erro(r jsonb, p_tipo text) returns boolean language sql immutable as $$
  select exists (select 1 from jsonb_array_elements(coalesce(r->'erros', '[]'::jsonb)) as e where e->>'tipo' = p_tipo);
$$;
create or replace function pg_temp.tem_aviso(r jsonb, p_tipo text) returns boolean language sql immutable as $$
  select exists (select 1 from jsonb_array_elements(coalesce(r->'avisos', '[]'::jsonb)) as e where e->>'tipo' = p_tipo);
$$;
create or replace function pg_temp.ok(r jsonb) returns boolean language sql immutable as $$
  select coalesce((r->>'sucesso')::boolean, false);
$$;
create or replace function pg_temp.lote(p_colaborador text, p_horas numeric) returns jsonb language sql immutable as $$
  select jsonb_build_array(jsonb_build_object('colaborador_id', p_colaborador, 'horas', p_horas));
$$;
-- Ids e datas registrados pelo teste, com erro claro quando faltam.
create or replace function pg_temp.ap(p_nome text) returns uuid language plpgsql as $$
declare v_id uuid;
begin
  select i.id into v_id from ids as i where i.nome = p_nome;
  if v_id is null then raise exception 'o teste nao registrou o id %', p_nome; end if;
  return v_id;
end $$;
create or replace function pg_temp.d(p_nome text) returns date language plpgsql as $$
declare v_d date;
begin
  select x.d into v_d from datas as x where x.nome = p_nome;
  if v_d is null then raise exception 'o teste nao registrou a data %', p_nome; end if;
  return v_d;
end $$;

-- =====================================================================================
-- 1. Catalogo: a empresa nasce com as seis, so Comercial pede cliente, tabela fechada.
-- =====================================================================================
do $catalogo$
declare
  v_codigos text[];
begin
  select array_agg(a.codigo order by a.ordem) into v_codigos
  from public.atividades_internas as a
  where a.tenant_id = '1d000000-0000-4000-8000-000000000010' and a.empresa_id = '1d000000-0000-4000-8000-000000000020';
  if v_codigos is distinct from array['comercial', 'treinamento', 'manutencao_fabrica', 'administrativo', 'exames', 'integracao'] then
    raise exception 'catalogo de partida da empresa A: %', v_codigos;
  end if;
  select array_agg(a.codigo) into v_codigos
  from public.atividades_internas as a
  where a.tenant_id = '1d000000-0000-4000-8000-000000000010' and a.empresa_id = '1d000000-0000-4000-8000-000000000020' and a.pede_cliente;
  if v_codigos is distinct from array['comercial'] then raise exception 'so Comercial devia pedir cliente: %', v_codigos; end if;
  if exists (select 1 from public.atividades_internas as a where a.tenant_id = '1d000000-0000-4000-8000-000000000010' and not a.ativo) then
    raise exception 'atividade de partida nasceu inativa';
  end if;
  if (select count(*) from public.atividades_internas as a where a.empresa_id = '1d000000-0000-4000-8000-000000000021') <> 6 then
    raise exception 'empresa B devia nascer com as seis atividades';
  end if;
  if (select nome from public.atividades_internas where id = (select id from ids where nome = 'ATIV_MANUTENCAO_FABRICA')) <> 'Manutenção da fábrica' then
    raise exception 'nome da manutencao da fabrica';
  end if;

  -- So as funcoes leem e gravam; o nucleo e os semeadores nao sao chamaveis de fora.
  if has_table_privilege('authenticated', 'public.atividades_internas', 'select')
     or has_table_privilege('authenticated', 'public.atividades_internas', 'insert') then
    raise exception 'authenticated le ou grava atividades_internas direto';
  end if;
  if has_function_privilege('authenticated', 'public.fn_atividades_internas_semear(uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_horas_internas_gravar(uuid, uuid, uuid, date, jsonb, text, integer, text, text, boolean, uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_horas_internas_pode_lancar(uuid, uuid, uuid, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_tablet_resumo_dia_interno(uuid, uuid, uuid, uuid, date)', 'execute') then
    raise exception 'funcao interna das horas internas ficou aberta para authenticated';
  end if;
  if has_function_privilege('anon', 'public.app_lancar_horas_internas(uuid, date, jsonb, text, integer, text, text, boolean)', 'execute')
     or has_function_privilege('anon', 'public.app_tablet_lancar_horas_internas(text, uuid, date, integer, integer, uuid, boolean)', 'execute')
     or has_function_privilege('anon', 'public.web_horas_internas_resumo(date, date)', 'execute') then
    raise exception 'funcao de horas internas aberta para anon';
  end if;
  -- fn_tablet_validar_sessao faz FOR UPDATE: quem a chama nao pode ser STABLE, senao a
  -- chamada pelo PostgREST (transacao somente leitura) quebra.
  if (select p.provolatile from pg_proc as p where p.oid = 'public.app_tablet_atividades(text)'::regprocedure) <> 'v' then
    raise exception 'app_tablet_atividades voltou a ser STABLE/IMMUTABLE';
  end if;
end $catalogo$;

-- Diretor: leitura do aplicativo, do tablet e o cadastro.
select pg_temp.como('1d000000-0000-4000-8000-000000000005');
set local role authenticated;
do $catalogo_diretor$
declare
  r jsonb;
  v_codigos text[];
  v_visita uuid;
begin
  select array_agg(a.codigo order by a.ordem, a.nome) into v_codigos from public.app_atividades_internas() as a;
  if v_codigos is distinct from array['comercial', 'treinamento', 'manutencao_fabrica', 'administrativo', 'exames', 'integracao'] then
    raise exception 'app_atividades_internas(): %', v_codigos;
  end if;
  if (select a.codigo from public.app_atividades_internas() as a limit 1) <> 'comercial' then
    raise exception 'app_atividades_internas devia vir em ordem, comercial primeiro';
  end if;
  select array_agg(a.codigo order by a.ordem, a.nome) into v_codigos from public.app_atividades_internas(true) as a;
  if v_codigos is distinct from array['treinamento', 'manutencao_fabrica', 'administrativo', 'exames', 'integracao'] then
    raise exception 'app_atividades_internas(true) nao devia trazer a comercial: %', v_codigos;
  end if;

  if (select count(*) from public.web_atividades_internas_listar()) <> 6
     or (select sum(em_uso) from public.web_atividades_internas_listar()) <> 0 then
    raise exception 'cadastro devia listar as seis sem uso';
  end if;

  -- Nova, inativa, codigo tirado do nome (sem acento).
  r := public.web_atividade_interna_salvar(null, null, 'Visita técnica', false, false, 70);
  if not pg_temp.ok(r) then raise exception 'cadastrar atividade: %', r; end if;
  v_visita := (r->>'id')::uuid;
  insert into ids values ('ATIV_VISITA', v_visita);
  if (select codigo from public.web_atividades_internas_listar() where id = v_visita) <> 'visita_tecnica' then
    raise exception 'codigo tirado do nome: %', (select codigo from public.web_atividades_internas_listar() where id = v_visita);
  end if;
  if (select count(*) from public.web_atividades_internas_listar()) <> 7 then raise exception 'cadastro devia listar a inativa'; end if;
  if (select codigo from public.web_atividades_internas_listar() offset 6 limit 1) <> 'visita_tecnica' then
    raise exception 'a inativa devia vir por ultimo no cadastro';
  end if;
  if exists (select 1 from public.app_atividades_internas() where id = v_visita) then raise exception 'inativa apareceu no aplicativo'; end if;

  -- Editar pelo id.
  r := public.web_atividade_interna_salvar(v_visita, 'visita_tecnica', 'Visita ao cliente', false, false, 75);
  if not pg_temp.ok(r) or (r->>'id')::uuid <> v_visita then raise exception 'editar atividade: %', r; end if;
  if (select nome from public.web_atividades_internas_listar() where id = v_visita) <> 'Visita ao cliente' then raise exception 'edicao nao gravou o nome'; end if;

  -- Codigo repetido, na criacao e na edicao.
  begin
    perform public.web_atividade_interna_salvar(null, 'treinamento', 'Outro treinamento', false, true, 0);
    raise exception 'aceitou codigo repetido na criacao';
  exception when others then
    if sqlerrm <> 'Já existe uma atividade com o código "treinamento".' then raise; end if;
  end;
  begin
    perform public.web_atividade_interna_salvar(v_visita, 'comercial', 'Visita ao cliente', false, false, 75);
    raise exception 'aceitou codigo repetido na edicao';
  exception when others then
    if sqlerrm <> 'Já existe uma atividade com o código "comercial".' then raise; end if;
  end;
  begin
    perform public.web_atividade_interna_salvar(null, 'sem_nome', '   ', false, true, 0);
    raise exception 'aceitou atividade sem nome';
  exception when others then
    if sqlerrm <> 'Informe o nome da atividade.' then raise; end if;
  end;
  -- Atividade de outra empresa nao se edita daqui.
  begin
    perform public.web_atividade_interna_salvar((select id from ids where nome = 'B_TREINAMENTO'), 'treinamento', 'Sequestrada', false, true, 0);
    raise exception 'editou atividade da empresa B';
  exception when others then
    if sqlerrm <> 'Atividade não encontrada nesta empresa.' then raise; end if;
  end;
end $catalogo_diretor$;
reset role;
select pg_temp.sistema();

-- Coordenacao e Admin tambem cuidam do cadastro.
select pg_temp.como('1d000000-0000-4000-8000-000000000002');
set local role authenticated;
do $catalogo_coord$
declare r jsonb;
begin
  if (select count(*) from public.web_atividades_internas_listar()) <> 7 then raise exception 'coordenacao nao listou o cadastro'; end if;
  r := public.web_atividade_interna_salvar((select id from ids where nome = 'ATIV_VISITA'), 'visita_tecnica', 'Visita ao cliente', false, false, 80);
  if not pg_temp.ok(r) then raise exception 'coordenacao nao salvou: %', r; end if;
end $catalogo_coord$;
reset role;
select pg_temp.sistema();

select pg_temp.como('1d000000-0000-4000-8000-000000000007');
set local role authenticated;
do $catalogo_admin$
begin
  if (select count(*) from public.web_atividades_internas_listar()) <> 7 then raise exception 'admin nao listou o cadastro'; end if;
end $catalogo_admin$;
reset role;
select pg_temp.sistema();

-- Quem nao e gestao: le a lista do aplicativo, mas nao abre o cadastro.
create or replace function pg_temp.cadastro_fechado(p_quem text) returns void language plpgsql as $$
begin
  begin
    perform public.web_atividades_internas_listar();
    raise exception '% listou o cadastro de atividades', p_quem;
  exception when others then
    if sqlerrm <> 'O cadastro de atividades internas é da gestão.' then raise; end if;
  end;
  begin
    perform public.web_atividade_interna_salvar(null, 'intrusa', 'Intrusa', false, true, 0);
    raise exception '% salvou atividade', p_quem;
  exception when others then
    if sqlerrm <> 'O cadastro de atividades internas é da gestão.' then raise; end if;
  end;
end $$;

select pg_temp.como('1d000000-0000-4000-8000-000000000004');
set local role authenticated;
do $catalogo_ana$
begin
  perform pg_temp.cadastro_fechado('APONTADOR');
  if (select count(*) from public.app_atividades_internas()) <> 6 then raise exception 'ANA devia ler as seis ativas no aplicativo'; end if;
end $catalogo_ana$;
reset role;
select pg_temp.sistema();

select pg_temp.como('1d000000-0000-4000-8000-000000000003');
set local role authenticated;
do $catalogo_tecnico$ begin perform pg_temp.cadastro_fechado('TECNICO'); end $catalogo_tecnico$;
reset role;
select pg_temp.sistema();

select pg_temp.como('1d000000-0000-4000-8000-000000000008');
set local role authenticated;
do $catalogo_faturamento$ begin perform pg_temp.cadastro_fechado('FATURAMENTO'); end $catalogo_faturamento$;
reset role;
select pg_temp.sistema();

select pg_temp.como('1d000000-0000-4000-8000-000000000006');
set local role authenticated;
do $catalogo_tv$ begin perform pg_temp.cadastro_fechado('PAINEL_TV'); end $catalogo_tv$;
reset role;
select pg_temp.sistema();

-- =====================================================================================
-- 1b. O codigo que o cadastro grava, Admin tambem salvando, e a empresa nova.
-- =====================================================================================
select pg_temp.como('1d000000-0000-4000-8000-000000000005');
set local role authenticated;
do $codigo$
declare
  r jsonb;
  v_codigo text;
begin
  -- "Comercial2" digitado: baixa a caixa sem comer a primeira letra.
  r := public.web_atividade_interna_salvar(null, 'Comercial2', 'Comercial 2', false, false, 91);
  if not pg_temp.ok(r) then raise exception 'salvar "Comercial2": %', r; end if;
  insert into ids values ('ATIV_COMERCIAL2', (r->>'id')::uuid);
  select l.codigo into v_codigo from public.web_atividades_internas_listar() as l where l.id = (r->>'id')::uuid;
  if v_codigo is distinct from 'comercial2' then raise exception '"Comercial2" devia virar comercial2, ficou %', v_codigo; end if;

  -- Codigo em branco: sai do nome, sem acento, com "_" no lugar dos espacos.
  r := public.web_atividade_interna_salvar(null, '   ', 'Manutenção da Fábrica X', false, false, 92);
  if not pg_temp.ok(r) then raise exception 'salvar sem codigo: %', r; end if;
  select l.codigo into v_codigo from public.web_atividades_internas_listar() as l where l.id = (r->>'id')::uuid;
  if v_codigo is distinct from 'manutencao_da_fabrica_x' then
    raise exception '"Manutenção da Fábrica X" devia virar manutencao_da_fabrica_x, ficou %', v_codigo;
  end if;

  -- Codigo que comeca com numero, ou que fica vazio depois de limpo.
  foreach v_codigo in array array['2x', '_'] loop
    begin
      perform public.web_atividade_interna_salvar(null, v_codigo, 'Código inválido', false, false, 93);
      raise exception 'aceitou o codigo "%"', v_codigo;
    exception when others then
      if sqlerrm not like 'O código precisa começar com letra%' then raise; end if;
    end;
  end loop;

  -- Repetido depois de normalizado: "Comercial" vira o comercial de partida.
  begin
    perform public.web_atividade_interna_salvar(null, 'Comercial', 'Comercial de novo', false, false, 94);
    raise exception 'aceitou "Comercial", que normaliza para um codigo que ja existe';
  exception when others then
    if sqlerrm not like 'Já existe%' then raise; end if;
  end;

  -- Seis de partida, a visita, comercial2 e manutencao_da_fabrica_x; nada das recusadas.
  if (select count(*) from public.web_atividades_internas_listar()) <> 9 then
    raise exception 'cadastro devia ter 9 atividades: %', (select array_agg(l.codigo) from public.web_atividades_internas_listar() as l);
  end if;
end $codigo$;
reset role;
select pg_temp.sistema();

-- Admin tambem salva (Coordenacao ja salvou no bloco 1).
select pg_temp.como('1d000000-0000-4000-8000-000000000007');
set local role authenticated;
do $codigo_admin$
declare r jsonb;
begin
  r := public.web_atividade_interna_salvar(pg_temp.ap('ATIV_COMERCIAL2'), 'comercial2', 'Comercial de peças', false, false, 91);
  if not pg_temp.ok(r) then raise exception 'admin nao salvou: %', r; end if;
  if (select l.nome from public.web_atividades_internas_listar() as l where l.id = pg_temp.ap('ATIV_COMERCIAL2')) <> 'Comercial de peças' then
    raise exception 'a edicao do admin nao gravou';
  end if;
end $codigo_admin$;
reset role;
select pg_temp.sistema();

do $empresa_nova$
declare
  v_seis constant text[] := array['comercial', 'treinamento', 'manutencao_fabrica', 'administrativo', 'exames', 'integracao'];
  v_codigos text[];
begin
  -- A migration semeou as empresas que ja existiam no banco.
  if exists (
    select 1
    from c.empresa as e
    join public.empresas as pe on pe.id = e.id
    where e.tenant_id <> '1d000000-0000-4000-8000-000000000010'
      and not coalesce((select array_agg(a.codigo) from public.atividades_internas as a
                         where a.tenant_id = e.tenant_id and a.empresa_id = e.id), '{}'::text[]) @> v_seis
  ) then
    raise exception 'existe empresa do banco sem as seis atividades de partida';
  end if;

  -- Empresa nova gravada em public.empresas: o gatilho trg_empresas_atividades_internas
  -- da as seis, na ordem, ativas, e so a Comercial pede cliente.
  insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo)
  values ('1d000000-0000-4000-8000-000000000022', '1d000000-0000-4000-8000-000000000010', 'HI-C', 'Empresa horas C', 'Empresa C', '41000000000300', true);
  insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo)
  values ('1d000000-0000-4000-8000-000000000022', '1d000000-0000-4000-8000-000000000010', '41000000000300', 'Empresa horas C', 'Empresa C', true);
  select array_agg(a.codigo order by a.ordem) into v_codigos
  from public.atividades_internas as a
  where a.tenant_id = '1d000000-0000-4000-8000-000000000010' and a.empresa_id = '1d000000-0000-4000-8000-000000000022';
  if v_codigos is distinct from v_seis then raise exception 'empresa nova nasceu com %', v_codigos; end if;
  if exists (
    select 1 from public.atividades_internas as a
    where a.empresa_id = '1d000000-0000-4000-8000-000000000022' and (not a.ativo or a.pede_cliente <> (a.codigo = 'comercial'))
  ) then
    raise exception 'empresa nova nasceu com atividade inativa ou pedindo cliente fora da Comercial';
  end if;

  -- A tela Admin > Empresas (app/admin/empresas/page.tsx) grava so em c.empresa, sem
  -- public.empresas: o gatilho trg_c_empresa_atividades_internas tambem da as seis. (Achado
  -- na revisao de 14/09/2026; antes a empresa criada pela tela ficava sem catalogo.)
  insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo)
  values ('1d000000-0000-4000-8000-000000000023', '1d000000-0000-4000-8000-000000000010', 'HI-D', 'Empresa horas D', 'Empresa D', '41000000000400', true);
  select array_agg(a.codigo order by a.ordem) into v_codigos from public.atividades_internas as a
   where a.empresa_id = '1d000000-0000-4000-8000-000000000023';
  if v_codigos is distinct from v_seis then raise exception 'empresa criada em c.empresa nasceu com %', v_codigos; end if;
end $empresa_nova$;

create temp table apontamento_sem_gatilho (like public.apontamentos_horas including constraints including defaults);

-- =====================================================================================
-- 2. OS ou atividade, uma so; cliente e orcamento so na hora interna. Por fora das
--    funcoes (como postgres), que e onde a regra da tabela tem de segurar sozinha.
-- =====================================================================================
do $destino$
declare
  v_hoje date := public.fn_tablet_data_hoje();
  v_trein uuid := (select id from ids where nome = 'ATIV_TREINAMENTO');
  v_c text;
  v_antes bigint := (select count(*) from public.apontamentos_horas where tenant_id = '1d000000-0000-4000-8000-000000000010');
begin
  -- OS e atividade juntas: o gatilho entra no ramo da atividade e a restricao barra.
  begin
    insert into public.apontamentos_horas (tenant_id, empresa_id, os_id, atividade_id, colaborador_id, data, horas, tipo_hora_id)
    values ('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', 949001, v_trein,
            '1d000000-0000-4000-8000-000000000102', v_hoje, 1, '1d000000-0000-4000-8000-000000000301');
    raise exception 'hora com OS e atividade foi gravada';
  exception when check_violation then
    get stacked diagnostics v_c = constraint_name;
    if v_c <> 'chk_apontamentos_horas_destino' then raise exception 'OS e atividade barrada pela restricao errada: %', v_c; end if;
  end;

  -- Nenhuma das duas: com os gatilhos, o validador ja recusa (cai no ramo da OS)...
  begin
    insert into public.apontamentos_horas (tenant_id, empresa_id, os_id, atividade_id, colaborador_id, data, horas, tipo_hora_id)
    values ('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', null, null,
            '1d000000-0000-4000-8000-000000000102', v_hoje, 1, '1d000000-0000-4000-8000-000000000301');
    raise exception 'hora sem OS e sem atividade foi gravada';
  exception when others then
    if sqlerrm not like 'OS % não encontrada.' then raise; end if;
  end;
  -- ...e sem gatilho nenhum, quem segura e a restricao. A copia da tabela
  -- (apontamento_sem_gatilho) leva as restricoes CHECK com o mesmo nome e nenhum
  -- gatilho. (session_replication_role nao pode ser mudado por este papel.)
  begin
    insert into apontamento_sem_gatilho (tenant_id, empresa_id, os_id, atividade_id, colaborador_id, data, horas, tipo_hora_id)
    values ('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', null, null,
            '1d000000-0000-4000-8000-000000000102', v_hoje, 1, '1d000000-0000-4000-8000-000000000301');
    raise exception 'hora sem OS e sem atividade passou pela restricao';
  exception when check_violation then
    get stacked diagnostics v_c = constraint_name;
    if v_c <> 'chk_apontamentos_horas_destino' then raise exception 'nenhum destino barrado pela restricao errada: %', v_c; end if;
  end;
  begin
    insert into apontamento_sem_gatilho (tenant_id, empresa_id, os_id, atividade_id, colaborador_id, data, horas, tipo_hora_id)
    values ('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', 949001, v_trein,
            '1d000000-0000-4000-8000-000000000102', v_hoje, 1, '1d000000-0000-4000-8000-000000000301');
    raise exception 'hora com OS e atividade passou pela restricao';
  exception when check_violation then
    get stacked diagnostics v_c = constraint_name;
    if v_c <> 'chk_apontamentos_horas_destino' then raise exception 'OS e atividade (sem gatilho) barrada pela restricao errada: %', v_c; end if;
  end;
  begin
    insert into apontamento_sem_gatilho (tenant_id, empresa_id, atividade_id, colaborador_id, data, horas, tipo_hora_id, cliente_id, cliente_nome, orcamento_descricao)
    values ('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', v_trein,
            '1d000000-0000-4000-8000-000000000102', v_hoje, 1, '1d000000-0000-4000-8000-000000000301', 949001, 'CLIENTE', 'orcamento');
  exception when check_violation then
    raise exception 'a restricao recusou cliente e orcamento numa hora interna';
  end;
  begin
    insert into apontamento_sem_gatilho (tenant_id, empresa_id, os_id, colaborador_id, data, horas, tipo_hora_id, cliente_nome)
    values ('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', 949001,
            '1d000000-0000-4000-8000-000000000102', v_hoje, 1, '1d000000-0000-4000-8000-000000000301', 'CLIENTE');
    raise exception 'cliente numa hora de OS passou pela restricao';
  exception when check_violation then
    get stacked diagnostics v_c = constraint_name;
    if v_c <> 'chk_apontamentos_horas_cliente_so_interna' then raise exception 'cliente na OS (sem gatilho) barrado pela restricao errada: %', v_c; end if;
  end;

  -- Cliente, nome digitado ou orcamento numa hora de OS.
  begin
    insert into public.apontamentos_horas (tenant_id, empresa_id, os_id, colaborador_id, data, horas, tipo_hora_id, cliente_nome)
    values ('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', 949001,
            '1d000000-0000-4000-8000-000000000102', v_hoje, 1, '1d000000-0000-4000-8000-000000000301', 'CLIENTE DIGITADO');
    raise exception 'hora de OS aceitou cliente_nome';
  exception when check_violation then
    get stacked diagnostics v_c = constraint_name;
    if v_c <> 'chk_apontamentos_horas_cliente_so_interna' then raise exception 'cliente_nome na OS barrado pela restricao errada: %', v_c; end if;
  end;
  begin
    insert into public.apontamentos_horas (tenant_id, empresa_id, os_id, colaborador_id, data, horas, tipo_hora_id, cliente_id)
    values ('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', 949001,
            '1d000000-0000-4000-8000-000000000102', v_hoje, 1, '1d000000-0000-4000-8000-000000000301', 949001);
    raise exception 'hora de OS aceitou cliente_id';
  exception when check_violation then
    get stacked diagnostics v_c = constraint_name;
    if v_c <> 'chk_apontamentos_horas_cliente_so_interna' then raise exception 'cliente_id na OS barrado pela restricao errada: %', v_c; end if;
  end;
  begin
    insert into public.apontamentos_horas (tenant_id, empresa_id, os_id, colaborador_id, data, horas, tipo_hora_id, orcamento_descricao)
    values ('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', 949001,
            '1d000000-0000-4000-8000-000000000102', v_hoje, 1, '1d000000-0000-4000-8000-000000000301', 'painel');
    raise exception 'hora de OS aceitou orcamento';
  exception when check_violation then
    get stacked diagnostics v_c = constraint_name;
    if v_c <> 'chk_apontamentos_horas_cliente_so_interna' then raise exception 'orcamento na OS barrado pela restricao errada: %', v_c; end if;
  end;

  -- O validador segura as regras da atividade tambem por fora das funcoes.
  begin
    insert into public.apontamentos_horas (tenant_id, empresa_id, atividade_id, colaborador_id, data, horas, tipo_hora_id)
    values ('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', (select id from ids where nome = 'ATIV_COMERCIAL'),
            '1d000000-0000-4000-8000-000000000102', v_hoje, 1, '1d000000-0000-4000-8000-000000000301');
    raise exception 'comercial sem cliente gravou por fora';
  exception when others then
    if sqlerrm not like 'Hora em Comercial pede o cliente%' then raise; end if;
  end;
  begin
    insert into public.apontamentos_horas (tenant_id, empresa_id, atividade_id, colaborador_id, data, horas, tipo_hora_id, cliente_nome)
    values ('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', (select id from ids where nome = 'ATIV_COMERCIAL'),
            '1d000000-0000-4000-8000-000000000102', v_hoje, 1, '1d000000-0000-4000-8000-000000000301', 'ALGUEM');
    raise exception 'comercial sem orcamento gravou por fora';
  exception when others then
    if sqlerrm not like 'Hora em Comercial pede qual orçamento%' then raise; end if;
  end;
  begin
    insert into public.apontamentos_horas (tenant_id, empresa_id, atividade_id, colaborador_id, data, horas, tipo_hora_id)
    values ('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', (select id from ids where nome = 'B_TREINAMENTO'),
            '1d000000-0000-4000-8000-000000000102', v_hoje, 1, '1d000000-0000-4000-8000-000000000301');
    raise exception 'atividade da empresa B gravou na A';
  exception when others then
    if sqlerrm <> 'Atividade interna não encontrada nesta empresa.' then raise; end if;
  end;
  begin
    insert into public.apontamentos_horas (tenant_id, empresa_id, atividade_id, colaborador_id, data, horas, tipo_hora_id)
    values ('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', (select id from ids where nome = 'ATIV_VISITA'),
            '1d000000-0000-4000-8000-000000000102', v_hoje, 1, '1d000000-0000-4000-8000-000000000301');
    raise exception 'atividade inativa gravou por fora';
  exception when others then
    if sqlerrm not like 'A atividade "Visita ao cliente" está inativa%' then raise; end if;
  end;

  if (select count(*) from public.apontamentos_horas where tenant_id = '1d000000-0000-4000-8000-000000000010') <> v_antes then
    raise exception 'alguma hora recusada ficou gravada';
  end if;
end $destino$;

-- =====================================================================================
-- 3. Lancar pelo aplicativo e pela web (app_lancar_horas_internas), como Coordenacao, que
--    lanca para qualquer pessoa da empresa.
-- =====================================================================================
select pg_temp.como('1d000000-0000-4000-8000-000000000002');
set local role authenticated;
do $lancar_recusas$
declare
  r jsonb;
  v_hoje date := pg_temp.d('hoje');
  v_comercial uuid := pg_temp.ap('ATIV_COMERCIAL');
  v_treinamento uuid := pg_temp.ap('ATIV_TREINAMENTO');
  v_ana constant text := '1d000000-0000-4000-8000-000000000101';
begin
  -- Comercial sem cliente e sem orcamento: os dois erros de uma vez, nada gravado.
  r := public.app_lancar_horas_internas(v_comercial, v_hoje, pg_temp.lote(v_ana, 1), null, null, null, null, true);
  if pg_temp.ok(r) or (r->>'gravados')::integer <> 0
     or not pg_temp.tem_erro(r, 'cliente') or not pg_temp.tem_erro(r, 'orcamento') then
    raise exception 'Comercial sem cliente e sem orcamento: %', r;
  end if;
  -- Nome digitado so com espacos nao conta como cliente.
  r := public.app_lancar_horas_internas(v_comercial, v_hoje, pg_temp.lote(v_ana, 1), null, null, '   ', 'painel da linha 3', true);
  if pg_temp.ok(r) or not pg_temp.tem_erro(r, 'cliente') or pg_temp.tem_erro(r, 'orcamento') then
    raise exception 'Comercial com nome de cliente em branco: %', r;
  end if;
  -- Cliente do cadastro, sem orcamento.
  r := public.app_lancar_horas_internas(v_comercial, v_hoje, pg_temp.lote(v_ana, 1), null, 949001, null, '   ', true);
  if pg_temp.ok(r) or pg_temp.tem_erro(r, 'cliente') or not pg_temp.tem_erro(r, 'orcamento') then
    raise exception 'Comercial sem orcamento: %', r;
  end if;
  -- Cliente de outra empresa.
  r := public.app_lancar_horas_internas(v_comercial, v_hoje, pg_temp.lote(v_ana, 1), null, 949002, null, 'painel da linha 3', true);
  if pg_temp.ok(r) or r->'erros'->0->>'mensagem' is distinct from 'Cliente não encontrado nesta empresa.' then
    raise exception 'cliente da empresa B aceito na A: %', r;
  end if;
  -- Atividade inativa; atividade de outra empresa.
  r := public.app_lancar_horas_internas(pg_temp.ap('ATIV_VISITA'), v_hoje, pg_temp.lote(v_ana, 1), null, null, null, null, true);
  if pg_temp.ok(r) or r->'erros'->0->>'mensagem' is distinct from 'A atividade "Visita ao cliente" está inativa.' then
    raise exception 'atividade inativa aceita: %', r;
  end if;
  r := public.app_lancar_horas_internas(pg_temp.ap('B_TREINAMENTO'), v_hoje, pg_temp.lote(v_ana, 1), null, null, null, null, true);
  if pg_temp.ok(r) or r->'erros'->0->>'mensagem' is distinct from 'Escolha a atividade.' then
    raise exception 'atividade da empresa B aceita: %', r;
  end if;
  -- Data futura; lote vazio; pessoa inativa; pessoa de outra empresa; horas fora da faixa;
  -- a mesma pessoa duas vezes no lote.
  r := public.app_lancar_horas_internas(v_treinamento, v_hoje + 1, pg_temp.lote(v_ana, 1), null, null, null, null, true);
  if pg_temp.ok(r) or not pg_temp.tem_erro(r, 'data_futura') then raise exception 'data futura aceita: %', r; end if;
  r := public.app_lancar_horas_internas(v_treinamento, v_hoje, '[]'::jsonb, null, null, null, null, true);
  if pg_temp.ok(r) or not pg_temp.tem_erro(r, 'lancamentos') then raise exception 'lote vazio aceito: %', r; end if;
  r := public.app_lancar_horas_internas(v_treinamento, v_hoje, pg_temp.lote('1d000000-0000-4000-8000-000000000103', 1), null, null, null, null, true);
  if pg_temp.ok(r) or not pg_temp.tem_erro(r, 'colaborador_inativo') then raise exception 'CARLA, inativa, aceita: %', r; end if;
  r := public.app_lancar_horas_internas(v_treinamento, v_hoje, pg_temp.lote('1d000000-0000-4000-8000-000000000106', 1), null, null, null, null, true);
  if pg_temp.ok(r) or r->'erros'->0->>'mensagem' is distinct from 'Colaborador não pertence a esta empresa.' then
    raise exception 'ZECA, da empresa B, aceito: %', r;
  end if;
  r := public.app_lancar_horas_internas(v_treinamento, v_hoje, pg_temp.lote(v_ana, 0), null, null, null, null, true);
  if pg_temp.ok(r) or not pg_temp.tem_erro(r, 'horas') then raise exception 'zero hora aceita: %', r; end if;
  r := public.app_lancar_horas_internas(v_treinamento, v_hoje, pg_temp.lote(v_ana, 24.5), null, null, null, null, true);
  if pg_temp.ok(r) or not pg_temp.tem_erro(r, 'horas') then raise exception '24,5 h aceitas: %', r; end if;
  r := public.app_lancar_horas_internas(v_treinamento, v_hoje,
         jsonb_build_array(jsonb_build_object('colaborador_id', v_ana, 'horas', 1), jsonb_build_object('colaborador_id', v_ana, 'horas', 2)),
         null, null, null, null, true);
  if pg_temp.ok(r) or not pg_temp.tem_erro(r, 'lote_duplicado') then raise exception 'mesma pessoa duas vezes no lote: %', r; end if;
end $lancar_recusas$;
reset role;
select pg_temp.sistema();

do $lancar_recusas_nada$
begin
  if exists (select 1 from public.apontamentos_horas where tenant_id = '1d000000-0000-4000-8000-000000000010' and atividade_id is not null) then
    raise exception 'alguma hora interna recusada ficou gravada';
  end if;
end $lancar_recusas_nada$;

select pg_temp.como('1d000000-0000-4000-8000-000000000002');
set local role authenticated;
do $lancar$
declare
  r jsonb;
  v_hoje date := pg_temp.d('hoje');
  v_comercial uuid := pg_temp.ap('ATIV_COMERCIAL');
begin
  -- Primeiro contato: o cliente ainda nao existe no cadastro e vai o nome digitado.
  r := public.app_lancar_horas_internas(v_comercial, v_hoje, pg_temp.lote('1d000000-0000-4000-8000-000000000101', 1),
         '   ', null, '  PADARIA NOVA  ', '  painel da linha 3 ', false);
  if not pg_temp.ok(r) or (r->>'gravados')::integer <> 1 or r->>'atividade_nome' <> 'Comercial' or (r->>'data')::date <> v_hoje then
    raise exception 'Comercial com nome digitado: %', r;
  end if;
  insert into ids values ('AP_COMERCIAL_DIGITADO', (r->'apontamento_ids'->>0)::uuid);

  -- Cliente do cadastro, para o PEDRO.
  r := public.app_lancar_horas_internas(v_comercial, v_hoje, pg_temp.lote('1d000000-0000-4000-8000-000000000105', 1.5),
         'reunião de levantamento', 949001, null, 'retrofit da prensa', false);
  if not pg_temp.ok(r) or (r->>'gravados')::integer <> 1 then raise exception 'Comercial com cliente do cadastro: %', r; end if;
  insert into ids values ('AP_COMERCIAL_CADASTRO', (r->'apontamento_ids'->>0)::uuid);

  -- DIEGO nao tem taxa: na OS seria recusado, na atividade interna grava.
  r := public.app_lancar_horas_internas(pg_temp.ap('ATIV_INTEGRACAO'), v_hoje, pg_temp.lote('1d000000-0000-4000-8000-000000000104', 2),
         'primeiro dia na empresa', null, null, null, false);
  if not pg_temp.ok(r) or (r->>'gravados')::integer <> 1 then raise exception 'Integracao do DIEGO, sem taxa: %', r; end if;
  insert into ids values ('AP_INTEGRACAO_DIEGO', (r->'apontamento_ids'->>0)::uuid);

  -- Duplicidade: mesma atividade, pessoa, data e tipo de hora ja lancados. No Comercial,
  -- tambem o mesmo cliente e o mesmo orcamento, sem diferenca de maiusculas.
  r := public.app_lancar_horas_internas(v_comercial, v_hoje, pg_temp.lote('1d000000-0000-4000-8000-000000000101', 1),
         null, null, 'padaria nova', 'PAINEL DA LINHA 3', true);
  if pg_temp.ok(r) or (r->>'gravados')::integer <> 0 or r->'erros'->0->>'tipo' is distinct from 'duplicidade' then
    raise exception 'Comercial repetido (mesmo cliente e orcamento) aceito: %', r;
  end if;
  r := public.app_lancar_horas_internas(pg_temp.ap('ATIV_INTEGRACAO'), v_hoje, pg_temp.lote('1d000000-0000-4000-8000-000000000104', 2),
         'de novo', null, null, null, true);
  if pg_temp.ok(r) or (r->>'gravados')::integer <> 0 or r->'erros'->0->>'tipo' is distinct from 'duplicidade' then
    raise exception 'Integracao repetida aceita: %', r;
  end if;
  -- Outro orcamento do mesmo cliente, ou outro cliente com o mesmo orcamento, no mesmo dia: e outra coisa.
  r := public.app_lancar_horas_internas(v_comercial, v_hoje, pg_temp.lote('1d000000-0000-4000-8000-000000000101', 1),
         null, null, 'PADARIA NOVA', 'painel da linha 4', false);
  if not pg_temp.ok(r) then raise exception 'outro orcamento do mesmo cliente recusado: %', r; end if;
  insert into ids values ('AP_COMERCIAL_OUTRO_ORCAMENTO', (r->'apontamento_ids'->>0)::uuid);
  r := public.app_lancar_horas_internas(v_comercial, v_hoje, pg_temp.lote('1d000000-0000-4000-8000-000000000101', 1),
         null, 949001, null, 'painel da linha 3', false);
  if not pg_temp.ok(r) then raise exception 'outro cliente com o mesmo orcamento recusado: %', r; end if;
  insert into ids values ('AP_COMERCIAL_OUTRO_CLIENTE', (r->'apontamento_ids'->>0)::uuid);
end $lancar$;
reset role;
select pg_temp.sistema();

do $lancar_conferir$
declare
  v public.apontamentos_horas;
begin
  select * into v from public.apontamentos_horas where id = pg_temp.ap('AP_COMERCIAL_DIGITADO');
  if v.os_id is not null or v.atividade_id <> pg_temp.ap('ATIV_COMERCIAL') or v.cliente_id is not null
     or v.cliente_nome is distinct from 'PADARIA NOVA' or v.orcamento_descricao is distinct from 'painel da linha 3'
     or v.descricao is not null or v.tablet_sessao_id is not null
     or v.colaborador_id <> '1d000000-0000-4000-8000-000000000101' or v.criado_por_user_id <> '1d000000-0000-4000-8000-000000000002' then
    raise exception 'Comercial digitado gravado errado: %', to_jsonb(v);
  end if;
  -- Nasce aprovada, sem fila e sem aprovador: e aprovacao automatica, mesmo lancada pela coordenacao.
  if v.status_aprovacao <> 'aprovado' or v.aprovado_por is not null or v.aprovado_automaticamente_em is null
     or v.pendente_em is not null or v.rejeitado_em is not null then
    raise exception 'hora interna lancada pela coordenacao nao nasceu com aprovacao automatica: %', to_jsonb(v);
  end if;

  select * into v from public.apontamentos_horas where id = pg_temp.ap('AP_COMERCIAL_CADASTRO');
  if v.cliente_id is distinct from 949001 or v.cliente_nome is not null or v.orcamento_descricao is distinct from 'retrofit da prensa'
     or v.descricao is distinct from 'reunião de levantamento' or v.colaborador_id <> '1d000000-0000-4000-8000-000000000105'
     or v.status_aprovacao <> 'aprovado' then
    raise exception 'Comercial com cliente do cadastro gravado errado: %', to_jsonb(v);
  end if;

  select * into v from public.apontamentos_horas where id = pg_temp.ap('AP_INTEGRACAO_DIEGO');
  if v.status_aprovacao <> 'aprovado' or v.horas <> 2 or v.colaborador_id <> '1d000000-0000-4000-8000-000000000104' then
    raise exception 'Integracao do DIEGO gravada errada: %', to_jsonb(v);
  end if;
  if exists (select 1 from public.colaborador_taxas where colaborador_id = '1d000000-0000-4000-8000-000000000104') then
    raise exception 'o fixture devia deixar o DIEGO sem taxa';
  end if;
  -- A mesma pessoa, numa OS, continua barrada pela falta de taxa.
  begin
    insert into public.apontamentos_horas (tenant_id, empresa_id, os_id, colaborador_id, data, horas, tipo_hora_id, descricao)
    values ('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', 949001,
            '1d000000-0000-4000-8000-000000000104', pg_temp.d('hoje'), 1, '1d000000-0000-4000-8000-000000000301', 'montagem');
    raise exception 'hora em OS do DIEGO, sem taxa, foi gravada';
  exception when others then
    if sqlerrm not like 'Não é permitido lançar horas: colaborador % não possui taxa vigente em %' then raise; end if;
  end;

  -- As repetidas nao gravaram: ANA com tres Comerciais hoje, DIEGO com uma Integracao.
  if (select count(*) from public.apontamentos_horas where colaborador_id = '1d000000-0000-4000-8000-000000000101'
        and atividade_id = pg_temp.ap('ATIV_COMERCIAL') and data = pg_temp.d('hoje')) <> 3
     or (select count(*) from public.apontamentos_horas where colaborador_id = '1d000000-0000-4000-8000-000000000104'
        and atividade_id = pg_temp.ap('ATIV_INTEGRACAO')) <> 1 then
    raise exception 'lancamento repetido ficou gravado';
  end if;
end $lancar_conferir$;

-- Classificacao pela data, igual a hora em OS e ao tablet: sabado 50%, domingo e feriado
-- 100%, dia util normal ate 9 h e o resto 50%.
select pg_temp.como('1d000000-0000-4000-8000-000000000002');
set local role authenticated;
do $classificar$
declare
  r jsonb;
  v_manutencao uuid := pg_temp.ap('ATIV_MANUTENCAO_FABRICA');
  v_diego constant text := '1d000000-0000-4000-8000-000000000104';
begin
  r := public.app_lancar_horas_internas(v_manutencao, pg_temp.d('sabado'), pg_temp.lote(v_diego, 2), 'limpeza do galpão', null, null, null, true);
  if not pg_temp.ok(r) or (r->>'gravados')::integer <> 1 then raise exception 'sabado: %', r; end if;
  insert into ids values ('AP_SABADO', (r->'apontamento_ids'->>0)::uuid);
  r := public.app_lancar_horas_internas(v_manutencao, pg_temp.d('domingo'), pg_temp.lote(v_diego, 2), 'limpeza do galpão', null, null, null, true);
  if not pg_temp.ok(r) or (r->>'gravados')::integer <> 1 then raise exception 'domingo: %', r; end if;
  insert into ids values ('AP_DOMINGO', (r->'apontamento_ids'->>0)::uuid);
  r := public.app_lancar_horas_internas(v_manutencao, pg_temp.d('feriado'), pg_temp.lote(v_diego, 2), 'limpeza do galpão', null, null, null, true);
  if not pg_temp.ok(r) or (r->>'gravados')::integer <> 1 then raise exception 'feriado: %', r; end if;
  insert into ids values ('AP_FERIADO', (r->'apontamento_ids'->>0)::uuid);
  -- Dia util com 10 h: duas linhas, e o aviso de mais de 9 h volta junto.
  r := public.app_lancar_horas_internas(v_manutencao, pg_temp.d('util'), pg_temp.lote(v_diego, 10), 'troca do telhado', null, null, null, true);
  if not pg_temp.ok(r) or (r->>'gravados')::integer <> 2 or jsonb_array_length(r->'apontamento_ids') <> 2
     or not pg_temp.tem_aviso(r, 'jornada_maior_que_9h') then
    raise exception 'dia util com 10 h: %', r;
  end if;
end $classificar$;
reset role;
select pg_temp.sistema();

do $classificar_conferir$
declare
  v_codigo text;
begin
  select th.codigo into v_codigo from public.apontamentos_horas as h join public.tipos_horas as th on th.id = h.tipo_hora_id where h.id = pg_temp.ap('AP_SABADO');
  if v_codigo is distinct from 'EXTRA_50' then raise exception 'sabado classificado como %', v_codigo; end if;
  select th.codigo into v_codigo from public.apontamentos_horas as h join public.tipos_horas as th on th.id = h.tipo_hora_id where h.id = pg_temp.ap('AP_DOMINGO');
  if v_codigo is distinct from 'EXTRA_100' then raise exception 'domingo classificado como %', v_codigo; end if;
  select th.codigo into v_codigo from public.apontamentos_horas as h join public.tipos_horas as th on th.id = h.tipo_hora_id where h.id = pg_temp.ap('AP_FERIADO');
  if v_codigo is distinct from 'EXTRA_100' then raise exception 'feriado classificado como %', v_codigo; end if;
  if (select count(*) from public.apontamentos_horas as h where h.colaborador_id = '1d000000-0000-4000-8000-000000000104' and h.data = pg_temp.d('util')) <> 2
     or not exists (select 1 from public.apontamentos_horas as h join public.tipos_horas as th on th.id = h.tipo_hora_id
                    where h.colaborador_id = '1d000000-0000-4000-8000-000000000104' and h.data = pg_temp.d('util') and th.codigo = 'NORMAL' and h.horas = 9)
     or not exists (select 1 from public.apontamentos_horas as h join public.tipos_horas as th on th.id = h.tipo_hora_id
                    where h.colaborador_id = '1d000000-0000-4000-8000-000000000104' and h.data = pg_temp.d('util') and th.codigo = 'EXTRA_50' and h.horas = 1) then
    raise exception 'dia util com 10 h devia virar 9 h NORMAL e 1 h EXTRA_50';
  end if;
  if exists (select 1 from public.apontamentos_horas where colaborador_id = '1d000000-0000-4000-8000-000000000104' and status_aprovacao <> 'aprovado') then
    raise exception 'hora interna classificada nao nasceu aprovada';
  end if;
end $classificar_conferir$;

-- =====================================================================================
-- 4. Avisos: retroativo e mais de 9 h no dia (somando a hora em OS) so gravam confirmados.
-- =====================================================================================
select pg_temp.como('1d000000-0000-4000-8000-000000000002');
set local role authenticated;
do $avisos$
declare
  r jsonb;
  v_hoje date := pg_temp.d('hoje');
  v_bruno constant text := '1d000000-0000-4000-8000-000000000102';
begin
  -- BRUNO ja tem 4 h na HI-1 hoje; mais 6 h de Administrativo passam de 9 h.
  r := public.app_lancar_horas_internas(pg_temp.ap('ATIV_ADMINISTRATIVO'), v_hoje, pg_temp.lote(v_bruno, 6), 'inventário do almoxarifado', null, null, null, false);
  if pg_temp.ok(r) or (r->>'gravados')::integer <> 0 or jsonb_array_length(r->'erros') <> 0 or not pg_temp.tem_aviso(r, 'jornada_maior_que_9h') then
    raise exception 'mais de 9 h sem confirmar: %', r;
  end if;
  if (select e->>'mensagem' from jsonb_array_elements(r->'avisos') as e where e->>'tipo' = 'jornada_maior_que_9h') not like 'BRUNO ficará com 10,00 h apontadas em %' then
    raise exception 'o aviso de jornada devia somar a hora da OS: %', r;
  end if;
  r := public.app_lancar_horas_internas(pg_temp.ap('ATIV_ADMINISTRATIVO'), v_hoje, pg_temp.lote(v_bruno, 6), 'inventário do almoxarifado', null, null, null, true);
  if not pg_temp.ok(r) or (r->>'gravados')::integer <> 1 or not pg_temp.tem_aviso(r, 'jornada_maior_que_9h') then
    raise exception 'mais de 9 h confirmado: %', r;
  end if;
  insert into ids values ('AP_ADMINISTRATIVO_BRUNO', (r->'apontamento_ids'->>0)::uuid);

  -- Mais de 7 dias atras: retroativo.
  r := public.app_lancar_horas_internas(pg_temp.ap('ATIV_EXAMES'), v_hoje - 10, pg_temp.lote(v_bruno, 1), null, null, null, null, false);
  if pg_temp.ok(r) or (r->>'gravados')::integer <> 0 or not pg_temp.tem_aviso(r, 'retroativo') or pg_temp.tem_aviso(r, 'jornada_maior_que_9h') then
    raise exception 'retroativo sem confirmar: %', r;
  end if;
  r := public.app_lancar_horas_internas(pg_temp.ap('ATIV_EXAMES'), v_hoje - 10, pg_temp.lote(v_bruno, 1), null, null, null, null, true);
  if not pg_temp.ok(r) or (r->>'gravados')::integer <> 1 then raise exception 'retroativo confirmado: %', r; end if;

  -- Exatamente 7 dias ainda nao e retroativo.
  r := public.app_lancar_horas_internas(pg_temp.ap('ATIV_EXAMES'), v_hoje - 7, pg_temp.lote(v_bruno, 1), null, null, null, null, false);
  if not pg_temp.ok(r) or jsonb_array_length(r->'avisos') <> 0 then raise exception '7 dias atras: %', r; end if;
end $avisos$;
reset role;
select pg_temp.sistema();

do $avisos_conferir$
begin
  if (select count(*) from public.apontamentos_horas where colaborador_id = '1d000000-0000-4000-8000-000000000102' and atividade_id is not null) <> 3 then
    raise exception 'o que nao foi confirmado gravou: % horas internas do BRUNO',
      (select count(*) from public.apontamentos_horas where colaborador_id = '1d000000-0000-4000-8000-000000000102' and atividade_id is not null);
  end if;
end $avisos_conferir$;

-- =====================================================================================
-- 5. Quem lanca para quem: APONTADOR e TECNICO so para si; coordenacao para cima para
--    qualquer um; conta do tablet, TV e faturamento nao lancam por aqui.
-- =====================================================================================
select pg_temp.como('1d000000-0000-4000-8000-000000000004');
set local role authenticated;
do $apontador$
declare
  r jsonb;
  v_hoje date := pg_temp.d('hoje');
begin
  r := public.app_lancar_horas_internas(pg_temp.ap('ATIV_EXAMES'), v_hoje, pg_temp.lote('1d000000-0000-4000-8000-000000000101', 1), 'exame periódico', null, null, null, false);
  if not pg_temp.ok(r) or (r->>'gravados')::integer <> 1 then raise exception 'ANA lancando para si: %', r; end if;
  insert into ids values ('AP_EXAMES_ANA', (r->'apontamento_ids'->>0)::uuid);

  r := public.app_lancar_horas_internas(pg_temp.ap('ATIV_EXAMES'), v_hoje, pg_temp.lote('1d000000-0000-4000-8000-000000000102', 1), null, null, null, null, true);
  if pg_temp.ok(r) or r->'erros'->0->>'tipo' is distinct from 'permissao'
     or r->'erros'->0->>'mensagem' is distinct from 'Seu perfil só lança hora interna para você mesmo. Quem lança para os outros é a coordenação.' then
    raise exception 'ANA lancando para o BRUNO: %', r;
  end if;
  r := public.app_lancar_horas_internas(pg_temp.ap('ATIV_TREINAMENTO'), v_hoje,
         jsonb_build_array(jsonb_build_object('colaborador_id', '1d000000-0000-4000-8000-000000000101', 'horas', 1),
                           jsonb_build_object('colaborador_id', '1d000000-0000-4000-8000-000000000102', 'horas', 1)),
         null, null, null, null, true);
  if pg_temp.ok(r) or r->'erros'->0->>'tipo' is distinct from 'permissao' then raise exception 'ANA num lote com o BRUNO: %', r; end if;
end $apontador$;
reset role;
select pg_temp.sistema();

select pg_temp.como('1d000000-0000-4000-8000-000000000003');
set local role authenticated;
do $tecnico_lanca$
declare r jsonb;
begin
  r := public.app_lancar_horas_internas(pg_temp.ap('ATIV_TREINAMENTO'), pg_temp.d('util'), pg_temp.lote('1d000000-0000-4000-8000-000000000105', 3), 'curso de NR10 da turma', null, null, null, true);
  if not pg_temp.ok(r) or (r->>'gravados')::integer <> 1 then raise exception 'PEDRO lancando para si: %', r; end if;
  insert into ids values ('AP_TREINAMENTO_PEDRO', (r->'apontamento_ids'->>0)::uuid);
  r := public.app_lancar_horas_internas(pg_temp.ap('ATIV_TREINAMENTO'), pg_temp.d('util'), pg_temp.lote('1d000000-0000-4000-8000-000000000101', 3), null, null, null, null, true);
  if pg_temp.ok(r) or r->'erros'->0->>'tipo' is distinct from 'permissao' then raise exception 'PEDRO lancando para a ANA: %', r; end if;
end $tecnico_lanca$;
reset role;
select pg_temp.sistema();

create or replace function pg_temp.nao_lanca(p_quem text, p_mensagem text) returns void language plpgsql as $$
declare r jsonb;
begin
  r := public.app_lancar_horas_internas(pg_temp.ap('ATIV_EXAMES'), pg_temp.d('hoje'), pg_temp.lote('1d000000-0000-4000-8000-000000000102', 1), null, null, null, null, true);
  if pg_temp.ok(r) or r->'erros'->0->>'tipo' is distinct from 'permissao' or r->'erros'->0->>'mensagem' is distinct from p_mensagem then
    raise exception '% lancou hora interna, ou foi recusado com a mensagem errada: %', p_quem, r;
  end if;
end $$;

select pg_temp.como('1d000000-0000-4000-8000-000000000001');
set local role authenticated;
do $conta_tablet_lanca$ begin perform pg_temp.nao_lanca('conta do tablet', 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.'); end $conta_tablet_lanca$;
reset role;
select pg_temp.sistema();

select pg_temp.como('1d000000-0000-4000-8000-000000000006');
set local role authenticated;
do $tv_lanca$ begin perform pg_temp.nao_lanca('PAINEL_TV', 'Seu perfil não tem permissão para lançar horas.'); end $tv_lanca$;
reset role;
select pg_temp.sistema();

select pg_temp.como('1d000000-0000-4000-8000-000000000008');
set local role authenticated;
do $faturamento_lanca$ begin perform pg_temp.nao_lanca('FATURAMENTO', 'Seu perfil não tem permissão para lançar horas.'); end $faturamento_lanca$;
reset role;
select pg_temp.sistema();

-- Admin lanca um lote para duas pessoas.
select pg_temp.como('1d000000-0000-4000-8000-000000000007');
set local role authenticated;
do $admin_lanca$
declare r jsonb;
begin
  r := public.app_lancar_horas_internas(pg_temp.ap('ATIV_ADMINISTRATIVO'), pg_temp.d('hoje') - 1,
         jsonb_build_array(jsonb_build_object('colaborador_id', '1d000000-0000-4000-8000-000000000101', 'horas', 1),
                           jsonb_build_object('colaborador_id', '1d000000-0000-4000-8000-000000000102', 'horas', 1)),
         'arrumação do escritório', null, null, null, true);
  if not pg_temp.ok(r) or (r->>'gravados')::integer <> 2 then raise exception 'lote do admin: %', r; end if;
  insert into ids values ('AP_LOTE_ANA', (r->'apontamento_ids'->>0)::uuid), ('AP_LOTE_BRUNO', (r->'apontamento_ids'->>1)::uuid);
end $admin_lanca$;
reset role;
select pg_temp.sistema();

do $quem_conferir$
declare
  v public.apontamentos_horas;
begin
  -- APONTADOR, que na OS nasceria pendente: a hora interna nasce com aprovacao automatica.
  select * into v from public.apontamentos_horas where id = pg_temp.ap('AP_EXAMES_ANA');
  if v.status_aprovacao <> 'aprovado' or v.aprovado_por is not null or v.aprovado_automaticamente_em is null or v.pendente_em is not null
     or v.criado_por_user_id <> '1d000000-0000-4000-8000-000000000004' then
    raise exception 'hora interna da propria ANA: %', to_jsonb(v);
  end if;
  select * into v from public.apontamentos_horas where id = pg_temp.ap('AP_TREINAMENTO_PEDRO');
  if v.status_aprovacao <> 'aprovado' or v.criado_por_user_id <> '1d000000-0000-4000-8000-000000000003' then
    raise exception 'hora interna do proprio PEDRO: %', to_jsonb(v);
  end if;
  select * into v from public.apontamentos_horas where id = pg_temp.ap('AP_LOTE_ANA');
  if v.colaborador_id <> '1d000000-0000-4000-8000-000000000101' or v.criado_por_user_id <> '1d000000-0000-4000-8000-000000000007' then
    raise exception 'lote do admin, ANA: %', to_jsonb(v);
  end if;
  select * into v from public.apontamentos_horas where id = pg_temp.ap('AP_LOTE_BRUNO');
  if v.colaborador_id <> '1d000000-0000-4000-8000-000000000102' or v.criado_por_user_id <> '1d000000-0000-4000-8000-000000000007' then
    raise exception 'lote do admin, BRUNO: %', to_jsonb(v);
  end if;
  -- Nada das recusas: ANA com 3 Comerciais, Exames e o lote; PEDRO com Comercial e Treinamento; BRUNO com 3 e o lote.
  if (select count(*) from public.apontamentos_horas where colaborador_id = '1d000000-0000-4000-8000-000000000101' and atividade_id is not null) <> 5
     or (select count(*) from public.apontamentos_horas where colaborador_id = '1d000000-0000-4000-8000-000000000105' and atividade_id is not null) <> 2
     or (select count(*) from public.apontamentos_horas where colaborador_id = '1d000000-0000-4000-8000-000000000102' and atividade_id is not null) <> 4 then
    raise exception 'lancamento recusado por permissao ficou gravado';
  end if;
end $quem_conferir$;

-- =====================================================================================
-- 6. Tablet do PIN: so atividade que nao pede cliente, idempotencia pela chave, sem
--    barrar duplicidade (como o tablet de OS) e janela de 15 dias.
-- =====================================================================================
select pg_temp.como('1d000000-0000-4000-8000-000000000005');
set local role authenticated;
do $tablet_autorizar$
declare r jsonb;
begin
  r := public.web_tablet_salvar('1d000000-0000-4000-8000-000000000001', 'Tablet da producao', 60, true);
  if not pg_temp.ok(r) then raise exception 'tablet nao autorizado: %', r; end if;
  r := public.web_tablet_pin_definir('1d000000-0000-4000-8000-000000000102', '1234');
  if not pg_temp.ok(r) then raise exception 'PIN do BRUNO: %', r; end if;
  r := public.web_tablet_pin_definir('1d000000-0000-4000-8000-000000000104', '5678');
  if not pg_temp.ok(r) then raise exception 'PIN do DIEGO: %', r; end if;
end $tablet_autorizar$;
reset role;
select pg_temp.sistema();

select pg_temp.como('1d000000-0000-4000-8000-000000000001');
set local role authenticated;
do $tablet$
declare
  r jsonb;
  v_token text;
  v_chave uuid := gen_random_uuid();
  v_hoje date := pg_temp.d('hoje');
  v_treinamento uuid := pg_temp.ap('ATIV_TREINAMENTO');
  v_codigos text[];
  v_id uuid;
  v_linha public.apontamentos_horas;
begin
  r := public.app_tablet_identificar('1234');
  if not pg_temp.ok(r) or r->>'colaborador_nome' <> 'BRUNO' then raise exception 'PIN 1234: %', r; end if;
  v_token := r->>'sessao_token';

  -- So as ativas que nao pedem cliente, na ordem do cadastro (sem Comercial, sem as inativas).
  r := public.app_tablet_atividades(v_token);
  select array_agg(x.e->>'codigo' order by x.n) into v_codigos from jsonb_array_elements(r->'atividades') with ordinality as x(e, n);
  if not pg_temp.ok(r) or v_codigos is distinct from array['treinamento', 'manutencao_fabrica', 'administrativo', 'exames', 'integracao'] then
    raise exception 'atividades do tablet: %', r;
  end if;
  r := public.app_tablet_atividades('token-que-nao-existe');
  if pg_temp.ok(r) or r->'erros'->0->>'tipo' is distinct from 'sessao_invalida' then raise exception 'atividades com token invalido: %', r; end if;

  -- Comercial pede cliente e orcamento: o tablet recusa e manda para o celular.
  r := public.app_tablet_lancar_horas_internas(v_token, pg_temp.ap('ATIV_COMERCIAL'), v_hoje, 1, 0, gen_random_uuid(), true);
  if pg_temp.ok(r) or r->'erros'->0->>'mensagem' is distinct from 'Comercial pede cliente e orçamento: lance pelo celular.' then
    raise exception 'Comercial pelo tablet: %', r;
  end if;
  r := public.app_tablet_lancar_horas_internas(v_token, pg_temp.ap('ATIV_VISITA'), v_hoje, 1, 0, gen_random_uuid(), true);
  if pg_temp.ok(r) or r->'erros'->0->>'tipo' is distinct from 'atividade' then raise exception 'atividade inativa pelo tablet: %', r; end if;
  r := public.app_tablet_lancar_horas_internas(v_token, pg_temp.ap('B_TREINAMENTO'), v_hoje, 1, 0, gen_random_uuid(), true);
  if pg_temp.ok(r) or r->'erros'->0->>'tipo' is distinct from 'atividade' then raise exception 'atividade da empresa B pelo tablet: %', r; end if;

  -- BRUNO ja tem 10 h hoje (4 h na HI-1 e 6 h de Administrativo): sem confirmar, so o aviso.
  r := public.app_tablet_lancar_horas_internas(v_token, v_treinamento, v_hoje, 1, 30, v_chave, false);
  if pg_temp.ok(r) or (r->>'gravados')::integer <> 0 or not pg_temp.tem_aviso(r, 'jornada_maior_que_9h') then
    raise exception 'tablet sem confirmar o aviso: %', r;
  end if;
  -- Confirmando: 1h30 vira 1,50 e o resumo do dia mostra a OS e a outra atividade.
  r := public.app_tablet_lancar_horas_internas(v_token, v_treinamento, v_hoje, 1, 30, v_chave, true);
  if not pg_temp.ok(r) or (r->>'horas')::numeric <> 1.5 or (r->>'minutos')::integer <> 90 or (r->>'gravados')::integer <> 1
     or r->>'colaborador_nome' <> 'BRUNO' or r->>'atividade_nome' <> 'Treinamento' then
    raise exception 'tablet confirmado: %', r;
  end if;
  if (r->'resumo'->>'subtotal_atividade_horas')::numeric <> 1.5 or (r->'resumo'->>'total_dia_horas')::numeric <> 11.5
     or not (r->'resumo'->'outras_do_dia' @> jsonb_build_array(jsonb_build_object('rotulo', 'OS HI-1', 'horas', 4),
                                                              jsonb_build_object('rotulo', 'Administrativo', 'horas', 6))) then
    raise exception 'resumo do dia no tablet: %', r;
  end if;
  v_id := (r->>'apontamento_id')::uuid;
  insert into ids values ('AP_TABLET', v_id);

  -- Mesma chave: nao grava de novo e devolve o mesmo apontamento.
  r := public.app_tablet_lancar_horas_internas(v_token, v_treinamento, v_hoje, 1, 30, v_chave, true);
  if not pg_temp.ok(r) or not coalesce((r->>'repetido')::boolean, false) or (r->>'apontamento_id')::uuid <> v_id then
    raise exception 'reenvio da mesma chave: %', r;
  end if;
  -- Chave nova, mesma atividade, dia e duracao: grava. Quem segura o reenvio e a chave.
  r := public.app_tablet_lancar_horas_internas(v_token, v_treinamento, v_hoje, 1, 30, gen_random_uuid(), true);
  if not pg_temp.ok(r) or (r->'resumo'->>'subtotal_atividade_horas')::numeric <> 3 or jsonb_array_length(r->'resumo'->'lancamentos') <> 2 then
    raise exception 'segundo lancamento igual com chave nova no tablet: %', r;
  end if;

  -- Janela: hoje - 15 entra (retroativo confirmado); hoje - 16 e amanha nao.
  r := public.app_tablet_lancar_horas_internas(v_token, pg_temp.ap('ATIV_EXAMES'), v_hoje - 15, 1, 0, gen_random_uuid(), true);
  if not pg_temp.ok(r) then raise exception 'tablet em hoje - 15: %', r; end if;
  r := public.app_tablet_lancar_horas_internas(v_token, pg_temp.ap('ATIV_EXAMES'), v_hoje - 16, 1, 0, gen_random_uuid(), true);
  if pg_temp.ok(r) or r->'erros'->0->>'tipo' is distinct from 'data_fora_da_janela' or (r->'janela'->>'de')::date <> v_hoje - 15 then
    raise exception 'tablet em hoje - 16: %', r;
  end if;
  r := public.app_tablet_lancar_horas_internas(v_token, pg_temp.ap('ATIV_EXAMES'), v_hoje + 1, 1, 0, gen_random_uuid(), true);
  if pg_temp.ok(r) or r->'erros'->0->>'tipo' is distinct from 'data_futura' then raise exception 'tablet amanha: %', r; end if;
  r := public.app_tablet_lancar_horas_internas(v_token, pg_temp.ap('ATIV_EXAMES'), v_hoje, 1, 0, null, true);
  if pg_temp.ok(r) or r->'erros'->0->>'tipo' is distinct from 'chave' then raise exception 'tablet sem chave: %', r; end if;
  r := public.app_tablet_lancar_horas_internas(v_token, pg_temp.ap('ATIV_EXAMES'), v_hoje, 0, 0, gen_random_uuid(), true);
  if pg_temp.ok(r) or r->'erros'->0->>'tipo' is distinct from 'duracao' then raise exception 'tablet com duracao zero: %', r; end if;

  -- DIEGO, sem taxa, tambem lanca pelo tablet (e a Integracao de hoje ja lancada pelo app nao barra).
  r := public.app_tablet_identificar('5678');
  if not pg_temp.ok(r) or r->>'colaborador_nome' <> 'DIEGO' then raise exception 'PIN 5678: %', r; end if;
  v_token := r->>'sessao_token';
  r := public.app_tablet_lancar_horas_internas(v_token, pg_temp.ap('ATIV_INTEGRACAO'), v_hoje, 1, 0, gen_random_uuid(), true);
  if not pg_temp.ok(r) then raise exception 'DIEGO pelo tablet: %', r; end if;
  perform public.app_tablet_encerrar(v_token, 'finalizado');

  -- A tabela so se confere como postgres.
  reset role;
  select * into v_linha from public.apontamentos_horas where id = v_id;
  if v_linha.status_aprovacao <> 'aprovado' or v_linha.aprovado_por is not null or v_linha.aprovado_automaticamente_em is null
     or v_linha.pendente_em is not null or v_linha.tablet_sessao_id is null or v_linha.os_id is not null
     or v_linha.atividade_id <> v_treinamento or v_linha.horas <> 1.5
     or v_linha.criado_por_user_id <> '1d000000-0000-4000-8000-000000000001' then
    raise exception 'hora interna do tablet gravada errada: %', to_jsonb(v_linha);
  end if;
  if (select count(*) from public.apontamentos_horas where colaborador_id = '1d000000-0000-4000-8000-000000000102'
        and atividade_id = v_treinamento and data = v_hoje and tablet_sessao_id is not null) <> 2 then
    raise exception 'o reenvio da mesma chave duplicou, ou a chave nova nao gravou';
  end if;
  if (select count(*) from public.apontamentos_horas where colaborador_id = '1d000000-0000-4000-8000-000000000104'
        and atividade_id = pg_temp.ap('ATIV_INTEGRACAO') and data = v_hoje) <> 2 then
    raise exception 'DIEGO devia ter a Integracao do app e a do tablet';
  end if;
  if not exists (select 1 from public.apontamentos_horas where colaborador_id = '1d000000-0000-4000-8000-000000000102'
                   and data = v_hoje - 15 and tablet_sessao_id is not null) then
    raise exception 'a hora de hoje - 15 do tablet nao gravou';
  end if;
  set local role authenticated;
end $tablet$;
reset role;
select pg_temp.sistema();

-- Toda hora interna, lancada por gestao, APONTADOR, TECNICO ou tablet, fica com aprovacao
-- automatica e sem aprovador (trg_hora_interna_aprovacao_automatica). Conferido de novo no fim.
create or replace function pg_temp.internas_aprovacao_automatica(p_momento text) returns void language plpgsql as $$
declare v_errada jsonb;
begin
  select to_jsonb(h) into v_errada
  from public.apontamentos_horas as h
  where h.tenant_id = '1d000000-0000-4000-8000-000000000010' and h.atividade_id is not null
    and (h.status_aprovacao is distinct from 'aprovado' or h.aprovado_por is not null or h.aprovado_automaticamente_em is null
         or h.aprovado_em is null or h.pendente_em is not null or h.rejeitado_em is not null)
  limit 1;
  if v_errada is not null then
    raise exception '%: hora interna fora da aprovacao automatica: %', p_momento, v_errada;
  end if;
end $$;
do $aprovacao_automatica$
begin
  if (select count(distinct h.criado_por_user_id) from public.apontamentos_horas as h
      where h.tenant_id = '1d000000-0000-4000-8000-000000000010' and h.atividade_id is not null) < 5 then
    raise exception 'o teste devia ter horas internas lancadas por coordenacao, APONTADOR, TECNICO, admin e tablet';
  end if;
  perform pg_temp.internas_aprovacao_automatica('depois dos lancamentos');
end $aprovacao_automatica$;

-- =====================================================================================
-- 7. Custo e de OS: nenhuma hora interna em vw_apontamentos_horas_custo nem no custo da OS.
-- =====================================================================================
do $custo$
declare
  v_antes custo_antes;
begin
  select * into v_antes from custo_antes;
  if (select count(*) from public.apontamentos_horas where tenant_id = '1d000000-0000-4000-8000-000000000010' and atividade_id is not null) < 15 then
    raise exception 'o teste devia ter horas internas a esta altura';
  end if;
  if exists (
    select 1 from public.vw_apontamentos_horas_custo as v
    join public.apontamentos_horas as h on h.id = v.apontamento_id
    where h.atividade_id is not null
  ) then
    raise exception 'hora interna entrou em vw_apontamentos_horas_custo';
  end if;
  if (select count(*) from public.vw_apontamentos_horas_custo as v join public.colaboradores as c on c.id = v.colaborador_id
       where c.tenant_id = '1d000000-0000-4000-8000-000000000010') <> v_antes.linhas_fixture
     or (select coalesce(sum(v.total_horas), 0) from public.vw_custo_mao_obra_os as v where v.os_id = 949001) <> v_antes.horas_os
     or (select coalesce(sum(v.custo_mao_obra), 0) from public.vw_custo_mao_obra_os as v where v.os_id = 949001) <> v_antes.custo_os
     or (select count(*) from public.vw_custo_mao_obra_os as v where v.os_id is null) <> v_antes.grupos_sem_os
     or (select coalesce(sum(v.total_horas), 0) from public.vw_custo_mao_obra_os as v where v.os_id is null) <> v_antes.horas_sem_os then
    raise exception 'o custo mudou com as horas internas: antes %', to_jsonb(v_antes);
  end if;
end $custo$;

-- =====================================================================================
-- 8. Leituras que juntavam a OS: a hora interna aparece, com a atividade.
-- =====================================================================================
-- 8a. TV (tv_horas_periodo), pela conta da televisao.
select pg_temp.como('1d000000-0000-4000-8000-000000000006');
set local role authenticated;
do $tv$
declare
  v_hoje date := pg_temp.d('hoje');
  v_de date := pg_temp.d('hoje') - 16;
  v_tv numeric;
  v_tabela numeric;
begin
  -- Hora interna: atividade, sem OS e sem cliente.
  if not exists (
    select 1 from public.tv_horas_periodo(v_de, v_hoje, null) as t
    where t.colaborador_nome = 'PEDRO' and t.data = v_hoje and t.atividade_id = pg_temp.ap('ATIV_COMERCIAL') and t.atividade_nome = 'Comercial'
      and t.os_id is null and t.numero_os is null and t.cliente_nome is null and t.horas = 1.5 and t.status_aprovacao = 'aprovado'
  ) then
    raise exception 'TV sem a hora Comercial do PEDRO: %', (select json_agg(t) from public.tv_horas_periodo(v_hoje, v_hoje, null) as t);
  end if;
  -- A OS continua vindo como OS.
  if not exists (
    select 1 from public.tv_horas_periodo(v_de, v_hoje, null) as t
    where t.colaborador_nome = 'BRUNO' and t.data = v_hoje and t.os_id = 949001 and t.numero_os = 'HI-1' and t.atividade_id is null and t.horas = 4
  ) then
    raise exception 'TV sem a hora do BRUNO na HI-1';
  end if;
  -- A semana soma a hora interna: BRUNO hoje = 4 h na HI-1 + 6 h de Administrativo + 2 x 1,5 h de Treinamento.
  select sum(t.horas) into v_tv from public.tv_horas_periodo(v_hoje, v_hoje, null) as t where t.colaborador_nome = 'BRUNO';
  if v_tv is distinct from 13.00 then raise exception 'TV, BRUNO hoje: % h (esperado 13)', v_tv; end if;
  -- Nenhuma hora interna do periodo fica de fora.
  select coalesce(sum(t.horas), 0) into v_tv from public.tv_horas_periodo(v_de, v_hoje, null) as t where t.atividade_id is not null;
  reset role;
  select coalesce(sum(h.horas), 0) into v_tabela
  from public.apontamentos_horas as h
  join public.colaboradores as c on c.id = h.colaborador_id and c.ativo
  where h.tenant_id = '1d000000-0000-4000-8000-000000000010' and h.empresa_id = '1d000000-0000-4000-8000-000000000020'
    and h.atividade_id is not null and h.data between v_de and v_hoje and coalesce(h.status_aprovacao, 'pendente') <> 'rejeitado';
  set local role authenticated;
  if v_tv <> v_tabela then raise exception 'TV com % h internas, tabela com %', v_tv, v_tabela; end if;
end $tv$;
reset role;
select pg_temp.sistema();

-- 8b. Listagem da web (web_listar_apontamentos_horas).
select pg_temp.como('1d000000-0000-4000-8000-000000000005');
set local role authenticated;
do $listar$
declare
  v_hoje date := pg_temp.d('hoje');
  v_de date := pg_temp.d('hoje') - 60;
  v record;
  v_lista bigint;
  v_tabela bigint;
begin
  select * into v from public.web_listar_apontamentos_horas(v_de, v_hoje) as l where l.id = pg_temp.ap('AP_COMERCIAL_DIGITADO');
  if not found then raise exception 'a listagem da web escondeu a hora interna'; end if;
  if v.os_id is not null or v.numero_os is not null or v.atividade_id <> pg_temp.ap('ATIV_COMERCIAL') or v.atividade_nome <> 'Comercial'
     or v.cliente_nome is distinct from 'PADARIA NOVA' or v.cliente_id is not null or v.orcamento_descricao is distinct from 'painel da linha 3'
     or v.colaborador_nome <> 'ANA' or v.status_aprovacao <> 'aprovado' or v.criado_por_nome is distinct from 'Coordenacao' then
    raise exception 'listagem da web, Comercial digitado: %', row_to_json(v);
  end if;
  select * into v from public.web_listar_apontamentos_horas(v_de, v_hoje) as l where l.id = pg_temp.ap('AP_COMERCIAL_CADASTRO');
  if not found or v.cliente_nome is distinct from 'CLIENTE HORAS' or v.cliente_id is distinct from 949001
     or v.orcamento_descricao is distinct from 'retrofit da prensa' or v.colaborador_nome <> 'PEDRO' then
    raise exception 'listagem da web, Comercial do cadastro: %', row_to_json(v);
  end if;
  select * into v from public.web_listar_apontamentos_horas(v_de, v_hoje) as l where l.id = pg_temp.ap('AP_TABLET');
  if not found or v.atividade_nome <> 'Treinamento' or v.colaborador_nome <> 'BRUNO' or v.cliente_nome is not null then
    raise exception 'listagem da web, hora do tablet: %', row_to_json(v);
  end if;
  select * into v from public.web_listar_apontamentos_horas(v_de, v_hoje) as l where l.id = '1d000000-0000-4000-8000-00000000a001';
  if not found or v.numero_os <> 'HI-1' or v.atividade_id is not null or v.atividade_nome is not null or v.cliente_nome <> 'CLIENTE HORAS' then
    raise exception 'listagem da web, hora da OS: %', row_to_json(v);
  end if;
  -- Filtro por atividade: so ela (tres Comerciais da ANA e um do PEDRO).
  if exists (select 1 from public.web_listar_apontamentos_horas(v_de, v_hoje, p_atividade_id => pg_temp.ap('ATIV_COMERCIAL')) as l
             where l.atividade_id is distinct from pg_temp.ap('ATIV_COMERCIAL'))
     or (select count(*) from public.web_listar_apontamentos_horas(v_de, v_hoje, p_atividade_id => pg_temp.ap('ATIV_COMERCIAL'))) <> 4 then
    raise exception 'filtro por atividade na listagem da web';
  end if;
  -- Filtro por OS: nenhuma hora interna.
  if exists (select 1 from public.web_listar_apontamentos_horas(v_de, v_hoje, p_os_id => 949001) as l where l.atividade_id is not null) then
    raise exception 'filtro por OS trouxe hora interna';
  end if;
  -- Todas as horas internas do periodo aparecem.
  select count(*) into v_lista from public.web_listar_apontamentos_horas(v_de, v_hoje) as l where l.atividade_id is not null;
  reset role;
  select count(*) into v_tabela from public.apontamentos_horas as h
  where h.tenant_id = '1d000000-0000-4000-8000-000000000010' and h.empresa_id = '1d000000-0000-4000-8000-000000000020'
    and h.atividade_id is not null and h.data between v_de and v_hoje;
  set local role authenticated;
  if v_lista <> v_tabela then raise exception 'listagem da web com % horas internas, tabela com %', v_lista, v_tabela; end if;
end $listar$;
reset role;
select pg_temp.sistema();

-- 8c. Historico do aplicativo (app_historico_lancamentos): a ANA ve as dela; a gestao ve todas.
select pg_temp.como('1d000000-0000-4000-8000-000000000004');
set local role authenticated;
do $historico_ana$
declare
  v_hoje date := pg_temp.d('hoje');
  v_de date := pg_temp.d('hoje') - 60;
  v record;
begin
  select * into v from public.app_historico_lancamentos('horas', v_de, v_hoje, null, null, 100, null) as h
  where h.origem_id = pg_temp.ap('AP_COMERCIAL_DIGITADO')::text;
  if not found then raise exception 'o historico da ANA escondeu a hora interna'; end if;
  if v.tipo <> 'hora' or v.os_id is not null or v.numero_os is not null or v.atividade_nome <> 'Comercial'
     or v.cliente_nome is distinct from 'PADARIA NOVA' or v.descricao is distinct from 'painel da linha 3' or v.quantidade <> 1
     or v.status <> 'aprovado' or v.pode_ver_autoria or v.autor_nome is not null then
    raise exception 'historico da ANA, Comercial digitado: %', row_to_json(v);
  end if;
  select * into v from public.app_historico_lancamentos('horas', v_de, v_hoje, null, null, 100, null) as h
  where h.origem_id = pg_temp.ap('AP_EXAMES_ANA')::text;
  if not found or v.atividade_nome <> 'Exames' or v.cliente_nome is not null or v.descricao is distinct from 'exame periódico' then
    raise exception 'historico da ANA, Exames: %', row_to_json(v);
  end if;
  if exists (select 1 from public.app_historico_lancamentos('tudo', v_de, v_hoje, null, null, 100, null) as h
             where h.origem_id in (pg_temp.ap('AP_COMERCIAL_CADASTRO')::text, pg_temp.ap('AP_TABLET')::text, '1d000000-0000-4000-8000-00000000a001')) then
    raise exception 'o historico da ANA mostrou hora de outra pessoa';
  end if;
end $historico_ana$;
reset role;
select pg_temp.sistema();

select pg_temp.como('1d000000-0000-4000-8000-000000000005');
set local role authenticated;
do $historico_gestao$
declare
  v_hoje date := pg_temp.d('hoje');
  v_de date := pg_temp.d('hoje') - 60;
  v record;
begin
  -- Hora interna sem descricao nem orcamento fica sem descricao (o titulo ja e a atividade),
  -- e o aprovador e a aprovacao automatica.
  select * into v from public.app_historico_lancamentos('horas', v_de, v_hoje, null, null, 100, null) as h
  where h.origem_id = pg_temp.ap('AP_TABLET')::text;
  if not found or v.atividade_nome <> 'Treinamento' or v.autor_nome <> 'BRUNO' or v.os_id is not null or not v.pode_ver_autoria
     or v.descricao is not null or v.cliente_nome is not null or v.aprovado_por_nome is distinct from 'Aprovação automática' then
    raise exception 'historico da gestao, hora do tablet: %', row_to_json(v);
  end if;
  select * into v from public.app_historico_lancamentos('horas', v_de, v_hoje, null, null, 100, null) as h
  where h.origem_id = '1d000000-0000-4000-8000-00000000a001';
  if not found or v.numero_os <> 'HI-1' or v.atividade_nome is not null or v.cliente_nome <> 'CLIENTE HORAS' or v.descricao <> 'Montagem do painel' then
    raise exception 'historico da gestao, hora da OS: %', row_to_json(v);
  end if;
  -- Hora de OS sem texto nenhum continua "Apontamento de horas".
  select * into v from public.app_historico_lancamentos('horas', v_de, v_hoje, null, null, 100, null) as h
  where h.origem_id = '1d000000-0000-4000-8000-00000000a002';
  if not found or v.numero_os <> 'HI-2' or v.descricao is distinct from 'Apontamento de horas' then
    raise exception 'historico da gestao, hora de OS sem descricao: %', row_to_json(v);
  end if;
  if exists (select 1 from public.app_historico_lancamentos('materiais', v_de, v_hoje, null, null, 100, null) as h where h.atividade_nome is not null)
     or exists (select 1 from public.app_historico_lancamentos('horas', v_de, v_hoje, null, 949001, 100, null) as h where h.atividade_nome is not null) then
    raise exception 'historico de materiais ou de uma OS trouxe hora interna';
  end if;

  select * into v from public.app_historico_lancamentos('horas', v_de, v_hoje, null, null, 100, null) as h
  where h.origem_id = pg_temp.ap('AP_COMERCIAL_CADASTRO')::text;
  -- Comercial com cliente do cadastro: a hora guarda so cliente_id e o nome vem do cadastro.
  if not found or v.atividade_nome <> 'Comercial' or v.descricao is distinct from 'retrofit da prensa'
     or v.cliente_nome is distinct from 'CLIENTE HORAS' or v.aprovado_por_nome is distinct from 'Aprovação automática' then
    raise exception 'historico da gestao, Comercial do cadastro: %', row_to_json(v);
  end if;
end $historico_gestao$;
reset role;
select pg_temp.sistema();

-- 8d. Minhas horas do aplicativo (app_minhas_horas_mes), pela ANA: a hora interna aparece
--     sem OS, com o nome da atividade no lugar do codigo da OS, e o mes fecha com o ano.
select pg_temp.como('1d000000-0000-4000-8000-000000000004');
set local role authenticated;
do $minhas_horas$
declare
  v_hoje date := pg_temp.d('hoje');
  v_ano integer := extract(year from pg_temp.d('hoje'))::integer;
  v_mes integer := extract(month from pg_temp.d('hoje'))::integer;
  v_soma_mes numeric;
  v_soma_ano numeric;
  v_tabela numeric;
begin
  if not exists (select 1 from public.app_minhas_horas_mes(v_ano, v_mes) as m
                 where m.data = v_hoje and m.os_id is null and m.codigo_os = 'Comercial' and m.horas = 3 and not m.tem_rejeitado) then
    raise exception 'minhas horas sem os 3 Comerciais de hoje: %', (select json_agg(m) from public.app_minhas_horas_mes(v_ano, v_mes) as m);
  end if;
  if not exists (select 1 from public.app_minhas_horas_mes(v_ano, v_mes) as m
                 where m.data = v_hoje and m.os_id is null and m.codigo_os = 'Exames' and m.horas = 1) then
    raise exception 'minhas horas sem o Exames de hoje: %', (select json_agg(m) from public.app_minhas_horas_mes(v_ano, v_mes) as m);
  end if;
  select coalesce(sum(m.horas), 0) into v_soma_mes from public.app_minhas_horas_mes(v_ano, v_mes) as m;
  select a.total_horas into v_soma_ano from public.app_minhas_horas_ano(v_ano) as a where a.mes = date_trunc('month', v_hoje)::date;
  reset role;
  select coalesce(sum(h.horas), 0) into v_tabela from public.apontamentos_horas as h
  where h.colaborador_id = '1d000000-0000-4000-8000-000000000101'
    and h.data >= date_trunc('month', v_hoje)::date and h.data < (date_trunc('month', v_hoje) + interval '1 month')::date;
  set local role authenticated;
  if v_soma_mes <> v_tabela or v_soma_ano <> v_tabela then
    raise exception 'minhas horas da ANA: mes %, ano %, tabela %', v_soma_mes, v_soma_ano, v_tabela;
  end if;
end $minhas_horas$;
reset role;
select pg_temp.sistema();

-- =====================================================================================
-- 9. Para onde foram as horas (web_horas_internas_resumo): por atividade, pessoa, cliente e
--    orcamento; so hora interna; pede can('apontamentos', 'read').
-- =====================================================================================
select pg_temp.como('1d000000-0000-4000-8000-000000000005');
set local role authenticated;
do $resumo$
declare
  v_hoje date := pg_temp.d('hoje');
  v_de date := pg_temp.d('hoje') - 60;
  v record;
  v_horas numeric;
  v_lancamentos bigint;
  v_horas_tabela numeric;
  v_lancamentos_tabela bigint;
begin
  if exists (select 1 from public.web_horas_internas_resumo(v_de, v_hoje) as r where r.atividade_id is null) then
    raise exception 'resumo trouxe hora de OS';
  end if;
  if (select r.atividade_codigo from public.web_horas_internas_resumo(v_de, v_hoje) as r limit 1) <> 'comercial' then
    raise exception 'resumo devia comecar pela Comercial (ordem 10)';
  end if;
  -- Comercial: uma linha por pessoa, cliente e orcamento.
  select * into v from public.web_horas_internas_resumo(v_de, v_hoje) as r
  where r.atividade_codigo = 'comercial' and r.cliente_nome = 'PADARIA NOVA' and r.orcamento_descricao = 'painel da linha 3';
  if not found or v.colaborador_nome <> 'ANA' or v.cliente_id is not null or v.horas <> 1 or v.lancamentos <> 1 or v.primeiro_dia <> v_hoje then
    raise exception 'resumo, Comercial digitado: %', row_to_json(v);
  end if;
  select * into v from public.web_horas_internas_resumo(v_de, v_hoje) as r
  where r.atividade_codigo = 'comercial' and r.cliente_id = 949001 and r.orcamento_descricao = 'retrofit da prensa';
  if not found or v.colaborador_nome <> 'PEDRO' or v.cliente_nome <> 'CLIENTE HORAS' or v.horas <> 1.5 or v.lancamentos <> 1 then
    raise exception 'resumo, Comercial do cadastro: %', row_to_json(v);
  end if;
  select * into v from public.web_horas_internas_resumo(v_de, v_hoje) as r
  where r.atividade_codigo = 'comercial' and r.cliente_id = 949001 and r.orcamento_descricao = 'painel da linha 3';
  if not found or v.colaborador_nome <> 'ANA' or v.horas <> 1 then
    raise exception 'resumo, outro cliente com o mesmo orcamento devia ser linha propria: %', row_to_json(v);
  end if;
  -- DIEGO em Manutencao: sabado 2 + domingo 2 + feriado 2 + dia util 10 = 16 h em 5 lancamentos.
  select * into v from public.web_horas_internas_resumo(v_de, v_hoje) as r
  where r.atividade_codigo = 'manutencao_fabrica' and r.colaborador_nome = 'DIEGO';
  if not found or v.horas <> 16 or v.lancamentos <> 5 or v.primeiro_dia <> pg_temp.d('feriado')
     or v.ultimo_dia <> greatest(pg_temp.d('sabado'), pg_temp.d('domingo'), pg_temp.d('util')) then
    raise exception 'resumo, Manutencao do DIEGO: %', row_to_json(v);
  end if;
  -- BRUNO em Treinamento pelo tablet: duas vezes 1,5 h.
  select * into v from public.web_horas_internas_resumo(v_de, v_hoje) as r
  where r.atividade_codigo = 'treinamento' and r.colaborador_nome = 'BRUNO';
  if not found or v.horas <> 3 or v.lancamentos <> 2 then raise exception 'resumo, Treinamento do BRUNO: %', row_to_json(v); end if;
  -- O resumo soma o mesmo que a tabela.
  select sum(r.horas), sum(r.lancamentos) into v_horas, v_lancamentos from public.web_horas_internas_resumo(v_de, v_hoje) as r;
  reset role;
  select sum(h.horas), count(*) into v_horas_tabela, v_lancamentos_tabela from public.apontamentos_horas as h
  where h.tenant_id = '1d000000-0000-4000-8000-000000000010' and h.empresa_id = '1d000000-0000-4000-8000-000000000020'
    and h.atividade_id is not null and h.data between v_de and v_hoje;
  set local role authenticated;
  if v_horas <> v_horas_tabela or v_lancamentos <> v_lancamentos_tabela then
    raise exception 'resumo com % h em % lancamentos, tabela com % h em %', v_horas, v_lancamentos, v_horas_tabela, v_lancamentos_tabela;
  end if;
  -- Periodo invertido, ou maior que 400 dias.
  begin
    perform public.web_horas_internas_resumo(v_hoje, v_hoje - 1);
    raise exception 'resumo aceitou periodo invertido';
  exception when others then
    if sqlerrm <> 'Informe um período de até 400 dias.' then raise; end if;
  end;
  begin
    perform public.web_horas_internas_resumo(v_hoje - 401, v_hoje);
    raise exception 'resumo aceitou mais de 400 dias';
  exception when others then
    if sqlerrm <> 'Informe um período de até 400 dias.' then raise; end if;
  end;
end $resumo$;
reset role;
select pg_temp.sistema();

select pg_temp.como('1d000000-0000-4000-8000-000000000007');
set local role authenticated;
do $resumo_admin$
begin
  if (select count(*) from public.web_horas_internas_resumo(pg_temp.d('hoje') - 60, pg_temp.d('hoje'))) = 0 then
    raise exception 'admin nao leu o resumo';
  end if;
end $resumo_admin$;
reset role;
select pg_temp.sistema();

create or replace function pg_temp.resumo_fechado(p_quem text) returns void language plpgsql as $$
begin
  begin
    perform public.web_horas_internas_resumo(pg_temp.d('hoje') - 30, pg_temp.d('hoje'));
    raise exception '% abriu o resumo de horas internas', p_quem;
  exception when others then
    if sqlerrm <> 'Sem permissão para consultar apontamentos.' then raise; end if;
  end;
end $$;

select pg_temp.como('1d000000-0000-4000-8000-000000000004');
set local role authenticated;
do $resumo_ana$ begin perform pg_temp.resumo_fechado('APONTADOR'); end $resumo_ana$;
reset role;
select pg_temp.sistema();

select pg_temp.como('1d000000-0000-4000-8000-000000000003');
set local role authenticated;
do $resumo_tecnico$ begin perform pg_temp.resumo_fechado('TECNICO'); end $resumo_tecnico$;
reset role;
select pg_temp.sistema();

select pg_temp.como('1d000000-0000-4000-8000-000000000006');
set local role authenticated;
do $resumo_tv$ begin perform pg_temp.resumo_fechado('PAINEL_TV'); end $resumo_tv$;
reset role;
select pg_temp.sistema();

-- Coordenacao com papel de tenant GESTOR nao passa em can('apontamentos', 'read'): igual a
-- listagem de apontamentos da web, que usa a mesma porta.
select pg_temp.como('1d000000-0000-4000-8000-000000000002');
set local role authenticated;
do $resumo_coordenacao$ begin perform pg_temp.resumo_fechado('COORDENACAO'); end $resumo_coordenacao$;
reset role;
select pg_temp.sistema();

-- =====================================================================================
-- 10. Editar e cancelar hora interna.
-- =====================================================================================
do $pode_alterar$
declare
  v_id uuid := pg_temp.ap('AP_EXAMES_ANA');
begin
  -- Nasce aprovada e nao tem responsavel de OS: so a gestao altera, nem a propria pessoa.
  if public.fn_usuario_pode_alterar_apontamento('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', '1d000000-0000-4000-8000-000000000004', v_id) then
    raise exception 'a propria ANA pode alterar a hora interna ja aprovada';
  end if;
  if public.fn_usuario_pode_alterar_apontamento('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', '1d000000-0000-4000-8000-000000000003', v_id)
     or public.fn_usuario_pode_alterar_apontamento('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', '1d000000-0000-4000-8000-000000000008', v_id)
     or public.fn_usuario_pode_alterar_apontamento('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', '1d000000-0000-4000-8000-000000000006', v_id) then
    raise exception 'TECNICO, FATURAMENTO ou PAINEL_TV podem alterar hora interna de outra pessoa';
  end if;
  if not public.fn_usuario_pode_alterar_apontamento('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', '1d000000-0000-4000-8000-000000000002', v_id)
     or not public.fn_usuario_pode_alterar_apontamento('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', '1d000000-0000-4000-8000-000000000005', v_id)
     or not public.fn_usuario_pode_alterar_apontamento('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', '1d000000-0000-4000-8000-000000000007', v_id) then
    raise exception 'COORDENACAO, DIRETOR e ADMIN deviam poder alterar hora interna';
  end if;
end $pode_alterar$;

select pg_temp.como('1d000000-0000-4000-8000-000000000004');
set local role authenticated;
do $ana_edita$
begin
  begin
    perform public.app_editar_apontamento(pg_temp.ap('AP_EXAMES_ANA'), 2, '1d000000-0000-4000-8000-000000000301', 'exame periódico anual', true, null);
    raise exception 'a ANA editou a propria hora interna aprovada';
  exception when others then
    if sqlerrm <> 'Seu perfil não possui permissão para editar apontamentos.' then raise; end if;
  end;
end $ana_edita$;
reset role;
select pg_temp.sistema();

-- Coordenacao editando a hora interna de outra pessoa.
select pg_temp.como('1d000000-0000-4000-8000-000000000002');
set local role authenticated;
do $editar_coordenacao$
declare
  v_tipo uuid;
begin
  reset role;
  select h.tipo_hora_id into v_tipo from public.apontamentos_horas as h where h.id = pg_temp.ap('AP_TREINAMENTO_PEDRO');
  set local role authenticated;
  -- >>> CENARIO QUE FALHA HOJE (reportado em 14/09/2026): fn_usuario_pode_alterar_apontamento
  -- >>> diz que a coordenacao pode, mas app_editar_apontamento (e web_atualizar_apontamento_horas)
  -- >>> pergunta antes can('apontamentos', 'write'), que e falso para COORDENACAO com papel de
  -- >>> tenant GESTOR. Este trecho confere o que o banco faz HOJE; quando a coordenacao passar a
  -- >>> editar, ele quebra: troque pela edicao comentada abaixo e confira a notificacao como no
  -- >>> bloco da gestao logo depois (com "Coordenacao alterou ...").
  begin
    perform public.app_editar_apontamento(pg_temp.ap('AP_TREINAMENTO_PEDRO'), 3.25, v_tipo, 'curso de NR10 da turma', true, 'conferido com o Pedro');
    raise exception 'a coordenacao editou a hora interna do PEDRO: a trava de can() saiu, troque este trecho pela edicao comentada abaixo';
  exception when others then
    if sqlerrm <> 'Seu perfil não possui permissão para editar apontamentos.' then raise; end if;
  end;
  -- r := public.app_editar_apontamento(pg_temp.ap('AP_TREINAMENTO_PEDRO'), 3.25, v_tipo, 'curso de NR10 da turma', true, 'conferido com o Pedro');
  -- if not pg_temp.ok(r) then raise exception 'coordenacao editando hora interna: %', r; end if;
end $editar_coordenacao$;
reset role;
select pg_temp.sistema();

-- Diretor editando: pelo aplicativo (com motivo, trilha e notificacao) e pela web.
select pg_temp.como('1d000000-0000-4000-8000-000000000005');
set local role authenticated;
do $editar_gestao$
declare
  r jsonb;
  v_id uuid := pg_temp.ap('AP_TREINAMENTO_PEDRO');
  v_tipo uuid;
  v_data date;
  v_tipo_exames uuid;
  v_antes public.apontamentos_horas;
  v public.apontamentos_horas;
  v_notificacao public.app_notificacoes;
begin
  reset role;
  select * into v_antes from public.apontamentos_horas as h where h.id = v_id;
  v_tipo := v_antes.tipo_hora_id;
  v_data := v_antes.data;
  select h.tipo_hora_id into v_tipo_exames from public.apontamentos_horas as h where h.id = pg_temp.ap('AP_EXAMES_ANA');
  set local role authenticated;

  r := public.app_editar_apontamento(v_id, 3.5, v_tipo, 'curso de NR10 da turma toda', true, 'conferido com o Pedro');
  if not pg_temp.ok(r) then raise exception 'diretor editando hora interna pelo aplicativo: %', r; end if;

  reset role;
  -- A gestao editando nao vira aprovador: continua aprovacao automatica, com as datas de antes.
  select * into v from public.apontamentos_horas where id = v_id;
  if v.horas <> 3.5 or v.status_aprovacao <> 'aprovado' or v.atividade_id <> pg_temp.ap('ATIV_TREINAMENTO') or v.os_id is not null
     or v.aprovado_por is not null or v.pendente_em is not null
     or v.aprovado_automaticamente_em is distinct from v_antes.aprovado_automaticamente_em
     or v.aprovado_em is distinct from v_antes.aprovado_em then
    raise exception 'hora interna editada pelo aplicativo: antes %, depois %', to_jsonb(v_antes), to_jsonb(v);
  end if;
  if not exists (
    select 1 from public.apontamentos_horas_edicoes as e
    where e.apontamento_id = v_id and e.os_id is null and e.horas_antes = 3 and e.horas_depois = 3.5
      and e.motivo = 'conferido com o Pedro' and e.editado_por_user_id = '1d000000-0000-4000-8000-000000000005'
  ) then
    raise exception 'a trilha de edicao da hora interna nao gravou';
  end if;
  -- O PEDRO e avisado falando da atividade, e o aviso abre o historico.
  select * into v_notificacao from public.app_notificacoes as n
  where n.usuario_id = '1d000000-0000-4000-8000-000000000003' and n.tipo = 'hora_alterada' and n.dados->>'apontamento_id' = v_id::text;
  if not found then raise exception 'o PEDRO nao recebeu a notificacao da edicao'; end if;
  if v_notificacao.corpo is distinct from format('Diretor alterou a sua hora de %s em Treinamento. Motivo: conferido com o Pedro', to_char(v_data, 'DD/MM/YYYY'))
     or v_notificacao.corpo like '%na OS%'
     or v_notificacao.dados->>'url' is distinct from '/(tabs)/historico'
     or v_notificacao.dados->'os_id' is distinct from 'null'::jsonb then
    raise exception 'notificacao da edicao da hora interna: % %', v_notificacao.corpo, v_notificacao.dados;
  end if;
  set local role authenticated;

  -- Web: o que a tela manda (data, horas, tipo e descricao).
  r := public.web_atualizar_apontamento_horas(pg_temp.ap('AP_EXAMES_ANA'),
         jsonb_build_object('data', pg_temp.d('hoje'), 'horas', 1.5, 'tipo_hora_id', v_tipo_exames, 'descricao', 'exame periódico anual'));
  if not pg_temp.ok(r) then raise exception 'diretor editando hora interna pela web: %', r; end if;
  reset role;
  select * into v from public.apontamentos_horas where id = pg_temp.ap('AP_EXAMES_ANA');
  if v.horas <> 1.5 or v.descricao <> 'exame periódico anual' or v.status_aprovacao <> 'aprovado' or v.atividade_id <> pg_temp.ap('ATIV_EXAMES')
     or v.aprovado_por is not null or v.aprovado_automaticamente_em is null then
    raise exception 'hora interna editada pela web: %', to_jsonb(v);
  end if;
  set local role authenticated;

  -- Excluir pela web (app/apontamentos/page.tsx usa web_excluir_apontamento_horas).
  r := public.web_excluir_apontamento_horas(pg_temp.ap('AP_LOTE_ANA'));
  if not pg_temp.ok(r) then raise exception 'excluir hora interna pela web: %', r; end if;
  reset role;
  if exists (select 1 from public.apontamentos_horas where id = pg_temp.ap('AP_LOTE_ANA')) then raise exception 'hora interna excluida continua na tabela'; end if;
  set local role authenticated;
end $editar_gestao$;
reset role;
select pg_temp.sistema();

-- Cancelar (app_cancelar_apontamento) e descancelar (app_restaurar_apontamento).
select pg_temp.como('1d000000-0000-4000-8000-000000000002');
set local role authenticated;
do $cancelar$
declare
  r jsonb;
  v_id uuid := pg_temp.ap('AP_COMERCIAL_OUTRO_ORCAMENTO');
  v_cancelamento public.apontamentos_horas_cancelamentos;
  v_notificacao public.app_notificacoes;
begin
  r := public.app_cancelar_apontamento(v_id, 'lançado em duplicidade');
  if not pg_temp.ok(r) or (r->>'gravados')::integer <> 1 then raise exception 'coordenacao cancelando hora interna: %', r; end if;

  reset role;
  if exists (select 1 from public.apontamentos_horas where id = v_id) then
    raise exception 'a hora interna cancelada continua em apontamentos_horas';
  end if;
  -- O arquivo guarda a hora sem OS, com a atividade no lugar do numero da OS e o cliente digitado.
  select * into v_cancelamento from public.apontamentos_horas_cancelamentos as c where c.apontamento_id = v_id;
  if not found or v_cancelamento.os_id is not null or v_cancelamento.numero_os is distinct from 'Comercial'
     or v_cancelamento.cliente_nome is distinct from 'PADARIA NOVA' or v_cancelamento.colaborador_nome <> 'ANA'
     or v_cancelamento.cancelado_por_user_id <> '1d000000-0000-4000-8000-000000000002'
     or v_cancelamento.dados_apontamento->>'atividade_id' is distinct from pg_temp.ap('ATIV_COMERCIAL')::text
     or v_cancelamento.dados_apontamento->>'orcamento_descricao' is distinct from 'painel da linha 4' then
    raise exception 'arquivo do cancelamento da hora interna: %', to_jsonb(v_cancelamento);
  end if;
  -- Quem lancou (a coordenacao, para a ANA) e avisado falando da atividade, nao de OS.
  if not coalesce((r->>'notificacao_enviada')::boolean, false) then
    raise exception 'o cancelamento da hora interna nao avisou quem lancou: %', r;
  end if;
  select * into v_notificacao from public.app_notificacoes as n
  where n.usuario_id = '1d000000-0000-4000-8000-000000000002' and n.tipo = 'hora_cancelada' and n.dados->>'apontamento_id' = v_id::text;
  if not found or v_notificacao.corpo like '%na OS%'
     or v_notificacao.corpo not like '% em Comercial foram canceladas por Coordenacao. Motivo: lançado em duplicidade'
     or v_notificacao.dados->>'url' is distinct from '/(tabs)/historico' then
    raise exception 'notificacao do cancelamento da hora interna: % %', v_notificacao.corpo, v_notificacao.dados;
  end if;
  set local role authenticated;

  -- Cancelar de novo nao quebra.
  r := public.app_cancelar_apontamento(v_id, 'lançado em duplicidade');
  if not pg_temp.ok(r) or not coalesce((r->>'ja_cancelado')::boolean, false) then raise exception 'cancelar duas vezes: %', r; end if;
end $cancelar$;
reset role;
select pg_temp.sistema();

-- A propria ANA nao cancela a hora interna: ja nasce aprovada, e depois disso so a gestao.
select pg_temp.como('1d000000-0000-4000-8000-000000000004');
set local role authenticated;
do $ana_cancela$
declare r jsonb;
begin
  r := public.app_cancelar_apontamento(pg_temp.ap('AP_EXAMES_ANA'), 'lançado errado');
  if pg_temp.ok(r) or r->'erros'->0->>'tipo' is distinct from 'permissao' then
    raise exception 'a ANA cancelando a propria hora interna: %', r;
  end if;
end $ana_cancela$;
reset role;
select pg_temp.sistema();

select pg_temp.como('1d000000-0000-4000-8000-000000000002');
set local role authenticated;
do $restaurar$
declare
  r jsonb;
  v_id uuid := pg_temp.ap('AP_COMERCIAL_OUTRO_ORCAMENTO');
  v public.apontamentos_horas;
begin
  r := public.app_restaurar_apontamento(v_id);
  if not pg_temp.ok(r) then raise exception 'coordenacao descancelando hora interna: %', r; end if;
  reset role;
  select * into v from public.apontamentos_horas where id = v_id;
  if not found then raise exception 'a hora interna descancelada nao voltou'; end if;
  if v.atividade_id is distinct from pg_temp.ap('ATIV_COMERCIAL') or v.os_id is not null
     or v.cliente_nome is distinct from 'PADARIA NOVA' or v.orcamento_descricao is distinct from 'painel da linha 4'
     or v.status_aprovacao <> 'aprovado' or v.colaborador_id <> '1d000000-0000-4000-8000-000000000101' then
    raise exception 'hora interna descancelada voltou diferente: %', to_jsonb(v);
  end if;
  if not exists (select 1 from public.apontamentos_horas_cancelamentos as c
                 where c.apontamento_id = v_id and c.restaurado_em is not null
                   and c.restaurado_por_user_id = '1d000000-0000-4000-8000-000000000002') then
    raise exception 'o arquivo do cancelamento nao marcou o descancelamento';
  end if;
  set local role authenticated;
end $restaurar$;
reset role;
select pg_temp.sistema();

-- =====================================================================================
-- 11. Hora antiga de atividade que mudou depois. "Inativa" e "pede cliente" valem para a
--     hora que ENTRA na atividade (insert, ou update que troca a atividade): corrigir a hora
--     que ja estava nela continua possivel pela web (web_atualizar_apontamento_horas regrava
--     a data, e o gatilho trg_validar_apontamento_horas roda) e pelo aplicativo
--     (app_editar_apontamento, que nao toca em data, OS, atividade nem colaborador).
-- =====================================================================================
select pg_temp.como('1d000000-0000-4000-8000-000000000005');
set local role authenticated;
do $hora_antiga$
declare
  r jsonb;
  v_hoje date := pg_temp.d('hoje');
  v_id uuid := pg_temp.ap('AP_TREINAMENTO_PEDRO');
  v_tipo uuid;
  v_data date;
  v public.apontamentos_horas;
begin
  -- A gestao passa Treinamento a pedir cliente e orcamento.
  r := public.web_atividade_interna_salvar(pg_temp.ap('ATIV_TREINAMENTO'), 'treinamento', 'Treinamento', true, true, 20);
  if not pg_temp.ok(r) then raise exception 'passar Treinamento a pedir cliente: %', r; end if;
  -- Lancamento novo ja pede.
  r := public.app_lancar_horas_internas(pg_temp.ap('ATIV_TREINAMENTO'), v_hoje, pg_temp.lote('1d000000-0000-4000-8000-000000000105', 1),
         'curso de solda', null, null, null, true);
  if pg_temp.ok(r) or not pg_temp.tem_erro(r, 'cliente') or not pg_temp.tem_erro(r, 'orcamento') then
    raise exception 'Treinamento novo sem cliente, depois de passar a pedir: %', r;
  end if;

  reset role;
  select h.tipo_hora_id, h.data into v_tipo, v_data from public.apontamentos_horas as h where h.id = v_id;
  set local role authenticated;
  -- A hora antiga do PEDRO, sem cliente, edita pela web como a tela manda...
  r := public.web_atualizar_apontamento_horas(v_id,
         jsonb_build_object('data', v_data, 'horas', 2.5, 'tipo_hora_id', v_tipo, 'descricao', 'curso de NR10 da turma toda'));
  if not pg_temp.ok(r) then raise exception 'web editando hora antiga de atividade que passou a pedir cliente: %', r; end if;
  -- ...so com as horas...
  r := public.web_atualizar_apontamento_horas(v_id, jsonb_build_object('horas', 2.75));
  if not pg_temp.ok(r) then raise exception 'web editando so as horas da hora antiga: %', r; end if;
  -- ...e pelo aplicativo.
  r := public.app_editar_apontamento(v_id, 3, v_tipo, 'curso de NR10 da turma toda', true, 'ajuste de horas');
  if not pg_temp.ok(r) then raise exception 'aplicativo editando a hora antiga: %', r; end if;

  reset role;
  select * into v from public.apontamentos_horas where id = v_id;
  if v.horas <> 3 or v.atividade_id <> pg_temp.ap('ATIV_TREINAMENTO') or v.cliente_id is not null or v.cliente_nome is not null
     or v.orcamento_descricao is not null or v.status_aprovacao <> 'aprovado' then
    raise exception 'hora antiga depois das edicoes: %', to_jsonb(v);
  end if;
  -- Por fora das funcoes: entrar em Treinamento sem cliente continua recusado, inserindo ou trocando a atividade.
  begin
    insert into public.apontamentos_horas (tenant_id, empresa_id, atividade_id, colaborador_id, data, horas, tipo_hora_id)
    values ('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', pg_temp.ap('ATIV_TREINAMENTO'),
            '1d000000-0000-4000-8000-000000000105', v_hoje, 1, '1d000000-0000-4000-8000-000000000301');
    raise exception 'insert em Treinamento sem cliente gravou';
  exception when others then
    if sqlerrm not like 'Hora em Treinamento pede o cliente%' then raise; end if;
  end;
  begin
    update public.apontamentos_horas set atividade_id = pg_temp.ap('ATIV_TREINAMENTO') where id = pg_temp.ap('AP_EXAMES_ANA');
    raise exception 'trocar uma hora para Treinamento sem cliente passou';
  exception when others then
    if sqlerrm not like 'Hora em Treinamento pede o cliente%' then raise; end if;
  end;
  set local role authenticated;

  -- A gestao desativa Manutencao da fabrica.
  r := public.web_atividade_interna_salvar(pg_temp.ap('ATIV_MANUTENCAO_FABRICA'), 'manutencao_fabrica', 'Manutenção da fábrica', false, false, 30);
  if not pg_temp.ok(r) then raise exception 'desativar Manutencao: %', r; end if;
  r := public.app_lancar_horas_internas(pg_temp.ap('ATIV_MANUTENCAO_FABRICA'), v_hoje, pg_temp.lote('1d000000-0000-4000-8000-000000000104', 1),
         null, null, null, null, true);
  if pg_temp.ok(r) or r->'erros'->0->>'mensagem' is distinct from 'A atividade "Manutenção da fábrica" está inativa.' then
    raise exception 'lancamento novo em atividade desativada: %', r;
  end if;
  -- A hora antiga do sabado continua editavel pela web e pelo aplicativo.
  reset role;
  select h.tipo_hora_id, h.data into v_tipo, v_data from public.apontamentos_horas as h where h.id = pg_temp.ap('AP_SABADO');
  set local role authenticated;
  r := public.web_atualizar_apontamento_horas(pg_temp.ap('AP_SABADO'),
         jsonb_build_object('data', v_data, 'horas', 2.5, 'tipo_hora_id', v_tipo, 'descricao', 'limpeza do galpão'));
  if not pg_temp.ok(r) then raise exception 'web editando hora antiga de atividade desativada: %', r; end if;
  r := public.app_editar_apontamento(pg_temp.ap('AP_SABADO'), 3, v_tipo, 'limpeza do galpão inteiro', true, 'ajuste de horas');
  if not pg_temp.ok(r) then raise exception 'aplicativo editando hora antiga de atividade desativada: %', r; end if;

  reset role;
  select * into v from public.apontamentos_horas where id = pg_temp.ap('AP_SABADO');
  if v.horas <> 3 or v.atividade_id <> pg_temp.ap('ATIV_MANUTENCAO_FABRICA') or v.status_aprovacao <> 'aprovado' then
    raise exception 'hora antiga de atividade desativada depois das edicoes: %', to_jsonb(v);
  end if;
  -- Entrar na atividade desativada continua recusado, inserindo ou trocando a atividade.
  begin
    insert into public.apontamentos_horas (tenant_id, empresa_id, atividade_id, colaborador_id, data, horas, tipo_hora_id)
    values ('1d000000-0000-4000-8000-000000000010', '1d000000-0000-4000-8000-000000000020', pg_temp.ap('ATIV_MANUTENCAO_FABRICA'),
            '1d000000-0000-4000-8000-000000000104', v_hoje, 1, '1d000000-0000-4000-8000-000000000301');
    raise exception 'insert em atividade desativada gravou';
  exception when others then
    if sqlerrm <> 'A atividade "Manutenção da fábrica" está inativa e não recebe mais horas.' then raise; end if;
  end;
  begin
    update public.apontamentos_horas set atividade_id = pg_temp.ap('ATIV_MANUTENCAO_FABRICA') where id = pg_temp.ap('AP_INTEGRACAO_DIEGO');
    raise exception 'trocar uma hora para a atividade desativada passou';
  exception when others then
    if sqlerrm <> 'A atividade "Manutenção da fábrica" está inativa e não recebe mais horas.' then raise; end if;
  end;
  set local role authenticated;
end $hora_antiga$;
reset role;
select pg_temp.sistema();

-- Depois de editar pela web e pelo aplicativo, descancelar e excluir, nenhuma hora interna
-- saiu da aprovacao automatica.
do $aprovacao_automatica_fim$
begin
  perform pg_temp.internas_aprovacao_automatica('no fim do teste');
end $aprovacao_automatica_fim$;

rollback;
