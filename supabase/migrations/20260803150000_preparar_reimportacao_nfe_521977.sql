begin;

do $$
declare
  v_tenant_id uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';
  v_empresa_id uuid := 'f0e74f49-a127-46b4-901b-f7b37e43c690';
  v_fornecedor_id bigint := 246;
  v_pedido_id uuid := 'df29f6af-8cc3-435f-b20a-6a6a214171df';
  v_tubo_item_id integer;
begin
  if not exists (
    select 1
    from public.nf_entrada nf
    where nf.id = 1965
      and nf.tenant_id = v_tenant_id
      and nf.empresa_id = v_empresa_id
      and nf.chave = '42260702612064000179550010005219771564239546'
      and nf.numero = '521977'
      and nf.deleted_at is not null
  ) then
    raise exception 'Preparacao abortada: NF-e 521977 arquivada nao confere.';
  end if;

  if not exists (
    select 1
    from m.pedido_compra p
    where p.id = v_pedido_id
      and p.tenant_id = v_tenant_id
      and p.empresa_id = v_empresa_id
      and p.codigo = 'PC-SEG-00312-026'
      and p.fornecedor_id = v_fornecedor_id
      and p.status = 'ENVIADO'
      and p.deleted_at is null
  ) then
    raise exception 'Preparacao abortada: pedido PC-SEG-00312-026 nao confere.';
  end if;

  update public.itens i
  set unidade_medida = 'KG',
      atualizado_em = now(),
      atualizado_por = 'CORRECAO_NFE_521977'
  where i.id = 2928
    and i.tenant_id = v_tenant_id
    and i.empresa_id = v_empresa_id
    and i.fornecedor_id = v_fornecedor_id
    and i.codigo_interno = '577'
    and upper(i.nome) = 'CHAPA FINA QUENTE 2,00 X 1200 X 3000';

  if not found then
    raise exception 'Preparacao abortada: item 2928 da chapa nao confere.';
  end if;

  select i.id
    into v_tubo_item_id
  from public.itens i
  where i.tenant_id = v_tenant_id
    and i.empresa_id = v_empresa_id
    and i.codigo_interno = '45'
  limit 1;

  if v_tubo_item_id is null then
    insert into public.itens (
      tenant_id,
      empresa_id,
      codigo_interno,
      codigo_fornecedor,
      nome,
      tipo,
      controla_estoque,
      unidade_medida,
      custo_ultima_compra,
      custo_medio,
      preco_unitario,
      fornecedor_id,
      data_atualizacao_preco,
      data_ultima_compra,
      margem_lucro_percentual,
      finalidade,
      ncm,
      aliquota_icms,
      aliquota_ipi,
      aliquota_pis,
      aliquota_cofins,
      criado_por,
      atualizado_por
    ) values (
      v_tenant_id,
      v_empresa_id,
      '45',
      '45',
      'TUBO RETANGULAR 40 X 60 X 2,00',
      'produto',
      true,
      'KG',
      7.727126,
      7.727126,
      7.727126,
      v_fornecedor_id,
      '2026-07-28 23:49:00'::timestamp,
      '2026-07-28 23:49:00'::timestamp,
      52,
      'materia_prima'::public.item_finalidade,
      '73066100',
      12,
      5,
      1.65,
      7.6,
      'CORRECAO_NFE_521977',
      'CORRECAO_NFE_521977'
    )
    returning id into v_tubo_item_id;
  else
    update public.itens i
    set codigo_fornecedor = '45',
        nome = 'TUBO RETANGULAR 40 X 60 X 2,00',
        tipo = 'produto',
        controla_estoque = true,
        unidade_medida = 'KG',
        fornecedor_id = v_fornecedor_id,
        finalidade = 'materia_prima'::public.item_finalidade,
        ncm = '73066100',
        ativo = true,
        atualizado_em = now(),
        atualizado_por = 'CORRECAO_NFE_521977'
    where i.id = v_tubo_item_id
      and i.tenant_id = v_tenant_id
      and i.empresa_id = v_empresa_id;
  end if;

  insert into public.fiscal_itens (
    tenant_id,
    empresa_id,
    item_id,
    ncm,
    aliq_icms,
    aliq_ipi,
    aliq_pis,
    aliq_cofins,
    credita_icms,
    credita_pis,
    credita_cofins,
    ipi_entra_no_custo
  ) values (
    v_tenant_id,
    v_empresa_id,
    v_tubo_item_id,
    '73066100',
    12,
    5,
    1.65,
    7.6,
    false,
    false,
    false,
    true
  )
  on conflict (tenant_id, empresa_id, item_id) do update
  set ncm = excluded.ncm,
      aliq_icms = excluded.aliq_icms,
      aliq_ipi = excluded.aliq_ipi,
      aliq_pis = excluded.aliq_pis,
      aliq_cofins = excluded.aliq_cofins,
      ipi_entra_no_custo = excluded.ipi_entra_no_custo,
      atualizado_em = now();

  update m.pedido_compra_item pci
  set item_id = v_tubo_item_id,
      item_codigo = '45',
      item_nome = 'TUBO RETANGULAR 40 X 60 X 2,00',
      updated_at = now()
  where pci.tenant_id = v_tenant_id
    and pci.empresa_id = v_empresa_id
    and pci.pedido_compra_id = v_pedido_id
    and pci.id in (
      '71aa134c-c841-4b15-bdd8-129e3ef6ba63'::uuid,
      'ad517be9-c448-43a1-81db-14722b37d180'::uuid
    )
    and pci.deleted_at is null
    and pci.item_id is null;

  if (select count(*) from m.pedido_compra_item pci
      where pci.tenant_id = v_tenant_id
        and pci.empresa_id = v_empresa_id
        and pci.pedido_compra_id = v_pedido_id
        and pci.id in (
          '71aa134c-c841-4b15-bdd8-129e3ef6ba63'::uuid,
          'ad517be9-c448-43a1-81db-14722b37d180'::uuid
        )
        and pci.item_id = v_tubo_item_id
        and pci.item_codigo = '45'
        and pci.deleted_at is null) <> 2 then
    raise exception 'Preparacao abortada: nao foi possivel vincular os dois itens de tubo do pedido.';
  end if;
end;
$$;

commit;
