begin;

create or replace function public.set_os_item_quantidade_baixada(
  p_os_item_id integer,
  p_quantidade_baixada numeric,
  p_realizado_por text default null,
  p_motivo text default null,
  p_empresa_id uuid default null
)
returns public.os_itens
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant uuid;
  v_empresa uuid;
  v_realizado_por text;
  v_row public.os_itens%rowtype;
  v_updated public.os_itens%rowtype;
  v_item public.itens%rowtype;
  v_os public.ordens_servico%rowtype;
  v_atual numeric(14,3);
  v_nova numeric(14,3);
  v_delta numeric(14,3);
  v_saldo_atual numeric(14,3) := 0;
  v_os_label text;
  v_motivo text;
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Tenant atual nao definido';
  end if;

  if not (
    public.can('os_rpcs', 'execute')
    or public.has_permission('os.write')
  ) then
    raise exception 'Sem permissao para executar operacao de OS';
  end if;

  v_empresa := coalesce(p_empresa_id, public.current_empresa_id());
  if v_empresa is null then
    raise exception 'Empresa atual nao definida. Informe p_empresa_id na chamada da RPC.';
  end if;

  perform public.set_current_empresa(v_empresa);

  v_realizado_por := coalesce(p_realizado_por, auth.uid()::text);

  select *
    into v_row
  from public.os_itens
  where id = p_os_item_id
    and tenant_id = v_tenant
    and empresa_id = v_empresa
  for update;

  if not found then
    raise exception 'Item da OS nao encontrado';
  end if;

  select *
    into v_os
  from public.ordens_servico os
  where os.id = v_row.os_id
    and os.tenant_id = v_tenant
    and os.empresa_id = v_empresa;

  if not found then
    raise exception 'OS do item nao encontrada no tenant/empresa atual';
  end if;

  select *
    into v_item
  from public.itens
  where id = v_row.item_id
    and tenant_id = v_tenant
    and empresa_id = v_empresa;

  if not found then
    raise exception 'Item invalido ou fora do tenant/empresa atual';
  end if;

  if p_quantidade_baixada is null then
    raise exception 'Quantidade baixada invalida';
  end if;

  v_nova := round(p_quantidade_baixada, 3);
  if v_nova < 0 or v_nova > v_row.quantidade then
    raise exception 'Quantidade baixada deve ficar entre 0 e %', v_row.quantidade;
  end if;

  v_atual := least(coalesce(v_row.quantidade_baixada, 0), v_row.quantidade);
  v_delta := v_nova - v_atual;

  if abs(v_delta) < 0.0005 then
    update public.os_itens
       set quantidade_baixada = v_nova,
           baixa_estoque = (v_nova >= v_row.quantidade)
     where id = v_row.id
       and tenant_id = v_tenant
       and empresa_id = v_empresa
     returning * into v_updated;

    return v_updated;
  end if;

  if coalesce(v_item.tipo, '') <> 'produto' or coalesce(v_item.controla_estoque, false) = false then
    raise exception 'Item nao controla estoque; quantidade baixada deve permanecer 0';
  end if;

  if not (public.can('estoque', 'write') or public.can('os_rpcs', 'execute')) then
    raise exception 'Sem permissao para movimentar estoque';
  end if;

  v_os_label := coalesce(nullif(trim(v_os.numero_os), ''), nullif(v_os.os_num::text, ''), v_os.id::text);
  v_motivo := nullif(trim(coalesce(p_motivo, '')), '');
  if v_motivo is null then
    v_motivo := 'Ajuste quantidade baixada OS ' || v_os_label;
  end if;

  v_motivo := trim(regexp_replace(v_motivo, '[[:space:]]*\[OS[[:space:]]+[^\]]+\][[:space:]]*$', '', 'i'));
  if position(upper('OS ' || v_os_label) in upper(v_motivo)) = 0 then
    v_motivo := v_motivo || ' [OS ' || v_os_label || ']';
  end if;

  if v_delta > 0 then
    select coalesce(e.quantidade_atual, 0)
      into v_saldo_atual
    from public.estoque e
    where e.tenant_id = v_tenant
      and e.empresa_id = v_empresa
      and e.item_id = v_row.item_id
    for update;

    if not found then
      v_saldo_atual := 0;
    end if;

    if v_delta > coalesce(v_saldo_atual, 0) then
      raise exception 'Saldo insuficiente para baixar %. Saldo atual: %', v_delta, coalesce(v_saldo_atual, 0);
    end if;

    insert into public.movimentacoes (
      tenant_id,
      empresa_id,
      item_id,
      tipo,
      quantidade,
      motivo,
      realizado_por,
      data_movimentacao,
      origem_os_id,
      created_at
    )
    values (
      v_tenant,
      v_empresa,
      v_row.item_id,
      'saida',
      v_delta,
      v_motivo,
      v_realizado_por,
      now(),
      v_row.os_id,
      now()
    );
  else
    insert into public.movimentacoes (
      tenant_id,
      empresa_id,
      item_id,
      tipo,
      quantidade,
      motivo,
      realizado_por,
      data_movimentacao,
      origem_os_id,
      created_at
    )
    values (
      v_tenant,
      v_empresa,
      v_row.item_id,
      'entrada',
      abs(v_delta),
      v_motivo,
      v_realizado_por,
      now(),
      v_row.os_id,
      now()
    );
  end if;

  update public.os_itens
     set quantidade_baixada = v_nova,
         baixa_estoque = (v_nova >= quantidade)
   where id = v_row.id
     and tenant_id = v_tenant
     and empresa_id = v_empresa
   returning * into v_updated;

  return v_updated;
end;
$function$;

grant execute on function public.set_os_item_quantidade_baixada(integer, numeric, text, text, uuid)
  to anon, authenticated, service_role;

notify pgrst, 'reload schema';

commit;
