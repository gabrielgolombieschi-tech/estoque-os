alter table if exists m.pedido_compra
  add column if not exists transporte_tipo text,
  add column if not exists transportadora_nome text;

do $$
begin
  if exists (
    select 1
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where con.conname = 'pedido_compra_transporte_tipo_check'
      and nsp.nspname = 'm'
      and rel.relname = 'pedido_compra'
  ) then
    alter table m.pedido_compra
      drop constraint pedido_compra_transporte_tipo_check;
  end if;

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
    add constraint pedido_compra_transporte_tipo_check
    check (transporte_tipo is null or upper(btrim(transporte_tipo)) in ('CIF', 'FOB'));

  alter table m.pedido_compra
    add constraint pedido_compra_transportadora_nome_check
    check (
      upper(coalesce(btrim(transporte_tipo), '')) <> 'CIF'
      or nullif(btrim(coalesce(transportadora_nome, '')), '') is not null
    );
end $$;

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
      new.numero := m.pedido_compra_next_numero(new.tenant_id, new.empresa_id);
    end if;
    if new.codigo is null or btrim(new.codigo) = '' then
      new.codigo := m.pedido_compra_build_codigo(new.empresa_id, new.numero, new.emissao_date);
    end if;
  end if;

  new.status := upper(trim(coalesce(new.status, 'RASCUNHO')));
  new.transporte_tipo := nullif(upper(btrim(coalesce(new.transporte_tipo, ''))), '');
  new.transportadora_nome := nullif(btrim(coalesce(new.transportadora_nome, '')), '');

  if new.transporte_tipo is not null and new.transporte_tipo not in ('CIF', 'FOB') then
    raise exception 'Transporte invalido. Use CIF ou FOB.';
  end if;

  if new.transporte_tipo = 'CIF' and new.transportadora_nome is null then
    raise exception 'Informe a transportadora quando o transporte for CIF.';
  end if;

  if new.transporte_tipo is distinct from 'CIF' then
    new.transportadora_nome := null;
  end if;

  if new.condicao_pagamento_id is not null then
    select cp.id
      into v_condicao_id
    from c.condicao_pagamento cp
    where cp.id = new.condicao_pagamento_id
      and cp.tenant_id = new.tenant_id
      and cp.empresa_id = new.empresa_id
      and cp.deleted_at is null
    limit 1;

    if v_condicao_id is null then
      raise exception 'Condicao de pagamento invalida para este tenant/empresa (id=%)', new.condicao_pagamento_id;
    end if;
  end if;

  return new;
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
  from m.pedido_compra p
  where p.id = p_pedido_id
    and p.deleted_at is null
  for update;

  if not found then
    raise exception 'Pedido nao encontrado';
  end if;

  v_new := upper(trim(coalesce(p_status_para, '')));

  if v_new in ('APROVADO', 'REPROVADO') and not public.can('compras', 'approve', v_pedido.tenant_id) then
    raise exception 'Sem permissao para aprovar/reprovar';
  end if;
  if v_new in ('PARCIAL_RECEBIDO', 'RECEBIDO') and not public.can('compras', 'receive', v_pedido.tenant_id) then
    raise exception 'Sem permissao para receber';
  end if;
  if v_new not in ('APROVADO', 'REPROVADO', 'PARCIAL_RECEBIDO', 'RECEBIDO') and not public.can('compras', 'write', v_pedido.tenant_id) then
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
    if nullif(btrim(coalesce(v_pedido.transporte_tipo, '')), '') is null then
      v_missing := array_append(v_missing, 'transporte');
    end if;
    if upper(coalesce(v_pedido.transporte_tipo, '')) = 'CIF'
      and nullif(btrim(coalesce(v_pedido.transportadora_nome, '')), '') is null then
      v_missing := array_append(v_missing, 'transportadora');
    end if;

    if coalesce(array_length(v_missing, 1), 0) > 0 then
      raise exception 'Preencha % antes de solicitar aprovacao, aprovar ou enviar o pedido', array_to_string(v_missing, ', ');
    end if;
  end if;

  update m.pedido_compra p
     set status = v_new,
         cancel_reason = case when v_new = 'CANCELADO' then p_mensagem else p.cancel_reason end,
         updated_by = a.fn_current_usuario_id()
   where p.id = p_pedido_id;

  perform m.fn_pedido_compra_log_evento(
    p_pedido_id,
    case when v_new in ('APROVADO', 'REPROVADO') then 'APROVACAO' else 'STATUS' end,
    v_pedido.status,
    v_new,
    p_mensagem
  );
end;
$$;
