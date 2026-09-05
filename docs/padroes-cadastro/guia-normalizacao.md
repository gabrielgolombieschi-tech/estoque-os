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

O cadastro atual ainda não possui campo próprio de modelo. Não será criado nem presumido nesta etapa. Série/modelo pode permanecer no nome quando for uma compatibilidade técnica indispensável e houver aprovação humana registrada. Também deve permanecer a família e a referência alfanumérica oficial quando o código de origem for exclusivamente numérico, pois ela é necessária para identificar o produto sem repetir o número de origem.

## Princípios gerais

1. Interpretar o material; não copiar automaticamente palavras, abreviações ou a ordem da nota fiscal.
2. Não repetir fabricante, marca, código interno, código do fornecedor ou código de barras no nome. Exceção: quando o código de origem for exclusivamente numérico, incluir a família e a referência alfanumérica oficial do fabricante, sem repetir o número de origem.
3. Não inventar especificações, aplicação, material, grau de proteção, medidas ou compatibilidades.
4. Usar o mesmo nome técnico para o mesmo tipo de material, preservando somente os atributos que realmente o diferenciam.
5. Não unir itens tecnicamente diferentes apenas por terem dimensão, acabamento ou aplicação semelhantes.
6. Manter o valor numérico junto à unidade, sem espaço: `100A`, `500VCA`, `24VCC`, `400mm` e `6kA`.
7. Não há padrão global de ordem de dimensões aprovado no ERP. Enquanto não houver aprovação, dimensões devem ser mantidas como pendência e não inferidas.
8. Não incluir no nome número de pedido de compra, NF-e, OS, data da compra ou observação comercial. Esses dados pertencem aos documentos transacionais do ERP.

### Regra aprovada: unidades compactas

- O padrão sem espaço vale para valor simples, faixa e razão numérica: `115A`, `110-127VCA/CC` e `50/60Hz`.
- A regra se aplica a todas as famílias e a todas as unidades técnicas confirmadas, incluindo corrente, tensão, frequência, potência, dimensão, massa, tempo e pressão.
- A sugestão do agente e a confirmação do cadastro passam pela mesma normalização determinística no servidor.

### Regra aprovada: dados transacionais fora do nome

- Remover do cadastro reutilizável sufixos como `- Pedido 2025/114583` e `- PEDIDO 2026/81006 -`.
- Manter o número do pedido, a NF-e, a OS, a data e as observações comerciais nos documentos e relacionamentos próprios.
- Preservar sem alteração a descrição original da NF-e como evidência fiscal e de rastreabilidade.
- A remoção determinística limita-se a sufixos de pedido com formato reconhecido, para não apagar termos técnicos legítimos.

### Regra aprovada: cabos elétricos, de controle e sinal

- Esta regra cobre somente cabos fornecidos sem conector, plugue, terminal, chicote ou adaptador nas pontas. Cabos montados e cordões com terminação são outra classe de produto e não entram neste lote.
- Distinguir `UNIPOLAR` (uma via) de `MULTIPOLAR` (duas ou mais vias) quando a formação estiver confirmada. Cabos de potência ficam em `CABOS ELÉTRICOS`; cabos de controle e sinal ficam em `CABOS PARA SINAL E COMANDO`.
- A descrição deve informar, quando confirmados documentalmente: família ou tipo, formação e seção nominal, classe de tensão, material da isolação dos condutores, material da capa externa e presença ou ausência de blindagem.
- Isolação e capa são atributos diferentes e não podem ser resumidos como um único “material do cabo”. Exemplos: `ISOLAÇÃO PVC CAPA PUR` e `ISOLAÇÃO HEPR CAPA PVC`.
- Em `CABO PP`, PP identifica a família construtiva e não significa isolação de polipropileno. Na construção convencional confirmada, registrar `ISOLAÇÃO PVC CAPA PVC`.
- Preservar a notação técnica `G` ou `x`: `G` indica condutor de proteção verde/amarelo; `x` indica ausência desse condutor.
- Se faltar qualquer atributo obrigatório, o agente deve registrá-lo em `dados_pendentes`, reduzir a confiança e não inventar o valor.
- Exemplo aprovado: `CABO DE CONTROLE FLEXÍVEL PUR-JZ 12G0,5MM² 300/500V ISOLAÇÃO PVC CAPA PUR SEM BLINDAGEM`.
- Outros exemplos aprovados: `CABO ELÉTRICO FLEXÍVEL UNIPOLAR FLEXSIL 1X2,5MM² 450/750V ISOLAÇÃO PVC SEM CAPA SEM BLINDAGEM VERDE/AMARELO` e `CABO ELÉTRICO FLEXÍVEL MULTIPOLAR PP 4X2,5MM² 300/500V ISOLAÇÃO PVC CAPA PVC SEM BLINDAGEM PRETO`.

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
- Registrar somente atributos confirmados. Exemplo: `CONTATOR AC-3 25A 1NA+1NF 220V 50/60Hz CONEXÃO POR PARAFUSO`.
- Usar `CONTATOR AUXILIAR` para itens de comando e nomes específicos para acessórios, como tampa, bloco de terminais e supressor de surto.
- Blocos auxiliares frontais para contatores ficam em `ACESSÓRIOS PARA CONTATORES` e usam o formato `BLOCO DE CONTATO AUXILIAR FRONTAL {contatos} {tensão} {tipo_conexão} PARA CONTATOR`.
- Em qualquer família, manter valor e unidade juntos: `25A`, `220V`, `50/60Hz` e `6kA`.

## Regra aprovada: disjuntores motor

- Hierarquia: `PROTECAO_E_SECCIONAMENTO` > `DISJUNTORES_MOTOR` e `ACESSORIOS_DISJUNTORES_MOTOR`.
- Conexões entre disjuntor-motor e contator ficam em `MANOBRA_E_PARTIDA_MOTORES` > `CONEXOES_PARTIDA_MOTORES`.
- Nome: `DISJUNTOR MOTOR {faixa_ajuste_corrente}` ou `DISJUNTOR MOTOR {corrente_nominal}`.
- Exemplo: `DISJUNTOR MOTOR 4,5-6,3A`.
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
- Exemplo: `RELÉ DE SOBRECARGA 9-12,5A TAMANHO S0`.
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
- Switches Ethernet industriais devem indicar obrigatoriamente a quantidade de portas. Quando confirmados, indicar também gerenciamento, camada, meio, conector e velocidade por tipo de porta. Sem quantidade confirmada, registrar a pendência e não finalizar como `switch Ethernet industrial` genérico.
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

## Integração aprovada: novo cadastro assistido por IA

Na tela **Itens > Novo**, o cadastro assistido começa com somente três informações: fornecedor já cadastrado e ativo, código de origem e quantidade de referência para cotação. Essa quantidade não cria saldo nem movimenta estoque.

O agente consulta o catálogo estruturado, os grupos disponíveis e itens internos semelhantes. Ele propõe nome padronizado, fabricante em campo próprio, grupo, unidade, preço e uma referência fiscal interna. A pessoa usuária revisa todos esses dados antes de confirmar; o agente não grava nada durante a sugestão.

- O código pode ser digitado com espaços ou hífens, mas o ERP consulta, compara e grava a forma em maiúsculas sem esses separadores visuais. Outros caracteres técnicos, como `/`, são preservados.
- A finalidade inicial é sempre `matéria-prima`; a pessoa usuária pode revisá-la antes da confirmação quando houver exceção justificada.
- O preço pesquisado deve priorizar Mercado Livre, eBay e lojas técnicas com página concreta. Página oficial sem preço confirma especificação, mas não encerra a pesquisa de cotação.
- Para eBay em moeda estrangeira, o sistema registra a moeda de origem, taxa USD/BRL (ou equivalente) verificável, URL e data da cotação; calcula primeiro o valor em reais e aplica claramente o fator `1,80` de importação. Sem taxa verificável, o preço permanece pendente; o sistema não inventa câmbio.
- NCM, IPI, CST e alíquotas são sugestões baseadas em item interno semelhante, identificando o item de referência. Exigem validação fiscal humana antes da gravação.
- A origem fiscal inicial é sempre `0 — Nacional`; os demais campos fiscais continuam sujeitos à revisão humana.
- Um grupo inexistente pode ser sugerido, mas só é criado com confirmação explícita. Itens com o mesmo fornecedor e código ativo não podem ser duplicados; um correspondente inativo exige revisão ou reativação explícita.
- A confirmação gera uma trilha de auditoria com a proposta revisada, fontes de preço, regra de cálculo e referência interna utilizada.

## Regra aplicada: componentes WAGO, Phoenix Contact e SICK

O lote foi classificado por função técnica, mesmo quando o fornecedor é a única informação de origem preenchida no cadastro. Fornecedor e fabricante continuam em seus campos; não entram no nome padronizado.

Para a linha Phoenix Contact, cujo código de origem é exclusivamente numérico, a família e a referência alfanumérica oficial permanecem no nome. Exemplos: `PT 2,5`, `TRIO-PS-2G/1AC/24DC/10`, `FL SWITCH 1005N` e `SAC-4P-5,0-PVC/M12FR`. O número de origem, como `3209510` ou `1085039`, continua somente em `itens.codigo_interno`.

- Componentes de montagem ficam em `Montagem de painéis`: canaletas, trilhos DIN, prensa-cabos, identificação e ferramentas.
- Bornes, pentes, tampas, blocos de distribuição, conectores multipolares e tomadas DIN ficam em `Conexões elétricas`. Um pente de borne não deve ser confundido com um pente de relé de interface.
- Cabos e conectores M8/M12 ficam em `Sensores industriais` quando atendem sensores ou atuadores; cabos e conectores Ethernet/PROFINET ficam em `Comunicação industrial`.
- Sensores são separados por princípio: indutivo, fotoelétrico, garfo, nível, ultrassônico, fluxo, temperatura e pressão. Declarar alcance, saída, dimensão, pinos, cabo e material somente quando confirmados.
- Cortinas de luz, controladores, chaves, atuadores e dispositivos de habilitação pertencem a `Segurança de máquinas`. A família técnica aparece quando determina compatibilidade ou na regra de código de origem numérico (D-028), acompanhada da referência alfanumérica confirmada.
- Os itens SICK com códigos internos `2066614-COPIA` e `2066614-COPIA-COPIA` receberam nome e grupo técnicos, mas seus códigos não foram alterados porque divergem do item identificado na própria descrição.
- O item WAGO `60510362` foi mantido como `BORNE DE PASSAGEM SEM PARAFUSO`, sem supor bitola, quantidade de condutores ou tensão.

Exemplos registrados no catálogo: `CONTROLADOR DE SEGURANÇA FLEXI COMPACT 20DI 4DO`, `CORTINA DE LUZ DE SEGURANÇA RECEPTORA 750MM RESOLUÇÃO 30MM ALCANCE 30M` e `SWITCH ETHERNET INDUSTRIAL GERENCIÁVEL COM NAT 8 PORTAS RJ45 10/100MBPS`.

## D-033 — Revisão técnica SICK e prevenção de descrições genéricas

A revisão de 05/09/2026 inventariou 79 cadastros SICK (72 ativos). O primeiro lote corrige os 21 mais genéricos, sem declarar os demais tecnicamente completos. O manifesto `revisao-sick-2026-09-05.json` registra os nomes anteriores, propostas, grupos, fontes oficiais e lacunas. O script `scripts/revisar-sick.mjs` é somente leitura por padrão; `--apply` grava exclusivamente nome/grupo com backup e proteção contra mudanças concorrentes, e `--verify` confere o resultado.

- Código exclusivamente numérico exige família/referência alfanumérica oficial na descrição, sem repetir o número nem a marca.
- Sensores fotoelétricos: princípio, faixa de trabalho, saída, alimentação e conexão. Confirmar se uma barreira é emissor, receptor ou conjunto. Não trocar alcance de trabalho pelo máximo limite.
- Cortinas: transmissor/receptor, altura protegida, resolução, alcance e tipo. As C4-RD deste lote têm alcance de 4,5m; não herdar os 15m de outra variante deTec4 Core.
- Segurança: `safety switch` não significa switch Ethernet. STR1/TR4 RFID são chaves sem contato, não travas mecânicas. Distinguir OSSD de contatos mecânicos e distância assegurada Sao de alcance genérico. Separar sensor radar e controlador/protocolo.
- Cabos montados: função, comprimento, cada terminação, seções, isolação, capa, blindagem e tensão do conjunto devem ser confirmados. O cabo isolado pode suportar tensão superior à dos conectores. A regra de estoque obrigatório em metros dos cabos sem terminação não se aplica automaticamente.
- Acessórios: corda de tração pertence à chave de segurança; acoplamento e cabo de programação pertencem a encoders. Informar os dois diâmetros do acoplamento. Não presumir resistência de terminador a partir do protocolo.

As regras estão no catálogo e em um módulo compartilhado pelos dois agentes (novo cadastro e importação de NF-e). A checagem de completude acrescenta pendências e reduz a confiança para baixa; ela não certifica a veracidade dos dados nem substitui conferência da ficha exata. A confirmação humana existente permanece.

Pendências preservadas: códigos divergentes `2066614-COPIA` e `2066614-COPIA-COPIA`; materiais ainda não confirmados em alguns cabos montados; resistência do terminador; composição comercial da barreira VSE180. O radar fica em `Segurança de máquinas`, sem criar subgrupo sem aprovação. Nenhuma alteração de unidade, multiplicador, saldo, preço, código ou dados fiscais faz parte deste lote.
