\set ON_ERROR_STOP on

-- Regressao funcional: todos os termos antes de LIMIT/count/paginacao,
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
values ('27000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'busca-item@example.test', '{"provider":"email","providers":["email"]}', '{"nome":"Teste busca item"}', now(), now());
insert into public.tenants (id, nome, ativo) values
  ('27000000-0000-4000-8000-000000000010', 'Tenant busca', true),
  ('27000000-0000-4000-8000-000000000011', 'Outro tenant busca', true);
insert into c.tenant (id, codigo, nome, ativo) values
  ('27000000-0000-4000-8000-000000000010', 'BUSCA-TESTE', 'Tenant busca', true),
  ('27000000-0000-4000-8000-000000000011', 'BUSCA-OUTRO', 'Outro tenant busca', true);
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo) values
  ('27000000-0000-4000-8000-000000000020', '27000000-0000-4000-8000-000000000010', 'BUSCA-A', 'Empresa busca A', 'Empresa busca A', '27000000000100', true),
  ('27000000-0000-4000-8000-000000000021', '27000000-0000-4000-8000-000000000010', 'BUSCA-B', 'Empresa busca B', 'Empresa busca B', '27000000000200', true),
  ('27000000-0000-4000-8000-000000000022', '27000000-0000-4000-8000-000000000011', 'BUSCA-C', 'Empresa busca C', 'Empresa busca C', '27000000000300', true);
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo) values
  ('27000000-0000-4000-8000-000000000020', '27000000-0000-4000-8000-000000000010', '27000000000100', 'Empresa busca A', 'Empresa busca A', true),
  ('27000000-0000-4000-8000-000000000021', '27000000-0000-4000-8000-000000000010', '27000000000200', 'Empresa busca B', 'Empresa busca B', true),
  ('27000000-0000-4000-8000-000000000022', '27000000-0000-4000-8000-000000000011', '27000000000300', 'Empresa busca C', 'Empresa busca C', true);
insert into a.usuario (id, auth_user_id, nome, email, ativo)
values ('27000000-0000-4000-8000-000000000040', '27000000-0000-4000-8000-000000000001', 'Teste busca', 'busca-item@example.test', true);
insert into a.usuario_tenant (usuario_id, tenant_id, papel, ativo)
values ('27000000-0000-4000-8000-000000000040', '27000000-0000-4000-8000-000000000010', 'ADMIN', true);
insert into a.usuario_empresa (usuario_id, empresa_id, papel, ativo)
values ('27000000-0000-4000-8000-000000000040', '27000000-0000-4000-8000-000000000020', 'DIRETOR', true);
insert into public.user_tenant_context (user_id, tenant_id)
values ('27000000-0000-4000-8000-000000000001', '27000000-0000-4000-8000-000000000010');
insert into public.user_empresa_context (user_id, tenant_id, empresa_id)
values ('27000000-0000-4000-8000-000000000001', '27000000-0000-4000-8000-000000000010', '27000000-0000-4000-8000-000000000020');

insert into public.fornecedores (id, tenant_id, empresa_id, nome)
values (927001, '27000000-0000-4000-8000-000000000010', '27000000-0000-4000-8000-000000000020', 'ELÉTRICA BRASIL 1,5 COMÉRCIO');

-- Mais de 200 candidatos iniciais: os dois corretos vem depois pelo nome.
insert into public.itens (id, tenant_id, empresa_id, codigo_interno, nome, tipo, unidade_medida, finalidade, ativo, controla_estoque, fornecedor_id)
select 927100 + n, '27000000-0000-4000-8000-000000000010', '27000000-0000-4000-8000-000000000020',
       'DECOY-' || n, 'A CABO FLEXIVEL 2,5MM² ' || n, 'produto', 'UN', 'revenda', true, true, 927001
from generate_series(1, 210) n;
insert into public.itens (id, tenant_id, empresa_id, codigo_interno, codigo_barras, nome, fabricante, tipo, unidade_medida, finalidade, ativo, controla_estoque, fornecedor_id) values
  (927001, '27000000-0000-4000-8000-000000000010', '27000000-0000-4000-8000-000000000020', 'CB-1.5-A', '7345001234567', 'Z CABO FLEXÍVEL 1,5MM² AZUL', 'MARCA TESTE', 'produto', 'UN', 'revenda', true, true, 927001),
  (927002, '27000000-0000-4000-8000-000000000010', '27000000-0000-4000-8000-000000000020', 'CB-1.5-B', null, 'Z CABO COBRE 1.5MM² PRETO', 'MARCA TESTE', 'produto', 'UN', 'fabricado', true, true, 927001),
  (927003, '27000000-0000-4000-8000-000000000010', '27000000-0000-4000-8000-000000000020', '123', null, 'PARAFUSO', null, 'produto', 'UN', 'revenda', true, true, null),
  (927004, '27000000-0000-4000-8000-000000000010', '27000000-0000-4000-8000-000000000020', '1234', null, 'PARAFUSO LONGO', null, 'produto', 'UN', 'revenda', true, true, null),
  (927005, '27000000-0000-4000-8000-000000000010', '27000000-0000-4000-8000-000000000021', 'ESCOPO-B', null, 'Z CABO FLEXÍVEL 1,5MM² AZUL', 'MARCA TESTE', 'produto', 'UN', 'revenda', true, true, null),
  (927006, '27000000-0000-4000-8000-000000000011', '27000000-0000-4000-8000-000000000022', 'ESCOPO-C', null, 'Z CABO FLEXÍVEL 1,5MM² AZUL', 'MARCA TESTE', 'produto', 'UN', 'revenda', true, true, null);

update public.fiscal_itens set origem = 0, ncm = '85444900'
where tenant_id = '27000000-0000-4000-8000-000000000010'
  and empresa_id = '27000000-0000-4000-8000-000000000020'
  and item_id in (927001, 927002);
insert into public.movimentacoes (id, item_id, tenant_id, empresa_id, tipo, quantidade, data_movimentacao, motivo) values
  (927001, 927001, '27000000-0000-4000-8000-000000000010', '27000000-0000-4000-8000-000000000020', 'entrada', 1, '2026-09-18', 'Fixture transacional busca'),
  (927002, 927002, '27000000-0000-4000-8000-000000000010', '27000000-0000-4000-8000-000000000020', 'entrada', 1, '2026-09-18', 'Fixture transacional busca');
insert into c.conjunto (id, tenant_id, empresa_id, codigo, nome, precificacao, preco_fixo)
values ('27000000-0000-4000-8000-000000000050', '27000000-0000-4000-8000-000000000010', '27000000-0000-4000-8000-000000000020', 'CJ-1.5', 'CONJUNTO CABO FLEXÍVEL', 'PRECO_FIXO', 1);

select set_config('request.jwt.claim.sub', '27000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"27000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

do $test$
declare
  t constant uuid := '27000000-0000-4000-8000-000000000010';
  e constant uuid := '27000000-0000-4000-8000-000000000020';
  v_count integer;
  v_total bigint;
  v_id integer;
  v_ids integer[];
  v_export_ids integer[];
  v_fornecedor_termo text;
  v_json jsonb;
begin
  select array_agg(s.id order by s.id) into v_ids
  from public.search_orcamento_itens(t, e, '1,5 cabo', 'comercio eletrica', 200) s;
  perform pg_temp.assert_busca(v_ids = array[927001,927002], 'Orcamento: todos termos de item/fornecedor antes do limite e sem vazamento de escopo');

  select array_agg(s.id order by s.id) into v_ids
  from public.search_os_itens(t, e, '1.5 cabo', 'comercio eletrica', false, 200) s;
  perform pg_temp.assert_busca(v_ids = array[927001,927002], 'OS: todos termos de item/fornecedor antes do limite');

  select count(*), max(s.id) into v_count, v_id from public.search_orcamento_itens(t, e, '123') s;
  perform pg_temp.assert_busca(v_count = 1 and v_id = 927003, 'Codigo numerico de orcamento permanece exato');
  select count(*), max(s.id) into v_count, v_id from public.search_os_itens(t, e, '123') s;
  perform pg_temp.assert_busca(v_count = 1 and v_id = 927003, 'Codigo numerico de OS permanece exato');
  select count(*), max(s.id) into v_count, v_id from public.search_cadastro_itens(t, e, p_codigo => '123') s;
  perform pg_temp.assert_busca(v_count = 1 and v_id = 927003, 'Codigo numerico de cadastro permanece exato');

  -- Mesmo contrato usado pelo PostgREST na impressao: coluna normalizada e
  -- um ILIKE por termo, todos antes de selecionar os itens do fornecedor.
  foreach v_fornecedor_termo in array array['comercio eletrica', '1.5 eletrica', '1,5 comercio'] loop
    select array_agg(s.id order by s.id) into v_ids
    from public.search_cadastro_itens(t, e, p_produto => 'cabo 1,5', p_fornecedor => v_fornecedor_termo) s;
    select array_agg(i.id order by i.id) into v_export_ids
    from public.itens i
    join public.fornecedores f on f.id = i.fornecedor_id and f.tenant_id = i.tenant_id and f.empresa_id = i.empresa_id
    where i.tenant_id = t and i.empresa_id = e
      and i.nome_item_busca ilike '%CABO%' and i.nome_item_busca ilike '%1.5%'
      and not exists (
        select 1 from regexp_split_to_table(public.fn_item_busca_normalizar(v_fornecedor_termo), ' ') parte
        where f.nome_busca_termos not ilike '%' || parte || '%'
      );
    perform pg_temp.assert_busca(v_ids = array[927001,927002] and v_export_ids = v_ids,
      'Impressao e cadastro divergem no fornecedor: ' || v_fornecedor_termo);
  end loop;
  select count(*), max(i.id) into v_count, v_id from public.itens i
  where i.tenant_id = t and i.empresa_id = e and (i.codigo_interno = '123' or i.codigo_barras = '123');
  perform pg_temp.assert_busca(v_count = 1 and v_id = 927003, 'Codigo numerico da impressao nao inclui 1234 ao buscar 123');

  select count(*), max(s.total_count), max(s.id) into v_count, v_total, v_id
  from public.search_cadastro_itens(t, e, p_produto => 'cabo 1,5', p_page_size => 1, p_sort_key => 'id') s;
  perform pg_temp.assert_busca(v_count = 1 and v_total = 2 and v_id = 927001, 'Cadastro: count antes de paginar');
  select max(s.id) into v_id
  from public.search_cadastro_itens(t, e, p_produto => '1.5 cabo', p_page => 2, p_page_size => 1, p_sort_key => 'id') s;
  perform pg_temp.assert_busca(v_id = 927002, 'Cadastro: segunda pagina dos resultados completos');

  select count(*), max(s.total_count), max(s.item_id) into v_count, v_total, v_id
  from public.search_estoque_itens(t, e, p_nome => 'cabo 1,5', p_page_size => 1, p_sort_key => 'id') s;
  perform pg_temp.assert_busca(v_count = 1 and v_total = 2 and v_id = 927001, 'Estoque: filtro Produto normalizado e count antes de paginar');
  select count(*) into v_count from public.search_estoque_itens(t, e, p_busca_geral => '1,5 marca cabo') s;
  perform pg_temp.assert_busca(v_count = 2, 'Estoque geral: palavras distribuidas em campos diferentes');
  select count(*) into v_count from public.search_estoque_itens(t, e, p_codigo => 'CB-1.5') s;
  perform pg_temp.assert_busca(v_count = 2, 'Filtro de codigo dedicado preserva substring literal');

  select count(*), max(s.total_count) into v_count, v_total
  from public.search_relatorio_estoque(t, e, p_busca => '1,5 cabo', p_page_size => 1) s;
  perform pg_temp.assert_busca(v_count = 1 and v_total = 2, 'Relatorio estoque: filtro antes de count/limit');
  select count(*) into v_count from public.search_relatorio_estoque(t, e, p_busca => '1.5 cabo', p_page_size => 500) s;
  perform pg_temp.assert_busca(v_count = 2, 'Relatorio estoque: mesmos dados para exportacao completa');

  select count(*) into v_count from public.search_orcamento_conjuntos(t, e, '1,5 flexivel') s;
  perform pg_temp.assert_busca(v_count = 1, 'Conjunto: termos entre codigo e nome');
  select count(*) into v_count from public.rel_entradas_periodo_consolidado(t, e, '2026-09-18', '2026-09-18', p_busca_item => '1,5 cabo') s;
  perform pg_temp.assert_busca(v_count = 2, 'Entradas no periodo: todos termos');
  select count(*) into v_count from public.home_busca_comando('1,5 cabo') s where s.tipo = 'Item';
  perform pg_temp.assert_busca(v_count = 2, 'Home: busca de itens e isolamento');
  select count(*), max(s.id) into v_count, v_id from f.fn_faturamento_buscar_itens(t, e, '1,5 cabo') s;
  perform pg_temp.assert_busca(v_count = 1 and v_id = 927002, 'Faturamento: busca AND preserva restricao de fabricado');
  select array_agg(s.id order by s.id) into v_ids from f.fn_remessa_buscar_itens('1,5 cabo', 50) s;
  perform pg_temp.assert_busca(v_ids = array[927001,927002], 'Remessa: busca AND com catalogo completo');

  v_json := public.fiscal_item_similares(927003, '1,5 cabo');
  select count(*) into v_count from jsonb_array_elements(v_json->'candidatos');
  perform pg_temp.assert_busca(v_count = 2, 'Fiscal similar: busca manual preserva decimal e todos termos');

  select count(*) into v_count from public.itens i
  where i.tenant_id = t and i.empresa_id = e
    and i.busca_item ilike '%CABO%' and i.busca_item ilike '%1.5%';
  perform pg_temp.assert_busca(v_count = 2, 'Coluna gerada usada por filtros encadeados PostgREST');

  begin
    perform * from public.search_estoque_itens(t, '27000000-0000-4000-8000-000000000021', p_nome => 'cabo 1,5');
    raise exception 'Busca aceitou empresa sem acesso';
  exception when others then
    if sqlerrm <> 'estoque_search_access_denied' then raise; end if;
  end;
  begin
    perform * from public.search_orcamento_itens('27000000-0000-4000-8000-000000000011', '27000000-0000-4000-8000-000000000022', 'cabo 1,5');
    raise exception 'Busca aceitou outro tenant';
  exception when others then
    if sqlerrm <> 'orcamento_item_search_access_denied' then raise; end if;
  end;
end;
$test$;

reset role;
rollback;
