-- Devolucao de compra: a referencia de homologacao e a NF-e da empresa para ela mesma, e a
-- finalidade volta a ser congelada entre homologacao e producao.
--
-- O que a SEFAZ de homologacao ensinou em 17/09/2026 (NF-e 121481/3 da Acos America):
--   - finNFe 4 sem NFref, com a chave real de entrada (que ela nao conhece), com uma NF-e de
--     homologacao de VENDA da empresa (destinatario outro) ou com a origem como nota modelo 1
--     (refNF): rejeicao 321 "nao possui documento fiscal referenciado";
--   - finNFe 1 com CFOP 5201: rejeicao 328 "CFOP de devolucao para NF-e que nao e de devolucao";
--   - finNFe 4 referenciando uma NF-e de homologacao emitida pela empresa PARA ELA MESMA
--     (remessa para conserto 5915, NF-e 2/64, chave 42260913671448000189550020000000641164283751):
--     e o caso que passa.
--
-- Entao:
--   1. devolucao_compra.chave_referencia_homologacao passa a ser a ultima NF-e AUTORIZADA em
--      homologacao cujo destinatario e a propria empresa (mesmo CNPJ), nao a ultima qualquer;
--   2. a tolerancia de finalidade_emissao na comparacao producao x homologacao (20260917210000,
--      da tentativa com finNFe 1) e desfeita: os dois ambientes saem com finNFe 4.

do $$
declare
  v_def text;
  v_antes constant text := E'        ''chave_referencia_homologacao'', (\n          select e.chave_acesso from f.documento_fiscal_emissao e\n           where e.tenant_id = v_scope.tenant_id and e.empresa_id = v_scope.empresa_id\n             and e.ambiente = ''HOMOLOGACAO'' and e.status = ''AUTORIZADA'' and e.chave_acesso ~ ''^[0-9]{44}$''\n           order by e.autorizado_em desc nulls last, e.updated_at desc limit 1)';
  v_depois constant text := E'        ''chave_referencia_homologacao'', (\n          -- NF-e de homologacao da empresa para ela mesma: a unica referencia que a SEFAZ de\n          -- teste aceita numa devolucao (finNFe 4).\n          select e.chave_acesso from f.documento_fiscal_emissao e\n            join f.documento_fiscal d on d.id = e.documento_fiscal_id\n            join public.clientes c on c.id = d.cliente_id\n           where e.tenant_id = v_scope.tenant_id and e.empresa_id = v_scope.empresa_id\n             and e.ambiente = ''HOMOLOGACAO'' and e.status = ''AUTORIZADA'' and e.chave_acesso ~ ''^[0-9]{44}$''\n             and regexp_replace(coalesce(c.documento, ''''), ''[^0-9]'', '''', ''g'') = regexp_replace(v_empresa.cnpj, ''[^0-9]'', '''', ''g'')\n           order by e.autorizado_em desc nulls last, e.updated_at desc limit 1)';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'f' and p.proname = 'fn_devolucao_compra_nfe_criar';
  if v_def is null then
    raise exception 'f.fn_devolucao_compra_nfe_criar nao encontrada';
  end if;
  if position('para ela mesma' in v_def) > 0 then
    raise notice 'fn_devolucao_compra_nfe_criar ja usa a referencia propria; nada a fazer';
  else
    if position(v_antes in v_def) = 0 then
      raise exception 'ancora da referencia de homologacao nao encontrada em fn_devolucao_compra_nfe_criar';
    end if;
    v_def := replace(v_def, v_antes, v_depois);
    execute v_def;
  end if;
end $$;

do $$
declare
  v_def text;
  v_antes constant text := '(array[''data_emissao'',''data_entrada_saida'',''nome_destinatario'',''ambiente'',''ambiente_emissao'',''notas_referenciadas''] || case when p_payload->>''natureza_operacao'' = ''DEVOLUCAO DE COMPRA PARA INDUSTRIALIZACAO'' then array[''finalidade_emissao''] else ''{}''::text[] end)::text[]';
  v_depois constant text := 'array[''data_emissao'',''data_entrada_saida'',''nome_destinatario'',''ambiente'',''ambiente_emissao'',''notas_referenciadas'']::text[]';
  v_n int;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'f' and p.proname = 'fn_nfe_producao_preparar_e_claimar';
  if v_def is null then
    raise exception 'f.fn_nfe_producao_preparar_e_claimar nao encontrada';
  end if;
  v_n := (length(v_def) - length(replace(v_def, v_antes, ''))) / length(v_antes);
  if v_n = 0 then
    raise notice 'fn_nfe_producao_preparar_e_claimar ja esta estrita na finalidade; nada a fazer';
    return;
  end if;
  if v_n <> 2 then
    raise exception 'esperava 2 ocorrencias da lista tolerante, achou %', v_n;
  end if;
  v_def := replace(v_def, v_antes, v_depois);
  execute v_def;
end $$;
