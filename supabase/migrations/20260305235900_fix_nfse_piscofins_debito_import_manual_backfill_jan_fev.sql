begin;

-- Sincroniza PIS/COFINS DEBITO para documentos NFSE de saida/servico.
-- Regras:
-- 1) Se existir valor em linha previa (DEBITO/RETENCAO), replica para DEBITO.
-- 2) Se nao existir e o documento for NFSE manual (chave NFSE-...), aplica aliquotas padrao cumulativas.
create or replace function f.fn_nfse_sync_piscofins_debito_doc(
  p_documento_fiscal_id uuid
)
returns void
language plpgsql
security definer
set search_path = f, public
set row_security = off
as $$
declare
  v_df f.documento_fiscal%rowtype;
  v_base_original numeric(15,2);
  v_deducoes numeric(15,2);
  v_base_calculo numeric(15,2);
  v_imposto text;
  v_default_aliq numeric(12,4);
  v_ref_valor numeric(15,2);
  v_ref_aliq numeric(12,4);
  v_ref_natureza text;
  v_valor numeric(15,2);
  v_aliq numeric(12,4);
begin
  if p_documento_fiscal_id is null then
    return;
  end if;

  select *
    into v_df
  from f.documento_fiscal df
  where df.id = p_documento_fiscal_id
    and df.deleted_at is null
  limit 1;

  if not found then
    return;
  end if;

  if coalesce(v_df.modelo, '') <> 'NFSE'
     or coalesce(v_df.operacao, '') <> 'SAIDA'
     or coalesce(v_df.natureza, '') <> 'SERVICO' then
    return;
  end if;

  v_base_original := round(coalesce(v_df.valor_servicos, v_df.valor_total, 0)::numeric, 2);
  v_deducoes := round(greatest(coalesce(v_df.material_valor, 0)::numeric, 0), 2);
  v_base_calculo := round(greatest(v_base_original - v_deducoes, 0), 2);

  foreach v_imposto in array array['PIS','COFINS'] loop
    v_default_aliq := case when v_imposto = 'PIS' then 0.6500 else 3.0000 end;
    v_ref_valor := null;
    v_ref_aliq := null;
    v_ref_natureza := null;
    v_valor := 0;
    v_aliq := 0;

    select
      round(coalesce(i.valor_ajustado, i.valor_calculado, 0)::numeric, 2) as valor,
      round(coalesce(i.aliquota, 0)::numeric, 4) as aliq,
      i.natureza
      into v_ref_valor, v_ref_aliq, v_ref_natureza
    from f.documento_fiscal_imposto i
    where i.tenant_id = v_df.tenant_id
      and i.documento_fiscal_id = v_df.id
      and i.imposto = v_imposto
      and i.deleted_at is null
    order by case when i.natureza = 'DEBITO' then 0 when i.natureza = 'RETENCAO' then 1 else 2 end,
             i.updated_at desc nulls last,
             i.created_at desc nulls last
    limit 1;

    if coalesce(v_ref_valor, 0) > 0 then
      v_valor := v_ref_valor;
      if coalesce(v_ref_aliq, 0) > 0 then
        v_aliq := v_ref_aliq;
      elsif v_base_calculo > 0 then
        v_aliq := round((v_valor * 100.0) / v_base_calculo, 4);
      else
        v_aliq := 0;
      end if;
    elsif v_base_calculo > 0 and coalesce(v_df.chave_acesso, '') like 'NFSE-%' then
      -- NFSE manual (sem XML importado): default cumulativo.
      v_aliq := v_default_aliq;
      v_valor := round((v_base_calculo * v_aliq) / 100.0, 2);
    end if;

    if coalesce(v_valor, 0) <= 0 then
      continue;
    end if;

    insert into f.documento_fiscal_imposto (
      id,
      tenant_id,
      documento_fiscal_id,
      imposto,
      natureza,
      base_original,
      deducoes,
      base_calculo,
      aliquota,
      valor_calculado,
      valor_ajustado,
      created_at,
      updated_at,
      deleted_at
    )
    values (
      gen_random_uuid(),
      v_df.tenant_id,
      v_df.id,
      v_imposto,
      'DEBITO',
      v_base_original,
      v_deducoes,
      v_base_calculo,
      coalesce(v_aliq, 0),
      v_valor,
      null,
      now(),
      now(),
      null
    )
    on conflict (tenant_id, documento_fiscal_id, imposto, natureza)
    do update set
      base_original = excluded.base_original,
      deducoes = excluded.deducoes,
      base_calculo = excluded.base_calculo,
      aliquota = excluded.aliquota,
      valor_calculado = excluded.valor_calculado,
      updated_at = now(),
      deleted_at = null;
  end loop;
end;
$$;

revoke all on function f.fn_nfse_sync_piscofins_debito_doc(uuid) from public;
grant execute on function f.fn_nfse_sync_piscofins_debito_doc(uuid) to service_role;
grant execute on function f.fn_nfse_sync_piscofins_debito_doc(uuid) to authenticated;

create or replace function f.trg_nfse_sync_piscofins_from_doc()
returns trigger
language plpgsql
security definer
set search_path = f, public
set row_security = off
as $$
begin
  if tg_op = 'DELETE' then
    return old;
  end if;

  if new.deleted_at is null
     and coalesce(new.modelo, '') = 'NFSE'
     and coalesce(new.operacao, '') = 'SAIDA'
     and coalesce(new.natureza, '') = 'SERVICO' then
    perform f.fn_nfse_sync_piscofins_debito_doc(new.id);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_nfse_sync_piscofins_from_doc on f.documento_fiscal;
create trigger trg_nfse_sync_piscofins_from_doc
after insert or update of valor_servicos, valor_total, material_valor, chave_acesso, modelo, operacao, natureza, deleted_at
on f.documento_fiscal
for each row
execute function f.trg_nfse_sync_piscofins_from_doc();

create or replace function f.trg_nfse_sync_piscofins_from_imposto_ret()
returns trigger
language plpgsql
security definer
set search_path = f, public
set row_security = off
as $$
begin
  if tg_op = 'DELETE' then
    return old;
  end if;

  if new.deleted_at is null
     and new.imposto in ('PIS','COFINS')
     and new.natureza = 'RETENCAO' then
    perform f.fn_nfse_sync_piscofins_debito_doc(new.documento_fiscal_id);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_nfse_sync_piscofins_from_imposto_ret on f.documento_fiscal_imposto;
create trigger trg_nfse_sync_piscofins_from_imposto_ret
after insert or update of valor_calculado, valor_ajustado, aliquota, natureza, deleted_at
on f.documento_fiscal_imposto
for each row
when (new.imposto in ('PIS','COFINS') and new.natureza = 'RETENCAO')
execute function f.trg_nfse_sync_piscofins_from_imposto_ret();

-- Backfill pontual solicitado: janeiro e fevereiro/2026.
do $$
declare
  r record;
begin
  for r in
    select df.id
    from f.documento_fiscal df
    where df.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
      and df.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
      and df.deleted_at is null
      and coalesce(df.modelo,'') = 'NFSE'
      and coalesce(df.operacao,'') = 'SAIDA'
      and coalesce(df.natureza,'') = 'SERVICO'
      and df.competencia_date >= date '2026-01-01'
      and df.competencia_date < date '2026-03-01'
  loop
    perform f.fn_nfse_sync_piscofins_debito_doc(r.id);
  end loop;
end $$;

notify pgrst, 'reload schema';
commit;
