begin;

-- Adjust credit-conference RPC to current schema (without legacy nf_entrada_itens credit-mode columns).
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
  with efet as (
    select
      df.competencia_date,
      dfi.imposto,
      sum(coalesce(dfi.valor_ajustado, dfi.valor_calculado, 0))::numeric as valor_efetivo,
      count(distinct df.id)::bigint as qtd_nfs
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
    e.competencia_date,
    e.imposto,
    e.valor_efetivo as valor_provisionado,
    e.valor_efetivo,
    0::numeric as valor_pendente_revisao,
    0::numeric as valor_nao_creditavel,
    0::bigint as qtd_itens_pendentes,
    e.qtd_nfs
  from efet e
  order by 1 asc, 2 asc;
end;
$$;

revoke all on function f.fn_imposto_credito_conferencia_range(uuid, uuid, date, date) from public;
grant execute on function f.fn_imposto_credito_conferencia_range(uuid, uuid, date, date) to authenticated;
grant execute on function f.fn_imposto_credito_conferencia_range(uuid, uuid, date, date) to service_role;

notify pgrst, 'reload schema';
commit;
