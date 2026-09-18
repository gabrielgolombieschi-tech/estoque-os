# OV-SEG-00012-026 — CHAVE PIZZATO (PBG/Portobello) — 18/09/2026

Uma NF-e de **R$ 3.777,40**: mercadoria 3.441,82 + IPI 9,75% (335,58). OC 1312773, valor fechado,
utilização "Aquisição de Mercadoria Insumos", entrega 02/10/2026.

| | |
| --- | --- |
| OV | OV-SEG-00012-026 (`ordens_servico.id` 365) · PBG S/A · orçado 3.777,40 |
| Item | 1828 · NG2D1D411AF30 · CHAVE DE SEGURANÇA COM TRAVA E ATUADOR PLÁSTICO · NCM 8536.50.90 · 1 UN |
| Importação | **Por conta e ordem**: NF-e **8509/1** da PRANA COMERCIO EXTERIOR (17.737.980/0001-02), 22/10/2024, natureza "REMESSA POR CONTA E ORDEM DE TERC.", CFOP 5949, IPI 9,75% destacado, `orig` 1, **DI 2422904512** desembaraçada no Porto de Itajaí em 18/10/2024 |
| Homologação | **NF-e 2/82**, cStat 100, protocolo 342260000955663, chave 42260913671448000189550020000000821390968555, 18/09/2026 14:38 |
| Produção | **Não emitida** |

## A decisão fiscal (Gabriel, 18/09/2026)

A nota sai com **CST 00, 12%, sem cBenef**, pelo perfil SEG-VENDA-TERCEIROS-SC-5102-O1-CST00.

Fundamento: destinação **insumo** para **contribuinte** → alíquota de 12% da **Lei 10.297/96, art.
19, III, "n"**. É alíquota, não benefício. A redução de base do Anexo 2, art. 7º, VII (cBenef
SC820006) só tem função quando a operação seria tributada a 17%.

Não foi criado perfil CST 20 de origem 1, e o cBenef não foi acrescentado ao perfil O1-CST00.

## O que mudou na trava do cBenef

Antes: NCM da lista de automação + CST 00 a 12% + sem cBenef = bloqueio.

Agora, `faltaCbenefAutomacaoSc` não bloqueia quando as quatro condições andam juntas
(`aliquota12PorDestinacaoSc`):

1. destinação que segue em operação tributada — **revenda, insumo ou consignação**;
2. destinatário **contribuinte**;
3. perfil **sem redução de base** (CST 00, sem percentual);
4. a nota **não traz cBenef** — quando traz, quem emitiu está declarando o benefício (alínea "a",
   12% direto sobre a base integral com a observação no documento) e nada muda.

Continua bloqueando: CST 20 ou qualquer redução de base sem cBenef; 12% em destinação de consumo
(manutenção, uso e consumo, ativo), inclusive pela exceção da OC; e 12% para não contribuinte.
Junto com a trava, o **texto do benefício também deixa de entrar** nas informações complementares
quando os 12% são alíquota — antes a nota podia sair afirmando base reduzida que não existia.

O **resolvedor de perfis não mudou**: para origem 2 ele continua escolhendo o perfil de automação
(CST 20 + SC820006), como na NF-e 2/15.

Onde está: `supabase/functions/_shared/fiscal/icms-sc-destinacao.ts` (regra),
`supabase/functions/_shared/nfe-payload.ts` (montador), `components/faturamento/OvNfeDraftsPanel.tsx`
(mesma checagem na conferência da tela), `scripts/test-nfe-pipeline.mjs` (os dois lados).

## Pergunta em aberto para a contadora

> **NCM da lista de automação (Anexo 2, art. 7º, VII) com destino insumo ou revenda a contribuinte:
> a nota sai com CST 00 a 12% pela alínea "n" da Lei 10.297/96, ou com CST 20 + redução de base +
> cBenef SC820006?**
>
> Hoje o ERP faz as duas coisas, conforme a origem da mercadoria: origem 1 (importada por nós) sai
> CST 00 a 12% sem código (esta OV); origem 2 sai CST 20 com SC820006 (NF-e 2/15, mesma peça, mesmo
> cliente). As duas chegam aos mesmos 12% efetivos e ao mesmo valor de nota. Falta o alinhamento
> sobre qual é a forma correta de declarar.

Histórico útil: a **NF-e 2/15** (produção, 11/09/2026) foi para a **PBG S/A** com CST 20, 17% e
redução de 29,412% (cBenef SC820006) e foi autorizada. A 2/13, mesma configuração e mesmo cliente,
foi cancelada em 11/09 — o motivo registrado é "Nota emitida sem o pedido de compra do cliente.
Será reemitida com a OC informada", **não** recusa do CST ou da alíquota. Não há registro de
recusa da Portobello por causa do CST 20.

## Como saiu a homologação (NF-e 2/82)

| Campo | Valor |
| --- | --- |
| natOp / CFOP / indFinal | VENDA MERCADORIA ADQ. REC. DE TERCEIROS / 5102 / 0 |
| item | CQ NG2D1D411AF30, NCM 8536.50.90, 1 UN × 3.441,82, **orig 1** |
| ICMS | CST **00**, vBC **3.441,82** (IPI fora), **12%**, vICMS **413,02**, **sem cBenef** |
| IPI | CST 50, cEnq 999, 9,75%, **vIPI 335,58** |
| PIS / COFINS | base 3.028,80 · 49,98 / 230,19 |
| IBS/CBS | base **2.748,63** |
| vNF | **3.777,40** (= OC 1312773) |
| Cobrança | dup 001 · 02/11/2026 · 3.777,40 (boleto, 45 dias) |
| Frete | modFrete 1 · TEDE · 1 volume |
| infCpl | "Destinação informada pelo destinatário: insumo de produção. Alíquota interna de ICMS de 12% - operação destinada a contribuinte do imposto - Lei 10.297/96, art. 19, III, "n", e Lei 17.878/2019 \| Pedido de compra do cliente: 1312773 \| Cod. cliente: 313852" |

Sem texto de benefício e sem cBenef, como a decisão determina.

## Modelo F30 × F31 (só relato, nada alterado)

| Entrada | Emitente | Data | Item | Modelo na descrição | Qtd | CFOP | DI |
| --- | --- | --- | --- | --- | ---: | --- | --- |
| 8509/1 | PRANA COMERCIO EXTERIOR | 22/10/2024 | **1828** | NG 2D1D411A-**F31** | 10 | 5949 | **2422904512** |
| 3801/1 | ELETRICA SEGAU (nota própria) | 31/08/2026 | **2065** (código 1744) | NG 2D1D411A-**F30** | 2 | 5102 | — |

A OV e a OC pedem o **F30**. O item 1828, que está na OV e foi marcado como importado por nós,
tem o código NG2D1D411AF30 no cadastro, mas a única entrada com DI ligada a ele é de **F31**. O
item 2065 é o F30 de verdade na descrição, porém sua entrada é uma nota emitida pela própria Segau
(CFOP 5102, sem DI) e o cadastro dele está com origem 2, sem equiparação.

**Confirmar antes da nota real**: se a peça que vai no caminhão é F30 ou F31, e se o vínculo do
item 1828 com a entrada F31 está correto. O vínculo não foi alterado.

## O que falta para a nota real

1. Revisar o perfil SEG-VENDA-TERCEIROS-SC-5102-O1-CST00 não é necessário (já revisado e liberado
   em 18/09), mas a **liberação é por homologação**: liberar o perfil para a NF-e 2/82.
2. Emitir a nota real pela tela da OV.
3. Antes disso, resolver o F30 × F31 acima.
