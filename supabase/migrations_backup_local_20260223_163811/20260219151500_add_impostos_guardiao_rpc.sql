-- Expose fiscal consistency checks (XML x documento_fiscal_imposto) to app/API consumers.
-- Source of truth: r.r_guardiao_impostos_docs

create or replace function f.fn_imposto_guardiao_range(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_comp_ini date,
  p_comp_fim date,
  p_operacao text default null,
  p_tipo text default null,
  p_imposto text default null
) returns table(
  tenant_id uuid,
  empresa_id uuid,
  competencia_date date,
  documento_fiscal_id uuid,
  nf_entrada_id bigint,
  chave_acesso text,
  operacao text,
  tipo text,
  imposto text,
  natureza_esperada text,
  esperado numeric,
  encontrado numeric,
  diff numeric,
  detalhe text
)
language plpgsql
security definer
set search_path to 'f', 'r', 'public', 'a', 'c'
set row_security to 'off'
as $$
begin
  if auth.uid() is null then
    if current_user not in ('postgres', 'service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  if p_tenant_id is null then
    raise exception 'tenant_id e obrigatorio.';
  end if;
  if p_empresa_id is null then
    raise exception 'empresa_id e obrigatorio.';
  end if;
  if p_comp_ini is null or p_comp_fim is null then
    raise exception 'Informe p_comp_ini e p_comp_fim';
  end if;
  if p_comp_fim <= p_comp_ini then
    raise exception 'Intervalo invalido: p_comp_fim deve ser > p_comp_ini';
  end if;

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
    g.tenant_id,
    g.empresa_id,
    g.competencia_date,
    g.documento_fiscal_id,
    g.nf_entrada_id,
    g.chave_acesso,
    g.operacao,
    g.tipo,
    g.imposto,
    g.natureza_esperada,
    g.esperado,
    g.encontrado,
    g.diff,
    g.detalhe
  from r.r_guardiao_impostos_docs g
  where g.tenant_id = p_tenant_id
    and g.empresa_id = p_empresa_id
    and g.competencia_date >= p_comp_ini
    and g.competencia_date < p_comp_fim
    and (p_operacao is null or g.operacao = p_operacao)
    and (p_tipo is null or g.tipo = p_tipo)
    and (p_imposto is null or g.imposto = p_imposto)
  order by g.competencia_date asc, g.tipo asc, g.imposto asc nulls last, g.documento_fiscal_id asc;
end;
$$;

revoke all on function f.fn_imposto_guardiao_range(uuid, uuid, date, date, text, text, text) from public;
grant execute on function f.fn_imposto_guardiao_range(uuid, uuid, date, date, text, text, text) to authenticated;
grant execute on function f.fn_imposto_guardiao_range(uuid, uuid, date, date, text, text, text) to service_role;
