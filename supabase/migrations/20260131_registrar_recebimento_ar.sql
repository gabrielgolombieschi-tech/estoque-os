-- Adds AR receipt RPC analogous to f.registrar_pagamento_ap.
-- IMPORTANT: verify with your existing finance schema in Supabase before applying.

create schema if not exists f;

create or replace function f.registrar_recebimento_ar(
  p_titulo_id uuid,
  p_conta_bancaria_id uuid,
  p_data_pagamento date,
  p_forma_pagamento text,
  p_valor numeric,
  p_observacoes text default null,
  p_change_reason text default null
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_pagamento_id uuid;
  v_titulo record;
  v_valor_restante numeric;
  v_parcela record;
  v_aplicado numeric;
  v_new_aberto numeric;
begin
  if p_titulo_id is null then
    raise exception 'p_titulo_id obrigatório';
  end if;
  if p_conta_bancaria_id is null then
    raise exception 'p_conta_bancaria_id obrigatório';
  end if;
  if p_data_pagamento is null then
    raise exception 'p_data_pagamento obrigatório';
  end if;
  if p_valor is null or p_valor <= 0 then
    raise exception 'p_valor deve ser > 0';
  end if;
  if p_forma_pagamento is null or length(trim(p_forma_pagamento)) = 0 then
    raise exception 'p_forma_pagamento obrigatório';
  end if;

  select *
    into v_titulo
  from f.titulo t
  where t.id = p_titulo_id
    and t.deleted_at is null;

  if not found then
    raise exception 'Título não encontrado';
  end if;

  if v_titulo.tipo <> 'AR' then
    raise exception 'Somente AR pode receber (tipo=%)', v_titulo.tipo;
  end if;

  if v_titulo.status not in ('APROVADO','AGENDADO','PAGO') then
    -- mirror AP function behaviour: require at least approved-ish.
    raise exception 'Status inválido para recebimento (status=%)', v_titulo.status;
  end if;

  if p_valor > v_titulo.valor_aberto then
    raise exception 'Valor maior que saldo em aberto';
  end if;

  insert into f.pagamento(
    tenant_id,
    empresa_id,
    conta_bancaria_id,
    data_pagamento,
    forma_pagamento,
    valor,
    observacoes,
    change_reason
  )
  values (
    v_titulo.tenant_id,
    v_titulo.empresa_id,
    p_conta_bancaria_id,
    p_data_pagamento,
    p_forma_pagamento,
    p_valor,
    p_observacoes,
    p_change_reason
  )
  returning id into v_pagamento_id;

  v_valor_restante := p_valor;

  for v_parcela in
    select p.id, p.valor_aberto
    from f.titulo_parcela p
    where p.titulo_id = p_titulo_id
      and p.deleted_at is null
      and p.valor_aberto > 0
    order by p.vencimento_date asc, p.numero asc
  loop
    exit when v_valor_restante <= 0;

    v_aplicado := least(v_parcela.valor_aberto, v_valor_restante);

    insert into f.pagamento_item(
      tenant_id,
      empresa_id,
      pagamento_id,
      titulo_parcela_id,
      valor,
      change_reason
    )
    values (
      v_titulo.tenant_id,
      v_titulo.empresa_id,
      v_pagamento_id,
      v_parcela.id,
      v_aplicado,
      p_change_reason
    );

    update f.titulo_parcela
      set valor_aberto = valor_aberto - v_aplicado
    where id = v_parcela.id;

    v_valor_restante := v_valor_restante - v_aplicado;
  end loop;

  select coalesce(sum(p.valor_aberto), 0)
    into v_new_aberto
  from f.titulo_parcela p
  where p.titulo_id = p_titulo_id
    and p.deleted_at is null;

  update f.titulo
    set valor_aberto = v_new_aberto,
        status = case when v_new_aberto <= 0 then 'PAGO' else v_titulo.status end
  where id = p_titulo_id;

  return v_pagamento_id;
end;
$$;

-- Grants: allow authenticated users to execute (RLS will still enforce tenant/empresa).
grant execute on function f.registrar_recebimento_ar(uuid, uuid, date, text, numeric, text, text) to authenticated;
