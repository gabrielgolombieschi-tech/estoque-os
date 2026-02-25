begin;

create or replace function public.fn_backfill_movimentacoes_nf_entrada(
  p_nf_entrada_id bigint
) returns table(rows_inserted integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nf public.nf_entrada%rowtype;
  v_rows integer := 0;
begin
  if p_nf_entrada_id is null then
    raise exception 'p_nf_entrada_id obrigatorio';
  end if;

  select *
    into v_nf
  from public.nf_entrada
  where id = p_nf_entrada_id
  limit 1;

  if v_nf.id is null then
    raise exception 'NF de entrada nao encontrada (id=%)', p_nf_entrada_id;
  end if;

  insert into public.movimentacoes (
    item_id,
    tipo,
    quantidade,
    motivo,
    realizado_por,
    data_movimentacao,
    custo_unitario_bruto,
    custo_unitario_real,
    credito_icms,
    credito_pis,
    credito_cofins,
    origem_nf_entrada_id,
    origem_os_id,
    v_ipi,
    v_icms,
    v_pis,
    v_cofins,
    v_frete_rateado,
    tenant_id,
    empresa_id
  )
  select
    i.id,
    'entrada'::text,
    coalesce(ni.qtd, 0),
    'Backfill automatico importacao XML NF-e ' || v_nf.chave,
    coalesce(public.jwt_claim('email'), auth.uid()::text, 'system-backfill'),
    now(),
    nullif(ni.v_unit, 0),
    nullif(ni.v_unit, 0),
    coalesce(ni.v_icms, 0),
    coalesce(ni.v_pis, 0),
    coalesce(ni.v_cofins, 0),
    v_nf.id,
    v_nf.os_id,
    coalesce(ni.v_ipi, 0),
    coalesce(ni.v_icms, 0),
    coalesce(ni.v_pis, 0),
    coalesce(ni.v_cofins, 0),
    0,
    v_nf.tenant_id,
    v_nf.empresa_id
  from public.nf_entrada_itens ni
  join public.itens i
    on i.tenant_id = v_nf.tenant_id
   and i.empresa_id = v_nf.empresa_id
   and i.id = ni.item_id
   and i.tipo = 'produto'
   and coalesce(i.controla_estoque, false) = true
  where ni.nf_entrada_id = v_nf.id
    and ni.tenant_id = v_nf.tenant_id
    and not exists (
      select 1
      from public.movimentacoes m
      where m.tenant_id = v_nf.tenant_id
        and m.empresa_id = v_nf.empresa_id
        and m.origem_nf_entrada_id = v_nf.id
        and m.item_id = i.id
        and m.tipo = 'entrada'
      limit 1
    );

  get diagnostics v_rows = row_count;
  rows_inserted := coalesce(v_rows, 0);
  return next;
end;
$$;

grant all on function public.fn_backfill_movimentacoes_nf_entrada(bigint) to authenticated;
grant all on function public.fn_backfill_movimentacoes_nf_entrada(bigint) to service_role;

commit;
