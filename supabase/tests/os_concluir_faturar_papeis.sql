\set ON_ERROR_STOP on

-- Quem fatura fecha a OS: FATURAMENTO e FINANCEIRO concluem a OS (os_concluir) e
-- passam da checagem de papel em os_faturar; TECNICO continua barrado nos dois.

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('18000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'faturamento@example.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Faturamento"}'::jsonb, now(), now()),
  ('18000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'financeiro@example.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Financeiro"}'::jsonb, now(), now()),
  ('18000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'tecnico@example.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Tecnico"}'::jsonb, now(), now());

insert into public.tenants (id, nome, ativo) values ('18000000-0000-4000-8000-000000000010', 'Tenant papeis OS', true);
insert into c.tenant (id, codigo, nome, ativo) values ('18000000-0000-4000-8000-000000000010', 'PAPEIS-OS', 'Tenant papeis OS', true);
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo)
values ('18000000-0000-4000-8000-000000000020', '18000000-0000-4000-8000-000000000010', 'PAP-A', 'Empresa papeis', 'Empresa papeis', '18000000000100', true);
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo)
values ('18000000-0000-4000-8000-000000000020', '18000000-0000-4000-8000-000000000010', '18000000000100', 'Empresa papeis', 'Empresa papeis', true);

insert into a.usuario (id, auth_user_id, nome, email, ativo) values
  ('18000000-0000-4000-8000-000000000041', '18000000-0000-4000-8000-000000000001', 'Faturamento', 'faturamento@example.test', true),
  ('18000000-0000-4000-8000-000000000042', '18000000-0000-4000-8000-000000000002', 'Financeiro', 'financeiro@example.test', true),
  ('18000000-0000-4000-8000-000000000043', '18000000-0000-4000-8000-000000000003', 'Tecnico', 'tecnico@example.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo) values
  ('18000000-0000-4000-8000-000000000041', '18000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('18000000-0000-4000-8000-000000000042', '18000000-0000-4000-8000-000000000010', 'GESTOR', true),
  ('18000000-0000-4000-8000-000000000043', '18000000-0000-4000-8000-000000000010', 'GESTOR', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo) values
  ('18000000-0000-4000-8000-000000000041', '18000000-0000-4000-8000-000000000020', 'FATURAMENTO', true),
  ('18000000-0000-4000-8000-000000000042', '18000000-0000-4000-8000-000000000020', 'FINANCEIRO', true),
  ('18000000-0000-4000-8000-000000000043', '18000000-0000-4000-8000-000000000020', 'TECNICO', true);
insert into public.user_tenant_context (user_id, tenant_id) values
  ('18000000-0000-4000-8000-000000000001', '18000000-0000-4000-8000-000000000010'),
  ('18000000-0000-4000-8000-000000000002', '18000000-0000-4000-8000-000000000010'),
  ('18000000-0000-4000-8000-000000000003', '18000000-0000-4000-8000-000000000010');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id) values
  ('18000000-0000-4000-8000-000000000001', '18000000-0000-4000-8000-000000000010', '18000000-0000-4000-8000-000000000020'),
  ('18000000-0000-4000-8000-000000000002', '18000000-0000-4000-8000-000000000010', '18000000-0000-4000-8000-000000000020'),
  ('18000000-0000-4000-8000-000000000003', '18000000-0000-4000-8000-000000000010', '18000000-0000-4000-8000-000000000020');

insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social)
values (918001, '18000000-0000-4000-8000-000000000010', '18000000-0000-4000-8000-000000000020', 'CLIENTE PAPEIS', '18111111000191', 'CLIENTE PAPEIS LTDA');

insert into public.ordens_servico (id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id, empresa_id,
  status_fluxo, tipo_documento, codigo, numero_doc, descricao_servico, orcado)
values
  (918001, 'PAP-1', 'CLIENTE PAPEIS', 918001, 'em_andamento', 918001, '18000000-0000-4000-8000-000000000010', '18000000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-PAP-001', 1, 'OS do faturamento', 100),
  (918002, 'PAP-2', 'CLIENTE PAPEIS', 918001, 'em_andamento', 918002, '18000000-0000-4000-8000-000000000010', '18000000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-PAP-002', 1, 'OS do financeiro', 100),
  (918003, 'PAP-3', 'CLIENTE PAPEIS', 918001, 'em_andamento', 918003, '18000000-0000-4000-8000-000000000010', '18000000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-PAP-003', 1, 'OS do tecnico', 100);

-- TECNICO: barrado em ambos.
select set_config('request.jwt.claim.sub', '18000000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"18000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;
do $tecnico$
begin
  begin
    perform public.os_concluir(918003);
    raise exception 'TECNICO concluiu a OS.';
  exception when others then
    if sqlerrm not like 'Somente%' then raise; end if;
  end;
  begin
    perform public.os_faturar(918003);
    raise exception 'TECNICO passou da checagem de papel em os_faturar.';
  exception when others then
    if sqlerrm not like 'Somente%' then raise; end if;
  end;
end;
$tecnico$;
reset role;

-- FATURAMENTO: conclui; em os_faturar passa do papel e para na regra seguinte (nota + saldo).
select set_config('request.jwt.claim.sub', '18000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"18000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
do $faturamento$
declare v_fluxo text;
begin
  perform public.os_concluir(918001);
  select status_fluxo into v_fluxo from public.ordens_servico where id = 918001;
  if v_fluxo <> 'concluida' then raise exception 'FATURAMENTO nao concluiu a OS (status %).', v_fluxo; end if;
  begin
    perform public.os_faturar(918001);
    raise exception 'os_faturar aceitou OS sem nota vinculada.';
  exception when others then
    if sqlerrm like 'Somente%' then raise exception 'FATURAMENTO barrado no papel de os_faturar: %', sqlerrm; end if;
    if sqlerrm not like 'A OS só pode ser marcada como faturada%' then raise; end if;
  end;
end;
$faturamento$;
reset role;

-- FINANCEIRO: tambem conclui (antes so faturava).
select set_config('request.jwt.claim.sub', '18000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"18000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;
do $financeiro$
declare v_fluxo text;
begin
  perform public.os_concluir(918002);
  select status_fluxo into v_fluxo from public.ordens_servico where id = 918002;
  if v_fluxo <> 'concluida' then raise exception 'FINANCEIRO nao concluiu a OS (status %).', v_fluxo; end if;
end;
$financeiro$;
reset role;

rollback;
