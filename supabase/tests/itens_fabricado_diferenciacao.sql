\set ON_ERROR_STOP on

-- Produto fabricado (producao propria) separado do item de compra:
--   - criar_item_fabricado_da_os grava finalidade = fabricado;
--   - o trigger deriva `fabricado` da finalidade nos dois sentidos;
--   - fn_faturamento_buscar_itens (tela de faturar OS) nao lista item de compra;
--   - search_cadastro_itens devolve fabricado + OS de origem e filtra por p_fabricado.

begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values (
  '17000000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', 'fabricado@example.test',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"nome":"Teste fabricado"}'::jsonb, now(), now()
);

insert into public.tenants (id, nome, ativo)
values ('17000000-0000-4000-8000-000000000010', 'Tenant fabricado', true);
insert into c.tenant (id, codigo, nome, ativo)
values ('17000000-0000-4000-8000-000000000010', 'FAB-TESTE', 'Tenant fabricado', true);

insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo)
values ('17000000-0000-4000-8000-000000000020', '17000000-0000-4000-8000-000000000010', 'FAB-A', 'Empresa fabricado', 'Empresa fabricado', '17000000000100', true);
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo)
values ('17000000-0000-4000-8000-000000000020', '17000000-0000-4000-8000-000000000010', '17000000000100', 'Empresa fabricado', 'Empresa fabricado', true);

insert into a.usuario (id, auth_user_id, nome, email, ativo)
values ('17000000-0000-4000-8000-000000000040', '17000000-0000-4000-8000-000000000001', 'Teste fabricado', 'fabricado@example.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo)
values ('17000000-0000-4000-8000-000000000040', '17000000-0000-4000-8000-000000000010', 'ADMIN', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo)
values ('17000000-0000-4000-8000-000000000040', '17000000-0000-4000-8000-000000000020', 'DIRETOR', true);
insert into public.user_tenant_context (user_id, tenant_id)
values ('17000000-0000-4000-8000-000000000001', '17000000-0000-4000-8000-000000000010');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
values ('17000000-0000-4000-8000-000000000001', '17000000-0000-4000-8000-000000000010', '17000000-0000-4000-8000-000000000020');

insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social)
values (917001, '17000000-0000-4000-8000-000000000010', '17000000-0000-4000-8000-000000000020', 'CLIENTE FAB', '17111111000191', 'CLIENTE FAB LTDA');

insert into public.ordens_servico (id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id, empresa_id,
  status_fluxo, tipo_documento, codigo, numero_doc, descricao_servico, orcado)
values (917001, '319T', 'CLIENTE FAB', 917001, 'em_andamento', 917001,
        '17000000-0000-4000-8000-000000000010', '17000000-0000-4000-8000-000000000020',
        'em_andamento', 'OS', 'OS-FAB-001', 1, 'KIT SENSOR- FLUXOMETRO 30LT', 18166.99);

-- Item de compra com nome parecido: e o que a busca da tela de faturar nao pode listar.
insert into public.itens (tenant_id, empresa_id, codigo_interno, nome, tipo, unidade_medida, finalidade, ativo)
values ('17000000-0000-4000-8000-000000000010', '17000000-0000-4000-8000-000000000020', 'COMPRA-01', 'KIT SENSOR - FLUXOMETRO 30LT 187', 'produto', 'UN', 'revenda', true);

-- Usuario logado (DIRETOR na empresa): cria o produto fabricado pela RPC da tela.
select set_config('request.jwt.claim.sub', '17000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"17000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

do $rpc$
declare
  v_id integer;
  v_item public.itens%rowtype;
  v_busca integer;
  v_busca_compra integer;
  v_lista integer;
  v_lista_fab integer;
  v_os_numero text;
begin
  v_id := public.criar_item_fabricado_da_os(917001, 'Sistema de controle de fluxo', '9032.89.29', 0, 'UN', '51', null, null);
  select * into v_item from public.itens where id = v_id;
  if v_item.finalidade is distinct from 'fabricado'::public.item_finalidade or v_item.fabricado is not true then
    raise exception 'criar_item_fabricado_da_os gravou finalidade % / fabricado %', v_item.finalidade, v_item.fabricado;
  end if;
  if v_item.codigo_interno <> 'FAB-OS319T-01' or v_item.origem_os_id <> 917001 then
    raise exception 'codigo/origem inesperados: % / %', v_item.codigo_interno, v_item.origem_os_id;
  end if;

  -- Tela de faturar OS: "FLUXO" casa com os dois nomes, mas so o fabricado volta.
  select count(*), count(*) filter (where b.codigo = 'COMPRA-01') into v_busca, v_busca_compra
  from f.fn_faturamento_buscar_itens('17000000-0000-4000-8000-000000000010', '17000000-0000-4000-8000-000000000020', 'FLUXO', 12) b;
  if v_busca <> 1 or v_busca_compra <> 0 then
    raise exception 'fn_faturamento_buscar_itens devolveu % itens (% de compra); esperado 1 fabricado.', v_busca, v_busca_compra;
  end if;

  -- Estoque > Cadastro: sem filtro lista os dois; p_fabricado e finalidade separam.
  select count(*) into v_lista
  from public.search_cadastro_itens('17000000-0000-4000-8000-000000000010', '17000000-0000-4000-8000-000000000020');
  if v_lista <> 2 then raise exception 'search_cadastro_itens sem filtro devolveu %, esperado 2.', v_lista; end if;

  select count(*), max(s.origem_os_numero) into v_lista_fab, v_os_numero
  from public.search_cadastro_itens('17000000-0000-4000-8000-000000000010', '17000000-0000-4000-8000-000000000020', p_fabricado => true) s;
  if v_lista_fab <> 1 or v_os_numero is distinct from '319T' then
    raise exception 'search_cadastro_itens p_fabricado devolveu % (OS %), esperado 1 da OS 319T.', v_lista_fab, v_os_numero;
  end if;

  select count(*) into v_lista_fab
  from public.search_cadastro_itens('17000000-0000-4000-8000-000000000010', '17000000-0000-4000-8000-000000000020', p_finalidade => 'fabricado') s
  where s.fabricado is true and s.finalidade = 'fabricado';
  if v_lista_fab <> 1 then raise exception 'search_cadastro_itens p_finalidade=fabricado devolveu %, esperado 1.', v_lista_fab; end if;
end;
$rpc$;

reset role;

-- Trigger: a finalidade manda na flag e a flag manda na finalidade.
do $trigger$
declare
  v_item public.itens%rowtype;
begin
  update public.itens set finalidade = 'fabricado' where codigo_interno = 'COMPRA-01' returning * into v_item;
  if v_item.fabricado is not true then raise exception 'finalidade=fabricado nao marcou fabricado.'; end if;

  -- finalidade e not null: desmarcar a flag direto e recusado, o caminho e trocar a finalidade.
  begin
    update public.itens set fabricado = false where codigo_interno = 'COMPRA-01';
    raise exception 'desmarcar fabricado com finalidade=fabricado foi aceito.';
  exception when sqlstate '22023' then null;
  end;

  update public.itens set finalidade = 'revenda' where codigo_interno = 'COMPRA-01' returning * into v_item;
  if v_item.fabricado is not false then raise exception 'voltar para revenda nao desmarcou fabricado.'; end if;

  update public.itens set fabricado = true where codigo_interno = 'COMPRA-01' returning * into v_item;
  if v_item.finalidade is distinct from 'fabricado'::public.item_finalidade then raise exception 'marcar fabricado nao ajustou a finalidade.'; end if;

  update public.itens set finalidade = 'consumo' where codigo_interno = 'COMPRA-01' returning * into v_item;
  if v_item.fabricado is not false then raise exception 'voltar para consumo nao desmarcou fabricado.'; end if;

  insert into public.itens (tenant_id, empresa_id, codigo_interno, nome, tipo, unidade_medida, ativo, fabricado)
  values ('17000000-0000-4000-8000-000000000010', '17000000-0000-4000-8000-000000000020', 'FAB-MANUAL-01', 'PAINEL FEITO NA OFICINA', 'produto', 'UN', true, true)
  returning * into v_item;
  if v_item.finalidade is distinct from 'fabricado'::public.item_finalidade then raise exception 'insert com fabricado=true ficou com finalidade %.', v_item.finalidade; end if;

  insert into public.itens (tenant_id, empresa_id, codigo_interno, nome, tipo, unidade_medida, finalidade, ativo)
  values ('17000000-0000-4000-8000-000000000010', '17000000-0000-4000-8000-000000000020', 'CONSUMO-01', 'FITA ISOLANTE', 'produto', 'UN', 'consumo', true)
  returning * into v_item;
  if v_item.fabricado is not false then raise exception 'insert de consumo ficou fabricado.'; end if;
end;
$trigger$;

rollback;
