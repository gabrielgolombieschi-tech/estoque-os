begin;

do $$
declare
  v_tenant_id constant uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';
  v_empresa_id constant uuid := 'f0e74f49-a127-46b4-901b-f7b37e43c690';
  v_nf_id constant bigint := 2004;
  v_os_id constant integer := 205;
  v_item_id constant integer := 45;
  v_mov_id bigint;
  v_quantidade_atual numeric;
  v_quantidade_correta numeric;
  v_delta numeric;
begin
  select sum(ni.qtd)
    into v_quantidade_correta
  from public.nf_entrada_itens ni
  where ni.tenant_id = v_tenant_id
    and ni.empresa_id = v_empresa_id
    and ni.nf_entrada_id = v_nf_id
    and ni.item_id = v_item_id;

  if abs(coalesce(v_quantidade_correta, 0) - 55.674) > 0.0005 then
    raise exception 'Quantidade correta do tubo na NF diverge do esperado: %', v_quantidade_correta;
  end if;

  select mov.id, mov.quantidade
    into v_mov_id, v_quantidade_atual
  from public.movimentacoes mov
  where mov.tenant_id = v_tenant_id
    and mov.empresa_id = v_empresa_id
    and mov.origem_nf_entrada_id = v_nf_id
    and mov.origem_os_id = v_os_id
    and mov.item_id = v_item_id
    and mov.tipo = 'saida'
  for update;

  if v_mov_id is null then
    raise exception 'Movimentacao duplicada do tubo nao foi localizada';
  end if;

  v_delta := v_quantidade_atual - v_quantidade_correta;

  if v_delta > 0.0005 then
    if not exists (
      select 1
      from public.movimentacoes mov
      where mov.tenant_id = v_tenant_id
        and mov.empresa_id = v_empresa_id
        and mov.origem_nf_entrada_id = v_nf_id
        and mov.origem_os_id = v_os_id
        and mov.item_id = v_item_id
        and mov.tipo = 'entrada'
        and mov.motivo = 'ESTORNO PARCIAL BAIXA DUPLICADA NF 2004 OS 206'
    ) then
      insert into public.movimentacoes(
        tenant_id, empresa_id, item_id, tipo, quantidade, motivo,
        realizado_por, data_movimentacao, origem_nf_entrada_id, origem_os_id
      ) values (
        v_tenant_id, v_empresa_id, v_item_id, 'entrada', v_delta,
        'ESTORNO PARCIAL BAIXA DUPLICADA NF 2004 OS 206',
        'gabriel@segau.com.br', now(), v_nf_id, v_os_id
      );
    end if;
  end if;

  update public.os_itens
     set quantidade = v_quantidade_correta,
         quantidade_baixada = v_quantidade_correta,
         valor_total = round(v_quantidade_correta * coalesce(valor_unitario, 0), 2),
         baixa_estoque = true
   where tenant_id = v_tenant_id
     and empresa_id = v_empresa_id
     and os_id = v_os_id
     and item_id = v_item_id
     and observacoes = 'Importacao XML NF 2004 [OS 206]';
end;
$$;

-- A funcao foi criada apenas para esta correcao assistida. Removela evita uma
-- reexecucao acidental depois que a NF, o pedido e a OS ja foram conciliados.
drop function if exists public.corrigir_reimportacao_nfe_521977(text);

commit;
