\set ON_ERROR_STOP on

-- Lista de e-mails do cliente na entrega da NF-e
-- (supabase/migrations/20260919040000_cliente_emails_nfe.sql).
--
-- Blocos:
--   1  lista vazia quando o cliente ainda nao tem contato com e-mail
--   2  registrar cadastra o que faltava: e-mail em minusculas, nome pela parte antes do @,
--      setor NF-E, vezes_usado 1
--   3  registrar de novo soma o uso, nao duplica e a lista vem do mais recente para o mais antigo
--   4  e-mail invalido, vazio e nulo sao ignorados; maiusculas e espacos nao criam duplicata
--   5  contato que veio do orcamento mantem nome e setor; so o uso e atualizado
--   6  cliente de outra empresa e cliente inexistente: erro, e nada gravado
--
-- Tenant 1e140000-...-0001, empresa ...0002; usuario fiscal ...0010/0011.

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('1e140000-0000-4000-8000-000000000010', 'authenticated', 'authenticated', 'emails-nfe@example.test',
  '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Fiscal Emails"}'::jsonb, now(), now());

insert into public.tenants (id, nome, ativo) values ('1e140000-0000-4000-8000-000000000001', 'Teste emails NF-e', true);
insert into c.tenant (id, codigo, nome) values ('1e140000-0000-4000-8000-000000000001', 'TESTE-EMAILS', 'Teste emails NF-e');
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj)
values ('1e140000-0000-4000-8000-000000000002', '1e140000-0000-4000-8000-000000000001', 'EMAILS', 'EMPRESA EMAILS LTDA', 'EMAILS', '44444444000191');
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, uf, cidade)
values ('1e140000-0000-4000-8000-000000000002', '1e140000-0000-4000-8000-000000000001', '44444444000191', 'EMPRESA EMAILS LTDA', 'EMAILS', 'SC', 'JOINVILLE')
on conflict (id) do nothing;

insert into a.usuario (id, auth_user_id, nome, email, ativo)
values ('1e140000-0000-4000-8000-000000000011', '1e140000-0000-4000-8000-000000000010', 'Fiscal Emails', 'emails-nfe@example.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo)
values ('1e140000-0000-4000-8000-000000000011', '1e140000-0000-4000-8000-000000000001', 'ADMIN', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo)
values ('1e140000-0000-4000-8000-000000000011', '1e140000-0000-4000-8000-000000000002', 'DIRETOR', true);
insert into public.user_tenant_context (user_id, tenant_id)
values ('1e140000-0000-4000-8000-000000000010', '1e140000-0000-4000-8000-000000000001');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
values ('1e140000-0000-4000-8000-000000000010', '1e140000-0000-4000-8000-000000000001', '1e140000-0000-4000-8000-000000000002');

-- Uma segunda empresa, para o bloco 6.
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj)
values ('1e140000-0000-4000-8000-000000000003', '1e140000-0000-4000-8000-000000000001', 'EMAILS2', 'EMPRESA EMAILS 2 LTDA', 'EMAILS2', '44444444000272');
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, uf, cidade)
values ('1e140000-0000-4000-8000-000000000003', '1e140000-0000-4000-8000-000000000001', '44444444000272', 'EMPRESA EMAILS 2 LTDA', 'EMAILS2', 'SC', 'JOINVILLE')
on conflict (id) do nothing;

insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social, uf, indicador_ie)
values
  (914001, '1e140000-0000-4000-8000-000000000001', '1e140000-0000-4000-8000-000000000002', 'PORTOBELLO SA', '83475913000191', 'PBG S/A', 'SC', '1'),
  (914002, '1e140000-0000-4000-8000-000000000001', '1e140000-0000-4000-8000-000000000003', 'CLIENTE DE OUTRA EMPRESA', '11222333000181', 'OUTRA LTDA', 'SC', '1');

-- Contato vindo do orcamento: nome e setor de verdade, ainda sem uso na NF-e.
insert into public.cliente_contatos (tenant_id, empresa_id, cliente_id, nome, setor, email, telefone, ativo, principal, vezes_usado, ultimo_uso_em)
values ('1e140000-0000-4000-8000-000000000001', '1e140000-0000-4000-8000-000000000002', 914001,
        'MARIANA COMPRAS', 'COMPRAS', 'mariana@portobello.com.br', '(48) 3279-2222', true, false, 3, now() - interval '10 days');

-- Cliente sem nenhum contato, para o bloco 1.
insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social, uf, indicador_ie)
values (914003, '1e140000-0000-4000-8000-000000000001', '1e140000-0000-4000-8000-000000000002', 'CLIENTE SEM CONTATO', '22333444000181', 'SEM CONTATO LTDA', 'SC', '1');

-- A partir daqui, como a pessoa logada.
select set_config('request.jwt.claim.sub', '1e140000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claims', '{"sub":"1e140000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;

-- 1. Lista vazia --------------------------------------------------------------------------------
do $b1$
begin
  if public.clientes_emails_nfe(914003) <> '[]'::jsonb then
    raise exception 'cliente sem contato devia devolver lista vazia: %', public.clientes_emails_nfe(914003);
  end if;
end;
$b1$;

-- 2. Registrar cadastra o que faltava -----------------------------------------------------------
do $b2$
declare
  v_lista jsonb;
  v_ct public.cliente_contatos%rowtype;
begin
  v_lista := public.clientes_registrar_emails_nfe(914001, array['Financeiro@Portobello.com.br ', 'nfe@portobello.com.br']);
  if jsonb_array_length(v_lista) <> 3 then
    raise exception 'esperava 3 e-mails na lista, veio %: %', jsonb_array_length(v_lista), v_lista;
  end if;
  select * into v_ct from public.cliente_contatos
   where cliente_id = 914001 and email = 'financeiro@portobello.com.br';
  if v_ct.id is null then raise exception 'e-mail novo nao foi cadastrado'; end if;
  if v_ct.nome <> 'FINANCEIRO' or v_ct.setor <> 'NF-E' or v_ct.vezes_usado <> 1
     or v_ct.ultimo_uso_em is null or not v_ct.ativo then
    raise exception 'contato novo gravado errado: % % % % %', v_ct.nome, v_ct.setor, v_ct.vezes_usado, v_ct.ultimo_uso_em, v_ct.ativo;
  end if;
end;
$b2$;

-- 3. Registrar de novo soma o uso e ordena pelo mais recente -------------------------------------
do $b3$
declare
  v_lista jsonb;
  v_ct public.cliente_contatos%rowtype;
begin
  v_lista := public.clientes_registrar_emails_nfe(914001, array['nfe@portobello.com.br', 'compras@portobello.com.br']);
  if jsonb_array_length(v_lista) <> 4 then
    raise exception 'esperava 4 e-mails, veio %: %', jsonb_array_length(v_lista), v_lista;
  end if;
  select * into v_ct from public.cliente_contatos where cliente_id = 914001 and email = 'nfe@portobello.com.br';
  if v_ct.vezes_usado <> 2 then raise exception 'uso repetido nao somou: %', v_ct.vezes_usado; end if;
  -- Ordem: quem foi usado por ultimo vem primeiro; o contato antigo do orcamento fica por ultimo.
  if v_lista->3->>'email' <> 'mariana@portobello.com.br' then
    raise exception 'ordem da lista errada: %', v_lista;
  end if;
  if (select count(*) from public.cliente_contatos where cliente_id = 914001) <> 4 then
    raise exception 'numero de contatos do cliente mudou alem do esperado';
  end if;
end;
$b3$;

-- 4. Entrada invalida e duplicidade --------------------------------------------------------------
do $b4$
declare
  v_lista jsonb;
begin
  v_lista := public.clientes_registrar_emails_nfe(914001, array['sem-arroba', '  ', null, 'NFE@PORTOBELLO.COM.BR']);
  if jsonb_array_length(v_lista) <> 4 then
    raise exception 'e-mail invalido ou duplicado entrou na lista: %', v_lista;
  end if;
  if (select vezes_usado from public.cliente_contatos where cliente_id = 914001 and email = 'nfe@portobello.com.br') <> 3 then
    raise exception 'e-mail em maiusculas devia somar no mesmo contato';
  end if;
  -- Lista vazia nao quebra.
  if jsonb_array_length(public.clientes_registrar_emails_nfe(914001, array[]::text[])) <> 4 then
    raise exception 'chamada sem e-mails devia so devolver a lista';
  end if;
end;
$b4$;

-- 5. Contato do orcamento mantem nome e setor ----------------------------------------------------
do $b5$
declare
  v_ct public.cliente_contatos%rowtype;
begin
  perform public.clientes_registrar_emails_nfe(914001, array['mariana@portobello.com.br']);
  select * into v_ct from public.cliente_contatos where cliente_id = 914001 and email = 'mariana@portobello.com.br';
  if v_ct.nome <> 'MARIANA COMPRAS' or v_ct.setor <> 'COMPRAS' then
    raise exception 'o registro da NF-e nao pode renomear o contato: % / %', v_ct.nome, v_ct.setor;
  end if;
  if v_ct.vezes_usado <> 4 or v_ct.ultimo_uso_em < now() - interval '1 minute' then
    raise exception 'uso do contato do orcamento nao foi atualizado: % %', v_ct.vezes_usado, v_ct.ultimo_uso_em;
  end if;
  -- Agora ele e o mais recente e passa a ser o primeiro da lista.
  if public.clientes_emails_nfe(914001)->0->>'email' <> 'mariana@portobello.com.br' then
    raise exception 'o mais recente devia abrir a lista: %', public.clientes_emails_nfe(914001);
  end if;
end;
$b5$;

-- 6. Cliente de outra empresa e inexistente ------------------------------------------------------
do $b6$
declare
  v_antes bigint := (select count(*) from public.cliente_contatos);
begin
  begin
    perform public.clientes_emails_nfe(914002);
    raise exception 'leu contatos de cliente de outra empresa';
  exception when no_data_found then null;
  end;
  begin
    perform public.clientes_registrar_emails_nfe(914002, array['a@b.com.br']);
    raise exception 'gravou contato em cliente de outra empresa';
  exception when no_data_found then null;
  end;
  begin
    perform public.clientes_emails_nfe(999999);
    raise exception 'leu contatos de cliente inexistente';
  exception when no_data_found then null;
  end;
  begin
    perform public.clientes_emails_nfe(null);
    raise exception 'aceitou cliente nulo';
  exception when invalid_parameter_value then null;
  end;
  if (select count(*) from public.cliente_contatos) <> v_antes then
    raise exception 'recusa gravou contato';
  end if;
end;
$b6$;

rollback;
