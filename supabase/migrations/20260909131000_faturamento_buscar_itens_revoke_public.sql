-- Conserta o grant aberto por 20260909130000.
--
-- Aquela migration trocou o retorno de f.fn_faturamento_buscar_itens e, por isso,
-- teve de recriar a funcao com drop + create. O PostgreSQL concede EXECUTE a PUBLIC
-- em toda funcao nova, e o create de la nao revogou: a funcao ficou com PUBLIC,
-- authenticated, postgres e service_role, enquanto as irmas do schema (fn_os_notas,
-- fn_os_saldo_a_faturar, fn_os_pronta_para_faturada) tem apenas as tres ultimas.
--
-- A funcao e SECURITY DEFINER com row_security off; ela so nao vazou dados porque
-- checa tenant, empresa e f.has_finance_access() logo no inicio. Ainda assim o
-- grant fica igual ao das irmas.

revoke execute on function f.fn_faturamento_buscar_itens(uuid, uuid, text, integer) from public;
