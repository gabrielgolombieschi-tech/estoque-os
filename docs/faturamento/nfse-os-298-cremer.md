# NFS-e da OS 298 — CREMER S.A. — NR 12 Cozinha de Goma

Uma NFS-e de **R$ 58.000,00**, sem NF-e. OC 148753, linha única de serviço, IPI zero, 60 dias,
frete FOB. Definição fiscal do Gabriel em 18/09/2026. A nota precisa sair até **20/09/2026**
(cláusula da OC).

| | |
| --- | --- |
| OS | 298 (`ordens_servico.id` 297) · CREMER S.A. (cliente 178) · orçado 58.000,00 |
| Serviço | 14.01 · adequação de máquina à NR-12 (mecânica e elétrica), com projeto, apreciação de risco, laudo e ART. Empreitada a preço fechado |
| Tomador | CREMER S.A. · 82.641.325/0001-18 · IE 250010992 · Rua Iguaçu 291, Itoupava Seca, Blumenau/SC · CEP 89030-030 (cadastro confere com a OC) |
| Homologação | **DPS 2/36 · NFS-e de teste nº 21** · autorizada 18/09/2026 13:45 · verificação 42091022213671448000189000000000002126090538633989 |
| Produção | **Não emitida.** Depende da liberação do perfil para esta homologação (capítulo abaixo) |

## Como saiu a homologação

| Campo | Valor | Esperado |
| --- | --- | --- |
| Valor do serviço | 58.000,00 | igual |
| ISS | 5% · 2.900,00 · **não retido** (recolhido pela Segau em Joinville) | igual |
| Retenção CRF | 4,65% · **2.697,00** (PIS 377,00 + COFINS 1.740,00 + CSLL 580,00), `tpRetPisCofins 3` | igual |
| IRRF / INSS | não há | igual |
| PIS próprio | **957,00** (1,65%) — campo `valor_pis`, novo | igual |
| COFINS próprio | **4.408,00** (7,60%) — campo `valor_cofins`, novo | igual |
| Líquido a receber | **55.303,00** · parcela 001 em 60 dias · boleto | igual |
| cTribNac / NBS | 140101 / 120015000 | igual |
| Local da prestação | 4202404 (Blumenau) · ISS incide em 4209102 (Joinville) | igual |
| IBS/CBS | CST 000 · cClassTrib 000001 · cIndOp **050102** | CST e cClassTrib iguais; **base**: ver abaixo |
| Pedido de compra | 148753 (campo próprio e no corpo) | igual |
| Competência | 2026-09-18 | mês da emissão |

**Base do IBS/CBS.** O esperado de 49.735,00 exclui o ISS **e** o PIS/COFINS próprios
(58.000 − 2.900 − 957 − 4.408). O ERP mostra **55.100,00** (58.000 − 2.900), que é o que o
ambiente nacional devolveu nas NFS-e 32 e 37 de agosto/2026 e o que `calcularIbsCbsNfse`
reproduz. A DPS **não leva a base**: quem calcula é o ambiente nacional. Enquanto a diferença não
for decidida, o ERP segue o comportamento observado; o teste do pipeline fixa os dois números
para ninguém mudar sem querer.

**Discriminação (íntegra, como foi enviada):**

```
ADEQUAÇÃO DE MÁQUINA À NR-12 — COZINHA DE GOMA: ADEQUAÇÃO MECÂNICA E ELÉTRICA DE SEGURANÇA,
INCLUINDO PROJETO, APRECIAÇÃO DE RISCO, LAUDO TÉCNICO E ART. EMPREITADA A PREÇO FECHADO. PEDIDO
DE COMPRA Nº 148753. PEDIDO DE COMPRA: 148753. VENCIMENTO: 60 DDL. OS 298. "SERVIÇO SUJEITO À
RETENÇÃO DE CRF À ALÍQUOTA DE 4,65% (PIS 0,65%; COFINS 3,0%; CSLL 1,0%) CONFORME LEI 10.833/2003,
ARTS. 30 E 31, E IN SRF 459/2004. TRIBUTOS INCIDENTES SOBRE O PREÇO CONFORME LEI 12.741/2012."
```

O pedido aparece **duas vezes**: uma na descrição exata pedida pelo Gabriel e outra no segmento
que o ERP monta sempre. Para sair uma só vez, tire a última frase da descrição da linha ou deixe
um template de discriminação sem `{PEDIDO}` no cadastro do cliente.

**Informações complementares:** `OS 298 | EMITIDA EM HOMOLOGACAO - SEM VALOR FISCAL` (o aviso de
homologação sai na nota real).

## Material da OS = insumo do serviço

Conferido antes de mexer: **nenhum item FAB-\*, nenhum item fabricado e nenhuma linha com
finalidade "venda"**. As 39 linhas são 36 de produto (R$ 2.902,11, 35 já com baixa de estoque
como consumo/aplicação na OS) e 3 de despesa (R$ 521,98: ART/CREA-SC), que não movimentam
estoque. Os R$ 3.424,09 do `valor_total` da OS são a soma das duas coisas; os R$ 2.902,11 são o
material. **Nada precisou ser alterado.**

A NFS-e não toca no estoque e não deduz material da base (o 14.01 não permite dedução; só a obra
07.02 permite). Depois da nota o **saldo a faturar da OS é zero** (58.000,00 reservados pela
solicitação; a nota real converte a reserva em faturado). A decisão ficou registrada na
solicitação, em campo interno que não vai na nota:

> Material acessório tratado como insumo do serviço, decisão de Gabriel G. Mendes em 18/09/2026;
> OC 148753 em linha única de serviço.

## Emitir a NFS-e real da OS 298 (passo a passo)

A nota real só sai depois que o perfil **SEG-NFSE-1401** for liberado **para esta homologação**.
A revisão do perfil (texto legal e cIndOp novos) desabilitou a produção de propósito: toda
revisão exige homologação nova e liberação nova.

1. **Liberar o perfil.** `node scripts/nfse-perfil-liberar.mjs SEG-NFSE-1401 <id da solicitação>`
   (o id aparece na tela da OS, no cartão da NFS-e) — ou pela tela de perfis, no perfil
   SEG-NFSE-1401, quadro "Liberação separada para produção": escolher a homologação **DPS 2/36 ·
   NFS-e 21**, escrever a justificativa (15 a 1000 caracteres) e marcar a confirmação.
2. **Abrir a OS.** OS › 298 › **Faturar** › aba NFS-e. O cartão mostra
   "Autorizada em homologação · DPS 2/36 · NFS-e nº 21".
3. **Conferir antes de clicar** (é o que o cliente vai receber):
   - Tomador **CREMER S.A.**, CNPJ 82.641.325/0001-18, Blumenau/SC.
   - Valor **58.000,00** e, no quadro verde, **você recebe 55.303,00**.
   - **Vencimento 60 dias** (uma parcela) e boleto.
   - **OC 148753** na descrição.
   - ISS 2.900,00 **não retido** (a Segau recolhe em Joinville).
4. **Emitir.** Botão **Emitir NFS-e real (produção)**. Confirmar no aviso. O retorno chega
   sozinho; o cartão passa a "AUTORIZADA · NFS-e REAL" com número, chave e DANFSe.
5. **Enviar ao cliente.** Botão **Enviar por e-mail** (XML + DANFSe) ou baixar a DANFSe e o XML e
   mandar junto com o **boleto** de 60 dias. O título a receber nasce com o líquido de
   55.303,00.

> **NFS-e não aceita carta de correção de valor nem de retenção.** Errou valor, retenção ou
> tomador: o caminho é **substituir** (gera nota nova referenciando a errada) ou **cancelar** — em
> Joinville, até o último dia do mês de emissão. Por isso a conferência do passo 3 é o momento de
> parar, não depois.

## O que mudou no ERP nesta rodada (18/09/2026)

- **PIS e COFINS próprios na DPS**: `valor_pis` e `valor_cofins` passam a ir junto com as
  alíquotas; base = valor do serviço. A retenção continua em `tpRetPisCofins` + `valor_csll`
  (soma PIS+COFINS+CSLL retidos), como nas notas reais.
- **Texto legal da retenção**: sai a IN RFB 2.141/2023, entra **Lei 10.833/2003, arts. 30 e 31, e
  IN SRF 459/2004**, nos perfis 14.01, 14.06 e 17.09 (revisão registrada com justificativa).
  Diverge da resposta da contadora de 06/09/2026, que indicou a IN RFB 2.141/2023 — confirmar.
- **cIndOp 050102** quando não há destinatário distinto do tomador (era 050103). Vale para todo o
  grupo 0501, portanto também para o 14.06 e o 17.09; a obra (020201) não muda.
- **Tela Faturar NFS-e**: líquido em destaque com a conta em linguagem simples; legenda no ISS
  retido; código de serviço com legenda; campo de observação interna; pedido de compra
  obrigatório quando o cadastro do cliente exigir (a CREMER passou a exigir).
- **Cadastro do cliente**: caixa "Exige o número do pedido de compra (OC) no corpo da nota" e,
  na CREMER, "optante do Simples: não" (estava em branco e gerava aviso na nota).
