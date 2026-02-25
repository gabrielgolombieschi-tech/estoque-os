begin;

-- Corrige dados existentes: para a mesma OS + item, manter apenas uma pendencia aberta
-- (priorizando EM_PEDIDO) e cancelar as duplicadas.
with abertas as (
  select
    cp.id,
    cp.tenant_id,
    cp.empresa_id,
    cp.origem_os_id,
    cp.item_id,
    cp.status,
    cp.created_at,
    row_number() over (
      partition by cp.tenant_id, cp.empresa_id, cp.origem_os_id, cp.item_id
      order by
        case when cp.status = 'EM_PEDIDO' then 0 else 1 end,
        cp.created_at asc,
        cp.id asc
    ) as rn
  from m.compra_pendencia cp
  where cp.deleted_at is null
    and cp.origem_tipo = 'OS'
    and cp.status in ('PENDENTE', 'EM_PEDIDO')
    and cp.origem_os_id is not null
    and cp.item_id is not null
),
dups as (
  select id
  from abertas
  where rn > 1
)
update m.compra_pendencia cp
   set status = 'CANCELADO',
       cancel_reason = 'Cancelado automaticamente: duplicidade de pendencia aberta para a mesma OS/item.',
       updated_by = a.fn_current_usuario_id()
 where cp.id in (select id from dups);

-- Garante integridade futura: no maximo uma pendencia aberta (PENDENTE/EM_PEDIDO)
-- por tenant+empresa+OS+item.
create unique index if not exists uq_compra_pendencia__os_item_aberta
  on m.compra_pendencia(tenant_id, empresa_id, origem_os_id, item_id)
  where deleted_at is null
    and origem_tipo = 'OS'
    and status in ('PENDENTE', 'EM_PEDIDO')
    and origem_os_id is not null
    and item_id is not null;

commit;
