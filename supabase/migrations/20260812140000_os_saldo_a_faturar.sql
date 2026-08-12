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
  select id, orcado, usa_relatorio_hh into v_os
  from public.ordens_servico
  where id = p_os_id
    and tenant_id = p_tenant_id
    and empresa_id = p_empresa_id;

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

revoke all on function f.fn_os_saldo_a_faturar(uuid, uuid, integer) from public;
revoke all on function f.fn_os_saldo_a_faturar(uuid, uuid, integer) from anon;
grant execute on function f.fn_os_saldo_a_faturar(uuid, uuid, integer) to authenticated, service_role;

comment on function f.fn_os_saldo_a_faturar(uuid, uuid, integer) is
  'Saldo a faturar de uma OS: valor do pedido (orcado, ou soma bruta de vw_hh_total_os quando usa_relatorio_hh) menos o total ja faturado (documento_fiscal SAIDA emitido vinculado via os_id_import).';

create or replace function public.import_nfse_saida_com_os(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_nfse_json jsonb,
  p_xml_raw text,
  p_os_id integer default null
) returns table(status text, message text, documento_fiscal_id uuid)
language plpgsql
security definer
set search_path = 'public', 'f', 'a'
as $$
declare
  v_result record;
  v_saldo record;
  v_valor_nota numeric(14,2);
begin
  if p_os_id is null then
    raise exception 'OS e obrigatoria para importar NFS-e.';
  end if;

  perform 1
  from public.ordens_servico os
  where os.id = p_os_id
    and os.tenant_id = p_tenant_id
    and os.empresa_id = p_empresa_id
    and coalesce(os.status, '') <> 'cancelada';

  if not found then
    raise exception 'OS invalida (id=%) para este tenant/empresa.', p_os_id;
  end if;

  v_valor_nota := coalesce((p_nfse_json -> 'valores' ->> 'valor_total')::numeric, 0);

  select * into v_saldo
  from f.fn_os_saldo_a_faturar(p_tenant_id, p_empresa_id, p_os_id);

  if v_valor_nota > (v_saldo.saldo + 0.01) then
    raise exception
      'Valor da NFS-e (R$ %) excede o saldo a faturar da OS % (R$ %). Ajuste o valor orcado da OS ou o valor da nota antes de importar.',
      to_char(v_valor_nota, 'FM999999990.00'),
      p_os_id,
      to_char(v_saldo.saldo, 'FM999999990.00');
  end if;

  for v_result in
    select *
    from public.import_nfse_saida(
      p_tenant_id => p_tenant_id,
      p_empresa_id => p_empresa_id,
      p_nfse_json => p_nfse_json,
      p_xml_raw => p_xml_raw
    )
  loop
    if v_result.documento_fiscal_id is not null and lower(coalesce(v_result.status, '')) <> 'error' then
      update f.documento_fiscal
      set os_id_import = p_os_id,
          updated_at = now()
      where id = v_result.documento_fiscal_id
        and tenant_id = p_tenant_id
        and empresa_id = p_empresa_id
        and deleted_at is null;
    end if;

    status := v_result.status;
    message := v_result.message;
    documento_fiscal_id := v_result.documento_fiscal_id;
    return next;
  end loop;

  return;
end;
$$;

grant execute on function public.import_nfse_saida_com_os(uuid, uuid, jsonb, text, integer) to authenticated;
