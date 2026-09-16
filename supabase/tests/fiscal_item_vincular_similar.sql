\set ON_ERROR_STOP on

-- "Vincular com similar" na conferencia da NF-e
-- (supabase/migrations/20260916130000_fiscal_item_vincular_similar.sql).
--
-- Blocos:
--   0  estrutura: SECURITY DEFINER com search_path fixo, sem anon; a funcao de permissao
--      nao e chamavel direto
--   1  permissao: igual a can('fiscal_itens','write'); APONTADOR e sem sessao recusados
--   2  busca: so fiscal completo, ativo, da empresa; mesmo NCM primeiro, depois palavras,
--      fabricante e grupo; busca por id, codigo e nome; origem 1 marcada como nao copiavel
--   3  recusas da copia, uma a uma, com a frase exata, e nada gravado
--   4  copia gravada: so os campos marcados, procedencia, audit_log, e linha fiscal criada
--      para item que nao tinha
--
-- Contas (tenant T 1f00...0010: empresa A ...0020, empresa B ...0021):
--   ...0001  admin@similar.test      T ADMIN,  A ADMIN      -> pode
--   ...0002  apontador@similar.test  T ADMIN,  A APONTADOR  -> nao pode
--   ...0003  tecnico@similar.test    T GESTOR, A TECNICO    -> o que can() disser
-- Itens da empresa A:
--   91001 CLP CP1H (OMRON), sem fiscal, NCM 85371020 so no cadastro antigo  <- o alvo
--   91002 CLP CP1E (OMRON), NCM 85371020, origem 2, sem CEST
--   91003 CLP S7-1200 (SIEMENS), NCM 85371020, origem 0, com CEST
--   91004 CONTATOR 9A, NCM 85364900, origem 0                -> so aparece buscando
--   91005 CLP ZELIO (SCHNEIDER), NCM 85371090, origem 1 equiparado
--   91006 CLP SEM NCM, fiscal sem NCM                          -> nunca aparece
--   91007 CLP INATIVO, fiscal completo, inativo                -> nunca aparece
--   91010 CLP SEM LINHA FISCAL, sem linha em fiscal_itens      <- alvo do insert
-- Empresa B: 91008 CLP OUTRA EMPRESA (completo), 91009 CLP ALVO B (sem fiscal).

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select ('1f000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', e.email,
       '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('nome', e.email), now(), now()
from (values (1, 'admin@similar.test'), (2, 'apontador@similar.test'), (3, 'tecnico@similar.test')) as e(n, email);

insert into public.tenants (id, nome, ativo) values ('1f000000-0000-4000-8000-000000000010', 'Tenant similar', true);
insert into c.tenant (id, codigo, nome, ativo) values ('1f000000-0000-4000-8000-000000000010', 'SIMILAR', 'Tenant similar', true);
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo) values
  ('1f000000-0000-4000-8000-000000000020', '1f000000-0000-4000-8000-000000000010', 'SI-A', 'Empresa similar A', 'Empresa A', '43000000000100', true),
  ('1f000000-0000-4000-8000-000000000021', '1f000000-0000-4000-8000-000000000010', 'SI-B', 'Empresa similar B', 'Empresa B', '43000000000200', true);
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo) values
  ('1f000000-0000-4000-8000-000000000020', '1f000000-0000-4000-8000-000000000010', '43000000000100', 'Empresa similar A', 'Empresa A', true),
  ('1f000000-0000-4000-8000-000000000021', '1f000000-0000-4000-8000-000000000010', '43000000000200', 'Empresa similar B', 'Empresa B', true);

insert into a.usuario (id, auth_user_id, nome, email, ativo)
select ('1f000000-0000-4000-8000-0000000004' || lpad(n::text, 2, '0'))::uuid,
       ('1f000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       initcap(split_part(u.email, '@', 1)), u.email, true
from generate_series(1, 3) as n
join auth.users as u on u.id = ('1f000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid;

insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo) values
  ('1f000000-0000-4000-8000-000000000401', '1f000000-0000-4000-8000-000000000010', 'ADMIN', true),
  ('1f000000-0000-4000-8000-000000000402', '1f000000-0000-4000-8000-000000000010', 'ADMIN', true),
  ('1f000000-0000-4000-8000-000000000403', '1f000000-0000-4000-8000-000000000010', 'GESTOR', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo, deleted_at) values
  ('1f000000-0000-4000-8000-000000000401', '1f000000-0000-4000-8000-000000000020', 'ADMIN', true, null),
  ('1f000000-0000-4000-8000-000000000401', '1f000000-0000-4000-8000-000000000021', 'ADMIN', true, null),
  ('1f000000-0000-4000-8000-000000000402', '1f000000-0000-4000-8000-000000000020', 'APONTADOR', true, null),
  ('1f000000-0000-4000-8000-000000000403', '1f000000-0000-4000-8000-000000000020', 'TECNICO', true, null);

insert into public.user_tenant_context (user_id, tenant_id)
select ('1f000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, '1f000000-0000-4000-8000-000000000010'
from generate_series(1, 3) as n;
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
select ('1f000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, '1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000020'
from generate_series(1, 3) as n;

insert into public.itens (id, codigo_interno, nome, tipo, finalidade, fabricante, ncm, ativo, tenant_id, empresa_id) values
  (91001, 'SIMCP1H', 'CLP CP1H -24XDI PNP/NPN - 16XDO NPN - 1XAI', 'produto', 'revenda', 'OMRON', '85371020', true, '1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000020'),
  (91002, 'SIMCP1E', 'CLP CP1E 20 PONTOS NPN', 'produto', 'revenda', 'OMRON', null, true, '1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000020'),
  (91003, 'SIMS71200', 'CLP S7-1200 CPU 1214C', 'produto', 'revenda', 'SIEMENS', null, true, '1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000020'),
  (91004, 'SIMCONT9A', 'CONTATOR 9A 24VCC', 'produto', 'revenda', 'WEG', null, true, '1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000020'),
  (91005, 'SIMZELIO', 'CLP ZELIO SR2', 'produto', 'revenda', 'SCHNEIDER', null, true, '1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000020'),
  (91006, 'SIMSEMNCM', 'CLP SEM NCM', 'produto', 'revenda', 'OMRON', null, true, '1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000020'),
  (91007, 'SIMINATIVO', 'CLP INATIVO', 'produto', 'revenda', 'OMRON', null, false, '1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000020'),
  (91010, 'SIMSEMLINHA', 'CLP SEM LINHA FISCAL', 'produto', 'revenda', null, null, true, '1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000020'),
  (91008, 'SIMOUTRA', 'CLP OUTRA EMPRESA', 'produto', 'revenda', 'OMRON', null, true, '1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000021'),
  (91009, 'SIMALVOB', 'CLP ALVO B', 'produto', 'revenda', 'OMRON', null, true, '1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000021');

-- Algum gatilho de itens pode ja ter criado a linha fiscal vazia; o fixture decide sozinho.
delete from public.fiscal_itens where item_id between 91001 and 91010;

insert into public.fiscal_itens (tenant_id, empresa_id, item_id, ncm, cest, origem, cfop_padrao, cst_icms, cst_pis, cst_cofins, cst_ipi, unidade_tributavel, aliq_icms, aliq_ipi, aliq_pis, aliq_cofins, equiparado_industrial) values
  ('1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000020', 91001, null, null, null, null, null, null, null, null, null, null, null, null, null, false),
  ('1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000020', 91002, '85371020', null, 2, '5102', '00', '01', '01', '53', 'UN', 17, 0, 1.65, 7.6, false),
  ('1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000020', 91003, '85371020', '1200100', 0, '5102', '00', '01', '01', '53', 'UN', 12, 0, 1.65, 7.6, false),
  ('1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000020', 91004, '85364900', null, 0, '5102', '00', '01', '01', '53', 'UN', 17, 0, 1.65, 7.6, false),
  ('1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000020', 91005, '85371090', null, 1, '5102', '00', '01', '01', '50', 'UN', 17, 5, 1.65, 7.6, true),
  ('1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000020', 91006, null, null, 0, '5102', '00', '01', '01', '53', 'UN', 17, 0, 1.65, 7.6, false),
  ('1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000020', 91007, '85371020', null, 0, '5102', '00', '01', '01', '53', 'UN', 17, 0, 1.65, 7.6, false),
  ('1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000021', 91008, '85371020', null, 0, '5102', '00', '01', '01', '53', 'UN', 17, 0, 1.65, 7.6, false),
  ('1f000000-0000-4000-8000-000000000010', '1f000000-0000-4000-8000-000000000021', 91009, null, null, null, null, null, null, null, null, null, null, null, null, null, false);

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

-- A copia tem de ser recusada com exatamente esta frase.
create or replace function pg_temp.recusa(p_item integer, p_similar integer, p_campos text[], p_frase text, p_caso text) returns void language plpgsql as $$
begin
  begin
    perform public.fiscal_item_copiar_de_similar(p_item, p_similar, p_campos);
  exception when others then
    if sqlerrm is distinct from p_frase then
      raise exception '%: esperava "%", veio "%"', p_caso, p_frase, sqlerrm;
    end if;
    return;
  end;
  raise exception '%: a copia passou, devia recusar com "%"', p_caso, p_frase;
end $$;

-- Ids dos candidatos, na ordem da funcao.
create or replace function pg_temp.ids(p_item integer, p_busca text) returns integer[] language sql as $$
  select coalesce(array_agg((c->>'id')::integer order by o), '{}'::integer[])
  from jsonb_array_elements(public.fiscal_item_similares(p_item, p_busca)->'candidatos') with ordinality as x(c, o);
$$;

create temp table fiscal_antes as
select fi.* from public.fiscal_itens fi where fi.item_id between 91001 and 91010;
grant select on fiscal_antes to authenticated;

-- =====================================================================================
-- 0. Estrutura
-- =====================================================================================
do $estrutura$
declare
  v_funcao text;
begin
  foreach v_funcao in array array[
    'public.fiscal_item_similares(integer,text,integer)',
    'public.fiscal_item_copiar_de_similar(integer,integer,text[])',
    'public.fiscal_item_permissao_copiar_similar()'
  ] loop
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
  end loop;
  if not has_function_privilege('authenticated', 'public.fiscal_item_similares(integer,text,integer)', 'execute')
     or not has_function_privilege('authenticated', 'public.fiscal_item_copiar_de_similar(integer,integer,text[])', 'execute') then
    raise exception 'busca e copia deviam abrir para authenticated';
  end if;
  if has_function_privilege('authenticated', 'public.fiscal_item_permissao_copiar_similar()', 'execute') then
    raise exception 'a funcao de permissao nao devia ser chamavel direto';
  end if;
end $estrutura$;

-- =====================================================================================
-- 1. Permissao: can('fiscal_itens','write'). Quem pode passa da permissao e para em
--    "nao encontrado" (item que nao existe); quem nao pode para antes.
-- =====================================================================================
create or replace function pg_temp.permissao(p_quem text, p_esperado boolean) returns void language plpgsql as $$
declare
  v_pode boolean := coalesce(public.can('fiscal_itens', 'write'), false);
begin
  if p_esperado is not null and v_pode is distinct from p_esperado then
    raise exception '%: can(fiscal_itens, write) devia ser %, foi %', p_quem, p_esperado, v_pode;
  end if;
  if v_pode then
    perform pg_temp.recusa(99999999, 91002, array['origem'], 'Item #99999999 nao encontrado nesta empresa.', p_quem);
    if cardinality(pg_temp.ids(91001, null)) = 0 then
      raise exception '%: pode e a busca veio vazia', p_quem;
    end if;
  else
    perform pg_temp.recusa(91001, 91002, array['origem'], 'Sem permissao para editar o cadastro fiscal de itens.', p_quem);
    begin
      perform public.fiscal_item_similares(91001, null);
      raise exception '%: nao pode e buscou similares', p_quem;
    exception when others then
      if sqlerrm <> 'Sem permissao para editar o cadastro fiscal de itens.' then raise; end if;
    end;
  end if;
end $$;

select pg_temp.como('1f000000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.permissao('ADMIN do tenant, ADMIN na empresa', true);
reset role;
select pg_temp.sistema();

select pg_temp.como('1f000000-0000-4000-8000-000000000002');
set local role authenticated;
select pg_temp.permissao('ADMIN do tenant, APONTADOR na empresa', false);
reset role;
select pg_temp.sistema();

select pg_temp.como('1f000000-0000-4000-8000-000000000003');
set local role authenticated;
select pg_temp.permissao('GESTOR do tenant, TECNICO na empresa', null);
reset role;
select pg_temp.sistema();

set local role authenticated;
select pg_temp.permissao('sem sessao', false);
reset role;

-- =====================================================================================
-- 2. Busca
-- =====================================================================================
select pg_temp.como('1f000000-0000-4000-8000-000000000001');
set local role authenticated;
do $busca$
declare
  v_r jsonb := public.fiscal_item_similares(91001, null);
  v_ids integer[];
  v_zelio jsonb;
begin
  if v_r->'atual'->>'ncm' is not null or v_r->'atual'->>'origem' is not null then
    raise exception 'atual: devia vir sem NCM e origem no fiscal: %', v_r->'atual';
  end if;
  if v_r->'atual'->>'ncm_cadastro_antigo' is distinct from '85371020' or v_r->>'ncm_referencia' is distinct from '85371020' then
    raise exception 'atual: o NCM do cadastro antigo devia ser a referencia: %', v_r;
  end if;
  if (v_r->'palavras'->>0) is distinct from 'CLP' then
    raise exception 'a familia devia ser CLP: %', v_r->'palavras';
  end if;

  -- Mesmo NCM primeiro (CP1E, mesmo fabricante, antes do S7-1200), depois a familia.
  v_ids := pg_temp.ids(91001, null);
  if v_ids is distinct from array[91002, 91003, 91005] then
    raise exception 'ordem sem busca: esperava {91002,91003,91005}, veio %', v_ids;
  end if;
  if (v_r->'candidatos'->0->'motivos') is distinct from '["mesmo NCM", "palavras em comum: CLP, NPN", "mesmo fabricante"]'::jsonb then
    raise exception 'motivos do CP1E: %', v_r->'candidatos'->0->'motivos';
  end if;

  select c into v_zelio from jsonb_array_elements(v_r->'candidatos') c where (c->>'id')::integer = 91005;
  if (v_zelio->>'origem_copiavel')::boolean is distinct from false then
    raise exception 'origem 1 devia vir como nao copiavel: %', v_zelio;
  end if;

  if pg_temp.ids(91001, 'contator') is distinct from array[91004] then
    raise exception 'busca por nome: %', pg_temp.ids(91001, 'contator');
  end if;
  if pg_temp.ids(91001, 'sims71200') is distinct from array[91003] then
    raise exception 'busca por codigo: %', pg_temp.ids(91001, 'sims71200');
  end if;
  if pg_temp.ids(91001, '91005') is distinct from array[91005] then
    raise exception 'busca por id: %', pg_temp.ids(91001, '91005');
  end if;
  if pg_temp.ids(91001, 'clp') && array[91001, 91006, 91007, 91008, 91009, 91010] then
    raise exception 'a busca trouxe o proprio item, sem NCM, inativo ou de outra empresa: %', pg_temp.ids(91001, 'clp');
  end if;

  begin
    perform public.fiscal_item_similares(91009, null);
    raise exception 'buscou similar para item de outra empresa';
  exception when others then
    if sqlerrm <> 'Item #91009 nao encontrado nesta empresa.' then raise; end if;
  end;
end $busca$;

-- =====================================================================================
-- 3. Recusas, e nada gravado
-- =====================================================================================
select pg_temp.recusa(91001, 91002, array[]::text[], 'Marque ao menos um campo para copiar.', 'sem campos');
select pg_temp.recusa(91001, 91002, array['  '], 'Marque ao menos um campo para copiar.', 'campo em branco');
select pg_temp.recusa(91001, 91002, array['origem', 'ipi_codigo_enquadramento_legal'], 'O campo ipi_codigo_enquadramento_legal nao e copiado de similar.', 'cEnq');
select pg_temp.recusa(91001, 91002, array['numero_fci'], 'O campo numero_fci nao e copiado de similar.', 'FCI');
select pg_temp.recusa(91001, 91001, array['origem'], 'Escolha um similar diferente do proprio item.', 'o proprio item');
select pg_temp.recusa(91009, 91002, array['origem'], 'Item #91009 nao encontrado nesta empresa.', 'item de outra empresa');
select pg_temp.recusa(91001, 91008, array['origem'], 'Similar #91008 nao encontrado nesta empresa.', 'similar de outra empresa');
select pg_temp.recusa(91001, 91006, array['origem'], 'O similar #91006 nao tem cadastro fiscal completo (NCM e origem).', 'similar sem NCM');
select pg_temp.recusa(91001, 91010, array['origem'], 'O similar #91010 nao tem cadastro fiscal completo (NCM e origem).', 'similar sem linha fiscal');
select pg_temp.recusa(91001, 91002, array['origem', 'cest'], 'O similar #91002 nao tem cest para copiar.', 'similar sem CEST');
select pg_temp.recusa(91001, 91005, array['origem', 'ncm'],
  'A origem 1 do similar #91005 e de importacao propria: ela so vale com a equiparacao a industrial declarada no proprio item. Informe a origem no cadastro do item.',
  'origem 1');
reset role;
select pg_temp.sistema();

do $nada$
begin
  if exists (
    (select * from fiscal_antes except select fi.* from public.fiscal_itens fi where fi.item_id between 91001 and 91010)
    union all
    (select fi.* from public.fiscal_itens fi where fi.item_id between 91001 and 91010 except select * from fiscal_antes)
  ) then
    raise exception 'uma recusa gravou em fiscal_itens';
  end if;
end $nada$;

-- =====================================================================================
-- 4. Copia gravada
-- =====================================================================================
select pg_temp.como('1f000000-0000-4000-8000-000000000001');
set local role authenticated;
select public.fiscal_item_copiar_de_similar(91001, 91002, array['ORIGEM', 'ncm', 'cst_icms', 'aliq_icms', 'unidade_tributavel', 'ncm']);
-- NCM do cadastro antigo nao entra na conta: o fiscal e que vale; FCI do alvo fica.
select public.fiscal_item_copiar_de_similar(91010, 91003, array['origem', 'ncm', 'cest']);
reset role;
select pg_temp.sistema();

do $gravado$
declare
  v_fi public.fiscal_itens%rowtype;
  v_audit integer;
begin
  select * into v_fi from public.fiscal_itens where item_id = 91001;
  if row(v_fi.origem, v_fi.ncm, v_fi.cst_icms, v_fi.aliq_icms, v_fi.unidade_tributavel)
       is distinct from row(2::smallint, '85371020'::varchar, '00'::varchar, 17::numeric, 'UN'::text) then
    raise exception 'campos marcados gravados errado: %', to_jsonb(v_fi);
  end if;
  if v_fi.cest is not null or v_fi.cfop_padrao is not null or v_fi.cst_pis is not null or v_fi.cst_cofins is not null
     or v_fi.cst_ipi is not null or v_fi.aliq_ipi is not null or v_fi.aliq_pis is not null or v_fi.aliq_cofins is not null
     or v_fi.ipi_codigo_enquadramento_legal is not null or v_fi.equiparado_industrial then
    raise exception 'copiou campo que nao foi marcado: %', to_jsonb(v_fi);
  end if;
  if v_fi.fiscal_copiado_de_item_id is distinct from 91002
     or v_fi.fiscal_copiado_campos is distinct from array['aliq_icms', 'cst_icms', 'ncm', 'origem', 'unidade_tributavel']
     or v_fi.fiscal_copiado_em is null
     or v_fi.fiscal_copiado_por is distinct from '1f000000-0000-4000-8000-000000000001'::uuid then
    raise exception 'procedencia gravada errado: %', to_jsonb(v_fi);
  end if;

  select count(*) into v_audit
  from public.audit_log al
  where al.table_name = 'fiscal_itens' and al.action = 'UPDATE'
    and al.row_pk = v_fi.id::text
    and al.actor_user_id = '1f000000-0000-4000-8000-000000000001'
    and al.old_data->>'origem' is null and al.new_data->>'origem' = '2';
  if v_audit <> 1 then
    raise exception 'audit_log devia ter o antes e o depois da copia (achou %)', v_audit;
  end if;

  select * into v_fi from public.fiscal_itens where item_id = 91010;
  if not found
     or row(v_fi.origem, v_fi.ncm, v_fi.cest, v_fi.fiscal_copiado_de_item_id)
        is distinct from row(0::smallint, '85371020'::varchar, '1200100'::varchar, 91003) then
    raise exception 'item sem linha fiscal devia ganhar a linha com a copia: %', to_jsonb(v_fi);
  end if;

  -- O similar nao muda.
  if exists (select fi.* from public.fiscal_itens fi where fi.item_id in (91002, 91003)
             except select * from fiscal_antes) then
    raise exception 'a copia mexeu no similar';
  end if;

  raise notice 'OK: estrutura, permissao can(fiscal_itens, write), busca e ordem, recusas e copia gravada.';
end $gravado$;

rollback;
