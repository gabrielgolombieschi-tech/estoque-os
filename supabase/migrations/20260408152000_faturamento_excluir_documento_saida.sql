begin;

create or replace function public.faturamento_excluir_documento_saida(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_documento_fiscal_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = 'public','f','a'
as $$
declare
  v_df record;
  v_now timestamptz := now();
  v_source_nf_entrada_id bigint;
  v_legacy_key text;
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
    public.can('financeiro','write')
    or public.can('financeiro','config')
    or f.has_finance_access(p_tenant_id, p_empresa_id)
  ) then
    raise exception 'Sem permissao para excluir documento fiscal de faturamento';
  end if;

  select
    df.id,
    df.tenant_id,
    df.empresa_id,
    df.operacao,
    df.natureza,
    df.nfe_status,
    df.nfse_status,
    df.source_nf_entrada_id,
    df.chave_acesso
  into v_df
  from f.documento_fiscal df
  where df.id = p_documento_fiscal_id
    and df.tenant_id = p_tenant_id
    and df.empresa_id = p_empresa_id
    and df.deleted_at is null
  limit 1;

  if v_df.id is null then
    raise exception 'Documento fiscal nao encontrado para tenant/empresa informado.';
  end if;

  if coalesce(v_df.operacao, '') <> 'SAIDA' then
    raise exception 'A exclusao suportada aqui e apenas para documentos de saida.';
  end if;

  if coalesce(v_df.natureza, '') not in ('PRODUTO', 'SERVICO') then
    raise exception 'Natureza de documento nao suportada para exclusao.';
  end if;

  if exists (
    select 1
    from f.titulo t
    join f.titulo_parcela tp
      on tp.titulo_id = t.id
     and tp.tenant_id = t.tenant_id
     and tp.deleted_at is null
    join f.pagamento_item pi
      on pi.titulo_parcela_id = tp.id
     and pi.deleted_at is null
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.documento_fiscal_id = v_df.id
      and t.deleted_at is null
  ) then
    raise exception 'O documento possui recebimento/baixa no financeiro. Estorne primeiro os titulos vinculados.';
  end if;

  if exists (
    select 1
    from f.titulo t
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.documento_fiscal_id = v_df.id
      and t.deleted_at is null
      and (
        upper(coalesce(t.status, '')) = 'PAGO'
        or abs(round(coalesce(t.valor_total, 0), 2) - round(coalesce(t.valor_aberto, 0), 2)) > 0.009
      )
  ) then
    raise exception 'O documento possui recebimento/baixa no financeiro. Estorne primeiro os titulos vinculados.';
  end if;

  update f.titulo_agendamento ta
  set deleted_at = v_now,
      updated_at = v_now
  where ta.tenant_id = p_tenant_id
    and ta.deleted_at is null
    and exists (
      select 1
      from f.titulo t
      where t.id = ta.titulo_id
        and t.tenant_id = p_tenant_id
        and t.empresa_id = p_empresa_id
        and t.documento_fiscal_id = v_df.id
        and t.deleted_at is null
    );

  update f.titulo_aprovacao ta
  set deleted_at = v_now,
      updated_at = v_now
  where ta.tenant_id = p_tenant_id
    and ta.deleted_at is null
    and exists (
      select 1
      from f.titulo t
      where t.id = ta.titulo_id
        and t.tenant_id = p_tenant_id
        and t.empresa_id = p_empresa_id
        and t.documento_fiscal_id = v_df.id
        and t.deleted_at is null
    );

  update f.titulo_parcela tp
  set valor_aberto = 0,
      deleted_at = v_now,
      updated_at = v_now,
      updated_by = a.fn_current_usuario_id()
  where tp.tenant_id = p_tenant_id
    and tp.deleted_at is null
    and exists (
      select 1
      from f.titulo t
      where t.id = tp.titulo_id
        and t.tenant_id = p_tenant_id
        and t.empresa_id = p_empresa_id
        and t.documento_fiscal_id = v_df.id
        and t.deleted_at is null
    );

  update f.titulo_rateio tr
  set deleted_at = v_now,
      updated_at = v_now
  where tr.tenant_id = p_tenant_id
    and tr.deleted_at is null
    and exists (
      select 1
      from f.titulo t
      where t.id = tr.titulo_id
        and t.tenant_id = p_tenant_id
        and t.empresa_id = p_empresa_id
        and t.documento_fiscal_id = v_df.id
        and t.deleted_at is null
    );

  update f.titulo t
  set status = 'CANCELADO',
      valor_aberto = 0,
      deleted_at = v_now,
      updated_at = v_now,
      updated_by = a.fn_current_usuario_id()
  where t.tenant_id = p_tenant_id
    and t.empresa_id = p_empresa_id
    and t.documento_fiscal_id = v_df.id
    and t.deleted_at is null;

  update f.documento_fiscal_item dfi
  set deleted_at = v_now,
      updated_at = v_now
  where dfi.tenant_id = p_tenant_id
    and dfi.documento_fiscal_id = v_df.id
    and dfi.deleted_at is null;

  update f.documento_fiscal_imposto dfi
  set deleted_at = v_now,
      updated_at = v_now
  where dfi.tenant_id = p_tenant_id
    and dfi.documento_fiscal_id = v_df.id
    and dfi.deleted_at is null;

  update f.documento_fiscal_xml dfx
  set deleted_at = v_now
  where dfx.tenant_id = p_tenant_id
    and dfx.documento_fiscal_id = v_df.id
    and dfx.deleted_at is null;

  v_source_nf_entrada_id := v_df.source_nf_entrada_id;
  if v_source_nf_entrada_id is not null then
    if exists (
      select 1
      from public.movimentacoes m
      where m.tenant_id = p_tenant_id
        and m.empresa_id = p_empresa_id
        and m.origem_nf_entrada_id = v_source_nf_entrada_id
    ) then
      raise exception 'A NF-e possui movimentacoes de estoque vinculadas. Remova/estorne essas movimentacoes antes de excluir.';
    end if;

    update f.documento_fiscal
    set source_nf_entrada_id = null,
        nfe_status = 'CANCELADA',
        deleted_at = v_now,
        updated_at = v_now
    where id = v_df.id
      and tenant_id = p_tenant_id
      and empresa_id = p_empresa_id
      and deleted_at is null;

    v_legacy_key := left(coalesce((select chave from public.nf_entrada where id = v_source_nf_entrada_id), 'NFEX'), 40)
      || '#DEL#' || v_source_nf_entrada_id::text;

    update public.nf_entrada
    set chave = v_legacy_key,
        deleted_at = v_now,
        updated_at = v_now
    where id = v_source_nf_entrada_id
      and tenant_id = p_tenant_id
      and empresa_id = p_empresa_id;
  else
    update f.documento_fiscal
    set
      nfe_status = case when coalesce(v_df.natureza, '') = 'PRODUTO' then 'CANCELADA' else nfe_status end,
      nfse_status = case when coalesce(v_df.natureza, '') = 'SERVICO' then 'CANCELADA' else nfse_status end,
      deleted_at = v_now,
      updated_at = v_now
    where id = v_df.id
      and tenant_id = p_tenant_id
      and empresa_id = p_empresa_id
      and deleted_at is null;
  end if;

  return v_df.id;
end;
$$;

grant execute on function public.faturamento_excluir_documento_saida(uuid, uuid, uuid) to authenticated;

commit;
