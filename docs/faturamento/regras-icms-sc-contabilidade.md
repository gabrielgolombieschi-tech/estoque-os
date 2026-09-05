# Regras de ICMS/SC da contabilidade — fonte para parametrização

Transcrição das regras recebidas da **Status Contabilidade** (documento
"Apresentação dos tributos incidentes no Lucro Real — ELÉTRICA SEGAU", criado
por Deise Dias em 24/11/2021), dos e-mails de cBenef obrigatório e da exigência
da PORTOBELLO. É a fonte de verdade para os perfis de operação; quando o código
divergir daqui, o código está errado.

## Onde cada operação é emitida

Definido em 04/09/2026. Importa para não generalizar a tela errada:

| Operação | Onde | Natureza / CFOP |
|---|---|---|
| **Revenda** de mercadoria de terceiros | NF-e da OV (tela atual) | VENDA MERCADORIA ADQ. REC. DE TERCEIROS · CFOP 5102 |
| **Industrialização** própria | pelas **OS** | 5.101 / 6.101 |
| Simples remessa, conserto, remessa para industrialização, venda de ativo, conta e ordem | lugar próprio, ainda a criar | 5.124, 5.551, 5.901, 5.915/6.915, 5.916/6.916, 6.902, 6.923 |

A tela da OV já recusa por construção qualquer outra natureza e qualquer CFOP
diferente de 5102 (`f.fn_solicitacao_nfe_salvar_conferencia_2026`). Os cBenef por
CFOP da seção "cBenef obrigatório" pertencem aos fluxos de baixo — **não**
parametrizar na tela de revenda.

Não confundir com a **destinação**, na seção seguinte: aquela é o que o *cliente*
faz com a mercadoria, e existe dentro da revenda.

## Alíquota interna de ICMS em SC: 12% ou 17%

Não é característica do produto — é da **destinação que o adquirente dá à
mercadoria**:

| Destinação | Alíquota | Base legal |
|---|---|---|
| Destinatário **contribuinte** que vai revender / industrializar | **12%** | Lei 10.297/96, art. 19, III, "n" |
| **Uso e consumo** ou **ativo imobilizado** do adquirente | **17%** | RICMS/SC, art. 26, I |
| Destinatário **não contribuinte** | **17%** | RICMS/SC, art. 26, I |

> "Nas operações internas aplicar 12% quando o destinatário for revender, ou
> aplicar 17% se for destinatário final."

### O que a PORTOBELLO exige

Carta do cliente, citando a **Lei 17.878/2019**, vigente desde 01/03/2020: nas
saídas internas destinadas a contribuintes do ICMS a alíquota é de **12%**, e
ela se aplica às utilizações informadas nas OCs deles:

- Aquisição de mercadoria em consignado
- Aquisição de mercadoria para manutenção
- Aquisição de mercadoria insumos
- Aquisição de mercadoria para revenda

> "Alíquotas destacadas divergentes das mesmas, iremos recusar a NF até a
> correção da mesma."

**Tensão a resolver com o contador:** o documento de 2021 põe *uso e consumo* em
17%, e "manutenção" é discutível como uso e consumo. A PORTOBELLO classifica
manutenção como 12%. A destinação vem informada na OC do cliente, então o
sistema deve **registrar a destinação declarada** e derivar a alíquota dela — sem
adivinhar.

## Interestadual

Tabela origem × destino da Resolução do Senado nº 22/89 (SC como origem): **7%**
para AC, AL, AM, AP, BA, CE, DF, ES, GO, MA, MT, MS, PA, PB, PE, PI, RN, RO, RR,
SE, TO; **12%** para MG, PR, RS, RJ, SP.

Mercadoria **importada** ou com Conteúdo de Importação **acima de 40%**: **4%**,
independentemente das UFs envolvidas (Resolução do Senado nº 13/2012).

## Reduções de base de cálculo — automação, informática e telecomunicações

Base legal: **RICMS/SC-01, Anexo 2, Art. 7º, VII** · cBenef **SC820006** ·
redução de **29,412%** · somente operações **internas**.

| NCM | Descrição |
|---|---|
| 8536.49.00 | Equipamentos de automação, informática e telecomunicações: outros relés |
| 8536.50.90 | Equipamentos de automação, informática e telecomunicações: outros interruptores, seccionadores e comutadores |
| 8544.49.00 | Equipamentos de automação, informática e telecomunicações: outros condutores elétricos, para tensão não superior a 1.000 V |

**A alternativa autorizada (alínea "a" do inciso VII):**

> "Fica facultado aplicar diretamente o percentual de 12% sobre a base de cálculo
> integral, desde que o sujeito passivo aponha, no documento fiscal, a seguinte
> observação: 'Base de cálculo reduzida - produtos da indústria de automação,
> informática e telecomunicações'."

Então, para estes NCMs, há **dois caminhos legais e equivalentes**:

1. CST 20, base reduzida em 29,412%, alíquota 17% → ICMS efetivo 12%
2. CST 00, base integral, alíquota 12% — **exige** a observação acima no documento

O caminho 2 **não** é irregularidade: é a faculdade do regulamento. Nos dois
casos há benefício em uso, então cBenef SC820006 e a base legal em dados
adicionais são obrigatórios (ver seção seguinte).

**Cuidado:** NCM **8537.10.20** (controlador programável / PLC) **não está** na
lista de redução. Nele o 12% vem da Lei 10.297/96, art. 19, III, "n" — é
alíquota, não benefício. Nesse caso **não** há cBenef e **não** se põe a
observação de base reduzida.

## cBenef obrigatório

Duas datas, ambas já passadas:

- **01/07/2023** — os códigos abaixo passaram a ser obrigatórios.
- **03/02/2025** — a SEFAZ **rejeita** documento fiscal com qualquer benefício de
  ICMS (isenção, suspensão, redução de base, diferimento, crédito presumido) que
  não informe o **cBenef no campo do produto** e a **base legal em dados
  adicionais**.

| CFOP / NCM | Benefício | cBenef | Base legal (dados adicionais) |
|---|---|---|---|
| 5.124 | Diferimento — retorno de mercadoria recebida para conserto, reparo ou industrialização | SC830080 | RICMS/SC-01, Anexo 3, Art. 8º, X |
| 5.551 | Venda de ativo imobilizado | SC810192 | RICMS/SC-01, Anexo 2, Art. 35, I |
| 5.901 | Remessa para industrialização por encomenda | SC840007 | RICMS/SC-01, Anexo 2, Art. 27, I |
| 6.902 | Retorno de mercadoria utilizada na industrialização por encomenda | SC840008 | RICMS/SC-01, Anexo 2, Art. 27, II |
| 5.915 / 6.915 | Suspensão — remessa para conserto, reparo ou industrialização (retorno em 180 dias) | SC840007 | RICMS/SC-01, Anexo 2, Art. 27, I |
| 5.916 / 6.916 | Suspensão — retorno de mercadoria remetida para conserto (180 dias) | SC840008 | RICMS/SC-01, Anexo 2, Art. 27, II |
| 6.923 | Não-incidência — remessa por conta e ordem de terceiros, venda à ordem, armazém geral | SC800018 | RICMS/SC-01, Anexo 6, Art. 41 |
| NCM 8536.49.00, 8536.50.90, 8544.49.00 | Redução de base — saída interna de equipamentos de automação, informática e telecomunicações | SC820006 | RICMS/SC-01, Anexo 2, Art. 7º, VII |

No CFOP 5.124 o diferimento se aplica **somente à parcela da mão de obra**; o
valor acrescido relativo a mercadorias adquiridas e empregadas pelo próprio
estabelecimento é normalmente tributado.

## CFOP × CST de ICMS

| CFOP | Operação | CST |
|---|---|---|
| 5.101 / 6.101 | Venda de produção do estabelecimento | 00 |
| 5.102 / 6.102 | Venda de mercadoria adquirida ou recebida de terceiros | 00, ou 20 com redução de base |
| 5.901 / 6.901 | Remessa para industrialização por encomenda | ICMS 50 (suspenso) · IPI 55 (suspenso) |
| 5.915 | Remessa de mercadoria ou bem para conserto ou reparo | ICMS 50 (suspenso) · IPI 55 (suspenso) |
| 6.119 | Venda de mercadoria de terceiros entregue por conta e ordem do adquirente originário, em venda à ordem | 00, ou 20 com redução de base |

Para 5.901/6.901 e 5.915, as informações complementares devem trazer:

- ICMS suspenso, conforme o inciso I do art. 27 do Anexo 2 do Decreto nº 2.870/01 — RICMS-SC/01
- IPI suspenso, conforme o inciso VI do art. 43 do Decreto nº 7.212/10 — RIPI/10

## Tributos federais — Lucro Real

**Revenda e industrialização** (por NCM, iguais em 8537.10.20, 9403.20.00,
8536.20.00, 8536.49.00, 8536.50.90, 8544.49.00):

| PIS | COFINS | IRPJ | CSLL |
|---|---|---|---|
| 1,65% | 7,60% | 1,20% | 1,08% |

IPI: consultar TIPI.

**Serviços** (CNAE 4321-5/00 instalação e manutenção elétrica; 7119-7/04 perícia
técnica de segurança do trabalho):

| PIS | COFINS | IRPJ | CSLL | ISS |
|---|---|---|---|---|
| 1,65% | 7,60% | 4,80% | 2,88% | 5% |

- Instalação e manutenção elétrica: **não** há retenção de PIS/COFINS/CSLL.
- Perícia: retenção de **IRRF 1,5%** e **CRF 4,65%** (PIS 0,65%, COFINS 3,0%,
  CSLL 1%) sobre o valor do serviço. Dispensada quando o imposto retido for
  ≤ R$ 10,00 (Lei 9.430/96, art. 67; Lei 10.833/2003, art. 31, § 3º).
- O valor da retenção deve constar no documento fiscal (IN SRF 459/2004, art. 1º,
  § 10).

**PIS/COFINS — alíquota zero ou suspensão:** verificar antes se o adquirente é
habilitado em regime especial (PADIS, Decreto 6.233/2007 e Lei 11.484/2007),
se está na Zona Franca de Manaus ou Área de Livre Comércio, e se a receita é de
exportação.

**CST de PIS/COFINS na saída (regime não cumulativo):** 1 tributável com
alíquota básica · 6 alíquota zero · 9 com suspensão · 49 outras saídas.

## Base de cálculo do ICMS

**Integra** (RICMS/SC, art. 22): o montante do próprio imposto; seguros, juros e
demais importâncias pagas, recebidas ou debitadas, e descontos concedidos sob
condição; frete, quando o transporte é feito pelo próprio remetente ou por sua
conta e ordem e cobrado em separado.

**Não integra** (art. 23): o IPI, quando a operação entre contribuintes e
relativa a produto destinado a industrialização ou comercialização configurar
fato gerador dos dois impostos — **exceto** nas vendas a consumidor final, em que
o IPI **soma** à base do ICMS; os acréscimos financeiros de vendas a prazo a
consumidor final; e as bonificações em mercadorias.

## Vencimentos

| Tributo | Dia | Se cair em feriado ou fim de semana |
|---|---|---|
| ICMS | 10 | prorroga |
| ISS | 15 | antecipa |
| PIS, COFINS, IPI | 25 | antecipa |
| CSLL, IRPJ | 31 | antecipa |
