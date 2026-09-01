create or replace function public.fn_hh_sync_apontamento_key(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_os_id integer,
  p_colaborador_id uuid,
  p_data date,
  p_hh_lancamento_id bigint default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_apontamento_id uuid;
  v_tipo_normal uuid;
  v_total_horas numeric(10,2);
  v_horas_normais numeric(10,2);
  v_horas_extra_50 numeric(10,2);
  v_horas_extra_100 numeric(10,2);
  v_fator_aplicado numeric(6,3);
  v_descricao text;
begin
  select
    round(coalesce(sum(coalesce(hl.horas_trabalhadas, 0)), 0), 2),
    round(coalesce(sum(
      case
        when coalesce(hl.tem_extra_50, false)
          or coalesce(hl.tem_extra_100, false)
          or coalesce(hl.horas_extra_50, 0) > 0
          or coalesce(hl.horas_extra_100, 0) > 0
        then greatest(
          coalesce(hl.horas_trabalhadas, 0)
          - coalesce(hl.horas_extra_50, 0)
          - coalesce(hl.horas_extra_100, 0),
          0
        )
        when hl.percentual_aplicado in (50, 100) then 0
        else coalesce(hl.horas_trabalhadas, 0)
      end
    ), 0), 2),
    round(coalesce(sum(
      case
        when coalesce(hl.tem_extra_50, false)
          or coalesce(hl.horas_extra_50, 0) > 0
        then coalesce(hl.horas_extra_50, 0)
        when hl.percentual_aplicado = 50 then coalesce(hl.horas_trabalhadas, 0)
        else 0
      end
    ), 0), 2),
    round(coalesce(sum(
      case
        when coalesce(hl.tem_extra_100, false)
          or coalesce(hl.horas_extra_100, 0) > 0
        then coalesce(hl.horas_extra_100, 0)
        when hl.percentual_aplicado = 100 then coalesce(hl.horas_trabalhadas, 0)
        else 0
      end
    ), 0), 2),
    string_agg(nullif(trim(coalesce(hl.observacao, '')), ''), ' | ' order by hl.criado_em, hl.id)
  into
    v_total_horas,
    v_horas_normais,
    v_horas_extra_50,
    v_horas_extra_100,
    v_descricao
  from public.hh_lancamentos hl
  where hl.tenant_id = p_tenant_id
    and hl.empresa_id = p_empresa_id
    and hl.os_id = p_os_id
    and hl.colaborador_id = p_colaborador_id
    and hl.data = p_data;

  if coalesce(v_total_horas, 0) <= 0 then
    delete from public.apontamentos_horas ah
    where ah.tenant_id = p_tenant_id
      and ah.empresa_id = p_empresa_id
      and ah.os_id = p_os_id
      and ah.colaborador_id = p_colaborador_id
      and ah.data = p_data
      and (
        coalesce(ah.gerado_por_hh, false) = true
        or ah.hh_lancamento_id = p_hh_lancamento_id
      );
    return;
  end if;

  v_fator_aplicado := round(
    (
      coalesce(v_horas_normais, 0)
      + coalesce(v_horas_extra_50, 0) * 1.5
      + coalesce(v_horas_extra_100, 0) * 2
    ) / nullif(v_total_horas, 0),
    3
  );

  select th.id
    into v_tipo_normal
  from public.tipos_horas th
  where th.tenant_id = p_tenant_id
    and th.codigo = 'NORMAL'
    and th.ativo = true
  limit 1;

  select ah.id
    into v_apontamento_id
  from public.apontamentos_horas ah
  where ah.tenant_id = p_tenant_id
    and ah.empresa_id = p_empresa_id
    and ah.os_id = p_os_id
    and ah.colaborador_id = p_colaborador_id
    and ah.data = p_data
  order by
    coalesce(ah.gerado_por_hh, false) desc,
    (ah.hh_lancamento_id is not null) desc,
    ah.criado_em desc
  limit 1;

  if v_apontamento_id is null then
    begin
      insert into public.apontamentos_horas (
        tenant_id,
        empresa_id,
        os_id,
        colaborador_id,
        data,
        horas,
        tipo_hora_id,
        fator_aplicado,
        gerado_por_hh,
        hh_lancamento_id,
        status,
        descricao,
        hora_entrada_1,
        hora_saida_1,
        hora_entrada_2,
        hora_saida_2
      ) values (
        p_tenant_id,
        p_empresa_id,
        p_os_id,
        p_colaborador_id,
        p_data,
        v_total_horas,
        v_tipo_normal,
        coalesce(v_fator_aplicado, 1),
        true,
        p_hh_lancamento_id,
        'lancado',
        coalesce(nullif(v_descricao, ''), 'HH lancado na OS'),
        null,
        null,
        null,
        null
      )
      returning id into v_apontamento_id;
    exception when unique_violation then
      select ah.id
        into v_apontamento_id
      from public.apontamentos_horas ah
      where ah.tenant_id = p_tenant_id
        and ah.empresa_id = p_empresa_id
        and ah.os_id = p_os_id
        and ah.colaborador_id = p_colaborador_id
        and ah.data = p_data
      order by
        coalesce(ah.gerado_por_hh, false) desc,
        (ah.hh_lancamento_id is not null) desc,
        ah.criado_em desc
      limit 1;

      if v_apontamento_id is null then
        raise;
      end if;
    end;
  end if;

  update public.apontamentos_horas
  set
    horas = v_total_horas,
    tipo_hora_id = coalesce(tipo_hora_id, v_tipo_normal),
    gerado_por_hh = true,
    hh_lancamento_id = coalesce(hh_lancamento_id, p_hh_lancamento_id),
    status = 'lancado',
    descricao = coalesce(nullif(v_descricao, ''), descricao, 'HH lancado na OS'),
    hora_entrada_1 = null,
    hora_saida_1 = null,
    hora_entrada_2 = null,
    hora_saida_2 = null
  where id = v_apontamento_id;

  update public.apontamentos_horas
  set fator_aplicado = coalesce(v_fator_aplicado, 1)
  where id = v_apontamento_id;

  delete from public.apontamentos_horas ah
  where ah.tenant_id = p_tenant_id
    and ah.empresa_id = p_empresa_id
    and ah.os_id = p_os_id
    and ah.colaborador_id = p_colaborador_id
    and ah.data = p_data
    and ah.id <> v_apontamento_id
    and coalesce(ah.gerado_por_hh, false) = true;
end;
$$;

create or replace function public.fn_hh_criar_apontamento()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  perform public.fn_hh_sync_apontamento_key(
    new.tenant_id,
    new.empresa_id,
    new.os_id,
    new.colaborador_id,
    new.data,
    new.id
  );

  return new;
end;
$$;

create or replace function public.fn_hh_sync_apontamento()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  perform public.fn_hh_sync_apontamento_key(
    new.tenant_id,
    new.empresa_id,
    new.os_id,
    new.colaborador_id,
    new.data,
    new.id
  );

  return new;
end;
$$;

create or replace function public.fn_hh_delete_apontamento()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  perform public.fn_hh_sync_apontamento_key(
    old.tenant_id,
    old.empresa_id,
    old.os_id,
    old.colaborador_id,
    old.data,
    old.id
  );

  return old;
end;
$$;

drop trigger if exists trg_hh_criar_apontamento on public.hh_lancamentos;

drop trigger if exists trg_hh_sync_apontamento on public.hh_lancamentos;
create trigger trg_hh_sync_apontamento
after insert or update on public.hh_lancamentos
for each row execute function public.fn_hh_sync_apontamento();

drop trigger if exists trg_hh_delete_apontamento on public.hh_lancamentos;
create trigger trg_hh_delete_apontamento
after delete on public.hh_lancamentos
for each row execute function public.fn_hh_delete_apontamento();
