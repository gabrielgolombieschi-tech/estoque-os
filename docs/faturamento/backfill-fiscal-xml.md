# Backfill fiscal a partir dos XMLs armazenados

- **1.529 de 1.663 itens prioritários (91,9%)** têm evidência XML para NCM, origem, CFOP, ICMS, unidades, PIS e COFINS; **134** não têm nenhuma.
- Para origem, **1.518 das 1.662 lacunas cadastrais** têm valor XML sem conflito; **144** ficam para pesquisa ou revisão manual.
- Para NCM, o catálogo combinado (`itens` + `fiscal_itens`) tem **54 lacunas**: XML resolve apenas **3** sem conflito e **51** continuam manuais; olhando somente `itens`, a lacuna continua sendo 68.
- CEST tem evidência para **834** itens e deixa **829** sem documento; CST de IPI tem evidência para **1.342** e deixa **321** sem documento.
- Há **153 pares campo×item com mais de um valor XML**: 15 NCM, 10 origens, 32 CFOP, 8 CST/CSOSN de ICMS, 9 unidades comerciais, 33 tributáveis, 3 CEST, 15 CST de IPI, 14 PIS e 14 COFINS.

Relatório somente leitura executado em 01/09/2026 contra produção, para o tenant `3ced7cfa-efbb-4f0f-addc-2028f60d1ca7`. Nenhum `INSERT`, `UPDATE`, `DELETE`, DDL, `db push` ou `migration repair` foi executado. O recorte prioritário é o mesmo da auditoria: item ativo em OS/OV não cancelada, com `ordens_servico.data_abertura >= 01/09/2025` e `< 02/09/2026`.

## 1. Inventário e a diferença entre 211 e 51 notas

### O banco diz

Inventário de `f.documento_fiscal`, considerando XML ativo em `f.documento_fiscal_xml`:

| Operação | Natureza | Modelo | Ano | Documentos | Com XML | Sem XML |
|---|---|---:|---:|---:|---:|---:|
| ENTRADA | PRODUTO | 55 | 2016 | 2 | 2 | 0 |
| ENTRADA | PRODUTO | 55 | 2017 | 5 | 5 | 0 |
| ENTRADA | PRODUTO | nulo | 2018 | 1 | 1 | 0 |
| ENTRADA | PRODUTO | 55 | 2018 | 1 | 1 | 0 |
| ENTRADA | PRODUTO | nulo | 2019 | 3 | 3 | 0 |
| ENTRADA | PRODUTO | 55 | 2019 | 4 | 4 | 0 |
| ENTRADA | PRODUTO | 55 | 2020 | 2 | 2 | 0 |
| ENTRADA | PRODUTO | nulo | 2021 | 1 | 0 | 1 |
| ENTRADA | PRODUTO | 55 | 2021 | 1 | 1 | 0 |
| ENTRADA | PRODUTO | nulo | 2022 | 2 | 1 | 1 |
| ENTRADA | PRODUTO | 55 | 2022 | 2 | 2 | 0 |
| ENTRADA | PRODUTO | nulo | 2023 | 16 | 16 | 0 |
| ENTRADA | PRODUTO | 55 | 2023 | 8 | 8 | 0 |
| ENTRADA | PRODUTO | nulo | 2024 | 121 | 77 | 44 |
| ENTRADA | PRODUTO | 55 | 2024 | 14 | 14 | 0 |
| SAÍDA | PRODUTO | 55 | 2024 | 1 | 1 | 0 |
| ENTRADA | PRODUTO | nulo | 2025 | 151 | 110 | 41 |
| ENTRADA | PRODUTO | 55 | 2025 | 80 | 80 | 0 |
| SAÍDA | PRODUTO | 55 | 2025 | 50 | 50 | 0 |
| SAÍDA | SERVIÇO | NFS-e | 2025 | 53 | 53 | 0 |
| ENTRADA | PRODUTO | nulo | 2026 | 107 | 90 | 17 |
| ENTRADA | PRODUTO | 55 | 2026 | 1.397 | 1.397 | 0 |
| ENTRADA | PRODUTO | 65 | 2026 | 1 | 1 | 0 |
| SAÍDA | PRODUTO | nulo | 2026 | 19 | 19 | 0 |
| SAÍDA | PRODUTO | 55 | 2026 | 142 | 140 | 2 |
| SAÍDA | SERVIÇO | NFS-e | 2026 | 169 | 164 | 5 |

No período de doze meses usado pela auditoria há exatamente **211 saídas de produto**: 50 NF-e de 2025, 19 documentos de 2026 sem modelo e 142 NF-e modelo 55 de 2026. Delas, 209 têm XML.

### Por que 211 não projeta o volume anual

A diferença está explicada por importação parcial, não pelo filtro de natureza:

- O levantamento externo contém **51 NF-e de agosto/2026**; produção contém somente **30** NF-e de saída desse mês, todas da `SEG`. Faltam 21, ou **41,2%**, já no mês usado como referência.
- O histórico de saída no ERP começa em **17/09/2025**, não em 01/09/2025.
- As notas emitidas entre setembro e dezembro/2025 foram registradas no ERP principalmente em **19/03/2026**, caracterizando carga retroativa, não captura contínua.
- NFS-e não explica a diferença 51 × 30: elas estão classificadas separadamente como `natureza='SERVICO'` e `modelo='NFSE'`; o conjunto de 51 é de NF-e.
- Os 209 XMLs de saída do recorte são todos da `SEG`, somam 277 linhas e usam somente **CST 00, 20 e 51**. As duas saídas da `SGU` não têm XML; portanto, o banco não fornece evidência de CSOSN emitido pela `SGU`.

Conclusão factual: o Top 30 anterior é um ranking do subconjunto importado, não uma amostra completa das saídas. Ele não deve definir sozinho a ordem do mutirão.

SQL executado:

```sql
with docs as (
  select df.id, df.operacao, coalesce(df.natureza,'(nulo)') as natureza,
         coalesce(df.modelo,'(nulo)') as modelo,
         extract(year from df.emissao_date)::int as ano,
         df.emissao_date, df.created_at,
         exists (
           select 1
           from f.documento_fiscal_xml x
           where x.tenant_id=df.tenant_id
             and x.documento_fiscal_id=df.id
             and x.deleted_at is null
             and nullif(x.xml_raw,'') is not null
         ) as tem_xml
  from f.documento_fiscal df
  where df.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
    and df.deleted_at is null
)
select operacao,natureza,modelo,ano,count(*) as documentos,
       count(*) filter (where tem_xml) as com_xml,
       count(*) filter (where not tem_xml) as sem_xml,
       min(emissao_date) as primeira,max(emissao_date) as ultima
from docs
group by operacao,natureza,modelo,ano
order by ano,operacao,natureza,modelo;

select to_char(date_trunc('month',df.emissao_date),'YYYY-MM') as mes,
       e.codigo as empresa,coalesce(df.modelo,'(nulo)') as modelo,
       count(*) as documentos,
       min(df.created_at)::date as primeiro_registro,
       max(df.created_at)::date as ultimo_registro
from f.documento_fiscal df
join c.empresa e on e.id=df.empresa_id and e.tenant_id=df.tenant_id
where df.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and df.deleted_at is null and df.operacao='SAIDA'
  and df.natureza='PRODUTO'
  and df.emissao_date>=date '2025-09-01'
  and df.emissao_date<date '2026-09-02'
group by 1,2,3 order by 1,2,3;
```

## 2. Cobertura dos 1.663 itens prioritários

### Como a linha XML foi ligada ao item

Nas entradas, `public.import_nf_entrada` percorre o array de itens e insere `nf_entrada_itens` na mesma ordem. Em produção, as **2.025 notas de entrada com XML** têm 5.449 linhas XML e 5.449 linhas em `nf_entrada_itens`; nenhuma nota diverge na quantidade de linhas. O pareamento por posição encontra 4.508 linhas com `item_id`; 941 foram importadas sem vínculo a item interno. A igualdade integral de contagem por nota e o laço de inserção em ordem tornam esse pareamento determinístico para o retrato atual.

Nas saídas, `cProd` foi ligado a `itens.codigo_interno` dentro do mesmo tenant e empresa. Só **9** itens do recorte de OS/OV aparecem nas saídas armazenadas; quase toda a cobertura vem das entradas.

### O XML diz

| Campo | Evidência em entrada | Evidência em saída | Em qualquer XML | Sem evidência |
|---|---:|---:|---:|---:|
| NCM | 1.529 | 9 | **1.529** | **134** |
| Origem | 1.529 | 9 | **1.529** | **134** |
| CFOP | 1.529 | 9 | **1.529** | **134** |
| CST/CSOSN ICMS | 1.529 | 9 | **1.529** | **134** |
| Unidade comercial | 1.529 | 9 | **1.529** | **134** |
| Unidade tributável | 1.529 | 9 | **1.529** | **134** |
| CEST | 834 | 0 | **834** | **829** |
| CST IPI | 1.342 | 4 | **1.342** | **321** |
| CST PIS | 1.529 | 9 | **1.529** | **134** |
| CST COFINS | 1.529 | 9 | **1.529** | **134** |

### O cadastro diz e quanto o XML consegue fechar sem conflito

“Sem conflito” abaixo significa `count(distinct valor)=1`, incluindo itens com uma única nota. A coluna manual/revisão inclui ausência de XML e XMLs divergentes.

| Campo | Cadastro incompleto | XML sem conflito | Lacuna fechável | Manual/revisão |
|---|---:|---:|---:|---:|
| NCM, usando o catálogo combinado | 54 | 1.514 | **3** | **51** |
| Origem | 1.662 | 1.519 | **1.518** | **144** |
| CFOP | 1.658 | 1.497 | 1.493 | 165 |
| CST/CSOSN ICMS | 1.663 | 1.521 | 1.521 | 142 |
| Unidade comercial | 0 | 1.520 | 0 | 0 |
| Unidade tributável | 1.663 | 1.496 | 1.496 | 167 |
| CEST em branco | 1.663 | 831 | 831 | 832 |
| CST IPI | 1.663 | 1.327 | 1.327 | 336 |
| CST PIS | 1.663 | 1.515 | 1.515 | 148 |
| CST COFINS | 1.663 | 1.515 | 1.515 | 148 |

Os números mecânicos não significam que todos os campos podem ser copiados:

- **Atributos do produto:** NCM, origem, unidades e CEST são candidatos de backfill, sujeitos a unanimidade e revisão das exceções. Origem pode mudar por fornecedor/lote e CEST só deve permanecer quando aplicável ao produto.
- **Atributos da operação/emissor:** CFOP, CST/CSOSN de ICMS e CST de IPI/PIS/COFINS da entrada descrevem a venda do fornecedor para a empresa. Não definem automaticamente a revenda da `SEG` ou `SGU`. Esses valores são evidência para perfis e testes, não backfill automático do payload de saída.
- **Regime:** misturar `CST` e `CSOSN` na mesma coluna apaga a diferença entre regime normal e Simples. O XML deve preservar também o tipo do código.

SQL executado para a extração e cobertura (o mesmo CTE alimenta as seções 3 e 6):

```sql
with prioridade as materialized (
  select distinct i.tenant_id,i.empresa_id,i.id as item_id
  from public.itens i
  join public.os_itens oi on oi.tenant_id=i.tenant_id
   and oi.empresa_id=i.empresa_id and oi.item_id=i.id
  join public.ordens_servico os on os.id=oi.os_id
   and os.tenant_id=oi.tenant_id and os.empresa_id=oi.empresa_id
  where i.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
    and i.ativo is true
    and os.data_abertura>=date '2025-09-01'
    and os.data_abertura<date '2026-09-02'
    and coalesce(os.status,'')<>'cancelada'
    and coalesce(os.tipo_documento,'OS') in ('OS','OV')
), entrada_notas as materialized (
  select ne.id,ne.tenant_id,ne.empresa_id,ne.chave,
         xmlparse(document ne.xml_raw) as doc
  from public.nf_entrada ne
  where ne.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
    and ne.deleted_at is null and nullif(ne.xml_raw,'') is not null
), entrada_itens as materialized (
  select ni.tenant_id,ni.empresa_id,ni.nf_entrada_id,ni.item_id,
         row_number() over(partition by ni.nf_entrada_id order by ni.id)::int as ord
  from public.nf_entrada_itens ni
  join entrada_notas n on n.id=ni.nf_entrada_id
   and n.tenant_id=ni.tenant_id and n.empresa_id=ni.empresa_id
), entrada as materialized (
  select 'ENTRADA'::text as fonte,ei.item_id,n.chave as documento,x.*
  from entrada_notas n
  cross join lateral xmltable(
    xmlnamespaces('http://www.portalfiscal.inf.br/nfe' as n),
    '//n:det' passing n.doc columns
      ord for ordinality,
      ncm text path 'string(.//n:NCM)',
      origem text path 'string(.//n:ICMS/*/n:orig)',
      cfop text path 'string(.//n:CFOP)',
      ucom text path 'string(.//n:uCom)',
      utrib text path 'string(.//n:uTrib)',
      cest text path 'string(.//n:CEST)',
      cst text path 'string(.//n:ICMS/*/n:CST)',
      csosn text path 'string(.//n:ICMS/*/n:CSOSN)',
      ipi text path 'string(.//n:IPI/*/n:CST)',
      pis text path 'string(.//n:PIS/*/n:CST)',
      cofins text path 'string(.//n:COFINS/*/n:CST)'
  ) x
  join entrada_itens ei on ei.nf_entrada_id=n.id and ei.ord=x.ord
  join prioridade p on p.tenant_id=ei.tenant_id
   and p.empresa_id=ei.empresa_id and p.item_id=ei.item_id
), saida_notas as materialized (
  select df.tenant_id,df.empresa_id,df.chave_acesso,
         xmlparse(document dx.xml_raw) as doc
  from f.documento_fiscal df
  join f.documento_fiscal_xml dx on dx.tenant_id=df.tenant_id
   and dx.documento_fiscal_id=df.id and dx.deleted_at is null
  where df.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
    and df.deleted_at is null and df.operacao='SAIDA'
    and df.natureza='PRODUTO' and nullif(dx.xml_raw,'') is not null
), saida as materialized (
  select 'SAIDA'::text as fonte,i.id as item_id,n.chave_acesso as documento,x.*
  from saida_notas n
  cross join lateral xmltable(
    xmlnamespaces('http://www.portalfiscal.inf.br/nfe' as n),
    '//n:det' passing n.doc columns
      ord for ordinality,cprod text path 'string(.//n:cProd)',
      ncm text path 'string(.//n:NCM)',
      origem text path 'string(.//n:ICMS/*/n:orig)',
      cfop text path 'string(.//n:CFOP)',ucom text path 'string(.//n:uCom)',
      utrib text path 'string(.//n:uTrib)',cest text path 'string(.//n:CEST)',
      cst text path 'string(.//n:ICMS/*/n:CST)',
      csosn text path 'string(.//n:ICMS/*/n:CSOSN)',
      ipi text path 'string(.//n:IPI/*/n:CST)',
      pis text path 'string(.//n:PIS/*/n:CST)',
      cofins text path 'string(.//n:COFINS/*/n:CST)'
  ) x
  join public.itens i on i.tenant_id=n.tenant_id and i.empresa_id=n.empresa_id
   and btrim(i.codigo_interno)=nullif(btrim(x.cprod),'') and i.ativo is true
  join prioridade p on p.tenant_id=i.tenant_id
   and p.empresa_id=i.empresa_id and p.item_id=i.id
), evidencias as materialized (
  select * from entrada union all select * from saida
), campos as materialized (
  select fonte,item_id,documento,v.campo,nullif(btrim(v.valor),'') as valor
  from evidencias e
  cross join lateral (values
    ('NCM',e.ncm),('origem',e.origem),('CFOP',e.cfop),
    ('CST/CSOSN ICMS',case when nullif(btrim(e.cst),'') is not null
      then 'CST '||btrim(e.cst) when nullif(btrim(e.csosn),'') is not null
      then 'CSOSN '||btrim(e.csosn) end),
    ('unidade comercial',e.ucom),('unidade tributavel',e.utrib),
    ('CEST',e.cest),('CST IPI',e.ipi),
    ('CST PIS',e.pis),('CST COFINS',e.cofins)
  ) v(campo,valor)
  where nullif(btrim(v.valor),'') is not null
)
select campo,
       count(distinct item_id) filter(where fonte='ENTRADA') as entrada,
       count(distinct item_id) filter(where fonte='SAIDA') as saida,
       count(distinct item_id) as qualquer,
       1663-count(distinct item_id) as sem_evidencia
from campos group by campo;
```

## 3. Concordância e conflitos entre XMLs

| Campo | Itens com evidência | Uma nota | Múltiplas unânimes | Divergentes |
|---|---:|---:|---:|---:|
| NCM | 1.529 | 1.048 | 466 | **15** |
| Origem | 1.529 | 1.048 | 471 | **10** |
| CFOP | 1.529 | 1.048 | 449 | **32** |
| CST/CSOSN ICMS | 1.529 | 1.048 | 473 | **8** |
| Unidade comercial | 1.529 | 1.048 | 472 | **9** |
| Unidade tributável | 1.529 | 1.048 | 448 | **33** |
| CEST | 834 | 525 | 306 | **3** |
| CST IPI | 1.342 | 889 | 438 | **15** |
| CST PIS | 1.529 | 1.048 | 467 | **14** |
| CST COFINS | 1.529 | 1.048 | 467 | **14** |

`E` significa entrada e `S`, saída. Contagem é de documentos distintos.

### Divergências de atributos do produto

**NCM (15):** `13774` 39269090=1 E / 85030010=1 E; `139` 39173900=3 E / 73182400=1 E; `15044401` 85364100=3 E / 85364900=1 E; `291` 39269090=2 E / 39169090=1 E; `301204` 73063000=1 E / 73063090=1 E; `349` 73181600=4 E / 82075011=1 E; `3803` 84832000=1 E / 84833090=1 E; `3863` 82054000=1 E / 85444900=1 E; `3SK21221AA10` 85364100=4 E / 85364900=2 E; `3SU11020AB501BA0` 85365090=7 E / 85389090=1 E; `3SU14001AA101CA0` 85365090=6 E / 85389090=1 E; `408` 73089010=2 E / 85365090=1 E/S; `489` 73182900=2 E / 76042920=1 E; `6218` 83021000=1 E / 83024200=1 E; `CC320A` 39174090=2 E / 76082090=1 E.

**Origem (10):** `12821822` 0=1 E / 1=1 E; `139` 0=3 E / 2=1 E; `2011.017` 0=1 E / 2=1 E; `20973` 2=8 E/S / 0=1 E/S; `3209510` 1=4 E / 0=1 E/S; `3209536` 0=1 E/S / 1=1 E; `349` 1=4 E / 0=1 E; `3774` 0=3 E / 5=1 E; `3863` 0=1 E / 2=1 E; `489` 2=2 E / 0=1 E.

**Unidade comercial (9):** `13774` PC/PT; `139` RL=3/PC=1; `291` MIL=2/KG=1; `349` pc=4/PC=1; `3863` M/PC; `489` CT=2/PC=1; `6726` UND=3/UN=2; `CC320A` pc=2/PC=1; `GLM 0550` UNID=3/CJ=1. Variações apenas de caixa, como `pc`/`PC`, devem ser normalizadas antes de contar conflito semântico.

**Unidade tributável (33):** `11526` KG=4/PC=1; `13774` PC/PT; `139` RL=3/PC=1; `14720` UN=4/PT=1; `291` MIL=2/KG=1; `349` pc=4/PC=1; `3863` M/PC; `3RH29111HA11` PC=17/ST=1; `3RH29111HA22` PC=3/ST=1; `3RV29011E` PC=21/ST=1; `3SU10001HB200AA0` PC=3/ST=1; `3SU11020AB401BA0` PC=4/ST=1; `3SU11020AB501BA0` PC=7/ST=1; `3SU14001AA101CA0` PC=6/ST=1; `3SU15000AA100AA0` PC=4/ST=1; `3SX56012GA10` PC/ST; `3VM10102ED320AA0` PC/ST; `489` CT=2/PC=1; `5SL11067MB` PC=18/ST=1; `5SL11106MB` PC=2/ST=1; `5SL11107MB` PC=8/ST=2; `5SL11167MB` PC=4/ST=1; `5SL11207MB` PC/ST; `5SL13047MB` PC/ST; `5SL13107MB` PC=9/ST=1; `5SL13257MB` PC=8/ST=1; `5SL13327MB` PC=7/ST=1; `6204` KG=3/PC=1; `6726` UND=3/UN=2; `6ES72141AG400XB0` ST=2/PC=1; `6ES72324HB320XB0` PC/ST; `CC320A` pc=2/PC=1; `GLM 0550` UN=3/CJ=1.

**CEST (3):** `291` 1002000=2 E / 1900300=1 E; `3SU11020AB501BA0` 1200400=7 E / 1200500=1 E; `3SU14001AA101CA0` 1200400=6 E / 1200500=1 E.

### Variações tributárias e de operação

Estas linhas satisfazem a definição mecânica de “mais de um valor”, mas não são necessariamente erro de cadastro: podem refletir UF, natureza, regime do fornecedor ou tributação da operação.

**CFOP (32):** `13774` 5102/6101; `139` 6102=3/5102=1; `26067` 5102=34/6102=2/6119=1; `291` 6101=2/5102=1; `3209510` 6102=4/5102=1; `3209536` 5102/6102; `3RH29111HA11` 5102=17/6102=1; `3RH29111HA22` 5102=3/6102=1; `3RV29011E` 5102=21/6102=1; `3SU10001HB200AA0` 5102=3/6102=1; `3SU11020AB401BA0` 5102=4/6102=1; `3SU11020AB501BA0` 5102=7/6102=1; `3SU14001AA101CA0` 5102=6/6102=1; `3SU15000AA100AA0` 5102=4/6102=1; `3SX56012GA10` 5102/6102; `3VM10102ED320AA0` 5102/6102; `5SL11067MB` 5102=18/6102=1; `5SL11107MB` 5102=9/6102=1; `5SL11167MB` 5102=4/6102=1; `5SL13047MB` 5102/6102; `5SL13107MB` 5102=9/6102=1; `5SL13257MB` 5102=8/6102=1; `5SL13327MB` 5102=7/6102=1; `61010008138` 5102=3/5929=1; `6218` 5102/6404; `6ES72141AG400XB0` 6102=2/5102=1; `6ES72324HB320XB0` 5102/6102; `6SL32010BE218AA0` 5102=4/5949=1; `BMTR40X4000` 5102=2/6102=1; `CC320A` 5101=2/5102=1; `GL312PNG` 6102/6106; `GS-51PC` 6106/6916.

**CST/CSOSN ICMS (8):** `1788` CSOSN 102/CST 00; `26067` CST 20=34/CST 00=3; `291` CST 00=2/CSOSN 101=1; `408` CSOSN 102=2/CST 20=1; `489` CST 00=2/CSOSN 101=1; `6218` CSOSN 500/CST 00; `CC320A` CST 00=2/CSOSN 102=1; `GS-51PC` CST 00/CST 41.

**CST IPI (15):** `13774` 50/53; `139` 50=3/53=1; `21246` 50/53; `24405` 53=2/50=1; `349` 50=4/53=1; `3587` 50=2/53=1; `3773` 50=3/53=3; `3774` 53=3/50=1; `3777` 50=3/53=1; `489` 53=2/99=1; `CC320A` 51=2/99=1; `GLM 0548` 51=3/53=1; `GLM 0549` 51=3/53=1; `GLM 0550` 51=3/53=1; `GS-51PC` 50/53.

**CST PIS (14):** `12006` 08=2/01=1; `139` 01=3/49=1; `1788` 08/49; `291` 01=2/99=1; `408` 49=2/01=1; `489` 49=2/99=1; `6218` 01/49; `6SL32010BE218AA0` 01=4/07=1; `CC320A` 01=2/99=1; `GL312PNG` 01/99; `GLM 0548` 49=3/07=1; `GLM 0549` 49=3/07=1; `GLM 0550` 49=3/07=1; `GS-51PC` 01/08.

**CST COFINS (14):** os mesmos 14 itens e as mesmas contagens do PIS: `12006` 08=2/01=1; `139` 01=3/49=1; `1788` 08/49; `291` 01=2/99=1; `408` 49=2/01=1; `489` 49=2/99=1; `6218` 01/49; `6SL32010BE218AA0` 01=4/07=1; `CC320A` 01=2/99=1; `GL312PNG` 01/99; `GLM 0548` 49=3/07=1; `GLM 0549` 49=3/07=1; `GLM 0550` 49=3/07=1; `GS-51PC` 01/08.

SQL executado, anexado ao CTE `campos` da seção 2:

```sql
with por_item as materialized (
  select campo,item_id,count(distinct documento) as documentos,
         count(distinct valor) as valores
  from campos group by campo,item_id
)
select campo,count(*) as itens_com_evidencia,
       count(*) filter(where documentos=1) as uma_nota,
       count(*) filter(where documentos>1 and valores=1) as multiplas_unanimes,
       count(*) filter(where valores>1) as divergentes
from por_item group by campo;

with divergentes as (
  select campo,item_id
  from campos group by campo,item_id
  having count(distinct valor)>1
), valor_contagem as (
  select c.campo,c.item_id,c.valor,count(distinct c.documento) as notas,
         string_agg(distinct left(c.fonte,1),'/' order by left(c.fonte,1)) as fontes
  from campos c join divergentes d using(campo,item_id)
  group by c.campo,c.item_id,c.valor
)
select vc.campo,i.codigo_interno,i.nome,
       string_agg(vc.valor||'='||vc.notas||'['||vc.fontes||']','; '
                  order by vc.notas desc,vc.valor) as valores
from valor_contagem vc
join public.itens i on i.id=vc.item_id
group by vc.campo,i.codigo_interno,i.nome;
```

## 4. `itens` × `fiscal_itens`: correção da premissa de 44 + 1

### Estado atual do catálogo

Entre os **3.475 itens ativos** existentes no momento desta leitura:

| Campo | Só em `itens` | Só em `fiscal_itens` | Nos dois, igual | Nos dois, diferente | Em nenhum |
|---|---:|---:|---:|---:|---:|
| NCM | 243 | 23 | 2.937 | **0** | 272 |
| CEST | 0 | 0 | 0 | **0** | 3.475 |
| CFOP padrão | 174 | 0 | 0 | **0** | 3.301 |

Portanto, os **44 NCMs e 1 CFOP “divergentes” não são reproduzíveis como dois valores preenchidos diferentes**. Não há uma lista de 44 para o XML desempatar: há zero pares semânticos em conflito. O que existe são valores unilaterais, que a consulta anterior tratou como divergência ou retratou em outro instante.

A produção também mudou durante o dia: a auditoria anterior registrou 3.473 ativos e 3.135 linhas fiscais; esta leitura encontrou **3.475 ativos**, **3.137 linhas** em `fiscal_itens`, cobertura de **3.081 ativos** e **394 sem linha fiscal**. Não houve escrita desta auditoria. Há 18 itens com `criado_em` em 01/09, e o maior horário observado foi 15:04:52.

`fiscal_itens` permanece 1:1 no dado: 3.137 linhas e 3.137 chaves distintas, sem duplicata. O schema possui tanto `unique(item_id)` quanto `unique(tenant_id,empresa_id,item_id)`.

### O XML poderia arbitrar o quê

Como não existe par preenchido diferente, não há arbitragem `itens valor A × fiscal_itens valor B`. Os XMLs ainda servem para preencher lados vazios e para confrontar o valor único do catálogo; isso é backfill/validação, não desempate entre duas fontes preenchidas.

SQL executado:

```sql
with base as (
  select i.id,
    nullif(regexp_replace(btrim(coalesce(i.ncm,'')),'[^0-9]','','g'),'') as i_ncm,
    nullif(regexp_replace(btrim(coalesce(fi.ncm,'')),'[^0-9]','','g'),'') as f_ncm,
    nullif(regexp_replace(btrim(coalesce(i.cest,'')),'[^0-9]','','g'),'') as i_cest,
    nullif(regexp_replace(btrim(coalesce(fi.cest,'')),'[^0-9]','','g'),'') as f_cest,
    nullif(regexp_replace(btrim(coalesce(i.cfop_padrao,'')),'[^0-9]','','g'),'') as i_cfop,
    nullif(regexp_replace(btrim(coalesce(fi.cfop_padrao,'')),'[^0-9]','','g'),'') as f_cfop
  from public.itens i
  join c.empresa e on e.id=i.empresa_id and e.tenant_id=i.tenant_id
   and e.ativo is true and e.deleted_at is null
  left join public.fiscal_itens fi on fi.item_id=i.id
   and fi.tenant_id=i.tenant_id and fi.empresa_id=i.empresa_id
  where i.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
    and i.ativo is true
), campos as (
  select id,campo,iv,fv
  from base cross join lateral (values
    ('NCM',i_ncm,f_ncm),('CEST',i_cest,f_cest),
    ('CFOP padrão',i_cfop,f_cfop)
  ) v(campo,iv,fv)
)
select campo,
 count(*) filter(where iv is not null and fv is null) as so_itens,
 count(*) filter(where iv is null and fv is not null) as so_fiscal_itens,
 count(*) filter(where iv is not null and fv is not null and iv=fv) as ambos_iguais,
 count(*) filter(where iv is not null and fv is not null and iv<>fv) as ambos_diferentes,
 count(*) filter(where iv is null and fv is null) as nenhum
from campos group by campo;

select count(*) as linhas_tenant,
       count(distinct (tenant_id,empresa_id,item_id)) as chaves_distintas
from public.fiscal_itens
where tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';
```

## 5. Fonte de verdade e consumidores atuais

### O código diz

| Consumidor | Leitura | Escrita | Evidência |
|---|---|---|---|
| Tela principal de itens | Fiscal de `fiscal_itens` | `upsert` em `fiscal_itens` | `app/itens/ItensClient.tsx:273`, `:569`, `:771`, `:795`, `:1919` |
| Importação de estoque | Perfil de `fiscal_itens` | `upsert` em `fiscal_itens` | `app/estoque/importar/page.tsx:1703`, `:1764` |
| Agente de cadastro | Fiscal de `fiscal_itens` | `upsert` em `fiscal_itens` | `app/api/itens/agente-cadastro/sugerir/route.ts:374`; `confirmar/route.ts:252`, `:533` |
| Pedido de compra | Alíquota de IPI de `fiscal_itens` | — | `app/api/compras/pedidos/item-lookup/route.ts:190` |
| Regras fiscais SQL | `itens` só para identidade/tipo; fiscal de `fiscal_itens` | `insert/update fiscal_itens` | baseline `:30316`, `:30382`, `:30435`, `:30534` |
| Placeholder da importação de NF-e | Verifica `itens`; grava NCM e CFOP em `itens` | `insert itens` | `app/api/faturamento/nfe/importar-xml/route.ts:356-367` |
| Impressão de orçamento | NCM de `itens` | — | `app/comercial/orcamentos/[id]/imprimir/page.tsx:318` |
| Detalhe de NF-e, fallback | CFOP de `itens` quando a linha importada não tem CFOP | — | `app/faturamento/nfe/components/NfeDetail.tsx:222`, `:553`, `:567` |

A tela de item hoje **exibe e salva NCM em `fiscal_itens`**. Ela não usa `itens.ncm`, `itens.cest` nem `itens.cfop_padrao` no formulário fiscal. Em sentido oposto, a rota de importação que cria placeholder grava NCM/CFOP diretamente em `itens`, e orçamento/detalhe de nota ainda leem os campos legados. A divergência arquitetural é real mesmo sem valores conflitantes hoje.

A migration local `20260901121000_faturamento_itens_campos_fiscais.sql` amplia essa duplicação ao adicionar origem, CST/CSOSN, IPI/PIS/COFINS e unidade tributável em `itens`. Ela não cria uma terceira tabela, mas passa a manter o mesmo domínio em dois cadastros, enquanto o XML permanece a fonte documental. Além disso, `csosn` ficaria apenas em `itens`, embora o fluxo fiscal atual leia `fiscal_itens`.

### Opção A — consolidar em `public.itens`

Levar o conteúdo de `fiscal_itens` para `itens`, mudar a tela, importação, agente, pedido de compra e as funções `apply_fiscal_*`, e manter compatibilidade temporária para leitores antigos. A vantagem é eliminar `join` no payload e manter produto e fiscal juntos. O custo é o maior raio de mudança: permissões fiscais hoje são separadas (`fiscal_itens.write`), regras e auditoria já apontam para `fiscal_itens`, e campos por empresa/regime ficam acoplados ao cadastro-base.

### Opção B — consolidar em `public.fiscal_itens`

Tratar `itens.ncm`, `itens.cest` e `itens.cfop_padrao` como legado; mover a migration local de campos fiscais para `fiscal_itens`; mudar o placeholder, a impressão do orçamento e o fallback do detalhe para ler/gravar o cadastro fiscal. A vantagem é seguir a tela, permissões, agente, compras e funções SQL existentes, preservando separação entre cadastro comercial e configuração tributária. O custo é exigir `join` ou visão de compatibilidade e criar linha fiscal para os 394 itens ativos ainda sem uma.

**Recomendação, não decisão:** a Opção B tem menor raio de mudança e coincide com a fonte que a interface já exibe e salva. Antes do `db push`, a migration local deve ser revista para não criar uma segunda API fiscal em `itens`; durante a transição, uma visão ou sincronização somente de compatibilidade pode proteger orçamento e detalhe de NF-e. A decisão final continua aberta porque muda o schema ainda não aplicado.

SQL de apoio executado para descobrir as funções e consumidores SQL:

```sql
select n.nspname as schema,p.proname,
       pg_get_functiondef(p.oid) as definicao
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where p.prokind in ('f','p')
  and n.nspname in ('public','f','m')
  and (pg_get_functiondef(p.oid) ilike '%fiscal_itens%'
    or pg_get_functiondef(p.oid) ilike '%public.itens%');
```

Busca equivalente no repositório:

```text
rg -n "fiscal_itens|cfop_padrao|\.ncm|\.cest" app components lib src supabase
```

## 6. UPDATEs propostos, não executados

### NÃO EXECUTAR — aguardando janela com backup e fechamento do portão fiscal.

Os blocos abaixo são rascunhos de decisão. `xml_unanime` representa o CTE `campos` da seção 2 agregado por tenant, empresa, item e campo com `having count(distinct valor)=1`. Cada execução real deve repetir o CTE integral, mostrar o `SELECT` de prévia, validar a empresa e só então liberar o `UPDATE`. Nenhum bloco foi executado.

### NCM — candidato documental

```sql
-- PREVIEW
with xml_unanime as ( /* CTE integral da seção 2; campo='NCM'; 1 valor */ )
select i.tenant_id,i.empresa_id,i.id,i.codigo_interno,i.ncm as atual,x.valor as xml
from public.itens i join xml_unanime x on x.tenant_id=i.tenant_id
 and x.empresa_id=i.empresa_id and x.item_id=i.id
where i.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and i.empresa_id='<EMPRESA_ID>'::uuid and nullif(btrim(i.ncm),'') is null;

-- UPDATE PROPOSTO; NÃO EXECUTAR
with xml_unanime as ( /* mesmo CTE validado no preview */ )
update public.itens i set ncm=x.valor
from xml_unanime x
where i.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and i.empresa_id='<EMPRESA_ID>'::uuid
  and x.tenant_id=i.tenant_id and x.empresa_id=i.empresa_id and x.item_id=i.id
  and nullif(btrim(i.ncm),'') is null;
```

O alvo acima segue `itens` apenas para demonstrar o estado legado. Se a Opção B for aprovada, o alvo deve ser `fiscal_itens`; itens sem linha exigirão `INSERT ... ON CONFLICT`, não `UPDATE`.

### Origem — candidato documental com revisão de lote/FCI

```sql
-- PREVIEW
with xml_unanime as ( /* campo='origem'; 1 valor; valor entre 0 e 8 */ )
select fi.tenant_id,fi.empresa_id,fi.item_id,fi.origem as atual,x.valor as xml
from public.fiscal_itens fi join xml_unanime x using(tenant_id,empresa_id,item_id)
where fi.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and fi.empresa_id='<EMPRESA_ID>'::uuid and fi.origem is null;

-- UPDATE PROPOSTO; NÃO EXECUTAR
with xml_unanime as ( /* mesmo CTE validado no preview */ )
update public.fiscal_itens fi set origem=x.valor::smallint,atualizado_em=now()
from xml_unanime x
where fi.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and fi.empresa_id='<EMPRESA_ID>'::uuid
  and x.tenant_id=fi.tenant_id and x.empresa_id=fi.empresa_id and x.item_id=fi.item_id
  and fi.origem is null and x.valor ~ '^[0-8]$';
```

### Unidade comercial — nenhuma lacuna atual

```sql
-- PREVIEW: deve retornar zero no retrato atual
with xml_unanime as ( /* campo='unidade comercial'; 1 valor normalizado */ )
select i.tenant_id,i.empresa_id,i.id,i.unidade_medida,x.valor
from public.itens i join xml_unanime x on x.tenant_id=i.tenant_id
 and x.empresa_id=i.empresa_id and x.item_id=i.id
where i.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and i.empresa_id='<EMPRESA_ID>'::uuid
  and nullif(btrim(i.unidade_medida),'') is null;
-- UPDATE omitido: não há lacuna e abreviações exigem normalização de domínio.
```

### Unidade tributável — coluna ausente em produção

```sql
-- PREVIEW documental apenas
with xml_unanime as ( /* campo='unidade tributavel'; 1 valor normalizado */ )
select tenant_id,empresa_id,item_id,valor
from xml_unanime
where tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and empresa_id='<EMPRESA_ID>'::uuid;
-- UPDATE não gerável: a coluna não existe e a tabela-alvo depende da decisão da seção 5.
```

### CEST — candidato documental, condicionado à aplicabilidade

```sql
-- PREVIEW
with xml_unanime as ( /* campo='CEST'; 1 valor de 7 dígitos */ )
select fi.tenant_id,fi.empresa_id,fi.item_id,fi.cest as atual,x.valor as xml
from public.fiscal_itens fi join xml_unanime x using(tenant_id,empresa_id,item_id)
where fi.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and fi.empresa_id='<EMPRESA_ID>'::uuid and nullif(btrim(fi.cest),'') is null;

-- UPDATE PROPOSTO; NÃO EXECUTAR
with xml_unanime as ( /* mesmo CTE validado no preview */ )
update public.fiscal_itens fi set cest=x.valor,atualizado_em=now()
from xml_unanime x
where fi.tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and fi.empresa_id='<EMPRESA_ID>'::uuid
  and x.tenant_id=fi.tenant_id and x.empresa_id=fi.empresa_id and x.item_id=fi.item_id
  and nullif(btrim(fi.cest),'') is null and x.valor ~ '^[0-9]{7}$';
```

### CFOP — não copiar da entrada para a saída

```sql
-- PREVIEW para construir perfis por operação, sem alterar item
with xml_unanime as ( /* campo='CFOP', preservando fonte e documento */ )
select tenant_id,empresa_id,item_id,fonte,valor as cfop,count(*) as notas
from xml_unanime
where tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and empresa_id='<EMPRESA_ID>'::uuid
group by tenant_id,empresa_id,item_id,fonte,valor;
-- UPDATE omitido: CFOP depende de entrada/saída, UF, finalidade e natureza.
```

### CST/CSOSN de ICMS — não copiar regime do fornecedor

```sql
-- PREVIEW, mantendo o tipo do código
with xml_unanime as ( /* campo='CST/CSOSN ICMS' */ )
select tenant_id,empresa_id,item_id,fonte,valor,count(*) as notas
from xml_unanime
where tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and empresa_id='<EMPRESA_ID>'::uuid
group by tenant_id,empresa_id,item_id,fonte,valor;
-- UPDATE omitido: entrada reflete o fornecedor; SEG/SGU exigem CRT e perfil próprios.
```

### CST IPI — coluna ausente e tratamento depende da revenda

```sql
with xml_unanime as ( /* campo='CST IPI' */ )
select tenant_id,empresa_id,item_id,fonte,valor,count(*) as notas
from xml_unanime
where tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and empresa_id='<EMPRESA_ID>'::uuid
group by tenant_id,empresa_id,item_id,fonte,valor;
-- UPDATE não gerável: coluna ausente; CST de entrada não define IPI na revenda.
```

### CST PIS

```sql
with xml_unanime as ( /* campo='CST PIS' */ )
select tenant_id,empresa_id,item_id,fonte,valor,count(*) as notas
from xml_unanime
where tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and empresa_id='<EMPRESA_ID>'::uuid
group by tenant_id,empresa_id,item_id,fonte,valor;
-- UPDATE omitido: CST do fornecedor não define a saída da empresa.
```

### CST COFINS

```sql
with xml_unanime as ( /* campo='CST COFINS' */ )
select tenant_id,empresa_id,item_id,fonte,valor,count(*) as notas
from xml_unanime
where tenant_id='3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and empresa_id='<EMPRESA_ID>'::uuid
group by tenant_id,empresa_id,item_id,fonte,valor;
-- UPDATE omitido: CST do fornecedor não define a saída da empresa.
```

Não há bloco para `cClassTrib`: esse campo não existe nos XMLs NF-e analisados nem no schema de produção, e pertence à trilha paralela da reforma tributária.
