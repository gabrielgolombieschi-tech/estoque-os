-- Integra a Ordem de Venda ao fluxo de Compras sem expor as tabelas internas
-- a usuarios de Comercial/Financeiro. O discriminador fisico de origem segue
-- como 'OS' para preservar indices, triggers e compatibilidade existentes.

create or replace function m.vendas_compras_resumo()
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'm', 'auth'
set row_security to 'off'
as $$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_result jsonb;
begin
  if auth.uid() is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  if not (
    public.can('compras', 'read', v_tenant_id)
    or public.can('compras', 'write', v_tenant_id)
    or public.can('os_rpcs', 'execute', v_tenant_id)
    or public.has_permission('os.read')
    or public.has_permission('os.write')
    or public.can('financeiro', 'read', v_tenant_id)
    or public.can('financeiro', 'write', v_tenant_id)
    or public.has_permission('financeiro.read')
    or public.has_permission('financeiro.write')
  ) then
    raise exception 'Sem permissao para consultar compras das vendas.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'pendencia_id', pendencia.id,
        'origem_os_id', pendencia.origem_os_id,
        'status', pendencia.status
      ) order by pendencia.created_at desc
    ),
    '[]'::jsonb
  )
    into v_result
  from m.compra_pendencia as pendencia
  join public.ordens_servico as venda
    on venda.id = pendencia.origem_os_id
   and venda.tenant_id = pendencia.tenant_id
   and venda.empresa_id = pendencia.empresa_id
   and venda.tipo_documento = 'OV'
  where pendencia.tenant_id = v_tenant_id
    and pendencia.empresa_id = v_empresa_id
    and pendencia.deleted_at is null;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

create or replace function m.venda_compras_resumo(p_venda_id integer)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'm', 'auth'
set row_security to 'off'
as $$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_pendencias jsonb;
  v_pedido_itens jsonb;
  v_pedidos jsonb;
begin
  if auth.uid() is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  if not (
    public.can('compras', 'read', v_tenant_id)
    or public.can('compras', 'write', v_tenant_id)
    or public.can('os_rpcs', 'execute', v_tenant_id)
    or public.has_permission('os.read')
    or public.has_permission('os.write')
    or public.can('financeiro', 'read', v_tenant_id)
    or public.can('financeiro', 'write', v_tenant_id)
    or public.has_permission('financeiro.read')
    or public.has_permission('financeiro.write')
  ) then
    raise exception 'Sem permissao para consultar compras da venda.';
  end if;

  if not exists (
    select 1
    from public.ordens_servico as venda
    where venda.id = p_venda_id
      and venda.tenant_id = v_tenant_id
      and venda.empresa_id = v_empresa_id
      and venda.tipo_documento = 'OV'
  ) then
    raise exception 'Venda nao encontrada na empresa atual.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'pendencia_id', pendencia.id,
        'status', pendencia.status,
        'item_id', pendencia.item_id,
        'item_codigo', item.codigo_interno,
        'item_nome', coalesce(pendencia.item_nome, item.nome::text, item.descricao),
        'unidade', coalesce(pendencia.unidade, item.unidade_medida::text, 'UN'),
        'quantidade', pendencia.quantidade,
        'prioridade', pendencia.prioridade,
        'necessario_em', pendencia.necessario_em,
        'fornecedor_nome', coalesce(fornecedor.nome, 'SEM FORNECEDOR')
      ) order by pendencia.created_at desc
    ),
    '[]'::jsonb
  )
    into v_pendencias
  from m.compra_pendencia as pendencia
  left join public.itens as item
    on item.id = pendencia.item_id
   and item.tenant_id = pendencia.tenant_id
   and item.empresa_id = pendencia.empresa_id
  left join public.fornecedores as fornecedor
    on fornecedor.id = pendencia.fornecedor_id
   and fornecedor.tenant_id = pendencia.tenant_id
   and fornecedor.empresa_id = pendencia.empresa_id
  where pendencia.tenant_id = v_tenant_id
    and pendencia.empresa_id = v_empresa_id
    and pendencia.origem_tipo = 'OS'
    and pendencia.origem_os_id = p_venda_id
    and pendencia.deleted_at is null;

  with itens_venda as (
    select distinct pedido_item.id
    from m.pedido_compra_item as pedido_item
    where pedido_item.tenant_id = v_tenant_id
      and pedido_item.empresa_id = v_empresa_id
      and pedido_item.deleted_at is null
      and pedido_item.origem_os_id = p_venda_id
    union
    select distinct origem.pedido_compra_item_id
    from m.pedido_compra_item_origem as origem
    join m.compra_pendencia as pendencia
      on pendencia.id = origem.pendencia_id
     and pendencia.tenant_id = origem.tenant_id
     and pendencia.empresa_id = origem.empresa_id
    where origem.tenant_id = v_tenant_id
      and origem.empresa_id = v_empresa_id
      and origem.deleted_at is null
      and pendencia.deleted_at is null
      and pendencia.origem_tipo = 'OS'
      and pendencia.origem_os_id = p_venda_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', pedido_item.id,
        'pedido_compra_id', pedido_item.pedido_compra_id,
        'item_nome', pedido_item.item_nome,
        'unidade', pedido_item.unidade,
        'quantidade', pedido_item.quantidade,
        'quantidade_recebida', pedido_item.quantidade_recebida,
        'origem_os_id', p_venda_id
      ) order by pedido_item.created_at desc
    ),
    '[]'::jsonb
  )
    into v_pedido_itens
  from itens_venda
  join m.pedido_compra_item as pedido_item on pedido_item.id = itens_venda.id
  where pedido_item.tenant_id = v_tenant_id
    and pedido_item.empresa_id = v_empresa_id
    and pedido_item.deleted_at is null;

  with itens_venda as (
    select distinct pedido_item.pedido_compra_id
    from m.pedido_compra_item as pedido_item
    where pedido_item.tenant_id = v_tenant_id
      and pedido_item.empresa_id = v_empresa_id
      and pedido_item.deleted_at is null
      and pedido_item.origem_os_id = p_venda_id
    union
    select distinct pedido_item.pedido_compra_id
    from m.pedido_compra_item_origem as origem
    join m.compra_pendencia as pendencia
      on pendencia.id = origem.pendencia_id
     and pendencia.tenant_id = origem.tenant_id
     and pendencia.empresa_id = origem.empresa_id
    join m.pedido_compra_item as pedido_item
      on pedido_item.id = origem.pedido_compra_item_id
     and pedido_item.tenant_id = origem.tenant_id
     and pedido_item.empresa_id = origem.empresa_id
    where origem.tenant_id = v_tenant_id
      and origem.empresa_id = v_empresa_id
      and origem.deleted_at is null
      and pendencia.deleted_at is null
      and pendencia.origem_tipo = 'OS'
      and pendencia.origem_os_id = p_venda_id
      and pedido_item.deleted_at is null
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', pedido.id,
        'codigo', pedido.codigo,
        'status', pedido.status,
        'previsao_entrega_date', pedido.previsao_entrega_date
      ) order by pedido.created_at desc
    ),
    '[]'::jsonb
  )
    into v_pedidos
  from itens_venda
  join m.pedido_compra as pedido on pedido.id = itens_venda.pedido_compra_id
  where pedido.tenant_id = v_tenant_id
    and pedido.empresa_id = v_empresa_id
    and pedido.deleted_at is null;

  return jsonb_build_object(
    'pendencias', coalesce(v_pendencias, '[]'::jsonb),
    'pedido_itens', coalesce(v_pedido_itens, '[]'::jsonb),
    'pedidos', coalesce(v_pedidos, '[]'::jsonb)
  );
end;
$$;

create or replace function m.venda_sincronizar_compras(
  p_venda_id integer,
  p_item_id integer default null,
  p_quantidade numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'm', 'auth', 'a'
set row_security to 'off'
as $$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_codigo text;
  v_status text;
  v_quantidade_pendente numeric(15,3);
  v_inseridas integer := 0;
  v_atualizadas integer := 0;
  v_canceladas integer := 0;
  v_em_pedido integer := 0;
  v_sem_fornecedor integer := 0;
begin
  if auth.uid() is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  if not (
    public.can('compras', 'write', v_tenant_id)
    or public.can('os_rpcs', 'execute', v_tenant_id)
    or public.has_permission('os.write')
    or public.can('financeiro', 'write', v_tenant_id)
    or public.has_permission('financeiro.write')
  ) then
    raise exception 'Sem permissao para enviar a venda para Compras.';
  end if;

  select venda.codigo, coalesce(venda.status_fluxo, venda.status)
    into v_codigo, v_status
  from public.ordens_servico as venda
  where venda.id = p_venda_id
    and venda.tenant_id = v_tenant_id
    and venda.empresa_id = v_empresa_id
    and venda.tipo_documento = 'OV'
  for update;

  if not found then
    raise exception 'Venda nao encontrada na empresa atual.';
  end if;
  if v_status <> 'em_andamento' then
    raise exception 'Somente uma venda em andamento pode ser enviada para Compras.';
  end if;

  perform pg_advisory_xact_lock(
    hashtext('m.venda_sincronizar_compras'),
    p_venda_id
  );

  if p_item_id is not null then
    if p_quantidade is null or p_quantidade <= 0 then
      raise exception 'Informe uma quantidade de compra valida.';
    end if;

    select sum(greatest(item_os.quantidade - coalesce(item_os.quantidade_baixada, 0), 0))::numeric(15,3)
      into v_quantidade_pendente
    from public.os_itens as item_os
    where item_os.tenant_id = v_tenant_id
      and item_os.empresa_id = v_empresa_id
      and item_os.os_id = p_venda_id
      and item_os.item_id = p_item_id;

    if coalesce(v_quantidade_pendente, 0) <= 0 then
      raise exception 'O item nao possui quantidade pendente nesta venda.';
    end if;
    if p_quantidade > v_quantidade_pendente then
      raise exception 'A quantidade de compra nao pode superar o saldo pendente da venda (%).', v_quantidade_pendente;
    end if;

    if exists (
      select 1
      from m.compra_pendencia as pendencia
      where pendencia.tenant_id = v_tenant_id
        and pendencia.empresa_id = v_empresa_id
        and pendencia.origem_tipo = 'OS'
        and pendencia.origem_os_id = p_venda_id
        and pendencia.item_id = p_item_id
        and pendencia.status = 'EM_PEDIDO'
        and pendencia.deleted_at is null
    ) then
      raise exception 'Este item ja esta vinculado a um pedido de compra.';
    end if;

    update m.compra_pendencia as pendencia
       set quantidade = p_quantidade::numeric(15,3),
           fornecedor_id = coalesce(pendencia.fornecedor_id, item.fornecedor_id),
           item_nome = upper(trim(coalesce(item.nome, item.descricao, pendencia.item_nome, 'ITEM'))),
           unidade = coalesce(nullif(trim(item.unidade_medida), ''), pendencia.unidade, 'UN'),
           status = 'PENDENTE',
           cancel_reason = null,
           observacoes = 'Sincronizada manualmente pela ' || coalesce(v_codigo, 'OV ' || p_venda_id::text),
           updated_at = now(),
           updated_by = a.fn_current_usuario_id()
      from public.itens as item
     where pendencia.tenant_id = v_tenant_id
       and pendencia.empresa_id = v_empresa_id
       and pendencia.origem_tipo = 'OS'
       and pendencia.origem_os_id = p_venda_id
       and pendencia.item_id = p_item_id
       and pendencia.status = 'PENDENTE'
       and pendencia.deleted_at is null
       and item.tenant_id = v_tenant_id
       and item.empresa_id = v_empresa_id
       and item.id = p_item_id;
    get diagnostics v_atualizadas = row_count;

    if v_atualizadas = 0 then
      insert into m.compra_pendencia (
        tenant_id, empresa_id, status, fornecedor_id, origem_tipo, origem_os_id,
        item_id, item_nome, unidade, quantidade, prioridade, observacoes
      )
      select
        v_tenant_id, v_empresa_id, 'PENDENTE', item.fornecedor_id, 'OS', p_venda_id,
        item.id, upper(trim(coalesce(item.nome, item.descricao, 'ITEM'))),
        coalesce(nullif(trim(item.unidade_medida), ''), 'UN'), p_quantidade::numeric(15,3),
        'MEDIA', 'Gerada manualmente pela ' || coalesce(v_codigo, 'OV ' || p_venda_id::text)
      from public.itens as item
      where item.tenant_id = v_tenant_id
        and item.empresa_id = v_empresa_id
        and item.id = p_item_id;
      get diagnostics v_inseridas = row_count;
    end if;
  else
    with fonte as (
      select
        item_os.item_id,
        sum(greatest(item_os.quantidade - coalesce(item_os.quantidade_baixada, 0), 0))::numeric(15,3) as quantidade,
        coalesce(estoque.quantidade_atual, 0)::numeric(15,3) as estoque_atual
      from public.os_itens as item_os
      left join public.estoque as estoque
        on estoque.tenant_id = item_os.tenant_id
       and estoque.empresa_id = item_os.empresa_id
       and estoque.item_id = item_os.item_id
      where item_os.tenant_id = v_tenant_id
        and item_os.empresa_id = v_empresa_id
        and item_os.os_id = p_venda_id
        and item_os.quantidade > 0
      group by item_os.item_id, estoque.quantidade_atual
    )
    update m.compra_pendencia as pendencia
       set status = 'CANCELADO',
           cancel_reason = 'Cancelada pela sincronizacao da OV: item atendido ou removido.',
           updated_at = now(),
           updated_by = a.fn_current_usuario_id()
     where pendencia.tenant_id = v_tenant_id
       and pendencia.empresa_id = v_empresa_id
       and pendencia.origem_tipo = 'OS'
       and pendencia.origem_os_id = p_venda_id
       and pendencia.status = 'PENDENTE'
       and pendencia.deleted_at is null
       and not exists (
         select 1 from fonte
         where fonte.item_id = pendencia.item_id
           and fonte.quantidade > 0
           and fonte.estoque_atual < fonte.quantidade
       );
    get diagnostics v_canceladas = row_count;

    with fonte as (
      select
        item_os.item_id,
        sum(greatest(item_os.quantidade - coalesce(item_os.quantidade_baixada, 0), 0))::numeric(15,3) as quantidade,
        coalesce(estoque.quantidade_atual, 0)::numeric(15,3) as estoque_atual
      from public.os_itens as item_os
      left join public.estoque as estoque
        on estoque.tenant_id = item_os.tenant_id
       and estoque.empresa_id = item_os.empresa_id
       and estoque.item_id = item_os.item_id
      where item_os.tenant_id = v_tenant_id
        and item_os.empresa_id = v_empresa_id
        and item_os.os_id = p_venda_id
        and item_os.quantidade > 0
      group by item_os.item_id, estoque.quantidade_atual
    )
    update m.compra_pendencia as pendencia
       set quantidade = fonte.quantidade,
           fornecedor_id = coalesce(pendencia.fornecedor_id, item.fornecedor_id),
           item_nome = upper(trim(coalesce(item.nome, item.descricao, pendencia.item_nome, 'ITEM'))),
           unidade = coalesce(nullif(trim(item.unidade_medida), ''), pendencia.unidade, 'UN'),
           cancel_reason = null,
           observacoes = 'Sincronizada automaticamente pela ' || coalesce(v_codigo, 'OV ' || p_venda_id::text),
           updated_at = now(),
           updated_by = a.fn_current_usuario_id()
      from fonte
      join public.itens as item
        on item.tenant_id = v_tenant_id
       and item.empresa_id = v_empresa_id
       and item.id = fonte.item_id
     where pendencia.tenant_id = v_tenant_id
       and pendencia.empresa_id = v_empresa_id
       and pendencia.origem_tipo = 'OS'
       and pendencia.origem_os_id = p_venda_id
       and pendencia.item_id = fonte.item_id
       and pendencia.status = 'PENDENTE'
       and pendencia.deleted_at is null
       and fonte.quantidade > 0
       and fonte.estoque_atual < fonte.quantidade;
    get diagnostics v_atualizadas = row_count;

    with fonte as (
      select
        item_os.item_id,
        sum(greatest(item_os.quantidade - coalesce(item_os.quantidade_baixada, 0), 0))::numeric(15,3) as quantidade,
        coalesce(estoque.quantidade_atual, 0)::numeric(15,3) as estoque_atual
      from public.os_itens as item_os
      left join public.estoque as estoque
        on estoque.tenant_id = item_os.tenant_id
       and estoque.empresa_id = item_os.empresa_id
       and estoque.item_id = item_os.item_id
      where item_os.tenant_id = v_tenant_id
        and item_os.empresa_id = v_empresa_id
        and item_os.os_id = p_venda_id
        and item_os.quantidade > 0
      group by item_os.item_id, estoque.quantidade_atual
    )
    insert into m.compra_pendencia (
      tenant_id, empresa_id, status, fornecedor_id, origem_tipo, origem_os_id,
      item_id, item_nome, unidade, quantidade, prioridade, observacoes
    )
    select
      v_tenant_id, v_empresa_id, 'PENDENTE', item.fornecedor_id, 'OS', p_venda_id,
      item.id, upper(trim(coalesce(item.nome, item.descricao, 'ITEM'))),
      coalesce(nullif(trim(item.unidade_medida), ''), 'UN'), fonte.quantidade,
      'MEDIA', 'Gerada automaticamente pela ' || coalesce(v_codigo, 'OV ' || p_venda_id::text)
    from fonte
    join public.itens as item
      on item.tenant_id = v_tenant_id
     and item.empresa_id = v_empresa_id
     and item.id = fonte.item_id
    where fonte.quantidade > 0
      and fonte.estoque_atual < fonte.quantidade
      and not exists (
        select 1
        from m.compra_pendencia as existente
        where existente.tenant_id = v_tenant_id
          and existente.empresa_id = v_empresa_id
          and existente.origem_tipo = 'OS'
          and existente.origem_os_id = p_venda_id
          and existente.item_id = fonte.item_id
          and existente.status in ('PENDENTE', 'EM_PEDIDO')
          and existente.deleted_at is null
      );
    get diagnostics v_inseridas = row_count;

    with fonte as (
      select
        item_os.item_id,
        sum(greatest(item_os.quantidade - coalesce(item_os.quantidade_baixada, 0), 0))::numeric(15,3) as quantidade,
        coalesce(estoque.quantidade_atual, 0)::numeric(15,3) as estoque_atual
      from public.os_itens as item_os
      left join public.estoque as estoque
        on estoque.tenant_id = item_os.tenant_id
       and estoque.empresa_id = item_os.empresa_id
       and estoque.item_id = item_os.item_id
      where item_os.tenant_id = v_tenant_id
        and item_os.empresa_id = v_empresa_id
        and item_os.os_id = p_venda_id
        and item_os.quantidade > 0
      group by item_os.item_id, estoque.quantidade_atual
    )
    select
      count(*) filter (where item.fornecedor_id is null),
      count(*) filter (where exists (
        select 1 from m.compra_pendencia as pendencia
        where pendencia.tenant_id = v_tenant_id
          and pendencia.empresa_id = v_empresa_id
          and pendencia.origem_tipo = 'OS'
          and pendencia.origem_os_id = p_venda_id
          and pendencia.item_id = fonte.item_id
          and pendencia.status = 'EM_PEDIDO'
          and pendencia.deleted_at is null
      ))
      into v_sem_fornecedor, v_em_pedido
    from fonte
    join public.itens as item
      on item.tenant_id = v_tenant_id
     and item.empresa_id = v_empresa_id
     and item.id = fonte.item_id
    where fonte.quantidade > 0
      and fonte.estoque_atual < fonte.quantidade;
  end if;

  insert into public.ordens_servico_fluxo_eventos (
    tenant_id, empresa_id, os_id, evento, status_origem, status_destino, motivo, realizado_por
  ) values (
    v_tenant_id,
    v_empresa_id,
    p_venda_id,
    'sincronizar_compras',
    v_status,
    v_status,
    format('Pendencias: %s criada(s), %s atualizada(s), %s cancelada(s).', v_inseridas, v_atualizadas, v_canceladas),
    auth.uid()
  );

  return jsonb_build_object(
    'sucesso', true,
    'inseridas', v_inseridas,
    'atualizadas', v_atualizadas,
    'canceladas', v_canceladas,
    'em_pedido', v_em_pedido,
    'sem_fornecedor', v_sem_fornecedor,
    'total_movimentadas', v_inseridas + v_atualizadas + v_canceladas
  );
end;
$$;

create or replace function m.venda_registrar_oc(
  p_venda_id integer,
  p_numero text,
  p_data date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'm', 'auth'
set row_security to 'off'
as $$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_status text;
begin
  if auth.uid() is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  if not (
    public.can('os_rpcs', 'execute', v_tenant_id)
    or public.has_permission('os.write')
    or public.can('financeiro', 'write', v_tenant_id)
    or public.has_permission('financeiro.write')
  ) then
    raise exception 'Sem permissao para registrar a ordem de compra da venda.';
  end if;
  if nullif(btrim(p_numero), '') is null then
    raise exception 'Informe o numero da ordem de compra do cliente.';
  end if;

  select coalesce(venda.status_fluxo, venda.status)
    into v_status
  from public.ordens_servico as venda
  where venda.id = p_venda_id
    and venda.tenant_id = v_tenant_id
    and venda.empresa_id = v_empresa_id
    and venda.tipo_documento = 'OV'
  for update;

  if not found then
    raise exception 'Venda nao encontrada na empresa atual.';
  end if;
  if v_status = 'cancelada' then
    raise exception 'Nao e possivel registrar OC em uma venda cancelada.';
  end if;

  update public.ordens_servico
     set pedido_compra = btrim(p_numero),
         atualizado_em = now()
   where id = p_venda_id
     and tenant_id = v_tenant_id
     and empresa_id = v_empresa_id;

  insert into public.ordens_servico_fluxo_eventos (
    tenant_id, empresa_id, os_id, evento, status_origem, status_destino, motivo, realizado_por
  ) values (
    v_tenant_id, v_empresa_id, p_venda_id, 'registrar_oc_cliente', v_status, v_status,
    'OC ' || btrim(p_numero) || ' recebida em ' || coalesce(p_data, current_date)::text,
    auth.uid()
  );

  return jsonb_build_object('sucesso', true, 'numero', btrim(p_numero), 'data', coalesce(p_data, current_date));
end;
$$;

revoke all on function m.vendas_compras_resumo() from public, anon;
grant execute on function m.vendas_compras_resumo() to authenticated, service_role;

revoke all on function m.venda_compras_resumo(integer) from public, anon;
grant execute on function m.venda_compras_resumo(integer) to authenticated, service_role;

revoke all on function m.venda_sincronizar_compras(integer, integer, numeric) from public, anon;
grant execute on function m.venda_sincronizar_compras(integer, integer, numeric) to authenticated, service_role;

revoke all on function m.venda_registrar_oc(integer, text, date) from public, anon;
grant execute on function m.venda_registrar_oc(integer, text, date) to authenticated, service_role;

comment on function m.venda_sincronizar_compras(integer, integer, numeric) is
  'Sincroniza de forma transacional os itens pendentes de uma OV com m.compra_pendencia, preservando origem_tipo=OS.';
