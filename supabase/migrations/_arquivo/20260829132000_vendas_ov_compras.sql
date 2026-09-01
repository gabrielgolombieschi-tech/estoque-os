-- Compras mantem origem_tipo='OS' por compatibilidade. O tipo real e o codigo
-- visivel passam a ser derivados do documento de origem.

create or replace view r.r_compra_pendencias_detalhadas
with (security_invoker = true)
as
select
  pendencia.id as pendencia_id,
  pendencia.tenant_id,
  pendencia.empresa_id,
  pendencia.fornecedor_id,
  coalesce(fornecedor.nome, 'SEM FORNECEDOR') as fornecedor_nome,
  pendencia.status,
  pendencia.origem_tipo,
  pendencia.origem_os_id,
  documento.os_num,
  documento.numero_os,
  pendencia.item_id,
  item.codigo_interno as item_codigo,
  coalesce(pendencia.item_nome, item.nome::text, item.descricao) as item_nome,
  coalesce(pendencia.unidade, item.unidade_medida::text, 'UN') as unidade,
  pendencia.quantidade,
  pendencia.prioridade,
  pendencia.necessario_em,
  pendencia.observacoes,
  pendencia.estoque_meta,
  pendencia.estoque_atual_qtd,
  pendencia.estoque_em_compra_qtd,
  pendencia.estoque_alvo_qtd,
  pendencia.estoque_sugestao_qtd,
  documento.tipo_documento,
  documento.codigo
from m.compra_pendencia as pendencia
left join public.fornecedores as fornecedor
  on fornecedor.tenant_id = pendencia.tenant_id
 and fornecedor.empresa_id = pendencia.empresa_id
 and fornecedor.id = pendencia.fornecedor_id
left join public.ordens_servico as documento
  on documento.tenant_id = pendencia.tenant_id
 and documento.empresa_id = pendencia.empresa_id
 and documento.id = pendencia.origem_os_id
left join public.itens as item
  on item.tenant_id = pendencia.tenant_id
 and item.empresa_id = pendencia.empresa_id
 and item.id = pendencia.item_id
where pendencia.deleted_at is null;

create or replace view r.r_compra_pendencias_agrupadas_item
with (security_invoker = true)
as
with pend as (
  select
    pendencia.id,
    pendencia.tenant_id,
    pendencia.empresa_id,
    pendencia.fornecedor_id,
    pendencia.origem_tipo,
    pendencia.origem_os_id,
    pendencia.item_id,
    upper(trim(coalesce(pendencia.item_nome, item.nome::text, item.descricao, 'ITEM SEM NOME'))) as item_nome,
    coalesce(nullif(trim(pendencia.unidade), ''), nullif(trim(item.unidade_medida), ''), 'UN') as unidade,
    pendencia.quantidade,
    pendencia.estoque_meta,
    pendencia.created_at,
    documento.os_num,
    documento.numero_os,
    documento.tipo_documento,
    documento.codigo
  from m.compra_pendencia as pendencia
  left join public.itens as item
    on item.tenant_id = pendencia.tenant_id
   and item.empresa_id = pendencia.empresa_id
   and item.id = pendencia.item_id
  left join public.ordens_servico as documento
    on documento.tenant_id = pendencia.tenant_id
   and documento.empresa_id = pendencia.empresa_id
   and documento.id = pendencia.origem_os_id
  where pendencia.deleted_at is null
    and pendencia.status = 'PENDENTE'
), em_compra as (
  select
    pedido.tenant_id,
    pedido.empresa_id,
    pedido_item.item_id,
    sum(greatest(pedido_item.quantidade - pedido_item.quantidade_recebida, 0))::numeric(15,3) as qtd_em_compra_aberto
  from m.pedido_compra_item as pedido_item
  join m.pedido_compra as pedido on pedido.id = pedido_item.pedido_compra_id
  where pedido.deleted_at is null
    and pedido_item.deleted_at is null
    and pedido.status in ('RASCUNHO', 'AGUARDANDO_APROVACAO', 'APROVADO', 'ENVIADO', 'PARCIAL_RECEBIDO')
  group by pedido.tenant_id, pedido.empresa_id, pedido_item.item_id
)
select
  pend.tenant_id,
  pend.empresa_id,
  pend.fornecedor_id,
  coalesce(fornecedor.nome, 'SEM FORNECEDOR') as fornecedor_nome,
  pend.item_id,
  item.codigo_interno as item_codigo,
  pend.item_nome,
  pend.unidade,
  array_agg(pend.id order by pend.created_at) as pendencia_ids,
  coalesce(sum(pend.quantidade) filter (where pend.origem_tipo = 'OS'), 0)::numeric(15,3) as qtd_os_total,
  coalesce(sum(pend.quantidade) filter (where pend.origem_tipo in ('OUTROS', 'ESTOQUE')), 0)::numeric(15,3) as qtd_outros_total,
  coalesce(estoque.quantidade_atual, 0)::numeric(15,3) as qtd_estoque_atual,
  coalesce(em_compra.qtd_em_compra_aberto, 0)::numeric(15,3) as qtd_em_compra_aberto,
  greatest(0, coalesce(item.estoque_minimo, 0)::numeric - (coalesce(estoque.quantidade_atual, 0) + coalesce(em_compra.qtd_em_compra_aberto, 0)))::numeric(15,3) as sugestao_min,
  greatest(0, coalesce(item.estoque_ideal, 0)::numeric - (coalesce(estoque.quantidade_atual, 0) + coalesce(em_compra.qtd_em_compra_aberto, 0)))::numeric(15,3) as sugestao_ideal,
  greatest(0, coalesce(item.estoque_maximo, 0)::numeric - (coalesce(estoque.quantidade_atual, 0) + coalesce(em_compra.qtd_em_compra_aberto, 0)))::numeric(15,3) as sugestao_max,
  (array_agg(pend.id order by pend.created_at) filter (where pend.origem_tipo = 'ESTOQUE'))[1] as estoque_pendencia_id,
  max(pend.estoque_meta) filter (where pend.origem_tipo = 'ESTOQUE') as estoque_meta_atual,
  coalesce(sum(pend.quantidade) filter (where pend.origem_tipo = 'ESTOQUE'), 0)::numeric(15,3) as qtd_estoque_pendencia,
  coalesce(
    jsonb_agg(
      jsonb_build_object(
        'pendencia_id', pend.id,
        'documento_id', pend.origem_os_id,
        'os_id', pend.origem_os_id,
        'tipo_documento', coalesce(pend.tipo_documento, 'OS'),
        'codigo', coalesce(pend.codigo, 'OS ' || coalesce(pend.numero_os, pend.os_num::text, pend.origem_os_id::text)),
        'os_num', pend.os_num,
        'numero_os', pend.numero_os,
        'quantidade', pend.quantidade
      ) order by pend.created_at
    ) filter (where pend.origem_tipo = 'OS'),
    '[]'::jsonb
  ) as os_breakdown
from pend
left join public.fornecedores as fornecedor
  on fornecedor.tenant_id = pend.tenant_id
 and fornecedor.empresa_id = pend.empresa_id
 and fornecedor.id = pend.fornecedor_id
left join public.itens as item
  on item.tenant_id = pend.tenant_id
 and item.empresa_id = pend.empresa_id
 and item.id = pend.item_id
left join public.estoque as estoque
  on estoque.tenant_id = pend.tenant_id
 and estoque.empresa_id = pend.empresa_id
 and estoque.item_id = pend.item_id
left join em_compra
  on em_compra.tenant_id = pend.tenant_id
 and em_compra.empresa_id = pend.empresa_id
 and em_compra.item_id = pend.item_id
group by
  pend.tenant_id,
  pend.empresa_id,
  pend.fornecedor_id,
  coalesce(fornecedor.nome, 'SEM FORNECEDOR'),
  pend.item_id,
  item.codigo_interno,
  pend.item_nome,
  pend.unidade,
  estoque.quantidade_atual,
  em_compra.qtd_em_compra_aberto,
  item.estoque_minimo,
  item.estoque_ideal,
  item.estoque_maximo;

grant select on r.r_compra_pendencias_detalhadas to authenticated, service_role;
grant select on r.r_compra_pendencias_agrupadas_item to authenticated, service_role;
