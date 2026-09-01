-- A antiga Gestao de Cobranca continua sendo o relatorio operacional de OS.
-- A cobranca financeira da OV permanece disponivel pelo modulo Venda a Credito.

create or replace view r.r_gestao_cobranca_os
with (security_invoker = true)
as
select
  os.tenant_id,
  os.empresa_id,
  os.id as os_id,
  os.numero_os,
  os.os_num,
  os.cliente_nome,
  os.descricao_servico,
  os.data_conclusao,
  os.valor_total,
  os.pedido_compra as pedido_compra_os,
  cobranca.id as cobranca_id,
  cobranca.status as cobranca_status,
  cobranca.pedido_compra_cliente,
  cobranca.pedido_recebido_em,
  cobranca.faturado_em,
  cobranca.proximo_contato_date,
  cobranca.responsavel_id,
  cobranca.observacao,
  documento.documento_fiscal_id,
  documento.doc_modelo,
  documento.doc_serie,
  documento.doc_numero,
  documento.doc_emissao_date,
  documento.doc_status,
  titulo.titulo_ar_id,
  titulo.ar_status,
  titulo.ar_valor_total,
  titulo.ar_valor_aberto,
  case
    when os.data_conclusao is null then null::integer
    else current_date - os.data_conclusao::date
  end as dias_desde_conclusao
from public.ordens_servico as os
left join f.gestao_cobranca_os as cobranca
  on cobranca.tenant_id = os.tenant_id
 and cobranca.empresa_id = os.empresa_id
 and cobranca.os_id = os.id
 and cobranca.deleted_at is null
left join lateral (
  select
    fiscal.id as documento_fiscal_id,
    fiscal.modelo as doc_modelo,
    fiscal.serie as doc_serie,
    fiscal.numero as doc_numero,
    fiscal.emissao_date as doc_emissao_date,
    coalesce(fiscal.nfe_status, fiscal.nfse_status) as doc_status
  from f.documento_fiscal as fiscal
  where fiscal.tenant_id = os.tenant_id
    and fiscal.empresa_id = os.empresa_id
    and fiscal.os_id_import = os.id
    and fiscal.operacao = 'SAIDA'
    and fiscal.deleted_at is null
  order by fiscal.emissao_date desc nulls last, fiscal.created_at desc
  limit 1
) as documento on true
left join lateral (
  select
    conta.id as titulo_ar_id,
    conta.status as ar_status,
    conta.valor_total as ar_valor_total,
    conta.valor_aberto as ar_valor_aberto
  from f.titulo as conta
  where conta.tenant_id = os.tenant_id
    and conta.empresa_id = os.empresa_id
    and conta.tipo = 'AR'
    and conta.documento_fiscal_id = documento.documento_fiscal_id
    and conta.deleted_at is null
  order by conta.created_at desc
  limit 1
) as titulo on true
where os.status = 'concluida'
  and os.tipo_documento = 'OS';

grant select on r.r_gestao_cobranca_os to authenticated, service_role;
