\set ON_ERROR_STOP on

-- Regressao de movimentacoes: termos antes de LIMIT, relacionamentos e RLS,
-- normalizacao de acento/decimal e isolamento por tenant/empresa.
-- Fixtures totalmente transacionais; nenhum saldo/cadastro persiste.
begin;

create function pg_temp.assert_busca(p_ok boolean, p_mensagem text)
returns void language plpgsql as $$
begin
  if p_ok is distinct from true then raise exception '%', p_mensagem; end if;
end;
$$;
grant execute on function pg_temp.assert_busca(boolean, text) to authenticated;

select pg_temp.assert_busca(public.fn_item_busca_normalizar(E'  CaBo\tFLEXÍVEL 1,5mm²\nAZUL ') = 'CABO FLEXIVEL 1.5MM² AZUL', 'Normalizacao de acento, espacos e decimal');
select pg_temp.assert_busca(public.fn_item_busca_corresponde('CABO FLEXÍVEL COBRE 1,5MM² AZUL', '1.5 cabo azul'), 'Termos fora de ordem e separados');
select pg_temp.assert_busca(public.fn_item_busca_corresponde('CABO FLEXIVEL 1.5MM²', 'cabo 1,5'), 'Decimal ponto no cadastro e virgula na busca');
select pg_temp.assert_busca(not public.fn_item_busca_corresponde('CABO FLEXIVEL 2,5MM²', 'cabo 1,5'), 'Todos os termos sao obrigatorios');
select pg_temp.assert_busca(not public.fn_item_busca_corresponde('CABO 1,5MM²', 'cabo %'), 'Percentual nao pode virar curinga');
select pg_temp.assert_busca(not public.fn_item_busca_corresponde('CABO 1,5MM²', 'cabo _'), 'Sublinhado nao pode virar curinga');
select pg_temp.assert_busca(public.fn_item_busca_corresponde(null, E' \t\n'), 'Busca vazia nao restringe');
select pg_temp.assert_busca(not public.fn_item_busca_corresponde(null, 'cabo'), 'Texto nulo nao corresponde a palavra');

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('27110000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'busca-mov@example.test', '{"provider":"email","providers":["email"]}', '{"nome":"Teste busca item"}', now(), now());
insert into public.tenants (id, nome, ativo) values
  ('27110000-0000-4000-8000-000000000010', 'Tenant busca', true),
  ('27110000-0000-4000-8000-000000000011', 'Outro tenant busca', true);
insert into c.tenant (id, codigo, nome, ativo) values
  ('27110000-0000-4000-8000-000000000010', 'BUSCA-TESTE', 'Tenant busca', true),
  ('27110000-0000-4000-8000-000000000011', 'BUSCA-OUTRO', 'Outro tenant busca', true);
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo) values
  ('27110000-0000-4000-8000-000000000020', '27110000-0000-4000-8000-000000000010', 'BUSCA-A', 'Empresa busca A', 'Empresa busca A', '27110000000100', true),
  ('27110000-0000-4000-8000-000000000021', '27110000-0000-4000-8000-000000000010', 'BUSCA-B', 'Empresa busca B', 'Empresa busca B', '27110000000200', true),
  ('27110000-0000-4000-8000-000000000022', '27110000-0000-4000-8000-000000000011', 'BUSCA-C', 'Empresa busca C', 'Empresa busca C', '27110000000300', true);
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo) values
  ('27110000-0000-4000-8000-000000000020', '27110000-0000-4000-8000-000000000010', '27110000000100', 'Empresa busca A', 'Empresa busca A', true),
  ('27110000-0000-4000-8000-000000000021', '27110000-0000-4000-8000-000000000010', '27110000000200', 'Empresa busca B', 'Empresa busca B', true),
  ('27110000-0000-4000-8000-000000000022', '27110000-0000-4000-8000-000000000011', '27110000000300', 'Empresa busca C', 'Empresa busca C', true);
insert into a.usuario (id, auth_user_id, nome, email, ativo)
values ('27110000-0000-4000-8000-000000000040', '27110000-0000-4000-8000-000000000001', 'Teste busca', 'busca-mov@example.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo)
values ('27110000-0000-4000-8000-000000000040', '27110000-0000-4000-8000-000000000010', 'ADMIN', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo)
values ('27110000-0000-4000-8000-000000000040', '27110000-0000-4000-8000-000000000020', 'DIRETOR', true);
insert into public.user_tenant_context (user_id, tenant_id)
values ('27110000-0000-4000-8000-000000000001', '27110000-0000-4000-8000-000000000010');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
values ('27110000-0000-4000-8000-000000000001', '27110000-0000-4000-8000-000000000010', '27110000-0000-4000-8000-000000000020');


insert into public.fornecedores (id, tenant_id, empresa_id, nome)
values (928001, '27110000-0000-4000-8000-000000000010', '27110000-0000-4000-8000-000000000020', 'ELETRICA BRASIL COMERCIO');
insert into public.itens (id,tenant_id,empresa_id,codigo_interno,nome,tipo,finalidade,controla_estoque) values
(928001,'27110000-0000-4000-8000-000000000010','27110000-0000-4000-8000-000000000020','CB-1.5','CABO FLEXÍVEL COBRE 1,5MM² AZUL','produto','revenda',true),
(928002,'27110000-0000-4000-8000-000000000010','27110000-0000-4000-8000-000000000020','DECOY','CONTROLADOR 400V','produto','revenda',true),
(928003,'27110000-0000-4000-8000-000000000010','27110000-0000-4000-8000-000000000021','ALIEN-EMPRESA','CABO FLEXÍVEL COBRE 1,5MM² AZUL','produto','revenda',true),
(928004,'27110000-0000-4000-8000-000000000011','27110000-0000-4000-8000-000000000022','ALIEN-TENANT','CABO FLEXÍVEL COBRE 1,5MM² AZUL','produto','revenda',true);
insert into public.nf_entrada (id,tenant_id,empresa_id,chave,numero,fornecedor_id)
values (928001,'27110000-0000-4000-8000-000000000010','27110000-0000-4000-8000-000000000020','92800100000000000000000000000000000000000000','7332',928001);
insert into public.ordens_servico (id,tenant_id,empresa_id,numero_os,os_num,codigo,cliente_nome,descricao_servico)
values (928001,'27110000-0000-4000-8000-000000000010','27110000-0000-4000-8000-000000000020','OS-COMERCIAL-731',731,'OS-COMERCIAL-731','CLIENTE CERÂMICO','MANUTENÇÃO DE FORNO');
insert into public.movimentacoes (id,item_id,tenant_id,empresa_id,tipo,quantidade,motivo,origem_os_id,origem_nf_entrada_id)
values (928001,928001,'27110000-0000-4000-8000-000000000010','27110000-0000-4000-8000-000000000020','entrada',1,'Importação XML [OS 928001]',928001,928001);
insert into public.movimentacoes (id,item_id,tenant_id,empresa_id,tipo,quantidade,motivo)
select 928100+n,928002,'27110000-0000-4000-8000-000000000010','27110000-0000-4000-8000-000000000020','entrada',1,'Movimento recente'
from generate_series(1,1005) n;
insert into public.movimentacoes (id,item_id,tenant_id,empresa_id,tipo,quantidade,motivo) values
(930001,928003,'27110000-0000-4000-8000-000000000010','27110000-0000-4000-8000-000000000021','entrada',1,'Outra empresa'),
(930002,928004,'27110000-0000-4000-8000-000000000011','27110000-0000-4000-8000-000000000022','entrada',1,'Outro tenant');
select set_config('request.jwt.claim.sub','27110000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"27110000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $test$
declare
 t constant uuid:='27110000-0000-4000-8000-000000000010';
 e constant uuid:='27110000-0000-4000-8000-000000000020';
 v_ids integer[];
 v_count integer;
begin
 perform pg_temp.assert_busca(public.current_tenant_id()=t and public.current_empresa_id()=e,'Contexto fixture');
 select array_agg(id) into v_ids from public.movimentacoes_buscar(t,e,'cabo 1,5');
 perform pg_temp.assert_busca(v_ids=array[928001],'Item antigo encontrado depois de mais de1000 movimentos recentes; escopo empresa/tenant');
 select array_agg(id) into v_ids from public.movimentacoes_buscar(t,e,'AZUL 1.5 flexivel');
 perform pg_temp.assert_busca(v_ids=array[928001],'Ordem invertida, acento e decimal');
 select array_agg(id) into v_ids from public.movimentacoes_buscar(t,e,'comercio eletrica');
 perform pg_temp.assert_busca(v_ids=array[928001],'Fornecedor preservado');
 select array_agg(id) into v_ids from public.movimentacoes_buscar(t,e,'COMERCIAL-731 importacao');
 perform pg_temp.assert_busca(v_ids=array[928001],'Motivo com OS comercial');
 select array_agg(id) into v_ids from public.movimentacoes_buscar(t,e,'ceramico manutencao');
 perform pg_temp.assert_busca(v_ids=array[928001],'Cliente e descricao da OS');
 select count(*) into v_count from public.movimentacoes_buscar(t,e,'cabo 2,5');
 perform pg_temp.assert_busca(v_count=0,'Todos termos sao obrigatorios');
 select count(*) into v_count from public.movimentacoes_buscar(t,e,'controlador',5000);
 perform pg_temp.assert_busca(v_count=1000,'Limite maximo');
 select count(*) into v_count from public.movimentacoes_buscar(t,e,'controlador',3);
 perform pg_temp.assert_busca(v_count=3,'Limite solicitado');
 select count(*) into v_count from public.movimentacoes_buscar(t,'27110000-0000-4000-8000-000000000021','cabo');
 perform pg_temp.assert_busca(v_count=0,'Empresa divergente bloqueada');
 select count(*) into v_count from public.movimentacoes_buscar('27110000-0000-4000-8000-000000000011','27110000-0000-4000-8000-000000000022','cabo');
 perform pg_temp.assert_busca(v_count=0,'Tenant divergente bloqueado');
end;
$test$;
reset role;

-- A otimizacao das politicas deve manter o gate de acesso ativo da empresa.
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);
update a.usuario_empresa
set ativo = false
where usuario_id = '27110000-0000-4000-8000-000000000040'
  and empresa_id = '27110000-0000-4000-8000-000000000020';
select set_config('request.jwt.claim.sub', '27110000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"27110000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select pg_temp.assert_busca(
  (select count(*) from public.movimentacoes_buscar(
    '27110000-0000-4000-8000-000000000010',
    '27110000-0000-4000-8000-000000000020', 'cabo 1,5'
  )) = 0,
  'Usuario sem acesso ativo a empresa nao consulta movimentos'
);
select pg_temp.assert_busca(
  (select count(*) from public.movimentacoes
   where tenant_id = '27110000-0000-4000-8000-000000000010'
     and empresa_id = '27110000-0000-4000-8000-000000000020') = 0,
  'Politica de movimentacoes continua bloqueando acesso direto sem vinculo ativo'
);
reset role;
rollback;
