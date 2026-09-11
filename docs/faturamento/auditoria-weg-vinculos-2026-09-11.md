# Notas da WEG Tintas sem vinculação — 11/09/2026

## Vinculação executada — 11/09/2026

**15 notas vinculadas a 12 OS**, após autorização do usuário, totalizando **R$ 1.596.920,00 em valores brutos**. Gravação confirmada às 15:33:47 (Brasília), com nova consulta de conferência às 15:36:39. **Restam 12 notas sem vínculo**, incluindo a NFS-e 1729/2025, cuja OC na OS 42 ainda diverge.

| OS | Notas vinculadas nesta execução | Total já faturado da OS | Saldo bruto do pedido |
| ---: | --- | ---: | ---: |
| 41 | 3507 | R$ 125.000,00 | R$ 0,00 |
| 43 | 3518 | R$ 309.000,00 | R$ 0,00 |
| 44 | 1733/2025 | R$ 71.500,00 | R$ 0,00 |
| 45 | 3543 | R$ 210.500,00 | R$ 0,00 |
| 105 | 3630 | R$ 93.287,50 | R$ 0,00 |
| 131 | 1886/2026, 12 | R$ 168.300,00 | R$ 29.700,00 |
| 132 | 1856/2026, 15 | R$ 143.375,00 | R$ 11.625,00 |
| 135 | 1858/2026, 13 | R$ 210.375,00 | R$ 64.625,00 |
| 151 | 3623 | R$ 399.000,00 | R$ 0,00 |
| 214 | 1852/2026 | R$ 47.800,00 | R$ 0,00 |
| 228 | 1845/2026 | R$ 2.420,00 | R$ 0,00 |
| 242 | 3695 | R$ 12.390,00 | R$ 0,00 |

Os valores de faturamento incluem as notas já vinculadas anteriormente. A diferença pré-existente de R$ 0,50 entre a NF-e 3630 e o orçamento da OS 105 foi mantida. As OS 131, 132 e 135 continuam em andamento; vincular uma nota não encerra a OS.

Validação: simulação com rollback aprovada, aplicação em uma única transação e consulta independente após o commit. Os 15 documentos permaneceram emitidos, os 15 rateios receberam a OS correspondente, e os dados comerciais das 21 parcelas foram preservados. Valores e saldos dos títulos, vencimentos, status e dados cadastrais das OS permaneceram iguais aos anteriores; somente os vínculos e metadados de atualização foram alterados nessas tabelas. Os nove registros existentes na gestão de cobrança receberam os dados de faturamento por meio do trigger normal do sistema.

A rotina legada de AR redefine a primeira parcela ao alterar os_id_import. Os valores e vencimentos anteriores foram preservados dentro da mesma transação, sem desativar triggers, excluir registros ou modificar regras globais.

Conferência na aplicação publicada: filtro WEG carregado; carteira exibindo OS 131 a 85%, OS 132 a 93% e OS 135 a 77%; detalhes da OS 131 mostrando as quatro notas, incluindo as novas 1886/2026 e 12, total faturado de R$ 168.300,00 e saldo de R$ 29.700,00.

Evidências: backups/weg-oc-2026-09-11/vinculos-autorizados.json; aplicacao-2026-09-11T18-33-43-895Z.json; pos-vinculacao.json. O script operacional passou no ESLint.

---

**Histórico do levantamento anterior à vinculação:** as referências a notas sem vínculo nos trechos abaixo descrevem o estado inicial. O resultado atual é o registrado acima.

Consulta: 11/09/2026, 15:06:10 (horário de Brasília).
Emitente: Elétrica Segau Ltda (SEG), CNPJ 13.671.448/0001-89. Destinatário/tomador: WEG Tintas Ltda, CNPJ 60.621.141/0004-04 (cliente 43).

Foram encontrados 27 documentos emitidos sem OS vinculada. Todos contêm uma OC no XML ou na discriminação. Há 15 correspondências exatas e únicas com o pedido cadastrado em uma OS da mesma empresa; 12 notas dependem de revisão. Nenhum vínculo ou registro foi alterado.

Valor bruto das 27 notas: **R$ 1.856.662,62**. Das 15 correspondências exatas: **R$ 1.596.920,00**.

Os valores brutos de NFS-e vêm de ValorServicos/vServ. A coluna “valor_total cadastrado” preserva o valor gravado no documento; em parte das notas importadas ele corresponde ao líquido após retenções. Essa diferença não impede a identificação da OC, mas os dois valores não devem ser confundidos ao conferir faturamento.

## Notas das OS mostradas na imagem

| OS | OC nas observações | Nota | Série | Emissão | Valor bruto | valor_total cadastrado |
| ---: | --- | --- | --- | --- | ---: | ---: |
| 131 | 4518161886 | NFS-e 1886/2026 | A1 | 03/07/2026 | R$ 69.300,00 | R$ 69.300,00 |
| 131 | 4518161886 | NFS-e 12 | 70000 | 03/08/2026 | R$ 29.700,00 | R$ 27.529,00 |
| 132 | 4518419554 | NFS-e 1856/2026 | A1 | 08/06/2026 | R$ 55.180,00 | R$ 51.593,30 |
| 132 | 4518419554 | NFS-e 15 | 70000 | 03/08/2026 | R$ 13.717,50 | R$ 12.714,22 |
| 135 | 4518028694 | NFS-e 1858/2026 | A1 | 08/06/2026 | R$ 105.875,00 | R$ 98.993,12 |
| 135 | 4518028694 | NFS-e 13 | 70000 | 03/08/2026 | R$ 52.250,00 | R$ 48.642,50 |

Total das seis notas: **R$ 326.022,50 brutos**; soma de valor_total cadastrado: **R$ 308.772,14**.

As descrições confirmam o serviço das OS: movimentação mecânica na OS 131; proteções mecânicas NR12 das extrusoras na OS 132; serviços de elétrica na OS 135.

- OS 139 / OC 4518572701: nenhuma nota emitida pendente com essa OC. A NFS-e 1843/2026, de 21/05/2026, já está vinculada à OS 139 no banco consultado: R$ 87.500,00 brutos; R$ 81.812,50 em valor_total. A imagem mostra 0%, mas esse não é o estado do vínculo encontrado na consulta.
- OS 143 / OC 4518557106: nenhuma nota emitida pendente com essa OC. As NFS-e 1865/2026, 14 e 47 já estão vinculadas.

## Outras correspondências exatas

| OS | Descrição da OS | OC | Nota | Emissão | Valor bruto | Observação |
| ---: | --- | --- | --- | --- | ---: | --- |
| 44 | AUTOMAÇÃO ELEVADOR EXISTENTE - PENEIRA | 4518071327 | NFS-e 1733/2025 | 15/12/2025 | R$ 71.500,00 | OC exata; OS já marcada faturada. |
| 41 | ESTAÇÃO DE DESCARGA DE PRÉ MIX | 4517837989 | NF-e 3507 | 15/12/2025 | R$ 125.000,00 | OC exata; OS já marcada faturada. |
| 43 | EQUIPAMENTO DE MISTURA - DRYBLEND | 4518043005 | NF-e 3518 | 18/12/2025 | R$ 309.000,00 | OC exata; OS já marcada faturada. |
| 45 | SUPORTE PARA PENEIRA RUSSELL | 4517978499 | NF-e 3543 | 10/02/2026 | R$ 210.500,00 | OC exata; OS já marcada faturada. |
| 151 | ESTAÇÕES DE DESCARGA PREMIX (MENORES - 7 UNI) | 4518505390 | NF-e 3623 | 27/04/2026 | R$ 399.000,00 | OC exata; OS já marcada faturada. |
| 105 | SISTEMA DE AGUA GELADA | 4518321265 | NF-e 3630 | 30/04/2026 | R$ 93.287,50 | Nota R$ 0,50 acima do orçamento cadastrado (R$ 93.287,00). |
| 228 | ALTERAÇÃO PE ESTEIRA | 4518571670 | NFS-e 1845/2026 | 25/05/2026 | R$ 2.420,00 | OC exata; OS já marcada faturada. |
| 214 | 2 PREMIX MAIOR | 4518675436 | NFS-e 1852/2026 | 01/06/2026 | R$ 47.800,00 | OC exata; OS já marcada faturada. |
| 242 | SUPORTE PARA ELEVAÇÃO DE EXTRUSORA | 4518901806 | NF-e 3695 | 12/06/2026 | R$ 12.390,00 | OC exata; OS já marcada faturada. |

As nove OS dessa tabela já estão marcadas como faturadas, embora essas notas estejam sem vínculo no documento fiscal. A correspondência foi estabelecida pelo número da OC; o status da OS, isoladamente, não foi usado como prova.

## Notas com OC sem correspondência exata

| Nota | Emissão | OC na nota | Valor bruto | Descrição / conferência necessária |
| --- | --- | --- | ---: | --- |
| NF-e 3465 | 07/11/2025 | 4517453040 | R$ 57.541,02 | SUPORTE PENEIRA RUSSELL - OBRA DE ACO. Pedido confirmado na imagem do portal enviada pelo usuário; sem OS com essa OC no cadastro consultado. |
| NFS-e 1729/2025 | 12/12/2025 | 4517924267 | R$ 82.500,00 | Pedido 4517924267 confirmado na imagem do portal. Possível OS 42, cadastrada com 4517924567: um dígito divergente e orçamento igual ao valor bruto da nota. Forte indício de erro de digitação; conferir o conteúdo do pedido para confirmar a OS. |
| NFS-e 1730/2025 | 12/12/2025 | 4518180628 | R$ 86.630,00 | Adequação - Linhas 2025. Pedido confirmado na imagem do portal enviada pelo usuário; sem OS com essa OC no cadastro consultado. |
| NFS-e 1784/2026 | 16/03/2026 | 4518386375 | R$ 2.900,00 | SERVIÇOS DE CONSERTO DE ELEVADOR DE PENEIRA. PEDIDO DE COMPRA: 4518386375. VENCIMENTO: 14 DDL. "NÃO HÁ INCIDÊNCIA DAS RETENÇÕES FEDERAIS CONFORME IN SRF N° 459/2004". |
| NF-e 3610 | 10/04/2026 | 4518637517 | R$ 486,00 | APARELHO DE SINALIZACAO - COLUNA LUMINOSA VERMELH SONORO TUBO DE ALUMINIO COM BASE DOBRAVEL 24VCA - XVGB1SMA |
| NF-e 3654 | 21/05/2026 | 4518781925 | R$ 1.164,00 | REDUCAO INOX 250 PARA 200MM |
| NF-e 3655 | 21/05/2026 | 4518410893 | R$ 11.500,00 | FUSO DE ELEVADOR |
| NF-e 3656 | 25/05/2026 | 4518540956 | R$ 975,51 | CONJUNTO DE REDUCOES EM INOX |
| NF-e 3663 | 29/05/2026 | 4518687806 | R$ 6.695,46 | VALVULA DE SEGURANCA ROSCA 3/8 PARTIDA PROG |
| NF-e 3664 | 29/05/2026 | 4518610645 | R$ 4.900,63 | ESPACADOR MONTAGEM EM T;ESPACADOR PARA MONTAGEM EM T;VALVULA DE SEGURANCA ROSCA 1/2 PARTIDA PROG;VALVULA MANUAL ON OFF ROSCA 3/8 |
| NF-e 3666 | 01/06/2026 | 4518800843 | R$ 1.750,00 | JUNTA DE BORRACHA PARA PENEIRA VIBRATORIA |
| NF-e 3667 | 01/06/2026 | 4518749338 | R$ 2.700,00 | VALVULA MANUAL ON OFF ROSCA 1/2;VALVULA RETENCAO PILOTADA ROSCA 3/8 TUBO |

As 12 OCs acima também foram procuradas no pedido, nas observações e na descrição de todas as OS/OVs da mesma empresa, sem correspondência exata. A semelhança da descrição, sozinha, não confirma um vínculo.

## Complemento: pedidos nas imagens do portal WEG

Após o levantamento inicial, o usuário enviou duas imagens com 20 pedidos, dos quais 14 começam com 4517. O cruzamento abaixo usa os documentos da consulta de 11/09/2026 às 15:06:10. As imagens confirmam a existência e o número do pedido; não exibem os itens ou o valor contratado.

| Pedido 4517 confirmado no portal | Serial ME | Envio no portal | Nota sem vínculo localizada | Valor bruto | Correspondência com OS |
| --- | --- | --- | --- | ---: | --- |
| 4517924267 | 58118851 | 16/10/2025 | NFS-e 1729/2025 | R$ 82.500,00 | Forte candidata: OS 42, atualmente cadastrada com 4517924567. |
| 4517453040 | 56189817 | 27/06/2025 | NF-e 3465 | R$ 57.541,02 | Nenhuma OS com essa OC no cadastro consultado. |
| 4517837989 | 57988038 | 09/10/2025 | NF-e 3507 | R$ 125.000,00 | OS 41: correspondência exata. |
| 4517978499 | 58593579 | 11/11/2025 | NF-e 3543 | R$ 210.500,00 | OS 45: correspondência exata. |

O pedido **4517924267** coincide entre a imagem do portal e a discriminação da NFS-e 1729. A divergência está na referência cadastrada na OS 42 (**4517924567**). O orçamento da OS é R$ 82.500,00 e sua descrição é “FABRICAÇÃO E INSTALAÇÃO DE SUPORTES, PLATAFORMA E BANCADAS”; a nota descreve “Fornecimento - Pacote Caldeiraria”. O próximo dado para confirmar essa OS é o conteúdo do pedido no portal.

A NF-e **3465**, embora também descreva suporte para peneira Russell, cita o pedido **4517453040**, de junho de 2025. A OS **45** e a NF-e **3543** correspondem a outro pedido, **4517978499**, enviado em novembro de 2025. A coincidência do nome do equipamento não permite tratar os dois pedidos como uma única OS.

Os outros dez pedidos 4517 visíveis nas imagens não têm nota emitida com a respectiva OC no conjunto de documentos consultado: **4517941936, 4517704148, 4517763769, 4517699536, 4517784847, 4517698602, 4517596027, 4517652412, 4517426178 e 4517160792**. Isso não determina se há notas fora do acervo importado.

A primeira imagem também confirma pedidos 4518 relevantes: **4518180628 → NFS-e 1730/2025**, sem OS identificada; **4518071327 → NFS-e 1733/2025 → OS 44**; **4518043005 → NF-e 3518 → OS 43**; e **4518161886 → OS 131**, incluindo as notas pendentes já listadas acima.

Os totais do levantamento original permanecem: 15 correspondências exatas com OS e 12 notas que precisam de revisão. O portal acrescenta evidência para a OS 42, sem transformar a referência divergente em correspondência exata. Nenhum cadastro ou vínculo foi alterado.

## Evidências e identificação completa das 15 correspondências

### NFS-e 1733/2025 → OS 44

Número completo: 202500000001733. Série: A1. Documento fiscal: `c5ede672-9b42-43f0-9923-815b4bfe02bb`. ID interno da OS: `44`.
Campo consultado: discriminação do serviço (Discriminacao/xDescServ).

> Adequação do Suporte da Peneira 55% mão de obra 45% material Número do pedido: 4518071327 Vencimento: 28 DDL

### NF-e 3507 → OS 41

Número completo: 3507. Série: 1. Documento fiscal: `dc283f5d-353f-4adb-9378-945f260bf852`. ID interno da OS: `41`.
Campo consultado: informações complementares da NF-e (infCpl).

> VALOR APROXIMADO DOS TRIBUTOS: 21250,00. PEDIDO DE COMPRA 4517837989.

### NF-e 3518 → OS 43

Número completo: 3518. Série: 1. Documento fiscal: `43c7fa9e-974d-4f56-8f63-cba979bdcb6b`. ID interno da OS: `43`.
Campo consultado: informações complementares da NF-e (infCpl).

> VALOR APROXIMADO DOS TRIBUTOS: 52530,00. PEDIDO DE COMPRA 4518043005

### NF-e 3543 → OS 45

Número completo: 3543. Série: 1. Documento fiscal: `d8c692af-8af9-4a93-9575-8c0d49122afb`. ID interno da OS: `45`.
Campo consultado: informações complementares da NF-e (infCpl).

> VALOR APROXIMADO DOS TRIBUTOS: 35785,00. PEDIDO DE COMPRA 4517978499.

### NF-e 3623 → OS 151

Número completo: 3623. Série: 1. Documento fiscal: `fd3ac945-86cd-4d54-93ef-50b29d3211f5`. ID interno da OS: `170`.
Campo consultado: informações complementares da NF-e (infCpl).

> VALOR APROXIMADO DOS TRIBUTOS: 67830,00. PEDIDO DE COMPRA 4518505390

### NF-e 3630 → OS 105

Número completo: 3630. Série: 1. Documento fiscal: `65ebc8dd-d9b7-4728-a8ba-7115ca90b36f`. ID interno da OS: `124`.
Campo consultado: informações complementares da NF-e (infCpl).

> VALOR APROXIMADO DOS TRIBUTOS: 15858,88. PEDIDO DE COMPRA 4518321265

### NFS-e 1845/2026 → OS 228

Número completo: 202600000001845. Série: A1. Documento fiscal: `7083aa7f-149d-4b6b-a85a-a5e27d05d040`. ID interno da OS: `227`.
Campo consultado: discriminação do serviço (Discriminacao/xDescServ).

> SERVIÇO PARA ELEVAÇÃO DA ESTEIRA PEDIDO: 4518571670 VENCIMENTO: 28 DDL

### NFS-e 1852/2026 → OS 214

Número completo: 202600000001852. Série: A1. Documento fiscal: `e1afa4ed-d7bf-42f3-8e75-c59ee7e7b215`. ID interno da OS: `213`.
Campo consultado: discriminação do serviço (Discriminacao/xDescServ).

> PEDIDO DE COMPRA 4518675436 ALTERAÇÃO EM DUAS ESTAÇÃO DE DESCARGA - PREMIX MAIOR

### NFS-e 1856/2026 → OS 132

Número completo: 202600000001856. Série: A1. Documento fiscal: `7f930fc0-4725-4dd4-bcf7-829764fd1420`. ID interno da OS: `151`.
Campo consultado: discriminação do serviço (Discriminacao/xDescServ).

> FABRICAÇÃO E INSTALAÇÃO DAS PROTEÇOES MECÂNICAS NR12 - EXTRUSORAS (parte 2) PEDIDO: 4518419554 VENCIMENTO: 28 DDL

### NFS-e 1858/2026 → OS 135

Número completo: 202600000001858. Série: A1. Documento fiscal: `a5ef35b2-316b-4e9b-8ff7-26af4b5d870a`. ID interno da OS: `154`.
Campo consultado: discriminação do serviço (Discriminacao/xDescServ).

> SERVIÇO DE ELETRICA PEDIDO DE COMPRA: 4518028694 VENCIMENTO: 28 DDL.

### NF-e 3695 → OS 242

Número completo: 3695. Série: 1. Documento fiscal: `45c16fbc-83df-4687-8e9a-3ffc35598c18`. ID interno da OS: `241`.
Campo consultado: informações complementares da NF-e (infCpl).

> VALOR APROXIMADO DOS TRIBUTOS: 2496,30. PEDIDO DE COMPRA 4518901806

### NFS-e 1886/2026 → OS 131

Número completo: 202600000001886. Série: A1. Documento fiscal: `b905be85-f43d-4c10-95b1-b050909bb95c`. ID interno da OS: `150`.
Campo consultado: discriminação do serviço (Discriminacao/xDescServ).

> SERVIÇO DE MÃO DE OBRA MECANICA E MONTAGEM (MOVIMENTAÇÃO MECANICA MAQUINA) PEDIDO DE COMPRA: 4518161886.

### NFS-e 12 → OS 131

Número completo: 12. Série: 70000. Documento fiscal: `dee707e8-f964-48e7-b466-28d1e4295ba1`. ID interno da OS: `150`.
Campo consultado: discriminação do serviço (Discriminacao/xDescServ).

> SERVIÇO DE MÃO DE OBRA MECANICA E MONTAGEM (MOVIMENTAÇÃO MECANICA MAQUINA) (parte 4) PEDIDO DE COMPRA: 4518161886. VENCIMENTO: 28 DDL.

### NFS-e 13 → OS 135

Número completo: 13. Série: 70000. Documento fiscal: `efb9aec3-7205-45bc-b9d8-dfb7d7d87620`. ID interno da OS: `154`.
Campo consultado: discriminação do serviço (Discriminacao/xDescServ).

> SERVIÇO DE ELETRICA (parte 3) PEDIDO DE COMPRA: 4518028694 VENCIMENTO: 28 DDL.

### NFS-e 15 → OS 132

Número completo: 15. Série: 70000. Documento fiscal: `eedf9ff7-2d15-44ba-bc48-0347248ea7ce`. ID interno da OS: `151`.
Campo consultado: discriminação do serviço (Discriminacao/xDescServ).

> FABRICAÇÃO E INSTALAÇÃO DAS PROTEÇOES MECÂNICAS NR12 - EXTRUSORAS (parte 4) PEDIDO: 4518419554 VENCIMENTO: 28 DDL

## Escopo e validação

Tenant: `3ced7cfa-efbb-4f0f-addc-2028f60d1ca7`. Empresa: `f0e74f49-a127-46b4-901b-f7b37e43c690`.
- Consulta ao banco remoto em transação REPEATABLE READ, READ ONLY, com filtro por tenant e empresa; nenhuma escrita remota.
- Conferidos os 54 documentos ativos (não excluídos) e os 54 XMLs desse cliente. Há 44 documentos com status EMITIDA, sendo 17 vinculados e 27 sem vínculo. Os dez restantes não estão no status EMITIDA e foram excluídos das propostas.
- A empresa tem 518 documentos de saída não excluídos. Foi feita uma busca complementar nos XMLs de documentos classificados com outro cliente, procurando o CNPJ da WEG Tintas e nomes WEG: nenhum documento adicional encontrado.
- As 34 OS/OVs da WEG foram cruzadas com as OCs; a busca complementar abrangeu também as demais OS/OVs do mesmo tenant e empresa.
- Não foram encontrados vínculos de OS na NF de origem nem nos rateios financeiros das 27 notas sem vínculo.
- Conferidos a unicidade dos documentos, o CNPJ do tomador/destinatário, a correspondência exata da OC, a identidade do cliente e os totais em centavos.
- Evidências locais: backups/weg-oc-2026-09-11/auditoria-weg-oc-2026-09-11.json e auditoria-weg-oc-analisada-2026-09-11.json.
