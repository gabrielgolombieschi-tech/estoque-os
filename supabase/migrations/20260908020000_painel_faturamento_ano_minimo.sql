-- O painel de faturamento do app passa a declarar de que ano em diante o dado
-- do banco vale.
--
-- O modulo fiscal so comecou a capturar nota em setembro de 2025, e mesmo esses
-- meses vieram pela metade: set/2025 tem R$ 33.711 no banco contra R$ 1.001.878
-- na planilha do grupo; dez/2025 tem R$ 1.712.690 contra R$ 2.209.308. O ano de
-- 2025 inteiro aparecia como R$ 2,26 milhoes quando foram R$ 11,84 milhoes.
-- Nao era numero incompleto, era numero errado com cara de certo.
--
-- Importar a planilha nao resolveria: aquele historico e do grupo (SEGAU +
-- SGU) e nao se divide por empresa — tanto que o analitico web o descarta
-- assim que alguem filtra uma empresa. E o painel do app e por empresa, por
-- decisao de Gabriel. Entao a saida honesta e nao mostrar o que nao se sabe.
--
-- O limite vem daqui, e nao da tela, para existir um lugar so onde essa data
-- mora. Se um dia o historico for importado com separacao por empresa, muda o
-- valor abaixo e o aplicativo acompanha sozinho.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

do $patch_ano_minimo$
declare
  v_definition text;
  v_declara_needle text := $needle$  v_anos jsonb;
begin$needle$;
  v_declara_replacement text := $replacement$  v_anos jsonb;
  -- Primeiro ano em que o banco e a fonte do faturamento. Antes disso o
  -- historico e de planilha, do grupo, e nao cabe neste painel.
  v_ano_minimo constant integer := 2026;
begin$replacement$;
  v_retorno_needle text := $needle$  return jsonb_build_object(
    'ano', v_ano,
    'mes', v_mes,$needle$;
  v_retorno_replacement text := $replacement$  return jsonb_build_object(
    'ano', v_ano,
    'ano_minimo', v_ano_minimo,
    'mes', v_mes,$replacement$;
begin
  select pg_get_functiondef('public.app_faturamento_painel(integer,integer)'::regprocedure)
    into v_definition;

  if position(v_declara_needle in v_definition) = 0 then
    raise exception 'painel_faturamento_declaracao_nao_encontrada';
  end if;
  if position(v_retorno_needle in v_definition) = 0 then
    raise exception 'painel_faturamento_retorno_nao_encontrado';
  end if;

  v_definition := replace(v_definition, v_declara_needle, v_declara_replacement);
  v_definition := replace(v_definition, v_retorno_needle, v_retorno_replacement);
  execute v_definition;
end;
$patch_ano_minimo$;

do $assert$
begin
  if position('ano_minimo' in pg_get_functiondef('public.app_faturamento_painel(integer,integer)'::regprocedure)) = 0 then
    raise exception 'painel_sem_ano_minimo';
  end if;
end;
$assert$;

notify pgrst, 'reload schema';

commit;
