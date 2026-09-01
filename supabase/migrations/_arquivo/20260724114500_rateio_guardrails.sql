-- Protecoes permanentes para rateios financeiros.
--
-- Regras:
--   * o rateio deve pertencer ao mesmo tenant do titulo;
--   * plano, centro de custo e OS devem respeitar tenant/empresa;
--   * a mesma dimensao (plano + centro + OS) nao pode ser repetida;
--   * percentual agregado nao pode superar 100%;
--   * valor agregado nao pode superar o valor do titulo;
--   * quando percentual e valor forem informados, ambos devem reconciliar;
--   * validacao agregada e diferida para permitir edicoes multi-linha atomicas.

create or replace function f.trg_titulo_ap_auto_rateio_por_motivo()
returns trigger
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_titulo f.titulo%rowtype;
  v_plano uuid;
begin
  -- Como o trigger e diferido, NEW representa a fotografia do INSERT. Rele a
  -- linha para respeitar alteracoes, cancelamento ou exclusao feitos na mesma
  -- transacao.
  select t.*
    into v_titulo
  from f.titulo t
  where t.tenant_id = new.tenant_id
    and t.id = new.id
  for update;

  if not found
     or v_titulo.deleted_at is not null
     or v_titulo.status = 'CANCELADO'
     or coalesce(v_titulo.tipo, '') <> 'AP'
  then
    return new;
  end if;

  if exists (
    select 1
    from f.titulo_rateio tr
    where tr.tenant_id = v_titulo.tenant_id
      and tr.titulo_id = v_titulo.id
      and tr.deleted_at is null
  ) then
    return new;
  end if;

  if v_titulo.motivo_compra_id is not null then
    select mc.plano_contas_id
      into v_plano
    from f.motivo_compra mc
    join f.plano_contas pc
      on pc.tenant_id = v_titulo.tenant_id
     and pc.id = mc.plano_contas_id
     and pc.ativo
     and pc.deleted_at is null
    where mc.tenant_id = v_titulo.tenant_id
      and mc.id = v_titulo.motivo_compra_id
      and mc.deleted_at is null
    limit 1;
  end if;

  if v_plano is null then
    select pc.id
      into v_plano
    from f.plano_contas pc
    where pc.tenant_id = v_titulo.tenant_id
      and pc.codigo = 'DESP_GERAL'
      and pc.ativo
      and pc.deleted_at is null
    limit 1;
  end if;

  if v_plano is null then
    return new;
  end if;

  insert into f.titulo_rateio (
    tenant_id,
    titulo_id,
    plano_contas_id,
    percentual,
    valor
  )
  select
    v_titulo.tenant_id,
    v_titulo.id,
    v_plano,
    100.0000,
    coalesce(v_titulo.valor_total, 0)
  where not exists (
    select 1
    from f.titulo_rateio tr
    where tr.tenant_id = v_titulo.tenant_id
      and tr.titulo_id = v_titulo.id
      and tr.deleted_at is null
  );

  return new;
end;
$$;

create or replace function f.trg_titulo_rateio_preparar()
returns trigger
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_empresa_id uuid;
  v_valor_titulo numeric;
  v_titulo_status text;
  v_titulo_deleted_at timestamptz;
begin
  -- Serializa todas as escritas do mesmo titulo antes da validacao diferida.
  if tg_op = 'UPDATE'
     and (
       old.tenant_id is distinct from new.tenant_id
       or old.titulo_id is distinct from new.titulo_id
     )
  then
    perform 1
    from f.titulo t
    where t.tenant_id = old.tenant_id
      and t.id = old.titulo_id
    for update;
  end if;

  select t.empresa_id, t.valor_total, t.status, t.deleted_at
    into
      v_empresa_id,
      v_valor_titulo,
      v_titulo_status,
      v_titulo_deleted_at
  from f.titulo t
  where t.tenant_id = new.tenant_id
    and t.id = new.titulo_id
  for update;

  if not found then
    raise exception using
      errcode = '23503',
      message = format(
        'Rateio: titulo %s nao pertence ao tenant informado.',
        new.titulo_id
      );
  end if;

  if new.deleted_at is not null then
    return new;
  end if;

  if v_titulo_deleted_at is not null or v_titulo_status = 'CANCELADO' then
    raise exception using
      errcode = '23514',
      message = 'Rateio: nao e permitido criar ou reativar rateio em titulo excluido ou cancelado.';
  end if;

  if new.plano_contas_id is null then
    raise exception using
      errcode = '23514',
      message = 'Rateio: plano de contas e obrigatorio.';
  end if;

  if not exists (
    select 1
    from f.plano_contas pc
    where pc.tenant_id = new.tenant_id
      and pc.id = new.plano_contas_id
      and pc.ativo
      and pc.deleted_at is null
  ) then
    raise exception using
      errcode = '23503',
      message = 'Rateio: plano de contas invalido, inativo ou de outro tenant.';
  end if;

  if new.centro_custo_id is not null
     and not exists (
       select 1
       from f.centro_custo cc
       where cc.tenant_id = new.tenant_id
         and cc.empresa_id = v_empresa_id
         and cc.id = new.centro_custo_id
         and cc.ativo
         and cc.deleted_at is null
     )
  then
    raise exception using
      errcode = '23503',
      message = 'Rateio: centro de custo invalido ou de outra empresa.';
  end if;

  if new.os_id is not null
     and not exists (
       select 1
       from public.ordens_servico os
       where os.tenant_id = new.tenant_id
         and os.empresa_id = v_empresa_id
         and os.id = new.os_id
     )
  then
    raise exception using
      errcode = '23503',
      message = 'Rateio: ordem de servico invalida ou de outra empresa.';
  end if;

  if new.percentual is null and new.valor is null then
    raise exception using
      errcode = '23514',
      message = 'Rateio: informe percentual ou valor.';
  end if;

  if new.percentual is not null
     and new.valor is not null
     and abs(
       new.valor
       - round(coalesce(v_valor_titulo, 0) * new.percentual / 100.0, 2)
     ) > 0.01
  then
    raise exception using
      errcode = '23514',
      message = format(
        'Rateio: percentual %s%% equivale a %s, mas o valor informado e %s.',
        new.percentual,
        round(coalesce(v_valor_titulo, 0) * new.percentual / 100.0, 2),
        new.valor
      );
  end if;

  return new;
end;
$$;

create or replace function f.validar_consistencia_rateio_titulo(
  p_tenant_id uuid,
  p_titulo_id uuid
)
returns void
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_valor_titulo numeric;
  v_quantidade bigint;
  v_percentual numeric;
  v_valor numeric;
  v_duplicidades bigint;
begin
  if p_tenant_id is null or p_titulo_id is null then
    return;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'TITULO_RATEIO:' || p_tenant_id::text || ':' || p_titulo_id::text,
      0
    )
  );

  select t.valor_total
    into v_valor_titulo
  from f.titulo t
  where t.tenant_id = p_tenant_id
    and t.id = p_titulo_id
  for update;

  if not found then
    if exists (
      select 1
      from f.titulo_rateio tr
      where tr.tenant_id = p_tenant_id
        and tr.titulo_id = p_titulo_id
        and tr.deleted_at is null
    ) then
      raise exception using
        errcode = '23503',
        message = 'Rateio ativo sem titulo no mesmo tenant.';
    end if;
    return;
  end if;

  select
    count(*),
    coalesce(sum(tr.percentual), 0),
    coalesce(sum(coalesce(
      tr.valor,
      round(coalesce(v_valor_titulo, 0) * coalesce(tr.percentual, 0) / 100.0, 2),
      0
    )), 0),
    count(*)
      - count(distinct row(
          tr.plano_contas_id,
          tr.centro_custo_id,
          tr.os_id
        ))
    into
      v_quantidade,
      v_percentual,
      v_valor,
      v_duplicidades
  from f.titulo_rateio tr
  where tr.tenant_id = p_tenant_id
    and tr.titulo_id = p_titulo_id
    and tr.deleted_at is null;

  if v_quantidade = 0 then
    return;
  end if;

  if v_duplicidades > 0 then
    raise exception using
      errcode = '23505',
      message = 'Rateio: plano, centro de custo e OS repetidos no mesmo titulo.';
  end if;

  if v_percentual > 100.0001 then
    raise exception using
      errcode = '23514',
      message = format(
        'Rateio: soma percentual de %s%% excede 100%%.',
        round(v_percentual, 4)
      );
  end if;

  if v_valor > coalesce(v_valor_titulo, 0) + 0.01 then
    raise exception using
      errcode = '23514',
      message = format(
        'Rateio: soma de %s excede o valor do titulo (%s).',
        round(v_valor, 2),
        round(coalesce(v_valor_titulo, 0), 2)
      );
  end if;
end;
$$;

create or replace function f.trg_titulo_rateio_validar()
returns trigger
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform f.validar_consistencia_rateio_titulo(
      old.tenant_id,
      old.titulo_id
    );
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    if tg_op = 'INSERT'
       or new.tenant_id is distinct from old.tenant_id
       or new.titulo_id is distinct from old.titulo_id
       or new.deleted_at is distinct from old.deleted_at
       or new.plano_contas_id is distinct from old.plano_contas_id
       or new.centro_custo_id is distinct from old.centro_custo_id
       or new.os_id is distinct from old.os_id
       or new.percentual is distinct from old.percentual
       or new.valor is distinct from old.valor
    then
      perform f.validar_consistencia_rateio_titulo(
        new.tenant_id,
        new.titulo_id
      );
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_titulo_rateio_preparar on f.titulo_rateio;

create trigger trg_titulo_rateio_preparar
before insert or update on f.titulo_rateio
for each row
execute function f.trg_titulo_rateio_preparar();

drop trigger if exists ct_titulo_rateio_consistencia on f.titulo_rateio;

create constraint trigger ct_titulo_rateio_consistencia
after insert or update or delete on f.titulo_rateio
deferrable initially deferred
for each row
execute function f.trg_titulo_rateio_validar();

comment on trigger ct_titulo_rateio_consistencia on f.titulo_rateio is
  'Valida no commit duplicidade, soma percentual e soma em valor por titulo.';

revoke all on function f.trg_titulo_rateio_preparar() from public;
revoke all on function f.validar_consistencia_rateio_titulo(uuid, uuid) from public;
revoke all on function f.trg_titulo_rateio_validar() from public;

-- A RLS anterior limitava somente o tenant. O vinculo ao titulo passa a
-- garantir tambem a empresa ativa.
drop policy if exists titulo_rateio_all on f.titulo_rateio;

create policy titulo_rateio_all
on f.titulo_rateio
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and f.has_finance_access()
  and exists (
    select 1
    from f.titulo t
    where t.id = titulo_rateio.titulo_id
      and t.tenant_id = titulo_rateio.tenant_id
      and t.empresa_id = public.current_empresa_id()
      and t.deleted_at is null
  )
)
with check (
  tenant_id = public.current_tenant_id()
  and f.has_finance_access()
  and exists (
    select 1
    from f.titulo t
    where t.id = titulo_rateio.titulo_id
      and t.tenant_id = titulo_rateio.tenant_id
      and t.empresa_id = public.current_empresa_id()
      and t.deleted_at is null
  )
);

-- Rotinas de faturamento: um unico rateio automatico continua sendo atualizado
-- para 100%. Se houver uma divisao legitima, preserva percentuais e dimensoes e
-- recalcula somente os valores proporcionais.
do $$
declare
  v_definition text;
  v_patched text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(
    'f.fn_upsert_ar_from_documento_fiscal_v2(uuid,numeric)'::regprocedure
  )
  into v_definition;

  v_old := $old_documento$
    update f.titulo_rateio
    set
      plano_contas_id = v_plano_contas_id,
      os_id = v_df.os_id_import,
      percentual = 100.0000,
      valor = v_valor
    where titulo_id = v_titulo_id
      and tenant_id = v_df.tenant_id
      and deleted_at is null;

    get diagnostics v_rateio_count = row_count;

    if coalesce(v_rateio_count, 0) = 0 then
      insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, os_id, percentual, valor)
      values (v_df.tenant_id, v_titulo_id, v_plano_contas_id, v_df.os_id_import, 100.0000, v_valor);
    end if;$old_documento$;

  v_new := $new_documento$
    select count(*)
      into v_rateio_count
    from f.titulo_rateio
    where titulo_id = v_titulo_id
      and tenant_id = v_df.tenant_id
      and deleted_at is null;

    if coalesce(v_rateio_count, 0) = 0 then
      insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, os_id, percentual, valor)
      values (v_df.tenant_id, v_titulo_id, v_plano_contas_id, v_df.os_id_import, 100.0000, v_valor);
    elsif v_rateio_count = 1 then
      update f.titulo_rateio
      set
        plano_contas_id = v_plano_contas_id,
        os_id = v_df.os_id_import,
        percentual = 100.0000,
        valor = v_valor
      where titulo_id = v_titulo_id
        and tenant_id = v_df.tenant_id
        and deleted_at is null;
    else
      update f.titulo_rateio
      set valor = case
        when percentual is not null
          then round(v_valor * percentual / 100.0, 2)
        when valor is not null
             and coalesce(p_old_valor_total, 0) > 0
          then round(v_valor * valor / p_old_valor_total, 2)
        else valor
      end
      where titulo_id = v_titulo_id
        and tenant_id = v_df.tenant_id
        and deleted_at is null;
    end if;$new_documento$;

  v_patched := replace(v_definition, v_old, v_new);
  if v_patched = v_definition then
    raise exception
      'Rateios: bloco esperado nao encontrado em fn_upsert_ar_from_documento_fiscal_v2.';
  end if;
  execute v_patched;

  select pg_get_functiondef(
    'f.fn_upsert_ar_from_nfe_venda(uuid,numeric)'::regprocedure
  )
  into v_definition;

  v_old := $old_nfe$
    update f.titulo_rateio
    set
      percentual = 100.0000,
      valor = v_valor,
      plano_contas_id = v_plano_contas_id,
      os_id = v_df.os_id_import
    where titulo_id = v_titulo_id
      and tenant_id = v_df.tenant_id
      and deleted_at is null;

    get diagnostics v_rateio_count = row_count;

    if coalesce(v_rateio_count, 0) = 0 then
      insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, os_id, percentual, valor)
      values (v_df.tenant_id, v_titulo_id, v_plano_contas_id, v_df.os_id_import, 100.0000, v_valor);
    end if;$old_nfe$;

  v_new := $new_nfe$
    select count(*)
      into v_rateio_count
    from f.titulo_rateio
    where titulo_id = v_titulo_id
      and tenant_id = v_df.tenant_id
      and deleted_at is null;

    if coalesce(v_rateio_count, 0) = 0 then
      insert into f.titulo_rateio (tenant_id, titulo_id, plano_contas_id, os_id, percentual, valor)
      values (v_df.tenant_id, v_titulo_id, v_plano_contas_id, v_df.os_id_import, 100.0000, v_valor);
    elsif v_rateio_count = 1 then
      update f.titulo_rateio
      set
        percentual = 100.0000,
        valor = v_valor,
        plano_contas_id = v_plano_contas_id,
        os_id = v_df.os_id_import
      where titulo_id = v_titulo_id
        and tenant_id = v_df.tenant_id
        and deleted_at is null;
    else
      update f.titulo_rateio
      set valor = case
        when percentual is not null
          then round(v_valor * percentual / 100.0, 2)
        when valor is not null
             and coalesce(p_old_valor_total, 0) > 0
          then round(v_valor * valor / p_old_valor_total, 2)
        else valor
      end
      where titulo_id = v_titulo_id
        and tenant_id = v_df.tenant_id
        and deleted_at is null;
    end if;$new_nfe$;

  v_patched := replace(v_definition, v_old, v_new);
  if v_patched = v_definition then
    raise exception
      'Rateios: bloco esperado nao encontrado em fn_upsert_ar_from_nfe_venda.';
  end if;
  execute v_patched;
end;
$$;

-- O alerta passa a validar a soma percentual mesmo quando os rateios possuem
-- tambem o campo valor preenchido.
do $$
declare
  v_definition text;
  v_patched text;
  v_old text := $old_alerta$
        or (
          rs.quantidade_valor = 0
          and rs.quantidade_percentual = rs.quantidade
          and abs(rs.percentual - 100) > 0.0001
        )$old_alerta$;
  v_new text := $new_alerta$
        or (
          rs.quantidade_percentual = rs.quantidade
          and abs(rs.percentual - 100) > 0.0001
        )$new_alerta$;
begin
  select pg_get_functiondef(
    'f.relatorio_saude_financeira(uuid,uuid,date,date)'::regprocedure
  )
  into v_definition;

  v_patched := replace(v_definition, v_old, v_new);
  if v_patched = v_definition then
    raise exception
      'Rateios: regra esperada do alerta RATEIO_DIVERGENTE nao foi encontrada.';
  end if;

  execute v_patched;
end;
$$;
