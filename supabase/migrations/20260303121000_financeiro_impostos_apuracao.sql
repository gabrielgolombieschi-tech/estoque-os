begin;
-- Apuração mensal de impostos (base + valor calculado/ajustado) por competência.
-- Fonte: f.documento_fiscal + f.documento_fiscal_imposto
--
-- A página /financeiro/impostos consome via RPCs abaixo (não acessa a view diretamente).

create or replace view f.vw_imposto_apuracao_mensal as
select
  df.tenant_id,
  df.empresa_id,
  df.competencia_date,
  df.operacao,
  dfi.imposto,
  dfi.natureza,
  sum(coalesce(dfi.base_calculo, 0))::numeric as base_total,
  sum(coalesce(dfi.valor_calculado, 0))::numeric as valor_total_calculado,
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
create or replace function f.fn_imposto_apuracao_range(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_comp_ini date,
  p_comp_fim date,
  p_operacao text default null,
  p_natureza text default null
)
returns table (
  tenant_id uuid,
  empresa_id uuid,
  competencia_date date,
  operacao text,
  imposto text,
  natureza text,
  base_total numeric,
  valor_total_calculado numeric,
  valor_total_ajustado numeric,
  qtd_documentos bigint
)
language plpgsql
security definer
set search_path = f, public, a, c
set row_security to off
as $$
begin
  -- ✅ permite SQL Editor (postgres/service_role), mas mantém segurança no app
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  if p_tenant_id is null then raise exception 'tenant_id é obrigatório.'; end if;
  if p_empresa_id is null then raise exception 'empresa_id é obrigatório.'; end if;
  if p_comp_ini is null or p_comp_fim is null then raise exception 'Informe p_comp_ini e p_comp_fim'; end if;
  if p_comp_fim <= p_comp_ini then raise exception 'Intervalo inválido: p_comp_fim deve ser > p_comp_ini'; end if;

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
  select
    v.tenant_id,
    v.empresa_id,
    v.competencia_date,
    v.operacao::text,
    v.imposto,
    v.natureza,
    v.base_total,
    v.valor_total_calculado,
    v.valor_total_ajustado,
    v.qtd_documentos
  from f.vw_imposto_apuracao_mensal v
  where v.tenant_id = p_tenant_id
    and v.empresa_id = p_empresa_id
    and v.competencia_date >= p_comp_ini
    and v.competencia_date < p_comp_fim
    and (p_operacao is null or v.operacao::text = p_operacao)
    and (p_natureza is null or v.natureza = p_natureza)
  order by v.competencia_date asc, v.imposto asc, v.natureza asc;
end;
$$;
revoke all on function f.fn_imposto_apuracao_range(uuid, uuid, date, date, text, text) from public;
grant execute on function f.fn_imposto_apuracao_range(uuid, uuid, date, date, text, text) to authenticated;
grant execute on function f.fn_imposto_apuracao_range(uuid, uuid, date, date, text, text) to service_role;
create or replace function f.fn_imposto_documentos_do_mes(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_competencia date,
  p_imposto text,
  p_nat text,
  p_operacao text default null
)
returns table (
  documento_fiscal_id uuid,
  chave_acesso text,
  emissao_date date,
  competencia_date date,
  operacao text,
  modelo text,
  serie text,
  numero text,
  valor_documento numeric,
  valor_imposto numeric
)
language plpgsql
security definer
set search_path = f, public, a, c
set row_security to off
as $$
begin
  -- ✅ permite SQL Editor (postgres/service_role), mas mantém segurança no app
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  if p_tenant_id is null then raise exception 'tenant_id é obrigatório.'; end if;
  if p_empresa_id is null then raise exception 'empresa_id é obrigatório.'; end if;
  if p_competencia is null then raise exception 'competencia_date é obrigatório.'; end if;
  if p_imposto is null or length(trim(p_imposto)) = 0 then raise exception 'imposto é obrigatório.'; end if;
  if p_nat is null or length(trim(p_nat)) = 0 then raise exception 'natureza é obrigatória.'; end if;

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
  select
    df.id as documento_fiscal_id,
    df.chave_acesso,
    df.emissao_date,
    df.competencia_date,
    df.operacao::text,
    df.modelo,
    df.serie,
    df.numero,
    coalesce(df.valor_total, 0)::numeric as valor_documento,
    sum(coalesce(dfi.valor_ajustado, dfi.valor_calculado, 0))::numeric as valor_imposto
  from f.documento_fiscal_imposto dfi
  join f.documento_fiscal df
    on df.id = dfi.documento_fiscal_id
    and df.tenant_id = dfi.tenant_id
  where df.deleted_at is null
    and dfi.deleted_at is null
    and df.tenant_id = p_tenant_id
    and df.empresa_id = p_empresa_id
    and df.competencia_date = p_competencia
    and dfi.imposto = p_imposto
    and dfi.natureza = p_nat
    and (p_operacao is null or df.operacao::text = p_operacao)
  group by
    df.id,
    df.chave_acesso,
    df.emissao_date,
    df.competencia_date,
    df.operacao,
    df.modelo,
    df.serie,
    df.numero,
    df.valor_total
  order by df.emissao_date desc nulls last, df.created_at desc;
end;
$$;
revoke all on function f.fn_imposto_documentos_do_mes(uuid, uuid, date, text, text, text) from public;
grant execute on function f.fn_imposto_documentos_do_mes(uuid, uuid, date, text, text, text) to authenticated;
grant execute on function f.fn_imposto_documentos_do_mes(uuid, uuid, date, text, text, text) to service_role;
notify pgrst, 'reload schema';
commit;
