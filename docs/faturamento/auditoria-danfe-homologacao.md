# Auditoria da NF-e de homologação 2/8 — o que estava errado

Auditoria feita em 04/09/2026 sobre a NF-e **série 2, número 8**, autorizada em
homologação sob o protocolo 342260000900693, comparando o DANFE, o payload
enviado (`f.documento_fiscal_emissao.payload_enviado`), o **XML autorizado**
(`f.documento_fiscal_xml.xml_raw`) e o cadastro.

Chave: `42260913671448000189550020000000081026202994`.

## O que estava coerente

A chave decompõe exata: `42` (SC) · `2609` · `13671448000189` · `55` · `002` ·
`000000008` · `1` · cNF `02620299` · DV `4`. Emitente, IEs, códigos IBGE
(4209102 Joinville, 4218004 Tijucas), CEPs, `idDest 1`, CFOP 5102 e a UF de
destino são consistentes entre si. ICMS 547,61 = 12% de 4.563,40;
`vProd = vNF = 4.563,40`. PIS 75,30 e COFINS 346,82 estão no XML e
corretamente **não** aparecem no DANFE — o layout oficial não tem esses campos.
IPI `IPINT` CST 53 + `cEnq 999`, coerente com revenda. Volumes sem espécie,
marca e numeração, como na NF 3772 de produção. IBS/CBS da transição 2026
corretos: CBS 0,9% = 41,07 e IBS 0,1% = 4,56, com `IBSCBSTot`, sem integrar o
total da nota.

## Defeito 1 — a nota declarava pagamento em dinheiro (corrigido)

O payload nunca enviava o grupo YA (`pag`/`detPag`). O provedor preenchia o
default dele e o XML autorizado saiu com:

```xml
<pag><detPag><tPag>01</tPag><vPag>4563.40</vPag></detPag></pag>
```

`tPag 01` é **dinheiro**. Toda nota emitida por este sistema afirmava, num
documento fiscal, pagamento em espécie — inclusive em venda a prazo. Não havia
grupo `cobr`, e `condicao_pagamento` da solicitação estava nulo.

Corrigido pela migration `20260904140000_nfe_pagamento_confirmavel.sql`: a forma
de pagamento passou a ser confirmada na conferência, como frete e
transportadora, com colunas próprias, validação na RPC, pendência no
congelamento e presença no `operacao_snapshot`. Provado na NF-e 2/9
(protocolo 342260000901022):

```xml
<pag><detPag><indPag>1</indPag><tPag>15</tPag><vPag>4563.40</vPag></detPag></pag>
```

## Defeito 2 — o texto do benefício contradizia os campos (corrigido)

O XML da 2/8 trazia em `infCpl`:

> Base de cálculo reduzida - produtos da indústria de automação, informática e
> telecomunicações - RICMS-SC/01 - Anexo 2, art. 7º, VII

E, nos campos, o oposto:

```xml
<ICMS00><orig>2</orig><CST>00</CST><modBC>3</modBC>
  <vBC>4563.40</vBC><pICMS>12.0000</pICMS><vICMS>547.61</vICMS></ICMS00>
```

CST 00 é tributação integral, a base é a integral, não há `pRedBC` e não há
`cBenef`. A causa era a regra em `nfe-payload.ts`, que declarava o benefício
quando a alíquota interna era **menor que 17%**, independentemente de haver
redução. Alíquota menor não é benefício: quem afirma a redução é `pRedBC` +
`cBenef`. Corrigido — o texto agora só sai quando `reducao > 0`.

O valor do imposto é o mesmo pelos dois caminhos:
`4.563,40 × 12/17 × 17% = 547,61 = 4.563,40 × 12%`. O que mudava era a
declaração e o reporte da fruição do benefício.

## Defeito 3 — a evidência do perfil é circular (aberto)

O perfil `SEG-VENDA-TERCEIROS-SC-5102-O2-CST00` aponta como evidência a chave
`42260913671448000189550020000000011615133155` — que é a **NF-e 2/1 emitida por
este próprio sistema em homologação**, não uma nota real.
`base_reduzida_observada = false`, e a própria `leitura_operacional` registra
que a origem 2 foi definida por inferência, não observada. Homologação não
valida alíquota contra produto: autorizar ali não prova nada.

## RESOLVIDO em 04/09/2026 — era pergunta errada

O documento da Status Contabilidade (transcrito em
`regras-icms-sc-contabilidade.md`) mostrou que "12% ou 17% para o 8537.10.20"
não era uma escolha a fazer: **as duas alíquotas estão certas, em operações
diferentes.** Quem decide é a destinação que o adquirente dá à mercadoria —
12% para contribuinte que revende, industrializa, usa como insumo, manutenção ou
consignado (Lei 10.297/96, art. 19, III, "n", e Lei 17.878/2019); 17% para uso e
consumo, ativo imobilizado ou destinatário final (RICMS/SC, art. 26, I). Era por
isso que as notas reais desse NCM tinham 23 a 17% e 8 a 12%: destinações
diferentes, não incoerência.

Três consequências:

1. **O 12% do 8537.10.20 não é benefício** — é alíquota. Não leva cBenef nem
   texto de base reduzida. A correção do Defeito 2 estava certa **para este
   NCM**, mas errada como regra geral (ver abaixo).
2. **A redução de base é por NCM**, e só alcança 8536.49.00, 8536.50.90 e
   8544.49.00. O 8537.10.20 nunca esteve na lista.
3. **Faltava um campo.** O sistema tinha um único perfil interno, fixo em 12%:
   vender para uso e consumo sairia com alíquota errada. Implementado em
   `20260904170000_nfe_destinacao_mercadoria.sql` — destinação confirmada em cada
   nota, quatro perfis internos (12% e 17% × origem 0 e 2), e a destinação junto
   com a base legal da alíquota nas informações complementares. A PORTOBELLO
   recusa nota com alíquota divergente da utilização da OC, então a destinação
   **não** é herdada da nota anterior: a memória mostra o que a última usou, como
   sugestão visível, e a escolha é explícita.

Provado nas duas pontas, na mesma OV e no mesmo item:

| NF-e | Destinação | pICMS | vICMS | Perfil resolvido |
|---|---|---|---|---|
| 2/11 · protocolo 342260000901509 | REVENDA | 12% | 547,61 | `SEG-VENDA-TERCEIROS-SC-5102-O0-CST00` |
| 2/12 · protocolo 342260000901542 | USO_CONSUMO | 17% | 775,78 | `SEG-VENDA-TERCEIROS-SC-5102-O0-CST00-17` |

## Correção ao Defeito 2: a faculdade do Anexo 2, Art. 7º, VII

Eu chamei de contradição a nota que aplicava 12% sobre base integral com o texto
"base de cálculo reduzida". Para os NCMs **elegíveis** isso não é contradição: a
alínea "a" do inciso VII **faculta** aplicar 12% direto sobre a base integral,
*"desde que o sujeito passivo aponha, no documento fiscal"*, exatamente aquela
observação. Nesse caminho o texto é **obrigatório**, e o cBenef SC820006 também —
a SEFAZ rejeita benefício de ICMS sem código desde 03/02/2025.

Minha primeira correção amarrou o texto a `reducao > 0`, o que quebrou esse
caminho legal. A regra agora é por NCM elegível **com carga efetiva de 12%** —
nominal não serve, porque CST 20 a 17% com redução de 29,412% dá os mesmos 12%.
A 17% sobre base integral não há benefício em uso e o texto não sai.

## O que era a decisão sobre 12% ou 17% para o NCM 8537.10.20

Da evidência extraída das NF-e reais de agosto/2026
(`docs/faturamento/regras-nfe-63-combinacoes.csv`), separando por NCM:

| CFOP 5102 · NCM 8537.10.20 | Notas |
|---|---|
| origem 0 · CST 00 · **17%** · sem redução | 23 |
| origem 0 · CST 00 · **12%** · sem redução | 8 |
| CST 20 com base reduzida + `cBenef SC820006` | **0** |

O benefício (`pRedBC 29,4120`, `cBenef SC820006`, alíquota 17%) aparece em 61
notas do CFOP 5102, mas **somente** nos NCMs 8536.49.00 e 8536.50.90. Para o
8537.10.20 — o PLC — nenhuma nota real usou redução de base. Declarar CST 20
para este NCM afirmaria um benefício que o produto nunca recebeu na
escrituração da empresa.

Restam duas leituras possíveis, e a escolha é do contador:

1. **17% integral** (23 notas). Se o produto não é elegível ao Anexo 1, Seção
   XIX, esta é a alíquota interna cheia de SC e o caminho seguro.
2. **12%** (8 notas). Precisa de base legal declarada. Se vier do Anexo 2,
   art. 7º, VII, então a forma correta é CST 20 com `pRedBC` e `cBenef` — e aí
   a pergunta anterior volta: o 8537.10.20 é elegível?

Hoje o sistema emite 12% com CST 00 e origem 2 — a combinação de 8 notas
reais, exceto pela origem, que em todas as notas reais desse NCM é **0**.

## Número e série em produção

| | |
|---|---|
| Notas reais de saída da SEGAU | série **1**, até o número **3801** (31/08/2026) |
| NF 3772 (referência) | série 1 |
| Sistema em homologação | série **2**, números 1 a 9 |
| `c.empresa_fiscal.serie_nfe` | **2** — gravado e nunca lido por ninguém |

Até 04/09 o payload **não** enviava `serie` nem `numero`: quem numerava era o
contador da Focus, e o `serie_nfe` do cadastro não influenciava nada.

**Decisão de 05/09/2026:** o ERP emite na **série 2** também em produção. A
série 1 permanece com o emissor antigo, que fica como backup até o fim das
implantações de NF; depois disso, se não houver problema fiscal, tudo segue na
série 2. Para isso o payload passou a enviar `serie` lido do snapshot do
emitente (`c.empresa_fiscal.serie_nfe`, migration `20260905110000`); a
ausência vira pendência de cadastro. O `numero` continua sob controle da Focus,
que numera por série; a série 2 de produção começa em 1, sem colidir com a
sequência 1..3801 da série 1.

## Defeito 4 — homologação contava como faturamento (corrigido)

As emissões de homologação ficam em `nfe_status = 'RASCUNHO'` de propósito:
`f.fn_nfe_aplicar_retorno` grava esse status, e só `fn_nfe_aplicar_retorno_producao`
grava `'EMITIDA'`. Mas nada filtrava por isso, e as notas de teste apareciam:

- na tela `/faturamento/nfe`, misturadas com as notas reais de série 1;
- no **analítico de faturamento**, somando **R$ 41.070,60** de notas de teste
  como receita de agosto/setembro de 2026.

Critério aplicado nos dois lugares: entra `nfe_status = 'EMITIDA'`, ou
`'CANCELADA'` **com número** — cancelamento autorizado na SEFAZ é documento que
existiu (`f.fn_nfe_evento_registrar` mantém número e chave). Rascunho descartado
também vira `CANCELADA`, porém sem número, e fica de fora. NFS-e não usa
`nfe_status` (fica nulo) e segue pelo `nfse_status`.

Migration `20260904150000_faturamento_so_notas_emitidas.sql` e o filtro em
`NfeList.tsx`. Efeito medido no período de 01/08 a 30/09/2026:

| | Documentos | Valor |
|---|---|---|
| NF-e que entram | 30 | R$ 673.642,58 |
| NFS-e (inalteradas) | 29 | R$ 481.818,74 |
| Homologação removida | 9 | R$ 41.070,60 |
| Rascunhos descartados removidos | 3 | R$ 13.690,20 |

## Pendências menores

- **`indPres 0`** ("não se aplica") é código de nota complementar ou de ajuste.
  Venda normal a distância deveria ser `9` (não presencial, outros).
- A `observacao` da solicitação ("Composição parcial da OV…") fica no banco e
  não vai para o `infCpl`.
- Destinatário sem telefone e IE da transportadora vazia (ambos opcionais).
- A formatação do DANFE (`Nº 8` em vez de `Nº 000.000.008`, `Série 2` em vez de
  `002`) é do gerador de PDF da Focus, não nosso: o PDF vem por URL do provedor.
