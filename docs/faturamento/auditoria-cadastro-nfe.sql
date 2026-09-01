-- Auditoria somente leitura para emissão de NF-e.
-- Fonte usada no relatório: backup de 23/08/2026.
-- Escopo: tenant Segau e todas as empresas ativas, não excluídas, desse tenant.
-- Para outro ambiente/tenant, altere somente params.tenant_id em cada bloco.

-- 1. Confirmação das colunas fiscais disponíveis em itens e clientes.
select
  c.table_schema,
  c.table_name,
  c.ordinal_position,
  c.column_name,
  c.data_type
from information_schema.columns c
where (c.table_schema, c.table_name) in (
  ('public', 'itens'),
  ('public', 'clientes'),
  ('c', 'empresa'),
  ('c', 'empresa_fiscal')
)
order by c.table_schema, c.table_name, c.ordinal_position;

-- 2. Métricas de itens e clientes.
with
params as (
  select '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid as tenant_id
),
empresas_escopo as (
  select empresa.tenant_id, empresa.id as empresa_id
  from c.empresa as empresa
  join params on params.tenant_id = empresa.tenant_id
  where empresa.ativo is true
    and empresa.deleted_at is null
),
itens_ativos as (
  select item.*
  from public.itens as item
  join empresas_escopo as empresa
    on empresa.tenant_id = item.tenant_id
   and empresa.empresa_id = item.empresa_id
  where item.ativo is true
),
clientes_ativos as (
  select
    cliente.*,
    regexp_replace(coalesce(cliente.documento, ''), '[^0-9]', '', 'g') as documento_digitos
  from public.clientes as cliente
  join empresas_escopo as empresa
    on empresa.tenant_id = cliente.tenant_id
   and empresa.empresa_id = cliente.empresa_id
  where cliente.ativo is true
),
cnpj_somas as (
  select
    cliente.id,
    cliente.nome,
    cliente.documento,
    cliente.documento_digitos,
    (
      select sum(
        substr(cliente.documento_digitos, posicao, 1)::integer
        * (array[5,4,3,2,9,8,7,6,5,4,3,2])[posicao]
      )
      from generate_series(1, 12) as posicao
    ) as soma_primeiro_dv,
    (
      select sum(
        substr(cliente.documento_digitos, posicao, 1)::integer
        * (array[6,5,4,3,2,9,8,7,6,5,4,3,2])[posicao]
      )
      from generate_series(1, 13) as posicao
    ) as soma_segundo_dv
  from clientes_ativos as cliente
  where length(cliente.documento_digitos) = 14
),
cnpj_validacao as (
  select
    cnpj.*,
    case
      when cnpj.soma_primeiro_dv % 11 < 2 then 0
      else 11 - cnpj.soma_primeiro_dv % 11
    end as primeiro_dv_calculado,
    case
      when cnpj.soma_segundo_dv % 11 < 2 then 0
      else 11 - cnpj.soma_segundo_dv % 11
    end as segundo_dv_calculado
  from cnpj_somas as cnpj
)
select 'ITENS_TOTAL_ATIVOS' as metrica, count(*)::text as valor
from itens_ativos
union all
select 'ITENS_NCM_AUSENTE_OU_INVALIDO', count(*)::text
from itens_ativos
where length(regexp_replace(coalesce(ncm, ''), '[^0-9]', '', 'g')) <> 8
union all
select 'ITENS_UNIDADE_MEDIDA_AUSENTE', count(*)::text
from itens_ativos
where nullif(btrim(unidade_medida), '') is null
union all
select 'ITENS_CFOP_PADRAO_AUSENTE', count(*)::text
from itens_ativos
where nullif(btrim(cfop_padrao), '') is null
union all
select 'CLIENTES_TOTAL_ATIVOS', count(*)::text
from clientes_ativos
union all
select 'CLIENTES_DOCUMENTO_AUSENTE', count(*)::text
from clientes_ativos
where documento_digitos = ''
union all
select 'CLIENTES_CNPJ_DV_INVALIDO', count(*)::text
from cnpj_validacao
where documento_digitos ~ '^([0-9])\1{13}$'
   or substr(documento_digitos, 13, 1)::integer <> primeiro_dv_calculado
   or substr(documento_digitos, 14, 1)::integer <> segundo_dv_calculado
union all
select 'CLIENTES_IE_AUSENTE', count(*)::text
from clientes_ativos
where nullif(btrim(inscricao_estadual), '') is null
union all
select 'CLIENTES_ENDERECO_INCOMPLETO', count(*)::text
from clientes_ativos
where nullif(btrim(logradouro), '') is null
   or nullif(btrim(numero_endereco), '') is null
   or nullif(btrim(bairro), '') is null
   or nullif(btrim(cep), '') is null
   or nullif(btrim(uf), '') is null
order by metrica;

-- 3. CNPJs inválidos, para saneamento nominal.
with
params as (
  select '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid as tenant_id
),
empresas_escopo as (
  select empresa.tenant_id, empresa.id as empresa_id
  from c.empresa as empresa
  join params on params.tenant_id = empresa.tenant_id
  where empresa.ativo is true
    and empresa.deleted_at is null
),
clientes_cnpj as (
  select
    cliente.id,
    cliente.nome,
    cliente.documento,
    regexp_replace(coalesce(cliente.documento, ''), '[^0-9]', '', 'g') as documento_digitos
  from public.clientes as cliente
  join empresas_escopo as empresa
    on empresa.tenant_id = cliente.tenant_id
   and empresa.empresa_id = cliente.empresa_id
  where cliente.ativo is true
    and length(regexp_replace(coalesce(cliente.documento, ''), '[^0-9]', '', 'g')) = 14
),
cnpj_somas as (
  select
    cliente.*,
    (
      select sum(
        substr(cliente.documento_digitos, posicao, 1)::integer
        * (array[5,4,3,2,9,8,7,6,5,4,3,2])[posicao]
      )
      from generate_series(1, 12) as posicao
    ) as soma_primeiro_dv,
    (
      select sum(
        substr(cliente.documento_digitos, posicao, 1)::integer
        * (array[6,5,4,3,2,9,8,7,6,5,4,3,2])[posicao]
      )
      from generate_series(1, 13) as posicao
    ) as soma_segundo_dv
  from clientes_cnpj as cliente
),
cnpj_validacao as (
  select
    cnpj.*,
    case
      when cnpj.soma_primeiro_dv % 11 < 2 then 0
      else 11 - cnpj.soma_primeiro_dv % 11
    end as primeiro_dv_calculado,
    case
      when cnpj.soma_segundo_dv % 11 < 2 then 0
      else 11 - cnpj.soma_segundo_dv % 11
    end as segundo_dv_calculado
  from cnpj_somas as cnpj
)
select
  id,
  nome,
  documento,
  primeiro_dv_calculado,
  segundo_dv_calculado
from cnpj_validacao
where documento_digitos ~ '^([0-9])\1{13}$'
   or substr(documento_digitos, 13, 1)::integer <> primeiro_dv_calculado
   or substr(documento_digitos, 14, 1)::integer <> segundo_dv_calculado
order by id;

-- 4. Top 30 itens ativos sem NCM mais usados em OS.
with
params as (
  select '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid as tenant_id
),
empresas_escopo as (
  select empresa.tenant_id, empresa.id as empresa_id
  from c.empresa as empresa
  join params on params.tenant_id = empresa.tenant_id
  where empresa.ativo is true
    and empresa.deleted_at is null
),
itens_sem_ncm as (
  select item.*
  from public.itens as item
  join empresas_escopo as empresa
    on empresa.tenant_id = item.tenant_id
   and empresa.empresa_id = item.empresa_id
  where item.ativo is true
    and length(regexp_replace(coalesce(item.ncm, ''), '[^0-9]', '', 'g')) <> 8
)
select
  item.id,
  item.codigo_interno,
  item.nome,
  count(*) as linhas_os,
  sum(os_item.quantidade) as quantidade_total,
  count(distinct os_item.os_id) as os_distintas
from itens_sem_ncm as item
join public.os_itens as os_item
  on os_item.item_id = item.id
 and os_item.tenant_id = item.tenant_id
 and os_item.empresa_id = item.empresa_id
join public.ordens_servico as os
  on os.id = os_item.os_id
 and os.tenant_id = os_item.tenant_id
 and os.empresa_id = os_item.empresa_id
group by item.id, item.codigo_interno, item.nome
order by linhas_os desc, quantidade_total desc, item.id
limit 30;

-- 5. Empresas do escopo e respectivos dados fiscais.
with params as (
  select '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid as tenant_id
)
select
  empresa.id as empresa_id,
  empresa.codigo,
  empresa.razao_social,
  nullif(btrim(empresa.cnpj), '') is not null as tem_cnpj,
  fiscal.id is not null as tem_linha_fiscal,
  nullif(btrim(fiscal.inscricao_estadual), '') is not null as tem_ie,
  fiscal.ie_isento,
  fiscal.crt is not null as tem_crt,
  nullif(btrim(fiscal.cnae_principal), '') is not null as tem_cnae,
  false as tem_serie_nfe,
  false as tem_proximo_numero_nfe,
  nullif(btrim(empresa.email), '') is not null as tem_email,
  fiscal.regime_tributario
from c.empresa as empresa
join params on params.tenant_id = empresa.tenant_id
left join c.empresa_fiscal as fiscal
  on fiscal.empresa_id = empresa.id
 and fiscal.deleted_at is null
where empresa.ativo is true
  and empresa.deleted_at is null
order by empresa.codigo;

-- 6. Confirmação estrutural da ausência de série/próximo número de NF-e.
select
  coluna.table_schema,
  coluna.table_name,
  coluna.column_name,
  coluna.data_type
from information_schema.columns as coluna
where coluna.table_schema in ('c', 'f', 'public')
  and (
    coluna.column_name ilike '%serie%'
    or coluna.column_name ilike '%proximo%numero%'
    or coluna.column_name ilike '%numero%nfe%'
    or coluna.column_name ilike '%nfe%numero%'
    or coluna.column_name ilike '%nf%serie%'
  )
order by coluna.table_schema, coluna.table_name, coluna.ordinal_position;

-- 7. Volume de documento fiscal.
with
params as (
  select '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid as tenant_id
),
empresas_escopo as (
  select empresa.tenant_id, empresa.id as empresa_id
  from c.empresa as empresa
  join params on params.tenant_id = empresa.tenant_id
  where empresa.ativo is true
    and empresa.deleted_at is null
)
select
  count(*) as notas,
  count(*) filter (where documento.os_id_import is not null) as notas_com_os_id_import,
  min(documento.emissao_date) as menor_emissao,
  max(documento.emissao_date) as maior_emissao
from f.documento_fiscal as documento
join empresas_escopo as empresa
  on empresa.tenant_id = documento.tenant_id
 and empresa.empresa_id = documento.empresa_id
where documento.deleted_at is null;

