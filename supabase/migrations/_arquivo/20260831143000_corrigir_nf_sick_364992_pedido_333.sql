-- Corrige a conciliacao parcial da NF 364992 da SICK com o Pedido 333 e a OS 282.
-- A NF/estoque foram gravados, mas a aprovacao financeira falhou porque a OS do
-- pedido nao foi repassada. Os itens foram baixados manualmente na OS em seguida.

do $$
declare
  v_tenant_id constant uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';
  v_empresa_id constant uuid := 'f0e74f49-a127-46b4-901b-f7b37e43c690';
  v_pedido_id constant uuid := 'e5f99f73-d6f3-4909-8027-a54195a2165f';
  v_nf_entrada_id constant bigint := 2221;
  v_os_id constant integer := 281;
  v_item_3666_pedido_id constant uuid := '165b4f7c-7b9b-4223-9c03-2f302ab557d7';
  v_item_3667_pedido_id constant uuid := 'e6758b37-d7ba-40ab-88be-734e27bbeab2';
  v_receb_item_3666_id constant uuid := '40138272-fe40-41d4-b78a-4935f87ee21c';
  v_receb_item_3667_id constant uuid := '50382ede-28c5-4e29-90fd-eb36cc1962e3';
  v_titulo_id uuid;
  v_motivo_compra_id uuid;
  v_aprovado_por uuid;
  v_count integer;
begin
  if not exists (
    select 1
    from m.pedido_compra p
    where p.id = v_pedido_id
      and p.tenant_id = v_tenant_id
      and p.empresa_id = v_empresa_id
      and p.codigo = 'PC-SEG-00333-026'
      and p.deleted_at is null
  ) then
    raise exception 'Pedido SICK 333 nao localizado no tenant/empresa esperados.';
  end if;

  if not exists (
    select 1
    from public.nf_entrada ne
    where ne.id = v_nf_entrada_id
      and ne.tenant_id = v_tenant_id
      and ne.empresa_id = v_empresa_id
      and ne.chave = '35260800769222000335550020003649921439857551'
      and ne.deleted_at is null
  ) then
    raise exception 'NF SICK 364992 nao localizada no tenant/empresa esperados.';
  end if;

  if not exists (
    select 1
    from public.ordens_servico os
    where os.id = v_os_id
      and os.tenant_id = v_tenant_id
      and os.empresa_id = v_empresa_id
  ) then
    raise exception 'OS 282 nao localizada no tenant/empresa esperados.';
  end if;

  -- Os codigos informados como 3336/3337 correspondem, neste pedido, aos itens
  -- cadastrados 3666/3667. A NF trouxe respectivamente 1 e 2 unidades.
  update m.pedido_compra_recebimento_item ri
     set quantidade = 1
   where ri.id = v_receb_item_3666_id
     and ri.tenant_id = v_tenant_id
     and ri.empresa_id = v_empresa_id
     and ri.pedido_compra_item_id = v_item_3666_pedido_id
     and ri.item_id = 3666
     and ri.deleted_at is null
     and ri.quantidade in (1, 2);
  get diagnostics v_count = row_count;
  if v_count <> 1 then
    raise exception 'Recebimento do item 3666 divergiu do estado esperado.';
  end if;

  update m.pedido_compra_recebimento_item ri
     set quantidade = 2
   where ri.id = v_receb_item_3667_id
     and ri.tenant_id = v_tenant_id
     and ri.empresa_id = v_empresa_id
     and ri.pedido_compra_item_id = v_item_3667_pedido_id
     and ri.item_id = 3667
     and ri.deleted_at is null
     and ri.quantidade in (2, 4);
  get diagnostics v_count = row_count;
  if v_count <> 1 then
    raise exception 'Recebimento do item 3667 divergiu do estado esperado.';
  end if;

  update m.pedido_compra_item pi
     set quantidade_recebida = (
           select coalesce(sum(ri.quantidade), 0)
           from m.pedido_compra_recebimento_item ri
           join m.pedido_compra_recebimento r
             on r.id = ri.recebimento_id
            and r.tenant_id = ri.tenant_id
            and r.empresa_id = ri.empresa_id
            and r.deleted_at is null
           where ri.tenant_id = pi.tenant_id
             and ri.empresa_id = pi.empresa_id
             and ri.pedido_compra_item_id = pi.id
             and ri.deleted_at is null
         ),
         updated_at = now()
   where pi.tenant_id = v_tenant_id
     and pi.empresa_id = v_empresa_id
     and pi.pedido_compra_id = v_pedido_id
     and pi.id in (v_item_3666_pedido_id, v_item_3667_pedido_id)
     and pi.deleted_at is null;
  get diagnostics v_count = row_count;
  if v_count <> 2 then
    raise exception 'Nao foi possivel recalcular os dois itens do Pedido 333.';
  end if;

  if not exists (
    select 1 from m.pedido_compra_item pi
    where pi.id = v_item_3666_pedido_id
      and pi.tenant_id = v_tenant_id
      and pi.empresa_id = v_empresa_id
      and pi.quantidade_recebida = 1
      and pi.deleted_at is null
  ) or not exists (
    select 1 from m.pedido_compra_item pi
    where pi.id = v_item_3667_pedido_id
      and pi.tenant_id = v_tenant_id
      and pi.empresa_id = v_empresa_id
      and pi.quantidade_recebida = 2
      and pi.deleted_at is null
  ) then
    raise exception 'As quantidades recebidas nao fecharam em 1 e 2.';
  end if;

  -- As movimentacoes sao imutaveis. Confirma que as oito baixas manuais da OS
  -- correspondem exatamente aos oito itens da NF antes de marcar o fluxo concluido.
  select count(*)
    into v_count
  from public.movimentacoes mov
  where mov.tenant_id = v_tenant_id
    and mov.empresa_id = v_empresa_id
    and mov.origem_nf_entrada_id is null
    and mov.origem_os_id = v_os_id
    and mov.tipo = 'saida'
    and mov.id between 12482 and 12489
    and exists (
      select 1
      from public.nf_entrada_itens ni
      where ni.tenant_id = mov.tenant_id
        and ni.empresa_id = mov.empresa_id
        and ni.nf_entrada_id = v_nf_entrada_id
        and ni.item_id = mov.item_id
        and ni.qtd = mov.quantidade
    );
  if v_count <> 8 then
    raise exception 'As oito baixas manuais da NF nao foram vinculadas a OS.';
  end if;

  select ne.motivo_compra_id, ne.solicitante_usuario_id
    into v_motivo_compra_id, v_aprovado_por
  from public.nf_entrada ne
  where ne.id = v_nf_entrada_id
    and ne.tenant_id = v_tenant_id
    and ne.empresa_id = v_empresa_id
    and ne.deleted_at is null;

  if v_motivo_compra_id is null or v_aprovado_por is null then
    raise exception 'NF sem motivo/solicitante para concluir a aprovacao financeira.';
  end if;

  select public.fn_ensure_titulo_ap_from_nf_entrada(
    p_nf_entrada_id => v_nf_entrada_id,
    p_force_regen_parcelas => false,
    p_parcelas_json => null
  ) into v_titulo_id;

  if v_titulo_id is null then
    raise exception 'Titulo AP da NF 364992 nao localizado.';
  end if;

  perform public.fn_sync_titulo_aprovacao_from_nf_entrada(
    p_nf_entrada_id => v_nf_entrada_id,
    p_titulo_id => v_titulo_id,
    p_motivo_compra_id => v_motivo_compra_id,
    p_os_id => v_os_id,
    p_aprovado_por => v_aprovado_por
  );

  update public.nf_entrada
     set os_id = v_os_id,
         baixa_os_automatica = true,
         updated_at = now()
   where id = v_nf_entrada_id
     and tenant_id = v_tenant_id
     and empresa_id = v_empresa_id
     and deleted_at is null;
end;
$$;
