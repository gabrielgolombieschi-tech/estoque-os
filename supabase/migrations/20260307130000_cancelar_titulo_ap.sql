begin;

create or replace function f.cancelar_titulo_ap(
  p_titulo_id uuid,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_titulo f.titulo%rowtype;
  v_user uuid;
  v_tem_pagamento boolean;
begin
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select *
    into v_titulo
    from f.titulo
   where id = p_titulo_id
     and deleted_at is null;

  if not found then
    raise exception 'Titulo nao encontrado (id=%)', p_titulo_id;
  end if;

  if v_titulo.tipo <> 'AP' then
    raise exception 'Cancelamento so permite titulo AP. Tipo atual=%', v_titulo.tipo;
  end if;

  if upper(coalesce(v_titulo.status, '')) = 'CANCELADO' then
    raise exception 'Titulo ja esta cancelado';
  end if;

  if auth.uid() is not null then
    if not f.has_finance_access(v_titulo.tenant_id, v_titulo.empresa_id) then
      raise exception 'Sem permissao: somente ADMIN/FINANCEIRO';
    end if;
  end if;

  v_user := a.fn_current_usuario_id();

  if v_user is null then
    select ut.usuario_id
      into v_user
      from a.usuario_tenant ut
     where ut.tenant_id = v_titulo.tenant_id
       and ut.ativo = true
       and ut.deleted_at is null
       and ut.papel in ('OWNER','ADMIN')
     order by ut.created_at nulls last
     limit 1;

    if v_user is null then
      raise exception 'Nao foi possivel determinar usuario executor. Execute pelo app.';
    end if;
  end if;

  select exists (
    select 1
      from f.titulo_parcela tp
      join f.pagamento_item pi
        on pi.titulo_parcela_id = tp.id
       and pi.deleted_at is null
      join f.pagamento p
        on p.id = pi.pagamento_id
       and p.deleted_at is null
     where tp.tenant_id = v_titulo.tenant_id
       and tp.titulo_id = v_titulo.id
       and tp.deleted_at is null
  )
    into v_tem_pagamento;

  if v_tem_pagamento then
    raise exception 'Titulo possui pagamento aplicado. Estorne o pagamento antes de cancelar o lancamento.';
  end if;

  update f.titulo_agendamento
     set deleted_at = now(),
         updated_at = now(),
         updated_by = v_user
   where tenant_id = v_titulo.tenant_id
     and titulo_id = v_titulo.id
     and deleted_at is null;

  update f.titulo_parcela
     set valor_aberto = 0,
         updated_at = now(),
         updated_by = v_user
   where tenant_id = v_titulo.tenant_id
     and titulo_id = v_titulo.id
     and deleted_at is null
     and coalesce(valor_aberto, 0) <> 0;

  update f.titulo
     set valor_aberto = 0,
         status = 'CANCELADO',
         updated_at = now(),
         updated_by = v_user
   where id = v_titulo.id;

  insert into f.evento_financeiro (
    tenant_id, empresa_id,
    evento, ref_table, ref_id,
    payload,
    created_at, created_by
  )
  values (
    v_titulo.tenant_id, v_titulo.empresa_id,
    'TITULO_AP_CANCELADO',
    'f.titulo',
    v_titulo.id,
    jsonb_build_object(
      'motivo', p_motivo,
      'status_anterior', v_titulo.status,
      'status_novo', 'CANCELADO'
    ),
    now(), v_user
  );

  insert into f.aprovacao_evento (
    tenant_id, empresa_id,
    acao, ref_table, ref_id,
    motivo, payload,
    created_at, created_by
  )
  values (
    v_titulo.tenant_id, v_titulo.empresa_id,
    'REPROVOU',
    'f.titulo',
    v_titulo.id,
    'CANCELAMENTO_TITULO',
    jsonb_build_object(
      'motivo', p_motivo,
      'status_anterior', v_titulo.status,
      'status_novo', 'CANCELADO'
    ),
    now(), v_user
  );
end;
$$;

revoke all on function f.cancelar_titulo_ap(uuid, text) from public;
grant execute on function f.cancelar_titulo_ap(uuid, text) to authenticated;
grant execute on function f.cancelar_titulo_ap(uuid, text) to service_role;

commit;
