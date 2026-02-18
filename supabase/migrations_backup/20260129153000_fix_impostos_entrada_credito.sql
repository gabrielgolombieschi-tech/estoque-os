begin;

-- 1) Fix function: ENTRADA => CREDITO, SAIDA => DEBITO (ICMS/PIS/COFINS/IPI).
--    Keep ISS behavior outside this function.
create or replace function f.nfe_gravar_impostos_da_nf_entrada(
  p_nf_entrada_id bigint,
  p_documento_fiscal_id uuid,
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path to 'f', 'public', 'a'
as $_$
declare
  v_xml_col text;
  v_xml_text text;
  v_xml xml;

  v_vbc_icms numeric;
  v_vicms numeric;

  v_vipi numeric;
  v_base_ipi numeric;

  v_vpis numeric;
  v_base_pis numeric;

  v_vcofins numeric;
  v_base_cofins numeric;

  v_now timestamptz := now();

  v_aliq_icms numeric;
  v_aliq_ipi numeric;
  v_aliq_pis numeric;
  v_aliq_cofins numeric;

  v_cnt int;
  v_single numeric;

  v_operacao text;
  v_doc_natureza text;
  v_natureza_padrao text;
begin
  if p_nf_entrada_id is null then raise exception 'nf_entrada_id é obrigatório.'; end if;
  if p_documento_fiscal_id is null then raise exception 'documento_fiscal_id é obrigatório.'; end if;
  if p_tenant_id is null then raise exception 'tenant_id é obrigatório.'; end if;

  select df.operacao, df.natureza
    into v_operacao, v_doc_natureza
  from f.documento_fiscal df
  where df.id = p_documento_fiscal_id
    and df.tenant_id = p_tenant_id
    and df.deleted_at is null;

  if not found then
    raise exception 'Documento fiscal não encontrado (id=% tenant_id=%).', p_documento_fiscal_id, p_tenant_id;
  end if;

  if coalesce(v_doc_natureza, '') <> 'PRODUTO' then
    -- Esta função é para NF-e de produto (NF de entrada).
    -- Não interfere em ISS/serviços.
    null;
  end if;

  if v_operacao = 'ENTRADA' then
    v_natureza_padrao := 'CREDITO';
  else
    v_natureza_padrao := 'DEBITO';
  end if;

  -- Descobre a coluna do XML em public.nf_entrada
  select c.column_name
    into v_xml_col
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'nf_entrada'
    and c.column_name ilike '%xml%'
    and c.data_type in ('text','xml','character varying')
  order by
    case
      when c.column_name in ('xml','xml_raw','xml_text','conteudo_xml','arquivo_xml','xml_content') then 0
      else 1
    end,
    c.ordinal_position
  limit 1;

  if v_xml_col is null then
    raise exception 'Não encontrei coluna com XML em public.nf_entrada.';
  end if;

  execute format('select %I::text from public.nf_entrada where id = $1', v_xml_col)
    into v_xml_text
    using p_nf_entrada_id;

  if v_xml_text is null or btrim(v_xml_text) = '' then
    raise exception 'XML vazio em public.nf_entrada.id=% (coluna %).', p_nf_entrada_id, v_xml_col;
  end if;

  v_xml := v_xml_text::xml;

  -- Totais (ICMSTot)
  v_vbc_icms := coalesce(f._nfe_xpath_num(v_xml, '//nfe:ICMSTot/nfe:vBC/text()'), 0);
  v_vicms    := coalesce(f._nfe_xpath_num(v_xml, '//nfe:ICMSTot/nfe:vICMS/text()'), 0);

  v_vipi     := coalesce(f._nfe_xpath_num(v_xml, '//nfe:ICMSTot/nfe:vIPI/text()'), 0);
  v_vpis     := coalesce(f._nfe_xpath_num(v_xml, '//nfe:ICMSTot/nfe:vPIS/text()'), 0);
  v_vcofins  := coalesce(f._nfe_xpath_num(v_xml, '//nfe:ICMSTot/nfe:vCOFINS/text()'), 0);

  -- Bases por item (somando vBC)
  select coalesce(sum((x)::text::numeric), 0)
    into v_base_ipi
  from unnest(xpath(
    '//nfe:det/nfe:imposto/nfe:IPI//*[local-name()="vBC"]/text()',
    v_xml,
    array[array['nfe','http://www.portalfiscal.inf.br/nfe']]
  )) as t(x);

  if v_base_ipi = 0 then
    v_base_ipi := coalesce(f._nfe_xpath_num(v_xml, '//nfe:ICMSTot/nfe:vProd/text()'), 0);
  end if;

  select coalesce(sum((x)::text::numeric), 0)
    into v_base_pis
  from unnest(xpath(
    '//nfe:det/nfe:imposto/nfe:PIS//*[local-name()="vBC"]/text()',
    v_xml,
    array[array['nfe','http://www.portalfiscal.inf.br/nfe']]
  )) as t(x);

  select coalesce(sum((x)::text::numeric), 0)
    into v_base_cofins
  from unnest(xpath(
    '//nfe:det/nfe:imposto/nfe:COFINS//*[local-name()="vBC"]/text()',
    v_xml,
    array[array['nfe','http://www.portalfiscal.inf.br/nfe']]
  )) as t(x);

  -- Fallback bases
  if v_base_pis = 0 then
    v_base_pis := coalesce(f._nfe_xpath_num(v_xml, '//nfe:ICMSTot/nfe:vProd/text()'), 0);
  end if;
  if v_base_cofins = 0 then
    v_base_cofins := coalesce(f._nfe_xpath_num(v_xml, '//nfe:ICMSTot/nfe:vProd/text()'), 0);
  end if;

  --------------------------------------------------------------------
  -- ALÍQUOTAS: usar "fonte do XML" se houver UMA única alíquota.
  -- Se tiver múltiplas, cair para média ponderada (sum(valor)/sum(base)).
  --------------------------------------------------------------------

  -- ICMS: tentar pICMS único nos itens
  select count(distinct (x)::text::numeric), max((x)::text::numeric)
    into v_cnt, v_single
  from unnest(xpath(
    '//nfe:det/nfe:imposto/nfe:ICMS//*[local-name()="pICMS"]/text()',
    v_xml,
    array[array['nfe','http://www.portalfiscal.inf.br/nfe']]
  )) as t(x);

  if coalesce(v_cnt,0) = 1 and v_single is not null then
    v_aliq_icms := round(v_single, 4);
  else
    v_aliq_icms := case when v_vbc_icms > 0 then round((v_vicms / v_vbc_icms) * 100, 4) else 0 end;
  end if;

  -- IPI: tentar pIPI único
  select count(distinct (x)::text::numeric), max((x)::text::numeric)
    into v_cnt, v_single
  from unnest(xpath(
    '//nfe:det/nfe:imposto/nfe:IPI//*[local-name()="pIPI"]/text()',
    v_xml,
    array[array['nfe','http://www.portalfiscal.inf.br/nfe']]
  )) as t(x);

  if coalesce(v_cnt,0) = 1 and v_single is not null then
    v_aliq_ipi := round(v_single, 4);
  else
    v_aliq_ipi := case when v_base_ipi > 0 then round((v_vipi / v_base_ipi) * 100, 4) else 0 end;
  end if;

  -- PIS: tentar pPIS único
  select count(distinct (x)::text::numeric), max((x)::text::numeric)
    into v_cnt, v_single
  from unnest(xpath(
    '//nfe:det/nfe:imposto/nfe:PIS//*[local-name()="pPIS"]/text()',
    v_xml,
    array[array['nfe','http://www.portalfiscal.inf.br/nfe']]
  )) as t(x);

  if coalesce(v_cnt,0) = 1 and v_single is not null then
    v_aliq_pis := round(v_single, 4);
  else
    v_aliq_pis := case when v_base_pis > 0 then round((v_vpis / v_base_pis) * 100, 4) else 0 end;
  end if;

  -- COFINS: tentar pCOFINS único
  select count(distinct (x)::text::numeric), max((x)::text::numeric)
    into v_cnt, v_single
  from unnest(xpath(
    '//nfe:det/nfe:imposto/nfe:COFINS//*[local-name()="pCOFINS"]/text()',
    v_xml,
    array[array['nfe','http://www.portalfiscal.inf.br/nfe']]
  )) as t(x);

  if coalesce(v_cnt,0) = 1 and v_single is not null then
    v_aliq_cofins := round(v_single, 4);
  else
    v_aliq_cofins := case when v_base_cofins > 0 then round((v_vcofins / v_base_cofins) * 100, 4) else 0 end;
  end if;

  --------------------------------------------------------------------
  -- UPSERT (por unique tenant_id, documento_fiscal_id, imposto, natureza)
  --------------------------------------------------------------------

  -- ICMS
  if v_vicms > 0 or v_vbc_icms > 0 then
    insert into f.documento_fiscal_imposto (
      tenant_id, documento_fiscal_id,
      imposto, natureza,
      base_original, deducoes, base_calculo,
      aliquota, valor_calculado, valor_ajustado,
      created_at, updated_at, deleted_at
    ) values (
      p_tenant_id, p_documento_fiscal_id,
      'ICMS', v_natureza_padrao,
      v_vbc_icms, 0, v_vbc_icms,
      v_aliq_icms, v_vicms, null,
      v_now, v_now, null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original   = excluded.base_original,
      deducoes        = excluded.deducoes,
      base_calculo    = excluded.base_calculo,
      aliquota        = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      valor_ajustado  = excluded.valor_ajustado,
      updated_at      = excluded.updated_at,
      deleted_at      = null;
  end if;

  -- IPI
  if v_vipi > 0 then
    insert into f.documento_fiscal_imposto (
      tenant_id, documento_fiscal_id,
      imposto, natureza,
      base_original, deducoes, base_calculo,
      aliquota, valor_calculado, valor_ajustado,
      created_at, updated_at, deleted_at
    ) values (
      p_tenant_id, p_documento_fiscal_id,
      'IPI', v_natureza_padrao,
      v_base_ipi, 0, v_base_ipi,
      v_aliq_ipi, v_vipi, null,
      v_now, v_now, null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original   = excluded.base_original,
      deducoes        = excluded.deducoes,
      base_calculo    = excluded.base_calculo,
      aliquota        = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      valor_ajustado  = excluded.valor_ajustado,
      updated_at      = excluded.updated_at,
      deleted_at      = null;
  end if;

  -- PIS
  if v_vpis > 0 then
    insert into f.documento_fiscal_imposto (
      tenant_id, documento_fiscal_id,
      imposto, natureza,
      base_original, deducoes, base_calculo,
      aliquota, valor_calculado, valor_ajustado,
      created_at, updated_at, deleted_at
    ) values (
      p_tenant_id, p_documento_fiscal_id,
      'PIS', v_natureza_padrao,
      v_base_pis, 0, v_base_pis,
      v_aliq_pis, v_vpis, null,
      v_now, v_now, null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original   = excluded.base_original,
      deducoes        = excluded.deducoes,
      base_calculo    = excluded.base_calculo,
      aliquota        = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      valor_ajustado  = excluded.valor_ajustado,
      updated_at      = excluded.updated_at,
      deleted_at      = null;
  end if;

  -- COFINS
  if v_vcofins > 0 then
    insert into f.documento_fiscal_imposto (
      tenant_id, documento_fiscal_id,
      imposto, natureza,
      base_original, deducoes, base_calculo,
      aliquota, valor_calculado, valor_ajustado,
      created_at, updated_at, deleted_at
    ) values (
      p_tenant_id, p_documento_fiscal_id,
      'COFINS', v_natureza_padrao,
      v_base_cofins, 0, v_base_cofins,
      v_aliq_cofins, v_vcofins, null,
      v_now, v_now, null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original   = excluded.base_original,
      deducoes        = excluded.deducoes,
      base_calculo    = excluded.base_calculo,
      aliquota        = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      valor_ajustado  = excluded.valor_ajustado,
      updated_at      = excluded.updated_at,
      deleted_at      = null;
  end if;
end;
$_$;

create or replace function f.nfe_gravar_impostos_do_documento(p_documento_fiscal_id uuid)
returns void
language plpgsql
security definer
set search_path to 'f', 'public', 'a'
as $$
declare
  v_df record;
begin
  select
    id,
    tenant_id,
    empresa_id,
    source_nf_entrada_id
  into v_df
  from f.documento_fiscal
  where id = p_documento_fiscal_id
    and deleted_at is null;

  if not found then
    raise exception 'Documento fiscal não encontrado: %', p_documento_fiscal_id;
  end if;

  if v_df.source_nf_entrada_id is null then
    raise exception 'Documento fiscal % não tem source_nf_entrada_id preenchido.', p_documento_fiscal_id;
  end if;

  perform f.nfe_gravar_impostos_da_nf_entrada(v_df.source_nf_entrada_id, v_df.id, v_df.tenant_id);
end;
$$;

-- 2) Historical fix: ENTRADA with DEBITO -> CREDITO (ICMS/PIS/COFINS/IPI).
--    Avoid unique collisions (uq_documento_fiscal_imposto__doc_imp_nat) in 2 steps.

-- 2.1) Delete DEBITO rows when a matching CREDITO already exists.
delete from f.documento_fiscal_imposto dfi
using f.documento_fiscal df
where df.id = dfi.documento_fiscal_id
  and df.tenant_id = dfi.tenant_id
  and df.deleted_at is null
  and dfi.deleted_at is null
  and df.operacao = 'ENTRADA'
  and dfi.natureza = 'DEBITO'
  and dfi.imposto in ('ICMS','PIS','COFINS','IPI')
  and exists (
    select 1
    from f.documento_fiscal_imposto dfi2
    where dfi2.tenant_id = dfi.tenant_id
      and dfi2.documento_fiscal_id = dfi.documento_fiscal_id
      and dfi2.imposto = dfi.imposto
      and dfi2.natureza = 'CREDITO'
      and dfi2.deleted_at is null
  );

-- 2.2) Update remaining DEBITO -> CREDITO where there isn't a CREDITO yet.
update f.documento_fiscal_imposto dfi
set natureza = 'CREDITO',
    updated_at = now()
from f.documento_fiscal df
where df.id = dfi.documento_fiscal_id
  and df.tenant_id = dfi.tenant_id
  and df.deleted_at is null
  and dfi.deleted_at is null
  and df.operacao = 'ENTRADA'
  and dfi.natureza = 'DEBITO'
  and dfi.imposto in ('ICMS','PIS','COFINS','IPI')
  and not exists (
    select 1
    from f.documento_fiscal_imposto dfi2
    where dfi2.tenant_id = dfi.tenant_id
      and dfi2.documento_fiscal_id = dfi.documento_fiscal_id
      and dfi2.imposto = dfi.imposto
      and dfi2.natureza = 'CREDITO'
      and dfi2.deleted_at is null
  );

commit;

