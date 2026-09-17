-- Devolucao de compra: referencia item a item (DFeReferenciado) e a nota de teste com a propria
-- empresa como destinataria.
--
-- NT 2025.002-RTC (v1.40/1.50, em producao desde 01/09/2026): a NF-e de devolucao (finNFe 4)
-- referencia a nota de origem ITEM A ITEM, no grupo DFeReferenciado de cada det (chaveAcesso +
-- nItem). So o NFref do cabecalho nao atende mais (rejeicao 321, regra VC02-14). Alem disso o
-- destinatario da devolucao tem de ser o emitente da nota referenciada (VC02-50).
--
-- Em homologacao a SEFAZ nao conhece a nota real do fornecedor. A nota de teste referencia
-- entao a NF-e de homologacao da empresa para ela mesma (remessa 5915 Segau -> Segau, NF-e
-- 2/64 de 17/09/2026) e, por VC02-50, sai com a propria empresa como destinataria. A nota real
-- leva a chave de entrada, o nItem de origem de cada item e o fornecedor. A comparacao
-- producao x homologacao (f.fn_nfe_producao_preparar_e_claimar) passa a usar
-- f.fn_nfe_payload_comparavel, que tira essas diferencas so nesta natureza.

-- 1. Snapshot: nItem de origem por item e o nItem da nota de referencia de homologacao.
do $$
declare
  v_def text;
  v_anchor_decl constant text := E'  v_prev record;\nbegin';
  v_decl constant text := E'  v_prev record;\n  v_ref_hom record;\nbegin';
  v_anchor_texto constant text := E'  -- Frases dos itens para o infCpl';
  v_ref constant text := E'  -- Nota de referencia da homologacao: NF-e de homologacao da empresa para ela mesma (a unica\n  -- que a SEFAZ de teste aceita numa devolucao) e o primeiro item dela.\n  select e.chave_acesso, e.documento_fiscal_id,\n         (select coalesce(min(di.item_n), 1) from f.documento_fiscal_item di where di.documento_fiscal_id = e.documento_fiscal_id) as nitem\n    into v_ref_hom\n  from f.documento_fiscal_emissao e\n    join f.documento_fiscal d on d.id = e.documento_fiscal_id\n    join public.clientes c on c.id = d.cliente_id\n   where e.tenant_id = v_scope.tenant_id and e.empresa_id = v_scope.empresa_id\n     and e.ambiente = ''HOMOLOGACAO'' and e.status = ''AUTORIZADA'' and e.chave_acesso ~ ''^[0-9]{44}$''\n     and regexp_replace(coalesce(c.documento, ''''), ''[^0-9]'', '''', ''g'') = regexp_replace(v_empresa.cnpj, ''[^0-9]'', '''', ''g'')\n   order by e.autorizado_em desc nulls last, e.updated_at desc limit 1;\n\n  -- Frases dos itens para o infCpl';
  v_anchor_snap constant text := E'        ''chave_referencia_homologacao'', (\n          -- NF-e de homologacao da empresa para ela mesma: a unica referencia que a SEFAZ de\n          -- teste aceita numa devolucao (finNFe 4).\n          select e.chave_acesso from f.documento_fiscal_emissao e\n            join f.documento_fiscal d on d.id = e.documento_fiscal_id\n            join public.clientes c on c.id = d.cliente_id\n           where e.tenant_id = v_scope.tenant_id and e.empresa_id = v_scope.empresa_id\n             and e.ambiente = ''HOMOLOGACAO'' and e.status = ''AUTORIZADA'' and e.chave_acesso ~ ''^[0-9]{44}$''\n             and regexp_replace(coalesce(c.documento, ''''), ''[^0-9]'', '''', ''g'') = regexp_replace(v_empresa.cnpj, ''[^0-9]'', '''', ''g'')\n           order by e.autorizado_em desc nulls last, e.updated_at desc limit 1)';
  v_snap constant text := E'        ''chave_referencia_homologacao'', v_ref_hom.chave_acesso,\n        ''referencia_homologacao_nitem'', v_ref_hom.nitem,\n        -- nItem de origem de cada item devolvido (DFeReferenciado da nota real).\n        ''itens'', (select jsonb_agg(jsonb_build_object(''ordem'', i.ordem, ''nitem'', i.origem_nitem, ''codigo'', i.codigo) order by i.ordem)\n                    from f.operacao_fiscal_item i where i.operacao_id = v_op_id)';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'f' and p.proname = 'fn_devolucao_compra_nfe_criar';
  if v_def is null then
    raise exception 'f.fn_devolucao_compra_nfe_criar nao encontrada';
  end if;
  if position('referencia_homologacao_nitem' in v_def) > 0 then
    raise notice 'fn_devolucao_compra_nfe_criar ja grava o DFeReferenciado; nada a fazer';
  else
    if position(v_anchor_decl in v_def) = 0 or position(v_anchor_texto in v_def) = 0 or position(v_anchor_snap in v_def) = 0 then
      raise exception 'ancora nao encontrada em fn_devolucao_compra_nfe_criar (decl %, texto %, snap %)',
        position(v_anchor_decl in v_def) > 0, position(v_anchor_texto in v_def) > 0, position(v_anchor_snap in v_def) > 0;
    end if;
    v_def := replace(v_def, v_anchor_decl, v_decl);
    v_def := replace(v_def, v_anchor_texto, v_ref);
    v_def := replace(v_def, v_anchor_snap, v_snap);
    execute v_def;
  end if;
end $$;

-- 2. O que e comparavel entre a nota de homologacao e a real.
create or replace function f.fn_nfe_payload_comparavel(p_payload jsonb)
returns jsonb
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select case
    when p_payload->>'natureza_operacao' = 'DEVOLUCAO DE COMPRA PARA INDUSTRIALIZACAO' then
      -- Devolucao: a nota de teste tem a propria empresa como destinataria e referencia (no
      -- cabecalho e em cada item) a NF-e de homologacao da empresa; a real, o fornecedor e a
      -- nota de entrada. Tudo o mais — itens, impostos, totais, transporte, pagamento —
      -- continua congelado.
      jsonb_set(
        p_payload - array[
          'data_emissao', 'data_entrada_saida', 'nome_destinatario', 'ambiente', 'ambiente_emissao', 'notas_referenciadas',
          'cnpj_destinatario', 'cpf_destinatario', 'inscricao_estadual_destinatario', 'indicador_inscricao_estadual_destinatario',
          'logradouro_destinatario', 'numero_destinatario', 'complemento_destinatario', 'bairro_destinatario', 'municipio_destinatario',
          'codigo_municipio_destinatario', 'uf_destinatario', 'cep_destinatario', 'telefone_destinatario', 'local_destino'
        ]::text[],
        '{items}',
        coalesce((select jsonb_agg(i - 'chave_acesso_dfe_referenciado' - 'numero_item_dfe_referenciado')
                    from jsonb_array_elements(coalesce(p_payload->'items', '[]'::jsonb)) i), '[]'::jsonb)
      )
    else
      p_payload - array['data_emissao', 'data_entrada_saida', 'nome_destinatario', 'ambiente', 'ambiente_emissao', 'notas_referenciadas']::text[]
  end
$$;
revoke all on function f.fn_nfe_payload_comparavel(jsonb) from public, anon;
grant execute on function f.fn_nfe_payload_comparavel(jsonb) to authenticated, service_role;

do $$
declare
  v_def text;
  v_antes_hom constant text := '(v_homologacao_payload - array[''data_emissao'',''data_entrada_saida'',''nome_destinatario'',''ambiente'',''ambiente_emissao'',''notas_referenciadas'']::text[])';
  v_antes_prod constant text := '(p_payload - array[''data_emissao'',''data_entrada_saida'',''nome_destinatario'',''ambiente'',''ambiente_emissao'',''notas_referenciadas'']::text[])';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'f' and p.proname = 'fn_nfe_producao_preparar_e_claimar';
  if v_def is null then
    raise exception 'f.fn_nfe_producao_preparar_e_claimar nao encontrada';
  end if;
  if position('fn_nfe_payload_comparavel' in v_def) > 0 then
    raise notice 'fn_nfe_producao_preparar_e_claimar ja usa fn_nfe_payload_comparavel';
    return;
  end if;
  if position(v_antes_hom in v_def) = 0 or position(v_antes_prod in v_def) = 0 then
    raise exception 'ancoras da comparacao nao encontradas em fn_nfe_producao_preparar_e_claimar';
  end if;
  v_def := replace(v_def, v_antes_hom, 'f.fn_nfe_payload_comparavel(v_homologacao_payload)');
  v_def := replace(v_def, v_antes_prod, 'f.fn_nfe_payload_comparavel(p_payload)');
  execute v_def;
end $$;
