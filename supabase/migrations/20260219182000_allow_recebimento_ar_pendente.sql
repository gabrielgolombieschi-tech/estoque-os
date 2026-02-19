create or replace function f.registrar_recebimento_ar_v2(
  p_titulo_id uuid,
  p_conta_bancaria_id uuid,
  p_data_pagamento date,
  p_forma_pagamento text,
  p_valor_principal numeric,
  p_valor_juros numeric default 0,
  p_valor_multa numeric default 0,
  p_valor_desconto numeric default 0,
  p_observacoes text default null,
  p_change_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = f, public, a, c
set row_security = off
as $$
declare
  v_pagamento_id uuid;
  v_titulo record;
  v_total numeric(15,2);
  v_valor_restante numeric(15,2);
  v_parcela record;
  v_aplicado numeric(15,2);
  v_new_aberto numeric(15,2);
  v_user uuid;
begin
  if p_titulo_id is null then raise exception 'p_titulo_id obrigatorio'; end if;
  if p_conta_bancaria_id is null then raise exception 'p_conta_bancaria_id obrigatorio'; end if;
  if p_data_pagamento is null then raise exception 'p_data_pagamento obrigatorio'; end if;

  if p_valor_principal is null or p_valor_principal <= 0 then
    raise exception 'Valor principal deve ser > 0';
  end if;

  if coalesce(p_valor_juros,0) < 0 or coalesce(p_valor_multa,0) < 0 or coalesce(p_valor_desconto,0) < 0 then
    raise exception 'Juros/Multa/Desconto nao podem ser negativos';
  end if;

  if p_forma_pagamento is null or length(trim(p_forma_pagamento)) = 0 then
    raise exception 'p_forma_pagamento obrigatorio';
  end if;

  select *
    into v_titulo
    from f.titulo t
   where t.id = p_titulo_id
     and t.deleted_at is null;

  if not found then raise exception 'Titulo nao encontrado'; end if;

  if v_titulo.tipo <> 'AR' then
    raise exception 'Somente AR pode receber (tipo=%)', v_titulo.tipo;
  end if;

  -- Permite recebimento tambem quando AR estiver PENDENTE.
  if v_titulo.status not in ('PENDENTE','APROVADO','AGENDADO','PAGO') then
    raise exception 'Status invalido para recebimento (status=%)', v_titulo.status;
  end if;

  if round(p_valor_principal,2) > round(v_titulo.valor_aberto,2) then
    raise exception 'Principal (%) maior que saldo em aberto (%)', round(p_valor_principal,2), round(v_titulo.valor_aberto,2);
  end if;

  v_total := round((p_valor_principal + coalesce(p_valor_juros,0) + coalesce(p_valor_multa,0) - coalesce(p_valor_desconto,0)), 2);
  if v_total <= 0 then
    raise exception 'Total do recebimento deve ser > 0';
  end if;

  v_user := a.fn_current_usuario_id();

  insert into f.pagamento(
    tenant_id,
    empresa_id,
    conta_bancaria_id,
    data_pagamento,
    forma_pagamento,
    valor,
    valor_principal,
    valor_juros,
    valor_multa,
    valor_desconto,
    observacoes,
    change_reason,
    pago_por,
    created_at, updated_at, created_by, updated_by
  )
  values (
    v_titulo.tenant_id,
    v_titulo.empresa_id,
    p_conta_bancaria_id,
    p_data_pagamento,
    p_forma_pagamento,
    v_total,
    round(p_valor_principal,2),
    round(coalesce(p_valor_juros,0),2),
    round(coalesce(p_valor_multa,0),2),
    round(coalesce(p_valor_desconto,0),2),
    p_observacoes,
    p_change_reason,
    v_user,
    now(), now(), v_user, v_user
  )
  returning id into v_pagamento_id;

  v_valor_restante := round(p_valor_principal,2);

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
      change_reason,
      created_at, created_by, updated_at, updated_by
    )
    values (
      v_titulo.tenant_id,
      v_titulo.empresa_id,
      v_pagamento_id,
      v_parcela.id,
      v_aplicado,
      p_change_reason,
      now(), v_user, now(), v_user
    );

    update f.titulo_parcela
       set valor_aberto = round(valor_aberto - v_aplicado,2),
           updated_at = now(),
           updated_by = v_user
     where id = v_parcela.id;

    v_valor_restante := round(v_valor_restante - v_aplicado,2);
  end loop;

  select coalesce(sum(p.valor_aberto), 0)::numeric(15,2)
    into v_new_aberto
    from f.titulo_parcela p
   where p.titulo_id = p_titulo_id
     and p.deleted_at is null;

  update f.titulo
     set valor_aberto = v_new_aberto,
         status = case when v_new_aberto <= 0 then 'PAGO' else v_titulo.status end,
         updated_at = now(),
         updated_by = v_user
   where id = p_titulo_id;

  return v_pagamento_id;
end;
$$;

grant all on function f.registrar_recebimento_ar_v2(
  uuid, uuid, date, text, numeric, numeric, numeric, numeric, text, text
) to authenticated;
grant all on function f.registrar_recebimento_ar_v2(
  uuid, uuid, date, text, numeric, numeric, numeric, numeric, text, text
) to service_role;
