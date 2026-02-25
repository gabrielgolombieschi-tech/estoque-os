begin;

alter table f.motivo_compra
  add column if not exists favorito boolean not null default false,
  add column if not exists ordem integer not null default 0;

create schema if not exists r;

create or replace view r.r_motivo_compra_rank as
with uso_titulos as (
  select
    t.tenant_id,
    t.motivo_compra_id,
    count(*)::bigint as qtd_usos_180d
  from f.titulo t
  where t.deleted_at is null
    and t.created_at >= now() - interval '180 days'
    and t.motivo_compra_id is not null
  group by 1,2
)
select
  mc.*,
  coalesce(ut.qtd_usos_180d, 0) as qtd_usos_180d
from f.motivo_compra mc
left join uso_titulos ut
  on ut.tenant_id = mc.tenant_id
 and ut.motivo_compra_id = mc.id
where mc.deleted_at is null
  and mc.ativo = true;

alter view r.r_motivo_compra_rank set (security_invoker = on);

-- índice para lista do tenant (ajuda muito no order)
create index if not exists idx_motivo_compra__tenant_fav_ord_nome
  on f.motivo_compra (tenant_id, favorito desc, ordem desc, nome)
  where deleted_at is null and ativo = true;

commit;

-- permissões (se o projeto usa supabase com role authenticated)
grant usage on schema r to authenticated;
grant select on r.r_motivo_compra_rank to authenticated;
