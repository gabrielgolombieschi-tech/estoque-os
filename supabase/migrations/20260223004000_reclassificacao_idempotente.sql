create or replace function public.reclassificar_mov_saida_para_os(
  p_mov_id bigint,
  p_origem_os_id integer,
  p_realizado_por text default null
)
returns table (
  mov_original_id integer,
  mov_ajuste_id integer,
  mov_saida_corrigida_id integer
)
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_mov public.movimentacoes%rowtype;
  v_realizado_por text;
  v_motivo_saida text;
  v_mov_ajuste_id integer;
  v_mov_saida_id integer;
begin
  if p_mov_id is null or p_origem_os_id is null then
    raise exception 'Parametros obrigatorios: p_mov_id e p_origem_os_id';
  end if;

  select *
    into v_mov
  from public.movimentacoes
  where id = p_mov_id;

  if not found then
    raise exception 'Movimentacao % nao encontrada', p_mov_id;
  end if;

  if v_mov.tipo <> 'saida' then
    raise exception 'Movimentacao % nao e saida', p_mov_id;
  end if;

  if v_mov.origem_os_id is not null then
    raise exception 'Movimentacao % ja possui origem_os_id', p_mov_id;
  end if;

  if not exists (
    select 1
    from public.ordens_servico os
    where os.id = p_origem_os_id
      and os.tenant_id = v_mov.tenant_id
      and os.empresa_id = v_mov.empresa_id
  ) then
    raise exception 'OS % nao encontrada no mesmo tenant/empresa da movimentacao %', p_origem_os_id, p_mov_id;
  end if;

  -- Idempotencia: se a movimentacao ja foi reclassificada antes, retorna os IDs existentes.
  select m.id
    into v_mov_ajuste_id
  from public.movimentacoes m
  where m.tenant_id = v_mov.tenant_id
    and m.empresa_id = v_mov.empresa_id
    and m.item_id = v_mov.item_id
    and m.tipo = 'ajuste'
    and m.motivo = ('CORRECAO RASTREIO OS: neutraliza mov #' || v_mov.id::text)
  order by m.id asc
  limit 1;

  if v_mov_ajuste_id is not null then
    select m.id
      into v_mov_saida_id
    from public.movimentacoes m
    where m.tenant_id = v_mov.tenant_id
      and m.empresa_id = v_mov.empresa_id
      and m.item_id = v_mov.item_id
      and m.tipo = 'saida'
      and m.origem_os_id = p_origem_os_id
      and abs(coalesce(m.quantidade, 0) - coalesce(v_mov.quantidade, 0)) < 0.0001
      and abs(extract(epoch from (coalesce(m.data_movimentacao, m.created_at) - coalesce(v_mov.data_movimentacao, v_mov.created_at)))) <= 120
    order by m.id asc
    limit 1;

    if v_mov_saida_id is not null then
      return query
      select v_mov.id::integer, v_mov_ajuste_id, v_mov_saida_id;
      return;
    end if;
  end if;

  v_realizado_por := coalesce(p_realizado_por, auth.uid()::text, 'auditoria_sistema');

  insert into public.movimentacoes (
    tenant_id,
    empresa_id,
    item_id,
    tipo,
    quantidade,
    motivo,
    realizado_por,
    data_movimentacao,
    origem_nf_entrada_id,
    origem_os_id,
    created_at
  )
  values (
    v_mov.tenant_id,
    v_mov.empresa_id,
    v_mov.item_id,
    'ajuste',
    v_mov.quantidade,
    'CORRECAO RASTREIO OS: neutraliza mov #' || v_mov.id::text,
    v_realizado_por,
    coalesce(v_mov.data_movimentacao, now()),
    v_mov.origem_nf_entrada_id,
    null,
    now()
  )
  returning id into v_mov_ajuste_id;

  v_motivo_saida := trim(coalesce(v_mov.motivo, 'Baixa de estoque via OS ' || p_origem_os_id::text));
  if position(('OS ' || p_origem_os_id::text) in upper(v_motivo_saida)) = 0 then
    v_motivo_saida := v_motivo_saida || ' [OS ' || p_origem_os_id::text || ']';
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
    origem_nf_entrada_id,
    origem_os_id,
    created_at
  )
  values (
    v_mov.tenant_id,
    v_mov.empresa_id,
    v_mov.item_id,
    'saida',
    v_mov.quantidade,
    v_motivo_saida,
    v_realizado_por,
    coalesce(v_mov.data_movimentacao, now()),
    v_mov.origem_nf_entrada_id,
    p_origem_os_id,
    now()
  )
  returning id into v_mov_saida_id;

  return query
  select v_mov.id::integer, v_mov_ajuste_id, v_mov_saida_id;
end;
$$;
