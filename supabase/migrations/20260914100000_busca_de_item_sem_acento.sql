-- Busca de item sem acento. Decisao de Gabriel em 14/09/2026: quem digita
-- "armario" tem que achar ARMÁRIO. Hoje nao acha, porque o ilike do banco
-- compara o texto cru — e o cadastro tem acento.
--
-- A tela ja normaliza (tira acento e sobe pra maiuscula) do lado do navegador,
-- so que isso acontece DEPOIS que o banco devolveu as linhas: se o ilike nao
-- trouxe nada, nao ha o que filtrar. Entao a normalizacao precisa existir
-- tambem no banco, dos dois lados da comparacao.
--
-- public.fn_texto_busca e a versao SQL da mesma regra do navegador: troca as
-- letras acentuadas pelas simples e sobe pra maiuscula. E translate() puro,
-- sem depender da extensao unaccent, e por ser immutable pode virar indice
-- depois se a busca pesar.
--
-- Alcance: toda busca de item do sistema, por pedido de Gabriel — o mesmo
-- "armario" tem que achar em qualquer tela.
--   search_orcamento_itens    modal "Localizar item" do orcamento
--   search_os_itens           mesmo modal na OS e na venda
--   search_cadastro_itens     cadastro de itens (na migration 20260914110000,
--                             que corrige a assinatura errada usada aqui)
--   search_estoque_itens      tela de estoque
--   search_relatorio_estoque  relatorio de saldo
-- Mais a busca de conjunto do orcamento, que ate agora era um ilike direto na
-- view e passa a ter RPC propria — a view e security_invoker e nao da pra
-- chamar funcao no filtro do PostgREST.
--
-- Em todas elas a regra e a mesma: onde havia `campo ilike '%termo%'` agora ha
-- `fn_texto_busca(campo) like '%' || fn_texto_busca(termo) || '%'`. O like sem
-- "i" basta porque os dois lados ja sobem pra maiuscula. Busca por codigo
-- exato (so digitos) continua comparando o texto cru, que nao tem acento.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 1. Normalizador --------------------------------------------------------------

create or replace function public.fn_texto_busca(p_texto text)
returns text
language sql
immutable
parallel safe
set search_path to 'pg_catalog'
as $function$
  select upper(translate(
    coalesce(p_texto, ''),
    'áàâãäåÁÀÂÃÄÅéèêëÉÈÊËíìîïÍÌÎÏóòôõöÓÒÔÕÖúùûüÚÙÛÜçÇñÑýÿÝ',
    'aaaaaaAAAAAAeeeeEEEEiiiiIIIIoooooOOOOOuuuuUUUUcCnNyyY'
  ));
$function$;

comment on function public.fn_texto_busca(text) is
  'Texto sem acento e em maiusculas, para comparar busca digitada com cadastro.';

revoke all on function public.fn_texto_busca(text) from public, anon;
grant execute on function public.fn_texto_busca(text) to authenticated, service_role;

-- 2. Itens do orcamento ---------------------------------------------------------

create or replace function public.search_orcamento_itens(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_term text default null,
  p_fornecedor text default null,
  p_limit integer default 150
)
returns table(
  id integer,
  codigo_interno text,
  nome text,
  fabricante text,
  preco_unitario numeric,
  custo_ultima_compra numeric,
  fornecedor text,
  ultima_entrada timestamp without time zone,
  estoque_atual numeric,
  preco_sugerido numeric
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
declare
  v_term text := nullif(btrim(coalesce(p_term, '')), '');
  v_fornecedor text := nullif(btrim(coalesce(p_fornecedor, '')), '');
  v_limit integer := greatest(1, least(coalesce(p_limit, 150), 200));
  v_codigo_exato boolean := v_term ~ '^[0-9]+$';
  v_term_busca text := public.fn_texto_busca(v_term);
  v_fornecedor_busca text := public.fn_texto_busca(v_fornecedor);
begin
  if auth.uid() is null or p_tenant_id is null or p_empresa_id is null
     or not public.has_active_empresa_access(p_tenant_id,p_empresa_id)
     or not c.has_comercial_access(p_tenant_id,p_empresa_id) then
    raise exception 'orcamento_item_search_access_denied';
  end if;

  return query
  select i.id, i.codigo_interno::text, i.nome::text, i.fabricante::text,
         i.preco_unitario, i.custo_ultima_compra, f.nome::text,
         mov.data_movimentacao, e.quantidade_atual,
         public.fn_preco_venda_item_unscoped(p_tenant_id,p_empresa_id,i.id)
  from public.itens i
  left join public.fornecedores f on f.tenant_id=i.tenant_id and f.empresa_id=i.empresa_id and f.id=i.fornecedor_id
  left join public.estoque e on e.tenant_id=i.tenant_id and e.empresa_id=i.empresa_id and e.item_id=i.id
  left join lateral (
    select m.data_movimentacao from public.movimentacoes m
    where m.tenant_id=i.tenant_id and m.empresa_id=i.empresa_id and m.item_id=i.id and m.tipo='entrada'
    order by m.data_movimentacao desc nulls last, m.id desc limit 1
  ) mov on true
  where i.tenant_id=p_tenant_id and i.empresa_id=p_empresa_id and i.ativo is true
    and (
      v_term is null
      or (v_codigo_exato and (i.codigo_interno=v_term or i.codigo_barras=v_term or i.id::text=v_term))
      or (not v_codigo_exato and (
            public.fn_texto_busca(i.nome::text) like '%'||v_term_busca||'%'
            or public.fn_texto_busca(i.codigo_interno::text) like '%'||v_term_busca||'%'
            or public.fn_texto_busca(i.fabricante::text) like '%'||v_term_busca||'%'
          ))
    )
    and (v_fornecedor is null or public.fn_texto_busca(f.nome::text) like '%'||v_fornecedor_busca||'%')
  order by i.nome, i.id
  limit v_limit;
end;
$function$;

-- 3. Itens da OS e da venda -----------------------------------------------------

create or replace function public.search_os_itens(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_term text default null,
  p_fornecedor text default null,
  p_despesa_only boolean default false,
  p_limit integer default 150
)
returns table(
  id integer,
  codigo_interno text,
  nome text,
  fabricante text,
  tipo text,
  finalidade text,
  preco_unitario numeric,
  aliquota_ipi numeric,
  controla_estoque boolean,
  fornecedor text,
  ultima_entrada timestamp without time zone,
  estoque_atual numeric
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
declare
  v_term text := nullif(btrim(coalesce(p_term, '')), '');
  v_fornecedor text := nullif(btrim(coalesce(p_fornecedor, '')), '');
  v_limit integer := greatest(1, least(coalesce(p_limit, 150), 200));
  v_codigo_exato boolean := v_term ~ '^[0-9]+$';
  v_papel text := a.fn_current_empresa_papel(p_tenant_id, p_empresa_id);
  v_term_busca text := public.fn_texto_busca(v_term);
  v_fornecedor_busca text := public.fn_texto_busca(v_fornecedor);
begin
  if auth.uid() is null
     or p_tenant_id is null
     or p_empresa_id is null
     or public.current_tenant_id() is distinct from p_tenant_id
     or public.current_empresa_id__by_tenant(p_tenant_id) is distinct from p_empresa_id
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or coalesce(v_papel, '') not in (
       'ADMIN', 'DIRETOR', 'FINANCEIRO', 'FATURAMENTO', 'COORDENACAO',
       'COMPRAS', 'ALMOXARIFADO', 'TECNICO', 'APONTAMENTO_RH'
     ) then
    raise exception 'os_item_search_access_denied';
  end if;

  return query
  select
    i.id,
    i.codigo_interno::text,
    i.nome::text,
    i.fabricante::text,
    i.tipo::text,
    i.finalidade::text,
    i.preco_unitario,
    i.aliquota_ipi,
    i.controla_estoque,
    f.nome::text as fornecedor,
    mov.data_movimentacao as ultima_entrada,
    e.quantidade_atual as estoque_atual
  from public.itens i
  left join public.fornecedores f
    on f.tenant_id = i.tenant_id
   and f.empresa_id = i.empresa_id
   and f.id = i.fornecedor_id
  left join public.estoque e
    on e.tenant_id = i.tenant_id
   and e.empresa_id = i.empresa_id
   and e.item_id = i.id
  left join lateral (
    select m.data_movimentacao
    from public.movimentacoes m
    where m.tenant_id = i.tenant_id
      and m.empresa_id = i.empresa_id
      and m.item_id = i.id
      and m.tipo = 'entrada'
    order by m.data_movimentacao desc nulls last, m.id desc
    limit 1
  ) mov on true
  where i.tenant_id = p_tenant_id
    and i.empresa_id = p_empresa_id
    and i.ativo is true
    and (not coalesce(p_despesa_only, false) or i.id between 1 and 99)
    and (
      v_term is null
      or (
        v_codigo_exato
        and (i.id::text = v_term or i.codigo_interno = v_term or i.codigo_barras = v_term)
      )
      or (
        not v_codigo_exato
        and (
          public.fn_texto_busca(i.nome::text) like '%' || v_term_busca || '%'
          or public.fn_texto_busca(i.codigo_interno::text) like '%' || v_term_busca || '%'
          or public.fn_texto_busca(i.fabricante::text) like '%' || v_term_busca || '%'
        )
      )
    )
    and (v_fornecedor is null or public.fn_texto_busca(f.nome::text) like '%' || v_fornecedor_busca || '%')
  order by i.nome asc, i.id asc
  limit v_limit;
end;
$function$;

-- 4. Conjuntos do orcamento -----------------------------------------------------

create or replace function public.search_orcamento_conjuntos(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_term text default null,
  p_limit integer default 150
)
returns table(
  conjunto_id uuid,
  codigo text,
  nome text,
  preco_sugerido numeric
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
declare
  v_term text := nullif(btrim(coalesce(p_term, '')), '');
  v_limit integer := greatest(1, least(coalesce(p_limit, 150), 200));
  v_term_busca text := public.fn_texto_busca(v_term);
begin
  if auth.uid() is null or p_tenant_id is null or p_empresa_id is null
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or not c.has_comercial_access(p_tenant_id, p_empresa_id) then
    raise exception 'orcamento_conjunto_search_access_denied';
  end if;

  return query
  select v.conjunto_id, v.codigo::text, v.nome::text, v.preco_sugerido::numeric
  from r.r_orcamento_catalogo_busca v
  where v.origem = 'CONJUNTO'
    and v.tenant_id = p_tenant_id
    and v.empresa_id = p_empresa_id
    and (
      v_term is null
      or public.fn_texto_busca(v.codigo) like '%' || v_term_busca || '%'
      or public.fn_texto_busca(v.nome) like '%' || v_term_busca || '%'
    )
  order by v.nome, v.conjunto_id
  limit v_limit;
end;
$function$;

revoke all on function public.search_orcamento_conjuntos(uuid, uuid, text, integer) from public, anon;
grant execute on function public.search_orcamento_conjuntos(uuid, uuid, text, integer) to authenticated, service_role;

-- 5. Cadastro de itens ----------------------------------------------------------
--
-- Removido: esta seccao trazia a assinatura de 13 argumentos do baseline, mas
-- producao ja estava na de 14 (p_fabricado). O create or replace virou uma
-- sobrecarga e deixou a chamada ambigua. O conserto, com a assinatura certa,
-- esta em 20260914110000_busca_cadastro_itens_assinatura_certa.sql.

-- 6. Tela de estoque ------------------------------------------------------------

create or replace function public.search_estoque_itens(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_busca_geral text default null,
  p_codigo text default null,
  p_nome text default null,
  p_fornecedor text default null,
  p_item_id integer default null,
  p_ativo_only boolean default false,
  p_finalidade text default null,
  p_abaixo_minimo boolean default false,
  p_sem_fornecedor boolean default false,
  p_saldo_positivo boolean default false,
  p_page integer default 1,
  p_page_size integer default 50,
  p_sort_key text default 'nome',
  p_sort_dir text default 'asc'
)
returns table(
  total_count bigint,
  item_id integer,
  estoque_id integer,
  codigo_interno text,
  codigo_barras text,
  item_nome text,
  tipo text,
  unidade_medida text,
  quantidade_atual numeric,
  preco_unitario numeric,
  custo_medio numeric,
  estoque_minimo numeric,
  estoque_ideal numeric,
  estoque_maximo numeric,
  fornecedor_id integer,
  fornecedor_nome text,
  finalidade text,
  controla_estoque boolean,
  ativo boolean,
  atualizado_em timestamp without time zone,
  localizacao text,
  abaixo_minimo boolean
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
declare
  v_busca text := nullif(btrim(coalesce(p_busca_geral, '')), '');
  v_codigo text := nullif(btrim(coalesce(p_codigo, '')), '');
  v_nome text := nullif(btrim(coalesce(p_nome, '')), '');
  v_fornecedor text := nullif(btrim(coalesce(p_fornecedor, '')), '');
  v_finalidade text := nullif(btrim(coalesce(p_finalidade, '')), '');
  v_page integer := greatest(1, coalesce(p_page, 1));
  v_page_size integer := greatest(1, least(coalesce(p_page_size, 50), 500));
  v_sort_key text := lower(coalesce(p_sort_key, 'nome'));
  v_sort_dir text := lower(coalesce(p_sort_dir, 'asc'));
  v_busca_norm text := public.fn_texto_busca(v_busca);
  v_codigo_busca text := public.fn_texto_busca(v_codigo);
  v_nome_busca text := public.fn_texto_busca(v_nome);
  v_fornecedor_busca text := public.fn_texto_busca(v_fornecedor);
begin
  if auth.uid() is null
     or p_tenant_id is null
     or p_empresa_id is null
     or public.current_tenant_id() is distinct from p_tenant_id
     or public.current_empresa_id__by_tenant(p_tenant_id) is distinct from p_empresa_id
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or not (
       public.can('estoque', 'read', p_tenant_id)
       or public.can('estoque', 'write', p_tenant_id)
     ) then
    raise exception 'estoque_search_access_denied';
  end if;

  if v_sort_key not in ('id', 'codigo', 'nome') then
    v_sort_key := 'nome';
  end if;
  if v_sort_dir not in ('asc', 'desc') then
    v_sort_dir := 'asc';
  end if;

  return query
  with filtered as (
    select
      i.id as item_id,
      e.id as estoque_id,
      i.codigo_interno::text as codigo_interno,
      i.codigo_barras::text as codigo_barras,
      i.nome::text as item_nome,
      i.tipo::text as tipo,
      i.unidade_medida::text as unidade_medida,
      coalesce(e.quantidade_atual, 0)::numeric as quantidade_atual,
      i.preco_unitario::numeric as preco_unitario,
      i.custo_medio::numeric as custo_medio,
      i.estoque_minimo::numeric as estoque_minimo,
      i.estoque_ideal::numeric as estoque_ideal,
      i.estoque_maximo::numeric as estoque_maximo,
      i.fornecedor_id,
      f.nome::text as fornecedor_nome,
      i.finalidade::text as finalidade,
      i.controla_estoque,
      i.ativo,
      e.atualizado_em,
      e.localizacao::text as localizacao,
      (coalesce(e.quantidade_atual, 0) < coalesce(i.estoque_minimo, 0)) as abaixo_minimo
    from public.itens i
    left join public.estoque e
      on e.tenant_id = i.tenant_id
     and e.empresa_id = i.empresa_id
     and e.item_id = i.id
    left join public.fornecedores f
      on f.tenant_id = i.tenant_id
     and f.empresa_id = i.empresa_id
     and f.id = i.fornecedor_id
    where i.tenant_id = p_tenant_id
      and i.empresa_id = p_empresa_id
      and i.tipo = 'produto'
      and i.controla_estoque is true
      and (not coalesce(p_ativo_only, false) or i.ativo is true)
      and (p_item_id is null or i.id = p_item_id)
      and (
        v_busca is null
        or public.fn_texto_busca(i.codigo_interno::text) like '%' || v_busca_norm || '%'
        or public.fn_texto_busca(i.codigo_barras::text) like '%' || v_busca_norm || '%'
        or public.fn_texto_busca(i.nome::text) like '%' || v_busca_norm || '%'
      )
      and (
        v_codigo is null
        or public.fn_texto_busca(i.codigo_interno::text) like '%' || v_codigo_busca || '%'
        or public.fn_texto_busca(i.codigo_barras::text) like '%' || v_codigo_busca || '%'
      )
      and (v_nome is null or public.fn_texto_busca(i.nome::text) like '%' || v_nome_busca || '%')
      and (v_finalidade is null or i.finalidade::text = v_finalidade)
      and (
        (v_fornecedor is null and not coalesce(p_sem_fornecedor, false))
        or (v_fornecedor is null and coalesce(p_sem_fornecedor, false) and i.fornecedor_id is null)
        or (v_fornecedor is not null and public.fn_texto_busca(f.nome::text) like '%' || v_fornecedor_busca || '%')
        or (v_fornecedor is not null and coalesce(p_sem_fornecedor, false) and i.fornecedor_id is null)
      )
      and (not coalesce(p_saldo_positivo, false) or coalesce(e.quantidade_atual, 0) > 0)
      and (
        not coalesce(p_abaixo_minimo, false)
        or coalesce(e.quantidade_atual, 0) < coalesce(i.estoque_minimo, 0)
      )
  ), counted as (
    select count(*) over () as total_count, filtered.*
    from filtered
  )
  select
    counted.total_count,
    counted.item_id,
    counted.estoque_id,
    counted.codigo_interno,
    counted.codigo_barras,
    counted.item_nome,
    counted.tipo,
    counted.unidade_medida,
    counted.quantidade_atual,
    counted.preco_unitario,
    counted.custo_medio,
    counted.estoque_minimo,
    counted.estoque_ideal,
    counted.estoque_maximo,
    counted.fornecedor_id,
    counted.fornecedor_nome,
    counted.finalidade,
    counted.controla_estoque,
    counted.ativo,
    counted.atualizado_em,
    counted.localizacao,
    counted.abaixo_minimo
  from counted
  order by
    case when v_sort_key = 'id' and v_sort_dir = 'asc' then counted.item_id end asc,
    case when v_sort_key = 'id' and v_sort_dir = 'desc' then counted.item_id end desc,
    case when v_sort_key = 'codigo' and v_sort_dir = 'asc' then lower(counted.codigo_interno) end asc,
    case when v_sort_key = 'codigo' and v_sort_dir = 'desc' then lower(counted.codigo_interno) end desc,
    case when v_sort_key = 'nome' and v_sort_dir = 'asc' then lower(counted.item_nome) end asc,
    case when v_sort_key = 'nome' and v_sort_dir = 'desc' then lower(counted.item_nome) end desc,
    counted.item_id asc
  offset ((v_page - 1) * v_page_size)
  limit v_page_size;
end;
$function$;

comment on function public.search_estoque_itens(uuid, uuid, text, text, text, text, integer, boolean, text, boolean, boolean, boolean, integer, integer, text, text) is
  'Busca itens de estoque por codigo, barras ou nome (sem acento) apos validar o contexto e a permissao de estoque.';

-- 7. Relatorio de saldo ---------------------------------------------------------

create or replace function public.search_relatorio_estoque(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_busca text default null,
  p_fornecedor text default null,
  p_finalidade text default null,
  p_localizacao text default null,
  p_abaixo_minimo boolean default false,
  p_sem_fornecedor boolean default false,
  p_page integer default 1,
  p_page_size integer default 50,
  p_sort_key text default 'nome',
  p_sort_dir text default 'asc'
)
returns table(
  total_count bigint,
  item_id integer,
  codigo_interno text,
  item_nome text,
  unidade_medida text,
  quantidade_atual numeric,
  preco_unitario numeric,
  custo_medio numeric,
  estoque_minimo numeric,
  estoque_ideal numeric,
  estoque_maximo numeric,
  fornecedor_id integer,
  fornecedor_nome text,
  localizacao text,
  finalidade text,
  controla_estoque boolean,
  abaixo_minimo boolean
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
  v_fornecedor text := nullif(btrim(coalesce(p_fornecedor, '')), '');
  v_finalidade text := nullif(btrim(coalesce(p_finalidade, '')), '');
  v_localizacao text := nullif(btrim(coalesce(p_localizacao, '')), '');
  v_page integer := greatest(1, coalesce(p_page, 1));
  v_page_size integer := greatest(1, least(coalesce(p_page_size, 50), 500));
  v_sort_key text := lower(coalesce(p_sort_key, 'nome'));
  v_sort_dir text := lower(coalesce(p_sort_dir, 'asc'));
  v_busca_norm text := public.fn_texto_busca(v_busca);
  v_fornecedor_busca text := public.fn_texto_busca(v_fornecedor);
  v_localizacao_busca text := public.fn_texto_busca(v_localizacao);
begin
  if auth.uid() is null
     or p_tenant_id is null
     or p_empresa_id is null
     or public.current_tenant_id() is distinct from p_tenant_id
     or public.current_empresa_id__by_tenant(p_tenant_id) is distinct from p_empresa_id
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or not (
       public.can('estoque', 'read', p_tenant_id)
       or public.can('estoque', 'write', p_tenant_id)
     ) then
    raise exception 'estoque_report_access_denied';
  end if;

  if v_sort_key not in ('id', 'codigo', 'nome') then
    v_sort_key := 'nome';
  end if;
  if v_sort_dir not in ('asc', 'desc') then
    v_sort_dir := 'asc';
  end if;

  return query
  with filtered as (
    select
      i.id as item_id,
      i.codigo_interno::text as codigo_interno,
      i.nome::text as item_nome,
      i.unidade_medida::text as unidade_medida,
      coalesce(e.quantidade_atual, 0)::numeric as quantidade_atual,
      i.preco_unitario::numeric as preco_unitario,
      i.custo_medio::numeric as custo_medio,
      i.estoque_minimo::numeric as estoque_minimo,
      i.estoque_ideal::numeric as estoque_ideal,
      i.estoque_maximo::numeric as estoque_maximo,
      i.fornecedor_id,
      f.nome::text as fornecedor_nome,
      e.localizacao::text as localizacao,
      i.finalidade::text as finalidade,
      i.controla_estoque,
      (coalesce(e.quantidade_atual, 0) < coalesce(i.estoque_minimo, 0)) as abaixo_minimo
    from public.itens i
    left join public.estoque e
      on e.tenant_id = i.tenant_id
     and e.empresa_id = i.empresa_id
     and e.item_id = i.id
    left join public.fornecedores f
      on f.tenant_id = i.tenant_id
     and f.empresa_id = i.empresa_id
     and f.id = i.fornecedor_id
    where i.tenant_id = p_tenant_id
      and i.empresa_id = p_empresa_id
      and i.tipo = 'produto'
      and i.controla_estoque is true
      and (
        v_busca is null
        or public.fn_texto_busca(i.codigo_interno::text) like '%' || v_busca_norm || '%'
        or public.fn_texto_busca(i.codigo_barras::text) like '%' || v_busca_norm || '%'
        or public.fn_texto_busca(i.nome::text) like '%' || v_busca_norm || '%'
      )
      and (v_finalidade is null or i.finalidade::text = v_finalidade)
      and (v_localizacao is null or public.fn_texto_busca(e.localizacao::text) like '%' || v_localizacao_busca || '%')
      and (
        (v_fornecedor is null and not coalesce(p_sem_fornecedor, false))
        or (v_fornecedor is null and coalesce(p_sem_fornecedor, false) and i.fornecedor_id is null)
        or (v_fornecedor is not null and public.fn_texto_busca(f.nome::text) like '%' || v_fornecedor_busca || '%')
        or (v_fornecedor is not null and coalesce(p_sem_fornecedor, false) and i.fornecedor_id is null)
      )
      and (
        coalesce(p_abaixo_minimo, false)
        or coalesce(e.quantidade_atual, 0) > 0
      )
      and (
        not coalesce(p_abaixo_minimo, false)
        or coalesce(e.quantidade_atual, 0) < coalesce(i.estoque_minimo, 0)
      )
  ), counted as (
    select count(*) over () as total_count, filtered.*
    from filtered
  )
  select
    counted.total_count,
    counted.item_id,
    counted.codigo_interno,
    counted.item_nome,
    counted.unidade_medida,
    counted.quantidade_atual,
    counted.preco_unitario,
    counted.custo_medio,
    counted.estoque_minimo,
    counted.estoque_ideal,
    counted.estoque_maximo,
    counted.fornecedor_id,
    counted.fornecedor_nome,
    counted.localizacao,
    counted.finalidade,
    counted.controla_estoque,
    counted.abaixo_minimo
  from counted
  order by
    case when v_sort_key = 'id' and v_sort_dir = 'asc' then counted.item_id end asc,
    case when v_sort_key = 'id' and v_sort_dir = 'desc' then counted.item_id end desc,
    case when v_sort_key = 'codigo' and v_sort_dir = 'asc' then lower(counted.codigo_interno) end asc,
    case when v_sort_key = 'codigo' and v_sort_dir = 'desc' then lower(counted.codigo_interno) end desc,
    case when v_sort_key = 'nome' and v_sort_dir = 'asc' then lower(counted.item_nome) end asc,
    case when v_sort_key = 'nome' and v_sort_dir = 'desc' then lower(counted.item_nome) end desc,
    counted.item_id asc
  offset ((v_page - 1) * v_page_size)
  limit v_page_size;
end;
$function$;

comment on function public.search_relatorio_estoque(uuid, uuid, text, text, text, text, boolean, boolean, integer, integer, text, text) is
  'Relatorio de saldo consolidado, sempre escopado ao tenant e empresa ativos. Busca textual ignora acento.';

notify pgrst, 'reload schema';

commit;
