# Lote 008 — 50 itens

APLICADO E VERIFICADO

Data da revisão: 2026-09-09. Escopo: tenant 3ced7cfa-efbb-4f0f-addc-2028f60d1ca7; empresa f0e74f49-a127-46b4-901b-f7b37e43c690.

50 Siemens, todos com grupo: 7 CLPs, 10 módulos/placas digitais, 6 analógicos, 6 módulos de segurança, 4 interfaces/acopladores de remotas, 11 acessórios, 3 módulos de comunicação, 1 módulo de pesagem e 2 interfaces de operação. Alterações somente em nome e descrição complementar. Todos os 50 foram aplicados e verificados.

Grupo, código, fabricante, fornecedor, unidades, multiplicadores, preço, saldo e dados fiscais permanecem iguais. Cada comparação usa o cadastro real capturado, não um exemplo inventado.

As fontes técnicas e os registros de aplicação estão vinculados por ID. A ficha não substitui a conferência da placa/versão do item físico para dimensionamento.

## Ressalvas preservadas na aplicação

- CPUs e módulos G2 são identificados explicitamente. IDs 190/3208 não têm E/S analógicas integradas; a memória de programa é separada da memória de dados. Nas CPUs anteriores, a memória de trabalho é compartilhada.
- ID 3733: CPU de segurança ET200SP 1510SP F-1PN, não CPU S7-1200. A descrição será corrigida, mas grupo 55 permanece; eventual reclassificação exige avaliação separada. Requer Memory Card e BusAdapter para duas das três portas PROFINET.
- ID 1093: oito entradas no total, quatro utilizáveis como analógicas; não somar 8DI+4AI independentes. ID 914: saída rápida 0,1A/200kHz, não 0,5A. ID 2931: saída a relé, não transistor.
- Analógicos: resolução depende da faixa e geração. ID 731 mede corrente com transdutor de dois fios; ID 1091 não fornece 16bit em todas as faixas. ID 913: 14bit em tensão e 13bit em corrente.
- Interfaces 1095/3438 usam BusAdapter para duas portas; não confundir portas com interfaces. Servidor incluído não significa BusAdapter incluído. Acoplador 3439 é fornecido sem BusAdapter.
- Bases 732/3435 continuam o grupo de potencial; 3434 inicia novo grupo. ID 3440 é módulo servidor, não apenas base final. ID 204: a foto ilustrativa mostra outra capacidade; a tabela exata confirma 256MB.
- Versões de firmware/software citadas são as da ficha consultada; não garantem o firmware físico nem autorizam atualização. PL/SIL de um módulo não certifica o circuito completo.
- Fora do lote: ID 2461, código 6GK75421AX000XE0, ficha indisponível (HTTP 404). Não alterar código nem completar especificações por similaridade; consultar pesquisa-adiada-008.json.

Lote aprovado, aplicado e verificado: 50 itens. Modelos incorporados ao padrão ativo pela D-044, versão 1.32.0; ressalvas e grupo do ID 3733 preservados. O manifesto original conserva os critérios provisórios para manter a assinatura aprovada; os eventos usam critérios ativos. Lote 009 recebeu aprovação própria na D-045.

## Antes e depois dos 50

| Nº | ID / código | Antes | Depois aplicado |
| ---: | --- | --- | --- |
| 1 | 190<br>6ES72141AH500XB0 | CONTROLADOR PROGRAMÁVEL S7-1200 14DI/10DO 24VCC | CLP S7-1200 G2 CPU 1214C DC/DC/DC 14DI/10DO TRANSISTOR 0,5A 24VCC PROFINET 2 PORTAS |
| 2 | 191<br>6ES71316BH010BA0 | Módulo de entradas digitais para PLC ET200SP 16DI 24VCC | MÓDULO ENTRADAS DIGITAIS ET200SP 16DI 24VCC PARA SENSOR PNP ST BASE A0 |
| 3 | 199<br>6ES75261BH000AB0 | Módulo de entradas digitais de segurança para PLC ET200MP 16DI 24VCC | MÓDULO ENTRADAS DIGITAIS DE SEGURANÇA S7-1500 F-DI 16DI 24VCC |
| 4 | 200<br>6ES75262BF000AB0 | Módulo de saídas digitais de segurança para PLC ET200MP 8DO 24VCC 2A PPM | MÓDULO SAÍDAS DIGITAIS DE SEGURANÇA S7-1500 F-DQ 8DO 24VCC 2A PPM |
| 5 | 201<br>6ES75901AB600AA0 | Trilho de montagem para PLC S7-1500 160mm | TRILHO DE MONTAGEM S7-1500 160mm ALUMÍNIO ESTANHADO COM PARAFUSO DE ATERRAMENTO |
| 6 | 202<br>6ES75901AC400AA0 | Trilho de montagem para PLC S7-1500 245mm | TRILHO DE MONTAGEM S7-1500 245mm ALUMÍNIO ESTANHADO COM PARAFUSO DE ATERRAMENTO |
| 7 | 203<br>6ES75921AM000XB0 | Conector frontal com conexão por parafuso para PLC S7-1500 35mm | CONECTOR FRONTAL S7-1500 40 POLOS POR PARAFUSO PARA MÓDULOS DE 35mm COM 4 PONTES |
| 8 | 204<br>6ES79548LL040AA0 | Cartão de memória 256MB para PLC S7-1200/S7-1500 | CARTÃO DE MEMÓRIA SIMATIC S7-1X00 FLASH-EPROM 256MB 3,3V |
| 9 | 205<br>6GK75425DX100XE0 | Módulo de comunicação PROFIBUS DPV1 mestre/escravo para PLC S7-1500 | MÓDULO COMUNICAÇÃO S7-1500 CM1542-5 PROFIBUS DP MESTRE/DEVICE 1 PORTA SUB-D 9 PINOS ATÉ 12Mbit/s |
| 10 | 727<br>6ES71936AF000AA0 | BusAdapter BA 2xFC para estação ET200SP, 2 conexões FastConnect PROFINET | BUSADAPTER ET200SP BA2XFC PROFINET 2 PORTAS FASTCONNECT |
| 11 | 728<br>6ES71326BH010BA0 | Módulo de saídas digitais para PLC ET200SP 16DO 24VCC 0,5A | MÓDULO SAÍDAS DIGITAIS ET200SP 16DO TRANSISTOR PNP 24VCC 0,5A ST BASE A0 |
| 12 | 729<br>6ES71366BA010CA0 | Módulo de entradas digitais de segurança para PLC ET200SP 8DI 24VCC | MÓDULO ENTRADAS DIGITAIS DE SEGURANÇA ET200SP F-DI 8DI 24VCC HF |
| 13 | 730<br>6ES71366DC000CA0 | Módulo de saídas digitais de segurança para PLC ET200SP 8DO 24VCC | MÓDULO SAÍDAS DIGITAIS DE SEGURANÇA ET200SP F-DQ 8DO 24VCC 0,5A PP HF |
| 14 | 731<br>6ES71346HD010BA1 | Módulo de entradas analógicas para PLC ET200SP 4AI ±10V / ±5V / 1-5V / 0-10V / 0-20mA / 4-20mA 2 fios | MÓDULO ENTRADAS ANALÓGICAS ET200SP 4AI U/I ST ±10V/±5V/0-10V/1-5V/0-20mA/4-20mA 2 FIOS ATÉ 16BIT |
| 15 | 732<br>6ES71936BP000BA0 | Base para módulo ET200SP 15mm, 16 terminais push-in, sem terminais auxiliares, grupo de carga contínuo | BASEUNIT ET200SP BU15-P16+A0+2B TIPO A0 PUSH-IN SEM AUX CONTINUA GRUPO À ESQUERDA |
| 16 | 831<br>6ES72141AG400XB0 | CONTROLADOR PROGRAMÁVEL S7-1200 14DI/10DO/2AI 24VCC | CLP S7-1200 CPU 1214C DC/DC/DC 14DI/10DO TRANSISTOR 0,5A/2AI 0-10V 24VCC PROFINET 1 PORTA |
| 17 | 832<br>6ES72231BL320XB0 | MÓDULO DE ENTRADAS E SAÍDAS DIGITAIS PARA PLC S7-1200 16DI/16DO 24VCC | MÓDULO DIGITAL S7-1200 SM1223 16DI 24VCC SINK/SOURCE E 16DO TRANSISTOR 0,5A |
| 18 | 912<br>6ES72315PA300XB0 | MÓDULO DE ENTRADA RTD PARA PLC S7-1200 1AI Pt100/Pt1000 | PLACA DE SINAL S7-1200 SB1231 RTD 1AI PT100/PT1000 16BIT |
| 19 | 913<br>6ES72324HB320XB0 | MÓDULO DE SAÍDAS ANALÓGICAS PARA PLC S7-1200 2AO ±10V / 0-20mA / 4-20mA | MÓDULO SAÍDAS ANALÓGICAS S7-1200 SM1232 2AO ±10V 14BIT OU 0-20mA/4-20mA 13BIT |
| 20 | 914<br>6ES72221BD300XB0 | MÓDULO DE SAÍDAS DIGITAIS PARA PLC S7-1200 4DO 24VCC | PLACA DE SINAL S7-1200 SB1222 4DO MOSFET SINK/SOURCE 24VCC 0,1A 200kHz |
| 21 | 915<br>6ES72213BD300XB0 | MÓDULO DE ENTRADAS DIGITAIS PARA PLC S7-1200 4DI 24VCC | PLACA DE SINAL S7-1200 SB1221 4DI 24VCC SOURCING 200kHz |
| 22 | 931<br>6ES72111AE400XB0 | CONTROLADOR PROGRAMÁVEL S7-1200 6DI/4DO/2AI 24VCC | CLP S7-1200 CPU 1211C DC/DC/DC 6DI/4DO TRANSISTOR 0,5A/2AI 0-10V 24VCC PROFINET 1 PORTA |
| 23 | 979<br>6ED10551CB100BA2 | Módulo de expansão digital para PLC LOGO! 8 8DI/8DO 24VCC saídas PNP | MÓDULO EXPANSÃO DIGITAL LOGO! 8 DM16 24 8DI/8DO TRANSISTOR 24VCC 0,3A |
| 24 | 1091<br>6ES71356HD000BA1 | Módulo de saídas analógicas para PLC ET200SP 4AO ±10V / ±5V / 1-5V / 0-10V / ±20mA / 0-20mA / 4-20mA | MÓDULO SAÍDAS ANALÓGICAS ET200SP 4AO U/I ST ±10V/±5V/0-10V/1-5V/±20mA/0-20mA/4-20mA ATÉ 16BIT |
| 25 | 1092<br>6ED10554MH080BA1 | Interface homem-máquina com display para controlador LOGO! 8 | DISPLAY DE TEXTO LOGO! TDE 6 LINHAS×20 CARACTERES 2 PORTAS ETHERNET 12/24VCC OU 24VCA |
| 26 | 1093<br>6ED10521MD080BA1 | Controlador programável LOGO! 8 8DI/4DO relé 12/24VCC com display e Ethernet | CLP LOGO! 8.3 12/24RCE 8DI (4 COMPARTILHADAS COM AI)/4DO RELÉ 12/24VCC DISPLAY E ETHERNET |
| 27 | 1094<br>6ES72141AF400XB0 | CONTROLADOR PROGRAMÁVEL S7-1200 CPU 1214FC | CLP DE SEGURANÇA S7-1200F CPU 1214FC DC/DC/DC 14DI/10DO TRANSISTOR 0,5A/2AI 0-10V 24VCC PROFINET 1 PORTA |
| 28 | 1095<br>6ES71556AU020BN0 | Cabeça de rede PROFINET para estação ET200SP até 32 módulos de E/S | INTERFACE REMOTA ET200SP IM155-6PN ST PROFINET 2 PORTAS VIA BUSADAPTER ATÉ 32 MÓDULOS 24VCC |
| 29 | 1096<br>6ES72266DA320XB0 | Módulo de saídas digitais de segurança para PLC S7-1200 4DO 24VCC | MÓDULO SAÍDAS DIGITAIS DE SEGURANÇA S7-1200 SM1226 F-DQ 4DO 24VCC 2A |
| 30 | 2140<br>6ES72221BH320XB0 | MÓDULO DE SAÍDAS DIGITAIS PARA PLC S7-1200 16DO 24VCC | MÓDULO SAÍDAS DIGITAIS S7-1200 SM1222 16DO TRANSISTOR 24VCC 0,5A |
| 31 | 2446<br>6ES72411CH320XB0 | Módulo de comunicação RS422/RS485 para PLC S7-1200 com conector SUB-D 9 pinos | MÓDULO COMUNICAÇÃO S7-1200 CM1241 RS422/RS485 1 PORTA SUB-D 9 PINOS FÊMEA MODBUS RTU |
| 32 | 2448<br>7MH49602AA01 | Módulo de pesagem SIWAREX WP231 para PLC S7-1200 ou operação autônoma, 1 canal, 4DI/4DO, 1AO, RS485 e Ethernet | MÓDULO PESAGEM SIWAREX WP231 1 CANAL CÉLULA PONTE COMPLETA 1-4mV/V 24VCC S7-1200 OU AUTÔNOMO |
| 33 | 2449<br>6GK72435DX300XE0 | Módulo de comunicação PROFIBUS DP mestre para PLC S7-1200 | MÓDULO COMUNICAÇÃO S7-1200 CM1243-5 PROFIBUS DP MESTRE 1 PORTA SUB-D 9 PINOS 12Mbit/s 24VCC |
| 34 | 2463<br>6AV21240JC010AX0 | Interface homem-máquina touchscreen 9″ | IHM TP900 COMFORT 9POL TOUCH RESISTIVO TFT 800×480 PROFINET 2 PORTAS E MPI/PROFIBUS DP 24VCC |
| 35 | 2737<br>6ES72235BL500XB0 | MÓDULO DE ENTRADAS E SAÍDAS DIGITAIS PARA PLC S7-1200 16DI/16DO 24VCC | MÓDULO DIGITAL S7-1200 G2 SM1223 16DI 24VCC SINK/SOURCE E 16DO TRANSISTOR PNP 0,5A |
| 36 | 2930<br>6ES72211BH500XB0 | MÓDULO DE ENTRADAS DIGITAIS PARA PLC S7-1200 16DI 24VCC | MÓDULO ENTRADAS DIGITAIS S7-1200 G2 SM1221 16DI 24VCC SINK/SOURCE |
| 37 | 2931<br>6ES72235PH500XB0 | MÓDULO DE ENTRADAS E SAÍDAS DIGITAIS PARA PLC S7-1200 8DI/8DO A RELÉ | MÓDULO DIGITAL S7-1200 G2 SM1223 8DI 24VCC SINK/SOURCE E 8DO RELÉ 2A |
| 38 | 3129<br>6ES72314HF320XB0 | MÓDULO DE ENTRADAS ANALÓGICAS PARA PLC S7-1200 8AI ±10V / ±5V / ±2,5V / 0-20mA / 4-20mA | MÓDULO ENTRADAS ANALÓGICAS S7-1200 SM1231 8AI ±10V/±5V/±2,5V/0-20mA/4-20mA 12BIT+SINAL |
| 39 | 3208<br>6ES72121AG500XB0 | CONTROLADOR PROGRAMÁVEL S7-1200 8DI/6DO 24VCC | CLP S7-1200 G2 CPU 1212C DC/DC/DC 8DI/6DO TRANSISTOR 0,5A 24VCC PROFINET 2 PORTAS |
| 40 | 3209<br>6ES72314HF500XB0 | MÓDULO DE ENTRADAS ANALÓGICAS PARA PLC S7-1200 8AI ±10V / ±5V / ±2,5V / 0-20mA / 4-20mA | MÓDULO ENTRADAS ANALÓGICAS S7-1200 G2 SM1231 8AI ±10V/±5V/±2,5V/0-20mA/4-20mA 14BIT |
| 41 | 3432<br>6ES71936AG200AA0 | BusAdapter BA LC/RJ45 para estação ET200SP, 1 conexão LC fibra óptica e 1 conexão RJ45 PROFINET | BUSADAPTER PROFINET BA LC/RJ45 2 PORTAS 1 LC FIBRA MULTIMODO E 1 RJ45 COBRE |
| 42 | 3433<br>6ES71580AD010XA0 | Módulo acoplador DP/DP para redes PROFIBUS, linha SIMATIC DP, com alimentação redundante | ACOPLADOR DP/DP ENTRE 2 REDES PROFIBUS DP ALIMENTAÇÃO REDUNDANTE 24VCC |
| 43 | 3434<br>6ES71936BP200DA0 | Base para módulo ET200SP 15mm, 16 terminais push-in, 10 terminais auxiliares, novo grupo de carga | BASEUNIT ET200SP BU15-P16+A10+2D TIPO A0 PUSH-IN 10 AUX NOVO GRUPO DE POTENCIAL |
| 44 | 3435<br>6ES71936BP200BA0 | Base para módulo ET200SP 15mm, 16 terminais push-in, 10 terminais auxiliares, grupo de carga contínuo | BASEUNIT ET200SP BU15-P16+A10+2B TIPO A0 PUSH-IN 10 AUX CONTINUA GRUPO À ESQUERDA |
| 45 | 3436<br>6ES71936AR000AA0 | BusAdapter BA 2xRJ45 para estação ET200SP, 2 portas RJ45 PROFINET | BUSADAPTER ET200SP BA2XRJ45 PROFINET 2 PORTAS RJ45 |
| 46 | 3437<br>6ES71366DB000CA0 | Módulo de saídas digitais de segurança para PLC ET200SP 4DO 24VCC | MÓDULO SAÍDAS DIGITAIS DE SEGURANÇA ET200SP F-DQ 4DO 24VCC 2A PM HF |
| 47 | 3438<br>6ES71556AU010CN0 | Cabeça de rede PROFINET para estação ET200SP, 2 portas PROFINET, até 64 módulos de E/S | INTERFACE REMOTA ET200SP IM155-6PN/2 HF PROFINET 2 PORTAS VIA BUSADAPTER ATÉ 64 MÓDULOS 24VCC |
| 48 | 3439<br>6ES71583AD100XA0 | Módulo acoplador PN/PN para redes PROFINET com troca determinística de dados | ACOPLADOR PN/PN PROFINET ATÉ 4 CONTROLADORES POR SUB-REDE 24VCC SEM BUSADAPTER |
| 49 | 3440<br>6ES71936PA000AA0 | Base final para PLC ET200SP | MÓDULO SERVIDOR SIMATIC ET200SP 7×117×36mm |
| 50 | 3733<br>6ES75101SJ010AB0 | CONTROLADOR PROGRAMÁVEL S7-1500 F-1 PN 150KB 750KB 1 INTERFACE PROFINET IRT | CLP DE SEGURANÇA ET200SP CPU 1510SP F-1PN 24VCC PROGRAMA 150KB DADOS 750KB PROFINET IRT 3 PORTAS |

## Descrição complementar e evidências por item

### ID 190 — 6ES7214-1AH50-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7214-1AH50-0XB0. CPU compacta de segunda geração G2. Alimentação nominal 24VCC, faixa 20,4-28,8VCC; 14 entradas digitais 24VCC e 10 saídas digitais 24VCC, 0,5A por saída para carga resistiva. Sem entradas ou saídas analógicas integradas. Memórias separadas: programa 250KB, dados 750KB e retenção 20KB; não somar nem confundir com memória de carga. Uma interface PROFINET, duas portas RJ45 e switch integrado, até 100Mbit/s. A ficha atual informa firmware V4.1 e STEP 7 V21 ou superior; isso não comprova firmware instalado nem autoriza atualização. Não copiar E/S analógicas ou compatibilidades da geração anterior. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72141AH500XB0).

Evidência: Ficha oficial Siemens 6ES7214-1AH50-0XB0; páginas 1, 3, 4. SHA-256: 2416ee11c64ecd134fecec15f13a6d17ce25a895779d7ebb746b3a0f0bcb9f07. Arquivo: backups/fontes-lote-008/190.pdf.

### ID 191 — 6ES7131-6BH01-0BA0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7131-6BH01-0BA0. DI16x24VDC ST, entrada sink/P-reading para sensor PNP, tipo 3 IEC 61131. Dezesseis entradas; BaseUnit A0, código de cor CC00. Alimentação 24VCC (19,2-28,8VCC). Diagnósticos de ruptura de fio e alimentação. Não confundir lógica da entrada com saída PNP de um módulo DQ. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71316BH010BA0).

Evidência: Ficha oficial Siemens 6ES7131-6BH01-0BA0; páginas 1. SHA-256: b82a5183ba48b41c5c499fcd13cb6937849c53f66f73a0c30d79091e1691838f. Arquivo: backups/fontes-lote-008/191.pdf.

### ID 199 — 6ES7526-1BH00-0AB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7526-1BH00-0AB0. Módulo de segurança F-DI, 16DI em 24VCC; largura 35mm. A quantidade é de canais físicos; configuração redundante pode consumir mais de um canal por função. O fabricante informa possibilidade de até PL e/SIL3 nas condições aplicáveis; o cadastro não certifica a função ou circuito completo. Preservar distinção PP, PM e PPM, sem substituir uma topologia por outra. Comunicação de segurança PROFIsafe confirmada no resumo da referência. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES75261BH000AB0).

Evidência: Ficha oficial Siemens 6ES7526-1BH00-0AB0; páginas 1. SHA-256: 4d0d994e1e324a763ebfbcaa920f7f5e640ec61e30bec5019bfafbf148a70018. Arquivo: backups/fontes-lote-008/199.pdf.

### ID 200 — 6ES7526-2BF00-0AB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7526-2BF00-0AB0. Módulo de segurança F-DQ, 8DO em 24VCC, variante 2A PPM; largura 35mm. A quantidade é de canais físicos; configuração redundante pode consumir mais de um canal por função. O fabricante informa possibilidade de até PL e/SIL3 nas condições aplicáveis; o cadastro não certifica a função ou circuito completo. Preservar distinção PP, PM e PPM, sem substituir uma topologia por outra. Comunicação de segurança PROFIsafe confirmada no resumo da referência. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES75262BF000AB0).

Evidência: Ficha oficial Siemens 6ES7526-2BF00-0AB0; páginas 1. SHA-256: cc24b9b9aef58331bd67027c13455c3b5647b45d9be9d867517c64ff8e26b5fc. Arquivo: backups/fontes-lote-008/200.pdf.

### ID 201 — 6ES7590-1AB60-0AA0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7590-1AB60-0AA0. Trilho de montagem SIMATIC S7-1500, alumínio com estanhagem galvânica. Dimensões 160×155×16mm. Inclui parafuso de aterramento e trilho DIN integrado para acessórios como bornes, disjuntores e relés. Não é trilho DIN genérico de mesma extensão. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES75901AB600AA0).

Evidência: Ficha oficial Siemens 6ES7590-1AB60-0AA0; páginas 1. SHA-256: 07cb30247abde0dbb033e9eb6f1742321ae7001772831a8e0710916934ab6dd7. Arquivo: backups/fontes-lote-008/201.pdf.

### ID 202 — 6ES7590-1AC40-0AA0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7590-1AC40-0AA0. Trilho de montagem SIMATIC S7-1500, alumínio com estanhagem galvânica. Dimensões 245×155×16mm. Inclui parafuso de aterramento e trilho DIN integrado para acessórios como bornes, disjuntores e relés. Não é trilho DIN genérico de mesma extensão. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES75901AC400AA0).

Evidência: Ficha oficial Siemens 6ES7590-1AC40-0AA0; páginas 1. SHA-256: baf3c07815832e356fc0f51ed73d06f30c4f9a86b15eb25bf5169c5bc477d8ca. Arquivo: backups/fontes-lote-008/202.pdf.

### ID 203 — 6ES7592-1AM00-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7592-1AM00-0XB0. Conector frontal de 40 polos, conexão por parafuso, para módulos S7-1500 de largura 35mm; inclui quatro pontes de potencial e abraçadeiras. Condutores 0,25-1,5mm² por conexão segundo tabela. Os 35mm são largura do módulo compatível, não passo dos contatos. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES75921AM000XB0).

Evidência: Ficha oficial Siemens 6ES7592-1AM00-0XB0; páginas 1. SHA-256: 18b342989d19977d3d96ea337406c1182d132a034f859722c8dd7b306d0e111e. Arquivo: backups/fontes-lote-008/203.pdf.

### ID 204 — 6ES7954-8LL04-0AA0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7954-8LL04-0AA0. SIMATIC Memory Card para CPU S7-1x00, Flash-EPROM de 256MB, 3,3V. A foto é ilustrativa e mostra outra capacidade; usar a tabela da referência 8LL04. Não confundir memória de carga removível com memória de trabalho da CPU nem substituir por cartão SD genérico. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES79548LL040AA0).

Evidência: Ficha oficial Siemens 6ES7954-8LL04-0AA0; páginas 1. SHA-256: a66525da5f809dffaba5ac3706f079727a3fef0605a367b3c9ff57dafe815d54. Arquivo: backups/fontes-lote-008/204.pdf.

### ID 205 — 6GK7542-5DX10-0XE0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6GK7542-5DX10-0XE0. CM1542-5 para S7-1500, PROFIBUS DP como mestre DPV1 ou DP Device. Uma conexão fêmea Sub-D de nove pinos, RS485, 9,6kbit/s a 12Mbit/s. Comunicação S7 e PG/OP, roteamento de registros e sincronização de tempo. Alimentação pelo barramento traseiro 15VCC; não atribuir 24VCC externo por analogia com CM1243-5. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6GK75425DX100XE0).

Evidência: Ficha oficial Siemens 6GK7542-5DX10-0XE0; páginas 1. SHA-256: d0e417c04b8beea4982d5cf4eb0e8f4a5ad3307ba708da3c5bed20b75821fb61. Arquivo: backups/fontes-lote-008/205.pdf.

### ID 727 — 6ES7193-6AF00-0AA0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7193-6AF00-0AA0. BusAdapter BA2XFC, uma interface PROFINET com switch de duas portas FastConnect para conexão direta do cabo de cobre, não duas tomadas RJ45. Comprimento máximo de cabo de cobre 100m conforme ficha. Conferir compatibilidade da CPU/interface remota; não é módulo de E/S nem switch autônomo alimentado externamente. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71936AF000AA0).

Evidência: Ficha oficial Siemens 6ES7193-6AF00-0AA0; páginas 1. SHA-256: 94f04c874410d52f53ba0cfb48f777fc2228b6437e3cf7c37ff310d11bd0dceb. Arquivo: backups/fontes-lote-008/727.pdf.

### ID 728 — 6ES7132-6BH01-0BA0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7132-6BH01-0BA0. DQ16x24VDC/0.5A ST, dezesseis saídas source/PNP/P-switching. Alimentação 24VCC (19,2-28,8VCC), BaseUnit A0 e código CC00. Diagnósticos de curto-circuito, ruptura de fio e alimentação. A corrente de 0,5A é por canal; respeitar limites de soma e temperatura do módulo. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71326BH010BA0).

Evidência: Ficha oficial Siemens 6ES7132-6BH01-0BA0; páginas 1. SHA-256: 21148527a3b89a87f551b5cd392e4f417a459cc2132d3cdd319211b7306fe39c. Arquivo: backups/fontes-lote-008/728.pdf.

### ID 729 — 6ES7136-6BA01-0CA0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7136-6BA01-0CA0. Módulo de segurança F-DI, 8DI em 24VCC, variante HF; largura 15mm. Utiliza BaseUnit A0. A quantidade é de canais físicos; configuração redundante pode consumir mais de um canal por função. O fabricante informa possibilidade de até PL e/SIL3 nas condições aplicáveis; o cadastro não certifica a função ou circuito completo. Preservar distinção PP, PM e PPM, sem substituir uma topologia por outra. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71366BA010CA0).

Evidência: Ficha oficial Siemens 6ES7136-6BA01-0CA0; páginas 1. SHA-256: 0f342dcfeedfa9cba932869d2a3f1af29b8c8caadd2e6897ee951642acb83cf4. Arquivo: backups/fontes-lote-008/729.pdf.

### ID 730 — 6ES7136-6DC00-0CA0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7136-6DC00-0CA0. Módulo de segurança F-DQ, 8DO em 24VCC, variante 0,5A PP HF; largura 15mm. Utiliza BaseUnit A0. A quantidade é de canais físicos; configuração redundante pode consumir mais de um canal por função. O fabricante informa possibilidade de até PL e/SIL3 nas condições aplicáveis; o cadastro não certifica a função ou circuito completo. Preservar distinção PP, PM e PPM, sem substituir uma topologia por outra. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71366DC000CA0).

Evidência: Ficha oficial Siemens 6ES7136-6DC00-0CA0; páginas 1. SHA-256: 4e2b36724b1cefd0c7971dc89d93d909d64da3b7e1ba81e82bbc5d47d4ca7729. Arquivo: backups/fontes-lote-008/730.pdf.

### ID 731 — 6ES7134-6HD01-0BA1

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7134-6HD01-0BA1. AI4xU/I 2-wire ST, quatro canais diferenciais tensão/corrente, BaseUnit A0/A1 e CC03. Alimentação 24VCC (19,2-28,8VCC). Faixas ±10V e ±5V com 16bit incluindo sinal; 0-10V, 1-5V, 0-20mA e 4-20mA com 15bit. Corrente para transdutor de dois fios; a ficha não admite transdutor de corrente de quatro fios nesta referência. Não chamar todos os modos de 16bit nem confundir limite de destruição com faixa de medição. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71346HD010BA1).

Evidência: Ficha oficial Siemens 6ES7134-6HD01-0BA1; páginas 1, 2. SHA-256: b2b7c300a7dff692d20c1ccbd09ae7f53681fbf5bbc2d34bb67b0ffe9a694ac1. Arquivo: backups/fontes-lote-008/731.pdf.

### ID 732 — 6ES7193-6BP00-0BA0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7193-6BP00-0BA0. BaseUnit tipo A0, modelo BU15-P16+A0+2B; terminais push-in, sem terminais auxiliares. Continua o grupo de potencial por ponte à esquerda; não inicia grupo novo. Dimensões largura×altura 15×117mm. Tensão nominal 24VCC; barramentos P1/P2 máximo 10A e terminais de processo máximo 2A. Não confundir base de conexão com módulo eletrônico de E/S. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71936BP000BA0).

Evidência: Ficha oficial Siemens 6ES7193-6BP00-0BA0; páginas 1. SHA-256: 51a1658f04b5d20f1b180eb03beca1f0022f3baacb4c2781b40addc913448cd3. Arquivo: backups/fontes-lote-008/732.pdf.

### ID 831 — 6ES7214-1AG40-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7214-1AG40-0XB0. CPU compacta 1214C, não G2. Alimentação 24VCC, faixa 20,4-28,8VCC. 14DI 24VCC, 10DO transistor 24VCC/0,5A para carga resistiva e 2AI 0-10V de 10bit; sem saídas analógicas integradas. Memória de trabalho compartilhada de programa/dados 150KB; não duplicar essa capacidade. Uma interface PROFINET com uma porta RJ45. A ficha atual informa firmware V4.7 e STEP 7 V20 ou superior, não a versão efetivamente instalada. Não intercambiar especificações com CPU G2 de número de modelo semelhante. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72141AG400XB0).

Evidência: Ficha oficial Siemens 6ES7214-1AG40-0XB0; páginas 1, 3. SHA-256: faf8df45485ee5dcee1e76d8d5a34302627a5100d1a395748813dd598f7c0e11. Arquivo: backups/fontes-lote-008/831.pdf.

### ID 832 — 6ES7223-1BL32-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7223-1BL32-0XB0. SM1223 geração anterior à G2: dezesseis entradas 24VCC sink/source e dezesseis saídas transistor 24VCC/0,5A. Alimentação 24VCC, faixa 20,4-28,8VCC. Não presumir compatibilidade mecânica/elétrica entre SM1223 de gerações diferentes. Corrente por canal sujeita aos limites de carga e agrupamento da ficha. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72231BL320XB0).

Evidência: Ficha oficial Siemens 6ES7223-1BL32-0XB0; páginas 1. SHA-256: 461292ff616b187ce741167ab68748cdc41fad35e194d251b2a90b683dbe36b9. Arquivo: backups/fontes-lote-008/832.pdf.

### ID 912 — 6ES7231-5PA30-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7231-5PA30-0XB0. Signal Board SB1231 RTD com uma entrada para termorresistência, resolução nominal 16bit e alimentação nominal 24VCC. Pt100/Pt1000 no resumo; tabela também confirma Pt200/Pt500 e resistência 150Ω/300Ω/600Ω. Não é entrada de termopar nem cartão genérico 4-20mA. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72315PA300XB0).

Evidência: Ficha oficial Siemens 6ES7231-5PA30-0XB0; páginas 1. SHA-256: 1e74b308cdf5fed97cc680a35257c6eea9993d131f1e0e62950e7c55f2fb672e. Arquivo: backups/fontes-lote-008/912.pdf.

### ID 913 — 6ES7232-4HB32-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7232-4HB32-0XB0. SM1232, duas saídas analógicas configuráveis para ±10V com 14bit ou 0-20mA/4-20mA com 13bit. Alimentação nominal 24VCC. Carga mínima 1kΩ para tensão e máxima 600Ω para corrente. Não são quatro saídas nem resolução única de 14bit em corrente. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72324HB320XB0).

Evidência: Ficha oficial Siemens 6ES7232-4HB32-0XB0; páginas 1. SHA-256: 5fcb89f06460eb4bcf395896205a4ad0e168b7f5fdbf79e87e1014883a949ddc. Arquivo: backups/fontes-lote-008/913.pdf.

### ID 914 — 6ES7222-1BD30-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7222-1BD30-0XB0. Signal Board SB1222, quatro saídas digitais MOSFET sink/source 24VCC, até 200kHz. Corrente nominal 0,1A por saída para carga resistiva, não 0,5A dos módulos SM1222. Sem proteção contra curto-circuito integrada. Alimentação de eletrônica pelo barramento 5VCC, consumo típico 35mA. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72221BD300XB0).

Evidência: Ficha oficial Siemens 6ES7222-1BD30-0XB0; páginas 1. SHA-256: c906d180ceea43dcebac236737acc215d27a5e16f0e0714a6b3b5e4edb347043. Arquivo: backups/fontes-lote-008/914.pdf.

### ID 915 — 6ES7221-3BD30-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7221-3BD30-0XB0. Signal Board SB1221, quatro entradas digitais 24VCC current-sourcing, até 200kHz. Não converter para entrada sink/PNP por analogia com outros módulos. Alimentação de eletrônica pelo barramento 5VCC, consumo típico 40mA. Não é módulo lateral SM1221. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72213BD300XB0).

Evidência: Ficha oficial Siemens 6ES7221-3BD30-0XB0; páginas 1. SHA-256: 553d9a4a8c394d7b99c370f3f1bf3ce5a091a91803c829f6f7d826270744df1f. Arquivo: backups/fontes-lote-008/915.pdf.

### ID 931 — 6ES7211-1AE40-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7211-1AE40-0XB0. CPU compacta 1211C, não G2. Alimentação 24VCC, faixa 20,4-28,8VCC. 6DI 24VCC, 4DO transistor 24VCC/0,5A para carga resistiva e 2AI 0-10V de 10bit; sem saídas analógicas integradas. Memória de trabalho compartilhada de programa/dados 75KB; não duplicar essa capacidade. Uma interface PROFINET com uma porta RJ45. A ficha atual informa firmware V4.7 e STEP 7 V20 ou superior, não a versão efetivamente instalada. Não intercambiar especificações com CPU G2 de número de modelo semelhante. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72111AE400XB0).

Evidência: Ficha oficial Siemens 6ES7211-1AE40-0XB0; páginas 1, 3. SHA-256: e686c949682e23cb17e732671d975d875e18c1bf0597cb98bf3ef3cce7c01b9e. Arquivo: backups/fontes-lote-008/931.pdf.

### ID 979 — 6ED1055-1CB10-0BA2

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ED1055-1CB10-0BA2. Expansão LOGO! DM16 24 para LOGO! 8, oito entradas e oito saídas digitais transistor. Alimentação/sinais 24VCC; faixa de alimentação 20,4-28,8VCC. Corrente nominal 0,3A por saída. Montagem em trilho DIN35mm, largura de quatro módulos: a indicação 4MW significa largura modular, não potência em megawatts. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ED10551CB100BA2).

Evidência: Ficha oficial Siemens 6ED1055-1CB10-0BA2; páginas 1. SHA-256: 344090c0f6f7836871e5ef0a7c3f5ba474259f8d461b6f8b327f469fedcfde5a. Arquivo: backups/fontes-lote-008/979.pdf.

### ID 1091 — 6ES7135-6HD00-0BA1

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7135-6HD00-0BA1. AQ4xU/I ST, quatro canais, BaseUnit A0/A1, CC00 e alimentação 24VCC (19,2-28,8VCC). Resolução depende da faixa: ±10V e ±20mA 16bit incluindo sinal; ±5V 15bit incluindo sinal; 0-10V e 0-20mA 15bit; 1-5V 13bit; 4-20mA 14bit. Carga de tensão mínimo 2kΩ e de corrente máximo 500Ω. Ligações de tensão a dois ou quatro fios; corrente a dois fios. Não são oito canais por admitir tensão e corrente. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71356HD000BA1).

Evidência: Ficha oficial Siemens 6ES7135-6HD00-0BA1; páginas 1, 2. SHA-256: e374832f61a0637b36eea3e385f2e5a38fe7e7ad606bc2ff5c45b96c77b01588. Arquivo: backups/fontes-lote-008/1091.pdf.

### ID 1092 — 6ED1055-4MH08-0BA1

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ED1055-4MH08-0BA1. Display FSTN para LOGO! 8 ou superior, seis linhas de vinte caracteres, iluminação de fundo em três cores e duas portas Ethernet. Alimentação 12/24VCC ou 24VCA. IP65 somente no frontal. Não é CPU LOGO! nem tela touchscreen colorida. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ED10554MH080BA1).

Evidência: Ficha oficial Siemens 6ED1055-4MH08-0BA1; páginas 1. SHA-256: cca66e146634b40a1cf8cb869f97a7d51bedf2cfcca45666366d2d664121650e. Arquivo: backups/fontes-lote-008/1092.pdf.

### ID 1093 — 6ED1052-1MD08-0BA1

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ED1052-1MD08-0BA1. LOGO! 12/24RCE versão 8.3, alimentação 12/24VCC (10,8-28,8VCC), display integrado e Ethernet. Oito entradas digitais, das quais quatro podem funcionar como analógicas 0-10V; não são doze entradas independentes. Quatro saídas a relé: máximo 10A em carga resistiva e 3A em carga indutiva, com proteção externa necessária. Memória para 400 blocos, LOGO! Soft Comfort V8.3 ou superior. Preservar referência antiga, sem substituir automaticamente pela geração seguinte. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ED10521MD080BA1).

Evidência: Ficha oficial Siemens 6ED1052-1MD08-0BA1; páginas 1. SHA-256: e08205859cd100c4baf4002a600ee8342f8fa2a7c7260f0be8d857c378a7c978. Arquivo: backups/fontes-lote-008/1093.pdf.

### ID 1094 — 6ES7214-1AF40-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7214-1AF40-0XB0. CPU compacta 1214FC, não G2. Alimentação 24VCC, faixa 20,4-28,8VCC. 14DI 24VCC, 10DO transistor 24VCC/0,5A para carga resistiva e 2AI 0-10V de 10bit; sem saídas analógicas integradas. Memória de trabalho compartilhada de programa/dados 200KB; não duplicar essa capacidade. Uma interface PROFINET com uma porta RJ45. A ficha atual informa firmware V4.7 e STEP 7 V20 ou superior, não a versão efetivamente instalada. CPU F de segurança: não tratar automaticamente todas as E/S integradas como E/S F nem certificar a função de segurança do circuito completo. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72141AF400XB0).

Evidência: Ficha oficial Siemens 6ES7214-1AF40-0XB0; páginas 1, 3. SHA-256: e5a6c73af7147d9a13a2da94daddb3da95522f448f676af114827431ce0b4a9e. Arquivo: backups/fontes-lote-008/1094.pdf.

### ID 1095 — 6ES7155-6AU02-0BN0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7155-6AU02-0BN0. IM155-6PN ST: uma interface PROFINET com duas portas via BusAdapter, não duas tomadas RJ45 fixas incluídas. Até 32 módulos ET200SP e 16 ET200AL; inclui módulo servidor 6ES7193-6PA00-0AA0. Alimentação 24VCC (19,2-28,8VCC). Suporta multi-hot-swap; não suporta redundância de sistema S2 nesta ficha. Capacidades de software devem ser conferidas com firmware físico; ficha atual V6.4.0, STEP 7 V20. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71556AU020BN0).

Evidência: Ficha oficial Siemens 6ES7155-6AU02-0BN0; páginas 1, 2. SHA-256: 67e3d276f6f1cb1d73bbb6ea63785d299b09f2b4bf7d6948100abb775a77d43e. Arquivo: backups/fontes-lote-008/1095.pdf.

### ID 1096 — 6ES7226-6DA32-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7226-6DA32-0XB0. Módulo de segurança F-DQ, 4DO em 24VCC, variante 2A; largura 70mm. A quantidade é de canais físicos; configuração redundante pode consumir mais de um canal por função. O fabricante informa possibilidade de até PL e/SIL3 nas condições aplicáveis; o cadastro não certifica a função ou circuito completo. Preservar distinção PP, PM e PPM, sem substituir uma topologia por outra. Comunicação de segurança PROFIsafe confirmada no resumo da referência. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72266DA320XB0).

Evidência: Ficha oficial Siemens 6ES7226-6DA32-0XB0; páginas 1. SHA-256: 53defc4331a470af61745ecd52c72f9b9ea8c746b18ebf211b26d81490c46f55. Arquivo: backups/fontes-lote-008/1096.pdf.

### ID 2140 — 6ES7222-1BH32-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7222-1BH32-0XB0. SM1222, dezesseis saídas digitais transistor 24VCC, corrente nominal 0,5A por saída para carga resistiva. Alimentação 20,4-28,8VCC. Não possui proteção interna contra curto-circuito: prever proteção externa conforme fabricante. Não é placa frontal SB1222. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72221BH320XB0).

Evidência: Ficha oficial Siemens 6ES7222-1BH32-0XB0; páginas 1. SHA-256: b9e24e2c75bfb5a11800b86bd922207ddb1fe9b46d77752900f48beaa578a24a. Arquivo: backups/fontes-lote-008/2140.pdf.

### ID 2446 — 6ES7241-1CH32-0XB0

Antes: SIMATIC S7-1200, SUPORTA MENSAGEM BASEADO EM FREEPORT

Depois: Descrição anterior preservada como histórico (não validada integralmente):
SIMATIC S7-1200, SUPORTA MENSAGEM BASEADO EM FREEPORT

Referência Siemens 6ES7241-1CH32-0XB0. CM1241 com uma interface RS422/RS485, conector Sub-D de nove pinos fêmea. Suporta Freeport e Modbus RTU mestre/device; ASCII e USS disponíveis por biblioteca. Consumo máximo 220mA do barramento traseiro 5VCC. Não é RS232 nem interface Ethernet. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72411CH320XB0).

Evidência: Ficha oficial Siemens 6ES7241-1CH32-0XB0; páginas 1. SHA-256: ba417cc3fe7016ae460d99550a27e0cf4c3c3e0aa994761456426f343b153607. Arquivo: backups/fontes-lote-008/2446.pdf.

### ID 2448 — 7MH4960-2AA01

Antes: SIWAREX WP231 SIMATIC S7-1200 ou autônomo, RS485 e Interface Ethernet, E/S integrada: 4 DI/4 DO, 1 AO (0/4...20mA)

Depois: Descrição anterior preservada como histórico (não validada integralmente):
SIWAREX WP231 SIMATIC S7-1200 ou autônomo, RS485 e Interface Ethernet, E/S integrada: 4 DI/4 DO, 1 AO (0/4...20mA)

Referência Siemens 7MH4960-2AA01. SIWAREX WP231 para uma balança de plataforma ou silo, células analógicas de extensometria em ponte completa 1-4mV/V. Alimentação 24VCC (19,2-28,8VCC), operação no S7-1200 ou independente. Quatro DI, quatro DQ 24VCC/0,5A para carga resistiva, uma AQ, uma RS485, uma Ethernet e uma interface de célula de carga. Não é célula de carga nem inclui automaticamente célula/caixa de junção. Uso comercial metrológico depende das condições e aprovações aplicáveis, não é garantido pelo cadastro. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=7MH49602AA01).

Evidência: Ficha oficial Siemens 7MH4960-2AA01; páginas 1. SHA-256: 5c27f287b9b72eea4f6310671b2a571bed3525b794ee0f4d40b8ad480dec8f16. Arquivo: backups/fontes-lote-008/2448.pdf.

### ID 2449 — 6GK7243-5DX30-0XE0

Antes: projetado para conectar controladores SIMATIC S7-1200 à rede PROFIBUS atuando como mestre DP (DP Master).  Este dispositivo suporta taxas de transferência de 9,6 kbit/s a 12 Mbit/s, permitindo a conexão de até 32 escravos DP e oferecendo capacidades de comunicação S7 e PG/OP

Depois: Descrição anterior preservada como histórico (não validada integralmente):
projetado para conectar controladores SIMATIC S7-1200 à rede PROFIBUS atuando como mestre DP (DP Master).  Este dispositivo suporta taxas de transferência de 9,6 kbit/s a 12 Mbit/s, permitindo a conexão de até 32 escravos DP e oferecendo capacidades de comunicação S7 e PG/OP

Referência Siemens 6GK7243-5DX30-0XE0. CM1243-5 para S7-1200, função mestre PROFIBUS DP, comunicação S7 e PG/OP. Uma porta fêmea Sub-D de nove pinos RS485, 9,6kbit/s a 12Mbit/s. Alimentação externa 24VCC ±20%, borne de três polos. Não atribuir função DP Device do CM1542-5 a esta referência. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6GK72435DX300XE0).

Evidência: Ficha oficial Siemens 6GK7243-5DX30-0XE0; páginas 1. SHA-256: b25f4eaeb9be8e18b6b429bf3536bef56c3fcd867b87b92184df55d55637ba20. Arquivo: backups/fontes-lote-008/2449.pdf.

### ID 2463 — 6AV2124-0JC01-0AX0

Antes: Este dispositivo é um tipo de homem-máquina (IHM) que permite o controle e a supervisão dos processos industriais com simplicidade. Comandado por touchscreen, com um display LCD de 9 polegadas, é possível acessar informações e sinais de processo em tempo real, além de inserir comandos pelo próprio display. Isso aumenta a agilidade e a eficiência dos processos produtivos da sua empresa. Com o conforto e a tecnologia da IHM TP900 PN DP COMFORT temos a possibilidade de monitorar diferentes tipos de variáveis, resultando em melhoria de processos e aumento da produtividade.

Depois: Descrição anterior preservada como histórico (não validada integralmente):
Este dispositivo é um tipo de homem-máquina (IHM) que permite o controle e a supervisão dos processos industriais com simplicidade. Comandado por touchscreen, com um display LCD de 9 polegadas, é possível acessar informações e sinais de processo em tempo real, além de inserir comandos pelo próprio display. Isso aumenta a agilidade e a eficiência dos processos produtivos da sua empresa. Com o conforto e a tecnologia da IHM TP900 PN DP COMFORT temos a possibilidade de monitorar diferentes tipos de variáveis, resultando em melhoria de processos e aumento da produtividade.

Referência Siemens 6AV2124-0JC01-0AX0. SIMATIC HMI TP900 Comfort, TFT widescreen 9pol, 800×480 pixels, toque resistivo e 16.777.216 cores. Alimentação 24VCC (19,2-28,8VCC). Uma interface Industrial Ethernet/PROFINET com switch de duas portas e interface MPI/PROFIBUS DP. Memória para configuração/dados de usuário 12MB, Windows CE6.0, configurável a partir de WinCC Comfort V11. Não é painel Unified nem Comfort de outra diagonal. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6AV21240JC010AX0).

Evidência: Ficha oficial Siemens 6AV2124-0JC01-0AX0; páginas 1, 2. SHA-256: 10f93a846c4d9bc59aeadb8b548f9541ce05ed2a471e7f4ba67905b9effbf815. Arquivo: backups/fontes-lote-008/2463.pdf.

### ID 2737 — 6ES7223-5BL50-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7223-5BL50-0XB0. SM1223 G2: dezesseis entradas 24VCC sink/source e dezesseis saídas transistor 24VCC/0,5A. Alimentação 24VCC, faixa 20,4-28,8VCC. Não presumir compatibilidade mecânica/elétrica entre SM1223 de gerações diferentes. Corrente por canal sujeita aos limites de carga e agrupamento da ficha. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72235BL500XB0).

Evidência: Ficha oficial Siemens 6ES7223-5BL50-0XB0; páginas 1. SHA-256: ff8ce4a823840a7b7e530cd5ddf219374270ae9058076f187b5bd542c4b863c4. Arquivo: backups/fontes-lote-008/2737.pdf.

### ID 2930 — 6ES7221-1BH50-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7221-1BH50-0XB0. SM1221 G2, dezesseis entradas digitais 24VCC sink/source, organizadas em quatro grupos. Alimentação pelo barramento traseiro 5VCC, consumo máximo 90mA; 24VCC refere-se ao sinal das entradas. Não confundir com versão anterior 1BH32. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72211BH500XB0).

Evidência: Ficha oficial Siemens 6ES7221-1BH50-0XB0; páginas 1. SHA-256: 5a61ec7173c05edbc44fac221f0b7cdfe04f9832867c5067c58e96f86d78c45c. Arquivo: backups/fontes-lote-008/2930.pdf.

### ID 2931 — 6ES7223-5PH50-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7223-5PH50-0XB0. SM1223 G2: oito entradas digitais 24VCC sink/source e oito saídas a relé 2A, não transistor. Alimentação nominal do módulo 24VCC (20,4-28,8VCC); essa alimentação não limita por si só a tensão comutável pelos contatos. Dimensionar saídas conforme tipo de carga e tabela específica de comutação. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72235PH500XB0).

Evidência: Ficha oficial Siemens 6ES7223-5PH50-0XB0; páginas 1. SHA-256: 027ae8d8213a1e7499332dd4c4a5581f33636a46ccb845a8ca186c16a6786ddc. Arquivo: backups/fontes-lote-008/2931.pdf.

### ID 3129 — 6ES7231-4HF32-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7231-4HF32-0XB0. SM1231 geração anterior à G2, oito entradas diferenciais de tensão ou corrente, alimentação 24VCC. Faixas ±10V, ±5V, ±2,5V, 0-20mA ou 4-20mA. Resolução 12bit mais sinal, ou 13bit ADC. Não mede diretamente termopar ou RTD. Não transportar resolução ou compatibilidade entre as versões 4HF32 e 4HF50. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72314HF320XB0).

Evidência: Ficha oficial Siemens 6ES7231-4HF32-0XB0; páginas 1. SHA-256: 0710115759fc27866d0d08d7570c39cb03f0bca781fda3aaefecd7fb9a6ea028. Arquivo: backups/fontes-lote-008/3129.pdf.

### ID 3208 — 6ES7212-1AG50-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7212-1AG50-0XB0. CPU compacta de segunda geração G2. Alimentação nominal 24VCC, faixa 20,4-28,8VCC; 8 entradas digitais 24VCC e 6 saídas digitais 24VCC, 0,5A por saída para carga resistiva. Sem entradas ou saídas analógicas integradas. Memórias separadas: programa 150KB, dados 500KB e retenção 20KB; não somar nem confundir com memória de carga. Uma interface PROFINET, duas portas RJ45 e switch integrado, até 100Mbit/s. A ficha atual informa firmware V4.1 e STEP 7 V21 ou superior; isso não comprova firmware instalado nem autoriza atualização. Não copiar E/S analógicas ou compatibilidades da geração anterior. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72121AG500XB0).

Evidência: Ficha oficial Siemens 6ES7212-1AG50-0XB0; páginas 1, 3, 4. SHA-256: ef360859301af0800fd5c2217c986f06e3f34686e57bccf7dc930d39e633a5cf. Arquivo: backups/fontes-lote-008/3208.pdf.

### ID 3209 — 6ES7231-4HF50-0XB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7231-4HF50-0XB0. SM1231 G2, oito entradas diferenciais de tensão ou corrente, alimentação 24VCC. Faixas ±10V, ±5V, ±2,5V, 0-20mA ou 4-20mA. Resolução 14bit ADC. Não mede diretamente termopar ou RTD. Não transportar resolução ou compatibilidade entre as versões 4HF32 e 4HF50. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES72314HF500XB0).

Evidência: Ficha oficial Siemens 6ES7231-4HF50-0XB0; páginas 1. SHA-256: 5c620109ad82030f3e4ddeff9be327434f12c3bf865e4504adfe46a3baf884e6. Arquivo: backups/fontes-lote-008/3209.pdf.

### ID 3432 — 6ES7193-6AG20-0AA0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7193-6AG20-0AA0. Conversor de mídia em formato SIMATIC BusAdapter BA LC/RJ45: uma interface PROFINET e duas portas, uma LC óptica 100BASE-FX e uma RJ45 cobre. Fibra multimodo 50/125µm ou 62,5/125µm até 3km nas condições da ficha; cobre até 100m. Não é duas portas RJ45 nem módulo SFP genérico. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71936AG200AA0).

Evidência: Ficha oficial Siemens 6ES7193-6AG20-0AA0; páginas 1. SHA-256: 2117d71b10772720a62910d7e839d7b41f98e02085bb7a8dd58f7d9b98166743. Arquivo: backups/fontes-lote-008/3432.pdf.

### ID 3433 — 6ES7158-0AD01-0XA0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7158-0AD01-0XA0. Acoplador DP/DP SIMATIC para interligação de duas redes PROFIBUS DP, alimentação redundante nominal 24VCC (20,4-28,8VCC). Não é PN/PN nem módulo CPU. Indicação de descontinuação planejada na ficha não autoriza inativar cadastro ou adotar outra referência. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71580AD010XA0).

Evidência: Ficha oficial Siemens 6ES7158-0AD01-0XA0; páginas 1. SHA-256: 2246c2f05979957782c34d635d39f2e4a77c4e06c892c2ecce1217da135a5d53. Arquivo: backups/fontes-lote-008/3433.pdf.

### ID 3434 — 6ES7193-6BP20-0DA0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7193-6BP20-0DA0. BaseUnit tipo A0, modelo BU15-P16+A10+2D; terminais push-in, dez terminais auxiliares. Inicia novo grupo de potencial; não faz ponte de alimentação com a base à esquerda. Dimensões largura×altura 15×141mm. Tensão nominal 24VCC; barramentos P1/P2 máximo 10A e terminais de processo máximo 2A. Não confundir base de conexão com módulo eletrônico de E/S. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71936BP200DA0).

Evidência: Ficha oficial Siemens 6ES7193-6BP20-0DA0; páginas 1. SHA-256: 97594af5db61a3e92c0b1f0dfa2bdc5243c29d28c80a0375e9d02a29b829ecd1. Arquivo: backups/fontes-lote-008/3434.pdf.

### ID 3435 — 6ES7193-6BP20-0BA0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7193-6BP20-0BA0. BaseUnit tipo A0, modelo BU15-P16+A10+2B; terminais push-in, dez terminais auxiliares. Continua o grupo de potencial por ponte à esquerda; não inicia grupo novo. Dimensões largura×altura 15×141mm. Tensão nominal 24VCC; barramentos P1/P2 máximo 10A e terminais de processo máximo 2A. Não confundir base de conexão com módulo eletrônico de E/S. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71936BP200BA0).

Evidência: Ficha oficial Siemens 6ES7193-6BP20-0BA0; páginas 1. SHA-256: 175f50ef10745e7a17cdc34570ea4f1b6aa36dd21edfb9883ad7f27b4c7a3163. Arquivo: backups/fontes-lote-008/3435.pdf.

### ID 3436 — 6ES7193-6AR00-0AA0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7193-6AR00-0AA0. BusAdapter BA2XRJ45, uma interface PROFINET com switch de duas portas RJ45. Comprimento máximo de cabo de cobre 100m conforme ficha. Conferir compatibilidade da CPU/interface remota; não é módulo de E/S nem switch autônomo alimentado externamente. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71936AR000AA0).

Evidência: Ficha oficial Siemens 6ES7193-6AR00-0AA0; páginas 1. SHA-256: 1b5f8d0db50c7db20e9835367ac71c0d6a37c915b46632b5df1be62bd84c442a. Arquivo: backups/fontes-lote-008/3436.pdf.

### ID 3437 — 6ES7136-6DB00-0CA0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7136-6DB00-0CA0. Módulo de segurança F-DQ, 4DO em 24VCC, variante 2A PM HF; largura 15mm. Utiliza BaseUnit A0. A quantidade é de canais físicos; configuração redundante pode consumir mais de um canal por função. O fabricante informa possibilidade de até PL e/SIL3 nas condições aplicáveis; o cadastro não certifica a função ou circuito completo. Preservar distinção PP, PM e PPM, sem substituir uma topologia por outra. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71366DB000CA0).

Evidência: Ficha oficial Siemens 6ES7136-6DB00-0CA0; páginas 1. SHA-256: 35755bcef534dc6bf67f1e152b75437618ab71ec1a54c32dbf18c88a625398f5. Arquivo: backups/fontes-lote-008/3437.pdf.

### ID 3438 — 6ES7155-6AU01-0CN0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7155-6AU01-0CN0. IM155-6PN/2 High Feature, uma posição de BusAdapter para duas portas PROFINET; até 64 módulos ET200SP e 16 ET200AL. Alimentação 24VCC (19,2-28,8VCC). Redundância S2, multi-hot-swap e modo isócrono de 0,25ms conforme configuração. Módulo servidor incluído; não presumir BusAdapter incluído. Não confundir com ST de 32 módulos. Ficha atual V4.2; conferir versão física antes de assegurar funções de software. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71556AU010CN0).

Evidência: Ficha oficial Siemens 6ES7155-6AU01-0CN0; páginas 1. SHA-256: 4c250b18dc11bf73f3f59f4ca5ef86df0fe3d4502887077dfacb978dac28ef44. Arquivo: backups/fontes-lote-008/3438.pdf.

### ID 3439 — 6ES7158-3AD10-0XA0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7158-3AD10-0XA0. PN/PN Coupler para troca determinística de dados entre sub-redes PROFINET, até quatro PN-Controllers por sub-rede conforme configuração. Comunicação de dados PROFIsafe, E/S e registros; alimentação redundante 24VCC (19,2-28,8VCC). Conexões via SIMATIC BusAdapter, fornecido sem BusAdapter. Número de controladores não é número de portas. Ficha atual V6.0 e STEP 7 V20 ou superior; conferir firmware físico. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71583AD100XA0).

Evidência: Ficha oficial Siemens 6ES7158-3AD10-0XA0; páginas 1. SHA-256: 81edb5e7a7dbf70ac4a2a470f1d36d754ca46bbb8a958f09dc1a0ea6811be980. Arquivo: backups/fontes-lote-008/3439.pdf.

### ID 3440 — 6ES7193-6PA00-0AA0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7193-6PA00-0AA0. Server Module de reposição para ET200SP, dimensões largura×altura×profundidade 7×117×36mm, corrente máxima 30mA e montagem em trilho de altura 7,5mm ou 15mm. Não chamar apenas de base final: a ficha identifica módulo servidor. Não é CPU ou cartão de E/S. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES71936PA000AA0).

Evidência: Ficha oficial Siemens 6ES7193-6PA00-0AA0; páginas 1. SHA-256: d815b1ff715d2591ea770e61dceb2a3be22bbd25499090e4e53d34f48f0ce15d. Arquivo: backups/fontes-lote-008/3440.pdf.

### ID 3733 — 6ES7510-1SJ01-0AB0

Antes: (sem descrição complementar)

Depois: Referência Siemens 6ES7510-1SJ01-0AB0. CPU de segurança para SIMATIC ET200SP, alimentação 24VCC (19,2-28,8VCC). Memória de programa 150KB e dados 750KB. Uma interface PROFINET IRT com três portas: uma integrada e duas via BusAdapter; não são três interfaces independentes. Requer SIMATIC Memory Card e BusAdapter para as portas 1 e 2; não presumir fornecimento desses acessórios. A indicação de peça de reposição na ficha não autoriza inativação ou troca de referência. Grupo atual 55 preservado; avaliar reclassificação separadamente, pois a CPU é ET200SP, não S7-1200. Especificação da referência consultada; conferir versão física e configuração no projeto. Não inferir acessórios incluídos apenas pela imagem ilustrativa.

Fonte: [documento técnico da referência](https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=6ES75101SJ010AB0).

Evidência: Ficha oficial Siemens 6ES7510-1SJ01-0AB0; páginas 1, 4. SHA-256: d3878a869dd09bda78dc44c348ec910494cf1f26c27fee3c959c821d6c6f997a. Arquivo: backups/fontes-lote-008/3733.pdf.

## Controle

Assinatura SHA-256 do manifesto: 86c374ac97fe7099f31182b085b7d533cb89015861bf670368d7ec14524feb9b.

Manifesto: lote-008-cinquenta-itens.json.

Eventos de aplicação confirmados: 50.
