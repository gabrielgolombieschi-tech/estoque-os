# Guia de normalização de cadastros

## Objetivo

Padronizar o campo `itens.nome` para que o catálogo do ERP descreva o material tecnicamente, com consistência e sem copiar automaticamente a descrição recebida na nota fiscal.

O texto original da nota continua como evidência fiscal e de rastreabilidade. A normalização se aplica ao cadastro reutilizável do ERP.

## Escopo inicial

Família: **painéis elétricos e componentes**, começando por acessórios de disjuntores caixa moldada e disjuntores mini.

## Campos e responsabilidades

| Informação | Campo do ERP | Regra |
| --- | --- | --- |
| Nome padronizado | `itens.nome` | Nome técnico, objetivo e pesquisável. |
| Código da nota / fornecedor | `itens.codigo_interno` | Preservar; não gerar nem alterar durante a normalização. |
| Código de barras | `itens.codigo_barras` | Preservar quando disponível. |
| Fabricante ou marca | `itens.fabricante` | Registrar no campo próprio, sem repetição no nome. |
| Fornecedor de origem | `itens.fornecedor_id` | Usar para selecionar e rastrear lotes de revisão; não repetir no nome. |
| Grupo controlado | `itens.grupo_id` | Classificar pelo cadastro de grupos de itens. |
| Texto complementar | `itens.descricao` | Usar apenas para informação técnica adicional confirmada. |

O cadastro atual ainda não possui campo próprio de modelo. Não será criado nem presumido nesta etapa. Série/modelo só pode permanecer no nome quando for uma compatibilidade técnica indispensável para distinguir o item e houver aprovação humana registrada.

## Princípios gerais

1. Interpretar o material; não copiar automaticamente palavras, abreviações ou a ordem da nota fiscal.
2. Não repetir fabricante, marca, código interno, código do fornecedor ou código de barras no nome.
3. Não inventar especificações, aplicação, material, grau de proteção, medidas ou compatibilidades.
4. Usar o mesmo nome técnico para o mesmo tipo de material, preservando somente os atributos que realmente o diferenciam.
5. Não unir itens tecnicamente diferentes apenas por terem dimensão, acabamento ou aplicação semelhantes.
6. Manter o valor numérico junto à unidade, sem espaço: `100A`, `500VCA`, `24VCC`, `400mm` e `6kA`.
7. Não há padrão global de ordem de dimensões aprovado no ERP. Enquanto não houver aprovação, dimensões devem ser mantidas como pendência e não inferidas.

## Termos que exigem análise

`caixa`, `armário`, `gabinete`, `quadro` e `painel` não são sinônimos universais. A equivalência depende do tipo construtivo, aplicação, acessórios e especificação disponível.

Para acessórios, o nome deve apontar o equipamento principal quando isso for necessário para evitar ambiguidade. Exemplo: `ACIONAMENTO ROTATIVO LATERAL PARA DISJUNTORES CAIXA MOLDADA`.

## Registro de dúvidas

Quando faltar informação para confirmar o material ou uma característica diferenciadora:

- manter o cadastro sem inferência;
- registrar o termo e o motivo em `termos_ambiguos_pendentes` no catálogo YAML;
- apresentar a dúvida junto da proposta;
- aguardar validação humana antes de transformar a interpretação em regra.

## Processo de aprovação humana

1. Apresentar cadastro atual, interpretação técnica, proposta de nome, grupo e justificativa.
2. Registrar somente decisões aprovadas no histórico do YAML, incluindo a origem e a data.
3. Aplicar a alteração no item individual somente após a aprovação correspondente.
4. A seleção de lotes pode partir do fornecedor da nota; isso não autoriza inferir ou substituir o fabricante do item.
4. Em novos fluxos de importação, a IA pode sugerir uma regra aprovada, mas deve sinalizar incerteza e nunca criar regra definitiva sozinha.

## Fonte estruturada de verdade

O arquivo `catalogo-paineis-eletricos.yaml` é a fonte estruturada de verdade para consumo futuro pela IA. Este guia explica o processo para pessoas e desenvolvedores.

## Regra aprovada: disjuntores mini

- Grupo controlado: `DISJUNTORES MINI`.
- Nome: `DISJUNTOR MINI {polos} CURVA {curva} {corrente_nominal} {capacidade_interrupcao}`.
- Exemplos: `DISJUNTOR MINI 2P CURVA C 25A 6kA` e `DISJUNTOR MINI 2P CURVA C 25A 4,5kA`.
- A marca permanece em `itens.fabricante` e o código da nota permanece em `itens.codigo_interno`.
- Quando a capacidade de interrupção não estiver confirmada, ela não é inventada nem incluída no nome. A pendência fica registrada no catálogo estruturado.

## Regra aprovada: contatores

- Hierarquia: `MANOBRA_E_PARTIDA_MOTORES` > `CONTATORES`, `CONTATORES_AUXILIARES` e `ACESSORIOS_PARA_CONTATORES`.
- Nome de contator: `CONTATOR {polos} {categoria_utilizacao} {corrente_nominal} {contatos_auxiliares} {tensao_comando} {frequencia} {tipo_conexao}`.
- Registrar somente atributos confirmados. Exemplo: `CONTATOR AC-3 25 A 1NA+1NF 220 V 50/60 Hz CONEXÃO POR PARAFUSO`.
- Usar `CONTATOR AUXILIAR` para itens de comando e nomes específicos para acessórios, como tampa, bloco de terminais e supressor de surto.
- Blocos auxiliares frontais para contatores ficam em `ACESSÓRIOS PARA CONTATORES` e usam o formato `BLOCO DE CONTATO AUXILIAR FRONTAL {contatos} {tensão} {tipo_conexão} PARA CONTATOR`.
- Em qualquer família, manter valor e unidade juntos: `25A`, `220V`, `50/60Hz` e `6kA`.

## Regra aprovada: disjuntores motor

- Hierarquia: `PROTECAO_E_SECCIONAMENTO` > `DISJUNTORES_MOTOR` e `ACESSORIOS_DISJUNTORES_MOTOR`.
- Conexões entre disjuntor-motor e contator ficam em `MANOBRA_E_PARTIDA_MOTORES` > `CONEXOES_PARTIDA_MOTORES`.
- Nome: `DISJUNTOR MOTOR {faixa_ajuste_corrente}` ou `DISJUNTOR MOTOR {corrente_nominal}`.
- Exemplo: `DISJUNTOR MOTOR 4,5-6,3 A`.
- A corrente ou faixa só pode ser usada quando aparecer claramente como especificação do item. Números da série, do modelo ou do código nunca são tratados como corrente.

## Regra aprovada: disjuntores caixa moldada

- Hierarquia: `DISJUNTORES_CAIXA_MOLDADA` e `ACESSORIOS`.
- Nome: `DISJUNTOR CAIXA MOLDADA {característica_confirmada} {polos} {corrente_nominal} {capacidade_interrupcao} {tensao}`.
- Nesta família, as medidas são compactas: `100A`, `16kA` e `380V`.
- Manoplas, acionamentos, acopladores, conexões, adaptadores e disparadores ficam em `ACESSÓRIOS` e devem indicar que atendem a disjuntor caixa moldada.
- Modelo e capacidade só podem permanecer no nome de uma manopla quando forem indispensáveis para sua compatibilidade técnica e estiverem confirmados. Exemplos aprovados: `3VT2 250A` e `AGW250 250A`.

## Regra aprovada: segurança de máquinas

- Hierarquia: `SEGURANCA_MAQUINAS` > `CHAVES_SEGURANCA`, `ATUADORES_CHAVES_SEGURANCA` e `ACESSORIOS_CHAVES_SEGURANCA`.
- Uma chave completa fica em `CHAVES DE SEGURANÇA`, ainda que seja fornecida com atuador. Atuador separado fica em `ATUADORES PARA CHAVES DE SEGURANÇA`.
- Parafusos tensionadores, fixadores e outros complementos ficam em `ACESSÓRIOS PARA CHAVES DE SEGURANÇA`.
- Nomear pela função e pelos atributos confirmados, como RFID, sem contato, intertravamento, contatos, conector, tensão, cabo e dimensões. Não repetir marca, modelo ou código.

## Regra aprovada: relés e módulos de segurança

- Dentro de `SEGURANÇA DE MÁQUINAS`, usar `RELÉS DE SEGURANÇA` para relés, unidades básicas e controladores programáveis de segurança.
- Expansões de entrada e saída ficam em `MÓDULOS DE EXPANSÃO PARA RELÉS DE SEGURANÇA`; não devem ser cadastradas como relés autônomos.
- Módulos voltados especificamente a inversores ficam em `MÓDULOS DE SEGURANÇA PARA INVERSORES`.
- Expansões de sistemas modulares de segurança ficam em `MÓDULOS DE SEGURANÇA MODULARES`.
- Descrever somente a função e atributos confirmados: contatos ou E/S, alimentação, temporização, conexão e nível de segurança. O mesmo padrão vale para quaisquer marcas e fornecedores.

## Regra aprovada: relés de interface

- Hierarquia: `RELES_MONITORAMENTO` > `RELES_INTERFACE` e `ACESSORIOS_RELES_INTERFACE`.
- Acopladores de saída, optoacopladores e relés encaixáveis são `RELÉS DE INTERFACE`; pentes e complementos ficam em `ACESSÓRIOS PARA RELÉS DE INTERFACE`.
- Informar tecnologia, contatos, alimentação, saída, corrente e conexão somente quando confirmados.
- Sem especificação técnica confirmada, usar apenas `RELÉ DE INTERFACE`; nunca deduzir contatos, tensão ou tipo de terminal pelo código.

## Regra aprovada: relés de sobrecarga

- Hierarquia: `MANOBRA_E_PARTIDA_MOTORES` > `RELES_SOBRECARGA` e `ACESSORIOS_RELES_SOBRECARGA`.
- Nome: `RELÉ DE SOBRECARGA {faixa_ajuste_corrente} {tamanho_construtivo}`.
- Exemplo: `RELÉ DE SOBRECARGA 9-12,5 A TAMANHO S0`.
- Suporte, base e outros complementos não são relés: devem ser classificados como acessórios e indicar o equipamento atendido.

## Regra aprovada: tipo de conexão

- Incluir `CONEXÃO POR PARAFUSO` ou `CONEXÃO POR MOLA` quando a referência técnica confirmar o tipo de terminal.
- Para os disjuntores-motor Siemens 3RV2 revisados: referências terminadas em `...10` usam parafuso; as terminadas em `...20` usam mola.
- Para os relés Siemens 3RU revisados com referência terminada em `...B0`, usar conexão por parafuso.
- A referência/modelo só pode permanecer no nome por compatibilidade técnica indispensável e com aprovação humana. Exceção aprovada: `BLOCO DE CONTATO AUXILIAR FRONTAL 3RV1901-1E (1NA+1NF)`.

## Regra aprovada: aplicação entre fornecedores

- A classificação é funcional e independe de marca ou fornecedor: os mesmos grupos e formatos se aplicam a Siemens, WEG, Schneider e demais fornecedores quando o produto for tecnicamente equivalente.
- Para contatores, disjuntores motor e relés de sobrecarga, informar o tipo de conexão apenas quando confirmado pela referência técnica.
- Em acessórios, o nome deve distinguir a função e os atributos confirmados — por exemplo, comprimento de barramento, corrente, tensão e número de polos — sem repetir marca, série, modelo ou código.

## Regra aprovada: seccionamento, fusíveis, DR e soft-starters

- Chaves seccionadoras ficam em `PROTECAO_E_SECCIONAMENTO` > `CHAVES_SECCIONADORAS`. Informar `MONTAGEM FRONTAL`, `MONTAGEM EM PAINEL` ou `MONTAGEM POR TOPO` somente quando a montagem estiver confirmada.
- Fusíveis NH e suas bases ficam em grupos próprios. Declarar tamanho, corrente, tensão e classe do fusível quando confirmados: `FUSÍVEL NH gL/gG TAMANHO 00 125A 500VCA`.
- DR fica em `INTERRUPTORES DIFERENCIAIS RESIDUAIS`; informar polos, corrente, corrente diferencial residual e tipo quando confirmados: `INTERRUPTOR DIFERENCIAL RESIDUAL 3P+N 80A 30mA TIPO AC`.
- Soft-starters ficam em `ACIONAMENTOS DE MOTORES` > `SOFT-STARTERS`; módulos, conjuntos de proteção e demais complementos ficam em `ACESSÓRIOS PARA SOFT-STARTERS`. Em módulos de comunicação, indicar o protocolo e a função, como `MÓDULO DE COMUNICAÇÃO PROFINET COM SWITCH INTEGRADO PARA SOFT-STARTER`.
- Relés de monitoramento devem explicitar a condição elétrica monitorada, por exemplo sequência, falta ou assimetria de fase; evitar o nome genérico `RELÉ DE MONITORAMENTO`.
- Bases e conectores de relés de segurança ficam em `SEGURANÇA DE MÁQUINAS` > `ACESSÓRIOS PARA RELÉS DE SEGURANÇA`, com largura e função quando confirmadas.

## Regra aprovada: alimentação, inversores e automação programável

- Usar `ALIMENTAÇÃO E ENERGIA` para fontes e UPS CC. Fontes devem declarar saída, corrente ou potência e tipo de entrada quando confirmados, como `FONTE DE ALIMENTAÇÃO 24VCC 10A ENTRADA MONOFÁSICA`.
- Inversores, resistores de frenagem e acessórios ficam em `ACIONAMENTOS DE MOTORES`. Acessórios devem declarar a família do inversor quando isso for necessário para compatibilidade, como `PAINEL DE OPERAÇÃO BOP-2 PARA INVERSOR SINAMICS G120`.
- Para PLC e módulos, a família é atributo obrigatório quando disponível. Os itens Siemens deste lote usam `S7-1200` no nome.
- Módulos analógicos devem declarar sinal e tipo: tensão, corrente ou RTD. Exemplo: `MÓDULO DE ENTRADAS ANALÓGICAS PARA PLC S7-1200 8AI ±10V / ±5V / ±2,5V / 0-20mA / 4-20mA`.
- Não usar o grupo S7-1200 para PLC de outras famílias ou fabricantes. Eles serão separados por família em lote próprio após validação humana.

## Regra aprovada: estações remotas ET200SP, ET200MP e acessórios S7-1500

- Em módulos e acessórios de automação, a família deve aparecer no nome quando determina compatibilidade: `ET200SP`, `ET200MP`, `S7-1200` ou `S7-1500`.
- Interfaces de estação remota ET200SP são nomeadas como `CABEÇA DE REDE PROFINET PARA ESTAÇÃO ET200SP`, com capacidade de módulos de E/S e portas quando confirmadas.
- Acopladores devem declarar os protocolos interligados e sua função. Exemplo: `MÓDULO ACOPLADOR DP/DP PARA REDES PROFIBUS, LINHA SIMATIC DP, COM ALIMENTAÇÃO REDUNDANTE`.
- Adaptadores de barramento usam a denominação técnica `BUSADAPTER` e o tipo que identifica a conexão física: `BA 2xFC`, `BA LC/RJ45` ou `BA 2xRJ45`.
- As bases ET200SP exigem diferenciação por largura, quantidade de terminais, presença de terminais auxiliares e comportamento do grupo de carga quando confirmados. O módulo servidor é classificado como acessório e recebe o nome `BASE FINAL PARA PLC ET200SP`.
- A marca não é repetida no nome. A exceção aprovada é a linha técnica `SIMATIC DP`, pois ela identifica tecnicamente o acoplador DP/DP.

## Regra aprovada: conexões elétricas, transformadores e relés temporizadores

- Em `CONEXÕES ELÉTRICAS`, separar bornes de passagem, bornes de passagem plug-in, bornes de proteção, pentes e tampas finais. O tipo plug-in permanece na descrição quando confirmado.
- Usar sempre `PENTE DE LIGAÇÃO PARA BORNES`, nunca `PONTE`, e registrar polos, seção e número de andares somente quando confirmados.
- Transformadores de comando devem declarar potência, entrada, saída e grau de proteção quando confirmados. Se faltar tensão de entrada ou saída, não inventar o valor nem reescrever a descrição; apenas classificar o item e registrar a pendência.
- Chaves seccionadoras declaram polos, corrente e tipo de montagem. `COM MANOPLA VERDE` permanece quando essa característica diferencia o item.
- Relés temporizadores declaram alimentação, faixa de temporização e contatos quando confirmados. Relés de monitoramento de fase devem indicar a condição monitorada, como falta e sequência de fase.

## Regra aprovada: servoacionamentos, comunicação industrial e instrumentação

- Em servomotores e cabos, informar a família do servomotor e do drive apenas quando ela for indispensável e confirmada para a compatibilidade. Cabos de sinal e cabos de potência devem permanecer separados.
- Itens de segurança modular devem indicar a função exata: unidade central, relé ou partida direta de segurança. A família técnica, como `3RK3 Basic`, pode permanecer quando identifica compatibilidade do sistema.
- Switches Ethernet industriais devem indicar se são gerenciáveis, a camada, e a quantidade, meio e conector das portas quando confirmados. Não usar apenas `switch Ethernet industrial`.
- Módulos de comunicação de PLC devem declarar a família do PLC, o protocolo e o papel de rede — por exemplo, mestre PROFIBUS DP — quando confirmados.
- Módulos de pesagem precisam declarar a família de PLC ou a possibilidade de operação autônoma, canal, E/S e interfaces confirmados. Exemplo aprovado: `MÓDULO DE PESAGEM SIWAREX WP231 PARA PLC S7-1200 OU OPERAÇÃO AUTÔNOMA, 1 CANAL, 4DI/4DO, 1AO, RS485 E ETHERNET`.
- Transformadores de corrente ficam em `MEDIÇÃO E INSTRUMENTAÇÃO` e devem declarar relação, carga e classe de precisão confirmadas, como `TRANSFORMADOR DE CORRENTE 50/5A 1,2VA CLASSE 1`.

## Integração aprovada: cadastro assistido na importação de NF-e

- Itens sem cadastro não podem mais usar diretamente a descrição original da NF-e para criar produto.
- O `Agente de Normalização de Cadastro` recebe os dados fiscais do item, os grupos disponíveis na empresa e este catálogo. Ele devolve descrição padronizada, grupo sugerido, justificativa, pendências e confiança.
- O agente deve usar um grupo existente quando ele for funcionalmente adequado. Não pode encaixar um cabo em `Conectores para rede industrial` apenas pela proximidade do termo.
- Quando não houver grupo adequado, o agente propõe um novo grupo simples e reutilizável, com código, nome e grupo pai existentes. Exemplos: `Cabos para rede industrial` e `Módulos e acessórios para rede industrial` dentro de `Comunicação industrial`.
- A sugestão aparece na tabela da importação antes do cadastro. O usuário confere e confirma em `Cadastrar sugestão IA` ou `Criar grupo e cadastrar IA`; o agente não grava itens por conta própria.
- Quando não houver descrição segura nem grupo existente ou novo sugerido, o cadastro é bloqueado até revisão humana. Isso evita inventar especificações ou criar itens sem classificação.
- O modelo é configurado somente no servidor por `ASSISTENTE_IA_OPENAI_MODEL`. A chave da OpenAI nunca é enviada ao navegador.
