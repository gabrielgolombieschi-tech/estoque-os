-- Evolui o pedido de compra para separar o IPI do valor unitario, permitir
-- destaque opcional na tela/impressao e expor as observacoes ja existentes.
--
-- Tambem corrige a semantica de transporte que estava invertida no modulo:
-- FOB exige transportadora; CIF nao exige e nao armazena transportadora.
-- Os pedidos existentes da empresa Segau sao invertidos para preservar a
-- intencao original informada pelos usuarios.

alter table if exists m.pedido_compra
  add column if not exists destacar_ipi boolean not null default false,
  add column if not exists total_ipi numeric(15,2) not null default 0;

alter table if exists m.pedido_compra_item
  add column if not exists aliquota_ipi numeric(9,4),
  add column if not exists valor_ipi_unitario numeric(15,4),
  add column if not exists valor_ipi_total numeric(15,2) not null default 0;

do $constraints_ipi$
begin
  if not exists (
    select 1
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where con.conname = 'pedido_compra_total_ipi_check'
      and nsp.nspname = 'm'
      and rel.relname = 'pedido_compra'
  ) then
    alter table m.pedido_compra
      add constraint pedido_compra_total_ipi_check
      check (total_ipi >= 0);
  end if;

  if not exists (
    select 1
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where con.conname = 'pedido_compra_item_aliquota_ipi_check'
      and nsp.nspname = 'm'
      and rel.relname = 'pedido_compra_item'
  ) then
    alter table m.pedido_compra_item
      add constraint pedido_compra_item_aliquota_ipi_check
      check (aliquota_ipi is null or aliquota_ipi between 0 and 100);
  end if;

  if not exists (
    select 1
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where con.conname = 'pedido_compra_item_valor_ipi_unitario_check'
      and nsp.nspname = 'm'
      and rel.relname = 'pedido_compra_item'
  ) then
    alter table m.pedido_compra_item
      add constraint pedido_compra_item_valor_ipi_unitario_check
      check (valor_ipi_unitario is null or valor_ipi_unitario >= 0);
  end if;

  if not exists (
    select 1
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where con.conname = 'pedido_compra_item_valor_ipi_total_check'
      and nsp.nspname = 'm'
      and rel.relname = 'pedido_compra_item'
  ) then
    alter table m.pedido_compra_item
      add constraint pedido_compra_item_valor_ipi_total_check
      check (valor_ipi_total >= 0);
  end if;
end;
$constraints_ipi$;

do $constraint_transporte$
begin
  if exists (
    select 1
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where con.conname = 'pedido_compra_transportadora_nome_check'
      and nsp.nspname = 'm'
      and rel.relname = 'pedido_compra'
  ) then
    alter table m.pedido_compra
      drop constraint pedido_compra_transportadora_nome_check;
  end if;

  alter table m.pedido_compra
    add constraint pedido_compra_transportadora_nome_check
    check (
      upper(coalesce(btrim(transporte_tipo), '')) <> 'FOB'
      or nullif(btrim(coalesce(transportadora_nome, '')), '') is not null
    )
    not valid;
end;
$constraint_transporte$;

create or replace function m.fn_pedido_compra_recalcular_totais(
  p_pedido_id uuid
)
returns void
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
declare
  v_total numeric(15,2);
  v_total_ipi numeric(15,2);
begin
  select
    coalesce(sum(item.valor_total), 0),
    coalesce(sum(item.valor_ipi_total), 0)
    into v_total, v_total_ipi
  from m.pedido_compra_item item
  where item.pedido_compra_id = p_pedido_id
    and item.deleted_at is null;

  update m.pedido_compra pedido
  set
    total_itens = v_total,
    total_ipi = v_total_ipi,
    total_geral = round(
      v_total
      + coalesce(pedido.total_frete, 0)
      - coalesce(pedido.total_desconto, 0),
      2
    )
  where pedido.id = p_pedido_id;
end;
$$;

create or replace function m.trg_pedido_compra_item_biu()
returns trigger
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
declare
  v_destacar_ipi boolean := false;
  v_aliquota_cadastro numeric(9,4);
begin
  if tg_op = 'INSERT' and (new.seq is null or new.seq <= 0) then
    select coalesce(max(item.seq), 0) + 1
      into new.seq
    from m.pedido_compra_item item
    where item.pedido_compra_id = new.pedido_compra_id
      and item.deleted_at is null;
  end if;

  if new.item_id is not null then
    select
      item.codigo_interno,
      upper(trim(coalesce(item.nome, item.descricao, new.item_nome))),
      coalesce(nullif(trim(item.unidade_medida), ''), new.unidade, 'UN')
      into new.item_codigo, new.item_nome, new.unidade
    from public.itens item
    where item.tenant_id = new.tenant_id
      and item.empresa_id = new.empresa_id
      and item.id = new.item_id
    limit 1;

    if tg_op = 'INSERT' and new.valor_ipi_unitario is null then
      select greatest(coalesce(fiscal.aliq_ipi, 0), 0)
        into v_aliquota_cadastro
      from public.fiscal_itens fiscal
      where fiscal.tenant_id = new.tenant_id
        and fiscal.empresa_id = new.empresa_id
        and fiscal.item_id = new.item_id
      limit 1;

      new.aliquota_ipi := coalesce(v_aliquota_cadastro, 0);
      new.valor_ipi_unitario := round(
        coalesce(new.valor_unitario, 0)
        * coalesce(v_aliquota_cadastro, 0)
        / 100,
        4
      );
    end if;
  else
    new.item_nome := upper(trim(coalesce(new.item_nome, '')));
    new.unidade := coalesce(nullif(trim(new.unidade), ''), 'UN');
  end if;

  select coalesce(pedido.destacar_ipi, false)
    into v_destacar_ipi
  from m.pedido_compra pedido
  where pedido.id = new.pedido_compra_id
    and pedido.tenant_id = new.tenant_id
    and pedido.empresa_id = new.empresa_id
    and pedido.deleted_at is null;

  new.valor_ipi_total := case
    when v_destacar_ipi then round(
      coalesce(new.quantidade, 0)
      * coalesce(new.valor_ipi_unitario, 0),
      2
    )
    else 0
  end;
  new.valor_total := round(
    coalesce(new.quantidade, 0)
    * (
      coalesce(new.valor_unitario, 0)
      + case
          when v_destacar_ipi then coalesce(new.valor_ipi_unitario, 0)
          else 0
        end
    ),
    2
  );
  return new;
end;
$$;

create or replace function m.trg_pedido_compra_biu()
returns trigger
language plpgsql
security definer
set search_path to 'm', 'public', 'c'
set row_security to off
as $$
declare
  v_condicao_id uuid;
begin
  if tg_op = 'INSERT' then
    if new.numero is null or new.numero <= 0 then
      new.numero := m.pedido_compra_next_numero(
        new.tenant_id,
        new.empresa_id
      );
    end if;
    if new.codigo is null or btrim(new.codigo) = '' then
      new.codigo := m.pedido_compra_build_codigo(
        new.empresa_id,
        new.numero,
        new.emissao_date
      );
    end if;
  end if;

  new.status := upper(trim(coalesce(new.status, 'RASCUNHO')));
  new.transporte_tipo :=
    nullif(upper(btrim(coalesce(new.transporte_tipo, ''))), '');
  new.transportadora_nome :=
    nullif(btrim(coalesce(new.transportadora_nome, '')), '');
  new.destacar_ipi := coalesce(new.destacar_ipi, false);

  if new.transporte_tipo is not null
     and new.transporte_tipo not in ('CIF', 'FOB')
  then
    raise exception 'Transporte invalido. Use CIF ou FOB.';
  end if;

  if new.transporte_tipo = 'FOB'
     and new.transportadora_nome is null
  then
    raise exception
      'Informe a transportadora quando o transporte for FOB.';
  end if;

  if new.transporte_tipo is distinct from 'FOB' then
    new.transportadora_nome := null;
  end if;

  if new.condicao_pagamento_id is not null then
    select condicao.id
      into v_condicao_id
    from c.condicao_pagamento condicao
    where condicao.id = new.condicao_pagamento_id
      and condicao.tenant_id = new.tenant_id
      and condicao.empresa_id = new.empresa_id
      and condicao.deleted_at is null
    limit 1;

    if v_condicao_id is null then
      raise exception
        'Condicao de pagamento invalida para este tenant/empresa (id=%)',
        new.condicao_pagamento_id;
    end if;
  end if;

  return new;
end;
$$;

-- A interface anterior exigia transportadora em CIF e nao a aceitava em FOB.
-- Inverte somente os pedidos da empresa validada para manter o significado
-- escolhido pelos usuarios e preservar os nomes das transportadoras. Esta
-- conversao ocorre depois da troca do trigger para aplicar a nova semantica.
update m.pedido_compra pedido
set
  transporte_tipo = case
    when upper(btrim(pedido.transporte_tipo)) = 'CIF' then 'FOB'
    when upper(btrim(pedido.transporte_tipo)) = 'FOB' then 'CIF'
    else pedido.transporte_tipo
  end,
  updated_at = now()
where pedido.tenant_id =
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
  and pedido.empresa_id =
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
  and pedido.deleted_at is null
  and upper(btrim(coalesce(pedido.transporte_tipo, ''))) in ('CIF', 'FOB');

create or replace function m.fn_pedido_compra_definir_destacar_ipi(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_pedido_id uuid,
  p_destacar boolean
)
returns jsonb
language plpgsql
security definer
set search_path to 'm', 'public'
set row_security to off
as $$
declare
  v_pedido m.pedido_compra%rowtype;
  v_itens integer;
begin
  if p_tenant_id is null
     or p_empresa_id is null
     or p_pedido_id is null
  then
    raise exception 'Tenant, empresa e pedido sao obrigatorios.';
  end if;

  if not public.can('compras', 'write', p_tenant_id) then
    raise exception 'Sem permissao para alterar pedido.';
  end if;

  select pedido.*
    into v_pedido
  from m.pedido_compra pedido
  where pedido.id = p_pedido_id
    and pedido.tenant_id = p_tenant_id
    and pedido.empresa_id = p_empresa_id
    and pedido.deleted_at is null
  for update;

  if not found then
    raise exception 'Pedido nao encontrado.';
  end if;

  update m.pedido_compra pedido
  set
    destacar_ipi = coalesce(p_destacar, false),
    updated_by = a.fn_current_usuario_id()
  where pedido.id = p_pedido_id
    and pedido.tenant_id = p_tenant_id
    and pedido.empresa_id = p_empresa_id;

  update m.pedido_compra_item item
  set
    aliquota_ipi = case
      when coalesce(p_destacar, false)
        and item.item_id is not null
        and item.valor_ipi_unitario is null
      then coalesce((
        select greatest(coalesce(fiscal.aliq_ipi, 0), 0)
        from public.fiscal_itens fiscal
        where fiscal.tenant_id = item.tenant_id
          and fiscal.empresa_id = item.empresa_id
          and fiscal.item_id = item.item_id
        limit 1
      ), 0)
      else item.aliquota_ipi
    end,
    valor_ipi_unitario = case
      when coalesce(p_destacar, false)
        and item.item_id is not null
        and item.valor_ipi_unitario is null
      then round(
        coalesce(item.valor_unitario, 0)
        * coalesce((
          select greatest(coalesce(fiscal.aliq_ipi, 0), 0)
          from public.fiscal_itens fiscal
          where fiscal.tenant_id = item.tenant_id
            and fiscal.empresa_id = item.empresa_id
            and fiscal.item_id = item.item_id
          limit 1
        ), 0)
        / 100,
        4
      )
      else item.valor_ipi_unitario
    end,
    updated_at = now(),
    updated_by = a.fn_current_usuario_id()
  where item.pedido_compra_id = p_pedido_id
    and item.tenant_id = p_tenant_id
    and item.empresa_id = p_empresa_id
    and item.deleted_at is null;

  get diagnostics v_itens = row_count;
  perform m.fn_pedido_compra_recalcular_totais(p_pedido_id);

  return jsonb_build_object(
    'pedidoId', p_pedido_id,
    'destacarIpi', coalesce(p_destacar, false),
    'itensRecalculados', v_itens
  );
end;
$$;

create or replace function m.fn_pedido_compra_transicionar(
  p_pedido_id uuid,
  p_status_para text,
  p_mensagem text default null
)
returns void
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
declare
  v_pedido m.pedido_compra%rowtype;
  v_new text;
  v_missing text[] := array[]::text[];
begin
  select *
    into v_pedido
  from m.pedido_compra pedido
  where pedido.id = p_pedido_id
    and pedido.deleted_at is null
  for update;

  if not found then
    raise exception 'Pedido nao encontrado';
  end if;

  v_new := upper(trim(coalesce(p_status_para, '')));

  if v_new in ('APROVADO', 'REPROVADO')
     and not public.can('compras', 'approve', v_pedido.tenant_id)
  then
    raise exception 'Sem permissao para aprovar/reprovar';
  end if;
  if v_new in ('PARCIAL_RECEBIDO', 'RECEBIDO')
     and not public.can('compras', 'receive', v_pedido.tenant_id)
  then
    raise exception 'Sem permissao para receber';
  end if;
  if v_new not in (
    'APROVADO',
    'REPROVADO',
    'PARCIAL_RECEBIDO',
    'RECEBIDO'
  ) and not public.can('compras', 'write', v_pedido.tenant_id)
  then
    raise exception 'Sem permissao para alterar pedido';
  end if;

  if v_new in ('AGUARDANDO_APROVACAO', 'APROVADO', 'ENVIADO') then
    if v_pedido.solicitante_usuario_id is null then
      v_missing := array_append(v_missing, 'solicitante');
    end if;
    if v_pedido.previsao_entrega_date is null then
      v_missing := array_append(v_missing, 'data de entrega');
    end if;
    if v_pedido.condicao_pagamento_id is null then
      v_missing := array_append(v_missing, 'condicao de pagamento');
    end if;
    if nullif(
      btrim(coalesce(v_pedido.transporte_tipo, '')),
      ''
    ) is null then
      v_missing := array_append(v_missing, 'transporte');
    end if;
    if upper(coalesce(v_pedido.transporte_tipo, '')) = 'FOB'
       and nullif(
         btrim(coalesce(v_pedido.transportadora_nome, '')),
         ''
       ) is null
    then
      v_missing := array_append(v_missing, 'transportadora');
    end if;

    if coalesce(array_length(v_missing, 1), 0) > 0 then
      raise exception
        'Preencha % antes de solicitar aprovacao, aprovar ou enviar o pedido',
        array_to_string(v_missing, ', ');
    end if;
  end if;

  update m.pedido_compra pedido
  set
    status = v_new,
    cancel_reason = case
      when v_new = 'CANCELADO' then p_mensagem
      else pedido.cancel_reason
    end,
    updated_by = a.fn_current_usuario_id()
  where pedido.id = p_pedido_id;

  perform m.fn_pedido_compra_log_evento(
    p_pedido_id,
    case
      when v_new in ('APROVADO', 'REPROVADO') then 'APROVACAO'
      else 'STATUS'
    end,
    v_pedido.status,
    v_new,
    p_mensagem
  );
end;
$$;

revoke all on function m.fn_pedido_compra_definir_destacar_ipi(
  uuid,
  uuid,
  uuid,
  boolean
) from public, anon;

grant execute on function m.fn_pedido_compra_definir_destacar_ipi(
  uuid,
  uuid,
  uuid,
  boolean
) to authenticated, service_role;

comment on function m.fn_pedido_compra_definir_destacar_ipi(
  uuid,
  uuid,
  uuid,
  boolean
) is
  'Ativa/desativa o destaque de IPI, inicializa valores pelo cadastro fiscal e recalcula o pedido no escopo tenant/empresa.';
