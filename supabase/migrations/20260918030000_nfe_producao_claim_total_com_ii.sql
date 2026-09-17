-- O claim de producao confere o vNF do payload contra produtos - desconto + frete + seguro +
-- outras despesas + IPI. A NF-e de entrada de importacao soma tambem o II (vII e parcela do vNF),
-- e a primeira emissao real da remessa UPS 1ZJ451C10441551106 (18/09/2026) parou com "Valor total
-- do payload nao fecha produtos/desconto/frete/seguro/despesas/IPI". O II entra na conta e fica
-- congelado: o do payload tem de ser o do snapshot da solicitacao (valor_total_ii).
do $$
declare
  v_def text;
  v_anchor constant text := 'v_total_esperado := round(v_produtos - v_desconto + v_frete + v_seguro + v_outros + v_ipi, 2);';
  v_novo constant text := E'-- II (importacao): parcela do vNF, congelada no snapshot da solicitacao (valor_total_ii).\n'
    || E'  if coalesce(f.fn_perfil_operacao_jsonb_numeric_seguro(p_payload, ''valor_total_ii''), 0)\n'
    || E'     is distinct from coalesce(nullif(v_sf.operacao_snapshot->>''valor_total_ii'', '''')::numeric, 0) then\n'
    || E'    raise exception using errcode = ''22023'', message = ''Valor total do II do payload diverge do congelado na solicitacao.'';\n'
    || E'  end if;\n'
    || E'  v_total_esperado := round(v_produtos - v_desconto + v_frete + v_seguro + v_outros + v_ipi\n'
    || E'    + coalesce(f.fn_perfil_operacao_jsonb_numeric_seguro(p_payload, ''valor_total_ii''), 0), 2);';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'f' and p.proname = 'fn_nfe_producao_preparar_e_claimar';
  if v_def is null then
    raise exception 'f.fn_nfe_producao_preparar_e_claimar nao encontrada';
  end if;
  if position('valor_total_ii' in v_def) > 0 then
    raise notice 'fn_nfe_producao_preparar_e_claimar ja soma o II; nada a fazer';
    return;
  end if;
  if (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor) <> 1 then
    raise exception 'ancora do total nao encontrada (ou repetida) em fn_nfe_producao_preparar_e_claimar';
  end if;
  v_def := replace(v_def, v_anchor, v_novo);
  execute v_def;
end $$;

-- Reversao: recriar fn_nfe_producao_preparar_e_claimar sem o trecho do valor_total_ii
-- (definicao anterior em 20260917230000 + baseline).
