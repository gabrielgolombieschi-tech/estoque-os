-- Completa os guardrails validando tambem mudancas no valor do titulo.
-- Inclui um smoke test transacional: tenta gravar 101%, confirma a rejeicao e
-- reverte integralmente a tentativa dentro de uma subtransacao.

create or replace function f.trg_titulo_validar_rateio()
returns trigger
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
begin
  if tg_op = 'UPDATE'
     and (
       new.tenant_id is distinct from old.tenant_id
       or new.id is distinct from old.id
       or new.valor_total is distinct from old.valor_total
       or new.deleted_at is distinct from old.deleted_at
     )
  then
    perform f.validar_consistencia_rateio_titulo(
      old.tenant_id,
      old.id
    );

    if new.tenant_id is distinct from old.tenant_id
       or new.id is distinct from old.id
    then
      perform f.validar_consistencia_rateio_titulo(
        new.tenant_id,
        new.id
      );
    end if;
  elsif tg_op = 'DELETE' then
    perform f.validar_consistencia_rateio_titulo(
      old.tenant_id,
      old.id
    );
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists ct_titulo_valida_rateio on f.titulo;

create constraint trigger ct_titulo_valida_rateio
after update or delete on f.titulo
deferrable initially deferred
for each row
execute function f.trg_titulo_validar_rateio();

revoke all on function f.trg_titulo_validar_rateio() from public;

do $$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_titulo_id uuid;
  v_valor_titulo numeric;
  v_plano_alternativo uuid;
  v_count_before bigint;
  v_count_after bigint;
  v_rejeitado boolean := false;
  v_message text;
begin
  select t.id, t.valor_total
    into v_titulo_id, v_valor_titulo
  from f.titulo t
  where t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id
    and t.deleted_at is null
    and t.status <> 'CANCELADO'
    and t.valor_total > 1
    and t.id <> '3f2a356b-1081-4c43-8b9a-fa752ab735d5'::uuid
    and (
      select count(*)
      from f.titulo_rateio tr
      where tr.tenant_id = v_tenant_id
        and tr.titulo_id = t.id
        and tr.deleted_at is null
    ) = 1
  order by t.id
  limit 1;

  if v_titulo_id is null then
    raise exception 'Rateios: titulo consistente nao encontrado para smoke test.';
  end if;

  select pc.id
    into v_plano_alternativo
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.ativo
    and pc.deleted_at is null
    and not exists (
      select 1
      from f.titulo_rateio tr
      where tr.tenant_id = v_tenant_id
        and tr.titulo_id = v_titulo_id
        and tr.plano_contas_id = pc.id
        and tr.centro_custo_id is null
        and tr.os_id is null
        and tr.deleted_at is null
    )
  order by pc.id
  limit 1;

  if v_plano_alternativo is null then
    raise exception 'Rateios: plano alternativo nao encontrado para smoke test.';
  end if;

  select count(*)
    into v_count_before
  from f.titulo_rateio tr
  where tr.tenant_id = v_tenant_id
    and tr.titulo_id = v_titulo_id
    and tr.deleted_at is null;

  begin
    insert into f.titulo_rateio (
      tenant_id,
      titulo_id,
      plano_contas_id,
      percentual,
      valor
    ) values (
      v_tenant_id,
      v_titulo_id,
      v_plano_alternativo,
      1.0000,
      round(v_valor_titulo * 0.01, 2)
    );

    set constraints all immediate;
  exception
    when check_violation then
      get stacked diagnostics v_message = message_text;
      if v_message not like 'Rateio: soma percentual%' then
        raise;
      end if;
      v_rejeitado := true;
  end;

  if not v_rejeitado then
    raise exception
      'Rateios: guardrail nao rejeitou a tentativa transacional de 101%%.';
  end if;

  select count(*)
    into v_count_after
  from f.titulo_rateio tr
  where tr.tenant_id = v_tenant_id
    and tr.titulo_id = v_titulo_id
    and tr.deleted_at is null;

  if v_count_after <> v_count_before then
    raise exception
      'Rateios: smoke test deixou alteracao persistente (% antes, % depois).',
      v_count_before,
      v_count_after;
  end if;
end;
$$;
