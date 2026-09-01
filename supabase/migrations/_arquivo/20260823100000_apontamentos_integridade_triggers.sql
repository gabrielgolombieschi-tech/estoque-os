begin;

create or replace function public.fn_apontamento_bloquear_duplicidade()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_horas_existentes numeric;
begin
  -- Scripts e manutenção com service role não entram nesta proteção.
  if auth.uid() is null or coalesce(new.gerado_por_hh, false) then
    return new;
  end if;

  select ah.horas
    into v_horas_existentes
  from public.apontamentos_horas ah
  where ah.os_id = new.os_id
    and ah.colaborador_id = new.colaborador_id
    and ah.data = new.data
    and ah.tipo_hora_id = new.tipo_hora_id
    and ah.gerado_por_hh = false
  order by ah.criado_em asc
  limit 1;

  if found then
    raise exception using
      errcode = '23505',
      message = format(
        'Já existe um apontamento normal de %s hora(s) em %s para esta OS, colaborador e tipo de hora. Para corrigir, edite o lançamento existente.',
        replace(v_horas_existentes::text, '.', ','),
        to_char(new.data, 'DD/MM/YYYY')
      );
  end if;

  return new;
end;
$$;

create or replace function public.fn_apontamento_bloquear_fechado()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- Espelhos HH permanecem mutáveis pelo sync/CASCADE; manutenção também passa.
  if auth.uid() is null or coalesce(old.gerado_por_hh, false) then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if old.status = 'fechado' then
    raise exception using
      errcode = '55000',
      message = 'Este apontamento está fechado e não pode ser alterado ou excluído.';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.fn_apontamento_validar_aprovacao()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_executor uuid := auth.uid();
  v_user_id_colaborador uuid;
begin
  -- Scripts e manutenção podem aprovar sem carimbo automático de usuário.
  if v_executor is null then
    return new;
  end if;

  if new.status = 'aprovado' then
    select c.user_id
      into v_user_id_colaborador
    from public.colaboradores c
    where c.id = new.colaborador_id;

    if v_user_id_colaborador is not null and v_user_id_colaborador = v_executor then
      raise exception using
        errcode = '42501',
        message = 'Autoaprovação não é permitida: o colaborador não pode aprovar o próprio apontamento.';
    end if;

    if tg_op = 'INSERT' or old.status is distinct from new.status then
      new.aprovado_por := v_executor;
      new.aprovado_em := now();
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_apontamento_bloquear_duplicidade on public.apontamentos_horas;
create trigger trg_apontamento_bloquear_duplicidade
before insert on public.apontamentos_horas
for each row execute function public.fn_apontamento_bloquear_duplicidade();

drop trigger if exists trg_apontamento_bloquear_fechado_update on public.apontamentos_horas;
create trigger trg_apontamento_bloquear_fechado_update
before update on public.apontamentos_horas
for each row execute function public.fn_apontamento_bloquear_fechado();

drop trigger if exists trg_apontamento_bloquear_fechado_delete on public.apontamentos_horas;
create trigger trg_apontamento_bloquear_fechado_delete
before delete on public.apontamentos_horas
for each row execute function public.fn_apontamento_bloquear_fechado();

drop trigger if exists trg_apontamento_validar_aprovacao on public.apontamentos_horas;
create trigger trg_apontamento_validar_aprovacao
before insert or update on public.apontamentos_horas
for each row execute function public.fn_apontamento_validar_aprovacao();

commit;
