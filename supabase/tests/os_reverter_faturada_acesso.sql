-- f.fn_os_reverter_faturada_sem_nota: checagem de acesso antes de qualquer leitura ou escrita
-- (migration 20260918110000). Usuario de outro tenant e recusado; o usuario certo passa e reverte;
-- o backend (sessao postgres sem JWT) passa. Roda inteiro numa transacao e termina em rollback.
--
-- Como rodar:
--   docker exec -i supabase_db_estoque-os psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f - < supabase/tests/os_reverter_faturada_acesso.sql

begin;

-- Tenant A (usuario ADMIN com acesso fiscal) e tenant B (sem usuario), cada um com uma OS faturada
-- sustentada por uma NF-e que foi cancelada.
insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('1e1b0000-0000-4000-8000-000000000010', 'authenticated', 'authenticated', 'reverter@example.test',
        '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Fiscal Reverter"}'::jsonb, now(), now());
insert into public.tenants (id, nome, ativo) values
  ('1e1b0000-0000-4000-8000-000000000001', 'Teste reverter A', true),
  ('1e1b0000-0000-4000-8000-00000000000b', 'Teste reverter B', true);
insert into c.tenant (id, codigo, nome) values
  ('1e1b0000-0000-4000-8000-000000000001', 'TESTE-REVERTER-A', 'Teste reverter A'),
  ('1e1b0000-0000-4000-8000-00000000000b', 'TESTE-REVERTER-B', 'Teste reverter B');
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj) values
  ('1e1b0000-0000-4000-8000-000000000002', '1e1b0000-0000-4000-8000-000000000001', 'REVERTER-A', 'EMPRESA REVERTER A LTDA', 'REVERTER A', '33333333000191'),
  ('1e1b0000-0000-4000-8000-00000000000c', '1e1b0000-0000-4000-8000-00000000000b', 'REVERTER-B', 'EMPRESA REVERTER B LTDA', 'REVERTER B', '44444444000191');
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, uf, cidade) values
  ('1e1b0000-0000-4000-8000-000000000002', '1e1b0000-0000-4000-8000-000000000001', '33333333000191', 'EMPRESA REVERTER A LTDA', 'REVERTER A', 'SC', 'JOINVILLE'),
  ('1e1b0000-0000-4000-8000-00000000000c', '1e1b0000-0000-4000-8000-00000000000b', '44444444000191', 'EMPRESA REVERTER B LTDA', 'REVERTER B', 'SC', 'JOINVILLE')
on conflict (id) do nothing;
insert into a.usuario (id, auth_user_id, nome, email, ativo) values
  ('1e1b0000-0000-4000-8000-000000000011', '1e1b0000-0000-4000-8000-000000000010', 'Fiscal Reverter', 'reverter@example.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo) values
  ('1e1b0000-0000-4000-8000-000000000011', '1e1b0000-0000-4000-8000-000000000001', 'ADMIN', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo) values
  ('1e1b0000-0000-4000-8000-000000000011', '1e1b0000-0000-4000-8000-000000000002', 'ADMIN', true);
insert into public.user_tenant_context (user_id, tenant_id) values
  ('1e1b0000-0000-4000-8000-000000000010', '1e1b0000-0000-4000-8000-000000000001');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id) values
  ('1e1b0000-0000-4000-8000-000000000010', '1e1b0000-0000-4000-8000-000000000001', '1e1b0000-0000-4000-8000-000000000002');

-- OS faturadas (uma por tenant) com NF-e de saida cancelada e nenhuma outra nota.
insert into public.ordens_servico (id, tenant_id, empresa_id, numero_os, os_num, codigo, cliente_nome, status, status_fluxo, faturado_em) values
  (919001, '1e1b0000-0000-4000-8000-000000000001', '1e1b0000-0000-4000-8000-000000000002', 'OS-919001', 919001, 'OS-919001', 'CLIENTE A', 'concluida', 'faturada', now()),
  (919002, '1e1b0000-0000-4000-8000-00000000000b', '1e1b0000-0000-4000-8000-00000000000c', 'OS-919002', 919002, 'OS-919002', 'CLIENTE B', 'concluida', 'faturada', now());
update public.ordens_servico set status_fluxo = 'faturada', status = 'concluida' where id in (919001, 919002);
alter table f.documento_fiscal disable trigger aaa_nfe_bloquear_documento_dml_direto;
alter table f.documento_fiscal disable trigger trg_documento_fiscal__reverter_os_faturada;
insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, emissao_date, competencia_date,
  valor_total, valor_produtos, valor_frete, valor_desconto, valor_outros, valor_seguro, valor_servicos, operacao, natureza, origem, os_id_import, nfe_status) values
  ('1e1b0000-0000-4000-8000-000000000301', '1e1b0000-0000-4000-8000-000000000001', '1e1b0000-0000-4000-8000-000000000002', repeat('3', 44), 'NFE', '2', '901', current_date, date_trunc('month', current_date)::date,
   100, 100, 0, 0, 0, 0, 0, 'SAIDA', 'PRODUTO', 'EMITIDO', 919001, 'CANCELADA'),
  ('1e1b0000-0000-4000-8000-000000000302', '1e1b0000-0000-4000-8000-00000000000b', '1e1b0000-0000-4000-8000-00000000000c', repeat('4', 44), 'NFE', '2', '902', current_date, date_trunc('month', current_date)::date,
   100, 100, 0, 0, 0, 0, 0, 'SAIDA', 'PRODUTO', 'EMITIDO', 919002, 'CANCELADA');

-- Sessao do usuario do tenant A.
select set_config('request.jwt.claim.sub', '1e1b0000-0000-4000-8000-000000000010', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"1e1b0000-0000-4000-8000-000000000010","role":"authenticated"}', true);
set local role authenticated;

do $test$
declare
  v_ok boolean;
begin
  -- 1. Tenant e empresa de outro (B): recusado antes de ler a OS.
  begin
    perform f.fn_os_reverter_faturada_sem_nota('1e1b0000-0000-4000-8000-00000000000b', '1e1b0000-0000-4000-8000-00000000000c', 919002);
    raise exception 'usuario do tenant A conseguiu chamar com o tenant B';
  exception when sqlstate '42501' then
    if sqlerrm not like 'Tenant e empresa informados nao pertencem a sessao do usuario.%' then raise; end if;
  end;
  if (select status_fluxo from public.ordens_servico where id = 919002) <> 'faturada' then
    raise exception 'a OS do tenant B foi alterada por usuario de outro tenant';
  end if;

  -- 2. Tenant certo com empresa errada: recusado.
  begin
    perform f.fn_os_reverter_faturada_sem_nota('1e1b0000-0000-4000-8000-000000000001', '1e1b0000-0000-4000-8000-00000000000c', 919001);
    raise exception 'empresa de outro tenant foi aceita';
  exception when sqlstate '42501' then null;
  end;

  -- 3. Usuario certo, tenant e empresa da sessao: passa e reverte.
  v_ok := f.fn_os_reverter_faturada_sem_nota('1e1b0000-0000-4000-8000-000000000001', '1e1b0000-0000-4000-8000-000000000002', 919001);
  if v_ok is not true then
    raise exception 'usuario certo nao reverteu a OS faturada sem nota';
  end if;
  if (select status_fluxo from public.ordens_servico where id = 919001) <> 'concluida'
     or (select status::text from public.ordens_servico where id = 919001) <> 'concluida'
     or (select faturado_em from public.ordens_servico where id = 919001) is not null then
    raise exception 'OS 919001 nao voltou para concluida: %', (select row_to_json(o) from public.ordens_servico o where o.id = 919001);
  end if;
  if not exists (
    select 1 from public.ordens_servico_fluxo_eventos e
    where e.os_id = 919001 and e.evento = 'reverter_faturada' and e.realizado_por = '1e1b0000-0000-4000-8000-000000000010'
  ) then
    raise exception 'evento de reversao nao registrou o usuario';
  end if;

  -- 4. OS ja revertida: nada a fazer (false), sem erro.
  if f.fn_os_reverter_faturada_sem_nota('1e1b0000-0000-4000-8000-000000000001', '1e1b0000-0000-4000-8000-000000000002', 919001) then
    raise exception 'OS ja concluida foi revertida de novo';
  end if;
end;
$test$;

-- Sessao anonima (JWT sem usuario): recusada.
reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
do $test$
begin
  begin
    perform f.fn_os_reverter_faturada_sem_nota('1e1b0000-0000-4000-8000-00000000000b', '1e1b0000-0000-4000-8000-00000000000c', 919002);
    raise exception 'sessao anonima conseguiu chamar';
  exception when sqlstate '42501' then null;
  end;
end;
$test$;

-- Backend (sessao postgres sem JWT, como migration/gatilho da finalizacao): passa.
reset role;
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claims', '', true);
do $test$
begin
  if f.fn_os_reverter_faturada_sem_nota('1e1b0000-0000-4000-8000-00000000000b', '1e1b0000-0000-4000-8000-00000000000c', 919002) is not true then
    raise exception 'backend nao reverteu a OS do tenant B';
  end if;
  if (select status_fluxo from public.ordens_servico where id = 919002) <> 'concluida' then
    raise exception 'OS 919002 nao voltou para concluida pelo backend';
  end if;
  raise notice 'os_reverter_faturada_acesso: recusas (tenant/empresa de outro, anonimo) e passagens (usuario certo, backend) ok';
end;
$test$;

rollback;
