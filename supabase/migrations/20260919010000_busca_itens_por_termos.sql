-- Busca de itens por todas as palavras, independentemente da ordem, caixa ou acento.
-- A normalizacao de decimais e exclusiva dos itens: fn_texto_busca e as colunas
-- que ja dependem dela permanecem inalteradas. Os filtros sao executados no
-- banco, antes da contagem, paginacao ou limite, inclusive para exportacoes.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

create or replace function public.fn_item_busca_normalizar(p_texto text)
returns text
language sql
immutable
parallel safe
set search_path to 'pg_catalog'
as $function$
  select btrim(regexp_replace(
    regexp_replace(public.fn_texto_busca(p_texto), '([0-9]),(?=[0-9])', '\1.', 'g'),
    '[[:space:]]+', ' ', 'g'
  ));
$function$;

create or replace function public.fn_item_busca_corresponde(p_texto text, p_busca text)
returns boolean
language sql
immutable
parallel safe
set search_path to 'pg_catalog'
as $function$
  select not exists (
    select 1
    from regexp_split_to_table(public.fn_item_busca_normalizar(p_busca), '[[:space:]]+') as termo(valor)
    where termo.valor <> ''
      and strpos(public.fn_item_busca_normalizar(p_texto), termo.valor) = 0
  );
$function$;

comment on function public.fn_item_busca_normalizar(text) is
  'Busca de item sem acento/caixa, espacos normalizados e virgula decimal equivalente a ponto.';
comment on function public.fn_item_busca_corresponde(text, text) is
  'Todos os termos da busca devem ocorrer literalmente no texto, em qualquer ordem. Busca vazia corresponde a qualquer texto.';
revoke all on function public.fn_item_busca_normalizar(text), public.fn_item_busca_corresponde(text, text) from public, anon;
grant execute on function public.fn_item_busca_normalizar(text), public.fn_item_busca_corresponde(text, text) to authenticated, service_role;

-- || e coalesce mantem a expressao immutable (concat_ws nao e immutable).
-- Campos separados preservam o significado de filtros exclusivos por nome.
alter table public.itens
  add column if not exists busca_item text generated always as (
    public.fn_item_busca_normalizar(
      coalesce(id::text, '') || ' ' || coalesce(codigo_interno::text, '') || ' ' ||
      coalesce(codigo_barras::text, '') || ' ' || coalesce(nome::text, '') || ' ' ||
      coalesce(fabricante::text, '')
    )
  ) stored,
  add column if not exists nome_item_busca text generated always as (
    public.fn_item_busca_normalizar(nome::text)
  ) stored;
comment on column public.itens.busca_item is 'Texto gerado para busca por termos em ID, codigos, nome e fabricante.';
comment on column public.itens.nome_item_busca is 'Nome gerado para busca por termos, sem acento/caixa e com decimal normalizado.';

-- Reescreve apenas os predicados das assinaturas existentes. Mantem escopos,
-- permissoes, retornos, grants, ordenacao e comparacoes de codigo numerico exato.
-- Ausencia ou duplicacao de um trecho esperado aborta a transacao inteira.
do $rewrite$
declare
  v_trocas text[] := array[
    array[
      'public.search_orcamento_itens(uuid, uuid, text, text, integer)',
      $before$public.fn_texto_busca(i.nome::text) like '%'||v_term_busca||'%'
            or public.fn_texto_busca(i.codigo_interno::text) like '%'||v_term_busca||'%'
            or public.fn_texto_busca(i.fabricante::text) like '%'||v_term_busca||'%'$before$,
      $after$public.fn_item_busca_corresponde(i.busca_item, v_term)$after$
    ],
    array[
      'public.search_os_itens(uuid, uuid, text, text, boolean, integer)',
      $before$public.fn_texto_busca(i.nome::text) like '%' || v_term_busca || '%'
          or public.fn_texto_busca(i.codigo_interno::text) like '%' || v_term_busca || '%'
          or public.fn_texto_busca(i.fabricante::text) like '%' || v_term_busca || '%'$before$,
      $after$public.fn_item_busca_corresponde(i.busca_item, v_term)$after$
    ],
    array[
      'public.search_cadastro_itens(uuid, uuid, integer, text, text, text, text, text, boolean, integer, integer, text, text, boolean)',
      $before$public.fn_texto_busca(i.nome::text) like '%' || v_produto_busca || '%'$before$,
      $after$public.fn_item_busca_corresponde(i.nome_item_busca, v_produto)$after$
    ],
    array[
      'public.search_estoque_itens(uuid, uuid, text, text, text, text, integer, boolean, text, boolean, boolean, boolean, integer, integer, text, text)',
      $before$public.fn_texto_busca(i.codigo_interno::text) like '%' || v_busca_norm || '%'
        or public.fn_texto_busca(i.codigo_barras::text) like '%' || v_busca_norm || '%'
        or public.fn_texto_busca(i.nome::text) like '%' || v_busca_norm || '%'$before$,
      $after$public.fn_item_busca_corresponde(i.busca_item, v_busca)$after$
    ],
    array[
      'public.search_relatorio_estoque(uuid, uuid, text, text, text, text, boolean, boolean, integer, integer, text, text)',
      $before$public.fn_texto_busca(i.codigo_interno::text) like '%' || v_busca_norm || '%'
        or public.fn_texto_busca(i.codigo_barras::text) like '%' || v_busca_norm || '%'
        or public.fn_texto_busca(i.nome::text) like '%' || v_busca_norm || '%'$before$,
      $after$public.fn_item_busca_corresponde(i.busca_item, v_busca)$after$
    ],
    array[
      'public.search_estoque_itens(uuid, uuid, text, text, text, text, integer, boolean, text, boolean, boolean, boolean, integer, integer, text, text)',
      $before$public.fn_texto_busca(i.nome::text) like '%' || v_nome_busca || '%'$before$,
      $after$public.fn_item_busca_corresponde(i.nome_item_busca, v_nome)$after$
    ],
    array[
      'public.search_orcamento_conjuntos(uuid, uuid, text, integer)',
      $before$public.fn_texto_busca(v.codigo) like '%' || v_term_busca || '%'
      or public.fn_texto_busca(v.nome) like '%' || v_term_busca || '%'$before$,
      $after$public.fn_item_busca_corresponde(coalesce(v.codigo, '') || ' ' || coalesce(v.nome, ''), v_term)$after$
    ],
    array[
      'f.fn_faturamento_buscar_itens(uuid, uuid, text, integer)',
      $before$public.fn_texto_busca(i.codigo_interno::text) like '%' || public.fn_texto_busca(v_termo) || '%'
      or public.fn_texto_busca(i.codigo_barras::text) like '%' || public.fn_texto_busca(v_termo) || '%'
      or public.fn_texto_busca(i.nome::text) like '%' || public.fn_texto_busca(v_termo) || '%'$before$,
      $after$public.fn_item_busca_corresponde(i.busca_item, v_termo)$after$
    ],
    array[
      'f.fn_remessa_buscar_itens(text, integer)',
      $before$public.fn_texto_busca(i.codigo_interno::text) like '%' || public.fn_texto_busca(v_termo) || '%'
      or public.fn_texto_busca(i.codigo_barras::text) like '%' || public.fn_texto_busca(v_termo) || '%'
      or public.fn_texto_busca(i.nome::text) like '%' || public.fn_texto_busca(v_termo) || '%'$before$,
      $after$public.fn_item_busca_corresponde(i.busca_item, v_termo)$after$
    ],
    array[
      'public.home_busca_comando(text)',
      $before$public.fn_texto_busca(concat_ws(' ', i.codigo_interno, i.codigo_barras, i.codigo_fornecedor, i.nome, i.descricao)) like v_padrao$before$,
      $after$public.fn_item_busca_corresponde(concat_ws(' ', i.busca_item, i.codigo_fornecedor, i.descricao), v_termo)$after$
    ],
    array[
      'public.rel_entradas_periodo_consolidado(uuid, uuid, date, date, text, text, text, boolean, boolean)',
      $before$public.fn_texto_busca(i.nome::text) like ('%' || public.fn_texto_busca(p_busca_item) || '%')
        or public.fn_texto_busca(i.codigo_interno::text) like ('%' || public.fn_texto_busca(p_busca_item) || '%')$before$,
      $after$public.fn_item_busca_corresponde(i.busca_item, p_busca_item)$after$
    ],
    array[
      'public.fiscal_item_similares(integer, text, integer)',
      $before$select coalesce(array_agg(w), '{}'::text[])
  into v_busca
  from regexp_split_to_table(
         regexp_replace(upper(translate(coalesce(p_busca, ''),
           'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
           'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc')), '[^A-Z0-9]+', ' ', 'g'),
         ' ') as w
  where w <> '';$before$,
      $after$select coalesce(array_agg(w), '{}'::text[])
  into v_busca
  from regexp_split_to_table(public.fn_item_busca_normalizar(p_busca), '[[:space:]]+') as w
  where w <> '';$after$
    ],
    array[
      'public.fiscal_item_similares(integer, text, integer)',
      $before$upper(translate(coalesce(i.id::text, '') || ' ' || coalesce(i.codigo_interno, '') || ' ' || coalesce(i.nome, ''),
             'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
             'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc')) as texto_busca$before$,
      $after$i.busca_item as texto_busca$after$
    ],
    array[
      'public.fiscal_item_similares(integer, text, integer)',
      $before$not exists (select 1 from unnest(v_busca) w where strpos(b.texto_busca, w) = 0)$before$,
      $after$public.fn_item_busca_corresponde(b.texto_busca, p_busca)$after$
    ],
    array[
      'public.search_orcamento_itens(uuid, uuid, text, text, integer)',
      $before$public.fn_texto_busca(f.nome::text) like '%'||v_fornecedor_busca||'%'$before$,
      $after$public.fn_item_busca_corresponde(f.nome::text, v_fornecedor)$after$
    ],
    array[
      'public.search_os_itens(uuid, uuid, text, text, boolean, integer)',
      $before$public.fn_texto_busca(f.nome::text) like '%' || v_fornecedor_busca || '%'$before$,
      $after$public.fn_item_busca_corresponde(f.nome::text, v_fornecedor)$after$
    ],
    array[
      'public.search_cadastro_itens(uuid, uuid, integer, text, text, text, text, text, boolean, integer, integer, text, text, boolean)',
      $before$public.fn_texto_busca(f.nome::text) like '%' || v_fornecedor_busca || '%'$before$,
      $after$public.fn_item_busca_corresponde(f.nome::text, v_fornecedor)$after$
    ],
    array[
      'public.search_estoque_itens(uuid, uuid, text, text, text, text, integer, boolean, text, boolean, boolean, boolean, integer, integer, text, text)',
      $before$public.fn_texto_busca(f.nome::text) like '%' || v_fornecedor_busca || '%'$before$,
      $after$public.fn_item_busca_corresponde(f.nome::text, v_fornecedor)$after$
    ],
    array[
      'public.search_relatorio_estoque(uuid, uuid, text, text, text, text, boolean, boolean, integer, integer, text, text)',
      $before$public.fn_texto_busca(f.nome::text) like '%' || v_fornecedor_busca || '%'$before$,
      $after$public.fn_item_busca_corresponde(f.nome::text, v_fornecedor)$after$
    ]
  ];
  v_i integer;
  v_funcao text;
  v_de text;
  v_para text;
  v_def text;
begin
  for v_i in 1 .. array_length(v_trocas, 1) loop
    v_funcao := v_trocas[v_i][1];
    v_de := v_trocas[v_i][2];
    v_para := v_trocas[v_i][3];
    v_def := pg_get_functiondef(v_funcao::regprocedure);
    if position(v_de in v_def) = 0 then
      if position(v_para in v_def) > 0 then
        continue;
      end if;
      raise exception 'Busca de itens: trecho esperado ausente em %: %', v_funcao, v_de;
    end if;
    if position(v_de in substring(v_def from position(v_de in v_def) + length(v_de))) > 0 then
      raise exception 'Busca de itens: trecho esperado duplicado em %: %', v_funcao, v_de;
    end if;
    execute replace(v_def, v_de, v_para);
  end loop;
end;
$rewrite$;

notify pgrst, 'reload schema';
commit;
