begin;

-- Root-cause fix: consolidated impostos must use effective value
-- (valor_ajustado when present, otherwise valor_calculado),
-- same business logic expected by fiscal conference in the UI.
create or replace view f.vw_imposto_apuracao_mensal as
select
  df.tenant_id,
  df.empresa_id,
  df.competencia_date,
  df.operacao,
  dfi.imposto,
  dfi.natureza,
  sum(coalesce(dfi.base_calculo, 0))::numeric as base_total,
  sum(coalesce(dfi.valor_ajustado, dfi.valor_calculado, 0))::numeric as valor_total_calculado,
  sum(coalesce(dfi.valor_ajustado, 0))::numeric as valor_total_ajustado,
  count(distinct dfi.documento_fiscal_id)::bigint as qtd_documentos
from f.documento_fiscal_imposto dfi
join f.documento_fiscal df
  on df.id = dfi.documento_fiscal_id
  and df.tenant_id = dfi.tenant_id
where df.deleted_at is null
  and dfi.deleted_at is null
  and df.competencia_date is not null
group by
  df.tenant_id,
  df.empresa_id,
  df.competencia_date,
  df.operacao,
  dfi.imposto,
  dfi.natureza;

revoke all on f.vw_imposto_apuracao_mensal from public;

notify pgrst, 'reload schema';
commit;
