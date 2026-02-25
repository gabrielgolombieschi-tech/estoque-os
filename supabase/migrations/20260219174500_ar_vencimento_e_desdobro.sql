create or replace function f.atualizar_titulo_parcela_vencimento_date(
  p_parcela_id uuid,
  p_vencimento_date date,
  p_change_reason text default null
)
returns void
language plpgsql
security definer
set search_path = f, public, a
set row_security = off
as $$
declare
  v_parcela f.titulo_parcela%rowtype;
  v_titulo f.titulo%rowtype;
  v_user uuid;
begin
  if p_parcela_id is null then
    raise exception 'p_parcela_id obrigatorio';
  end if;

  if p_vencimento_date is null then
    raise exception 'p_vencimento_date obrigatorio';
  end if;

  if auth.uid() is null then
    if current_user not in ('postgres', 'service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select *
    into v_parcela
  from f.titulo_parcela
  where id = p_parcela_id
    and deleted_at is null;

  if not found then
    raise exception 'Parcela nao encontrada (id=%)', p_parcela_id;
  end if;

  select *
    into v_titulo
  from f.titulo
  where id = v_parcela.titulo_id
    and deleted_at is null;

  if not found then
    raise exception 'Titulo nao encontrado para parcela (id=%)', p_parcela_id;
  end if;

  if v_titulo.tipo not in ('AP', 'AR') then
    raise exception 'Somente parcelas AP/AR podem ser alteradas nesta operacao';
  end if;

  if auth.uid() is not null then
    if not f.has_finance_access(v_titulo.tenant_id, v_titulo.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  if coalesce(v_parcela.valor_aberto, 0) <= 0 then
    raise exception 'Parcela liquidada; vencimento nao pode ser alterado';
  end if;

  v_user := a.fn_current_usuario_id();

  update f.titulo_parcela
     set vencimento_date = p_vencimento_date,
         updated_at = now(),
         updated_by = v_user
   where id = p_parcela_id;
end;
$$;
grant all on function f.atualizar_titulo_parcela_vencimento_date(uuid, date, text) to authenticated;
grant all on function f.atualizar_titulo_parcela_vencimento_date(uuid, date, text) to service_role;
create or replace function f.atualizar_titulo_parcela_vencimento_date(
  p_parcela_id uuid,
  p_vencimento_date date
)
returns void
language plpgsql
security definer
set search_path = f, public, a
set row_security = off
as $$
begin
  perform f.atualizar_titulo_parcela_vencimento_date(
    p_parcela_id => p_parcela_id,
    p_vencimento_date => p_vencimento_date,
    p_change_reason => null
  );
end;
$$;
grant all on function f.atualizar_titulo_parcela_vencimento_date(uuid, date) to authenticated;
grant all on function f.atualizar_titulo_parcela_vencimento_date(uuid, date) to service_role;
create or replace function f.desdobrar_parcela_ar_para_recebimento(
  p_parcela_id uuid,
  p_valor_receber numeric,
  p_novo_vencimento_date date default null,
  p_change_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = f, public, a
set row_security = off
as $$
declare
  v_parcela f.titulo_parcela%rowtype;
  v_titulo f.titulo%rowtype;
  v_user uuid;
  v_receber numeric(15,2);
  v_remanescente numeric(15,2);
  v_new_numero text;
  v_new_parcela_id uuid;
begin
  if p_parcela_id is null then
    raise exception 'p_parcela_id obrigatorio';
  end if;

  if p_valor_receber is null or p_valor_receber <= 0 then
    raise exception 'p_valor_receber deve ser > 0';
  end if;

  if auth.uid() is null then
    if current_user not in ('postgres', 'service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select p.*
    into v_parcela
  from f.titulo_parcela p
  where p.id = p_parcela_id
    and p.deleted_at is null
  for update;

  if not found then
    raise exception 'Parcela nao encontrada (id=%)', p_parcela_id;
  end if;

  select *
    into v_titulo
  from f.titulo
  where id = v_parcela.titulo_id
    and deleted_at is null;

  if not found then
    raise exception 'Titulo nao encontrado para parcela (id=%)', p_parcela_id;
  end if;

  if v_titulo.tipo <> 'AR' then
    raise exception 'Desdobramento permitido somente para AR';
  end if;

  if auth.uid() is not null then
    if not f.has_finance_access(v_titulo.tenant_id, v_titulo.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  if coalesce(v_parcela.valor_aberto, 0) <= 0 then
    raise exception 'Parcela sem saldo em aberto';
  end if;

  if round(coalesce(v_parcela.valor_aberto, 0), 2) <> round(coalesce(v_parcela.valor, 0), 2) then
    raise exception 'Desdobramento permitido apenas para parcela sem recebimentos anteriores';
  end if;

  v_receber := round(p_valor_receber, 2);
  if v_receber >= round(v_parcela.valor_aberto, 2) then
    raise exception 'Valor a receber deve ser menor que saldo aberto da parcela';
  end if;

  v_remanescente := round(v_parcela.valor_aberto - v_receber, 2);
  if v_remanescente <= 0 then
    raise exception 'Saldo remanescente invalido';
  end if;

  select lpad(
           (
             coalesce(
               max(
                 case
                   when regexp_replace(coalesce(numero, ''), '\D', '', 'g') <> ''
                     then regexp_replace(numero, '\D', '', 'g')::int
                   else null
                 end
               ),
               0
             ) + 1
           )::text,
           3,
           '0'
         )
    into v_new_numero
  from f.titulo_parcela
  where tenant_id = v_parcela.tenant_id
    and titulo_id = v_parcela.titulo_id
    and deleted_at is null;

  v_user := a.fn_current_usuario_id();

  update f.titulo_parcela
     set valor = v_receber,
         valor_aberto = v_receber,
         updated_at = now(),
         updated_by = v_user
   where id = v_parcela.id;

  insert into f.titulo_parcela (
    tenant_id,
    titulo_id,
    numero,
    vencimento_date,
    valor,
    valor_aberto,
    created_at,
    updated_at,
    created_by,
    updated_by
  )
  values (
    v_parcela.tenant_id,
    v_parcela.titulo_id,
    v_new_numero,
    coalesce(p_novo_vencimento_date, v_parcela.vencimento_date),
    v_remanescente,
    v_remanescente,
    now(),
    now(),
    v_user,
    v_user
  )
  returning id into v_new_parcela_id;

  return v_new_parcela_id;
end;
$$;
grant all on function f.desdobrar_parcela_ar_para_recebimento(uuid, numeric, date, text) to authenticated;
grant all on function f.desdobrar_parcela_ar_para_recebimento(uuid, numeric, date, text) to service_role;
