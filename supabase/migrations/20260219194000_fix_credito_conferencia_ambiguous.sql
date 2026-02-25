-- Fix RPC f.fn_imposto_credito_conferencia_range ambiguous column references

create or replace function f.fn_imposto_credito_conferencia_range(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_comp_ini date,
  p_comp_fim date
) returns table(
  competencia_date date,
  imposto text,
  valor_provisionado numeric,
  valor_efetivo numeric,
  valor_pendente_revisao numeric,
  valor_nao_creditavel numeric,
  qtd_itens_pendentes bigint,
  qtd_nfs bigint
)
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to off
as $$
begin
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  if p_tenant_id is null then raise exception 'tenant_id e obrigatorio.'; end if;
  if p_empresa_id is null then raise exception 'empresa_id e obrigatorio.'; end if;
  if p_comp_ini is null or p_comp_fim is null then raise exception 'Informe p_comp_ini e p_comp_fim'; end if;
  if p_comp_fim <= p_comp_ini then raise exception 'Intervalo invalido: p_comp_fim deve ser > p_comp_ini'; end if;

  if auth.uid() is not null then
    if public.current_tenant_id() is distinct from p_tenant_id then
      raise exception 'Tenant mismatch';
    end if;
    if public.current_empresa_id() is distinct from p_empresa_id then
      raise exception 'Empresa mismatch';
    end if;
    if not f.has_finance_access(p_tenant_id, p_empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  return query
  with docs as (
    select
      df.id as documento_fiscal_id,
      df.source_nf_entrada_id,
      df.competencia_date
    from f.documento_fiscal df
    where df.tenant_id = p_tenant_id
      and df.empresa_id = p_empresa_id
      and df.deleted_at is null
      and df.operacao = 'ENTRADA'
      and df.competencia_date >= p_comp_ini
      and df.competencia_date < p_comp_fim
      and df.source_nf_entrada_id is not null
  ),
  itens as (
    select
      d.competencia_date,
      d.documento_fiscal_id,
      ni.icms_credito_modo,
      ni.pis_credito_modo,
      ni.cofins_credito_modo,
      coalesce(ni.icms_credito_valor_elegivel,0)::numeric as icms_elegivel,
      coalesce(ni.pis_credito_valor_elegivel,0)::numeric as pis_elegivel,
      coalesce(ni.cofins_credito_valor_elegivel,0)::numeric as cofins_elegivel
    from docs d
    join public.nf_entrada_itens ni
      on ni.nf_entrada_id = d.source_nf_entrada_id
  ),
  itens_unpivot as (
    select it.competencia_date, it.documento_fiscal_id, 'ICMS'::text as imposto, it.icms_credito_modo as modo, it.icms_elegivel as valor from itens it
    union all
    select it.competencia_date, it.documento_fiscal_id, 'PIS'::text as imposto, it.pis_credito_modo as modo, it.pis_elegivel as valor from itens it
    union all
    select it.competencia_date, it.documento_fiscal_id, 'COFINS'::text as imposto, it.cofins_credito_modo as modo, it.cofins_elegivel as valor from itens it
  ),
  prov as (
    select
      i.competencia_date,
      i.imposto,
      sum(case when i.modo in ('CREDITA_IMEDIATO','CREDITA_PARCELADO') then i.valor else 0 end)::numeric as valor_provisionado,
      sum(case when i.modo = 'PENDENTE_REVISAO' then i.valor else 0 end)::numeric as valor_pendente_revisao,
      sum(case when i.modo = 'NAO_CREDITA' then i.valor else 0 end)::numeric as valor_nao_creditavel,
      count(*) filter (where i.modo = 'PENDENTE_REVISAO')::bigint as qtd_itens_pendentes,
      count(distinct i.documento_fiscal_id)::bigint as qtd_nfs
    from itens_unpivot i
    group by i.competencia_date, i.imposto
  ),
  efet as (
    select
      df.competencia_date,
      dfi.imposto,
      sum(coalesce(dfi.valor_ajustado, dfi.valor_calculado, 0))::numeric as valor_efetivo
    from f.documento_fiscal_imposto dfi
    join f.documento_fiscal df
      on df.id = dfi.documento_fiscal_id
     and df.tenant_id = dfi.tenant_id
    where dfi.tenant_id = p_tenant_id
      and df.empresa_id = p_empresa_id
      and dfi.deleted_at is null
      and df.deleted_at is null
      and df.operacao = 'ENTRADA'
      and dfi.natureza = 'CREDITO'
      and dfi.imposto in ('ICMS','PIS','COFINS')
      and df.competencia_date >= p_comp_ini
      and df.competencia_date < p_comp_fim
    group by df.competencia_date, dfi.imposto
  )
  select
    coalesce(p.competencia_date, e.competencia_date) as competencia_date,
    coalesce(p.imposto, e.imposto) as imposto,
    coalesce(p.valor_provisionado, 0)::numeric as valor_provisionado,
    coalesce(e.valor_efetivo, 0)::numeric as valor_efetivo,
    coalesce(p.valor_pendente_revisao, 0)::numeric as valor_pendente_revisao,
    coalesce(p.valor_nao_creditavel, 0)::numeric as valor_nao_creditavel,
    coalesce(p.qtd_itens_pendentes, 0)::bigint as qtd_itens_pendentes,
    coalesce(p.qtd_nfs, 0)::bigint as qtd_nfs
  from prov p
  full outer join efet e
    on e.competencia_date = p.competencia_date
   and e.imposto = p.imposto
  order by 1 asc, 2 asc;
end;
$$;
revoke all on function f.fn_imposto_credito_conferencia_range(uuid, uuid, date, date) from public;
grant execute on function f.fn_imposto_credito_conferencia_range(uuid, uuid, date, date) to authenticated;
grant execute on function f.fn_imposto_credito_conferencia_range(uuid, uuid, date, date) to service_role;
