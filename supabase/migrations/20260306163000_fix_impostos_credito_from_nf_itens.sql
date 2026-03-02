begin;

create or replace function f.nfe_sync_creditos_entrada_from_nf_itens(
  p_documento_fiscal_id uuid
) returns void
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security = off
as $$
declare
  v_df record;
  v_now timestamptz := now();

  v_base_prod numeric(15,2) := 0;
  v_vicms numeric(15,2) := 0;
  v_vpis numeric(15,2) := 0;
  v_vcofins numeric(15,2) := 0;
  v_vipi numeric(15,2) := 0;

  v_aliq_icms numeric(7,4);
  v_aliq_pis numeric(7,4);
  v_aliq_cofins numeric(7,4);
  v_aliq_ipi numeric(7,4);
begin
  if auth.uid() is null then
    if current_user not in ('postgres', 'service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  if p_documento_fiscal_id is null then
    raise exception 'p_documento_fiscal_id obrigatorio';
  end if;

  select
    df.id,
    df.tenant_id,
    df.empresa_id,
    df.operacao,
    df.natureza,
    df.source_nf_entrada_id
  into v_df
  from f.documento_fiscal df
  where df.id = p_documento_fiscal_id
    and df.deleted_at is null;

  if not found then
    raise exception 'Documento fiscal nao encontrado: %', p_documento_fiscal_id;
  end if;

  if auth.uid() is not null then
    if public.current_tenant_id() is distinct from v_df.tenant_id then
      raise exception 'Tenant mismatch';
    end if;
    if public.current_empresa_id() is distinct from v_df.empresa_id then
      raise exception 'Empresa mismatch';
    end if;
    if not f.has_finance_access(v_df.tenant_id, v_df.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  if coalesce(v_df.operacao, '') <> 'ENTRADA' then
    return;
  end if;
  if coalesce(v_df.natureza, 'PRODUTO') <> 'PRODUTO' then
    return;
  end if;
  if v_df.source_nf_entrada_id is null then
    return;
  end if;

  select
    round(coalesce(sum(coalesce(i.v_prod, 0)), 0)::numeric, 2) as base_prod,
    round(coalesce(sum(coalesce(i.v_icms, 0)), 0)::numeric, 2) as v_icms,
    round(coalesce(sum(coalesce(i.v_pis, 0)), 0)::numeric, 2) as v_pis,
    round(coalesce(sum(coalesce(i.v_cofins, 0)), 0)::numeric, 2) as v_cofins,
    round(coalesce(sum(coalesce(i.v_ipi, 0)), 0)::numeric, 2) as v_ipi
  into
    v_base_prod, v_vicms, v_vpis, v_vcofins, v_vipi
  from public.nf_entrada_itens i
  where i.tenant_id = v_df.tenant_id
    and i.empresa_id = v_df.empresa_id
    and i.nf_entrada_id = v_df.source_nf_entrada_id;

  if coalesce(v_base_prod, 0) <= 0 then
    return;
  end if;

  v_aliq_icms := case when v_base_prod > 0 then round((v_vicms / v_base_prod) * 100, 4) else null end;
  v_aliq_pis := case when v_base_prod > 0 then round((v_vpis / v_base_prod) * 100, 4) else null end;
  v_aliq_cofins := case when v_base_prod > 0 then round((v_vcofins / v_base_prod) * 100, 4) else null end;
  v_aliq_ipi := case when v_base_prod > 0 then round((v_vipi / v_base_prod) * 100, 4) else null end;

  if coalesce(v_vicms, 0) > 0 then
    insert into f.documento_fiscal_imposto (
      tenant_id, documento_fiscal_id, imposto, natureza,
      base_original, deducoes, base_calculo, aliquota,
      valor_calculado, valor_ajustado, created_at, updated_at, deleted_at
    ) values (
      v_df.tenant_id, v_df.id, 'ICMS', 'CREDITO',
      v_base_prod, 0, v_base_prod, v_aliq_icms,
      v_vicms, null, v_now, v_now, null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original = excluded.base_original,
      deducoes = excluded.deducoes,
      base_calculo = excluded.base_calculo,
      aliquota = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      valor_ajustado = null,
      updated_at = excluded.updated_at,
      deleted_at = null;
  end if;

  if coalesce(v_vpis, 0) > 0 then
    insert into f.documento_fiscal_imposto (
      tenant_id, documento_fiscal_id, imposto, natureza,
      base_original, deducoes, base_calculo, aliquota,
      valor_calculado, valor_ajustado, created_at, updated_at, deleted_at
    ) values (
      v_df.tenant_id, v_df.id, 'PIS', 'CREDITO',
      v_base_prod, 0, v_base_prod, v_aliq_pis,
      v_vpis, null, v_now, v_now, null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original = excluded.base_original,
      deducoes = excluded.deducoes,
      base_calculo = excluded.base_calculo,
      aliquota = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      valor_ajustado = null,
      updated_at = excluded.updated_at,
      deleted_at = null;
  end if;

  if coalesce(v_vcofins, 0) > 0 then
    insert into f.documento_fiscal_imposto (
      tenant_id, documento_fiscal_id, imposto, natureza,
      base_original, deducoes, base_calculo, aliquota,
      valor_calculado, valor_ajustado, created_at, updated_at, deleted_at
    ) values (
      v_df.tenant_id, v_df.id, 'COFINS', 'CREDITO',
      v_base_prod, 0, v_base_prod, v_aliq_cofins,
      v_vcofins, null, v_now, v_now, null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original = excluded.base_original,
      deducoes = excluded.deducoes,
      base_calculo = excluded.base_calculo,
      aliquota = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      valor_ajustado = null,
      updated_at = excluded.updated_at,
      deleted_at = null;
  end if;

  if coalesce(v_vipi, 0) > 0 then
    insert into f.documento_fiscal_imposto (
      tenant_id, documento_fiscal_id, imposto, natureza,
      base_original, deducoes, base_calculo, aliquota,
      valor_calculado, valor_ajustado, created_at, updated_at, deleted_at
    ) values (
      v_df.tenant_id, v_df.id, 'IPI', 'CREDITO',
      v_base_prod, 0, v_base_prod, v_aliq_ipi,
      v_vipi, null, v_now, v_now, null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original = excluded.base_original,
      deducoes = excluded.deducoes,
      base_calculo = excluded.base_calculo,
      aliquota = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      valor_ajustado = null,
      updated_at = excluded.updated_at,
      deleted_at = null;
  end if;
end;
$$;

revoke all on function f.nfe_sync_creditos_entrada_from_nf_itens(uuid) from public;
grant all on function f.nfe_sync_creditos_entrada_from_nf_itens(uuid) to authenticated;
grant all on function f.nfe_sync_creditos_entrada_from_nf_itens(uuid) to service_role;

do $$
declare
  r record;
begin
  -- Normaliza legado: valor_ajustado=0 invalida apuracao (coalesce prioriza ajustado).
  update f.documento_fiscal_imposto dfi
  set valor_ajustado = null,
      updated_at = now()
  from f.documento_fiscal df
  where df.id = dfi.documento_fiscal_id
    and df.tenant_id = dfi.tenant_id
    and df.deleted_at is null
    and df.operacao = 'ENTRADA'
    and df.source_nf_entrada_id is not null
    and dfi.deleted_at is null
    and dfi.natureza = 'CREDITO'
    and dfi.imposto in ('ICMS', 'PIS', 'COFINS', 'IPI')
    and dfi.valor_ajustado = 0
    and coalesce(dfi.valor_calculado, 0) > 0;

  -- Backfill de documentos de entrada com valores em nf_entrada_itens e sem credito fiscal gravado.
  for r in
    select df.id
    from f.documento_fiscal df
    where df.deleted_at is null
      and df.operacao = 'ENTRADA'
      and coalesce(df.natureza, 'PRODUTO') = 'PRODUTO'
      and df.source_nf_entrada_id is not null
      and exists (
        select 1
        from public.nf_entrada_itens i
        where i.tenant_id = df.tenant_id
          and i.empresa_id = df.empresa_id
          and i.nf_entrada_id = df.source_nf_entrada_id
          and (
            coalesce(i.v_icms, 0) > 0
            or coalesce(i.v_pis, 0) > 0
            or coalesce(i.v_cofins, 0) > 0
            or coalesce(i.v_ipi, 0) > 0
          )
      )
  loop
    perform f.nfe_sync_creditos_entrada_from_nf_itens(r.id);
  end loop;
end
$$;

commit;
