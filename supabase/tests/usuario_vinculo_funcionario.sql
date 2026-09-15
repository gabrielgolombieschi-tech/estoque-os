\set ON_ERROR_STOP on

-- Funcionário ligado ao usuário na criação pelo aplicativo
-- (supabase/migrations/20260915150000_app_vincular_funcionario_ao_usuario.sql).
--
-- Blocos:
--   0  estrutura: uma assinatura cada, SECURITY DEFINER com search_path fixo, sem anon
--   1  permissão: as duas funções abrem exatamente para quem app_contexto_atual diz
--      pode_criar_usuario; sem sessão ou sem perfil, a frase do contexto
--   2  lista: ativos da empresa atual sem usuário; busca sem acento por nome, cargo e
--      e-mail; nada de outra empresa, de outro tenant, inativo ou já ligado
--   3  recusas do vínculo, uma a uma, com a frase exata, e nada gravado
--   4  vínculo gravado: user_id, e-mail só quando faltava, repetição do mesmo par,
--      o usuário que acabou de ser ligado não entra de novo, OWNER também liga
--
-- Contas do fixture (tenant T 1e00...0010: empresa A ...0020, empresa B ...0021;
-- tenant T2 ...0011: empresa C ...0022):
--   ...0001  admin@vinculo.test            T ADMIN,  A ADMIN        -> pode criar usuário
--   ...0002  owner@vinculo.test            T OWNER,  A COORDENACAO  -> pode criar usuário
--   ...0003  diretor@vinculo.test          T ADMIN,  A DIRETOR      -> não pode (DIRETOR)
--   ...0004  coordenacao@vinculo.test      T GESTOR, A COORDENACAO  -> não pode
--   ...0005  apontador@vinculo.test        T ADMIN,  A APONTADOR    -> não pode (APONTADOR)
--   ...0006  financeiro@vinculo.test       T GESTOR, A FINANCEIRO   -> não pode
--   ...0007  novo1@vinculo.test            T GESTOR, A TECNICO      -> recém-criado, liga na ANA
--   ...0008  novo2@vinculo.test            T GESTOR, A APONTADOR    -> recém-criado, liga no CARLOS
--   ...0009  bruno@vinculo.test            T GESTOR, A TECNICO      -> já ligado ao BRUNO
--   ...0010  so-b@vinculo.test             T GESTOR, só B TECNICO   -> sem vínculo com A
--   ...0011  ue-inativo@vinculo.test       A com usuario_empresa inativo
--   ...0012  usuario-inativo@vinculo.test  a.usuario inativo, A ativo
--   ...0013  ue-excluido@vinculo.test      A com usuario_empresa.deleted_at
--   ...0014  sem-perfil@vinculo.test       só auth.users, sem a.usuario
--   ...0015  yara@vinculo.test             T GESTOR, A e B TECNICO  -> já ligado à YARA (B)
--   ...0016  outro-tenant@vinculo.test     T2 GESTOR, C TECNICO     -> outro tenant
--   ...0017  novo3@vinculo.test            T GESTOR, A TECNICO      -> OWNER liga na ÉRICA
-- Funcionários: A: ANA ROCHA (...0101, sem e-mail), CARLOS MOTA (...0102, com e-mail),
--   BRUNO DIAS (...0103, com usuário), DORA INATIVA (...0104, inativa), ÉRICA CONCEIÇÃO
--   (...0105, e-mail em branco). B: ZECA BARROS (...0106), YARA LEAL (...0107, com
--   usuário). T2/C: XAVIER NUNES (...0108).

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select ('1e000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', e.email,
       '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('nome', e.email), now(), now()
from (values
  (1, 'admin@vinculo.test'), (2, 'owner@vinculo.test'), (3, 'diretor@vinculo.test'), (4, 'coordenacao@vinculo.test'),
  (5, 'apontador@vinculo.test'), (6, 'financeiro@vinculo.test'), (7, 'novo1@vinculo.test'), (8, 'novo2@vinculo.test'),
  (9, 'bruno@vinculo.test'), (10, 'so-b@vinculo.test'), (11, 'ue-inativo@vinculo.test'), (12, 'usuario-inativo@vinculo.test'),
  (13, 'ue-excluido@vinculo.test'), (14, 'sem-perfil@vinculo.test'), (15, 'yara@vinculo.test'), (16, 'outro-tenant@vinculo.test'),
  (17, 'novo3@vinculo.test')
) as e(n, email);

insert into public.tenants (id, nome, ativo) values
  ('1e000000-0000-4000-8000-000000000010', 'Tenant vinculo', true),
  ('1e000000-0000-4000-8000-000000000011', 'Tenant vinculo 2', true);
insert into c.tenant (id, codigo, nome, ativo) values
  ('1e000000-0000-4000-8000-000000000010', 'VINCULO', 'Tenant vinculo', true),
  ('1e000000-0000-4000-8000-000000000011', 'VINCULO2', 'Tenant vinculo 2', true);
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo) values
  ('1e000000-0000-4000-8000-000000000020', '1e000000-0000-4000-8000-000000000010', 'VI-A', 'Empresa vinculo A', 'Empresa A', '42000000000100', true),
  ('1e000000-0000-4000-8000-000000000021', '1e000000-0000-4000-8000-000000000010', 'VI-B', 'Empresa vinculo B', 'Empresa B', '42000000000200', true),
  ('1e000000-0000-4000-8000-000000000022', '1e000000-0000-4000-8000-000000000011', 'VI-C', 'Empresa vinculo C', 'Empresa C', '42000000000300', true);
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo) values
  ('1e000000-0000-4000-8000-000000000020', '1e000000-0000-4000-8000-000000000010', '42000000000100', 'Empresa vinculo A', 'Empresa A', true),
  ('1e000000-0000-4000-8000-000000000021', '1e000000-0000-4000-8000-000000000010', '42000000000200', 'Empresa vinculo B', 'Empresa B', true),
  ('1e000000-0000-4000-8000-000000000022', '1e000000-0000-4000-8000-000000000011', '42000000000300', 'Empresa vinculo C', 'Empresa C', true);

-- a.usuario: todas as contas menos a 0014 (sem perfil). A 0012 fica inativa.
insert into a.usuario (id, auth_user_id, nome, email, ativo)
select ('1e000000-0000-4000-8000-0000000004' || lpad(n::text, 2, '0'))::uuid,
       ('1e000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       initcap(split_part(u.email, '@', 1)), u.email, n <> 12
from generate_series(1, 17) as n
join auth.users as u on u.id = ('1e000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid
where n <> 14;

insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo)
select ('1e000000-0000-4000-8000-0000000004' || lpad(n::text, 2, '0'))::uuid, '1e000000-0000-4000-8000-000000000010',
       case n when 1 then 'ADMIN' when 2 then 'OWNER' when 3 then 'ADMIN' when 5 then 'ADMIN' else 'GESTOR' end, true
from generate_series(1, 17) as n
where n not in (14, 16);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo) values
  ('1e000000-0000-4000-8000-000000000416', '1e000000-0000-4000-8000-000000000011', 'GESTOR', true);

insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo, deleted_at) values
  ('1e000000-0000-4000-8000-000000000401', '1e000000-0000-4000-8000-000000000020', 'ADMIN', true, null),
  ('1e000000-0000-4000-8000-000000000402', '1e000000-0000-4000-8000-000000000020', 'COORDENACAO', true, null),
  ('1e000000-0000-4000-8000-000000000403', '1e000000-0000-4000-8000-000000000020', 'DIRETOR', true, null),
  ('1e000000-0000-4000-8000-000000000404', '1e000000-0000-4000-8000-000000000020', 'COORDENACAO', true, null),
  ('1e000000-0000-4000-8000-000000000405', '1e000000-0000-4000-8000-000000000020', 'APONTADOR', true, null),
  ('1e000000-0000-4000-8000-000000000406', '1e000000-0000-4000-8000-000000000020', 'FINANCEIRO', true, null),
  ('1e000000-0000-4000-8000-000000000407', '1e000000-0000-4000-8000-000000000020', 'TECNICO', true, null),
  ('1e000000-0000-4000-8000-000000000408', '1e000000-0000-4000-8000-000000000020', 'APONTADOR', true, null),
  ('1e000000-0000-4000-8000-000000000409', '1e000000-0000-4000-8000-000000000020', 'TECNICO', true, null),
  ('1e000000-0000-4000-8000-000000000410', '1e000000-0000-4000-8000-000000000021', 'TECNICO', true, null),
  ('1e000000-0000-4000-8000-000000000411', '1e000000-0000-4000-8000-000000000020', 'TECNICO', false, null),
  ('1e000000-0000-4000-8000-000000000412', '1e000000-0000-4000-8000-000000000020', 'TECNICO', true, null),
  ('1e000000-0000-4000-8000-000000000413', '1e000000-0000-4000-8000-000000000020', 'TECNICO', true, now()),
  ('1e000000-0000-4000-8000-000000000415', '1e000000-0000-4000-8000-000000000020', 'TECNICO', true, null),
  ('1e000000-0000-4000-8000-000000000415', '1e000000-0000-4000-8000-000000000021', 'TECNICO', true, null),
  ('1e000000-0000-4000-8000-000000000416', '1e000000-0000-4000-8000-000000000022', 'TECNICO', true, null),
  ('1e000000-0000-4000-8000-000000000417', '1e000000-0000-4000-8000-000000000020', 'TECNICO', true, null);

-- Contexto: todas as contas que falam no teste olham para a empresa A.
insert into public.user_tenant_context (user_id, tenant_id)
select ('1e000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, '1e000000-0000-4000-8000-000000000010'
from generate_series(1, 6) as n;
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
select ('1e000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, '1e000000-0000-4000-8000-000000000010', '1e000000-0000-4000-8000-000000000020'
from generate_series(1, 6) as n;

insert into public.colaboradores (id, nome, cargo, area, ativo, tenant_id, empresa_id, user_id, email) values
  ('1e000000-0000-4000-8000-000000000101', 'ANA ROCHA', 'ELETRICISTA', 'eletrica', true, '1e000000-0000-4000-8000-000000000010', '1e000000-0000-4000-8000-000000000020', null, null),
  ('1e000000-0000-4000-8000-000000000102', 'CARLOS MOTA', 'MONTADOR', 'mecanica', true, '1e000000-0000-4000-8000-000000000010', '1e000000-0000-4000-8000-000000000020', null, 'carlos.mota@empresa.test'),
  ('1e000000-0000-4000-8000-000000000103', 'BRUNO DIAS', 'MECANICO', 'mecanica', true, '1e000000-0000-4000-8000-000000000010', '1e000000-0000-4000-8000-000000000020', '1e000000-0000-4000-8000-000000000009', 'bruno@vinculo.test'),
  ('1e000000-0000-4000-8000-000000000104', 'DORA INATIVA', 'AJUDANTE', null, false, '1e000000-0000-4000-8000-000000000010', '1e000000-0000-4000-8000-000000000020', null, null),
  ('1e000000-0000-4000-8000-000000000105', 'ÉRICA CONCEIÇÃO', 'PROJETISTA', 'engenharia', true, '1e000000-0000-4000-8000-000000000010', '1e000000-0000-4000-8000-000000000020', null, '   '),
  ('1e000000-0000-4000-8000-000000000106', 'ZECA BARROS', 'MONTADOR', 'mecanica', true, '1e000000-0000-4000-8000-000000000010', '1e000000-0000-4000-8000-000000000021', null, null),
  ('1e000000-0000-4000-8000-000000000107', 'YARA LEAL', 'ELETRICISTA', 'eletrica', true, '1e000000-0000-4000-8000-000000000010', '1e000000-0000-4000-8000-000000000021', '1e000000-0000-4000-8000-000000000015', null),
  ('1e000000-0000-4000-8000-000000000108', 'XAVIER NUNES', 'MONTADOR', 'mecanica', true, '1e000000-0000-4000-8000-000000000011', '1e000000-0000-4000-8000-000000000022', null, null);

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

-- A chamada tem de ser recusada com exatamente esta frase.
create or replace function pg_temp.recusa(p_colaborador uuid, p_usuario uuid, p_frase text, p_caso text) returns void language plpgsql as $$
begin
  begin
    perform public.app_vincular_funcionario_ao_usuario(p_colaborador, p_usuario);
  exception when others then
    if sqlerrm is distinct from p_frase then
      raise exception '%: esperava "%", veio "%"', p_caso, p_frase, sqlerrm;
    end if;
    return;
  end;
  raise exception '%: o vinculo passou, devia recusar com "%"', p_caso, p_frase;
end $$;

-- Nomes da lista, na ordem da função.
create or replace function pg_temp.lista(p_busca text) returns text[] language sql as $$
  select coalesce(array_agg(f.nome order by f.ordem), '{}'::text[])
  from public.app_funcionarios_sem_usuario(p_busca) with ordinality as f(id, nome, cargo, area, email, ordem);
$$;

-- Estado dos funcionários do fixture, para conferir que recusa nenhuma gravou nada.
create temp table estado_antes as
select c.id, c.nome, c.cargo, c.area, c.ativo, c.tenant_id, c.empresa_id, c.user_id, c.email
from public.colaboradores as c
where c.id::text like '1e000000-%';

-- =====================================================================================
-- 0. Estrutura
-- =====================================================================================
do $estrutura$
declare
  v_funcao text;
begin
  foreach v_funcao in array array['public.app_funcionarios_sem_usuario(text)', 'public.app_vincular_funcionario_ao_usuario(uuid,uuid)'] loop
    if (select count(*) from pg_proc as p
         where p.pronamespace = 'public'::regnamespace
           and p.proname = (select alvo.proname from pg_proc as alvo where alvo.oid = v_funcao::regprocedure)) <> 1 then
      raise exception '% tem mais de uma assinatura', v_funcao;
    end if;
    if not (select p.prosecdef from pg_proc as p where p.oid = v_funcao::regprocedure) then
      raise exception '% devia ser SECURITY DEFINER', v_funcao;
    end if;
    if not exists (select 1 from pg_proc as p, unnest(p.proconfig) as cfg
                    where p.oid = v_funcao::regprocedure and cfg like 'search\_path=%') then
      raise exception '% sem search_path fixo', v_funcao;
    end if;
    if has_function_privilege('anon', v_funcao, 'execute') then
      raise exception '% aberta para anon', v_funcao;
    end if;
    if not has_function_privilege('authenticated', v_funcao, 'execute') then
      raise exception '% fechada para authenticated', v_funcao;
    end if;
  end loop;
end $estrutura$;

-- =====================================================================================
-- 1. Permissão: igual a pode_criar_usuario de app_contexto_atual.
--    Para quem pode, o vínculo vai com um funcionário que não existe (passa da
--    permissão e para em "não encontrado", sem gravar). Para quem não pode, vai o par de
--    verdade ANA + novo1, e tem de parar antes de olhar qualquer coisa.
-- =====================================================================================
create or replace function pg_temp.permissao(p_quem text, p_esperado boolean) returns void language plpgsql as $$
declare
  v_pode boolean := (public.app_contexto_atual()->>'pode_criar_usuario')::boolean;
begin
  if v_pode is distinct from p_esperado then
    raise exception '%: app_contexto_atual devia dizer pode_criar_usuario=%, disse %', p_quem, p_esperado, v_pode;
  end if;

  if v_pode then
    if cardinality(pg_temp.lista(null)) <> 3 then
      raise exception '%: pode criar usuario e nao listou os 3 funcionarios sem usuario', p_quem;
    end if;
    perform pg_temp.recusa('1e000000-0000-4000-8000-00000000ffff', '1e000000-0000-4000-8000-000000000007',
                           'Funcionário não encontrado nesta empresa.', p_quem || ' (pode criar usuario)');
  else
    begin
      perform public.app_funcionarios_sem_usuario(null);
      raise exception '%: nao pode criar usuario e listou os funcionarios', p_quem;
    exception when others then
      if sqlerrm <> 'Seu perfil não pode criar usuários.' then raise; end if;
    end;
    perform pg_temp.recusa('1e000000-0000-4000-8000-000000000101', '1e000000-0000-4000-8000-000000000007',
                           'Seu perfil não pode criar usuários.', p_quem || ' (nao pode criar usuario)');
  end if;
end $$;

select pg_temp.como('1e000000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.permissao('ADMIN do tenant, ADMIN na empresa', true);
reset role;
select pg_temp.sistema();

select pg_temp.como('1e000000-0000-4000-8000-000000000002');
set local role authenticated;
select pg_temp.permissao('OWNER do tenant, COORDENACAO na empresa', true);
reset role;
select pg_temp.sistema();

select pg_temp.como('1e000000-0000-4000-8000-000000000003');
set local role authenticated;
select pg_temp.permissao('ADMIN do tenant, DIRETOR na empresa', false);
reset role;
select pg_temp.sistema();

select pg_temp.como('1e000000-0000-4000-8000-000000000004');
set local role authenticated;
select pg_temp.permissao('GESTOR do tenant, COORDENACAO na empresa', false);
reset role;
select pg_temp.sistema();

select pg_temp.como('1e000000-0000-4000-8000-000000000005');
set local role authenticated;
select pg_temp.permissao('ADMIN do tenant, APONTADOR na empresa', false);
reset role;
select pg_temp.sistema();

select pg_temp.como('1e000000-0000-4000-8000-000000000006');
set local role authenticated;
select pg_temp.permissao('GESTOR do tenant, FINANCEIRO na empresa', false);
reset role;
select pg_temp.sistema();

-- Sem sessão e sem perfil (auth user sem a.usuario): a frase do próprio contexto.
create or replace function pg_temp.sem_contexto(p_quem text) returns void language plpgsql as $$
begin
  begin
    perform public.app_funcionarios_sem_usuario(null);
    raise exception '%: listou sem contexto', p_quem;
  exception when others then
    if sqlerrm <> 'Autenticação e contexto de empresa são obrigatórios.' then raise; end if;
  end;
  perform pg_temp.recusa('1e000000-0000-4000-8000-000000000101', '1e000000-0000-4000-8000-000000000007',
                         'Autenticação e contexto de empresa são obrigatórios.', p_quem);
end $$;

set local role authenticated;
select pg_temp.sem_contexto('sem sessao');
reset role;

select pg_temp.como('1e000000-0000-4000-8000-000000000014');
set local role authenticated;
select pg_temp.sem_contexto('auth user sem a.usuario');
reset role;
select pg_temp.sistema();

-- =====================================================================================
-- 2. Lista
-- =====================================================================================
select pg_temp.como('1e000000-0000-4000-8000-000000000001');
set local role authenticated;
do $lista$
declare
  v_linha record;
  v_busca text;
begin
  if pg_temp.lista(null) is distinct from array['ANA ROCHA', 'CARLOS MOTA', 'ÉRICA CONCEIÇÃO'] then
    raise exception 'lista sem busca: %', pg_temp.lista(null);
  end if;
  -- Busca em branco vale como sem busca.
  if pg_temp.lista('   ') is distinct from pg_temp.lista(null) or pg_temp.lista('') is distinct from pg_temp.lista(null) then
    raise exception 'busca em branco devia trazer a lista inteira: %', pg_temp.lista('   ');
  end if;

  select * into v_linha from public.app_funcionarios_sem_usuario(null) as f where f.nome = 'CARLOS MOTA';
  if v_linha.id <> '1e000000-0000-4000-8000-000000000102' or v_linha.cargo <> 'MONTADOR'
     or v_linha.area <> 'mecanica' or v_linha.email <> 'carlos.mota@empresa.test' then
    raise exception 'colunas do CARLOS: %', to_jsonb(v_linha);
  end if;
  select * into v_linha from public.app_funcionarios_sem_usuario(null) as f where f.nome = 'ANA ROCHA';
  if v_linha.email is not null or v_linha.cargo <> 'ELETRICISTA' or v_linha.area <> 'eletrica' then
    raise exception 'colunas da ANA: %', to_jsonb(v_linha);
  end if;
  -- E-mail só com espaços chega como nulo: a tela não preenche o campo com branco.
  select * into v_linha from public.app_funcionarios_sem_usuario(null) as f where f.nome = 'ÉRICA CONCEIÇÃO';
  if v_linha.email is not null or v_linha.area <> 'engenharia' then
    raise exception 'colunas da ERICA: %', to_jsonb(v_linha);
  end if;

  -- Sem acento, com acento, pedaço do sobrenome, cargo e e-mail.
  foreach v_busca in array array['erica', 'ÉRICA', 'conceicao', 'Conceição', 'projetis'] loop
    if pg_temp.lista(v_busca) is distinct from array['ÉRICA CONCEIÇÃO'] then
      raise exception 'busca "%": %', v_busca, pg_temp.lista(v_busca);
    end if;
  end loop;
  foreach v_busca in array array['montador', 'carlos.mota@', 'EMPRESA.TEST', '  mota '] loop
    if pg_temp.lista(v_busca) is distinct from array['CARLOS MOTA'] then
      raise exception 'busca "%": %', v_busca, pg_temp.lista(v_busca);
    end if;
  end loop;
  -- "%" e "_" são texto, não curinga.
  if cardinality(pg_temp.lista('%')) <> 0 or cardinality(pg_temp.lista('_')) <> 0 then
    raise exception 'busca tratou %% ou _ como curinga';
  end if;

  -- Fora da lista: outra empresa (ZECA, YARA), outro tenant (XAVIER), inativa (DORA) e
  -- quem já tem usuário (BRUNO, YARA).
  foreach v_busca in array array['zeca', 'yara', 'xavier', 'dora', 'bruno'] loop
    if cardinality(pg_temp.lista(v_busca)) <> 0 then
      raise exception 'busca "%" devia vir vazia: %', v_busca, pg_temp.lista(v_busca);
    end if;
  end loop;
end $lista$;
reset role;
select pg_temp.sistema();

-- =====================================================================================
-- 3. Recusas do vínculo (como ADMIN)
-- =====================================================================================
select pg_temp.como('1e000000-0000-4000-8000-000000000001');
set local role authenticated;
do $recusas$
declare
  v_ana constant uuid := '1e000000-0000-4000-8000-000000000101';
  v_novo1 constant uuid := '1e000000-0000-4000-8000-000000000007';
begin
  perform pg_temp.recusa(null, v_novo1, 'Escolha o funcionário.', 'sem funcionario');
  perform pg_temp.recusa(v_ana, null, 'Informe o usuário que vai ficar ligado ao funcionário.', 'sem usuario');

  -- Funcionário de outra empresa do mesmo tenant, de outro tenant, que não existe; inativo.
  perform pg_temp.recusa('1e000000-0000-4000-8000-000000000106', v_novo1, 'Funcionário não encontrado nesta empresa.', 'funcionario da empresa B');
  perform pg_temp.recusa('1e000000-0000-4000-8000-000000000108', v_novo1, 'Funcionário não encontrado nesta empresa.', 'funcionario de outro tenant');
  perform pg_temp.recusa(gen_random_uuid(), v_novo1, 'Funcionário não encontrado nesta empresa.', 'funcionario que nao existe');
  perform pg_temp.recusa('1e000000-0000-4000-8000-000000000104', v_novo1, 'O funcionário DORA INATIVA está inativo.', 'funcionario inativo');

  -- Funcionário que já tem usuário.
  perform pg_temp.recusa('1e000000-0000-4000-8000-000000000103', v_novo1, 'O funcionário BRUNO DIAS já está ligado a outro usuário.', 'funcionario com usuario');

  -- Usuário sem vínculo ativo com a empresa A.
  perform pg_temp.recusa(v_ana, '1e000000-0000-4000-8000-000000000010', 'Este usuário não tem vínculo ativo com esta empresa.', 'usuario so da empresa B');
  perform pg_temp.recusa(v_ana, '1e000000-0000-4000-8000-000000000011', 'Este usuário não tem vínculo ativo com esta empresa.', 'usuario_empresa inativo');
  perform pg_temp.recusa(v_ana, '1e000000-0000-4000-8000-000000000012', 'Este usuário não tem vínculo ativo com esta empresa.', 'a.usuario inativo');
  perform pg_temp.recusa(v_ana, '1e000000-0000-4000-8000-000000000013', 'Este usuário não tem vínculo ativo com esta empresa.', 'usuario_empresa excluido');
  perform pg_temp.recusa(v_ana, '1e000000-0000-4000-8000-000000000014', 'Este usuário não tem vínculo ativo com esta empresa.', 'auth user sem a.usuario');
  perform pg_temp.recusa(v_ana, '1e000000-0000-4000-8000-000000000016', 'Este usuário não tem vínculo ativo com esta empresa.', 'usuario de outro tenant');
  perform pg_temp.recusa(v_ana, gen_random_uuid(), 'Este usuário não tem vínculo ativo com esta empresa.', 'usuario que nao existe');

  -- Usuário já ligado a outro funcionário: da mesma empresa (diz qual) e de outra (não diz).
  perform pg_temp.recusa(v_ana, '1e000000-0000-4000-8000-000000000009', 'Este usuário já está ligado ao funcionário BRUNO DIAS.', 'usuario ligado na empresa A');
  perform pg_temp.recusa(v_ana, '1e000000-0000-4000-8000-000000000015', 'Este usuário já está ligado a um funcionário de outra empresa.', 'usuario ligado na empresa B');
end $recusas$;
reset role;
select pg_temp.sistema();

do $nada_gravado$
begin
  if exists (
    (select * from estado_antes)
    except
    (select c.id, c.nome, c.cargo, c.area, c.ativo, c.tenant_id, c.empresa_id, c.user_id, c.email
       from public.colaboradores as c where c.id::text like '1e000000-%')
  ) or (select count(*) from public.colaboradores as c where c.id::text like '1e000000-%') <> (select count(*) from estado_antes) then
    raise exception 'alguma recusa gravou em colaboradores';
  end if;
end $nada_gravado$;

-- =====================================================================================
-- 4. Vínculo gravado
-- =====================================================================================
select pg_temp.como('1e000000-0000-4000-8000-000000000001');
set local role authenticated;
do $vinculo_admin$
declare
  r jsonb;
begin
  -- ANA, sem e-mail: fica com o e-mail do usuário.
  r := public.app_vincular_funcionario_ao_usuario('1e000000-0000-4000-8000-000000000101', '1e000000-0000-4000-8000-000000000007');
  if r is distinct from jsonb_build_object('sucesso', true, 'ja_estava_vinculado', false, 'colaborador_id', '1e000000-0000-4000-8000-000000000101',
                                           'nome', 'ANA ROCHA', 'email', 'novo1@vinculo.test') then
    raise exception 'vincular ANA: %', r;
  end if;

  -- O mesmo par de novo: sucesso, sem mudar nada.
  r := public.app_vincular_funcionario_ao_usuario('1e000000-0000-4000-8000-000000000101', '1e000000-0000-4000-8000-000000000007');
  if not coalesce((r->>'sucesso')::boolean, false) or not coalesce((r->>'ja_estava_vinculado')::boolean, false)
     or r->>'email' is distinct from 'novo1@vinculo.test' then
    raise exception 'repetir ANA + novo1: %', r;
  end if;

  -- CARLOS, com e-mail: o e-mail dele fica.
  r := public.app_vincular_funcionario_ao_usuario('1e000000-0000-4000-8000-000000000102', '1e000000-0000-4000-8000-000000000008');
  if not coalesce((r->>'sucesso')::boolean, false) or r->>'email' is distinct from 'carlos.mota@empresa.test' then
    raise exception 'vincular CARLOS: %', r;
  end if;

  -- Quem acabou de ser ligado não liga em outro, e a ANA não troca de usuário.
  perform pg_temp.recusa('1e000000-0000-4000-8000-000000000105', '1e000000-0000-4000-8000-000000000007',
                         'Este usuário já está ligado ao funcionário ANA ROCHA.', 'novo1 de novo, na ERICA');
  perform pg_temp.recusa('1e000000-0000-4000-8000-000000000101', '1e000000-0000-4000-8000-000000000008',
                         'O funcionário ANA ROCHA já está ligado a outro usuário.', 'ANA com outro usuario');

  if pg_temp.lista(null) is distinct from array['ÉRICA CONCEIÇÃO'] then
    raise exception 'depois de ligar ANA e CARLOS a lista devia ter so a ERICA: %', pg_temp.lista(null);
  end if;
end $vinculo_admin$;
reset role;
select pg_temp.sistema();

-- OWNER também liga. ÉRICA tinha e-mail só com espaços: conta como sem e-mail.
select pg_temp.como('1e000000-0000-4000-8000-000000000002');
set local role authenticated;
do $vinculo_owner$
declare
  r jsonb;
begin
  r := public.app_vincular_funcionario_ao_usuario('1e000000-0000-4000-8000-000000000105', '1e000000-0000-4000-8000-000000000017');
  if not coalesce((r->>'sucesso')::boolean, false) or r->>'email' is distinct from 'novo3@vinculo.test' or r->>'nome' is distinct from 'ÉRICA CONCEIÇÃO' then
    raise exception 'OWNER vinculando ERICA: %', r;
  end if;
  if cardinality(pg_temp.lista(null)) <> 0 then
    raise exception 'todos os funcionarios ativos da empresa A tem usuario; a lista devia vir vazia: %', pg_temp.lista(null);
  end if;
end $vinculo_owner$;
reset role;
select pg_temp.sistema();

do $gravado$
declare
  v_diferencas text;
begin
  -- Mudou só user_id e email de ANA, CARLOS (só user_id) e ÉRICA; o resto está igual.
  select string_agg(format('%s: %s -> %s', a.nome, to_jsonb(a), to_jsonb(d)), '; ')
    into v_diferencas
  from estado_antes as a
  join lateral (
    select c.id, c.nome, c.cargo, c.area, c.ativo, c.tenant_id, c.empresa_id, c.user_id, c.email
    from public.colaboradores as c where c.id = a.id
  ) as d on true
  where (a.nome, a.cargo, a.area, a.ativo, a.tenant_id, a.empresa_id) is distinct from (d.nome, d.cargo, d.area, d.ativo, d.tenant_id, d.empresa_id)
     or (a.id not in ('1e000000-0000-4000-8000-000000000101', '1e000000-0000-4000-8000-000000000102', '1e000000-0000-4000-8000-000000000105')
         and (a.user_id, a.email) is distinct from (d.user_id, d.email));
  if v_diferencas is not null then
    raise exception 'vinculo mexeu no que nao devia: %', v_diferencas;
  end if;

  if (select row(c.user_id, c.email) from public.colaboradores as c where c.id = '1e000000-0000-4000-8000-000000000101')
       is distinct from row('1e000000-0000-4000-8000-000000000007'::uuid, 'novo1@vinculo.test'::text) then
    raise exception 'ANA gravada errado';
  end if;
  if (select row(c.user_id, c.email) from public.colaboradores as c where c.id = '1e000000-0000-4000-8000-000000000102')
       is distinct from row('1e000000-0000-4000-8000-000000000008'::uuid, 'carlos.mota@empresa.test'::text) then
    raise exception 'CARLOS gravado errado';
  end if;
  if (select row(c.user_id, c.email) from public.colaboradores as c where c.id = '1e000000-0000-4000-8000-000000000105')
       is distinct from row('1e000000-0000-4000-8000-000000000017'::uuid, 'novo3@vinculo.test'::text) then
    raise exception 'ERICA gravada errado';
  end if;

  raise notice 'OK: estrutura, permissao igual a pode_criar_usuario, lista e busca, recusas e vinculo gravado.';
end $gravado$;

rollback;
