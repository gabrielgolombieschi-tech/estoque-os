-- f.fn_os_saldo_a_faturar: a reserva da solicitacao deixa de contar quando o
-- documento vinculado ja esta EMITIDA tambem pela NFS-e (nfse_status). Antes so
-- nfe_status era olhado e a primeira NFS-e real (OS 319, 05/09/2026) ficou
-- contada duas vezes: faturado 18.166,99 e reservado 18.166,99.
-- Baseline: versao da migration 20260905170000 (unica diferenca: a linha do
-- "not exists" com coalesce(d.nfe_status, d.nfse_status)).
create or replace function f.fn_os_saldo_a_faturar(p_tenant_id uuid, p_empresa_id uuid, p_os_id integer)
returns table (valor_pedido numeric, valor_faturado numeric, valor_reservado numeric, saldo numeric, usa_relatorio_hh boolean)
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_os public.ordens_servico%rowtype;
  v_valor_pedido numeric(14,2);
  v_valor_faturado numeric(14,2);
  v_valor_reservado numeric(14,2);
begin
  if p_tenant_id is null or p_empresa_id is null or p_os_id is null then
    raise exception using errcode = '22023', message = 'Tenant, empresa e OS/OV sao obrigatorios.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from p_tenant_id
    or public.current_empresa_id() is distinct from p_empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para consultar o faturamento desta empresa.';
  end if;

  select os.* into v_os
  from public.ordens_servico os
  where os.tenant_id = p_tenant_id and os.empresa_id = p_empresa_id and os.id = p_os_id and os.tipo_documento in ('OS', 'OV');
  if not found then
    raise exception using errcode = 'P0002', message = format('OS/OV %s nao encontrada nesta empresa.', p_os_id);
  end if;

  if v_os.usa_relatorio_hh then
    select coalesce(hh.total_hh, 0) into v_valor_pedido
    from public.vw_hh_total_os hh
    where hh.tenant_id = p_tenant_id and hh.empresa_id = p_empresa_id and hh.os_id = p_os_id;
    v_valor_pedido := coalesce(v_valor_pedido, 0);
  else
    v_valor_pedido := coalesce(v_os.orcado, 0);
  end if;

  select coalesce(sum(
    case
      when upper(coalesce(df.modelo, '')) = 'NFSE' then coalesce(df.valor_total, 0)
      else greatest(coalesce(df.valor_produtos, df.valor_total, 0) - coalesce(df.valor_desconto, 0), 0)
    end
  ), 0)
  into v_valor_faturado
  from f.documento_fiscal df
  where df.tenant_id = p_tenant_id and df.empresa_id = p_empresa_id and df.os_id_import = p_os_id
    and df.operacao = 'SAIDA' and df.deleted_at is null
    and (
      (upper(coalesce(df.modelo, '')) = 'NFSE' and upper(coalesce(df.nfse_status, '')) = 'EMITIDA')
      or (upper(coalesce(df.modelo, '')) <> 'NFSE' and (nullif(btrim(df.nfe_status), '') is null or upper(df.nfe_status) = 'EMITIDA'))
    );

  select coalesce(sum(round(greatest(si.quantidade * si.valor_unitario - coalesce(si.valor_desconto, 0), 0), 2)), 0)
  into v_valor_reservado
  from f.solicitacao_faturamento sf
  join f.solicitacao_item si
    on si.tenant_id = sf.tenant_id and si.empresa_id = sf.empresa_id and si.solicitacao_id = sf.id
  where sf.tenant_id = p_tenant_id and sf.empresa_id = p_empresa_id
    and sf.status <> 'CANCELADA'
    and si.origem_tipo = v_os.tipo_documento
    and si.origem_id = p_os_id::text
    and not exists (
      select 1
      from f.documento_fiscal_emissao e
      join f.documento_fiscal d on d.tenant_id = e.tenant_id and d.empresa_id = e.empresa_id and d.id = e.documento_fiscal_id
      where e.tenant_id = sf.tenant_id and e.empresa_id = sf.empresa_id and e.solicitacao_id = sf.id
        and d.deleted_at is null and upper(coalesce(d.nfe_status, d.nfse_status, '')) = 'EMITIDA'
    )
    and coalesce((
      select e.status
      from f.documento_fiscal_emissao e
      where e.tenant_id = sf.tenant_id and e.empresa_id = sf.empresa_id and e.solicitacao_id = sf.id
      order by e.created_at desc, e.documento_fiscal_id desc
      limit 1
    ), 'RASCUNHO') not in ('REJEITADA', 'ERRO', 'CANCELADA');

  valor_pedido := round(v_valor_pedido, 2);
  valor_faturado := round(v_valor_faturado, 2);
  valor_reservado := round(v_valor_reservado, 2);
  saldo := round(v_valor_pedido - v_valor_faturado - v_valor_reservado, 2);
  usa_relatorio_hh := coalesce(v_os.usa_relatorio_hh, false);
  return next;
end;
$$;
