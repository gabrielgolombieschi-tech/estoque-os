set check_function_bodies = off;

-- Saneia dados legados de compra_pendencia (origem OS):
-- 1) consolida duplicidades para manter apenas 1 pendencia ativa por OS+item
-- 2) cancela pendencias que nao existem mais na fonte atual da OS
with fonte_os as (
  select
    oi.tenant_id,
    oi.empresa_id,
    oi.os_id,
    oi.item_id,
    sum(oi.quantidade)::numeric(15,3) as quantidade
  from public.os_itens oi
  join public.ordens_servico os
    on os.tenant_id = oi.tenant_id
   and os.empresa_id = oi.empresa_id
   and os.id = oi.os_id
  where oi.quantidade > 0
    and coalesce(oi.baixa_estoque, false) = false
    and os.status in ('aberta', 'em_andamento')
  group by oi.tenant_id, oi.empresa_id, oi.os_id, oi.item_id
),
ranked as (
  select
    cp.id,
    cp.tenant_id,
    cp.empresa_id,
    cp.origem_os_id,
    cp.item_id,
    cp.quantidade,
    row_number() over (
      partition by cp.tenant_id, cp.empresa_id, cp.origem_os_id, cp.item_id
      order by cp.created_at desc nulls last, cp.id desc
    ) as rn,
    count(*) over (
      partition by cp.tenant_id, cp.empresa_id, cp.origem_os_id, cp.item_id
    ) as grp_count,
    sum(cp.quantidade) over (
      partition by cp.tenant_id, cp.empresa_id, cp.origem_os_id, cp.item_id
    )::numeric(15,3) as soma_qtd
  from m.compra_pendencia cp
  where cp.deleted_at is null
    and cp.origem_tipo = 'OS'
    and cp.status in ('PENDENTE', 'EM_PEDIDO')
),
consolidar_keeper as (
  update m.compra_pendencia cp
     set quantidade = coalesce(f.quantidade, r.soma_qtd),
         updated_by = a.fn_current_usuario_id()
    from ranked r
    left join fonte_os f
      on f.tenant_id = r.tenant_id
     and f.empresa_id = r.empresa_id
     and f.os_id = r.origem_os_id
     and f.item_id = r.item_id
   where cp.id = r.id
     and r.grp_count > 1
     and r.rn = 1
  returning cp.id
),
cancelar_duplicados as (
  update m.compra_pendencia cp
     set status = 'CANCELADO',
         cancel_reason = 'Cancelado automaticamente: duplicidade OS+item consolidada.',
         updated_by = a.fn_current_usuario_id()
    from ranked r
   where cp.id = r.id
     and r.grp_count > 1
     and r.rn > 1
  returning cp.id
)
update m.compra_pendencia cp
   set status = 'CANCELADO',
       cancel_reason = 'Cancelado automaticamente: item removido/baixado na OS.',
       updated_by = a.fn_current_usuario_id()
 where cp.deleted_at is null
   and cp.origem_tipo = 'OS'
   and cp.status in ('PENDENTE', 'EM_PEDIDO')
   and not exists (
     select 1
     from fonte_os f
     where f.tenant_id = cp.tenant_id
       and f.empresa_id = cp.empresa_id
       and f.os_id = cp.origem_os_id
       and f.item_id = cp.item_id
   );
