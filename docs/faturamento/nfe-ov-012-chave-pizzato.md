# OV-SEG-00012-026 — CHAVE PIZZATO (PBG/Portobello) — 18/09/2026

Venda de uma chave de segurança Pizzato importada por conta e ordem, para a Portobello, com a OC
1312773. A nota passou por duas leituras fiscais no mesmo dia; a segunda é a que vale.

| | |
| --- | --- |
| OV | OV-SEG-00012-026 (`ordens_servico.id` 365) · PBG S/A · orçado 3.777,40 |
| Item | 1828 · NG2D1D411AF30 · CHAVE DE SEGURANÇA COM TRAVA E ATUADOR PLÁSTICO · NCM 8536.50.90 · 1 UN |
| Importação | **Por conta e ordem**: NF-e **8509/1** da PRANA COMERCIO EXTERIOR (17.737.980/0001-02), 22/10/2024, natureza "REMESSA POR CONTA E ORDEM DE TERC.", CFOP 5949, IPI 9,75% destacado, `orig` 1, **DI 2422904512** desembaraçada no Porto de Itajaí em 18/10/2024 |

## Onde a nota está hoje

**Existe nota real, e ela está errada.** A NF-e **2/34** foi autorizada em produção em **18/09/2026
14:48:34** (protocolo 242260443480461, chave 4226 0913 6714 4800 0189 5500 2000 0000 3411 1562
8253), com mercadoria 3.441,82, IPI 335,58 e total 3.777,40, CST 00 a 12% sem cBenef.

Duas coisas mudaram depois dela:

1. **O IPI da OC é por fora.** Os 3.777,40 são o valor da mercadoria. Com IPI de 9,75% (368,30) a
   nota fecha em **4.145,70**, não em 3.777,40.
2. **O ICMS sai pelo benefício de automação**, não pela alíquota da alínea "n".

O cancelamento é do Gabriel, pela tela. A janela normal de cancelamento do ERP é de 24 horas da
autorização, ou seja, até **19/09/2026 14:48:34**; depois disso a SEFAZ rejeita com o código 501 e
o caminho passa a ser a NF-e de estorno (natureza 999). Estoque: a baixa de 1 UN do item 1828
ficou registrada em 18/09/2026 14:37, presa à OV e não à nota; o saldo do item é 12.

## As duas leituras fiscais do dia

**Primeira leitura, de manhã**: a OC seria valor fechado com IPI dentro, e os 12% viriam da
alíquota interna da Lei 10.297/96, art. 19, III, "n", com CST 00 e sem cBenef, porque alíquota não
é benefício. Foi assim que saíram a homologação **2/82** e a nota real **2/34**.

**Segunda leitura, à tarde** (a que vale): IPI por fora e ICMS pelo benefício do RICMS/SC-01,
**Anexo 2, art. 7º, VII**, com CST 20, 17% sobre base reduzida em 29,412% e **cBenef SC820006** —
os mesmos 12% de carga efetiva, declarados como redução de base.

A trava de cBenef ajustada na primeira leitura **continua valendo** e não atrapalha: ela só libera
os 12% sem código quando eles são alíquota, o que é o caso do perfil O1-CST00, não do perfil de
automação.

## O que mudou no ERP

**Preço** (migration `20260919130000`): a linha da OV voltou de 3.441,82 para **3.777,40**, igual
ao orçado, com o motivo gravado no histórico do item e no `audit_log`. O alerta de linhas contra
orçado fica limpo.

**Perfil novo** (migration `20260919140000`): `SEG-VENDA-TERCEIROS-SC-5102-O1-CST20-AUTOMACAO`,
espelho do perfil de origem 2 em todo o ICMS e nos NCMs elegíveis, mudando só a origem e o IPI.

| Campo | Valor |
| --- | --- |
| Origem | 1 |
| ICMS | CST 20 · 17% · redução 29,412% · base 70,588% · cBenef SC820006 |
| IPI | CST 50 · cEnq 999 · alíquota do produto/TIPI, não do perfil |
| NCMs elegíveis | 8536.49.00, 8536.50.90, 8544.49.00 |
| Destinações | revenda, insumo, manutenção, consignação |
| Estado | em revisão, produção desabilitada |

**Prioridade no resolvedor: nada foi alterado.** A regra de NCM já existia desde 10/09/2026 e é por
origem. Um perfil com lista só vale para os NCMs da lista; o perfil genérico da **mesma origem** só
entra quando nenhum perfil com lista casa com o NCM da linha. Simulação contra o banco de produção:

| NCM | Origem | Destinação | Perfil escolhido |
| --- | ---: | --- | --- |
| 8536.50.90 | 1 | insumo | O1-CST20-AUTOMACAO (novo) |
| 8536.50.90 | 1 | manutenção | O1-CST20-AUTOMACAO (novo) |
| 8536.50.90 | 1 | uso e consumo | O1-CST00-17 |
| 8536.50.90 | 2 | insumo | O2-CST20-AUTOMACAO (como antes) |
| **8537.10.20** | 1 | insumo | **O1-CST00**, 12% (como antes, caso da NF-e 2/33) |

Atenção a uma consequência: com as destinações copiadas do perfil de origem 2, a **manutenção** de
um item da lista com origem 1 passa a sair pelo benefício, onde antes ia para o perfil de 17%.

## Como a nota deve sair

Mercadoria 3.777,40, IPI por fora, ICMS pela base reduzida, destinação insumo.

| Campo | Valor |
| --- | ---: |
| vProd | 3.777,40 |
| IPI (CST 50, cEnq 999, 9,75%) | 368,30 |
| vBC do ICMS (70,588%) | 2.666,39 |
| pICMS 17% → vICMS | 453,29 |
| PIS 1,65% / COFINS 7,6% sobre 3.324,11 | 54,85 / 252,63 |
| Base de IBS/CBS | 3.016,63 |
| **vNF** | **4.145,70** |

O IPI fica fora da base do ICMS porque a destinação segue em operação tributada.

## Evidência do benefício: de onde veio a lista de NCMs

A lista **não foi lida do texto do RICMS**. Ela tem três camadas, todas rastreáveis.

**A fonte de negócio** é a transcrição das regras da Status Contabilidade, documento "Apresentação
dos tributos incidentes no Lucro Real — ELÉTRICA SEGAU", de Deise Dias, 24/11/2021, guardada em
[regras-icms-sc-contabilidade.md](regras-icms-sc-contabilidade.md). É lá que estão a base legal, a
redução de 29,412%, o cBenef e os três NCMs.

**A primeira gravação em código** é a constante de redução de automação em
[icms-sc-destinacao.ts](../../supabase/functions/_shared/fiscal/icms-sc-destinacao.ts), no commit
f09febc de 05/09/2026, com os três NCMs, o cBenef, o percentual e o texto da observação.

**A gravação no banco** foi em 10/09/2026, disparada pela OV-SEG-00007-026 (Portobello, CHAVE SEG
FD2083, item 20973, mesmo NCM):

| Migration | Commit | O que fez |
| --- | --- | --- |
| `20260910190000` | 22f1dfe | criou a coluna de NCMs elegíveis e semeou os três NCMs, citando a constante do código como fonte |
| `20260910210000` | 621bb84 | criou o perfil de automação de origem 2 já com a lista |
| `20260910240000` | cf31cb8 | vinculou o registro de evidência |

O registro de evidência no banco (`f.perfil_operacao_evidencia`, id
`14c18511-450d-4156-b4c8-7bc018a8bfbb`, gravado em 10/09/2026 22:11) aponta como fonte a "NF-e 3607
(07/04/2026), conferida com a contabilidade da Segau", com um item observado, NCM 8536.50.90,
origem 2, CST 20, 17% e base reduzida. Nenhuma migration posterior mudou o conteúdo da lista.

Há ainda lastro empírico: a matriz de 63 combinações extraída de 483 DANFEs antigas já trazia os
NCMs com redução de base.

### Descrição: o que existe e o que não existe

**Não existe no ERP o número do item nem o texto literal da Seção XIX do Anexo 1**, para nenhum dos
três NCMs. Não há tabela que ligue NCM a item de lista.

O que existe é uma descrição **redigida pela contabilidade**, em
[regras-icms-sc-contabilidade.md](regras-icms-sc-contabilidade.md):

| NCM | Descrição registrada |
| --- | --- |
| 8536.49.00 | Equipamentos de automação, informática e telecomunicações: outros relés |
| 8536.50.90 | Equipamentos de automação, informática e telecomunicações: outros interruptores, seccionadores e comutadores |
| 8544.49.00 | Equipamentos de automação, informática e telecomunicações: outros condutores elétricos, para tensão não superior a 1.000 V |

Ou seja, o enquadramento do 8536.50.90 se apoia na palavra "comutadores", não em um item numerado
da lista. A regra escrita é que a lista é **fechada nesses três NCMs** e não se estende por
analogia, e que NCM novo da Seção XIX vai ao contador antes de qualquer parametrização.

Dois pontos que merecem atenção ao perguntar:

- Nas 61 notas reais de CFOP 5102 com o benefício, só apareceram 8536.49.00 e 8536.50.90. O
  **8544.49.00 nunca saiu com o benefício** em nota nossa, e o documento da matriz registra que ele
  "permanece bloqueado quando beneficiado", citando a COPAT 90/2025. Mesmo assim ele está na lista
  de elegíveis dos perfis.
- Nos XMLs antigos o cBenef **não vinha**. Ele foi parametrizado por decisão, depois que a SEFAZ
  passou a exigi-lo em 03/02/2025.

### A faculdade da alínea "a" não está em uso

O documento da contabilidade transcreve a alínea ao pé da letra: é facultado aplicar 12% direto
sobre a base integral, desde que o documento fiscal traga a observação "Base de cálculo reduzida -
produtos da indústria de automação, informática e telecomunicações".

**Nenhum perfil do ERP usa esse caminho.** Todos os perfis com cBenef SC820006 têm CST 20, 17% e
redução de 29,412%. O montador da nota suporta a alínea "a", mas não há perfil que a acione. As
duas formas, lado a lado, para uma mercadoria de 1.000,00:

| Campo | Como o ERP faz hoje | Pela alínea "a" |
| --- | --- | --- |
| CST | 20 | 00 |
| vBC | 705,88 | 1.000,00 |
| pRedBC | 29,412 | não vai |
| pICMS | 17% | 12% |
| vICMS | 120,00 | 120,00 |
| cBenef | SC820006 | SC820006 |
| infCpl | texto da base reduzida | mesmo texto, obrigatório |

O imposto é o mesmo. Muda só a forma de declarar, e nos dois casos o cBenef e a base legal nos
dados adicionais são obrigatórios.

## Perguntas para a contadora

1. **Qual é a forma correta de declarar os 12%?** NCM da lista de automação com destino insumo ou
   revenda a contribuinte: a nota sai com CST 00 a 12% pela alínea "n" da Lei 10.297/96, ou com CST
   20 mais redução de base e cBenef SC820006? Hoje o ERP faz as duas coisas conforme a origem da
   mercadoria, e as duas chegam ao mesmo valor de nota.
2. **A chave de segurança com trava (8536.50.90) atende à descrição do item da Seção XIX do Anexo
   1?** O ERP entrou na lista pelo código NCM de uma nota de fornecedor, sem conferir a descrição
   do item da lista, que ele não tem registrada.
3. **O benefício do art. 7º, VII alcança mercadoria importada?** A peça desta OV foi importada por
   conta e ordem e está com origem 1. O perfil que existia era de origem 2.
4. **Cliente que exige "12% na nota" com destino manutenção**: podemos usar o benefício com a
   faculdade da alínea "a", aplicando 12% direto sobre a base integral com o texto no documento, em
   vez da exceção de alíquota por ordem de compra que o ERP usa hoje?

## Modelo F30 × F31 (só relato, nada alterado)

| Entrada | Emitente | Data | Item | Modelo na descrição | Qtd | CFOP | DI |
| --- | --- | --- | --- | --- | ---: | --- | --- |
| 8509/1 | PRANA COMERCIO EXTERIOR | 22/10/2024 | **1828** | NG 2D1D411A-**F31** | 10 | 5949 | **2422904512** |
| 3801/1 | ELETRICA SEGAU (nota própria) | 31/08/2026 | **2065** (código 1744) | NG 2D1D411A-**F30** | 2 | 5102 | — |

A OV e a OC pedem o **F30**. O item 1828, que está na OV e foi marcado como importado por nós, tem
o código NG2D1D411AF30 no cadastro, mas a única entrada com DI ligada a ele é de **F31**. O item
2065 é o F30 de verdade na descrição, porém sua entrada é uma nota emitida pela própria Segau, sem
DI, e o cadastro dele está com origem 2, sem equiparação. O vínculo não foi alterado.

## Histórico: o que a Portobello já recebeu

A **NF-e 2/15** (produção, 11/09/2026) foi para a **PBG S/A** com CST 20, 17% e redução de 29,412%
com cBenef SC820006, e foi autorizada. A 2/13, mesma configuração e mesmo cliente, foi cancelada em
11/09 com a justificativa "Nota emitida sem o pedido de compra do cliente. Será reemitida com a OC
informada", ou seja, não é recusa do CST nem da alíquota. Não há registro de recusa da Portobello
por causa do CST 20.

## O que falta

1. **Gabriel cancela a NF-e 2/34** pela tela, dentro da janela de 24 horas.
2. **Gabriel salva a revisão fiscal** do perfil `SEG-VENDA-TERCEIROS-SC-5102-O1-CST20-AUTOMACAO`.
3. Homologar a nota nova com os valores da tabela acima.
4. Confirmar o F30 contra F31 antes da nota real.
