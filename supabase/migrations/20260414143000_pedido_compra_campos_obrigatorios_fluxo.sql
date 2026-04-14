alter table if exists m.pedido_compra
  add column if not exists previsao_entrega_date date,
  add column if not exists condicao_pagamento_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where con.conname = 'fk_pedido_compra__condicao_pagamento__c_condicao_pagamento'
      and nsp.nspname = 'm'
      and rel.relname = 'pedido_compra'
  ) then
    alter table m.pedido_compra
      add constraint fk_pedido_compra__condicao_pagamento__c_condicao_pagamento
      foreign key (condicao_pagamento_id)
      references c.condicao_pagamento(id)
      on update restrict
      on delete set null;
  end if;
end $$;

create index if not exists idx_pedido_compra__tenant_empresa_condicao_pagamento
  on m.pedido_compra (tenant_id, empresa_id, condicao_pagamento_id);

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
