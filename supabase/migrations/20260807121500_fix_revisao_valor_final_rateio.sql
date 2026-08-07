begin;

-- Corrige a ordem da revisao quando o rateio possui percentual e valor.
-- O trigger de rateio compara o valor com o total atual do titulo; por isso,
-- rateios percentuais precisam ser recalculados depois da atualizacao do titulo.
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
  v_rateio_fixo_total_anterior numeric(15,2);
  v_rateio_fixo_total_novo numeric(15,2);
  v_rateio_fixo_ultimo_id uuid;
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

  v_novo_aberto := round(v_novo_valor - v_valor_pago, 2);

  update f.titulo_parcela tp
  set valor = v_novo_valor,
      valor_aberto = v_novo_aberto,
      updated_at = now(),
      updated_by = v_usuario_id
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

  -- Rateios somente em valor podem ser proporcionados antes do titulo porque
  -- o trigger imediato nao faz a validacao cruzada percentual x valor.
  select coalesce(sum(tr.valor), 0)::numeric(15,2)
    into v_rateio_fixo_total_anterior
  from f.titulo_rateio tr
  where tr.tenant_id = p_tenant_id
    and tr.titulo_id = p_titulo_id
    and tr.deleted_at is null
    and tr.percentual is null
    and tr.valor is not null;

  if v_titulo.valor_total > 0
     and abs(v_rateio_fixo_total_anterior - v_titulo.valor_total) <= 0.02
     and exists (
       select 1
       from f.titulo_rateio tr
       where tr.tenant_id = p_tenant_id
         and tr.titulo_id = p_titulo_id
         and tr.deleted_at is null
         and tr.percentual is null
         and tr.valor is not null
     ) then
    update f.titulo_rateio tr
    set valor = round(tr.valor * v_titulo_total_novo / v_titulo.valor_total, 2),
        updated_at = now(),
        updated_by = v_usuario_id
    where tr.tenant_id = p_tenant_id
      and tr.titulo_id = p_titulo_id
      and tr.deleted_at is null
      and tr.percentual is null
      and tr.valor is not null;

    select coalesce(sum(tr.valor), 0)::numeric(15,2)
      into v_rateio_fixo_total_novo
    from f.titulo_rateio tr
    where tr.tenant_id = p_tenant_id
      and tr.titulo_id = p_titulo_id
      and tr.deleted_at is null
      and tr.percentual is null
      and tr.valor is not null;

    select tr.id
      into v_rateio_fixo_ultimo_id
    from f.titulo_rateio tr
    where tr.tenant_id = p_tenant_id
      and tr.titulo_id = p_titulo_id
      and tr.deleted_at is null
      and tr.percentual is null
      and tr.valor is not null
    order by tr.id desc
    limit 1;

    if v_rateio_fixo_ultimo_id is not null
       and v_rateio_fixo_total_novo is distinct from v_titulo_total_novo then
      update f.titulo_rateio tr
      set valor = round(tr.valor + (v_titulo_total_novo - v_rateio_fixo_total_novo), 2),
          updated_at = now(),
          updated_by = v_usuario_id
      where tr.id = v_rateio_fixo_ultimo_id
        and tr.tenant_id = p_tenant_id;
    end if;

    v_rateios_ajustados := true;
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

  -- Com o novo total ja visivel, o trigger permite recalcular os rateios que
  -- armazenam simultaneamente percentual e valor.
  update f.titulo_rateio tr
  set valor = round(v_titulo_total_novo * tr.percentual / 100.0, 2),
      updated_at = now(),
      updated_by = v_usuario_id
  where tr.tenant_id = p_tenant_id
    and tr.titulo_id = p_titulo_id
    and tr.deleted_at is null
    and tr.percentual is not null
    and tr.valor is not null
    and tr.valor is distinct from round(v_titulo_total_novo * tr.percentual / 100.0, 2);

  if found then
    v_rateios_ajustados := true;
  end if;

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

revoke all on function f.revisar_valor_final_ap(uuid, uuid, uuid, uuid, numeric, text, text) from public;
grant execute on function f.revisar_valor_final_ap(uuid, uuid, uuid, uuid, numeric, text, text)
  to authenticated, service_role;

commit;
