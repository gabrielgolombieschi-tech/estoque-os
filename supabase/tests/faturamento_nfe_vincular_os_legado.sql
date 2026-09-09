\set ON_ERROR_STOP on

-- Trava de EMITIDA em NF-e de saida modelo 55: barra a transicao, nao o documento.
-- Cenario da NF-e 55/1/3752 da INCEPA (09/09/2026), nota importada do legado que
-- precisava ser amarrada a OS 251 pela tela de detalhe.

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('19100000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'vinculo-os@example.test',
  '{"provider":"email","providers":["email"]}'::jsonb, '{"nome":"Vinculo OS"}'::jsonb, now(), now());

insert into public.tenants (id, nome, ativo) values ('19100000-0000-4000-8000-000000000010', 'Tenant vinculo OS', true);
insert into c.tenant (id, codigo, nome, ativo) values ('19100000-0000-4000-8000-000000000010', 'VINC-OS', 'Tenant vinculo OS', true);
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo)
values ('19100000-0000-4000-8000-000000000020', '19100000-0000-4000-8000-000000000010', 'VINC-A', 'Empresa vinculo OS', 'Empresa vinculo OS', '19100000000100', true);
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo)
values ('19100000-0000-4000-8000-000000000020', '19100000-0000-4000-8000-000000000010', '19100000000100', 'Empresa vinculo OS', 'Empresa vinculo OS', true);

insert into a.usuario (id, auth_user_id, nome, email, ativo)
values ('19100000-0000-4000-8000-000000000040', '19100000-0000-4000-8000-000000000001', 'Vinculo OS', 'vinculo-os@example.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo)
values ('19100000-0000-4000-8000-000000000040', '19100000-0000-4000-8000-000000000010', 'ADMIN', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo)
values ('19100000-0000-4000-8000-000000000040', '19100000-0000-4000-8000-000000000020', 'DIRETOR', true);
insert into public.user_tenant_context (user_id, tenant_id)
values ('19100000-0000-4000-8000-000000000001', '19100000-0000-4000-8000-000000000010');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
values ('19100000-0000-4000-8000-000000000001', '19100000-0000-4000-8000-000000000010', '19100000-0000-4000-8000-000000000020');

insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social)
values (919101, '19100000-0000-4000-8000-000000000010', '19100000-0000-4000-8000-000000000020', 'CLIENTE VINCULO', '19111111000192', 'CLIENTE VINCULO LTDA');
insert into public.ordens_servico (id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id, empresa_id,
  status_fluxo, tipo_documento, codigo, numero_doc, descricao_servico, orcado)
values (919101, 'VINC-1', 'CLIENTE VINCULO', 919101, 'em_andamento', 919101, '19100000-0000-4000-8000-000000000010',
  '19100000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-VINC-001', 1, 'OS da nota do legado', 31540.13);

insert into f.plano_contas (tenant_id, codigo, nome, natureza, tipo, ativo)
values ('19100000-0000-4000-8000-000000000010', '3.01', 'RECEITA DE VENDAS', 'CREDITO', 'ANALITICA', true);

-- Nota do legado: importada, sem passagem pelo pipeline (nenhuma documento_fiscal_emissao).
insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, operacao, natureza,
  cliente_id, nfe_status, origem, valor_produtos, valor_total)
values ('19100000-0000-4000-8000-000000000031', '19100000-0000-4000-8000-000000000010', '19100000-0000-4000-8000-000000000020',
  '19100000000000000000000000000000000000000002', '55', '1', '3752', 'SAIDA', 'PRODUTO',
  919101, 'EMITIDA', 'IMPORTADO', 31540.13, 31540.13);

-- Rascunho de saida, para conferir que promover a EMITIDA continua barrado.
insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, operacao, natureza,
  cliente_id, nfe_status, origem, valor_produtos, valor_total)
values ('19100000-0000-4000-8000-000000000032', '19100000-0000-4000-8000-000000000010', '19100000-0000-4000-8000-000000000020',
  '19100000000000000000000000000000000000000003', '55', '1', '3753', 'SAIDA', 'PRODUTO',
  919101, 'RASCUNHO', 'IMPORTADO', 100.00, 100.00);

-- Primeira fase do importador de saida: nasce ENTRADA, sem cliente e sem status, com a
-- nf_entrada de origem. A segunda fase promove para SAIDA/EMITIDA.
insert into public.nf_entrada (id, tenant_id, empresa_id, chave, numero, serie, emitente_nome, emitente_cnpj,
  data_emissao, valor_produtos, valor_total, xml_raw)
values (919101, '19100000-0000-4000-8000-000000000010', '19100000-0000-4000-8000-000000000020',
  '19100000000000000000000000000000000000000009', '3804', '1', 'EMPRESA VINCULO OS', '19100000000100',
  '2026-09-03', 433434.55, 433434.55, '<nfeProc/>');
insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, operacao, natureza,
  nfe_status, origem, source_nf_entrada_id, valor_produtos, valor_total)
values ('19100000-0000-4000-8000-000000000033', '19100000-0000-4000-8000-000000000010', '19100000-0000-4000-8000-000000000020',
  '19100000000000000000000000000000000000000009', '55', '1', '3804', 'ENTRADA', 'PRODUTO',
  null, 'IMPORTADO', 919101, 433434.55, 433434.55);

-- Mesmo formato, porem sem XML de origem: nao e carga, e fabricacao de nota.
insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, operacao, natureza,
  nfe_status, origem, valor_produtos, valor_total)
values ('19100000-0000-4000-8000-000000000034', '19100000-0000-4000-8000-000000000010', '19100000-0000-4000-8000-000000000020',
  '19100000000000000000000000000000000000000010', '55', '1', '3805', 'ENTRADA', 'PRODUTO',
  null, 'IMPORTADO', 999999.99, 999999.99);

select set_config('request.jwt.claim.sub', '19100000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"19100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

do $vinculo$
declare v_os integer;
begin
  -- 1) Amarrar a OS numa nota emitida do legado: e o caso da tela, tem de passar.
  update f.documento_fiscal set os_id_import = 919101, updated_at = now()
  where id = '19100000-0000-4000-8000-000000000031';
  select os_id_import into v_os from f.documento_fiscal where id = '19100000-0000-4000-8000-000000000031';
  if v_os is distinct from 919101 then
    raise exception 'Vinculo da OS nao gravou: %', v_os;
  end if;

  -- 2) Desamarrar tambem: o botao Limpar da tela faz isso.
  update f.documento_fiscal set os_id_import = null, updated_at = now()
  where id = '19100000-0000-4000-8000-000000000031';
  select os_id_import into v_os from f.documento_fiscal where id = '19100000-0000-4000-8000-000000000031';
  if v_os is not null then
    raise exception 'Desvinculo da OS nao gravou: %', v_os;
  end if;

  -- 3) Valor de nota emitida continua intocavel.
  begin
    update f.documento_fiscal set valor_total = 1 where id = '19100000-0000-4000-8000-000000000031';
    raise exception 'Alterou o valor de uma NF-e emitida.';
  exception when sqlstate '42501' then null;
  end;

  -- 4) Promover rascunho a EMITIDA por fora do pipeline continua barrado.
  begin
    update f.documento_fiscal set nfe_status = 'EMITIDA' where id = '19100000-0000-4000-8000-000000000032';
    raise exception 'Promoveu um rascunho a EMITIDA por fora do pipeline.';
  exception when sqlstate '42501' then null;
  end;

  -- 5) Nascer EMITIDA continua barrado.
  begin
    insert into f.documento_fiscal (tenant_id, empresa_id, chave_acesso, modelo, serie, numero, operacao, natureza,
      cliente_id, nfe_status, origem, valor_produtos, valor_total)
    values ('19100000-0000-4000-8000-000000000010', '19100000-0000-4000-8000-000000000020',
      '19100000000000000000000000000000000000000004', '55', '1', '3754', 'SAIDA', 'PRODUTO',
      919101, 'EMITIDA', 'IMPORTADO', 50.00, 50.00);
    raise exception 'Inseriu uma NF-e de saida ja EMITIDA por fora do pipeline.';
  exception when sqlstate '42501' then null;
  end;

  -- 6) Segunda fase do importador de saida: promove a nota carregada por XML.
  update f.documento_fiscal set
    cliente_id = 919101, operacao = 'SAIDA', natureza = 'PRODUTO', nfe_status = 'EMITIDA',
    os_id_import = 919101, updated_at = now()
  where id = '19100000-0000-4000-8000-000000000033';
  if not exists (
    select 1 from f.documento_fiscal
    where id = '19100000-0000-4000-8000-000000000033' and operacao = 'SAIDA' and nfe_status = 'EMITIDA'
  ) then
    raise exception 'Importador de saida nao promoveu a nota carregada por XML.';
  end if;

  -- 7) Sem nf_entrada de origem nao ha prova de carga: continua barrado.
  begin
    update f.documento_fiscal set
      cliente_id = 919101, operacao = 'SAIDA', nfe_status = 'EMITIDA', updated_at = now()
    where id = '19100000-0000-4000-8000-000000000034';
    raise exception 'Promoveu a EMITIDA um documento sem XML de origem.';
  exception when sqlstate '42501' then null;
  end;
end;
$vinculo$;

reset role;

rollback;
