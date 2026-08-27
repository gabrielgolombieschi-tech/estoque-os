-- RELATORIO SOMENTE LEITURA: pre-migracao do novo fluxo de OS.
-- Os IDs abaixo definem explicitamente o escopo deste relatorio.
-- Nao cria, altera ou remove nenhum dado.
--
-- Regra de faturamento: a mesma usada pelo ERP-Web em lib/os/faturadoPorOs.ts.
--   - documento fiscal de SAIDA, vinculado por os_id_import e nao excluido;
--   - NFSe: nfse_status = EMITIDA;
--   - demais modelos: nfe_status vazio ou EMITIDA.

with contexto as (
  select
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid as tenant_id,
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid as empresa_id
),
documentos_emitidos as (
  select
    documento.os_id_import as os_id,
    min(coalesce(documento.emissao_date, documento.created_at::date)) as primeira_emissao,
    count(*)::integer as quantidade_documentos,
    coalesce(sum(documento.valor_total), 0)::numeric(15, 2) as valor_faturado
  from f.documento_fiscal as documento
  join contexto
    on contexto.tenant_id = documento.tenant_id
   and contexto.empresa_id = documento.empresa_id
  where documento.operacao = 'SAIDA'
    and documento.os_id_import is not null
    and documento.deleted_at is null
    and (
      (upper(coalesce(documento.modelo, '')) = 'NFSE' and upper(coalesce(documento.nfse_status, '')) = 'EMITIDA')
      or (
        upper(coalesce(documento.modelo, '')) <> 'NFSE'
        and (nullif(upper(btrim(coalesce(documento.nfe_status, ''))), '') is null or upper(coalesce(documento.nfe_status, '')) = 'EMITIDA')
      )
    )
  group by documento.os_id_import
),
os_concluidas as (
  select
    os.id,
    os.numero_os,
    os.cliente_nome,
    os.data_conclusao,
    documento.primeira_emissao,
    coalesce(documento.quantidade_documentos, 0) as quantidade_documentos,
    coalesce(documento.valor_faturado, 0)::numeric(15, 2) as valor_faturado,
    case when documento.os_id is not null then 'faturada_automatica' else 'concluida_sem_faturamento' end as balde
  from public.ordens_servico as os
  join contexto
    on contexto.tenant_id = os.tenant_id
   and contexto.empresa_id = os.empresa_id
  left join documentos_emitidos as documento on documento.os_id = os.id
  where os.status = 'concluida'
),
resumo as (
  select
    balde,
    count(*)::integer as quantidade,
    coalesce(sum(valor_faturado), 0)::numeric(15, 2) as valor_faturado_total
  from os_concluidas
  group by balde
)
select
  resumo.balde,
  resumo.quantidade,
  resumo.valor_faturado_total,
  coalesce(
    (
      select jsonb_agg(amostra order by (amostra ->> 'data_conclusao') desc nulls last, (amostra ->> 'id')::integer desc)
      from (
        select jsonb_build_object(
          'id', os.id,
          'numero_os', os.numero_os,
          'cliente_nome', os.cliente_nome,
          'data_conclusao', os.data_conclusao,
          'primeira_emissao', os.primeira_emissao,
          'quantidade_documentos', os.quantidade_documentos,
          'valor_faturado', os.valor_faturado
        ) as amostra
        from os_concluidas as os
        where os.balde = resumo.balde
        order by os.data_conclusao desc nulls last, os.id desc
        limit 10
      ) as itens_amostra
    ),
    '[]'::jsonb
  ) as amostra
from resumo
order by resumo.balde;

-- LISTA PARA REVISAO MANUAL DE GARANTIA.
-- Nao ha marcador legado confiavel de garantia: esta lista e exatamente o
-- subconjunto "concluida_sem_faturamento" a ser classificado pelo negocio.
with contexto as (
  select
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid as tenant_id,
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid as empresa_id
),
documentos_emitidos as (
  select distinct documento.os_id_import as os_id
  from f.documento_fiscal as documento
  join contexto on contexto.tenant_id = documento.tenant_id and contexto.empresa_id = documento.empresa_id
  where documento.operacao = 'SAIDA'
    and documento.os_id_import is not null
    and documento.deleted_at is null
    and (
      (upper(coalesce(documento.modelo, '')) = 'NFSE' and upper(coalesce(documento.nfse_status, '')) = 'EMITIDA')
      or (upper(coalesce(documento.modelo, '')) <> 'NFSE' and (nullif(upper(btrim(coalesce(documento.nfe_status, ''))), '') is null or upper(coalesce(documento.nfe_status, '')) = 'EMITIDA'))
    )
)
select
  os.id,
  os.numero_os,
  os.cliente_nome,
  os.data_abertura,
  os.data_conclusao,
  os.descricao_servico,
  os.responsavel_aprovacao_id
from public.ordens_servico as os
join contexto on contexto.tenant_id = os.tenant_id and contexto.empresa_id = os.empresa_id
left join documentos_emitidos as documento on documento.os_id = os.id
where os.status = 'concluida'
  and documento.os_id is null
order by os.data_conclusao desc nulls last, os.id desc;
