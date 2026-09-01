begin;

-- NF-e de saida usa public.nf_entrada apenas como staging para criar o
-- documento fiscal de faturamento. Mesmo que um fluxo antigo deixe os_id
-- preenchido nesse staging, o produto vendido nao pode virar material da OS.
create or replace function public.os_sync_itens_from_nf_entrada(
  p_nf_entrada_id bigint
) returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_nf public.nf_entrada%rowtype;
  v_inserted integer := 0;
begin
  select *
    into v_nf
  from public.nf_entrada nf
  where nf.id = p_nf_entrada_id;

  if v_nf.id is null then
    raise exception 'NF nao encontrada (id=%)', p_nf_entrada_id;
  end if;

  if v_nf.os_id is null then
    return 0;
  end if;

  -- Emitente igual a empresa selecionada caracteriza documento de saida.
  if exists (
    select 1
    from c.empresa e
    where e.tenant_id = v_nf.tenant_id
      and e.id = v_nf.empresa_id
      and e.deleted_at is null
      and nullif(regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g'), '') =
          nullif(regexp_replace(coalesce(v_nf.emitente_cnpj, ''), '[^0-9]', '', 'g'), '')
  ) then
    return 0;
  end if;

  insert into public.os_itens (
    tenant_id,
    empresa_id,
    os_id,
    item_id,
    quantidade,
    valor_unitario,
    valor_total,
    desconto_percentual,
    desconto_valor,
    baixa_estoque,
    observacoes,
    criado_em
  )
  select
    v_nf.tenant_id,
    v_nf.empresa_id,
    v_nf.os_id,
    ni.item_id::integer,
    round(ni.qtd, 3),
    round(ni.v_unit, 2),
    round(ni.v_prod, 2),
    0,
    0,
    false,
    'IMPORT XML NF ' || v_nf.chave || ' NF_ITEM ' || ni.id::text,
    now()
  from public.nf_entrada_itens ni
  where ni.tenant_id = v_nf.tenant_id
    and ni.empresa_id = v_nf.empresa_id
    and ni.nf_entrada_id = v_nf.id
    and ni.item_id is not null
    and ni.qtd > 0
    and not exists (
      select 1
      from public.os_itens oi
      where oi.tenant_id = v_nf.tenant_id
        and oi.empresa_id = v_nf.empresa_id
        and oi.os_id = v_nf.os_id
        and oi.observacoes = 'IMPORT XML NF ' || v_nf.chave || ' NF_ITEM ' || ni.id::text
    );

  get diagnostics v_inserted = row_count;

  update public.ordens_servico os
  set valor_total = coalesce((
        select sum(oi.valor_total)
        from public.os_itens oi
        where oi.tenant_id = v_nf.tenant_id
          and oi.empresa_id = v_nf.empresa_id
          and oi.os_id = v_nf.os_id
      ), 0),
      atualizado_em = now()
  where os.id = v_nf.os_id
    and os.tenant_id = v_nf.tenant_id
    and os.empresa_id = v_nf.empresa_id;

  return v_inserted;
end;
$$;

comment on function public.os_sync_itens_from_nf_entrada(bigint) is
  'Sincroniza materiais de NF de entrada com OS e ignora NF-e emitida pela propria empresa (faturamento/saida).';

do $$
declare
  v_tenant_id uuid := '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';
  v_empresa_id uuid := 'f0e74f49-a127-46b4-901b-f7b37e43c690';
  v_documentos integer := 0;
  v_removed integer := 0;
begin
  -- Antes de remover qualquer linha, confirma que as quatro notas permanecem
  -- preservadas no modelo correto de faturamento.
  select count(*)
    into v_documentos
  from f.documento_fiscal df
  join public.nf_entrada nf
    on nf.tenant_id = v_tenant_id
   and nf.empresa_id = v_empresa_id
   and nf.id = df.source_nf_entrada_id
  where df.tenant_id = v_tenant_id
    and df.empresa_id = v_empresa_id
    and df.source_nf_entrada_id in (1277, 1701, 1823, 1907)
    and df.operacao = 'SAIDA'
    and df.deleted_at is null;

  if v_documentos <> 4 then
    raise exception
      'Saneamento cancelado: esperados 4 documentos de faturamento preservados, encontrados %.',
      v_documentos;
  end if;

  -- Garante que a associacao correta OS <-> faturamento esteja no documento
  -- fiscal. O trigger financeiro propaga esse vinculo ao rateio do AR.
  update f.documento_fiscal df
  set os_id_import = nf.os_id,
      updated_at = now()
  from public.nf_entrada nf
  where nf.tenant_id = v_tenant_id
    and nf.empresa_id = v_empresa_id
    and nf.id in (1277, 1701, 1823, 1907)
    and nf.os_id in (180, 191)
    and df.tenant_id = v_tenant_id
    and df.empresa_id = v_empresa_id
    and df.source_nf_entrada_id = nf.id
    and df.operacao = 'SAIDA'
    and df.deleted_at is null
    and df.os_id_import is distinct from nf.os_id;

  -- Remove somente as linhas comprovadamente geradas por essas NF-e de saida:
  -- sem baixa, sem movimento e com quantidade/valor iguais ao item fiscal.
  delete from public.os_itens oi
  using public.nf_entrada nf, public.nf_entrada_itens ni, c.empresa e
  where oi.tenant_id = v_tenant_id
    and oi.empresa_id = v_empresa_id
    and oi.id in (2386, 2387, 4175, 4176, 4632, 4633, 5031, 5032)
    and coalesce(oi.baixa_estoque, false) = false
    and coalesce(oi.quantidade_baixada, 0) = 0
    and nf.tenant_id = v_tenant_id
    and nf.empresa_id = v_empresa_id
    and nf.id in (1277, 1701, 1823, 1907)
    and nf.os_id = oi.os_id
    and ni.tenant_id = v_tenant_id
    and ni.empresa_id = v_empresa_id
    and ni.nf_entrada_id = nf.id
    and ni.item_id = oi.item_id
    and abs(coalesce(ni.qtd, 0) - coalesce(oi.quantidade, 0)) <= 0.0005
    and abs(coalesce(ni.v_prod, 0) - coalesce(oi.valor_total, 0)) <= 0.01
    and e.tenant_id = v_tenant_id
    and e.id = v_empresa_id
    and e.deleted_at is null
    and nullif(regexp_replace(coalesce(e.cnpj, ''), '[^0-9]', '', 'g'), '') =
        nullif(regexp_replace(coalesce(nf.emitente_cnpj, ''), '[^0-9]', '', 'g'), '')
    and not exists (
      select 1
      from public.movimentacoes m
      where m.tenant_id = v_tenant_id
        and m.empresa_id = v_empresa_id
        and m.origem_nf_entrada_id = nf.id
        and m.origem_os_id = nf.os_id
        and m.item_id = ni.item_id
    );

  get diagnostics v_removed = row_count;
  raise notice 'Itens de faturamento retirados da composicao das OS: %', v_removed;

  -- O vinculo correto ja ficou em f.documento_fiscal.os_id_import; elimina o
  -- vinculo legado do staging para que atualizacoes futuras nao recriem itens.
  update public.nf_entrada nf
  set os_id = null,
      baixa_os_automatica = false,
      updated_at = now()
  where nf.tenant_id = v_tenant_id
    and nf.empresa_id = v_empresa_id
    and nf.id in (1277, 1701, 1823, 1907)
    and exists (
      select 1
      from f.documento_fiscal df
      where df.tenant_id = v_tenant_id
        and df.empresa_id = v_empresa_id
        and df.source_nf_entrada_id = nf.id
        and df.operacao = 'SAIDA'
        and df.os_id_import = nf.os_id
        and df.deleted_at is null
    );

  update public.ordens_servico os
  set valor_total = coalesce((
        select sum(oi.valor_total)
        from public.os_itens oi
        where oi.tenant_id = v_tenant_id
          and oi.empresa_id = v_empresa_id
          and oi.os_id = os.id
      ), 0),
      atualizado_em = now()
  where os.tenant_id = v_tenant_id
    and os.empresa_id = v_empresa_id
    and os.id in (180, 191);
end;
$$;

notify pgrst, 'reload schema';

commit;
