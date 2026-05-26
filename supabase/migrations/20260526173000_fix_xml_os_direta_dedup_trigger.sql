begin;

create or replace function public.trg_os_itens_dedup_xml_os_direta()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_nf_id bigint;
  v_nf public.nf_entrada%rowtype;
  v_os public.ordens_servico%rowtype;
  v_os_label text;
  v_final_obs text;
  v_direct_obs_id text;
  v_qtd numeric(14,3);
  v_vunit numeric(14,6);
  v_vtotal numeric(14,2);
  v_legacy_obs text[];
  v_keep_id integer;
  v_restante numeric(14,3);
  v_os_total numeric(14,2);
begin
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  v_nf_id := nullif(substring(coalesce(new.observacoes, '') from '^Importacao XML NF ([0-9]+) \[OS '), '')::bigint;
  if v_nf_id is null then
    return new;
  end if;

  select *
    into v_nf
  from public.nf_entrada nf
  where nf.id = v_nf_id
    and nf.tenant_id = new.tenant_id
    and nf.empresa_id = new.empresa_id
    and nf.os_id = new.os_id;

  if not found then
    return new;
  end if;

  select *
    into v_os
  from public.ordens_servico os
  where os.id = new.os_id
    and os.tenant_id = new.tenant_id
    and os.empresa_id = new.empresa_id;

  if not found then
    return new;
  end if;

  v_os_label := coalesce(nullif(trim(v_os.numero_os), ''), nullif(v_os.os_num::text, ''), new.os_id::text);
  v_final_obs := 'Importacao XML NF ' || v_nf_id::text || ' [OS ' || v_os_label || ']';
  v_direct_obs_id := 'Importacao XML NF ' || v_nf_id::text || ' [OS ' || new.os_id::text || ']';

  select
    coalesce(sum(ni.qtd), 0)::numeric(14,3),
    coalesce(max(nullif(ni.v_unit, 0)), new.valor_unitario)::numeric(14,6),
    coalesce(sum(nullif(ni.v_prod, 0)), 0)::numeric(14,2),
    array_agg('IMPORT XML NF ' || v_nf.chave || ' NF_ITEM ' || ni.id::text)
  into v_qtd, v_vunit, v_vtotal, v_legacy_obs
  from public.nf_entrada_itens ni
  where ni.tenant_id = new.tenant_id
    and ni.empresa_id = new.empresa_id
    and ni.nf_entrada_id = v_nf_id
    and ni.item_id = new.item_id;

  if coalesce(v_qtd, 0) <= 0 then
    v_qtd := new.quantidade;
  end if;
  if coalesce(v_vunit, 0) <= 0 then
    v_vunit := new.valor_unitario;
  end if;
  if coalesce(v_vtotal, 0) <= 0 then
    v_vtotal := (v_qtd * coalesce(v_vunit, 0))::numeric(14,2);
  end if;
  v_legacy_obs := coalesce(v_legacy_obs, array[]::text[]);

  select oi.id
    into v_keep_id
  from public.os_itens oi
  where oi.tenant_id = new.tenant_id
    and oi.empresa_id = new.empresa_id
    and oi.os_id = new.os_id
    and oi.item_id = new.item_id
    and (
      oi.observacoes = any(v_legacy_obs)
      or oi.observacoes = v_final_obs
      or oi.observacoes = v_direct_obs_id
    )
  order by
    case when oi.observacoes = any(v_legacy_obs) then 0 else 1 end,
    oi.id
  limit 1;

  if v_keep_id is null then
    v_keep_id := new.id;
  end if;

  if v_keep_id = new.id then
    update public.os_itens oi
       set quantidade = v_qtd,
           valor_unitario = v_vunit,
           valor_total = v_vtotal,
           baixa_estoque = true,
           quantidade_baixada = v_qtd,
           observacoes = v_final_obs
     where oi.id = new.id
       and oi.tenant_id = new.tenant_id
       and oi.empresa_id = new.empresa_id;
  else
    update public.os_itens oi
       set quantidade = v_qtd,
           valor_unitario = v_vunit,
           valor_total = v_vtotal,
           baixa_estoque = true,
           quantidade_baixada = v_qtd,
           observacoes = v_final_obs
     where oi.id = v_keep_id
       and oi.tenant_id = new.tenant_id
       and oi.empresa_id = new.empresa_id;

    delete from public.os_itens oi
    where oi.tenant_id = new.tenant_id
      and oi.empresa_id = new.empresa_id
      and oi.os_id = new.os_id
      and oi.item_id = new.item_id
      and oi.id <> v_keep_id
      and (
        oi.id = new.id
        or oi.observacoes = any(v_legacy_obs)
        or oi.observacoes = v_final_obs
        or oi.observacoes = v_direct_obs_id
      );
  end if;

  update public.nf_entrada nf
     set baixa_os_automatica = true,
         updated_at = now()
   where nf.id = v_nf_id
     and nf.tenant_id = new.tenant_id
     and nf.empresa_id = new.empresa_id;

  select coalesce(sum(oi.valor_total), 0)::numeric(14,2)
    into v_os_total
  from public.os_itens oi
  where oi.tenant_id = new.tenant_id
    and oi.empresa_id = new.empresa_id
    and oi.os_id = new.os_id;

  update public.ordens_servico os
     set valor_total = v_os_total,
         atualizado_em = now()
   where os.id = new.os_id
     and os.tenant_id = new.tenant_id
     and os.empresa_id = new.empresa_id;

  select coalesce(sum(greatest(oi.quantidade - coalesce(oi.quantidade_baixada, 0), 0)), 0)::numeric(14,3)
    into v_restante
  from public.os_itens oi
  where oi.tenant_id = new.tenant_id
    and oi.empresa_id = new.empresa_id
    and oi.os_id = new.os_id
    and oi.item_id = new.item_id;

  if coalesce(v_restante, 0) <= 0 and to_regclass('m.compra_pendencia') is not null then
    update m.compra_pendencia cp
       set status = 'CANCELADO',
           cancel_reason = coalesce(cp.cancel_reason, 'Cancelado automaticamente: item baixado por importacao XML direta na OS.')
     where cp.tenant_id = new.tenant_id
       and cp.empresa_id = new.empresa_id
       and cp.deleted_at is null
       and cp.origem_tipo = 'OS'
       and cp.origem_os_id = new.os_id
       and cp.item_id = new.item_id
       and cp.status in ('PENDENTE', 'EM_PEDIDO');
  end if;

  return new;
end;
$$;

drop trigger if exists trg_os_itens_dedup_xml_os_direta on public.os_itens;
create trigger trg_os_itens_dedup_xml_os_direta
after insert on public.os_itens
for each row
execute function public.trg_os_itens_dedup_xml_os_direta();

notify pgrst, 'reload schema';

commit;
