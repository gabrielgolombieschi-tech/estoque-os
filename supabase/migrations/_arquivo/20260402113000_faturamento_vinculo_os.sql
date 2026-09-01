create or replace function f.fn_upsert_ar_from_documento_fiscal_v2(
  p_documento_fiscal_id uuid,
  p_old_valor_total numeric default null
) returns uuid
language plpgsql
security definer
set search_path to 'f', 'public', 'a'
as $$
declare
  v_df record;
  v_titulo_id uuid;
  v_valor numeric(15,2);
  v_desc text;
  v_venc date;
  v_plano_contas_id uuid;
  v_valor_aberto_old numeric(15,2);
  v_rateio_count integer;
begin
  select * into v_df
  from f.documento_fiscal
  where id = p_documento_fiscal_id
    and deleted_at is null;

  if not found then return null; end if;

  if coalesce(v_df.operacao,'') <> 'SAIDA' then return null; end if;
  if coalesce(v_df.natureza,'') <> 'SERVICO' then return null; end if;
  if coalesce(v_df.nfse_status,'') <> 'EMITIDA' then return null; end if;
  if v_df.cliente_id is null then return null; end if;

  v_valor := coalesce(v_df.valor_total, 0);
  v_desc := concat(coalesce(v_df.modelo,'DOC'), ' ', coalesce(v_df.numero,''), '/', coalesce(v_df.serie,''));
  if btrim(v_desc) = '' then v_desc := 'FATURAMENTO'; end if;

  v_venc := coalesce(v_df.emissao_date, current_date) + 15;

  select pc.id into v_plano_contas_id
  from f.plano_contas pc
  where pc.tenant_id = v_df.tenant_id
    and pc.codigo = '3.01'
    and pc.deleted_at is null
  limit 1;

  if v_plano_contas_id is null then
    raise exception 'Plano de contas padrao (codigo=3.01) nao encontrado para tenant %', v_df.tenant_id;
  end if;

  select t.id, t.valor_aberto
    into v_titulo_id, v_valor_aberto_old
  from f.titulo t
  where t.tenant_id = v_df.tenant_id
    and t.empresa_id = v_df.empresa_id
    and t.tipo = 'AR'
    and t.documento_fiscal_id = v_df.id
    and t.deleted_at is null
  limit 1;

  if v_titulo_id is null then
    insert into f.titulo (
      tenant_id, empresa_id, tipo, status, origem,
      cliente_id, documento_fiscal_id, descricao,
      emissao_date, competencia_date,
      valor_total, valor_aberto
    ) values (
      v_df.tenant_id, v_df.empresa_id, 'AR', 'PENDENTE', 'FATURAMENTO',
      v_df.cliente_id, v_df.id, v_desc,
      v_df.emissao_date, v_df.competencia_date,
      v_valor, v_valor
    )
    returning id into v_titulo_id;

    insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
    values (v_df.tenant_id, v_titulo_id, '1', v_venc, v_valor, v_valor);

    insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, os_id, percentual, valor)
    values (v_df.tenant_id, v_titulo_id, v_plano_contas_id, v_df.os_id_import, 100.0000, v_valor);

  else
    update f.titulo
    set
      cliente_id = v_df.cliente_id,
      descricao = v_desc,
      emissao_date = v_df.emissao_date,
      competencia_date = v_df.competencia_date,
      valor_total = v_valor,
      valor_aberto = case
        when p_old_valor_total is not null and coalesce(valor_aberto,0) = coalesce(p_old_valor_total,0) then v_valor
        when coalesce(valor_aberto,0) = coalesce(valor_total,0) then v_valor
        else valor_aberto
      end
    where id = v_titulo_id;

    update f.titulo_parcela
    set
      vencimento_date = v_venc,
      valor = v_valor,
      valor_aberto = case
        when p_old_valor_total is not null and coalesce(valor_aberto,0) = coalesce(p_old_valor_total,0) then v_valor
        when coalesce(valor_aberto,0) = coalesce(valor,0) then v_valor
        else valor_aberto
      end
    where titulo_id = v_titulo_id
      and tenant_id = v_df.tenant_id
      and numero = '1'
      and deleted_at is null;

    update f.titulo_rateio
    set
      plano_contas_id = v_plano_contas_id,
      os_id = v_df.os_id_import,
      percentual = 100.0000,
      valor = v_valor
    where titulo_id = v_titulo_id
      and tenant_id = v_df.tenant_id
      and deleted_at is null;

    get diagnostics v_rateio_count = row_count;

    if coalesce(v_rateio_count, 0) = 0 then
      insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, os_id, percentual, valor)
      values (v_df.tenant_id, v_titulo_id, v_plano_contas_id, v_df.os_id_import, 100.0000, v_valor);
    end if;
  end if;

  return v_titulo_id;
end;
$$;

create or replace function f.fn_upsert_ar_from_nfe_venda(
  p_documento_fiscal_id uuid,
  p_old_valor_total numeric default null
) returns uuid
language plpgsql
security definer
set search_path to 'f', 'public', 'a'
as $$
declare
  v_df record;
  v_titulo_id uuid;
  v_valor numeric(15,2);
  v_desc text;
  v_venc date;
  v_plano_contas_id uuid;
  v_rateio_count integer;
begin
  select * into v_df
  from f.documento_fiscal
  where id = p_documento_fiscal_id
    and deleted_at is null;

  if not found then return null; end if;

  if coalesce(v_df.operacao,'') <> 'SAIDA' then return null; end if;
  if coalesce(v_df.natureza,'') <> 'PRODUTO' then return null; end if;
  if coalesce(v_df.nfe_status,'') <> 'EMITIDA' then return null; end if;

  if v_df.cliente_id is null then
    raise exception 'NF-e de faturamento precisa de cliente_id para gerar Contas a Receber.';
  end if;

  v_valor := coalesce(v_df.valor_total, 0);
  v_desc := concat('NFE ', coalesce(v_df.numero,''), '/', coalesce(v_df.serie,''));
  if btrim(v_desc) = '' then v_desc := 'FATURAMENTO NFE'; end if;

  v_venc := coalesce(v_df.emissao_date, current_date) + 15;

  select pc.id into v_plano_contas_id
  from f.plano_contas pc
  where pc.tenant_id = v_df.tenant_id
    and pc.codigo = '3.01'
    and pc.deleted_at is null
  limit 1;

  if v_plano_contas_id is null then
    raise exception 'Plano de contas padrao (codigo=3.01) nao encontrado para tenant %', v_df.tenant_id;
  end if;

  select t.id into v_titulo_id
  from f.titulo t
  where t.tenant_id = v_df.tenant_id
    and t.empresa_id = v_df.empresa_id
    and t.tipo = 'AR'
    and t.documento_fiscal_id = v_df.id
    and t.deleted_at is null
  limit 1;

  if v_titulo_id is null then
    insert into f.titulo (
      tenant_id, empresa_id,
      tipo, status, origem,
      cliente_id,
      documento_fiscal_id,
      descricao,
      emissao_date, competencia_date,
      valor_total, valor_aberto
    ) values (
      v_df.tenant_id, v_df.empresa_id,
      'AR', 'PENDENTE', 'FATURAMENTO',
      v_df.cliente_id,
      v_df.id,
      v_desc,
      v_df.emissao_date, v_df.competencia_date,
      v_valor, v_valor
    )
    returning id into v_titulo_id;

    insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
    values (v_df.tenant_id, v_titulo_id, '1', v_venc, v_valor, v_valor);

    insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, os_id, percentual, valor)
    values (v_df.tenant_id, v_titulo_id, v_plano_contas_id, v_df.os_id_import, 100.0000, v_valor);

  else
    update f.titulo
    set
      cliente_id = v_df.cliente_id,
      descricao = v_desc,
      emissao_date = v_df.emissao_date,
      competencia_date = v_df.competencia_date,
      valor_total = v_valor,
      valor_aberto = case
        when p_old_valor_total is not null and coalesce(valor_aberto,0) = coalesce(p_old_valor_total,0) then v_valor
        when coalesce(valor_aberto,0) = coalesce(valor_total,0) then v_valor
        else valor_aberto
      end
    where id = v_titulo_id;

    update f.titulo_parcela
    set
      vencimento_date = v_venc,
      valor = v_valor,
      valor_aberto = case
        when p_old_valor_total is not null and coalesce(valor_aberto,0) = coalesce(p_old_valor_total,0) then v_valor
        when coalesce(valor_aberto,0) = coalesce(valor,0) then v_valor
        else valor_aberto
      end
    where titulo_id = v_titulo_id
      and tenant_id = v_df.tenant_id
      and numero = '1'
      and deleted_at is null;

    update f.titulo_rateio
    set
      percentual = 100.0000,
      valor = v_valor,
      plano_contas_id = v_plano_contas_id,
      os_id = v_df.os_id_import
    where titulo_id = v_titulo_id
      and tenant_id = v_df.tenant_id
      and deleted_at is null;

    get diagnostics v_rateio_count = row_count;

    if coalesce(v_rateio_count, 0) = 0 then
      insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, os_id, percentual, valor)
      values (v_df.tenant_id, v_titulo_id, v_plano_contas_id, v_df.os_id_import, 100.0000, v_valor);
    end if;
  end if;

  return v_titulo_id;
end;
$$;

drop trigger if exists trg_documento_fiscal__ar_nfe on f.documento_fiscal;
create trigger trg_documento_fiscal__ar_nfe
after insert or update of nfe_status, cliente_id, valor_total, emissao_date, competencia_date, os_id_import
on f.documento_fiscal
for each row
execute function f.trg_documento_fiscal__ar_nfe();

drop trigger if exists trg_documento_fiscal__ar_nfse on f.documento_fiscal;
create trigger trg_documento_fiscal__ar_nfse
after insert or update of nfse_status, cliente_id, valor_total, emissao_date, competencia_date, os_id_import
on f.documento_fiscal
for each row
execute function f.trg_documento_fiscal__ar_nfse();

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
begin
  if p_os_id is not null then
    perform 1
    from public.ordens_servico os
    where os.id = p_os_id
      and os.tenant_id = p_tenant_id
      and os.empresa_id = p_empresa_id
      and coalesce(os.status, '') <> 'cancelada';

    if not found then
      raise exception 'OS invalida (id=%) para este tenant/empresa.', p_os_id;
    end if;
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
