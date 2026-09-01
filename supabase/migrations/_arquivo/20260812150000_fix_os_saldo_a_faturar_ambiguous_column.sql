-- fn_os_saldo_a_faturar (20260812140000) had an ambiguous column reference:
-- "usa_relatorio_hh" matched both the ordens_servico column and the OUT
-- parameter of the same name declared by `returns table (...)`. Qualify the
-- table columns with an alias to fix it.
create or replace function f.fn_os_saldo_a_faturar(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_os_id integer
)
returns table (
  valor_pedido numeric,
  valor_faturado numeric,
  saldo numeric,
  usa_relatorio_hh boolean
)
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_os record;
  v_valor_pedido numeric(14,2);
  v_valor_faturado numeric(14,2);
begin
  select o.id, o.orcado, o.usa_relatorio_hh into v_os
  from public.ordens_servico o
  where o.id = p_os_id
    and o.tenant_id = p_tenant_id
    and o.empresa_id = p_empresa_id;

  if not found then
    raise exception 'OS invalida (id=%) para este tenant/empresa.', p_os_id;
  end if;

  if v_os.usa_relatorio_hh then
    select coalesce(total_hh, 0) into v_valor_pedido
    from public.vw_hh_total_os
    where tenant_id = p_tenant_id
      and empresa_id = p_empresa_id
      and os_id = p_os_id;
    v_valor_pedido := coalesce(v_valor_pedido, 0);
  else
    v_valor_pedido := coalesce(v_os.orcado, 0);
  end if;

  select coalesce(sum(df.valor_total), 0) into v_valor_faturado
  from f.documento_fiscal df
  where df.tenant_id = p_tenant_id
    and df.empresa_id = p_empresa_id
    and df.os_id_import = p_os_id
    and df.operacao = 'SAIDA'
    and df.deleted_at is null
    and (
      (upper(coalesce(df.modelo, '')) = 'NFSE' and upper(coalesce(df.nfse_status, '')) = 'EMITIDA')
      or (
        upper(coalesce(df.modelo, '')) <> 'NFSE'
        and (nullif(btrim(df.nfe_status), '') is null or upper(df.nfe_status) = 'EMITIDA')
      )
    );

  valor_pedido := v_valor_pedido;
  valor_faturado := v_valor_faturado;
  saldo := v_valor_pedido - v_valor_faturado;
  usa_relatorio_hh := coalesce(v_os.usa_relatorio_hh, false);
  return next;
end;
$$;
