-- Busca sem acento no que sobrou: app mobile, faturamento, busca global da Home
-- e o relatorio de entradas no periodo. Continuacao de 20260914100000.
--
-- Aqui a troca NAO copia a definicao de nenhum arquivo. Ela le a definicao que
-- esta no banco agora (pg_get_functiondef), troca o pedaco combinado e executa
-- de volta. Duas razoes:
--
--  1. Copiar de migration errou uma vez: peguei search_cadastro_itens do
--     baseline sem ver que producao ja estava numa versao com mais um
--     parametro, e o create or replace virou sobrecarga. Partindo da definicao
--     viva, a assinatura e sempre a certa e sobrecarga nao acontece.
--  2. Sao funcoes longas (home_busca_comando tem ~160 linhas) das quais so
--     interessam duas ou tres linhas. Reproduzir o resto so aumentaria a chance
--     de escrever errado.
--
-- Se o trecho procurado nao existir mais, a migration para e diz qual era —
-- melhor falhar aqui do que aplicar pela metade. Se o trecho ja estiver
-- trocado, ela segue em frente, entao rodar de novo nao quebra nada.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

do $rewrite$
declare
  -- {funcao, trecho de hoje, trecho novo}
  v_trocas text[] := array[
    -- App mobile: lancar material na OS.
    array[
      'public.app_buscar_materiais(text, text, integer)',
      'item.nome ilike ''%'' || v_termo || ''%''',
      'public.fn_texto_busca(item.nome::text) like ''%'' || public.fn_texto_busca(v_termo) || ''%'''
    ],
    array[
      'public.app_buscar_materiais(text, text, integer)',
      'item.descricao ilike ''%'' || v_termo || ''%''',
      'public.fn_texto_busca(item.descricao::text) like ''%'' || public.fn_texto_busca(v_termo) || ''%'''
    ],
    array[
      'public.app_buscar_materiais(text, text, integer)',
      'item.codigo_interno ilike ''%'' || v_termo || ''%''',
      'public.fn_texto_busca(item.codigo_interno::text) like ''%'' || public.fn_texto_busca(v_termo) || ''%'''
    ],
    array[
      'public.app_buscar_materiais(text, text, integer)',
      'item.fabricante ilike ''%'' || v_fabricante || ''%''',
      'public.fn_texto_busca(item.fabricante::text) like ''%'' || public.fn_texto_busca(v_fabricante) || ''%'''
    ],

    -- App mobile: aba Estoque.
    array[
      'public.app_consultar_estoque(text, boolean, integer, integer)',
      'item.codigo_interno ilike ''%'' || v_busca || ''%''',
      'public.fn_texto_busca(item.codigo_interno::text) like ''%'' || public.fn_texto_busca(v_busca) || ''%'''
    ],
    array[
      'public.app_consultar_estoque(text, boolean, integer, integer)',
      'item.codigo_barras ilike ''%'' || v_busca || ''%''',
      'public.fn_texto_busca(item.codigo_barras::text) like ''%'' || public.fn_texto_busca(v_busca) || ''%'''
    ],
    array[
      'public.app_consultar_estoque(text, boolean, integer, integer)',
      'item.nome ilike ''%'' || v_busca || ''%''',
      'public.fn_texto_busca(item.nome::text) like ''%'' || public.fn_texto_busca(v_busca) || ''%'''
    ],
    array[
      'public.app_consultar_estoque(text, boolean, integer, integer)',
      'item.descricao ilike ''%'' || v_busca || ''%''',
      'public.fn_texto_busca(item.descricao::text) like ''%'' || public.fn_texto_busca(v_busca) || ''%'''
    ],
    array[
      'public.app_consultar_estoque(text, boolean, integer, integer)',
      'item.fabricante ilike ''%'' || v_busca || ''%''',
      'public.fn_texto_busca(item.fabricante::text) like ''%'' || public.fn_texto_busca(v_busca) || ''%'''
    ],

    -- App mobile: fornecedor no cadastro de item.
    array[
      'public.app_itens_fornecedores(text, integer)',
      'f.nome ilike ''%'' || v_busca || ''%''',
      'public.fn_texto_busca(f.nome::text) like ''%'' || public.fn_texto_busca(v_busca) || ''%'''
    ],

    -- Faturamento: produto da NF-e a partir da OS.
    array[
      'f.fn_faturamento_buscar_itens(uuid, uuid, text, integer)',
      'i.codigo_interno ilike ''%'' || v_termo || ''%''',
      'public.fn_texto_busca(i.codigo_interno::text) like ''%'' || public.fn_texto_busca(v_termo) || ''%'''
    ],
    array[
      'f.fn_faturamento_buscar_itens(uuid, uuid, text, integer)',
      'i.codigo_barras ilike ''%'' || v_termo || ''%''',
      'public.fn_texto_busca(i.codigo_barras::text) like ''%'' || public.fn_texto_busca(v_termo) || ''%'''
    ],
    array[
      'f.fn_faturamento_buscar_itens(uuid, uuid, text, integer)',
      'i.nome ilike ''%'' || v_termo || ''%''',
      'public.fn_texto_busca(i.nome::text) like ''%'' || public.fn_texto_busca(v_termo) || ''%'''
    ],

    -- Home: busca global. O padrao e um so para as cinco consultas (OS,
    -- cliente, item, colaborador e nota), entao normalizar o padrao e cada
    -- concat_ws deixa as cinco sem acento de uma vez.
    array[
      'public.home_busca_comando(text)',
      'v_padrao := ''%'' || v_termo || ''%'';',
      'v_padrao := ''%'' || public.fn_texto_busca(v_termo) || ''%'';'
    ],
    array[
      'public.home_busca_comando(text)',
      'concat_ws('' '', os.numero_os, os.os_num::text, os.cliente_nome, os.descricao_servico, os.pedido_compra) ilike v_padrao',
      'public.fn_texto_busca(concat_ws('' '', os.numero_os, os.os_num::text, os.cliente_nome, os.descricao_servico, os.pedido_compra)) like v_padrao'
    ],
    array[
      'public.home_busca_comando(text)',
      'concat_ws('' '', c.id::text, c.nome, c.nome_fantasia, c.razao_social, c.documento, c.documento_norm) ilike v_padrao',
      'public.fn_texto_busca(concat_ws('' '', c.id::text, c.nome, c.nome_fantasia, c.razao_social, c.documento, c.documento_norm)) like v_padrao'
    ],
    array[
      'public.home_busca_comando(text)',
      'concat_ws('' '', i.codigo_interno, i.codigo_barras, i.codigo_fornecedor, i.nome, i.descricao) ilike v_padrao',
      'public.fn_texto_busca(concat_ws('' '', i.codigo_interno, i.codigo_barras, i.codigo_fornecedor, i.nome, i.descricao)) like v_padrao'
    ],
    array[
      'public.home_busca_comando(text)',
      'concat_ws('' '', c.nome, c.cargo, c.email) ilike v_padrao',
      'public.fn_texto_busca(concat_ws('' '', c.nome, c.cargo, c.email)) like v_padrao'
    ],
    array[
      'public.home_busca_comando(text)',
      'concat_ws('' '', df.numero, df.serie, df.chave_acesso) ilike v_padrao',
      'public.fn_texto_busca(concat_ws('' '', df.numero, df.serie, df.chave_acesso)) like v_padrao'
    ],

    -- Estoque > Relatorios > Entradas no periodo.
    array[
      'public.rel_entradas_periodo_consolidado(uuid, uuid, date, date, text, text, text, boolean, boolean)',
      'i.nome ilike (''%'' || p_busca_item || ''%'')',
      'public.fn_texto_busca(i.nome::text) like (''%'' || public.fn_texto_busca(p_busca_item) || ''%'')'
    ],
    array[
      'public.rel_entradas_periodo_consolidado(uuid, uuid, date, date, text, text, text, boolean, boolean)',
      'i.codigo_interno ilike (''%'' || p_busca_item || ''%'')',
      'public.fn_texto_busca(i.codigo_interno::text) like (''%'' || public.fn_texto_busca(p_busca_item) || ''%'')'
    ],
    array[
      'public.rel_entradas_periodo_consolidado(uuid, uuid, date, date, text, text, text, boolean, boolean)',
      'coalesce(f.nome, ''SEM FORNECEDOR'') ilike (p_fornecedor_prefix || ''%'')',
      'public.fn_texto_busca(coalesce(f.nome, ''SEM FORNECEDOR'')::text) like (public.fn_texto_busca(p_fornecedor_prefix) || ''%'')'
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
        raise notice 'Ja estava trocado em %: %', v_funcao, v_de;
        continue;
      end if;
      raise exception 'Nao encontrei o trecho esperado em %: %', v_funcao, v_de;
    end if;

    execute replace(v_def, v_de, v_para);
  end loop;
end;
$rewrite$;

-- Rede de seguranca: nenhuma funcao de busca pode ter mais de uma assinatura.
-- Foi exatamente assim que search_cadastro_itens quebrou.
do $sobrecarga$
declare
  v_nome text;
  v_qtd integer;
begin
  foreach v_nome in array array[
    'search_orcamento_itens', 'search_orcamento_conjuntos', 'search_os_itens',
    'search_cadastro_itens', 'search_estoque_itens', 'search_relatorio_estoque',
    'app_buscar_materiais', 'app_consultar_estoque', 'app_itens_fornecedores',
    'home_busca_comando', 'rel_entradas_periodo_consolidado', 'fn_texto_busca'
  ]
  loop
    select count(*) into v_qtd
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = v_nome;

    if v_qtd <> 1 then
      raise exception 'public.% tem % assinaturas; deveria ter exatamente 1.', v_nome, v_qtd;
    end if;
  end loop;
end;
$sobrecarga$;

notify pgrst, 'reload schema';

commit;
