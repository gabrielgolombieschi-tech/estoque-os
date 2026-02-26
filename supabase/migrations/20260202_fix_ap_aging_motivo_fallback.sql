-- Fix: show motivo_compra for AP parcels even when titulo is not yet approved.
-- The legacy contas_pagar_receber screen reads f.r_ap_aging_detalhe which previously relied solely on f.titulo_aprovacao.
-- For APs created manually/recorrentes, we already store the selected motivo_compra_id on f.titulo, but there may be no approval row yet.
-- This change falls back to t.motivo_compra_id when ta.motivo_compra_id is null.

create or replace view f.r_ap_aging_detalhe as
select
  t.tenant_id,
  t.empresa_id,
  t.id as titulo_id,
  tp.id as parcela_id,
  tp.numero as parcela_numero,
  t.fornecedor_id,
  coalesce(forn.nome, 'SEM FORNECEDOR') as fornecedor_nome,
  coalesce(mc.codigo, 'NAO_CLASSIFICADO') as motivo_codigo,
  coalesce(mc.nome, 'NAO CLASSIFICADO') as motivo_nome,
  tp.vencimento_date,
  (current_date - tp.vencimento_date) as dias_atraso,
  tp.valor as valor_parcela,
  tp.valor_aberto,
  t.status,
  t.emissao_date,
  t.competencia_date
from f.titulo_parcela tp
join f.titulo t on t.id = tp.titulo_id
left join f.titulo_aprovacao ta
  on ta.tenant_id = t.tenant_id
 and ta.titulo_id = t.id
 and ta.deleted_at is null
left join f.motivo_compra mc
  on mc.id = coalesce(ta.motivo_compra_id, t.motivo_compra_id)
 and mc.deleted_at is null
left join public.fornecedores forn on forn.id = t.fornecedor_id
where tp.deleted_at is null
  and t.deleted_at is null
  and t.tipo = 'AP'
  and tp.valor_aberto > 0;
create or replace view f.r_ap_aging_resumo as
with base as (
  select
    t.tenant_id,
    t.empresa_id,
    t.fornecedor_id,
    coalesce(forn.nome, 'SEM FORNECEDOR') as fornecedor_nome,
    coalesce(mc.codigo, 'NAO_CLASSIFICADO') as motivo_codigo,
    coalesce(mc.nome, 'NAO CLASSIFICADO') as motivo_nome,
    tp.vencimento_date,
    tp.valor_aberto,
    (current_date - tp.vencimento_date) as dias_atraso
  from f.titulo_parcela tp
  join f.titulo t on t.id = tp.titulo_id
  left join f.titulo_aprovacao ta
    on ta.tenant_id = t.tenant_id
   and ta.titulo_id = t.id
   and ta.deleted_at is null
  left join f.motivo_compra mc
    on mc.id = coalesce(ta.motivo_compra_id, t.motivo_compra_id)
   and mc.deleted_at is null
  left join public.fornecedores forn on forn.id = t.fornecedor_id
  where tp.deleted_at is null
    and t.deleted_at is null
    and t.tipo = 'AP'
    and tp.valor_aberto > 0
)
select
  tenant_id,
  empresa_id,
  fornecedor_id,
  fornecedor_nome,
  motivo_codigo,
  motivo_nome,
  sum(case when vencimento_date > current_date then valor_aberto else 0 end)::numeric(15,2) as a_vencer,
  sum(case when dias_atraso between 0 and 30 then valor_aberto else 0 end)::numeric(15,2) as vencido_0_30,
  sum(case when dias_atraso between 31 and 60 then valor_aberto else 0 end)::numeric(15,2) as vencido_31_60,
  sum(case when dias_atraso between 61 and 90 then valor_aberto else 0 end)::numeric(15,2) as vencido_61_90,
  -- IMPORTANT: keep legacy column name to allow CREATE OR REPLACE VIEW without a RENAME COLUMN step.
  -- Semantics remain: 91+ days overdue.
  sum(case when dias_atraso >= 91 then valor_aberto else 0 end)::numeric(15,2) as vencido_90_mais,
  -- IMPORTANT: keep legacy column name (was `total_aberto`) to avoid 42P16 on CREATE OR REPLACE VIEW.
  sum(valor_aberto)::numeric(15,2) as total_aberto
from base
group by
  tenant_id,
  empresa_id,
  fornecedor_id,
  fornecedor_nome,
  motivo_codigo,
  motivo_nome;
