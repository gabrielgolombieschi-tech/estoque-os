begin;

create or replace function public.faturamento_sync_titulo_ar_parcelas(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_documento_fiscal_id uuid,
  p_parcelas_json jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = 'public','f','a'
as $$
declare
  v_df record;
  v_titulo_id uuid;
  v_parcelas jsonb := coalesce(p_parcelas_json, '[]'::jsonb);
  v_i int := 0;
  v_el jsonb;
  v_num text;
  v_venc date;
  v_val numeric(15,2);
  v_soma numeric(15,2) := 0;
  v_tem_recebimento boolean := false;
  v_venc_padrao date;
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  if p_tenant_id is null then
    raise exception 'tenant_id obrigatorio';
  end if;
  if p_empresa_id is null then
    raise exception 'empresa_id obrigatorio';
  end if;
  if p_documento_fiscal_id is null then
    raise exception 'documento_fiscal_id obrigatorio';
  end if;

  perform set_config('app.tenant_id', p_tenant_id::text, true);
  perform set_config('app.current_empresa_id', p_empresa_id::text, true);

  if not exists (
    select 1
    from public.tenant_memberships tm
    where tm.user_id = auth.uid()
      and tm.tenant_id = p_tenant_id
      and tm.status in ('active','ativo')
  ) then
    raise exception 'Tenant nao autorizado';
  end if;

  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'empresa_memberships') then
    if not exists (
      select 1
      from public.empresa_memberships em
      where em.user_id = auth.uid()
        and em.tenant_id = p_tenant_id
        and em.empresa_id = p_empresa_id
        and em.status = 'active'
    ) then
      raise exception 'Sem acesso a esta empresa';
    end if;
  end if;

  if not (
    public.can('xml_import','execute')
    or public.can('xml_import_faturamento','execute')
    or f.has_finance_access(p_tenant_id, p_empresa_id)
  ) then
    raise exception 'Sem permissao para gerar contas a receber';
  end if;

  select
    df.id,
    df.tenant_id,
    df.empresa_id,
    df.cliente_id,
    df.emissao_date,
    df.competencia_date,
    coalesce(df.valor_total, 0)::numeric(15,2) as valor_total,
    df.modelo,
    df.numero,
    df.serie,
    df.natureza,
    df.operacao,
    df.nfe_status,
    df.nfse_status
  into v_df
  from f.documento_fiscal df
  where df.id = p_documento_fiscal_id
    and df.tenant_id = p_tenant_id
    and df.empresa_id = p_empresa_id
    and df.operacao = 'SAIDA'
    and df.natureza in ('PRODUTO', 'SERVICO')
    and df.deleted_at is null
  limit 1;

  if v_df.id is null then
    raise exception 'Documento fiscal nao encontrado para tenant/empresa informado.';
  end if;

  if v_df.cliente_id is null then
    raise exception 'cliente_id obrigatorio para gerar contas a receber.';
  end if;

  if v_df.natureza = 'SERVICO' and coalesce(v_df.nfse_status, '') <> 'EMITIDA' then
    raise exception 'NFS-e precisa estar EMITIDA para sincronizar contas a receber.';
  end if;

  if v_df.natureza = 'PRODUTO' and coalesce(v_df.nfe_status, '') <> 'EMITIDA' then
    raise exception 'NF-e precisa estar EMITIDA para sincronizar contas a receber.';
  end if;

  select t.id
    into v_titulo_id
  from f.titulo t
  where t.tenant_id = p_tenant_id
    and t.empresa_id = p_empresa_id
    and t.tipo = 'AR'
    and t.documento_fiscal_id = v_df.id
    and t.deleted_at is null
  limit 1;

  if v_titulo_id is null then
    if v_df.natureza = 'SERVICO' then
      v_titulo_id := f.fn_upsert_ar_from_documento_fiscal_v2(v_df.id, null);
    else
      v_titulo_id := f.fn_upsert_ar_from_nfe_venda(v_df.id, null);
    end if;
  end if;

  if v_titulo_id is null then
    raise exception 'Nao foi possivel localizar/gerar o titulo AR.';
  end if;

  select exists (
    select 1
    from f.titulo_parcela tp
    join f.pagamento_item pi
      on pi.titulo_parcela_id = tp.id
     and pi.deleted_at is null
    where tp.tenant_id = p_tenant_id
      and tp.titulo_id = v_titulo_id
      and tp.deleted_at is null
  ) into v_tem_recebimento;

  if coalesce(v_tem_recebimento, false) then
    raise exception 'Nao e possivel ajustar parcelas: titulo ja possui recebimentos aplicados.';
  end if;

  update f.titulo_parcela
  set deleted_at = now(),
      updated_at = now(),
      updated_by = a.fn_current_usuario_id()
  where tenant_id = p_tenant_id
    and titulo_id = v_titulo_id
    and deleted_at is null;

  if jsonb_typeof(v_parcelas) = 'array' and jsonb_array_length(v_parcelas) > 0 then
    for v_el in select * from jsonb_array_elements(v_parcelas)
    loop
      v_num := coalesce(nullif(trim(v_el->>'numero'),''), lpad((v_i+1)::text, 3, '0'));
      v_num := regexp_replace(v_num, '\D', '', 'g');
      if v_num is null or v_num = '' then
        v_num := lpad((v_i+1)::text, 3, '0');
      else
        v_num := lpad(v_num, 3, '0');
      end if;

      v_venc := coalesce(nullif(trim(v_el->>'vencimento'), '')::date, nullif(trim(v_el->>'data'), '')::date);
      v_val := round(coalesce(nullif(trim(v_el->>'valor'), '')::numeric, 0), 2);

      if v_venc is null then
        raise exception 'Parcela sem data de vencimento (numero=%).', v_num;
      end if;
      if v_val <= 0 then
        raise exception 'Parcela com valor invalido (numero=% valor=%).', v_num, v_val;
      end if;

      insert into f.titulo_parcela (
        tenant_id,
        titulo_id,
        numero,
        vencimento_date,
        valor,
        valor_aberto
      )
      values (
        p_tenant_id,
        v_titulo_id,
        v_num,
        v_venc,
        v_val,
        v_val
      );

      v_soma := round(v_soma + v_val, 2);
      v_i := v_i + 1;
    end loop;

    if abs(v_soma - v_df.valor_total) > 0.05 then
      raise exception 'Soma das parcelas (%) difere do total do documento (%).', v_soma, v_df.valor_total;
    end if;
  else
    v_venc_padrao := coalesce(v_df.emissao_date, current_date) + 15;

    insert into f.titulo_parcela (
      tenant_id,
      titulo_id,
      numero,
      vencimento_date,
      valor,
      valor_aberto
    )
    values (
      p_tenant_id,
      v_titulo_id,
      '001',
      v_venc_padrao,
      v_df.valor_total,
      v_df.valor_total
    );
  end if;

  update f.titulo t
  set cliente_id = v_df.cliente_id,
      emissao_date = v_df.emissao_date,
      competencia_date = v_df.competencia_date,
      valor_total = v_df.valor_total,
      valor_aberto = case
        when coalesce(t.status, '') in ('PAGO', 'CANCELADO') then t.valor_aberto
        else (
          select coalesce(sum(tp.valor_aberto), 0)
          from f.titulo_parcela tp
          where tp.tenant_id = p_tenant_id
            and tp.titulo_id = v_titulo_id
            and tp.deleted_at is null
        )
      end,
      updated_at = now(),
      updated_by = a.fn_current_usuario_id()
  where t.id = v_titulo_id
    and t.tenant_id = p_tenant_id
    and t.deleted_at is null;

  return v_titulo_id;
end;
$$;

create or replace function public.nfse_sync_titulo_ar_parcelas(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_documento_fiscal_id uuid,
  p_parcelas_json jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = 'public','f','a'
as $$
begin
  return public.faturamento_sync_titulo_ar_parcelas(
    p_tenant_id,
    p_empresa_id,
    p_documento_fiscal_id,
    p_parcelas_json
  );
end;
$$;

grant execute on function public.faturamento_sync_titulo_ar_parcelas(uuid, uuid, uuid, jsonb) to authenticated;
grant execute on function public.nfse_sync_titulo_ar_parcelas(uuid, uuid, uuid, jsonb) to authenticated;

commit;
