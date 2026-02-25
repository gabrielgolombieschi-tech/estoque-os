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

  if v_titulo.tipo <> 'AP' then
    raise exception 'Somente parcelas de AP podem ser alteradas nesta operacao';
  end if;

  if auth.uid() is not null then
    if not f.has_finance_access(v_titulo.tenant_id, v_titulo.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  if coalesce(v_parcela.valor_aberto, 0) <= 0 then
    raise exception 'Parcela ja liquidada; vencimento nao pode ser alterado';
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
