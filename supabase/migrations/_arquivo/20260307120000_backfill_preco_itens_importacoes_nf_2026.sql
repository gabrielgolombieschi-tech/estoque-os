-- Backfill de preco_unitario para itens com importacoes de NF-e em 2026.
-- Regra: para cada (tenant_id, empresa_id, item_id), usa o ultimo movimento de entrada
-- vinculado a NF-e de entrada emitida em 2026 e com custo unitario valido.
with ultima_nf_2026 as (
  select distinct on (m.tenant_id, m.empresa_id, m.item_id)
    m.tenant_id,
    m.empresa_id,
    m.item_id,
    coalesce(m.custo_unitario_real, m.custo_unitario_bruto, 0)::numeric as preco_nf,
    coalesce(m.data_movimentacao, (n.data_emissao at time zone 'utc')) as data_ref
  from public.movimentacoes m
  join public.nf_entrada n
    on n.id = m.origem_nf_entrada_id
   and n.tenant_id = m.tenant_id
   and n.empresa_id = m.empresa_id
  where m.tipo = 'entrada'
    and m.origem_nf_entrada_id is not null
    and coalesce(m.custo_unitario_real, m.custo_unitario_bruto, 0) > 0
    and n.data_emissao >= timestamptz '2026-01-01 00:00:00+00'
    and n.data_emissao <  timestamptz '2027-01-01 00:00:00+00'
  order by
    m.tenant_id,
    m.empresa_id,
    m.item_id,
    n.data_emissao desc nulls last,
    m.data_movimentacao desc nulls last,
    m.id desc
)
update public.itens i
set preco_unitario = u.preco_nf,
    data_atualizacao_preco = u.data_ref,
    data_ultima_compra = case
      when i.data_ultima_compra is null or i.data_ultima_compra < u.data_ref then u.data_ref
      else i.data_ultima_compra
    end
from ultima_nf_2026 u
where i.tenant_id = u.tenant_id
  and i.empresa_id = u.empresa_id
  and i.id = u.item_id;
