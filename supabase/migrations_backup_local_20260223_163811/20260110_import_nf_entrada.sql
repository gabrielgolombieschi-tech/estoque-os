begin;

create or replace function public.import_nf_entrada(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_fornecedor_id bigint,
  p_nf_json jsonb,
  p_itens_json jsonb,
  p_xml_raw text
) returns table(status text, nf_id bigint, message text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_chave text;
  v_nf_id bigint;
  v_itens jsonb := coalesce(p_itens_json, '[]'::jsonb);
begin
  if auth.uid() is null then
    raise exception 'Usuario nao autenticado';
  end if;

  if p_tenant_id is null then
    raise exception 'tenant_id obrigatorio';
  end if;
  if p_empresa_id is null then
    raise exception 'empresa_id obrigatorio';
  end if;

  if not exists (
    select 1
    from public.tenant_memberships tm
    where tm.user_id = auth.uid()
      and tm.tenant_id = p_tenant_id
      and tm.status = 'active'
  ) then
    raise exception 'Tenant nao autorizado';
  end if;

  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'empresas') then
    if not exists (
      select 1
      from public.empresas e
      where e.id = p_empresa_id
        and e.tenant_id = p_tenant_id
        and e.ativo = true
    ) then
      raise exception 'Empresa nao encontrada para este tenant';
    end if;
  end if;

  v_chave := p_nf_json->>'chave';
  if v_chave is null or v_chave = '' then
    raise exception 'Chave da NF obrigatoria';
  end if;

  select nf.id
    into v_nf_id
  from public.nf_entrada nf
  where nf.tenant_id = p_tenant_id
    and nf.empresa_id = p_empresa_id
    and nf.chave = v_chave
  limit 1;

  if v_nf_id is not null then
    return query select 'ja_importada', v_nf_id, 'NF ja importada';
    return;
  end if;

  insert into public.nf_entrada(
    tenant_id,
    empresa_id,
    chave,
    numero,
    serie,
    emitente_nome,
    emitente_cnpj,
    valor_produtos,
    valor_frete,
    valor_seguro,
    valor_outros,
    valor_desconto,
    valor_total,
    fornecedor_id,
    data_emissao,
    xml_raw
  ) values (
    p_tenant_id,
    p_empresa_id,
    v_chave,
    p_nf_json->>'numero',
    p_nf_json->>'serie',
    p_nf_json->>'emitente_nome',
    p_nf_json->>'emitente_cnpj',
    (p_nf_json->>'valor_produtos')::numeric,
    (p_nf_json->>'valor_frete')::numeric,
    (p_nf_json->>'valor_seguro')::numeric,
    (p_nf_json->>'valor_outros')::numeric,
    (p_nf_json->>'valor_desconto')::numeric,
    (p_nf_json->>'valor_total')::numeric,
    p_fornecedor_id,
    (p_nf_json->>'data_emissao')::timestamptz,
    p_xml_raw
  )
  returning id into v_nf_id;

  insert into public.nf_entrada_itens(
    tenant_id,
    nf_entrada_id,
    item_id,
    codigo_fornecedor,
    descricao,
    ncm,
    qtd,
    v_unit,
    v_prod,
    v_icms,
    v_ipi,
    v_pis,
    v_cofins,
    aliq_icms,
    aliq_ipi,
    aliq_pis,
    aliq_cofins
  )
  select
    p_tenant_id,
    v_nf_id,
    item_id,
    codigo_fornecedor,
    descricao,
    ncm,
    qtd,
    v_unit,
    v_prod,
    v_icms,
    v_ipi,
    v_pis,
    v_cofins,
    aliq_icms,
    aliq_ipi,
    aliq_pis,
    aliq_cofins
  from jsonb_to_recordset(v_itens) as x(
    item_id bigint,
    codigo_fornecedor text,
    descricao text,
    ncm text,
    qtd numeric,
    v_unit numeric,
    v_prod numeric,
    v_icms numeric,
    v_ipi numeric,
    v_pis numeric,
    v_cofins numeric,
    aliq_icms numeric,
    aliq_ipi numeric,
    aliq_pis numeric,
    aliq_cofins numeric,
    quantidade numeric,
    tipo text,
    motivo text,
    realizado_por text,
    data_movimentacao timestamptz,
    custo_unitario_bruto numeric,
    custo_unitario_real numeric,
    v_frete_rateado numeric,
    credito_icms numeric,
    credito_pis numeric,
    credito_cofins numeric
  );

  insert into public.movimentacoes(
    tenant_id,
    empresa_id,
    item_id,
    tipo,
    quantidade,
    motivo,
    realizado_por,
    data_movimentacao,
    custo_unitario_bruto,
    custo_unitario_real,
    v_ipi,
    v_icms,
    v_pis,
    v_cofins,
    v_frete_rateado,
    credito_icms,
    credito_pis,
    credito_cofins,
    origem_nf_entrada_id
  )
  select
    p_tenant_id,
    p_empresa_id,
    item_id,
    tipo,
    quantidade,
    motivo,
    realizado_por,
    data_movimentacao,
    custo_unitario_bruto,
    custo_unitario_real,
    v_ipi,
    v_icms,
    v_pis,
    v_cofins,
    v_frete_rateado,
    credito_icms,
    credito_pis,
    credito_cofins,
    v_nf_id
  from jsonb_to_recordset(v_itens) as m(
    item_id bigint,
    quantidade numeric,
    tipo text,
    motivo text,
    realizado_por text,
    data_movimentacao timestamptz,
    custo_unitario_bruto numeric,
    custo_unitario_real numeric,
    v_ipi numeric,
    v_icms numeric,
    v_pis numeric,
    v_cofins numeric,
    v_frete_rateado numeric,
    credito_icms numeric,
    credito_pis numeric,
    credito_cofins numeric
  )
  where item_id is not null;

  return query select 'ok', v_nf_id, 'Importado com sucesso';
end;
$$;

commit;
