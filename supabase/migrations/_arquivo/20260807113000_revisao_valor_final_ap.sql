begin;

-- Revisa o valor efetivo de uma previsao de AP sem apagar pagamentos ja
-- registrados. A diferenca deixa de ser tratada como divida e fica auditada
-- em f.evento_financeiro.
create or replace function f.revisar_valor_final_ap(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_titulo_id uuid,
  p_titulo_parcela_id uuid,
  p_novo_valor_final numeric,
  p_motivo text,
  p_origem text default 'REVISAO_MANUAL'
)
returns jsonb
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_titulo f.titulo%rowtype;
  v_parcela f.titulo_parcela%rowtype;
  v_usuario_id uuid;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_origem text := upper(coalesce(nullif(btrim(p_origem), ''), 'REVISAO_MANUAL'));
  v_novo_valor numeric(15,2) := round(coalesce(p_novo_valor_final, 0), 2);
  v_valor_pago numeric(15,2);
  v_novo_aberto numeric(15,2);
  v_titulo_total_novo numeric(15,2);
  v_titulo_aberto_novo numeric(15,2);
  v_status_novo text;
  v_rateios_ajustados boolean := false;
  v_rateio_total_anterior numeric(15,2);
  v_rateio_total_novo numeric(15,2);
  v_rateio_ultimo_id uuid;
begin
  if p_tenant_id is null
     or p_empresa_id is null
     or p_titulo_id is null
     or p_titulo_parcela_id is null then
    raise exception 'Tenant, empresa, titulo e parcela sao obrigatorios';
  end if;

  if p_novo_valor_final is null or v_novo_valor <= 0 then
    raise exception 'O novo valor final deve ser maior que zero';
  end if;

  if v_motivo is null or length(v_motivo) < 5 then
    raise exception 'Informe o motivo da revisao (minimo 5 caracteres)';
  end if;

  if auth.uid() is not null then
    if p_tenant_id is distinct from public.current_tenant_id()
       or not f.has_finance_access(p_tenant_id, p_empresa_id) then
      raise exception 'Sem acesso financeiro ao tenant/empresa solicitado';
    end if;
  elsif coalesce(auth.role(), '') <> 'service_role'
        and current_user not in ('postgres', 'service_role') then
    raise exception 'Usuario nao autenticado';
  end if;

  select t.*
    into v_titulo
  from f.titulo t
  where t.id = p_titulo_id
    and t.tenant_id = p_tenant_id
    and t.empresa_id = p_empresa_id
    and t.deleted_at is null
  for update;

  if not found then
    raise exception 'Titulo AP nao encontrado no tenant/empresa informado';
  end if;

  if v_titulo.tipo <> 'AP' then
    raise exception 'A revisao de valor final permite somente titulos AP';
  end if;

  if v_titulo.status = 'CANCELADO' then
    raise exception 'Nao e possivel revisar um titulo cancelado';
  end if;

  select tp.*
    into v_parcela
  from f.titulo_parcela tp
  where tp.id = p_titulo_parcela_id
    and tp.tenant_id = p_tenant_id
    and tp.titulo_id = p_titulo_id
    and tp.deleted_at is null
  for update;

  if not found then
    raise exception 'Parcela nao encontrada para o titulo informado';
  end if;

  select coalesce(sum(pi.valor), 0)::numeric(15,2)
    into v_valor_pago
  from f.pagamento_item pi
  join f.pagamento p
    on p.id = pi.pagamento_id
   and p.tenant_id = p_tenant_id
   and p.empresa_id = p_empresa_id
   and p.deleted_at is null
  where pi.tenant_id = p_tenant_id
    and pi.empresa_id = p_empresa_id
    and pi.titulo_parcela_id = p_titulo_parcela_id
    and pi.deleted_at is null;

  v_valor_pago := round(coalesce(v_valor_pago, 0), 2);

  if v_novo_valor < v_valor_pago then
    raise exception
      'Novo valor final (%) nao pode ser menor que o total ja pago (%)',
      v_novo_valor,
      v_valor_pago;
  end if;

  if v_novo_valor = round(v_parcela.valor, 2) then
    raise exception 'O novo valor final e igual ao valor atual da parcela';
  end if;

  v_novo_aberto := round(v_novo_valor - v_valor_pago, 2);

  update f.titulo_parcela tp
  set valor = v_novo_valor,
      valor_aberto = v_novo_aberto,
      updated_at = now(),
      updated_by = a.fn_current_usuario_id()
  where tp.id = v_parcela.id
    and tp.tenant_id = p_tenant_id;

  select
    coalesce(sum(tp.valor), 0)::numeric(15,2),
    coalesce(sum(tp.valor_aberto), 0)::numeric(15,2)
  into v_titulo_total_novo, v_titulo_aberto_novo
  from f.titulo_parcela tp
  where tp.tenant_id = p_tenant_id
    and tp.titulo_id = p_titulo_id
    and tp.deleted_at is null;

  v_status_novo := case
    when v_titulo_aberto_novo = 0 then 'PAGO'
    when v_titulo.status = 'PAGO' and exists (
      select 1
      from f.titulo_aprovacao ta
      where ta.tenant_id = p_tenant_id
        and ta.titulo_id = p_titulo_id
        and ta.deleted_at is null
    ) then 'APROVADO'
    when v_titulo.status = 'PAGO' then 'PENDENTE'
    else v_titulo.status
  end;

  -- Mantem rateios fixos coerentes quando eles representavam exatamente o
  -- valor anterior do titulo. Rateios percentuais se ajustam naturalmente.
  select coalesce(sum(tr.valor), 0)::numeric(15,2)
    into v_rateio_total_anterior
  from f.titulo_rateio tr
  where tr.tenant_id = p_tenant_id
    and tr.titulo_id = p_titulo_id
    and tr.deleted_at is null
    and tr.valor is not null;

  if v_titulo.valor_total > 0
     and abs(v_rateio_total_anterior - v_titulo.valor_total) <= 0.02
     and exists (
       select 1
       from f.titulo_rateio tr
       where tr.tenant_id = p_tenant_id
         and tr.titulo_id = p_titulo_id
         and tr.deleted_at is null
         and tr.valor is not null
     ) then
    update f.titulo_rateio tr
    set valor = round(tr.valor * v_titulo_total_novo / v_titulo.valor_total, 2),
        updated_at = now(),
        updated_by = a.fn_current_usuario_id()
    where tr.tenant_id = p_tenant_id
      and tr.titulo_id = p_titulo_id
      and tr.deleted_at is null
      and tr.valor is not null;

    select coalesce(sum(tr.valor), 0)::numeric(15,2)
      into v_rateio_total_novo
    from f.titulo_rateio tr
    where tr.tenant_id = p_tenant_id
      and tr.titulo_id = p_titulo_id
      and tr.deleted_at is null
      and tr.valor is not null;

    select tr.id
      into v_rateio_ultimo_id
    from f.titulo_rateio tr
    where tr.tenant_id = p_tenant_id
      and tr.titulo_id = p_titulo_id
      and tr.deleted_at is null
      and tr.valor is not null
    order by tr.id desc
    limit 1;

    if v_rateio_ultimo_id is not null
       and v_rateio_total_novo is distinct from v_titulo_total_novo then
      update f.titulo_rateio tr
      set valor = round(tr.valor + (v_titulo_total_novo - v_rateio_total_novo), 2),
          updated_at = now(),
          updated_by = a.fn_current_usuario_id()
      where tr.id = v_rateio_ultimo_id
        and tr.tenant_id = p_tenant_id;
    end if;

    v_rateios_ajustados := true;
  end if;

  v_usuario_id := a.fn_current_usuario_id();

  if v_usuario_id is null then
    select ut.usuario_id
      into v_usuario_id
    from a.usuario_tenant ut
    where ut.tenant_id = p_tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
      and ut.papel in ('OWNER', 'ADMIN')
    order by ut.created_at nulls last
    limit 1;
  end if;

  update f.titulo t
  set valor_total = v_titulo_total_novo,
      valor_aberto = v_titulo_aberto_novo,
      status = v_status_novo,
      updated_at = now(),
      updated_by = v_usuario_id
  where t.id = p_titulo_id
    and t.tenant_id = p_tenant_id
    and t.empresa_id = p_empresa_id;

  insert into f.evento_financeiro (
    tenant_id,
    empresa_id,
    evento,
    ref_table,
    ref_id,
    payload,
    created_at,
    created_by
  ) values (
    p_tenant_id,
    p_empresa_id,
    'VALOR_FINAL_AP_REVISADO',
    'f.titulo',
    p_titulo_id,
    jsonb_build_object(
      'titulo_id', p_titulo_id,
      'titulo_parcela_id', p_titulo_parcela_id,
      'parcela_numero', v_parcela.numero,
      'valor_anterior', round(v_parcela.valor, 2),
      'valor_novo', v_novo_valor,
      'diferenca', round(v_novo_valor - v_parcela.valor, 2),
      'valor_pago', v_valor_pago,
      'saldo_anterior', round(v_parcela.valor_aberto, 2),
      'saldo_novo', v_novo_aberto,
      'titulo_valor_anterior', round(v_titulo.valor_total, 2),
      'titulo_valor_novo', v_titulo_total_novo,
      'titulo_saldo_anterior', round(v_titulo.valor_aberto, 2),
      'titulo_saldo_novo', v_titulo_aberto_novo,
      'status_anterior', v_titulo.status,
      'status_novo', v_status_novo,
      'rateios_ajustados', v_rateios_ajustados,
      'motivo', v_motivo,
      'origem', v_origem
    ),
    now(),
    v_usuario_id
  );

  return jsonb_build_object(
    'tituloId', p_titulo_id,
    'parcelaId', p_titulo_parcela_id,
    'valorAnterior', round(v_parcela.valor, 2),
    'valorNovo', v_novo_valor,
    'valorPago', v_valor_pago,
    'saldoNovo', v_novo_aberto,
    'statusNovo', v_status_novo
  );
end;
$$;

comment on function f.revisar_valor_final_ap(uuid, uuid, uuid, uuid, numeric, text, text) is
  'Revisa o valor efetivo de uma parcela AP, preserva pagamentos e grava trilha auditavel.';

revoke all on function f.revisar_valor_final_ap(uuid, uuid, uuid, uuid, numeric, text, text) from public;
grant execute on function f.revisar_valor_final_ap(uuid, uuid, uuid, uuid, numeric, text, text)
  to authenticated, service_role;

-- Pagamento menor que a previsao com confirmacao de que aquele e o valor
-- efetivamente devido. O pagamento e a revisao ocorrem na mesma transacao.
create or replace function f.registrar_pagamento_ap_valor_final(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_titulo_id uuid,
  p_titulo_parcela_id uuid,
  p_conta_bancaria_id uuid,
  p_data_pagamento date,
  p_forma_pagamento text,
  p_valor_principal numeric,
  p_valor_juros numeric default 0,
  p_valor_multa numeric default 0,
  p_valor_desconto numeric default 0,
  p_observacoes text default null,
  p_motivo_ajuste text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_titulo f.titulo%rowtype;
  v_parcela f.titulo_parcela%rowtype;
  v_pagamento_id uuid;
  v_novo_valor_final numeric(15,2);
begin
  if auth.uid() is not null then
    if p_tenant_id is distinct from public.current_tenant_id()
       or not f.has_finance_access(p_tenant_id, p_empresa_id) then
      raise exception 'Sem acesso financeiro ao tenant/empresa solicitado';
    end if;
  elsif coalesce(auth.role(), '') <> 'service_role'
        and current_user not in ('postgres', 'service_role') then
    raise exception 'Usuario nao autenticado';
  end if;

  if nullif(btrim(coalesce(p_motivo_ajuste, '')), '') is null
     or length(btrim(p_motivo_ajuste)) < 5 then
    raise exception 'Informe o motivo da revisao (minimo 5 caracteres)';
  end if;

  select t.*
    into v_titulo
  from f.titulo t
  where t.id = p_titulo_id
    and t.tenant_id = p_tenant_id
    and t.empresa_id = p_empresa_id
    and t.tipo = 'AP'
    and t.deleted_at is null
  for update;

  if not found then
    raise exception 'Titulo AP nao encontrado no tenant/empresa informado';
  end if;

  select tp.*
    into v_parcela
  from f.titulo_parcela tp
  where tp.id = p_titulo_parcela_id
    and tp.tenant_id = p_tenant_id
    and tp.titulo_id = p_titulo_id
    and tp.deleted_at is null
  for update;

  if not found then
    raise exception 'Parcela nao encontrada para o titulo informado';
  end if;

  if round(coalesce(p_valor_principal, 0), 2) <= 0
     or round(p_valor_principal, 2) >= round(v_parcela.valor_aberto, 2) then
    raise exception 'Para confirmar valor final, o pagamento deve ser menor que o saldo da parcela';
  end if;

  if round(v_titulo.valor_aberto, 2) <> round(v_parcela.valor_aberto, 2) then
    raise exception 'Este titulo possui outras parcelas abertas. Registre o pagamento e revise a parcela separadamente';
  end if;

  v_novo_valor_final := round(v_parcela.valor - v_parcela.valor_aberto + p_valor_principal, 2);

  v_pagamento_id := f.registrar_pagamento_ap_v2(
    p_titulo_id,
    p_conta_bancaria_id,
    p_data_pagamento,
    p_forma_pagamento,
    p_valor_principal,
    coalesce(p_valor_juros, 0),
    coalesce(p_valor_multa, 0),
    coalesce(p_valor_desconto, 0),
    p_observacoes,
    'UI: pagamento com valor final confirmado'
  );

  perform f.revisar_valor_final_ap(
    p_tenant_id,
    p_empresa_id,
    p_titulo_id,
    p_titulo_parcela_id,
    v_novo_valor_final,
    p_motivo_ajuste,
    'PAGAMENTO_VALOR_FINAL'
  );

  return v_pagamento_id;
end;
$$;

comment on function f.registrar_pagamento_ap_valor_final(uuid, uuid, uuid, uuid, uuid, date, text, numeric, numeric, numeric, numeric, text, text) is
  'Registra pagamento menor que a previsao e encerra atomicamente a diferenca revisada.';

revoke all on function f.registrar_pagamento_ap_valor_final(uuid, uuid, uuid, uuid, uuid, date, text, numeric, numeric, numeric, numeric, text, text) from public;
grant execute on function f.registrar_pagamento_ap_valor_final(uuid, uuid, uuid, uuid, uuid, date, text, numeric, numeric, numeric, numeric, text, text)
  to authenticated, service_role;

create or replace function f.historico_revisoes_valor_ap(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_titulo_id uuid,
  p_titulo_parcela_id uuid
)
returns table (
  id uuid,
  revisado_em timestamptz,
  valor_anterior numeric,
  valor_novo numeric,
  diferenca numeric,
  valor_pago numeric,
  saldo_anterior numeric,
  saldo_novo numeric,
  motivo text,
  origem text,
  revisado_por text
)
language plpgsql
stable
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
begin
  if auth.uid() is not null then
    if p_tenant_id is distinct from public.current_tenant_id()
       or not f.has_finance_access(p_tenant_id, p_empresa_id) then
      raise exception 'Sem acesso financeiro ao tenant/empresa solicitado';
    end if;
  elsif coalesce(auth.role(), '') <> 'service_role'
        and current_user not in ('postgres', 'service_role') then
    raise exception 'Usuario nao autenticado';
  end if;

  if not exists (
    select 1
    from f.titulo t
    join f.titulo_parcela tp
      on tp.titulo_id = t.id
     and tp.tenant_id = t.tenant_id
     and tp.deleted_at is null
    where t.id = p_titulo_id
      and t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.tipo = 'AP'
      and t.deleted_at is null
      and tp.id = p_titulo_parcela_id
  ) then
    raise exception 'Titulo/parcela AP nao encontrado no escopo informado';
  end if;

  return query
  select
    ef.id,
    ef.created_at,
    nullif(ef.payload ->> 'valor_anterior', '')::numeric,
    nullif(ef.payload ->> 'valor_novo', '')::numeric,
    nullif(ef.payload ->> 'diferenca', '')::numeric,
    nullif(ef.payload ->> 'valor_pago', '')::numeric,
    nullif(ef.payload ->> 'saldo_anterior', '')::numeric,
    nullif(ef.payload ->> 'saldo_novo', '')::numeric,
    ef.payload ->> 'motivo',
    ef.payload ->> 'origem',
    coalesce(u.nome, 'Sistema')::text
  from f.evento_financeiro ef
  left join a.usuario u
    on u.id = ef.created_by
   and u.deleted_at is null
  where ef.tenant_id = p_tenant_id
    and ef.empresa_id = p_empresa_id
    and ef.evento = 'VALOR_FINAL_AP_REVISADO'
    and ef.ref_table = 'f.titulo'
    and ef.ref_id = p_titulo_id
    and ef.payload ->> 'titulo_parcela_id' = p_titulo_parcela_id::text
  order by ef.created_at desc;
end;
$$;

comment on function f.historico_revisoes_valor_ap(uuid, uuid, uuid, uuid) is
  'Lista a trilha de revisoes do valor final de uma parcela AP no escopo informado.';

revoke all on function f.historico_revisoes_valor_ap(uuid, uuid, uuid, uuid) from public;
grant execute on function f.historico_revisoes_valor_ap(uuid, uuid, uuid, uuid)
  to authenticated, service_role;

commit;
