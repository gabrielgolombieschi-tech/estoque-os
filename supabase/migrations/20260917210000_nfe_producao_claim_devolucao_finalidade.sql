-- Comparacao producao x homologacao: na devolucao de compra a finalidade tambem muda.
--
-- A SEFAZ de homologacao recusa a devolucao (finNFe 4) com 321 "nao possui documento fiscal
-- referenciado" tanto com a chave real de entrada (que ela nao conhece) quanto com uma NF-e
-- de homologacao da propria empresa ou a origem como nota modelo 1 (17/09/2026, NF-e 121481/3
-- da Acos America). A nota de teste sai entao como finNFe 1 e sem NFref; a real, finNFe 4 com
-- a chave. f.fn_nfe_producao_preparar_e_claimar ja ignora notas_referenciadas (20260917120000);
-- passa a ignorar finalidade_emissao SO quando a natureza e a da devolucao. O montador
-- (validarPayloadProducaoContraHomologacao) tem o mesmo criterio.

do $$
declare
  v_def text;
  v_antes constant text := 'array[''data_emissao'',''data_entrada_saida'',''nome_destinatario'',''ambiente'',''ambiente_emissao'',''notas_referenciadas'']::text[]';
  v_depois constant text := '(array[''data_emissao'',''data_entrada_saida'',''nome_destinatario'',''ambiente'',''ambiente_emissao'',''notas_referenciadas''] || case when p_payload->>''natureza_operacao'' = ''DEVOLUCAO DE COMPRA PARA INDUSTRIALIZACAO'' then array[''finalidade_emissao''] else ''{}''::text[] end)::text[]';
  v_n int;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'f' and p.proname = 'fn_nfe_producao_preparar_e_claimar';
  if v_def is null then
    raise exception 'f.fn_nfe_producao_preparar_e_claimar nao encontrada';
  end if;
  if position('finalidade_emissao' in v_def) > 0 then
    raise notice 'fn_nfe_producao_preparar_e_claimar ja trata finalidade_emissao da devolucao';
    return;
  end if;
  v_n := (length(v_def) - length(replace(v_def, v_antes, ''))) / length(v_antes);
  if v_n <> 2 then
    raise exception 'esperava 2 ocorrencias da lista de chaves toleradas, achou %', v_n;
  end if;
  v_def := replace(v_def, v_antes, v_depois);
  execute v_def;
end $$;
