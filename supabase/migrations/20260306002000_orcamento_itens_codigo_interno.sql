-- Expor o codigo_interno do item no relatório de itens do orçamento.
-- Isso evita "Codigo = -" na tela de orçamento e no documento impresso.
create or replace view r.r_orcamento_itens as
select
  oi.id,
  oi.orcamento_id,
  oi.seq,
  oi.item_id,
  oi.item_tipo,
  oi.item_nome,
  oi.unidade,
  oi.quantidade,
  oi.valor_unitario,
  oi.desconto_item_percent,
  oi.acrescimo_cond_pag_percent,
  oi.desconto_global_percent,
  oi.valor_total_bruto,
  oi.valor_total,
  oi.valor_unitario_liquido,
  oi.created_at,
  oi.updated_at,
  oi.tenant_id,
  oi.empresa_id,
  -- Adicionar novas colunas sempre no final para não quebrar CREATE OR REPLACE VIEW.
  upper(trim(i.codigo_interno)) as item_codigo_interno
from m.orcamento_item oi
left join public.itens i
  on i.id = oi.item_id
 and i.tenant_id = oi.tenant_id
 and i.empresa_id = oi.empresa_id
where oi.deleted_at is null;
