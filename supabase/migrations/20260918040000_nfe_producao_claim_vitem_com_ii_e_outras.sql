-- Segunda trava do claim de producao na NF-e de entrada de importacao (18/09/2026): o vItem de
-- cada item leva, alem do IPI, o II (vII) e o vOutro do item (o ICMS por dentro), que o montador
-- soma no valor_total_item (NT 2025.002-RTC: vNFTot = soma dos vItem). O congelamento continua
-- sobre a solicitacao (quantidade, preco e desconto); II e vOutro vem do proprio payload e o total
-- ja e conferido contra o congelado (valor_total_ii e valor_outras_despesas da solicitacao).
do $$
declare
  v_def text;
  v_anchor constant text := '+ coalesce(f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, ''ipi_valor''), 0), 2)';
  v_novo constant text := E'+ coalesce(f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, ''ipi_valor''), 0)\n'
    || E'             -- Importacao (18/09/2026): vItem = vProd + vIPI + vII + vOutro do item.\n'
    || E'             + coalesce(f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, ''ii_valor''), 0)\n'
    || E'             + coalesce(f.fn_perfil_operacao_jsonb_numeric_seguro(px.item, ''valor_outras_despesas''), 0), 2)';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'f' and p.proname = 'fn_nfe_producao_preparar_e_claimar';
  if v_def is null then
    raise exception 'f.fn_nfe_producao_preparar_e_claimar nao encontrada';
  end if;
  if position('''ii_valor''' in v_def) > 0 then
    raise notice 'fn_nfe_producao_preparar_e_claimar ja soma o II no vItem; nada a fazer';
    return;
  end if;
  if (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor) <> 1 then
    raise exception 'ancora do vItem nao encontrada (ou repetida) em fn_nfe_producao_preparar_e_claimar';
  end if;
  v_def := replace(v_def, v_anchor, v_novo);
  execute v_def;
end $$;

-- Reversao: recriar fn_nfe_producao_preparar_e_claimar sem os dois termos (ii_valor e
-- valor_outras_despesas) do vItem esperado.
