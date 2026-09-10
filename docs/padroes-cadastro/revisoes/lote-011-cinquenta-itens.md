# Lote 011 — 50 itens

APLICAÇÃO PARCIAL SOB AUTORIZAÇÃO CONDICIONAL D-047

Data da revisão: 2026-09-10. Escopo: tenant 3ced7cfa-efbb-4f0f-addc-2028f60d1ca7; empresa f0e74f49-a127-46b4-901b-f7b37e43c690.

50 Siemens, todos com grupo: 8 diferenciais residuais, 7 bornes/tampas/pente, 10 conexões de partida, 5 atuadores de segurança, 5 fontes SITOP, 6 relés de interface, 1 pente de interface, 3 conectores de relé de segurança, 2 monitores de rede, 1 painel BOP-2, 1 UPS CC e 1 conector RJ45. Alterações somente em nome e descrição complementar. 28 aplicados e verificados; 22 retidos sem alteração por dúvida técnica.

Grupo, código, fabricante, fornecedor, unidades, multiplicadores, preço, saldo e dados fiscais permanecem iguais. Cada comparação usa o cadastro real capturado, não um exemplo inventado.

D-047 autoriza aplicar referências claras sem novas rodadas de aprovação. Itens retidos exigem esclarecimento técnico, não simples aprovação em bloco. Antes/depois mantido para auditoria interna; apresentar ao usuário somente exceções.

## Conferência técnica e exceções

- Diferenciais 226/227/737/2135: ficha confirma 50Hz; 738/744/745/816: 60Hz. Não generalizar 50/60Hz. Polos totais 2P/4P, sem acrescentar neutro além desse total. Ui e capacidade de curto condicionada não são alimentação nem Icn de minidisjuntor. Conferir placa e adequação antes de instalar.
- Fontes 922/923/924: duas faixas de entrada, não faixa contínua. 925: faixa contínua; 926: trifásica. Potência/corrente nominais não são picos e exigem redução por temperatura conforme variante. UPS 1623 não recebe bateria incluída, autonomia fixa ou PROFINET por inferência.
- Revisões PARCIAIS: 944/1616 têm limites de condutor encordoado invertidos; 1618 tem cor conflitante e seção histórica não confirmada; 957 tem gerações de contator divergentes; 1619 tem 5A no resumo/corrente térmica e só 5mA na tabela de saída incompleta. Esses conflitos permanecem explícitos; a redação não certifica as lacunas.
- Outras lacunas de material, dimensões/compatibilidade ou fornecimento estão listadas individualmente. 1616: tabela declara função PEN = não; proposta é PE. Pente 1618 tem dez polos, apesar da foto ilustrativa com duas pontas. Não deduzir polímero de UL94 V0.
- Atuadores 256/346: 67mm versus 77mm. Atuador RFID 1628 não é chave completa e campo genérico de capa PVC não prova cabo incluído. Kit reversor não é ligação em série nem conjunto com contatores.
- Relés 3RQ3 descontinuados: referência, atividade e código preservados; não trocar por sucessor 3RQ4. Corrente térmica 6A não equivale a AC-15 6A. Monitores 686/2406 têm funções distintas e não são relés de segurança.
- Conector RJ45 2535: ficha menciona embalagem de 50 unidades. Nenhuma unidade, fator, quantidade, saldo ou preço será alterado. Relação embalagem/compra no ERP precisa de confirmação separada.
- Possíveis duplicidades: 2641/2698, 2642/2699 e 2643/2700 têm referências iguais após normalização. Somente 2641/2642/2643 neste lote; não fundir ou excluir cadastros.
- Fora do lote por HTTP 404: 242/1583/1585/1586/1588. Indisponibilidade da ficha não prova inexistência do produto. Pendências de lotes anteriores permanecem separadas.

28 referências claras aplicadas e verificadas pela autorização condicional D-047. Os 22 retidos continuam sem alteração; inclusive ID 776, cujo resumo e tabela divergem sobre bobina/compatibilidade. Somente o subconjunto claro foi incorporado ao padrão 1.35.0; não é aprovação humana individual dos 50.

## Antes e depois dos 50

| Nº | ID / código | Antes | Depois (ver situação) | Situação |
| ---: | --- | --- | --- | --- |
| 1 | 226<br>5SV56460 | INTERRUPTOR DIFERENCIAL RESIDUAL 3P+N 63A 300mA TIPO AC | INTERRUPTOR DIFERENCIAL RESIDUAL SENTRON 5SV5 4P 63A 300mA TIPO AC 400VCA 50Hz INSTANTÂNEO | Aplicado e verificado |
| 2 | 227<br>5SV46120 | INTERRUPTOR DIFERENCIAL RESIDUAL 1P+N 25A 300mA TIPO AC | INTERRUPTOR DIFERENCIAL RESIDUAL SENTRON 5SV4 2P 25A 300mA TIPO AC 230VCA 50Hz INSTANTÂNEO | Aplicado e verificado |
| 3 | 240<br>8WH60000AM00 | Borne plug-in de passagem 35mm² | BORNE DE PASSAGEM SENTRON IPO PLUG-IN 35mm² 2 CONEXÕES 1 NÍVEL CINZA 125A 1000V | RETIDO — NÃO APLICADO |
| 4 | 256<br>3SE50000AV071AK2 | ATUADOR RADIAL UNIVERSAL AJUSTÁVEL PARA CHAVE DE POSIÇÃO DE SEGURANÇA SERVIÇO PESADO 67mm | ATUADOR RADIAL UNIVERSAL SIRIUS 3SE5 HEAVY DUTY 67mm AJUSTE VERTICAL/HORIZONTAL FIXAÇÃO POR PARAFUSO | RETIDO — NÃO APLICADO |
| 5 | 346<br>3SE50000AV07 | ATUADOR RADIAL PARA CHAVE DE POSIÇÃO DE SEGURANÇA SERVIÇO PESADO | ATUADOR RADIAL UNIVERSAL SIRIUS 3SE5 HEAVY DUTY 77mm AJUSTE VERTICAL/HORIZONTAL FIXAÇÃO POR PARAFUSO | RETIDO — NÃO APLICADO |
| 6 | 686<br>3UG56161CR20 | RELÉ DE MONITORAMENTO DE REDE TRIFÁSICA PARA FALTA, SEQUÊNCIA E ASSIMETRIA DE FASE, FREQUÊNCIA, SOBRETENSÃO E SUBTENSÃO 90-690VCA | RELÉ DE MONITORAMENTO SIRIUS 3UG5 3F 90-690VCA 15-70Hz FALTA/SEQUÊNCIA/ASSIMETRIA/FREQUÊNCIA/SOBRE-SUBTENSÃO 2REV PARAFUSO | Aplicado e verificado |
| 7 | 735<br>3RA19211DA00 | CONEXAO 3RV S00S0 C 3RT S00 PARAFUSO | MÓDULO DE LIGAÇÃO ELÉTRICA/MECÂNICA SIRIUS 3P 3RV2.1/3RV2.2 S00/S0 A 3RT2.1 S00 CA/CC | RETIDO — NÃO APLICADO |
| 8 | 737<br>5SV46420 | INTERRUPTOR DIFERENCIAL RESIDUAL 3P+N 25A 300mA TIPO AC | INTERRUPTOR DIFERENCIAL RESIDUAL SENTRON 5SV4 4P 25A 300mA TIPO AC 400VCA 50Hz INSTANTÂNEO | Aplicado e verificado |
| 9 | 738<br>5SV53120MB | INTERRUPTOR DIFERENCIAL RESIDUAL 1P+N 25A 30mA TIPO AC | INTERRUPTOR DIFERENCIAL RESIDUAL SENTRON 5SV5 2P 25A 30mA TIPO AC 230VCA 60Hz INSTANTÂNEO | Aplicado e verificado |
| 10 | 744<br>5SV53440MB | INTERRUPTOR DIFERENCIAL RESIDUAL 3P+N 40A 30mA TIPO AC | INTERRUPTOR DIFERENCIAL RESIDUAL SENTRON 5SV5 4P 40A 30mA TIPO AC 400VCA 60Hz INSTANTÂNEO | Aplicado e verificado |
| 11 | 745<br>5SV53420MB | INTERRUPTOR DIFERENCIAL RESIDUAL 3P+N 25A 30mA TIPO AC | INTERRUPTOR DIFERENCIAL RESIDUAL SENTRON 5SV5 4P 25A 30mA TIPO AC 400VCA 60Hz INSTANTÂNEO | Aplicado e verificado |
| 12 | 776<br>3RA29211BA00 | CONEXAO 3RV S00S0 C 3RT S0 CC PARAFUSO | MÓDULO DE LIGAÇÃO ELÉTRICA/MECÂNICA SIRIUS 3P 3RV2.1/3RV2.2 A 3RT2.2 S0 CC CONEXÃO POR PARAFUSO | RETIDO — NÃO APLICADO |
| 13 | 781<br>3RA29112AA00 | CONEXAO 3RV S00 C 3RT S00 MOLA | MÓDULO DE LIGAÇÃO ELÉTRICA/MECÂNICA SIRIUS 3P 3RV2011 A 3RT201 S00 CA/CC CONEXÃO POR MOLA | Aplicado e verificado |
| 14 | 789<br>3RA29232AA1 | JOGO DE MONTAGEM PARA REVERSÃO DE CONTATORES COM CONEXÃO POR PARAFUSO | KIT DE LIGAÇÃO PARA REVERSÃO SIRIUS 3P S0 COM INTERTRAVAMENTO MECÂNICO CONEXÃO POR PARAFUSO | Aplicado e verificado |
| 15 | 816<br>5SV43470MB | INTERRUPTOR DIFERENCIAL RESIDUAL 3P+N 80A 30mA TIPO AC | INTERRUPTOR DIFERENCIAL RESIDUAL SENTRON 5SV4 4P 80A 30mA TIPO AC 400VCA 60Hz INSTANTÂNEO | Aplicado e verificado |
| 16 | 821<br>3RQ31182AM00 | RELÉ DE INTERFACE COM RELÉ ENCAIXÁVEL 1 REVERSÍVEL 24VCC CONEXÃO POR MOLA | RELÉ DE INTERFACE SIRIUS 3RQ3 ENCAIXÁVEL 1REV ENTRADA 24VCC AC-15 3A EM 250VCA DC-13 1A EM 24VCC CONEXÃO POR MOLA PUSH-IN | Aplicado e verificado |
| 17 | 824<br>3RQ39010D | PENTE DE CONEXÃO 16 POLOS PARA RELÉS DE INTERFACE | PENTE DE LIGAÇÃO SIRIUS 3RQ3/3RS7 16 POLOS ALIMENTAÇÃO MÁXIMA 6A | RETIDO — NÃO APLICADO |
| 18 | 922<br>6EP33323SB000AX0 | FONTE DE ALIMENTAÇÃO 24VCC 3A ENTRADA MONOFÁSICA | FONTE ESTABILIZADA SITOP PSU4200 SAÍDA 24VCC 3A 72W ENTRADA 1F 100-120/200-240VCA 50/60Hz | Aplicado e verificado |
| 19 | 923<br>6EP33333SB000AX0 | FONTE DE ALIMENTAÇÃO 24VCC 5A ENTRADA MONOFÁSICA | FONTE ESTABILIZADA SITOP PSU4200 SAÍDA 24VCC 5A 120W ENTRADA 1F 100-120/200-240VCA 50/60Hz | Aplicado e verificado |
| 20 | 924<br>6EP33343SB000AX0 | FONTE DE ALIMENTAÇÃO 24VCC 10A ENTRADA MONOFÁSICA | FONTE ESTABILIZADA SITOP PSU4200 SAÍDA 24VCC 10A 240W ENTRADA 1F 100-120/200-240VCA 50/60Hz | Aplicado e verificado |
| 21 | 925<br>6EP33363SB000AX0 | FONTE DE ALIMENTAÇÃO 24VCC 20A ENTRADA MONOFÁSICA | FONTE ESTABILIZADA SITOP PSU4200 SAÍDA 24VCC 20A 480W ENTRADA 1F 120-240VCA 50/60Hz | Aplicado e verificado |
| 22 | 926<br>6EP34343SB000AX0 | FONTE DE ALIMENTAÇÃO 24VCC 10A ENTRADA TRIFÁSICA | FONTE ESTABILIZADA SITOP PSU4200 SAÍDA 24VCC 10A 240W ENTRADA 3F 400-500VCA 50/60Hz | Aplicado e verificado |
| 23 | 927<br>3RA29132AA1 | JOGO DE MONTAGEM PARA REVERSÃO DE CONTATORES COM CONEXÃO POR PARAFUSO | KIT DE LIGAÇÃO PARA REVERSÃO SIRIUS 3P S00 COM INTERTRAVAMENTO MECÂNICO CONEXÃO POR PARAFUSO | Aplicado e verificado |
| 24 | 928<br>3RA29132AA2 | JOGO DE MONTAGEM PARA REVERSÃO DE CONTATORES COM CONEXÃO POR MOLA | KIT DE LIGAÇÃO PARA REVERSÃO SIRIUS 3P S00 COM INTERTRAVAMENTO MECÂNICO CONEXÃO POR MOLA | Aplicado e verificado |
| 25 | 944<br>8WH60000AF00 | Borne plug-in de passagem 2 condutores 2,5mm² | BORNE DE PASSAGEM SENTRON IPO PLUG-IN 2,5mm² 2 CONEXÕES 1 NÍVEL CINZA 24A 800V | RETIDO — NÃO APLICADO |
| 26 | 957<br>3RA19111AA00 | CONEXAO 3RV S00 C/ 3RT S00 AC/DC (1UNID) | MÓDULO DE LIGAÇÃO ELÉTRICA/MECÂNICA SIRIUS 3P S00 PARA 3RV1011 E 3RT2.1/3RW301 CA/CC | RETIDO — NÃO APLICADO |
| 27 | 973<br>3RA29261A | CONECTOR PARA MONTAGEM EM SÉRIE DE CONTATORES | MÓDULO DE LIGAÇÃO EM SÉRIE SIRIUS 3P PARA 2 CONTATORES 3RT202 S0 CONEXÃO POR PARAFUSO | Aplicado e verificado |
| 28 | 977<br>8WH60000AG00 | Borne plug-in de passagem 2 condutores 4mm² | BORNE DE PASSAGEM SENTRON IPO PLUG-IN 4mm² 2 CONEXÕES 1 NÍVEL CINZA 32A 800V | RETIDO — NÃO APLICADO |
| 29 | 978<br>8WH90031GA00 | Tampa final para borne 4mm² | TAMPA FINAL SENTRON PARA BORNE DE PASSAGEM POR MOLA 4mm² CINZA ESPESSURA 2,2mm | RETIDO — NÃO APLICADO |
| 30 | 1002<br>3RA29161A | CONECTOR PARA MONTAGEM EM SÉRIE DE 2 CONTATORES | MÓDULO DE LIGAÇÃO EM SÉRIE SIRIUS 3P PARA 2 CONTATORES 3RT201 S00 CONEXÃO POR PARAFUSO | Aplicado e verificado |
| 31 | 1003<br>3RA29212AA00 | CONEXAO 3RV S0 C 3RT S0 MOLA | MÓDULO DE LIGAÇÃO ELÉTRICA/MECÂNICA SIRIUS 3P 3RV2.21 A 3RT2.2 S0 CA/CC CONEXÃO POR MOLA | Aplicado e verificado |
| 32 | 1088<br>6SL32550AA004CA1 | PAINEL DE OPERAÇÃO BOP-2 PARA INVERSOR SINAMICS G120 | PAINEL DE OPERAÇÃO SINAMICS BOP-2 LCD MONOCROMÁTICO 70×106,85×19,6mm IP55 | RETIDO — NÃO APLICADO |
| 33 | 1615<br>8WH90001GA00 | Tampa final para borne 2,5mm² | TAMPA FINAL SENTRON PARA BORNE DE PASSAGEM POR MOLA 2,5mm² CINZA ESPESSURA 2,2mm | RETIDO — NÃO APLICADO |
| 34 | 1616<br>8WH60000CF07 | Borne plug-in de proteção 2 condutores 2,5mm² | BORNE DE PROTEÇÃO PE SENTRON IPO PLUG-IN 2,5mm² 2 CONEXÕES 1 NÍVEL VERDE/AMARELO TERMOPLÁSTICO TRILHO TH35 | RETIDO — NÃO APLICADO |
| 35 | 1617<br>3RQ30521SM30 | RELÉ DE INTERFACE DE SAÍDA OPTOACOPLADO 1NA TRANSISTOR 24VCC SAÍDA 30VCC 2A CONEXÃO POR PARAFUSO | RELÉ DE INTERFACE OPTOACOPLADO SIRIUS 3RQ3 1NA TRANSISTOR ENTRADA 24VCC SAÍDA 10-30VCC 2A PARAFUSO | Aplicado e verificado |
| 36 | 1618<br>8WH90206BL10 | Pente de ligação para bornes 10 polos 2,5mm² | PENTE DE LIGAÇÃO TRANSVERSAL SENTRON 10 POLOS ENCAIXÁVEL PASSO 5,2mm ISOLADO PARA CENTRO DO BORNE | RETIDO — NÃO APLICADO |
| 37 | 1619<br>3RQ30551SM30 | RELÉ DE INTERFACE DE SAÍDA OPTOACOPLADO 1NA TRANSISTOR 24VCC SAÍDA 30VCC 5A CONEXÃO POR PARAFUSO | RELÉ DE INTERFACE OPTOACOPLADO SIRIUS 3RQ3 1NA TRANSISTOR ENTRADA 24VCC SAÍDA 10-30VCC 5A PARAFUSO | RETIDO — NÃO APLICADO |
| 38 | 1623<br>6EP41363AB000AY0 | UPS CC 24VCC 20A | MÓDULO UPS CC SITOP UPS1600 ENTRADA 24VCC SAÍDA 24VCC 20A 480W SEM INTERFACE PC IP20 | RETIDO — NÃO APLICADO |
| 39 | 1628<br>3SE63100BC01 | ATUADOR PADRÃO PARA CHAVE DE SEGURANÇA RFID 91mm x 25mm | ATUADOR RFID SIRIUS 3SE63 PLÁSTICO 91×25×22mm SEM RETENÇÃO MAGNÉTICA IP65/IP67/IP69K | Aplicado e verificado |
| 40 | 2135<br>5SV56140 | INTERRUPTOR DIFERENCIAL RESIDUAL 1P+N 40A 300mA TIPO AC | INTERRUPTOR DIFERENCIAL RESIDUAL SENTRON 5SV5 2P 40A 300mA TIPO AC 230VCA 50Hz INSTANTÂNEO | Aplicado e verificado |
| 41 | 2406<br>3UG55121BR20 | RELÉ DE MONITORAMENTO DE REDE TRIFÁSICA PARA FALTA, SEQUÊNCIA E ASSIMETRIA DE FASE 160-690VCA | RELÉ DE MONITORAMENTO SIRIUS 3UG5 3F 160-690VCA 15-70Hz FALTA/SEQUÊNCIA/ASSIMETRIA 2REV PARAFUSO | Aplicado e verificado |
| 42 | 2450<br>3SE50000AV04 | ATUADOR RADIAL ESQUERDO PARA CHAVE DE POSIÇÃO DE SEGURANÇA | ATUADOR RADIAL ESQUERDO SIRIUS 3SE5 PARA CHAVES 3SE51/3SE52/3SE53 FIXAÇÃO POR PARAFUSO | RETIDO — NÃO APLICADO |
| 43 | 2455<br>3SE50000AV01 | ATUADOR PADRÃO EM ZINCO FUNDIDO PARA CHAVE DE POSIÇÃO DE SEGURANÇA | ATUADOR PADRÃO SIRIUS 3SE5 ZINCO FUNDIDO PARA CHAVES 3SE51/3SE52/3SE53 FIXAÇÃO POR PARAFUSO | RETIDO — NÃO APLICADO |
| 44 | 2535<br>6GK19011BB102AE0 | Conector RJ45 macho blindado 4 polos para rede industrial | CONECTOR RJ45 IE FC PLUG 180 2×2 10/100Mbit/s METÁLICO FASTCONNECT AWG22 SAÍDA 180° IP20 | RETIDO — NÃO APLICADO |
| 45 | 2641<br>3ZY1212-1BA00 | CONECTOR DE DISPOSITIVOS PARA RELÉ DE SEGURANÇA 17,5mm | CONECTOR DE DISPOSITIVOS SIRIUS 3ZY1 PARA RELÉ DE SEGURANÇA 3SK1 LARGURA 17,5mm | RETIDO — NÃO APLICADO |
| 46 | 2642<br>3ZY1212-2DA00 | CONECTOR DE TERMINAÇÃO PARA RELÉ DE SEGURANÇA 22,5mm | CONECTOR DE TERMINAÇÃO SIRIUS 3ZY1 PARA RELÉ DE SEGURANÇA 3SK1 LARGURA 22,5mm | RETIDO — NÃO APLICADO |
| 47 | 2643<br>3ZY1212-2BA00 | CONECTOR DE DISPOSITIVOS PARA RELÉ DE SEGURANÇA 22,5mm | CONECTOR DE DISPOSITIVOS SIRIUS 3ZY1 PARA RELÉ DE SEGURANÇA 3SK1 LARGURA 22,5mm | RETIDO — NÃO APLICADO |
| 48 | 2889<br>3RQ30521SM50 | RELÉ DE INTERFACE DE SAÍDA OPTOACOPLADO 1NA TRIAC ENTRADA 24VCC SAÍDA 20-264VCA 2A CONEXÃO POR PARAFUSO | RELÉ DE INTERFACE OPTOACOPLADO SIRIUS 3RQ3 1NA TRIAC ENTRADA 24VCC SAÍDA 20-264VCA 2A PARAFUSO | Aplicado e verificado |
| 49 | 2890<br>3RQ31181AE00 | RELÉ DE INTERFACE COM RELÉ ENCAIXÁVEL 1 REVERSÍVEL 115VCA/CC CONEXÃO POR PARAFUSO | RELÉ DE INTERFACE SIRIUS 3RQ3 ENCAIXÁVEL 1REV ENTRADA 115VCA/CC 50/60Hz AC-15 3A EM 250VCA DC-13 1A EM 24VCC CONEXÃO POR PARAFUSO | Aplicado e verificado |
| 50 | 2891<br>3RQ31181AB00 | RELÉ DE INTERFACE COM RELÉ ENCAIXÁVEL 1 REVERSÍVEL 24VCA/CC CONEXÃO POR PARAFUSO | RELÉ DE INTERFACE SIRIUS 3RQ3 ENCAIXÁVEL 1REV ENTRADA 24VCA/CC 50/60Hz AC-15 3A EM 250VCA DC-13 1A EM 24VCC CONEXÃO POR PARAFUSO | Aplicado e verificado |

## Descrição complementar e evidências por item

### ID 226 — 5SV5646-0

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
INTERRUPTOR DIFERENCIAL RESIDUAL 3P+N 63A 300mA TIPO AC

Referência Siemens 5SV5646-0. RCCB de 4 polos totais (cadastro anterior 3P+N), tipo AC, sensibilidade 300mA, corrente nominal 63A. Tensão Un do resumo 400VCA, frequência 50Hz; não acrescentar 60Hz por analogia. Sem retardo de curta duração. O campo genérico de rede informa 230/400V, enquanto o resumo vincula Un ao número de polos; não tratar Ui 2000V como alimentação. Capacidade de estabelecimento/interrupção IEC61008-1 0,8kA; os 6kA de curto-circuito da ficha não são Icn de minidisjuntor nem proteção de sobrecorrente integrada. Verificar coordenação com proteção a montante, circuito de teste e adequação à instalação. IP20 condicionado ao quadro instalado e condutores conectados. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=5SV56460).

Evidência: Ficha oficial Siemens 5SV5646-0; páginas 1. SHA-256: 6962234c4f09f3c57573796897fe9c567efc156fd1e3e2a113e14b14001b3e5d. Arquivo: backups/fontes-lote-011/226.pdf.

### ID 227 — 5SV4612-0

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
INTERRUPTOR DIFERENCIAL RESIDUAL 1P+N 25A 300mA TIPO AC

Referência Siemens 5SV4612-0. RCCB de 2 polos totais (cadastro anterior 1P+N), tipo AC, sensibilidade 300mA, corrente nominal 25A. Tensão Un do resumo 230VCA, frequência 50Hz; não acrescentar 60Hz por analogia. Sem retardo de curta duração. O campo genérico de rede informa 230/400V, enquanto o resumo vincula Un ao número de polos; não tratar Ui 2000V como alimentação. Capacidade de estabelecimento/interrupção IEC61008-1 0,5kA; os 10kA de curto-circuito da ficha não são Icn de minidisjuntor nem proteção de sobrecorrente integrada. Verificar coordenação com proteção a montante, circuito de teste e adequação à instalação. IP20 condicionado ao quadro instalado e condutores conectados. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=5SV46120).

Evidência: Ficha oficial Siemens 5SV4612-0; páginas 1. SHA-256: 0266996236d61783e3f2c42e19fda39aa2830fdaa668f63435e04412e6d3aca4. Arquivo: backups/fontes-lote-011/227.pdf.

### ID 240 — 8WH6000-0AM00

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
Borne plug-in de passagem 35mm²

Referência Siemens 8WH6000-0AM00. Borne iPo cinza, seção nominal 35mm², um nível e dois pontos de conexão; corrente operacional 125A e tensão operacional 1000V. Não acrescentar CA/CC sem campo explícito. Não exige tampa final; flexível com terminal 2,5-35mm². Material isolante aparece apenas como 'Other', sem polímero confirmado; passo da tabela 35mm não utilizado como largura dimensional. UL94 V0 é classe de inflamabilidade, não identificação de material. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=8WH60000AM00).

Evidência: Ficha oficial Siemens 8WH6000-0AM00; páginas 1. SHA-256: 98937dee37d7b9524b27bde8c233ca488c86e8e9ffcd3550443bb584c18d49ea. Arquivo: backups/fontes-lote-011/240.pdf.

Atributos não confirmados: polimero_isolante, largura_dimensional.

### ID 256 — 3SE5000-0AV07-1AK2

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
ATUADOR RADIAL UNIVERSAL AJUSTÁVEL PARA CHAVE DE POSIÇÃO DE SEGURANÇA SERVIÇO PESADO 67mm

Referência Siemens 3SE5000-0AV07-1AK2. Atuador mecânico separado, universal radial heavy duty, comprimento 67mm, ajuste vertical e horizontal. Compatibilidade explicitada: chaves com trava 3SE5312/3SE5322 e AS-i 3SF13; chaves com atuador separado 3SE51/3SE52 e AS-i 3SF11/3SF12. Não confundir variantes 67mm e 77mm. A ficha não especifica material do atuador; não copiar zinco da variante padrão. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3SE50000AV071AK2).

Evidência: Ficha oficial Siemens 3SE5000-0AV07-1AK2; páginas 1. SHA-256: 2d9280a7c7fe93e07ab8bb50dbc0788ea0f477febda55c71fb40d54aeb571a64. Arquivo: backups/fontes-lote-011/256.pdf.

Atributos não confirmados: material_atuador.

### ID 346 — 3SE5000-0AV07

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
ATUADOR RADIAL PARA CHAVE DE POSIÇÃO DE SEGURANÇA SERVIÇO PESADO

Referência Siemens 3SE5000-0AV07. Atuador mecânico separado, universal radial heavy duty, comprimento 77mm, ajuste vertical e horizontal. Compatibilidade explicitada: chaves com trava 3SE5312/3SE5322 e AS-i 3SF13; chaves com atuador separado 3SE51/3SE52 e AS-i 3SF11/3SF12. Não confundir variantes 67mm e 77mm. A ficha não especifica material do atuador; não copiar zinco da variante padrão. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3SE50000AV07).

Evidência: Ficha oficial Siemens 3SE5000-0AV07; páginas 1. SHA-256: e3129e0c1d1182bbdb48b86cd6f6460d9f4b3f4ae97c672fe1b9797c7f44f2a3. Arquivo: backups/fontes-lote-011/346.pdf.

Atributos não confirmados: material_atuador.

### ID 686 — 3UG5616-1CR20

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
RELÉ DE MONITORAMENTO DE REDE TRIFÁSICA PARA FALTA, SEQUÊNCIA E ASSIMETRIA DE FASE, FREQUÊNCIA, SOBRETENSÃO E SUBTENSÃO 90-690VCA

Referência Siemens 3UG5616-1CR20. Resumo da referência informa faixa de rede 90-690VCA e 15-70Hz, dois contatos reversíveis, conexão por parafuso. Ajuste digital/display LCD, funções de falta/sequência/assimetria/frequência/sobre e subtensão e monitoramento de neutro ajustável. Tabela separa alimentação 200-690VCA ou 120-400VCA e medição 160-760VCA ou 90-440VCA, conforme ligação; não fundir tudo em faixa única de alimentação. Tabela mostra frequência invertida 70...15Hz; usa-se a ordem 15-70Hz explicitada no resumo. Confirmar ligação pelo manual; não selecionar bornes por inferência. Não indicado para circuitos de segurança; sem IO-Link. Corrente térmica 5A não é capacidade universal dos contatos. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3UG56161CR20).

Evidência: Ficha oficial Siemens 3UG5616-1CR20; páginas 1, 2. SHA-256: 57db1500bf71953580142cf98fa75fb53bc88926a030147fa2e1bc2aeb1ff8f8. Arquivo: backups/fontes-lote-011/686.pdf.

### ID 735 — 3RA1921-1DA00

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
CONEXAO 3RV S00S0 C 3RT S00 PARAFUSO

Referência Siemens 3RA1921-1DA00. Módulo de três polos para união elétrica e mecânica; disjuntor S00/S0 e contator S00, operação CA e CC. Resumo confirma 3RV2.1/3RV2.2 e 3RT2.1. Compatibilidades legadas adicionais citadas na tabela não autorizam ampliação automática. Conexão por parafuso do histórico não explicitada no texto desta ficha; mantém-se apenas no histórico identificado. Embalagem individual não altera multiplicador. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3RA19211DA00).

Evidência: Ficha oficial Siemens 3RA1921-1DA00; páginas 1. SHA-256: aa57f05573ebe1350e68e6e5c3a14912e18db61d41ec98a5952786f2c2e9e4ef. Arquivo: backups/fontes-lote-011/735.pdf.

Atributos não confirmados: conexao_parafuso_historica.

### ID 737 — 5SV4642-0

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
INTERRUPTOR DIFERENCIAL RESIDUAL 3P+N 25A 300mA TIPO AC

Referência Siemens 5SV4642-0. RCCB de 4 polos totais (cadastro anterior 3P+N), tipo AC, sensibilidade 300mA, corrente nominal 25A. Tensão Un do resumo 400VCA, frequência 50Hz; não acrescentar 60Hz por analogia. Sem retardo de curta duração. O campo genérico de rede informa 230/400V, enquanto o resumo vincula Un ao número de polos; não tratar Ui 2000V como alimentação. Capacidade de estabelecimento/interrupção IEC61008-1 0,8kA; os 10kA de curto-circuito da ficha não são Icn de minidisjuntor nem proteção de sobrecorrente integrada. Verificar coordenação com proteção a montante, circuito de teste e adequação à instalação. IP20 condicionado ao quadro instalado e condutores conectados. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=5SV46420).

Evidência: Ficha oficial Siemens 5SV4642-0; páginas 1. SHA-256: 0f94bfa2843114fda0894b21c33e88a1ea58c1c45d0c7095d49e21beab3eb093. Arquivo: backups/fontes-lote-011/737.pdf.

### ID 738 — 5SV5312-0MB

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
INTERRUPTOR DIFERENCIAL RESIDUAL 1P+N 25A 30mA TIPO AC

Referência Siemens 5SV5312-0MB. RCCB de 2 polos totais (cadastro anterior 1P+N), tipo AC, sensibilidade 30mA, corrente nominal 25A. Tensão Un do resumo 230VCA, frequência 60Hz; não acrescentar 50Hz por analogia. Sem retardo de curta duração. Capacidade de estabelecimento/interrupção IEC61008-1 0,5kA; os 6kA de curto-circuito da ficha não são Icn de minidisjuntor nem proteção de sobrecorrente integrada. Verificar coordenação com proteção a montante, circuito de teste e adequação à instalação. IP20 condicionado ao quadro instalado e condutores conectados. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=5SV53120MB).

Evidência: Ficha oficial Siemens 5SV5312-0MB; páginas 1. SHA-256: 0f64bbcaa3be9cf2ca44afb435595623ed221ca2d8e5a05e73d3008011cbdaec. Arquivo: backups/fontes-lote-011/738.pdf.

### ID 744 — 5SV5344-0MB

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
INTERRUPTOR DIFERENCIAL RESIDUAL 3P+N 40A 30mA TIPO AC

Referência Siemens 5SV5344-0MB. RCCB de 4 polos totais (cadastro anterior 3P+N), tipo AC, sensibilidade 30mA, corrente nominal 40A. Tensão Un do resumo 400VCA, frequência 60Hz; não acrescentar 50Hz por analogia. Sem retardo de curta duração. Capacidade de estabelecimento/interrupção IEC61008-1 0,8kA; os 6kA de curto-circuito da ficha não são Icn de minidisjuntor nem proteção de sobrecorrente integrada. Verificar coordenação com proteção a montante, circuito de teste e adequação à instalação. IP20 condicionado ao quadro instalado e condutores conectados. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=5SV53440MB).

Evidência: Ficha oficial Siemens 5SV5344-0MB; páginas 1. SHA-256: c6ca320b79308c0cbbc7220428ff3de4f30bb76677c6ac28ed9a1f0b99174a82. Arquivo: backups/fontes-lote-011/744.pdf.

### ID 745 — 5SV5342-0MB

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
INTERRUPTOR DIFERENCIAL RESIDUAL 3P+N 25A 30mA TIPO AC

Referência Siemens 5SV5342-0MB. RCCB de 4 polos totais (cadastro anterior 3P+N), tipo AC, sensibilidade 30mA, corrente nominal 25A. Tensão Un do resumo 400VCA, frequência 60Hz; não acrescentar 50Hz por analogia. Sem retardo de curta duração. Capacidade de estabelecimento/interrupção IEC61008-1 0,8kA; os 6kA de curto-circuito da ficha não são Icn de minidisjuntor nem proteção de sobrecorrente integrada. Verificar coordenação com proteção a montante, circuito de teste e adequação à instalação. IP20 condicionado ao quadro instalado e condutores conectados. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=5SV53420MB).

Evidência: Ficha oficial Siemens 5SV5342-0MB; páginas 1. SHA-256: d42cacfbfa3ee7b4e02967e24f44e9c0edb757848326361cec86585f590c1b76. Arquivo: backups/fontes-lote-011/745.pdf.

### ID 776 — 3RA2921-1BA00

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
CONEXAO 3RV S00S0 C 3RT S0 CC PARAFUSO

Referência Siemens 3RA2921-1BA00. Disjuntor S00/S0 e contator S0, três polos, união elétrica/mecânica por parafuso. Tabela identifica atuação CC do contator; resumo também cita AC/DC, soft-starter 3RW3 e contator estático 3RF34. Não universalizar para bobina CA convencional nem toda variante dessas famílias; conferir combinação exata. Tensão de bobina não é tensão própria do acessório. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3RA29211BA00).

Evidência: Ficha oficial Siemens 3RA2921-1BA00; páginas 1. SHA-256: 2d938f623994e6c1cf615df185b4b5d6e8dba0874c590b2b1ed13a052795fe65. Arquivo: backups/fontes-lote-011/776.pdf.

### ID 781 — 3RA2911-2AA00

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
CONEXAO 3RV S00 C 3RT S00 MOLA

Referência Siemens 3RA2911-2AA00. Três polos, disjuntor S00 e contator S00, união elétrica/mecânica 3RV2011/3RT201., conexão por mola e fixação por encaixe. Operação CA/CC refere-se ao contator compatível, não a alimentação do módulo passivo. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3RA29112AA00).

Evidência: Ficha oficial Siemens 3RA2911-2AA00; páginas 1. SHA-256: ff6409e975fa537c0742b8deafac44a1b38134dc78167ee27e5b8dbf38289bb8. Arquivo: backups/fontes-lote-011/781.pdf.

### ID 789 — 3RA2923-2AA1

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
JOGO DE MONTAGEM PARA REVERSÃO DE CONTATORES COM CONEXÃO POR PARAFUSO

Referência Siemens 3RA2923-2AA1. Kit elétrico e mecânico para partida reversora tamanho S0, três polos, inclui intertravamento mecânico. Conexão por parafuso. Não é partida completa nem inclui contatores por inferência. Não confundir com conector para dois contatores em série. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3RA29232AA1).

Evidência: Ficha oficial Siemens 3RA2923-2AA1; páginas 1. SHA-256: 6ea6e5b3177e41e55b178ba702cefdcaf6ad01c3e6369497822e5f5ebdfe2da3. Arquivo: backups/fontes-lote-011/789.pdf.

### ID 816 — 5SV4347-0MB

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
INTERRUPTOR DIFERENCIAL RESIDUAL 3P+N 80A 30mA TIPO AC

Referência Siemens 5SV4347-0MB. RCCB de 4 polos totais (cadastro anterior 3P+N), tipo AC, sensibilidade 30mA, corrente nominal 80A. Tensão Un do resumo 400VCA, frequência 60Hz; não acrescentar 50Hz por analogia. Sem retardo de curta duração. Capacidade de estabelecimento/interrupção IEC61008-1 0,8kA; os 10kA de curto-circuito da ficha não são Icn de minidisjuntor nem proteção de sobrecorrente integrada. Verificar coordenação com proteção a montante, circuito de teste e adequação à instalação. IP20 condicionado ao quadro instalado e condutores conectados. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=5SV43470MB).

Evidência: Ficha oficial Siemens 5SV4347-0MB; páginas 1. SHA-256: 0f6609ea1d03ce6ad7939b9847ce41c7f292d0764e6348db836ac93e098e1dcb. Arquivo: backups/fontes-lote-011/816.pdf.

### ID 821 — 3RQ3118-2AM00

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
RELÉ DE INTERFACE COM RELÉ ENCAIXÁVEL 1 REVERSÍVEL 24VCC CONEXÃO POR MOLA

Referência Siemens 3RQ3118-2AM00. Acoplador de saída com relé encaixável, um contato reversível, largura 6,2mm e LED de estado. Corrente térmica 6A não é capacidade AC-15: saída 3A em 250VCA AC-15 e 1A em 24VCC DC-13; em 125VCC 0,2A e 250VCC 0,1A. Fusível gG 4A indicado para proteção dos contatos; saída não é à prova de curto. Entrada exclusivamente CC, sem frequência de bobina. Ficha declara produto descontinuado e cita sucessor 3RQ4: manter código, atividade e especificações do 3RQ3, sem substituição automática. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3RQ31182AM00).

Evidência: Ficha oficial Siemens 3RQ3118-2AM00; páginas 1, 2. SHA-256: 3e76a2d7b42719203aebd94419e0ce925819e17db22978b0fd0537f97a053f45. Arquivo: backups/fontes-lote-011/821.pdf.

### ID 824 — 3RQ3901-0D

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
PENTE DE CONEXÃO 16 POLOS PARA RELÉS DE INTERFACE

Referência Siemens 3RQ3901-0D. Pente para interligar potenciais iguais, exclusivamente relés de interface SIRIUS 3RQ3 e conversores de sinal 3RS7 segundo ficha. Dezesseis polos e corrente máxima de alimentação 6A no conjunto, não 6A multiplicados por polo. Altura×largura×profundidade 3,3×99×11mm. Sem atribuir tensão ou material não informados. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3RQ39010D).

Evidência: Ficha oficial Siemens 3RQ3901-0D; páginas 1. SHA-256: 032b65afe56fd8a04c1784fd7d72b32fe532159268dbf3fc7551ae483d015df3. Arquivo: backups/fontes-lote-011/824.pdf.

Atributos não confirmados: tensao_e_material.

### ID 922 — 6EP3332-3SB00-0AX0

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
FONTE DE ALIMENTAÇÃO 24VCC 3A ENTRADA MONOFÁSICA

Referência Siemens 6EP3332-3SB00-0AX0. Saída nominal 24VCC/3A/72W, ajustável 24-28V por potenciômetro; não implica potência aumentada ao ajustar tensão. Entrada monofásica com seleção automática entre duas faixas nominais 100-120VCA e 200-240VCA; admissíveis 85-132VCA e 187-264VCA. Não é faixa contínua 85-264VCA. Frequência nominal 50/60Hz, admissível 47-63Hz. Ficha indica operação de 60°C a 70°C sem redução de corrente; não extrapolar às demais potências. Limites de curto-circuito/pico não substituem corrente contínua nominal. Paralelismo somente conforme instruções; não altera multiplicador. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6EP33323SB000AX0).

Evidência: Ficha oficial Siemens 6EP3332-3SB00-0AX0; páginas 1, 2. SHA-256: 16e0322cbefac01bec20abc7415876ec77fd13cc2e393408a31edbef456929db. Arquivo: backups/fontes-lote-011/922.pdf.

### ID 923 — 6EP3333-3SB00-0AX0

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
FONTE DE ALIMENTAÇÃO 24VCC 5A ENTRADA MONOFÁSICA

Referência Siemens 6EP3333-3SB00-0AX0. Saída nominal 24VCC/5A/120W, ajustável 24-28V por potenciômetro; não implica potência aumentada ao ajustar tensão. Entrada monofásica com seleção automática entre duas faixas nominais 100-120VCA e 200-240VCA; admissíveis 85-132VCA e 187-264VCA. Não é faixa contínua 85-264VCA. Frequência nominal 50/60Hz, admissível 47-63Hz. Entre 60°C e 70°C reduzir corrente em 4%/K conforme ficha. Limites de curto-circuito/pico não substituem corrente contínua nominal. Paralelismo somente conforme instruções; não altera multiplicador. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6EP33333SB000AX0).

Evidência: Ficha oficial Siemens 6EP3333-3SB00-0AX0; páginas 1, 2. SHA-256: 13515cce1e3edb6652c84887e9c9dceaa0cafe6397606cf93a9327dcf0e2a1c5. Arquivo: backups/fontes-lote-011/923.pdf.

### ID 924 — 6EP3334-3SB00-0AX0

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
FONTE DE ALIMENTAÇÃO 24VCC 10A ENTRADA MONOFÁSICA

Referência Siemens 6EP3334-3SB00-0AX0. Saída nominal 24VCC/10A/240W, ajustável 24-28V por potenciômetro; não implica potência aumentada ao ajustar tensão. Entrada monofásica com seleção automática entre duas faixas nominais 100-120VCA e 200-240VCA; admissíveis 85-132VCA e 187-264VCA. Não é faixa contínua 85-264VCA. Frequência nominal 50/60Hz, admissível 47-63Hz. Entre 60°C e 70°C reduzir corrente em 4%/K conforme ficha. Limites de curto-circuito/pico não substituem corrente contínua nominal. Paralelismo somente conforme instruções; não altera multiplicador. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6EP33343SB000AX0).

Evidência: Ficha oficial Siemens 6EP3334-3SB00-0AX0; páginas 1, 2. SHA-256: 01d652cccebe4c7581ff864c2a4716203a77e80b12394d731a4534d4a4cff117. Arquivo: backups/fontes-lote-011/924.pdf.

### ID 925 — 6EP3336-3SB00-0AX0

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
FONTE DE ALIMENTAÇÃO 24VCC 20A ENTRADA MONOFÁSICA

Referência Siemens 6EP3336-3SB00-0AX0. Saída nominal 24VCC/20A/480W, ajustável 24-28V por potenciômetro; não implica potência aumentada ao ajustar tensão. Entrada monofásica nominal 120-240VCA, faixa contínua admissível 85-264VCA. Frequência nominal 50/60Hz, admissível 47-63Hz. Entre 60°C e 70°C reduzir corrente em 3%/K conforme ficha. Limites de curto-circuito/pico não substituem corrente contínua nominal. Paralelismo somente conforme instruções; não altera multiplicador. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6EP33363SB000AX0).

Evidência: Ficha oficial Siemens 6EP3336-3SB00-0AX0; páginas 1, 2. SHA-256: 9cb8240e2df3126923766c66598b44a8296d242a89baea642c844a5d6757bcc4. Arquivo: backups/fontes-lote-011/925.pdf.

### ID 926 — 6EP3434-3SB00-0AX0

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
FONTE DE ALIMENTAÇÃO 24VCC 10A ENTRADA TRIFÁSICA

Referência Siemens 6EP3434-3SB00-0AX0. Saída nominal 24VCC/10A/240W, ajustável 24-28V por potenciômetro; não implica potência aumentada ao ajustar tensão. Entrada trifásica nominal 400-500VCA, faixa admissível 320-550VCA. Frequência nominal 50/60Hz, admissível 47-63Hz. Entre 60°C e 70°C reduzir corrente em 3%/K conforme ficha. Limites de curto-circuito/pico não substituem corrente contínua nominal. Paralelismo somente conforme instruções; não altera multiplicador. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6EP34343SB000AX0).

Evidência: Ficha oficial Siemens 6EP3434-3SB00-0AX0; páginas 1, 2. SHA-256: 167834c8ab619758afe08cd3f9f2ba77f446fa038c6eb178df2a739b25aa9558. Arquivo: backups/fontes-lote-011/926.pdf.

### ID 927 — 3RA2913-2AA1

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
JOGO DE MONTAGEM PARA REVERSÃO DE CONTATORES COM CONEXÃO POR PARAFUSO

Referência Siemens 3RA2913-2AA1. Kit elétrico e mecânico para partida reversora tamanho S00, três polos, inclui intertravamento mecânico. Conexão por parafuso. Não é partida completa nem inclui contatores por inferência. Não confundir com conector para dois contatores em série. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3RA29132AA1).

Evidência: Ficha oficial Siemens 3RA2913-2AA1; páginas 1. SHA-256: e110d1d728f98d2a47ad5f6831fe601d16bd5b85ad7c49dcff8919a2a768415e. Arquivo: backups/fontes-lote-011/927.pdf.

### ID 928 — 3RA2913-2AA2

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
JOGO DE MONTAGEM PARA REVERSÃO DE CONTATORES COM CONEXÃO POR MOLA

Referência Siemens 3RA2913-2AA2. Kit elétrico e mecânico para partida reversora tamanho S00, três polos, inclui intertravamento mecânico. Conexão por mola e fixação por encaixe. Não é partida completa nem inclui contatores por inferência. Não confundir com conector para dois contatores em série. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3RA29132AA2).

Evidência: Ficha oficial Siemens 3RA2913-2AA2; páginas 1. SHA-256: e92e57acc2573ab001acde6755ffd9bad9eb7dac2cf37ae58978828aeeea49ca. Arquivo: backups/fontes-lote-011/928.pdf.

### ID 944 — 8WH6000-0AF00

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
Borne plug-in de passagem 2 condutores 2,5mm²

Referência Siemens 8WH6000-0AF00. Borne iPo cinza, seção nominal 2,5mm², um nível e dois pontos de conexão; corrente operacional 24A e tensão operacional 800V. Não acrescentar CA/CC sem campo explícito. Exige tampa final. Flexível com terminal 0,14-2,5mm²; maciço até 4mm² não muda a seção nominal. Revisão PARCIAL: limites de condutor encordoado aparecem invertidos (1,5/0,14mm²); não corrigir por suposição. Polímero não confirmado. UL94 V0 é classe de inflamabilidade, não identificação de material. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=8WH60000AF00).

Evidência: Ficha oficial Siemens 8WH6000-0AF00; páginas 1. SHA-256: 30db77ded32c065875a8d103d2e5b022d6ea2a2ae72317339b7f4f8cd506561b. Arquivo: backups/fontes-lote-011/944.pdf.

Atributos não confirmados: faixa_condutor_encordoado_invertida, polimero_isolante.

### ID 957 — 3RA1911-1AA00

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
CONEXAO 3RV S00 C/ 3RT S00 AC/DC (1UNID)

Referência Siemens 3RA1911-1AA00. Três polos, tamanho S00, união elétrica/mecânica. Resumo cita 3RV1011 com 3RT2.1 ou 3RW301; tabela de design cita 3RT1.1. Revisão PARCIAL: manter a distinção entre gerações e exigir verificação da combinação física; não presumir intercambiabilidade de 3RT1/3RT2. Retira observação comercial '(1UNID)' do nome sem alterar unidade ou fator. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3RA19111AA00).

Evidência: Ficha oficial Siemens 3RA1911-1AA00; páginas 1. SHA-256: e7808247aceee5c3a6de819e6aa612f1a177bf1990e0f1a644a500d14d87563e. Arquivo: backups/fontes-lote-011/957.pdf.

Atributos não confirmados: compatibilidade_3RT1_versus_3RT2.

### ID 973 — 3RA2926-1A

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
CONECTOR PARA MONTAGEM EM SÉRIE DE CONTATORES

Referência Siemens 3RA2926-1A. Ligação em série de dois contatores 3RT202, tamanho S0, três polos e conexão por parafuso. Não é ligação de reversão nem inclui os dois contatores; não alterar quantidade de estoque por essa indicação de compatibilidade. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3RA29261A).

Evidência: Ficha oficial Siemens 3RA2926-1A; páginas 1. SHA-256: 3e2d12cfa58917d410daaf4d26f556d6ba872b518107fa9739e53932bc4482a0. Arquivo: backups/fontes-lote-011/973.pdf.

### ID 977 — 8WH6000-0AG00

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
Borne plug-in de passagem 2 condutores 4mm²

Referência Siemens 8WH6000-0AG00. Borne iPo cinza, seção nominal 4mm², um nível e dois pontos de conexão; corrente operacional 32A e tensão operacional 800V. Não acrescentar CA/CC sem campo explícito. Exige tampa final. Flexível com terminal 0,25-4mm²; maciço até 6mm² não muda a seção nominal. Passo genérico de 4mm não utilizado como largura; polímero não confirmado. UL94 V0 é classe de inflamabilidade, não identificação de material. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=8WH60000AG00).

Evidência: Ficha oficial Siemens 8WH6000-0AG00; páginas 1. SHA-256: acbb1a4403e92641ac53250e8858c1ecc52308d8ff0f9b0c95d2f6aca75024ff. Arquivo: backups/fontes-lote-011/977.pdf.

Atributos não confirmados: polimero_isolante, largura_dimensional.

### ID 978 — 8WH9003-1GA00

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
Tampa final para borne 4mm²

Referência Siemens 8WH9003-1GA00. Tampa final para borne de passagem com conexão por mola, seção 4mm²; cinza, espessura 2,2mm. Não é placa intermediária. UL94 V0 não identifica polímero; não presumir compatibilidade universal com qualquer borne da mesma seção. Material específico e referência exata do borne devem ser conferidos antes de substituição. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=8WH90031GA00).

Evidência: Ficha oficial Siemens 8WH9003-1GA00; páginas 1. SHA-256: f270c87e8899e8cdfe4db0eed43e412537f5df97c0383b623f72211d4e79aaa5. Arquivo: backups/fontes-lote-011/978.pdf.

Atributos não confirmados: polimero_especifico, referencia_exata_borne_compativel.

### ID 1002 — 3RA2916-1A

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
CONECTOR PARA MONTAGEM EM SÉRIE DE 2 CONTATORES

Referência Siemens 3RA2916-1A. Ligação em série de dois contatores 3RT201, tamanho S00, três polos e conexão por parafuso. Não é ligação de reversão nem inclui os dois contatores; não alterar quantidade de estoque por essa indicação de compatibilidade. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3RA29161A).

Evidência: Ficha oficial Siemens 3RA2916-1A; páginas 1. SHA-256: f478346e26459b7ec2e1bfa7a9c11afdf535302b1b671ee51e7e140fe4ddf8ae. Arquivo: backups/fontes-lote-011/1002.pdf.

### ID 1003 — 3RA2921-2AA00

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
CONEXAO 3RV S0 C 3RT S0 MOLA

Referência Siemens 3RA2921-2AA00. Três polos, ambos os dispositivos tamanho S0; conexão por mola, fixação por encaixe. Referências de compatibilidade do resumo 3RV2.21 e 3RT2.2.; não extrapolar para qualquer disjuntor/contator S0. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3RA29212AA00).

Evidência: Ficha oficial Siemens 3RA2921-2AA00; páginas 1. SHA-256: d5304fdf03ab73fbc80c740201a38abb8908d6a94f001a5b3feab1d2a6f59b70. Arquivo: backups/fontes-lote-011/1003.pdf.

### ID 1088 — 6SL3255-0AA00-4CA1

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
PAINEL DE OPERAÇÃO BOP-2 PARA INVERSOR SINAMICS G120

Referência Siemens 6SL3255-0AA00-4CA1. Painel Basic Operator Panel BOP-2, LCD monocromático, largura×altura×profundidade 70×106,85×19,6mm; IP55/UL tipo12 conforme montagem, operação 0-50°C. Ficha de uma página não especifica lista de drives compatíveis ou kit de montagem. Compatibilidade G120 do histórico não reconfirmada nesta ficha, permanece identificada no complemento. Não é inversor nem IHM touchscreen. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6SL32550AA004CA1).

Evidência: Ficha oficial Siemens 6SL3255-0AA00-4CA1; páginas 1. SHA-256: 7b25700e6b4ccf164d7dc3f3a241b1a1e59493714c5349cb5ec2d3f992b7890a. Arquivo: backups/fontes-lote-011/1088.pdf.

Atributos não confirmados: compatibilidade_G120_e_kit_montagem.

### ID 1615 — 8WH9000-1GA00

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
Tampa final para borne 2,5mm²

Referência Siemens 8WH9000-1GA00. Tampa final para borne de passagem com conexão por mola, seção 2,5mm²; cinza, espessura 2,2mm. Não é placa intermediária. UL94 V0 não identifica polímero; não presumir compatibilidade universal com qualquer borne da mesma seção. Material específico e referência exata do borne devem ser conferidos antes de substituição. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=8WH90001GA00).

Evidência: Ficha oficial Siemens 8WH9000-1GA00; páginas 1. SHA-256: 414e9680228775674a7fb72e490170fee88437df048eaba5435f94614a07fcdf. Arquivo: backups/fontes-lote-011/1615.pdf.

Atributos não confirmados: polimero_especifico, referencia_exata_borne_compativel.

### ID 1616 — 8WH6000-0CF07

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
Borne plug-in de proteção 2 condutores 2,5mm²

Referência Siemens 8WH6000-0CF07. Borne PE de um nível e dois pontos, termoplástico verde/amarelo, seção nominal 2,5mm², montagem TH35; requer tampa final. Resumo usa PE/PEN, mas tabela declara função PEN: NÃO; não cadastrar como PEN. Flexível com terminal 0,14-2,5mm², decapagem 9mm. Revisão PARCIAL: limites de condutor encordoado estão invertidos (4/0,14mm²); confirmar antes de selecionar esse tipo de condutor. Não atribuir corrente/tensão de borne de passagem a borne PE. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=8WH60000CF07).

Evidência: Ficha oficial Siemens 8WH6000-0CF07; páginas 1. SHA-256: d2e97976938268a4fc78ef789f69dc5d2ea8a0d122a08679d3ab28eb31eca6b8. Arquivo: backups/fontes-lote-011/1616.pdf.

Atributos não confirmados: faixa_condutor_encordoado_invertida.

### ID 1617 — 3RQ3052-1SM30

Antes: DC 24V

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
RELÉ DE INTERFACE DE SAÍDA OPTOACOPLADO 1NA TRANSISTOR 24VCC SAÍDA 30VCC 2A CONEXÃO POR PARAFUSO
DC 24V

Referência Siemens 3RQ3052-1SM30. Saída semicondutora não encaixável, função 1NA transistor, entrada nominal 24VCC com faixa 11-30VCC, saída 10-30VCC, largura 6,2mm e indicação LED verde. Faixa de corrente da saída 5mA-2A, protegida contra curto conforme ficha. Não confundir alimentação de entrada com tensão da carga. Descontinuação e sucessor 3RQ4 não autorizam trocar referência ou inativar item. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3RQ30521SM30).

Evidência: Ficha oficial Siemens 3RQ3052-1SM30; páginas 1, 2. SHA-256: 6dcf0ac302afb91ab04c130595f909a8ded59ec0c0a3fd468be4efafa2bbb92d. Arquivo: backups/fontes-lote-011/1617.pdf.

### ID 1618 — 8WH9020-6BL10

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
Pente de ligação para bornes 10 polos 2,5mm²

Referência Siemens 8WH9020-6BL10. Ponte transversal isolada e protegida contra toque, dez bornes interligados, encaixe central e passo 5,2mm. A foto é ilustrativa e mostra duas pontas: não reduzir os dez polos confirmados no resumo/tabela. Revisão PARCIAL: resumo indica cor petrol e tabela red; nenhuma cor foi escolhida. Seção histórica 2,5mm², material e limites elétricos não confirmados nesta ficha; não confundir passo com seção. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=8WH90206BL10).

Evidência: Ficha oficial Siemens 8WH9020-6BL10; páginas 1. SHA-256: 66c2bd3289147ee19f9d230d9a5b98c81342ab36d6194325cf9bbe8e323fbcd8. Arquivo: backups/fontes-lote-011/1618.pdf.

Atributos não confirmados: cor_divergente, secao_historica_2_5mm2, material_e_limites_eletricos.

### ID 1619 — 3RQ3055-1SM30

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
RELÉ DE INTERFACE DE SAÍDA OPTOACOPLADO 1NA TRANSISTOR 24VCC SAÍDA 30VCC 5A CONEXÃO POR PARAFUSO

Referência Siemens 3RQ3055-1SM30. Saída semicondutora não encaixável, função 1NA transistor, entrada nominal 24VCC com faixa 11-30VCC, saída 10-30VCC, largura 6,2mm e indicação LED verde. Revisão PARCIAL: resumo e corrente térmica informam 5A, enquanto tabela de saída mostra apenas 5mA, sem limite superior. Mantém 5A do resumo/histórico, sem certificar faixa completa ou considerar 5mA como máximo; conferir placa/manual antes de dimensionar carga. Não confundir alimentação de entrada com tensão da carga. Descontinuação e sucessor 3RQ4 não autorizam trocar referência ou inativar item. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3RQ30551SM30).

Evidência: Ficha oficial Siemens 3RQ3055-1SM30; páginas 1, 2. SHA-256: 1ccb089bfbd25f1e5bef8a4905e6b40311544f959a041ebadffd9f06e0c546a4. Arquivo: backups/fontes-lote-011/1619.pdf.

Atributos não confirmados: faixa_corrente_saida_tabela_incompleta.

### ID 1623 — 6EP4136-3AB00-0AY0

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
UPS CC 24VCC 20A

Referência Siemens 6EP4136-3AB00-0AY0. Módulo UPS para sistema com baterias, entrada nominal 24VCC/faixa 21-29VCC, saída nominal 24VCC/20A/480W. Não é fonte CA/CC; sem isolação galvânica entrada/saída. Saída normal aproximadamente Vin-0,2V; em bateria 18,5-27V. Pico 60A não é corrente contínua: ficha limita 3×In a 30ms/min e 1,5×In a 5s/min. Sem interface PC; não inferir USB/PROFINET de outras versões. Tempos selecionáveis no seletor não garantem autonomia: depende de bateria e carga. Fornecimento de bateria/fonte externa não confirmado, não presumir conjunto completo. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6EP41363AB000AY0).

Evidência: Ficha oficial Siemens 6EP4136-3AB00-0AY0; páginas 1, 2. SHA-256: 899dcce857edc37ad51d146a7a9325c8bc28d5ef78c6b3ec7e03199e841e3241. Arquivo: backups/fontes-lote-011/1623.pdf.

Atributos não confirmados: fornecimento_bateria_fonte_externa.

### ID 1628 — 3SE6310-0BC01

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
ATUADOR PADRÃO PARA CHAVE DE SEGURANÇA RFID 91mm x 25mm

Referência Siemens 3SE6310-0BC01. Atuador padrão para chaves RFID 3SE63, corpo e área ativa plásticos; comprimento×largura×altura 91×25×22mm, fixação por parafuso. Sem retenção magnética. Não é sensor com saídas OSSD. Campo genérico 'capa PVC' não prova cabo incluído em atuador passivo; não acrescentar cabo, conector ou alimentação. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3SE63100BC01).

Evidência: Ficha oficial Siemens 3SE6310-0BC01; páginas 1. SHA-256: dc8345da84c15994bb4cf0f815a9fe6c01cd478db5383ec408c3aa916f792dc0. Arquivo: backups/fontes-lote-011/1628.pdf.

### ID 2135 — 5SV5614-0

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
INTERRUPTOR DIFERENCIAL RESIDUAL 1P+N 40A 300mA TIPO AC

Referência Siemens 5SV5614-0. RCCB de 2 polos totais (cadastro anterior 1P+N), tipo AC, sensibilidade 300mA, corrente nominal 40A. Tensão Un do resumo 230VCA, frequência 50Hz; não acrescentar 60Hz por analogia. Sem retardo de curta duração. O campo genérico de rede informa 230/400V, enquanto o resumo vincula Un ao número de polos; não tratar Ui 2000V como alimentação. Capacidade de estabelecimento/interrupção IEC61008-1 0,5kA; os 6kA de curto-circuito da ficha não são Icn de minidisjuntor nem proteção de sobrecorrente integrada. Verificar coordenação com proteção a montante, circuito de teste e adequação à instalação. IP20 condicionado ao quadro instalado e condutores conectados. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=5SV56140).

Evidência: Ficha oficial Siemens 5SV5614-0; páginas 1. SHA-256: 0e4a834032c8ef432667f0dc3cf6ddfdeb6c88adece0c906d1281441f7e32e7b. Arquivo: backups/fontes-lote-011/2135.pdf.

### ID 2406 — 3UG5512-1BR20

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
RELÉ DE MONITORAMENTO DE REDE TRIFÁSICA PARA FALTA, SEQUÊNCIA E ASSIMETRIA DE FASE 160-690VCA

Referência Siemens 3UG5512-1BR20. Resumo da referência informa faixa de rede 160-690VCA e 15-70Hz, dois contatos reversíveis, conexão por parafuso. Indicação LED, falta/sequência/assimetria; assimetria não ajustável, por limites internos de tensão. Não possui função independente de sobre/subtensão, neutro ou frequência por analogia com 3UG5616. Tabela separa alimentação 200-690VCA e medição 160-760VCA. Tabela mostra frequência invertida 70...15Hz; usa-se a ordem 15-70Hz explicitada no resumo. Confirmar ligação pelo manual; não selecionar bornes por inferência. Não indicado para circuitos de segurança; sem IO-Link. Corrente térmica 5A não é capacidade universal dos contatos. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3UG55121BR20).

Evidência: Ficha oficial Siemens 3UG5512-1BR20; páginas 1, 2. SHA-256: e51bbcc055a580e56d1034234ea06eeef29dea2a58f88260e4a0be24df2059e6. Arquivo: backups/fontes-lote-011/2406.pdf.

### ID 2450 — 3SE5000-0AV04

Antes: ATUADOR DE DESIGNAÇÃO DE PRODUTO DESIGNAÇÃO DO TIPO DE PRODUTO 3SE5 DADOS TÉCNICOS GERAIS RESISTÊNCIA AO CHOQUE ● ACC. PARA IEC 60068-2-27 30G / 11 MS RESISTÊNCIA À VIBRAÇÃO ● ACC. PARA IEC 60068-2-6 0,35 MM/5G VIDA ÚTIL MECÂNICA (CICLOS DE COMUTAÇÃO) ● TÍPICO 1 000 000 CÓDIGO DE REFERÊNCIA ACC.

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
ATUADOR RADIAL ESQUERDO PARA CHAVE DE POSIÇÃO DE SEGURANÇA
ATUADOR DE DESIGNAÇÃO DE PRODUTO DESIGNAÇÃO DO TIPO DE PRODUTO 3SE5 DADOS TÉCNICOS GERAIS RESISTÊNCIA AO CHOQUE ● ACC. PARA IEC 60068-2-27 30G / 11 MS RESISTÊNCIA À VIBRAÇÃO ● ACC. PARA IEC 60068-2-6 0,35 MM/5G VIDA ÚTIL MECÂNICA (CICLOS DE COMUTAÇÃO) ● TÍPICO 1 000 000 CÓDIGO DE REFERÊNCIA ACC.

Referência Siemens 3SE5000-0AV04. Atuador mecânico separado radial esquerdo; compatível com 3SE5312/3SE5322 e AS-i 3SF13, e chaves separadas 3SE51/3SE52 e AS-i 3SF11/3SF12. Não presumir comprimento, material, regulagem universal ou lado direito. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3SE50000AV04).

Evidência: Ficha oficial Siemens 3SE5000-0AV04; páginas 1. SHA-256: e7e22ff5604f30a75f2588a0fd00506bd6887c7dc54632ca70c2ee4abf306637. Arquivo: backups/fontes-lote-011/2450.pdf.

Atributos não confirmados: comprimento_e_material.

### ID 2455 — 3SE5000-0AV01

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
ATUADOR PADRÃO EM ZINCO FUNDIDO PARA CHAVE DE POSIÇÃO DE SEGURANÇA

Referência Siemens 3SE5000-0AV01. Atuador padrão separado em zinco fundido. Compatibilidade: 3SE5312/3SE5322, AS-i 3SF13, 3SE51/3SE52 e AS-i 3SF11/3SF12. Não confundir com atuador radial ajustável nem atribuir comprimento não informado. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3SE50000AV01).

Evidência: Ficha oficial Siemens 3SE5000-0AV01; páginas 1. SHA-256: 688bc53ee533f3876d1275cd4d59df6a2dde270f8330714ae5c1fa26f3c257bb. Arquivo: backups/fontes-lote-011/2455.pdf.

Atributos não confirmados: comprimento.

### ID 2535 — 6GK1901-1BB10-2AE0

Antes: O CONECTOR RJ45 MACHO BLIND 4P CAT 5 6GK19011BB102AE0 DA SIEMENS É A ESCOLHA PERFEITA PARA GARANTIR UMA CONEXÃO RÁPIDA E SEGURA DE SEUS DISPOSITIVOS. COM UM REVESTIMENTO BLINDADO, ESTE CONECTOR DE METAL POSSUI 4 POLOS E É CAPAZ DE SE CONECTAR COM DISPOSITIVOS DE CATEGORIA 5. SE VOCÊ PRECISA DE UM CONECTOR QUE OFEREÇA ALTA QUALIDADE DE SINAL, ESTE PRODUTO É IDEAL PARA VOCÊ. COM A TECNOLOGIA DE CONEXÃO MODERNA DA SIEMENS, VOCÊ PODE GARANTIR QUE SEUS DISPOSITIVOS TERÃO A MELHOR PERFORMANCE POSSÍVEL, SEM INTERRUPÇÕES OU PROBLEMAS DE CONEXÃO. O CONECTOR RJ45 MACHO BLIND 4P CAT 5 6GK19011BB102AE0 FOI PROJETADO PARA GARANTIR A DURABILIDADE E RESISTÊNCIA NECESSÁRIAS PARA SUPORTAR OS AMBIENTES MAIS EXIGENTES, OFERECENDO ALTA RESISTÊNCIA MECÂNICA CONTRA IMPACTOS E VIBRAÇÕES, BEM COMO PROTEÇÃO ELÉTRICA. COM O CONECTOR RJ45 MACHO BLIND 4P CAT 5 6GK19011BB102AE0 DA SIEMENS, VOCÊ PODE GARANTIR QUE SEU SISTEMA DE AUTOMAÇÃO INDUSTRIAL TERÁ UMA CONEXÃO CONFIÁVEL E SEGURA PARA GARANTIR A CONTINUIDADE DE SUAS OPERAÇÕES, EVITANDO PREJUÍZOS E PERDAS DE PRODUÇÃO. ADQUIRA AGORA MESMO O CONECTOR RJ45 MACHO BLIND 4P CAT 5 6GK19011BB102AE0 DA SIEMENS E TENHA A CERTEZA DE UMA CONEXÃO IMPECÁVEL PARA SEUS DISPOSITIVOS!

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
Conector RJ45 macho blindado 4 polos para rede industrial
O CONECTOR RJ45 MACHO BLIND 4P CAT 5 6GK19011BB102AE0 DA SIEMENS É A ESCOLHA PERFEITA PARA GARANTIR UMA CONEXÃO RÁPIDA E SEGURA DE SEUS DISPOSITIVOS. COM UM REVESTIMENTO BLINDADO, ESTE CONECTOR DE METAL POSSUI 4 POLOS E É CAPAZ DE SE CONECTAR COM DISPOSITIVOS DE CATEGORIA 5. SE VOCÊ PRECISA DE UM CONECTOR QUE OFEREÇA ALTA QUALIDADE DE SINAL, ESTE PRODUTO É IDEAL PARA VOCÊ. COM A TECNOLOGIA DE CONEXÃO MODERNA DA SIEMENS, VOCÊ PODE GARANTIR QUE SEUS DISPOSITIVOS TERÃO A MELHOR PERFORMANCE POSSÍVEL, SEM INTERRUPÇÕES OU PROBLEMAS DE CONEXÃO. O CONECTOR RJ45 MACHO BLIND 4P CAT 5 6GK19011BB102AE0 FOI PROJETADO PARA GARANTIR A DURABILIDADE E RESISTÊNCIA NECESSÁRIAS PARA SUPORTAR OS AMBIENTES MAIS EXIGENTES, OFERECENDO ALTA RESISTÊNCIA MECÂNICA CONTRA IMPACTOS E VIBRAÇÕES, BEM COMO PROTEÇÃO ELÉTRICA. COM O CONECTOR RJ45 MACHO BLIND 4P CAT 5 6GK19011BB102AE0 DA SIEMENS, VOCÊ PODE GARANTIR QUE SEU SISTEMA DE AUTOMAÇÃO INDUSTRIAL TERÁ UMA CONEXÃO CONFIÁVEL E SEGURA PARA GARANTIR A CONTINUIDADE DE SUAS OPERAÇÕES, EVITANDO PREJUÍZOS E PERDAS DE PRODUÇÃO. ADQUIRA AGORA MESMO O CONECTOR RJ45 MACHO BLIND 4P CAT 5 6GK19011BB102AE0 DA SIEMENS E TENHA A CERTEZA DE UMA CONEXÃO IMPECÁVEL PARA SEUS DISPOSITIVOS!

Referência Siemens 6GK1901-1BB10-2AE0. Plugue Industrial Ethernet FastConnect para cabo IE FC TP 2×2 quatro fios AWG22, contatos de corte/prensagem, uma conexão RJ45 e saída de cabo 180°. Corpo metálico, 10/100Mbit/s (não Gigabit), dimensões largura×altura×profundidade 13,7×16×55mm. Ficha da referência -2AE0 informa embalagem de 50 unidades; isso não comprova unidade comercial usada no ERP. Preservar unidade, fator, saldo e preço; conferir documentação de compra antes de qualquer conversão. Blindagem histórica não ampliada para classe/categoria de cabo não informada. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6GK19011BB102AE0).

Evidência: Ficha oficial Siemens 6GK1901-1BB10-2AE0; páginas 1. SHA-256: 50d4f50af0c8e98d2584427a4e432865341f25ece0aafd62ac743b9dd0e5218e. Arquivo: backups/fontes-lote-011/2535.pdf.

Atributos não confirmados: correspondencia_embalagem_com_unidade_ERP.

### ID 2641 — 3ZY1212-1BA00

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
CONECTOR DE DISPOSITIVOS PARA RELÉ DE SEGURANÇA 17,5mm

Referência Siemens 3ZY1212-1BA00. Conector entre dispositivos para 3SK1, largura 17,5mm, altura 117,5mm; montagem por parafuso/trilho DIN. Não é relé completo nem resistor de terminação de rede. Há cadastro com referência normalizada igual fora deste lote: 2698. Registrar possível duplicidade sem fundir, excluir ou alterar códigos. Limites elétricos não informados nesta ficha resumida. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3ZY12121BA00).

Evidência: Ficha oficial Siemens 3ZY1212-1BA00; páginas 1. SHA-256: 893904a02299469e724093335e8f6716c15c126d63e4b5f9db53c0ecba9bdec2. Arquivo: backups/fontes-lote-011/2641.pdf.

Atributos não confirmados: limites_eletricos, possivel_duplicidade_cadastral.

### ID 2642 — 3ZY1212-2DA00

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
CONECTOR DE TERMINAÇÃO PARA RELÉ DE SEGURANÇA 22,5mm

Referência Siemens 3ZY1212-2DA00. Conector de terminação para 3SK1, largura 22,5mm, altura 117,5mm; montagem por parafuso/trilho DIN. Não é relé completo nem resistor de terminação de rede. Há cadastro com referência normalizada igual fora deste lote: 2699. Registrar possível duplicidade sem fundir, excluir ou alterar códigos. Limites elétricos não informados nesta ficha resumida. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3ZY12122DA00).

Evidência: Ficha oficial Siemens 3ZY1212-2DA00; páginas 1. SHA-256: 788caade419628a9e94d04fdb251c4928a2cc0f4b3923fe6a05813524f2b0316. Arquivo: backups/fontes-lote-011/2642.pdf.

Atributos não confirmados: limites_eletricos, possivel_duplicidade_cadastral.

### ID 2643 — 3ZY1212-2BA00

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
CONECTOR DE DISPOSITIVOS PARA RELÉ DE SEGURANÇA 22,5mm

Referência Siemens 3ZY1212-2BA00. Conector entre dispositivos para 3SK1, largura 22,5mm, altura 117,5mm; montagem por parafuso/trilho DIN. Não é relé completo nem resistor de terminação de rede. Há cadastro com referência normalizada igual fora deste lote: 2700. Registrar possível duplicidade sem fundir, excluir ou alterar códigos. Limites elétricos não informados nesta ficha resumida. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3ZY12122BA00).

Evidência: Ficha oficial Siemens 3ZY1212-2BA00; páginas 1. SHA-256: 6d313c9ea711d3a401a3e0d5756dfed4712175c4c36ce3c888ebc31c463a103c. Arquivo: backups/fontes-lote-011/2643.pdf.

Atributos não confirmados: limites_eletricos, possivel_duplicidade_cadastral.

### ID 2889 — 3RQ3052-1SM50

Antes: DC 24V

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
RELÉ DE INTERFACE DE SAÍDA OPTOACOPLADO 1NA TRIAC ENTRADA 24VCC SAÍDA 20-264VCA 2A CONEXÃO POR PARAFUSO
DC 24V

Referência Siemens 3RQ3052-1SM50. Saída semicondutora não encaixável, triac 1NA; entrada nominal 24VCC, faixa 11-30VCC. Carga CA 20-264V, corrente 5mA-2A; saída não é protegida contra curto. Largura 6,2mm, LED verde e parafusos. Campo genérico Main circuit: DC não deve substituir saída CA explicitada no resumo e tabela de corrente AC. Não substituir pelo sucessor 3RQ4 indicado. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3RQ30521SM50).

Evidência: Ficha oficial Siemens 3RQ3052-1SM50; páginas 1, 2. SHA-256: d7540ff5b8a7d2cfa9e4db795eefd837b48ea620a43834c266f9f17c3910867d. Arquivo: backups/fontes-lote-011/2889.pdf.

### ID 2890 — 3RQ3118-1AE00

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
RELÉ DE INTERFACE COM RELÉ ENCAIXÁVEL 1 REVERSÍVEL 115VCA/CC CONEXÃO POR PARAFUSO

Referência Siemens 3RQ3118-1AE00. Acoplador de saída com relé encaixável, um contato reversível, largura 6,2mm e LED de estado. Corrente térmica 6A não é capacidade AC-15: saída 3A em 250VCA AC-15 e 1A em 24VCC DC-13; em 125VCC 0,2A e 250VCC 0,1A. Fusível gG 4A indicado para proteção dos contatos; saída não é à prova de curto. Frequência 50/60Hz aplica-se à entrada CA, não CC. Ficha declara produto descontinuado e cita sucessor 3RQ4: manter código, atividade e especificações do 3RQ3, sem substituição automática. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3RQ31181AE00).

Evidência: Ficha oficial Siemens 3RQ3118-1AE00; páginas 1, 2. SHA-256: b1129491aa26f4d1a5f7a06b61957e3bda73a45ed22d404af9662abb001a5b81. Arquivo: backups/fontes-lote-011/2890.pdf.

### ID 2891 — 3RQ3118-1AB00

Antes: (sem descrição complementar)

Depois: Cadastro anterior preservado como histórico (não validado integralmente):
RELÉ DE INTERFACE COM RELÉ ENCAIXÁVEL 1 REVERSÍVEL 24VCA/CC CONEXÃO POR PARAFUSO

Referência Siemens 3RQ3118-1AB00. Acoplador de saída com relé encaixável, um contato reversível, largura 6,2mm e LED de estado. Corrente térmica 6A não é capacidade AC-15: saída 3A em 250VCA AC-15 e 1A em 24VCC DC-13; em 125VCC 0,2A e 250VCC 0,1A. Fusível gG 4A indicado para proteção dos contatos; saída não é à prova de curto. Frequência 50/60Hz aplica-se à entrada CA, não CC. Ficha declara produto descontinuado e cita sucessor 3RQ4: manter código, atividade e especificações do 3RQ3, sem substituição automática. Conferir referência/placa e condições de montagem antes de dimensionar. Não presumir acessórios por foto. Alteração cadastral não autoriza intervenção elétrica nem certifica a instalação.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=3RQ31181AB00).

Evidência: Ficha oficial Siemens 3RQ3118-1AB00; páginas 1, 2. SHA-256: 97be62509755910e79aca02abc81b00a98adf1d9015349e129ef5e8b9dc6aae2. Arquivo: backups/fontes-lote-011/2891.pdf.

## Controle

Assinatura SHA-256 do manifesto: 588f94f2467f6f9871276cb46677686cf52c6284dbd131e701b0432552417219.

Manifesto: lote-011-cinquenta-itens.json.

Eventos de aplicação confirmados: 28.
