# Auditoria de cadastro para NF-e

- Produção tem **3.473 itens ativos**; **1.663** apareceram em OS/OV entre 01/09/2025 e 01/09/2026 e formam o mutirão prioritário.
- Entre os 1.663 prioritários, **68 (4,1%)** têm NCM incompleto, **1.662 (99,9%)** não têm origem fiscal e **1.658 (99,7%)** não têm CFOP padrão.
- **Nenhum item está 100% pronto**: unidade tributável, CST de IPI e `cClassTrib` não existem em produção; os CST existentes no cadastro auxiliar estão praticamente vazios.
- Há **57 clientes ativos movimentados**; 1 está sem documento, 29 sem IE distinguível de isenção e 17 com endereço incompleto. Indicador IE e código IBGE faltam nos 57.
- Das duas empresas, a **Elétrica Segau** não tem linha fiscal; a **SGU Automação** tem IE e CRT 1. Série, próximo número e e-mail fiscal dedicado não existem como configuração.

Auditoria somente leitura executada em 01/09/2026 contra produção. Todos os recortes usam o tenant `3ced7cfa-efbb-4f0f-addc-2028f60d1ca7`, as empresas ativas e o intervalo fechado em 01/09/2025 e aberto em 02/09/2026. Nenhuma escrita foi executada.

## 1. Schema real e mapeamento

`public.itens` não possui `deleted_at`; portanto, item ativo foi definido por `ativo IS TRUE`, vinculado a empresa ativa e não excluída. As migrations locais de faturamento adicionam campos diretamente a `public.itens` e `public.clientes`, mas elas não foram aplicadas em produção e não contêm dados reais.

Colunas reais em produção:

- `public.itens`: `id`, `codigo_interno`, `codigo_barras`, `nome`, `descricao`, `tipo`, `categoria`, `subcategoria`, `unidade_medida`, `peso_bruto`, `peso_liquido`, `controla_estoque`, `estoque_minimo`, `estoque_maximo`, `estoque_ideal`, `custo_ultima_compra`, `custo_medio`, `data_ultima_compra`, `preco_unitario`, `preco_promocional`, `data_atualizacao_preco`, `margem_lucro_percentual`, `ncm`, `cest`, `cfop_padrao`, `aliquota_icms`, `aliquota_ipi`, `aliquota_pis`, `aliquota_cofins`, `fornecedor_id`, `codigo_fornecedor`, `controla_lote`, `controla_validade`, `dias_alerta_vencimento`, `ativo`, `observacoes`, `criado_em`, `criado_por`, `atualizado_em`, `atualizado_por`, `fabricante`, `tenant_id`, `finalidade`, `empresa_id`, `motivo_compra_id`, `created_at`, `updated_at`, `codigo_interno_sem_zeros`, `codigo_fornecedor_sem_zeros`, `mesclado_em_item_id`, `mesclado_em`, `mesclado_motivo`, `grupo_id`.
- `public.clientes`: `id`, `nome`, `documento`, `email`, `telefone`, `endereco`, `observacoes`, `ativo`, `criado_em`, `atualizado_em`, `tenant_id`, `habilita_hh`, `empresa_id`, `razao_social`, `nome_fantasia`, `inscricao_estadual`, `inscricao_municipal`, `cep`, `logradouro`, `numero_endereco`, `complemento`, `bairro`, `cidade`, `uf`, `pais`, `telefone2`, `email_financeiro`, `contato_nome`, `contato_email`, `contato_telefone`, `documento_norm`, `documento_key`, `documento_raiz`.
- `c.empresa`: `id`, `tenant_id`, `codigo`, `razao_social`, `nome_fantasia`, `cnpj`, `email`, `telefone`, `site`, `observacao`, `ativo`, `created_at`, `updated_at`, `created_by`, `updated_by`, `deleted_at`.
- `c.empresa_fiscal`: `id`, `empresa_id`, `ie_isento`, `inscricao_estadual`, `inscricao_municipal`, `cnae_principal`, `regime_tributario`, `crt`, `created_at`, `updated_at`, `created_by`, `updated_by`, `deleted_at`.

Produção também possui `public.fiscal_itens`, cadastro auxiliar 1:1 por tenant, empresa e item. Ele tem 3.135 linhas no tenant, sem chaves duplicadas, e cobre 3.079 dos 3.473 itens ativos. Esse cadastro não pode ser ignorado: contém campos fiscais que não estão em `public.itens`, embora estejam quase todos vazios.

| Dado esperado | Campo real usado em produção | Situação |
|---|---|---|
| NCM | `public.itens.ncm` | Existe. Há também `public.fiscal_itens.ncm`; 44 itens ativos divergem entre os dois cadastros. |
| Origem da mercadoria | `public.fiscal_itens.origem` | Existe como `smallint`; somente 2 itens ativos estão preenchidos. `public.itens.origem_mercadoria` existe apenas no local. |
| Unidade comercial | `public.itens.unidade_medida` | Existe e está preenchida em todos os ativos. |
| Unidade tributável | Não existe | **NÃO EXISTE em produção**. Existe apenas no schema local ainda não aplicado. |
| CEST | `public.itens.cest` e `public.fiscal_itens.cest` | Existem e estão vazios. Não existe marcador confiável de item sujeito a ST para calcular a falta condicional. |
| CFOP padrão | `public.itens.cfop_padrao` | Existe. `public.fiscal_itens.cfop_padrao` também existe; há 1 divergência entre os cadastros. |
| CST ICMS | `public.fiscal_itens.cst_icms` | Existe, mas nenhum item ativo está preenchido. |
| CST IPI | Não existe | **NÃO EXISTE em produção**. |
| CST PIS | `public.fiscal_itens.cst_pis` | Existe, mas nenhum item ativo está preenchido. |
| CST COFINS | `public.fiscal_itens.cst_cofins` | Existe; somente 1 item ativo está preenchido. |
| `cClassTrib` | Não existe | **NÃO EXISTE em produção**. |
| Indicador IE / `indIEDest` | Não existe | **NÃO EXISTE em produção**. `public.clientes.indicador_ie` existe apenas no local. |
| Código IBGE municipal | Não existe | **NÃO EXISTE em produção**. |

SQL de descoberta:

```sql
select table_schema, table_name, ordinal_position, column_name, data_type
from information_schema.columns
where (table_schema, table_name) in (
  ('public', 'itens'), ('public', 'fiscal_itens'),
  ('public', 'clientes'), ('c', 'empresa'), ('c', 'empresa_fiscal')
)
order by table_schema, table_name, ordinal_position;
```

## 2. Itens ativos

CEST em branco é mostrado como retrato, não como falta fiscal definitiva: sem CST de ICMS preenchido ou outro marcador de ST, produção não permite identificar quais itens exigem CEST.

| Campo incompleto | Todos os ativos | % | Movimentados em 12 meses | % | Backlog frio | % |
|---|---:|---:|---:|---:|---:|---:|
| Total do grupo | 3.473 | 100,0% | 1.663 | 100,0% | 1.810 | 100,0% |
| NCM nulo/vazio/diferente de 8 dígitos | 295 | 8,5% | **68** | **4,1%** | 227 | 12,5% |
| Origem nula ou fora de 0–8 | 3.471 | 99,9% | **1.662** | **99,9%** | 1.809 | 99,9% |
| Unidade comercial nula/vazia | 0 | 0,0% | 0 | 0,0% | 0 | 0,0% |
| Unidade tributável | 3.473 | 100,0% | **1.663** | **100,0%** | 1.810 | 100,0% |
| CEST em branco, sem condição ST disponível | 3.473 | 100,0% | 1.663 | 100,0% | 1.810 | 100,0% |
| CFOP padrão nulo/vazio | 3.299 | 95,0% | **1.658** | **99,7%** | 1.641 | 90,7% |
| CST ICMS nulo/vazio | 3.473 | 100,0% | **1.663** | **100,0%** | 1.810 | 100,0% |
| CST IPI | 3.473 | 100,0% | **1.663** | **100,0%** | 1.810 | 100,0% |
| CST PIS nulo/vazio | 3.473 | 100,0% | **1.663** | **100,0%** | 1.810 | 100,0% |
| CST COFINS nulo/vazio | 3.472 | 100,0% | **1.663** | **100,0%** | 1.809 | 99,9% |
| `cClassTrib` | 3.473 | 100,0% | **1.663** | **100,0%** | 1.810 | 100,0% |
| **100% prontos para emitir** | **0** | **0,0%** | **0** | **0,0%** | **0** | **0,0%** |

SQL executado:

```sql
with ativos as (
  select i.*, fi.origem, fi.cst_icms, fi.cst_pis, fi.cst_cofins
  from public.itens i
  join c.empresa e on e.id=i.empresa_id and e.tenant_id=i.tenant_id
    and e.ativo is true and e.deleted_at is null
  left join public.fiscal_itens fi on fi.tenant_id=i.tenant_id
    and fi.empresa_id=i.empresa_id and fi.item_id=i.id
  where i.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7' and i.ativo is true
), movimentados as (
  select distinct oi.item_id
  from public.os_itens oi
  join public.ordens_servico os on os.id=oi.os_id
    and os.tenant_id=oi.tenant_id and os.empresa_id=oi.empresa_id
  where oi.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
    and os.data_abertura>=date '2025-09-01' and os.data_abertura<date '2026-09-02'
    and coalesce(os.status,'')<>'cancelada'
    and coalesce(os.tipo_documento,'OS') in ('OS','OV')
), base as (
  select a.*,m.item_id is not null as movimentado_12m
  from ativos a left join movimentados m on m.item_id=a.id
), grupos as (
  select 'TOTAL'::text as grupo,* from base
  union all
  select case when movimentado_12m then 'MOVIMENTADOS_12M' else 'BACKLOG_FRIO' end,* from base
)
select grupo,count(*) as total,
  count(*) filter(where length(regexp_replace(coalesce(ncm,''),'[^0-9]','','g'))<>8) as ncm,
  count(*) filter(where origem is null or origem not between 0 and 8) as origem,
  count(*) filter(where nullif(btrim(unidade_medida),'') is null) as unidade_comercial,
  count(*) as unidade_tributavel,
  count(*) filter(where nullif(btrim(cest),'') is null) as cest_branco_sem_condicao_st,
  count(*) filter(where nullif(btrim(cfop_padrao),'') is null) as cfop_padrao,
  count(*) filter(where nullif(btrim(cst_icms),'') is null) as cst_icms,
  count(*) as cst_ipi,
  count(*) filter(where nullif(btrim(cst_pis),'') is null) as cst_pis,
  count(*) filter(where nullif(btrim(cst_cofins),'') is null) as cst_cofins,
  count(*) as c_class_trib,0 as itens_100_pct_prontos
from grupos group by grupo;
```

## 3. Movimento que define o mutirão

O recorte prioritário contém **1.663 itens ativos**; o backlog frio contém **1.810**. Foram consideradas 167 OS com 4.160 linhas e 2 OV com 2 linhas. Três itens encontrados nessas linhas estavam inativos e, por isso, ficaram fora dos 1.663.

O movimento foi datado por `ordens_servico.data_abertura`, porque `os_itens` não possui uma data obrigatória e uniforme para todo o histórico. OS/OV canceladas foram excluídas.

```sql
select coalesce(os.tipo_documento,'OS') as tipo_documento,
       count(distinct os.id) as documentos,
       count(distinct oi.item_id) as itens_distintos,
       count(*) as linhas
from public.os_itens oi
join public.ordens_servico os on os.id=oi.os_id
 and os.tenant_id=oi.tenant_id and os.empresa_id=oi.empresa_id
where oi.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and os.data_abertura>=date '2025-09-01' and os.data_abertura<date '2026-09-02'
  and coalesce(os.status,'')<>'cancelada'
  and coalesce(os.tipo_documento,'OS') in ('OS','OV')
group by coalesce(os.tipo_documento,'OS');
```

## 4. Clientes movimentados

Cliente movimentado é o cliente ativo que apareceu em OS/OV não cancelada ou documento fiscal de saída no período. São 45 clientes por OS/OV, 40 por nota de saída, 28 em ambas as fontes e **57 na união**.

Documento inválido aplica os algoritmos completos de CPF e CNPJ, incluindo rejeição de dígitos repetidos. Endereço incompleto exige logradouro, número, bairro, CEP, cidade e UF.

| Falta | Quantidade | Percentual sobre 57 |
|---|---:|---:|
| Sem CNPJ/CPF | 1 | 1,8% |
| Documento preenchido com DV inválido | 0 | 0,0% |
| IE em branco, sem marcador de isenção disponível | 29 | 50,9% |
| Indicador IE / `indIEDest` | 57 | 100,0% |
| Endereço incompleto | 17 | 29,8% |
| Código IBGE do município | 57 | 100,0% |

`public.clientes` não tem marcador de isenção nem `indicador_ie` em produção. Assim, os 29 sem IE não podem ser separados entre isentos e cadastros incompletos. O campo criado na migration local ainda não produz contagem real.

SQL executado (os cálculos dos DVs permanecem no próprio SELECT):

```sql
with clientes_movimento as (
  select os.tenant_id,os.empresa_id,os.cliente_id
  from public.ordens_servico os
  where os.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
    and os.cliente_id is not null
    and os.data_abertura>=date '2025-09-01' and os.data_abertura<date '2026-09-02'
    and coalesce(os.status,'')<>'cancelada'
    and coalesce(os.tipo_documento,'OS') in ('OS','OV')
  union
  select df.tenant_id,df.empresa_id,df.cliente_id
  from f.documento_fiscal df
  where df.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
    and df.cliente_id is not null and df.deleted_at is null and df.operacao='SAIDA'
    and df.emissao_date>=date '2025-09-01' and df.emissao_date<date '2026-09-02'
), base as (
  select c.*,regexp_replace(coalesce(c.documento,''),'[^0-9]','','g') as doc
  from public.clientes c
  join c.empresa e on e.id=c.empresa_id and e.tenant_id=c.tenant_id
    and e.ativo is true and e.deleted_at is null
  join clientes_movimento cm on cm.tenant_id=c.tenant_id
    and cm.empresa_id=c.empresa_id and cm.cliente_id=c.id
  where c.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7' and c.ativo is true
), calculo as (
  select b.*,case
    when length(doc)=11 and doc<>repeat(left(doc,1),11) then
      (case when mod((select sum(substr(doc,g,1)::int*(11-g)) from generate_series(1,9) g)*10,11)=10 then 0 else mod((select sum(substr(doc,g,1)::int*(11-g)) from generate_series(1,9) g)*10,11) end=substr(doc,10,1)::int)
      and (case when mod((select sum(substr(doc,g,1)::int*(12-g)) from generate_series(1,10) g)*10,11)=10 then 0 else mod((select sum(substr(doc,g,1)::int*(12-g)) from generate_series(1,10) g)*10,11) end=substr(doc,11,1)::int)
    when length(doc)=14 and doc<>repeat(left(doc,1),14) then
      (case when 11-mod((select sum(substr(doc,g::int,1)::int*w) from unnest(array[5,4,3,2,9,8,7,6,5,4,3,2]) with ordinality x(w,g)),11)>=10 then 0 else 11-mod((select sum(substr(doc,g::int,1)::int*w) from unnest(array[5,4,3,2,9,8,7,6,5,4,3,2]) with ordinality x(w,g)),11) end=substr(doc,13,1)::int)
      and (case when 11-mod((select sum(substr(doc,g::int,1)::int*w) from unnest(array[6,5,4,3,2,9,8,7,6,5,4,3,2]) with ordinality x(w,g)),11)>=10 then 0 else 11-mod((select sum(substr(doc,g::int,1)::int*w) from unnest(array[6,5,4,3,2,9,8,7,6,5,4,3,2]) with ordinality x(w,g)),11) end=substr(doc,14,1)::int)
    else false end as documento_valido
  from base b
)
select count(*) as clientes_movimentados,
  count(*) filter(where doc='') as sem_documento,
  count(*) filter(where doc<>'' and not documento_valido) as documento_invalido,
  count(*) filter(where nullif(btrim(inscricao_estadual),'') is null) as ie_em_branco,
  count(*) as indicador_ie_ausente,
  count(*) filter(where nullif(btrim(logradouro),'') is null
    or nullif(btrim(numero_endereco),'') is null or nullif(btrim(bairro),'') is null
    or nullif(btrim(cep),'') is null or nullif(btrim(cidade),'') is null
    or nullif(btrim(uf),'') is null) as endereco_incompleto,
  count(*) as codigo_ibge_ausente
from calculo;
```

## 5. Empresas

| Empresa | CNPJ | IE | CRT / regime | CNAE principal | Série NF-e configurada | Próximo número configurado | E-mail fiscal |
|---|---|---|---|---|---|---|---|
| `SEG` — ELÉTRICA SEGAU LTDA | `13.671.448/0001-89` | **Falta**: não há linha em `c.empresa_fiscal` | **Falta** | **Falta** | **NÃO EXISTE** | **NÃO EXISTE** | **NÃO EXISTE**; e-mail geral também vazio |
| `SGU` — SGU AUTOMAÇÃO LTDA | `35.739.220/0001-16` | `260586307`, não isenta | CRT `1`, Simples Nacional | **Falta** | **NÃO EXISTE** | **NÃO EXISTE** | **NÃO EXISTE**; e-mail geral `sguautomacao@outlook.com` |

Não existe coluna de série, próximo número de NF-e ou e-mail fiscal dedicado em `c.empresa`, `c.empresa_fiscal` ou nas demais configurações encontradas. Como fotografia operacional, `f.documento_fiscal` registra saídas modelo 55 na série 1: SEG chegou ao número 3.801 em 31/08/2026; SGU chegou ao 137 em 27/02/2026. Esses valores são documentos observados, não configuração do próximo número.

```sql
select e.id,e.codigo,e.razao_social,e.nome_fantasia,e.cnpj,e.email,
       ef.ie_isento,ef.inscricao_estadual,ef.cnae_principal,ef.regime_tributario,ef.crt
from c.empresa e
left join c.empresa_fiscal ef on ef.empresa_id=e.id and ef.deleted_at is null
where e.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and e.ativo is true and e.deleted_at is null
order by e.codigo;

select e.codigo as empresa,df.serie,count(*) as notas,
       max(case when df.numero~'^[0-9]+$' then df.numero::bigint end) as maior_numero,
       max(df.emissao_date) as ultima_emissao
from f.documento_fiscal df
join c.empresa e on e.id=df.empresa_id and e.tenant_id=df.tenant_id
where df.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and df.deleted_at is null and df.modelo='55' and df.operacao='SAIDA'
group by e.codigo,df.serie order by e.codigo,df.serie;
```

## 6. Top 30 do mutirão

O ranking usa notas de saída de produto, não quantidade de OS. No período existem 211 documentos; 209 têm XML armazenado, somando 277 linhas e 180 códigos distintos. Todos os 180 códigos foram associados de forma única a item ativo da mesma empresa. As 2 notas sem XML não entram no ranking.

`CEST?` significa CEST vazio, mas sem evidência cadastral suficiente para afirmar que o item está sujeito a ST. `UT`, `IPI*` e `cClassTrib*` indicam coluna ausente em produção.

| # | Item ID | Código | Descrição | Notas | O que falta |
|---:|---:|---|---|---:|---|
| 1 | 999 | 26067 | CHAVE SEG RFID C/ ATUADOR - NSD3AZ1SQK-F40/INTERRUPTOR | 37 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 2 | 998 | 19925 | CHAVE SEG C/SOLENOIDE E ATUADOR SEPARADO 2NA/ 1NA+1NF FG 60BD1D0A | 9 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 3 | 2308 | 20973 | CHAVE SEG ACIONAM. CORDA META. C/RESET MEC ESQUERDA CONEC. FD2083 | 9 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 4 | 1935 | 23899 | CHAVE SEG ACIONAM. CORDA PARA PARADA DE EMERGENCIA FP 2078 | 7 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 5 | 2068 | 1349 | ATUADOR FIM DE CURSO DO TIPO PESADO - 3SE5000-0AV07 | 6 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 6 | 1001 | 21002 | CHAVE SEG ACIONAM. CORDA C/RESET MEC DIREITA CONEC. FD2084 | 6 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 7 | 2055 | 1758 | CABO ACO P/KIT CORDA CHAVE SEG VF F05-100 ROLO C/100M | 4 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 8 | 2065 | 1744 | CHAVE SEG RFID 2 OSSD C/ATUADOR NG 2D1D411A-F30 24V | 3 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 9 | 1010 | 20972 | SENSOR SEG MAG PLAS RFID 2NA+1NF C/ ATUADOR - ST DD420MK-D1T | 3 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 10 | 2490 | 28833 | KIT ADEQUACAO NR12 - REBOLO PENDULAR | 3 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 11 | 886 | 1339 | BARRA CHATA 3/8 X 1 A36 (I.C) | 2 | origem, UT, CEST?, CFOP, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 12 | 2057 | 1754 | GANCHO TENSIONADOR P/KIT CORDA CHAVE SEG VF AF-TR5 | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 13 | 3053 | 19506 | CHAVE SEG ACIONAM. CORDA METALICA C/RESET MEC DIREITA FL2084-M2 | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 14 | 3084 | 20141 | INTERRUPTOR DE SEGURANCA - FD 983-M2 | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 15 | 2061 | 22585 | ATUADOR PARA CHAVE NS VN NS-F40 | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 16 | 2735 | 27390 | ATUADOR FIM DE CURSO DO TIPO PESADO 3SE50000AV071AK2 | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 17 | 1415 | 27462 | CABO DE CONTROLE P/ MOVIMENTACAO CORTINA OLFLEX FD 855 P 25G0 5 | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 18 | 1856 | 27964 | SENSOR 24V CC ST DD420MK PIZZATO | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 19 | 2310 | 28144 | CONVERSOR ELETRONICO DE FREQUENCIA P/MOTOR ELETRICO CFW900C50P0T4DB20Y2B 15414333 | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 20 | 1420 | 28262 | VLI80-2P42436 RETRO-REFL. SENS. - 6037496 | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 21 | 1419 | 28263 | PL80A REFLECTOR - 1003865 | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 22 | 1417 | 28277 | ET200SP IM155-6 PN/2 HF - 6ES71556AU010CN | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 23 | 1418 | 28279 | MASTER LICENSE PARA O SERIAL NUMBER 20100 | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 24 | 2303 | 28570 | ESTACAO DE DESCARGA DE PRE MIX | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 25 | 1414 | 28771 | BASE PAINEL ELETRICO | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 26 | 1416 | 28773 | CABOS E CONECTORES PROFINET PARA ENC | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 27 | 1434 | 28774 | DRIVER PARA SERVO MOTOR - DST1202 EMERSON | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 28 | 2520 | 28835 | CLP CPU OMRON CP1H 24VDC EX-40DT-D | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 29 | 2689 | 28839 | CONJUNTO DE REDUCOES EM INOX | 2 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |
| 30 | 3587 | 10367212546 | DFS60B-S4PC10000 INCREMENTAL ENCODER | 1 | origem, UT, CEST?, CST ICMS, IPI*, CST PIS, CST COFINS, cClassTrib* |

SQL executado para o ranking:

```sql
with notas as (
  select df.id,df.tenant_id,df.empresa_id,dfx.xml_raw
  from f.documento_fiscal df
  join f.documento_fiscal_xml dfx on dfx.documento_fiscal_id=df.id
    and dfx.tenant_id=df.tenant_id and dfx.deleted_at is null
  where df.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
    and df.deleted_at is null and df.operacao='SAIDA' and df.natureza='PRODUTO'
    and df.emissao_date>=date '2025-09-01' and df.emissao_date<date '2026-09-02'
), itens_xml as (
  select n.id as nota_id,n.tenant_id,n.empresa_id,
    ((xpath('string(.//n:cProd)',det,
      array[array['n','http://www.portalfiscal.inf.br/nfe']]))[1])::text as codigo
  from notas n
  cross join lateral unnest(xpath('//n:det',xmlparse(document n.xml_raw),
    array[array['n','http://www.portalfiscal.inf.br/nfe']])) det
), uso as (
  select empresa_id,codigo,count(distinct nota_id) as notas
  from itens_xml group by empresa_id,codigo
), mapeado as (
  select u.notas,i.id,i.codigo_interno,
    coalesce(nullif(btrim(i.nome),''),i.descricao) as descricao,
    i.ncm,i.cest,i.cfop_padrao,i.unidade_medida,
    fi.origem,fi.cst_icms,fi.cst_pis,fi.cst_cofins
  from uso u
  join public.itens i on i.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
    and i.empresa_id=u.empresa_id and i.ativo is true
    and (i.codigo_interno=u.codigo
      or nullif(regexp_replace(coalesce(i.codigo_interno,''),'^0+',''),'')
       = nullif(regexp_replace(coalesce(u.codigo,''),'^0+',''),''))
  left join public.fiscal_itens fi on fi.tenant_id=i.tenant_id
    and fi.empresa_id=i.empresa_id and fi.item_id=i.id
)
select id as item_id,codigo_interno as codigo,descricao,notas,
  concat_ws(', ',
    case when length(regexp_replace(coalesce(ncm,''),'[^0-9]','','g'))<>8 then 'NCM' end,
    case when origem is null or origem not between 0 and 8 then 'origem' end,
    case when nullif(btrim(unidade_medida),'') is null then 'unidade comercial' end,
    'unidade tributável (coluna ausente)',
    case when nullif(btrim(cest),'') is null then 'CEST em branco (ST indeterminada)' end,
    case when nullif(btrim(cfop_padrao),'') is null then 'CFOP padrão' end,
    case when nullif(btrim(cst_icms),'') is null then 'CST ICMS' end,
    'CST IPI (coluna ausente)',
    case when nullif(btrim(cst_pis),'') is null then 'CST PIS' end,
    case when nullif(btrim(cst_cofins),'') is null then 'CST COFINS' end,
    'cClassTrib (coluna ausente)') as faltas
from mapeado
order by notas desc,codigo_interno,id
limit 30;
```
