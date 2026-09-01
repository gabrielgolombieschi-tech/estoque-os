begin;

create or replace function public.estornar_nf_entrada(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_nf_entrada_id bigint,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'f', 'a', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_nf public.nf_entrada%rowtype;
  v_now timestamptz := now();
  v_executor text;
  v_documentos integer := 0;
  v_titulos integer := 0;
  v_movimentacoes integer := 0;
  v_mov record;
  v_item record;
  v_saldo numeric;
  v_quantidade_nf numeric;
  v_valor_nf numeric;
  v_custo_anterior numeric;
  v_ultimo_custo numeric;
begin
  if p_tenant_id is null or p_empresa_id is null then
    raise exception 'tenant_id e empresa_id sao obrigatorios';
  end if;
  if p_nf_entrada_id is null then
    raise exception 'nf_entrada_id obrigatorio';
  end if;
  if length(trim(coalesce(p_motivo, ''))) < 5 then
    raise exception 'Informe o motivo do estorno (minimo 5 caracteres).';
  end if;

  perform set_config('app.tenant_id', p_tenant_id::text, true);
  perform set_config('app.current_tenant_id', p_tenant_id::text, true);
  perform set_config('app.current_empresa_id', p_empresa_id::text, true);

  if auth.role() <> 'service_role' then
    if auth.uid() is null then
      raise exception 'Nao autenticado';
    end if;

    if not exists (
      select 1
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = p_tenant_id
        and tm.status in ('active', 'ativo')
    ) then
      raise exception 'Tenant nao autorizado';
    end if;

    if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'empresa_memberships')
       and not exists (
         select 1
         from public.empresa_memberships em
         where em.user_id = auth.uid()
           and em.tenant_id = p_tenant_id
           and em.empresa_id = p_empresa_id
           and em.status = 'active'
       ) then
      raise exception 'Sem acesso a esta empresa';
    end if;

    if not (
      public.can('financeiro', 'write')
      or public.can('financeiro', 'config')
      or f.has_finance_access(p_tenant_id, p_empresa_id)
    ) then
      raise exception 'Sem permissao para estornar NF-e de entrada';
    end if;
  end if;

  select *
    into v_nf
  from public.nf_entrada nf
  where nf.id = p_nf_entrada_id
    and nf.tenant_id = p_tenant_id
    and nf.empresa_id = p_empresa_id
    and nf.deleted_at is null
  for update;

  if not found then
    raise exception 'NF-e de entrada nao encontrada para tenant/empresa informado.';
  end if;

  if v_nf.os_id is not null then
    raise exception 'A NF-e esta vinculada a OS %. Remova o vinculo/consumo da OS antes do estorno.', v_nf.os_id;
  end if;

  if exists (
    select 1
    from public.imobilizado_itens ii
    where ii.tenant_id = p_tenant_id
      and ii.empresa_id = p_empresa_id
      and ii.nf_entrada_id = v_nf.id
      and ii.deleted_at is null
      and ii.status <> 'IMPORTADO'
  ) then
    raise exception 'A NF-e possui item de imobilizado ja colocado em uso. Reverta-o antes do estorno.';
  end if;

  if exists (
    select 1
    from public.consumo_itens ci
    where ci.tenant_id = p_tenant_id
      and ci.empresa_id = p_empresa_id
      and ci.nf_entrada_id = v_nf.id
      and ci.deleted_at is null
      and coalesce(ci.quantidade_consumida, 0) > 0
  ) then
    raise exception 'A NF-e possui item de consumo ja utilizado. Reverta o consumo antes do estorno.';
  end if;

  if exists (
    select 1
    from public.movimentacoes m
    where m.tenant_id = p_tenant_id
      and m.empresa_id = p_empresa_id
      and m.origem_nf_entrada_id = v_nf.id
      and (m.tipo <> 'entrada' or m.origem_os_id is not null)
  ) then
    raise exception 'A NF-e possui baixa/ajuste de estoque vinculado. Reverta esse consumo antes do estorno.';
  end if;

  if exists (
    select 1
    from f.documento_fiscal df
    join f.titulo t
      on t.tenant_id = df.tenant_id
     and t.empresa_id = df.empresa_id
     and t.documento_fiscal_id = df.id
     and t.deleted_at is null
    join f.titulo_parcela tp
      on tp.tenant_id = t.tenant_id
     and tp.titulo_id = t.id
     and tp.deleted_at is null
    join f.pagamento_item pi
      on pi.tenant_id = tp.tenant_id
     and pi.titulo_parcela_id = tp.id
     and pi.deleted_at is null
    join f.pagamento p
      on p.id = pi.pagamento_id
     and p.tenant_id = t.tenant_id
     and p.empresa_id = t.empresa_id
     and p.deleted_at is null
    where df.tenant_id = p_tenant_id
      and df.empresa_id = p_empresa_id
      and df.source_nf_entrada_id = v_nf.id
      and df.deleted_at is null
  ) then
    raise exception 'A NF-e possui pagamento aplicado. Estorne o pagamento antes de excluir o lancamento.';
  end if;

  if exists (
    select 1
    from f.documento_fiscal df
    join f.titulo t
      on t.tenant_id = df.tenant_id
     and t.empresa_id = df.empresa_id
     and t.documento_fiscal_id = df.id
     and t.deleted_at is null
    where df.tenant_id = p_tenant_id
      and df.empresa_id = p_empresa_id
      and df.source_nf_entrada_id = v_nf.id
      and df.deleted_at is null
      and (
        upper(coalesce(t.status, '')) = 'PAGO'
        or abs(round(coalesce(t.valor_total, 0), 2) - round(coalesce(t.valor_aberto, 0), 2)) > 0.009
      )
  ) then
    raise exception 'A NF-e possui baixa financeira. Estorne o pagamento antes de excluir o lancamento.';
  end if;

  -- Movimentos sao imutaveis. O estorno e registrado por movimentos opostos.
  -- Para preservar o custo medio, este fluxo conservador exige que nao haja
  -- movimentacao posterior dos itens afetados.
  for v_item in
    select m.item_id, max(m.id) as ultimo_mov_nf
    from public.movimentacoes m
    where m.tenant_id = p_tenant_id
      and m.empresa_id = p_empresa_id
      and m.origem_nf_entrada_id = v_nf.id
    group by m.item_id
  loop
    if exists (
      select 1
      from public.movimentacoes posterior
      where posterior.tenant_id = p_tenant_id
        and posterior.empresa_id = p_empresa_id
        and posterior.item_id = v_item.item_id
        and posterior.id > v_item.ultimo_mov_nf
    ) then
      raise exception 'O item % possui movimentacao posterior a NF-e. Faca um estorno assistido antes de excluir.', v_item.item_id;
    end if;

    select coalesce(e.quantidade_atual, 0)
      into v_saldo
    from public.estoque e
    where e.tenant_id = p_tenant_id
      and e.empresa_id = p_empresa_id
      and e.item_id = v_item.item_id
    for update;

    select
      coalesce(sum(m.quantidade), 0),
      coalesce(sum(m.quantidade * coalesce(m.custo_unitario_real, m.custo_unitario_bruto, 0)), 0)
      into v_quantidade_nf, v_valor_nf
    from public.movimentacoes m
    where m.tenant_id = p_tenant_id
      and m.empresa_id = p_empresa_id
      and m.item_id = v_item.item_id
      and m.origem_nf_entrada_id = v_nf.id
      and m.tipo = 'entrada';

    if coalesce(v_saldo, 0) + 0.000001 < v_quantidade_nf then
      raise exception 'Saldo insuficiente para estornar o item %: saldo %, necessario %.',
        v_item.item_id, coalesce(v_saldo, 0), v_quantidade_nf;
    end if;

    select case
      when (v_saldo - v_quantidade_nf) > 0
        then greatest(0, ((v_saldo * coalesce(i.custo_medio, 0)) - v_valor_nf) / (v_saldo - v_quantidade_nf))
      else 0
    end
      into v_custo_anterior
    from public.itens i
    where i.id = v_item.item_id
      and i.tenant_id = p_tenant_id;

    select coalesce(m.custo_unitario_real, m.custo_unitario_bruto, 0)
      into v_ultimo_custo
    from public.movimentacoes m
    where m.tenant_id = p_tenant_id
      and m.empresa_id = p_empresa_id
      and m.item_id = v_item.item_id
      and m.tipo = 'entrada'
      and m.origem_nf_entrada_id is distinct from v_nf.id
    order by m.id desc
    limit 1;

    for v_mov in
      select m.*
      from public.movimentacoes m
      where m.tenant_id = p_tenant_id
        and m.empresa_id = p_empresa_id
        and m.item_id = v_item.item_id
        and m.origem_nf_entrada_id = v_nf.id
        and m.tipo = 'entrada'
      order by m.id desc
    loop
      insert into public.movimentacoes (
        tenant_id, empresa_id, item_id, tipo, quantidade, motivo,
        realizado_por, data_movimentacao,
        custo_unitario_bruto, custo_unitario_real,
        credito_icms, credito_pis, credito_cofins,
        v_ipi, v_icms, v_pis, v_cofins, v_frete_rateado,
        origem_nf_entrada_id, origem_os_id, created_at
      ) values (
        p_tenant_id, p_empresa_id, v_mov.item_id, 'saida', v_mov.quantidade,
        format('ESTORNO NF-e %s/%s (NF_ENTRADA_%s): %s', coalesce(v_nf.numero, ''), coalesce(v_nf.serie, ''), v_nf.id, trim(p_motivo)),
        coalesce(public.jwt_claim('email'), auth.uid()::text, 'service_role'), now(),
        v_mov.custo_unitario_bruto, v_mov.custo_unitario_real,
        0, 0, 0, 0, 0, 0, 0, 0,
        v_nf.id, null, now()
      );
      v_movimentacoes := v_movimentacoes + 1;
    end loop;

    update public.itens i
    set custo_medio = round(coalesce(v_custo_anterior, 0), 6),
        custo_ultima_compra = round(coalesce(v_ultimo_custo, 0), 6)
    where i.id = v_item.item_id
      and i.tenant_id = p_tenant_id;
  end loop;

  update public.imobilizado_itens
  set status = 'CANCELADO', deleted_at = v_now, updated_at = v_now, updated_by = auth.uid()
  where tenant_id = p_tenant_id
    and empresa_id = p_empresa_id
    and nf_entrada_id = v_nf.id
    and deleted_at is null;

  update public.consumo_itens
  set status = 'CANCELADO', deleted_at = v_now, updated_at = v_now, updated_by = auth.uid()
  where tenant_id = p_tenant_id
    and empresa_id = p_empresa_id
    and nf_entrada_id = v_nf.id
    and deleted_at is null;

  update f.titulo_agendamento ta
  set deleted_at = v_now, updated_at = v_now
  where ta.tenant_id = p_tenant_id
    and ta.deleted_at is null
    and exists (
      select 1 from f.titulo t
      join f.documento_fiscal df on df.id = t.documento_fiscal_id
      where t.id = ta.titulo_id
        and t.tenant_id = p_tenant_id and t.empresa_id = p_empresa_id
        and df.tenant_id = p_tenant_id and df.empresa_id = p_empresa_id
        and df.source_nf_entrada_id = v_nf.id
    );

  update f.titulo_aprovacao ta
  set deleted_at = v_now, updated_at = v_now
  where ta.tenant_id = p_tenant_id
    and ta.deleted_at is null
    and exists (
      select 1 from f.titulo t
      join f.documento_fiscal df on df.id = t.documento_fiscal_id
      where t.id = ta.titulo_id
        and t.tenant_id = p_tenant_id and t.empresa_id = p_empresa_id
        and df.tenant_id = p_tenant_id and df.empresa_id = p_empresa_id
        and df.source_nf_entrada_id = v_nf.id
    );

  update f.titulo_parcela tp
  set valor_aberto = 0, deleted_at = v_now, updated_at = v_now, updated_by = a.fn_current_usuario_id()
  where tp.tenant_id = p_tenant_id
    and tp.deleted_at is null
    and exists (
      select 1 from f.titulo t
      join f.documento_fiscal df on df.id = t.documento_fiscal_id
      where t.id = tp.titulo_id
        and t.tenant_id = p_tenant_id and t.empresa_id = p_empresa_id
        and df.tenant_id = p_tenant_id and df.empresa_id = p_empresa_id
        and df.source_nf_entrada_id = v_nf.id
    );

  update f.titulo_rateio tr
  set deleted_at = v_now, updated_at = v_now
  where tr.tenant_id = p_tenant_id
    and tr.deleted_at is null
    and exists (
      select 1 from f.titulo t
      join f.documento_fiscal df on df.id = t.documento_fiscal_id
      where t.id = tr.titulo_id
        and t.tenant_id = p_tenant_id and t.empresa_id = p_empresa_id
        and df.tenant_id = p_tenant_id and df.empresa_id = p_empresa_id
        and df.source_nf_entrada_id = v_nf.id
    );

  update f.titulo t
  set status = 'CANCELADO', valor_aberto = 0, deleted_at = v_now,
      updated_at = v_now, updated_by = a.fn_current_usuario_id()
  where t.tenant_id = p_tenant_id
    and t.empresa_id = p_empresa_id
    and t.deleted_at is null
    and exists (
      select 1 from f.documento_fiscal df
      where df.id = t.documento_fiscal_id
        and df.tenant_id = p_tenant_id
        and df.empresa_id = p_empresa_id
        and df.source_nf_entrada_id = v_nf.id
    );
  get diagnostics v_titulos = row_count;

  update f.documento_fiscal_item dfi
  set deleted_at = v_now, updated_at = v_now
  where dfi.tenant_id = p_tenant_id
    and dfi.deleted_at is null
    and exists (
      select 1 from f.documento_fiscal df
      where df.id = dfi.documento_fiscal_id
        and df.tenant_id = p_tenant_id and df.empresa_id = p_empresa_id
        and df.source_nf_entrada_id = v_nf.id
    );

  update f.documento_fiscal_imposto dfi
  set deleted_at = v_now, updated_at = v_now
  where dfi.tenant_id = p_tenant_id
    and dfi.deleted_at is null
    and exists (
      select 1 from f.documento_fiscal df
      where df.id = dfi.documento_fiscal_id
        and df.tenant_id = p_tenant_id and df.empresa_id = p_empresa_id
        and df.source_nf_entrada_id = v_nf.id
    );

  update f.documento_fiscal_xml dfx
  set deleted_at = v_now
  where dfx.tenant_id = p_tenant_id
    and dfx.deleted_at is null
    and exists (
      select 1 from f.documento_fiscal df
      where df.id = dfx.documento_fiscal_id
        and df.tenant_id = p_tenant_id and df.empresa_id = p_empresa_id
        and df.source_nf_entrada_id = v_nf.id
    );

  update f.imposto_retencao ir
  set deleted_at = v_now, updated_at = v_now
  where ir.tenant_id = p_tenant_id
    and ir.deleted_at is null
    and exists (
      select 1 from f.documento_fiscal df
      where df.id = ir.documento_fiscal_id
        and df.tenant_id = p_tenant_id and df.empresa_id = p_empresa_id
        and df.source_nf_entrada_id = v_nf.id
    );

  update f.documento_fiscal df
  set nfe_status = 'CANCELADA', deleted_at = v_now, updated_at = v_now,
      updated_by = a.fn_current_usuario_id()
  where df.tenant_id = p_tenant_id
    and df.empresa_id = p_empresa_id
    and df.source_nf_entrada_id = v_nf.id
    and df.deleted_at is null;
  get diagnostics v_documentos = row_count;

  update public.nf_entrada
  set deleted_at = v_now, updated_at = v_now
  where id = v_nf.id
    and tenant_id = p_tenant_id
    and empresa_id = p_empresa_id
    and deleted_at is null;

  return jsonb_build_object(
    'status', 'ESTORNADA',
    'nf_entrada_id', v_nf.id,
    'numero', v_nf.numero,
    'serie', v_nf.serie,
    'documentos_cancelados', v_documentos,
    'titulos_cancelados', v_titulos,
    'movimentacoes_estorno', v_movimentacoes,
    'estornado_em', v_now
  );
end;
$$;

revoke all on function public.estornar_nf_entrada(uuid, uuid, bigint, text) from public;
grant execute on function public.estornar_nf_entrada(uuid, uuid, bigint, text) to authenticated;
grant execute on function public.estornar_nf_entrada(uuid, uuid, bigint, text) to service_role;

comment on function public.estornar_nf_entrada(uuid, uuid, bigint, text) is
  'Estorna com rastreabilidade uma NF-e de entrada sem pagamento, consumo ou movimentacao posterior; sempre escopada por tenant e empresa.';

commit;

notify pgrst, 'reload schema';
