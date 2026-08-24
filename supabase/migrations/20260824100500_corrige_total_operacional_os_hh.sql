-- Mantém o total da lista idêntico ao total exibido no detalhe:
-- Material + Mão de obra + Despesas + Impostos, inclusive para OS HH.

do $$
declare
  v_def text;
  v_trecho_anterior text := $trecho$
      when os.usa_relatorio_hh then
        coalesce(pedido_hh.pedido_hh, 0)
        + coalesce(itens.materiais, 0)
        + coalesce(itens.despesas, 0)
        + coalesce(mao_obra.mao_obra, 0)
      else$trecho$;
  v_trecho_corrigido text := $trecho$
      when os.usa_relatorio_hh then
        coalesce(itens.materiais, 0)
        + coalesce(itens.despesas, 0)
        + coalesce(mao_obra.mao_obra, 0)
        + coalesce(pedido_hh.pedido_hh, 0) * 0.15
      else$trecho$;
begin
  select pg_get_functiondef(
    'public.get_os_lista_custos_operacionais(uuid, uuid, integer[])'::regprocedure
  ) into v_def;

  if position(v_trecho_anterior in v_def) = 0 then
    raise exception 'Trecho esperado da função de custo operacional não foi encontrado.';
  end if;

  execute replace(v_def, v_trecho_anterior, v_trecho_corrigido);
end;
$$;
