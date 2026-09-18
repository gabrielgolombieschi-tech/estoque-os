\set ON_ERROR_STOP on

-- "Importado por nos" na tela fiscal do item (20260918210000): marca origem 1, equiparacao a
-- industrial e IPI 50 com a aliquota da TIPI; exige DIR/DI e nota de entrada; grava quem e
-- quando; recusa quem nao edita o fiscal, NCM sem TIPI e nota de entrada de outra DIR.
--
-- Contas do fixture:
--   ...0001  diretor@ipn.test   DIRETOR  -> edita o fiscal
--   ...0002  tecnico@ipn.test   TECNICO  -> nao edita
-- Itens: 1 (NCM 85371020, na TIPI a 9,75%), 2 (NCM 99999999, fora da TIPI).

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('1b000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'diretor@ipn.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Diretor"}'::jsonb, now(), now()),
  ('1b000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'tecnico@ipn.test', '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Tecnico"}'::jsonb, now(), now());

insert into public.tenants (id, nome, ativo) values ('1b000000-0000-4000-8000-000000000010', 'Tenant IPN', true);
insert into c.tenant (id, codigo, nome, ativo) values ('1b000000-0000-4000-8000-000000000010', 'IPN', 'Tenant IPN', true);
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo)
values ('1b000000-0000-4000-8000-000000000020', '1b000000-0000-4000-8000-000000000010', 'IPN-A', 'Empresa IPN', 'Empresa IPN', '19310000000100', true);
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo)
values ('1b000000-0000-4000-8000-000000000020', '1b000000-0000-4000-8000-000000000010', '19310000000100', 'Empresa IPN', 'Empresa IPN', true);

insert into a.usuario (id, auth_user_id, nome, email, ativo) values
  ('1b000000-0000-4000-8000-000000000041', '1b000000-0000-4000-8000-000000000001', 'Diretor', 'diretor@ipn.test', true),
  ('1b000000-0000-4000-8000-000000000042', '1b000000-0000-4000-8000-000000000002', 'Tecnico', 'tecnico@ipn.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo) values
  ('1b000000-0000-4000-8000-000000000041', '1b000000-0000-4000-8000-000000000010', 'ADMIN', true),
  ('1b000000-0000-4000-8000-000000000042', '1b000000-0000-4000-8000-000000000010', 'GESTOR', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo) values
  ('1b000000-0000-4000-8000-000000000041', '1b000000-0000-4000-8000-000000000020', 'DIRETOR', true),
  ('1b000000-0000-4000-8000-000000000042', '1b000000-0000-4000-8000-000000000020', 'TECNICO', true);
insert into public.user_tenant_context (user_id, tenant_id) values
  ('1b000000-0000-4000-8000-000000000001', '1b000000-0000-4000-8000-000000000010'),
  ('1b000000-0000-4000-8000-000000000002', '1b000000-0000-4000-8000-000000000010');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id) values
  ('1b000000-0000-4000-8000-000000000001', '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020'),
  ('1b000000-0000-4000-8000-000000000002', '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020');

insert into public.itens (id, codigo_interno, nome, tipo, unidade_medida, ativo, tenant_id, empresa_id, finalidade)
values
  (9310001, 'IPN-CPU', 'CPU DE CLP IMPORTADA', 'produto', 'UN', true, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', 'materia_prima'),
  (9310002, 'IPN-SEM-TIPI', 'ITEM SEM TIPI', 'produto', 'UN', true, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', 'materia_prima');
-- O cadastro do item ja cria a linha fiscal por gatilho; aqui so os campos do teste.
insert into public.fiscal_itens (item_id, tenant_id, empresa_id, ncm, origem, cst_ipi, unidade_tributavel)
values
  (9310001, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', '85371020', 2, '53', 'UN'),
  (9310002, '1b000000-0000-4000-8000-000000000010', '1b000000-0000-4000-8000-000000000020', '99999999', 2, '53', 'UN')
on conflict (item_id) do update
  set ncm = excluded.ncm, origem = excluded.origem, cst_ipi = excluded.cst_ipi, unidade_tributavel = excluded.unidade_tributavel;
insert into f.tipi_ncm (ncm, aliquota, descricao, fonte)
values ('85371020', 9.75, 'Controladores programaveis (teste)', 'teste fiscal_item_importado_por_nos')
on conflict (ncm) do nothing;

create or replace function pg_temp.como(p_sub text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_sub, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', p_sub), true);
end $$;

-- 1. Tecnico nao edita o fiscal. ------------------------------------------------------------------
select pg_temp.como('1b000000-0000-4000-8000-000000000002');
set local role authenticated;
do $tecnico$
begin
  begin
    perform public.web_fiscal_item_marcar_importado_por_nos(9310001, '260191366846', '2/24');
    raise exception 'tecnico marcou importacao';
  exception
    when insufficient_privilege then null;
  end;
end $tecnico$;
reset role;

-- 2. Diretor: validacoes e marcacao. ------------------------------------------------------------------
select pg_temp.como('1b000000-0000-4000-8000-000000000001');
set local role authenticated;
do $diretor$
declare
  r jsonb;
  v_fi public.fiscal_itens%rowtype;
begin
  -- DIR invalida.
  begin
    perform public.web_fiscal_item_marcar_importado_por_nos(9310001, '12', '2/24');
    raise exception 'DIR curta aceita';
  exception when invalid_parameter_value then null;
  end;
  -- Sem nota de entrada.
  begin
    perform public.web_fiscal_item_marcar_importado_por_nos(9310001, '260191366846', '  ');
    raise exception 'sem nota aceita';
  exception when invalid_parameter_value then null;
  end;
  -- NCM fora da TIPI.
  begin
    perform public.web_fiscal_item_marcar_importado_por_nos(9310002, '260191366846', '2/24');
    raise exception 'NCM sem TIPI aceito';
  exception when invalid_parameter_value then null;
  end;
  -- Item sem cadastro fiscal.
  begin
    perform public.web_fiscal_item_marcar_importado_por_nos(9319999, '260191366846', '2/24');
    raise exception 'item inexistente aceito';
  exception when no_data_found then null;
  end;

  -- Marcacao: origem 1, equiparado, IPI 50 a 9,75%, DIR e nota gravadas, quem e quando.
  r := public.web_fiscal_item_marcar_importado_por_nos(9310001, '26.019.136.6846', '2/24');
  if not (r->>'ok')::boolean then raise exception 'marcacao falhou: %', r; end if;
  if (r->'antes'->>'origem')::int <> 2 or r->'antes'->>'cst_ipi' <> '53' then raise exception 'antes errado: %', r; end if;
  if (r->>'tipi')::numeric <> 9.75 then raise exception 'tipi errada: %', r; end if;
  if r->'documento_fiscal' is not null and r->'documento_fiscal' <> 'null'::jsonb then raise exception 'nao devia achar nota 2/24 neste tenant: %', r; end if;

  select * into v_fi from public.fiscal_itens where item_id = 9310001;
  if v_fi.origem <> 1 or v_fi.origem_entrada <> 1 or not v_fi.equiparado_industrial then raise exception 'origem/equiparacao: %', to_jsonb(v_fi); end if;
  if v_fi.cst_ipi <> '50' or v_fi.aliq_ipi <> 9.75 then raise exception 'IPI: %', to_jsonb(v_fi); end if;
  if v_fi.importado_por_nos_dir <> '260191366846' or v_fi.importado_por_nos_nota <> '2/24' then raise exception 'DIR/nota: %', to_jsonb(v_fi); end if;
  if v_fi.importado_por_nos_em is null or v_fi.importado_por_nos_por <> '1b000000-0000-4000-8000-000000000001' then raise exception 'quem/quando: %', to_jsonb(v_fi); end if;
  if v_fi.ipi_codigo_enquadramento_legal is not null then raise exception 'cEnq nao e do produto'; end if;

  -- Marcar de novo com outra DIR e permitido (corrige a prova); a ultima vale.
  r := public.web_fiscal_item_marcar_importado_por_nos(9310001, '2612345678', '42260913671448000189550020000000241890455952');
  if not (r->>'ok')::boolean or r->'depois'->>'dir' <> '2612345678' then raise exception 'remarcacao: %', r; end if;
end $diretor$;
reset role;

-- 3. O audit_log de fiscal_itens guarda antes e depois. ------------------------------------------
do $audit$
begin
  if not exists (
    select 1 from public.audit_log a
    where a.table_name = 'fiscal_itens' and a.action = 'UPDATE'
      and a.new_data->>'item_id' = '9310001'
      and a.new_data->>'equiparado_industrial' = 'true'
      and a.old_data->>'equiparado_industrial' = 'false'
  ) then
    raise exception 'audit_log sem a troca de equiparacao do item 9310001';
  end if;
end $audit$;

rollback;
