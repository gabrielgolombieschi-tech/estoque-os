-- Coluna de nome sem acento em itens e fornecedores.
--
-- As telas que filtram por RPC ja estao resolvidas. Sobraram as que montam o
-- filtro no navegador e mandam pro PostgREST — modal de item da Baixa de OS,
-- Itens > Pesos, Itens > Imprimir, Estoque > Ajuste de nome, o modal de item
-- dos Conjuntos e o caminho legado do orcamento. Nessas, o filtro vai como
-- `nome=ilike.%termo%`, e o PostgREST nao aceita funcao no filtro: nao ha onde
-- encaixar fn_texto_busca.
--
-- Entao o banco guarda o nome ja normalizado numa coluna gerada, e a tela passa
-- a filtrar por ela com o termo tambem normalizado (lib/text.ts textoBusca, a
-- mesma regra). Coluna gerada e nao gatilho porque o Postgres garante que ela
-- nunca sai de sincronia com o nome — nao existe caminho de escrita que a
-- esqueca, nem no import de XML nem em correcao manual.
--
-- So `nome` precisa disso: codigo interno e codigo de barras sao alfanumericos
-- e nao tem acento, entao o ilike deles continua como esta.

begin;

set local lock_timeout = '10s';
-- O acrescimo reescreve a tabela inteira; itens tem ~10 mil linhas, e questao
-- de segundos, mas o timeout padrao fica curto demais se houver concorrencia.
set local statement_timeout = '600s';
set local role postgres;

alter table public.itens
  add column if not exists nome_busca text
  generated always as (public.fn_texto_busca(nome::text)) stored;

comment on column public.itens.nome_busca is
  'Nome sem acento e em maiusculas (fn_texto_busca). So para filtro de busca — nao editar, e coluna gerada.';

alter table public.fornecedores
  add column if not exists nome_busca text
  generated always as (public.fn_texto_busca(nome::text)) stored;

comment on column public.fornecedores.nome_busca is
  'Nome sem acento e em maiusculas (fn_texto_busca). So para filtro de busca — nao editar, e coluna gerada.';

notify pgrst, 'reload schema';

commit;
