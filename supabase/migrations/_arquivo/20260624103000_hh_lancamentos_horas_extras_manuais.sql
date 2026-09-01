alter table public.hh_lancamentos
  add column if not exists tem_extra_50 boolean not null default false,
  add column if not exists horas_extra_50 numeric(10,2) not null default 0,
  add column if not exists tem_extra_100 boolean not null default false,
  add column if not exists horas_extra_100 numeric(10,2) not null default 0;

comment on column public.hh_lancamentos.tem_extra_50 is
  'Indica que o lancamento possui horas extras 50% informadas manualmente.';
comment on column public.hh_lancamentos.horas_extra_50 is
  'Quantidade de horas extras 50% informada manualmente no lancamento HH.';
comment on column public.hh_lancamentos.tem_extra_100 is
  'Indica que o lancamento possui horas extras 100% informadas manualmente.';
comment on column public.hh_lancamentos.horas_extra_100 is
  'Quantidade de horas extras 100% informada manualmente no lancamento HH.';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'hh_lancamentos_horas_extra_50_ck'
      and conrelid = 'public.hh_lancamentos'::regclass
  ) then
    alter table public.hh_lancamentos
      add constraint hh_lancamentos_horas_extra_50_ck
      check (horas_extra_50 >= 0 and horas_extra_50 <= 24);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'hh_lancamentos_horas_extra_100_ck'
      and conrelid = 'public.hh_lancamentos'::regclass
  ) then
    alter table public.hh_lancamentos
      add constraint hh_lancamentos_horas_extra_100_ck
      check (horas_extra_100 >= 0 and horas_extra_100 <= 24);
  end if;
end $$;

create or replace function public.calculate_hh_lancamento()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_preco_base numeric(10,2);
  v_preco_50 numeric(10,2);
  v_preco_100 numeric(10,2);
  v_total_horas numeric(10,2);
  v_horas_normais numeric(10,2);
  v_horas_extra_50 numeric(10,2);
  v_horas_extra_100 numeric(10,2);
  v_tem_extra_manual boolean;
begin
  if NEW.entrada_1 is not null
    or NEW.saida_1 is not null
    or NEW.entrada_2 is not null
    or NEW.saida_2 is not null
  then
    if NEW.entrada_1 is null
      or NEW.saida_1 is null
      or NEW.entrada_2 is null
      or NEW.saida_2 is null
    then
      raise exception 'Preencha Entrada 1, Saida 1, Entrada 2 e Saida 2 ou deixe todos em branco.';
    end if;

    if NEW.saida_1 <= NEW.entrada_1 then
      raise exception 'Saida 1 deve ser maior que Entrada 1.';
    end if;

    if NEW.saida_2 <= NEW.entrada_2 then
      raise exception 'Saida 2 deve ser maior que Entrada 2.';
    end if;

    if NEW.saida_1 > NEW.entrada_2 then
      raise exception 'Saida 1 deve ser menor ou igual a Entrada 2.';
    end if;

    v_total_horas :=
      (extract(epoch from (NEW.saida_1 - NEW.entrada_1)) / 3600.0)
      + (extract(epoch from (NEW.saida_2 - NEW.entrada_2)) / 3600.0);

    NEW.hora_entrada := NEW.entrada_1;
    NEW.hora_saida := NEW.saida_2;
  else
    if NEW.hora_entrada is null or NEW.hora_saida is null then
      raise exception 'Preencha os horarios do lancamento HH.';
    end if;

    v_total_horas := extract(epoch from (NEW.hora_saida - NEW.hora_entrada)) / 3600.0;
    if v_total_horas < 0 then
      v_total_horas := v_total_horas + 24;
    end if;
  end if;

  v_total_horas := round(coalesce(v_total_horas, 0), 2);
  if v_total_horas <= 0 then
    raise exception 'Total de horas do lancamento HH deve ser maior que zero.';
  end if;

  NEW.horas_trabalhadas := v_total_horas;

  NEW.tem_extra_50 := coalesce(NEW.tem_extra_50, false) or coalesce(NEW.horas_extra_50, 0) > 0;
  NEW.tem_extra_100 := coalesce(NEW.tem_extra_100, false) or coalesce(NEW.horas_extra_100, 0) > 0;
  NEW.horas_extra_50 := case when NEW.tem_extra_50 then round(coalesce(NEW.horas_extra_50, 0), 2) else 0 end;
  NEW.horas_extra_100 := case when NEW.tem_extra_100 then round(coalesce(NEW.horas_extra_100, 0), 2) else 0 end;

  if NEW.horas_extra_50 < 0 or NEW.horas_extra_100 < 0 then
    raise exception 'Horas extras nao podem ser negativas.';
  end if;

  if NEW.horas_extra_50 + NEW.horas_extra_100 > v_total_horas then
    raise exception 'Horas extras nao podem exceder o total de horas do lancamento.';
  end if;

  select s.preco_base, s.preco_50, s.preco_100
    into v_preco_base, v_preco_50, v_preco_100
  from public.cliente_hh_servicos s
  where s.id = NEW.hh_servico_id
    and s.tenant_id = NEW.tenant_id
    and s.empresa_id = NEW.empresa_id
    and s.ativo = true
  limit 1;

  v_preco_base := coalesce(v_preco_base, nullif(NEW.valor_hora, 0), 0);
  v_preco_50 := coalesce(v_preco_50, round(v_preco_base * 1.5, 2));
  v_preco_100 := coalesce(v_preco_100, round(v_preco_base * 2.0, 2));

  v_tem_extra_manual := NEW.tem_extra_50 or NEW.tem_extra_100;

  if v_tem_extra_manual then
    v_horas_extra_50 := NEW.horas_extra_50;
    v_horas_extra_100 := NEW.horas_extra_100;
    v_horas_normais := v_total_horas - v_horas_extra_50 - v_horas_extra_100;
  else
    v_horas_extra_50 := case when NEW.percentual_aplicado = 50 then v_total_horas else 0 end;
    v_horas_extra_100 := case when NEW.percentual_aplicado = 100 then v_total_horas else 0 end;
    v_horas_normais := case when NEW.percentual_aplicado in (50, 100) then 0 else v_total_horas end;
  end if;

  NEW.valor_hora := round(v_preco_base, 2);
  NEW.valor_total := round(
    coalesce(v_horas_normais, 0) * coalesce(v_preco_base, 0)
    + coalesce(v_horas_extra_50, 0) * coalesce(v_preco_50, 0)
    + coalesce(v_horas_extra_100, 0) * coalesce(v_preco_100, 0),
    2
  );

  return NEW;
end;
$$;

create or replace function public.fn_hh_sync_apontamento()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_tipo_normal uuid;
  v_tipo_extra_50 uuid;
  v_tipo_extra_100 uuid;
  v_total_horas numeric(10,2);
  v_horas_normais numeric(10,2);
  v_horas_extra_50 numeric(10,2);
  v_horas_extra_100 numeric(10,2);
  v_tem_extra_manual boolean;
begin
  v_total_horas := round(coalesce(NEW.horas_trabalhadas, 0), 2);
  v_tem_extra_manual :=
    coalesce(NEW.tem_extra_50, false)
    or coalesce(NEW.tem_extra_100, false)
    or coalesce(NEW.horas_extra_50, 0) > 0
    or coalesce(NEW.horas_extra_100, 0) > 0;

  if v_tem_extra_manual then
    v_horas_extra_50 := round(coalesce(NEW.horas_extra_50, 0), 2);
    v_horas_extra_100 := round(coalesce(NEW.horas_extra_100, 0), 2);
    v_horas_normais := greatest(round(v_total_horas - v_horas_extra_50 - v_horas_extra_100, 2), 0);
  else
    v_horas_extra_50 := case when NEW.percentual_aplicado = 50 then v_total_horas else 0 end;
    v_horas_extra_100 := case when NEW.percentual_aplicado = 100 then v_total_horas else 0 end;
    v_horas_normais := case when NEW.percentual_aplicado in (50, 100) then 0 else v_total_horas end;
  end if;

  select id into v_tipo_normal
  from public.tipos_horas
  where tenant_id = NEW.tenant_id and codigo = 'NORMAL' and ativo = true
  limit 1;

  select id into v_tipo_extra_50
  from public.tipos_horas
  where tenant_id = NEW.tenant_id and codigo = 'EXTRA_50' and ativo = true
  limit 1;

  select id into v_tipo_extra_100
  from public.tipos_horas
  where tenant_id = NEW.tenant_id and codigo = 'EXTRA_100' and ativo = true
  limit 1;

  delete from public.apontamentos_horas
  where hh_lancamento_id = NEW.id;

  if v_horas_normais > 0 then
    insert into public.apontamentos_horas (
      tenant_id, empresa_id, os_id, colaborador_id, data, horas,
      tipo_hora_id, gerado_por_hh, hh_lancamento_id, status, descricao
    ) values (
      NEW.tenant_id, NEW.empresa_id, NEW.os_id, NEW.colaborador_id, NEW.data, v_horas_normais,
      v_tipo_normal, true, NEW.id, 'lancado', NEW.observacao
    );
  end if;

  if v_horas_extra_50 > 0 then
    insert into public.apontamentos_horas (
      tenant_id, empresa_id, os_id, colaborador_id, data, horas,
      tipo_hora_id, gerado_por_hh, hh_lancamento_id, status, descricao
    ) values (
      NEW.tenant_id, NEW.empresa_id, NEW.os_id, NEW.colaborador_id, NEW.data, v_horas_extra_50,
      v_tipo_extra_50, true, NEW.id, 'lancado', NEW.observacao
    );
  end if;

  if v_horas_extra_100 > 0 then
    insert into public.apontamentos_horas (
      tenant_id, empresa_id, os_id, colaborador_id, data, horas,
      tipo_hora_id, gerado_por_hh, hh_lancamento_id, status, descricao
    ) values (
      NEW.tenant_id, NEW.empresa_id, NEW.os_id, NEW.colaborador_id, NEW.data, v_horas_extra_100,
      v_tipo_extra_100, true, NEW.id, 'lancado', NEW.observacao
    );
  end if;

  return NEW;
end;
$$;
