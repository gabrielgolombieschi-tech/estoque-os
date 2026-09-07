# Revisão de cadastros — Siemens, Phoenix, Schneider, WEG e Rittal

Data: 05/09/2026. Status atualizado após autorização humana: **16 correções aplicadas e verificadas no banco**, com três classificações em grupos existentes. As decisões foram incorporadas ao padrão D-035, versão 1.23.0, no código local; não houve publicação da aplicação remota. O diagnóstico original e as fontes ficam preservados abaixo.

## Resultado da aplicação autorizada

- Siemens: 5 itens; Phoenix: 3; Schneider: 3; WEG: 3; Rittal: 2.
- Nomes e descrições técnicas corrigidos; fontes e condições de operação registradas na descrição complementar.
- Grupo `RELES_SEGURANCA` no ID 2952; `CORTINAS_LUZ_SEGURANCA` nos IDs 1394 e 1395. Nenhum grupo criado ou aplicado por aproximação.
- O ID 3324 ficou fora das 17 propostas iniciais por falta de confirmação de tensão/interrupção. Os sete conflitos/pendências de identificação listados adiante também não foram alterados. Na câmera 3612, a identificação e a resolução foram corrigidas; a interface continua explicitamente pendente.
- Backup anterior às escritas: `backups/revisao-cinco-fabricantes/2026-09-05T12-44-41-914Z.json`; retornos registrados no arquivo de mesmo nome com sufixo `.resultado.jsonl`.
- Reconsulta confirmou os 16 resultados e zero alterações restantes no lote. A comparação pós-gravação confirmou preservação dos demais campos de cada registro, incluindo código, fornecedor, fabricante, unidade e preço; não foram emitidos comandos de movimentação de estoque.
- Manifesto executável: `revisao-cinco-fabricantes-2026-09-05.json`. Script: `scripts/aplicar-revisao-fabricantes.mjs`, somente leitura sem `--apply`.
- Validação: lint dos arquivos de código alterados, `tsc --noEmit --incremental false`, testes D-035, qualidade de descrição, normalização de unidades e pesquisa XML aprovados. Não houve teste visual da tela autenticada nem publicação remota. As novas regras exigem recarregamento/publicação nas instâncias em execução.

## Escopo e cobertura

Consultas somente leitura, restritas ao tenant `3ced7cfa-efbb-4f0f-addc-2028f60d1ca7` e empresa `f0e74f49-a127-46b4-901b-f7b37e43c690`. Seleção por fabricante informado ou fornecedor associado às cinco marcas. Este recorte não equivale a uma validação da identidade de cada fabricante.

Inventário: **940 registros únicos, 934 ativos e 161 ativos sem grupo**. Foi feita triagem cadastral do recorte e pesquisa técnica dos casos prioritários abaixo, não conferência documental individual dos 940 itens. Os demais não devem ser considerados aprovados por ausência nesta lista.

| Marca atribuída no cadastro | Registros | Ativos | Ativos sem grupo |
| --- | ---: | ---: | ---: |
| Siemens | 458 | 458 | 0 |
| Phoenix | 138 | 134 | 2 |
| Schneider | 59 | 59 | 24 |
| WEG | 237 | 235 | 87 |
| Rittal | 48 | 48 | 48 |

A atribuição acima prioriza o campo fabricante e, na ausência, o fornecedor. O ID 688 está atribuído a WEG, mas tem fornecedor Siemens e referência Siemens; sua identidade precisa ser regularizada. Por isso, os totais por marca não representam uma classificação técnica já corrigida.

Rastreabilidade: `scripts/auditar-cadastros-fabricantes.mjs`; inventário em `backups/auditoria-fabricantes/2026-09-05T11-51-03-324Z.json`; descrições de NF consultadas em `backups/auditoria-fabricantes/2026-09-05T11-51-03-324Z-origens.json`. Os arquivos são retratos de leitura, não backups de alterações executadas.

## 17 propostas fundamentadas para os nomes

Propostas do diagnóstico original, posteriormente aprovadas pelo usuário. Foram aplicadas 16, excluindo o ID 3324. O estado anterior foi conferido antes da escrita, os códigos de integração foram preservados e os detalhes/condições passaram a constar na descrição complementar.

### Siemens

| ID / código atual | Problema | Nome proposto e fonte |
| --- | --- | --- |
| 3659 / 6SL32010BE238AA0 | “RESISTOR DE FRENAGEM FIXO 18KW” confunde potência nominal e pico. | RESISTOR DE FRENAGEM 30Ω POTÊNCIA NOMINAL 925W PICO 18,5kW/12s CICLO 5%. [Siemens](https://mall.industry.siemens.com/mall/en/b1/Catalog/Product/6SL3201-0BE23-8AA0). |
| 2740 / 6SL32010BE143AA0 | “0,37-1,1kW” não identifica a potência nominal do resistor. | RESISTOR DE FRENAGEM 370Ω POTÊNCIA NOMINAL 75W PICO 1,5kW/12s CICLO 5%. [Siemens](https://mall.industry.siemens.com/mall/it/it/Catalog/Product/6SL3201-0BE14-3AA0). |
| 3099 / 6SL32010BE210AA0 | “1,5-3kW” não identifica a potência nominal do resistor. | RESISTOR DE FRENAGEM 140Ω POTÊNCIA NOMINAL 200W PICO 4kW/12s CICLO 5%. [Siemens](https://mall.industry.siemens.com/mall/en/cn/Catalog/Product/6SL3201-0BE21-0AA0). |
| 1719 / 6SL32010BE218AA0 | “4-7,5kW” não identifica a potência nominal do resistor. | RESISTOR DE FRENAGEM 75Ω POTÊNCIA NOMINAL 375W PICO 7,5kW/12s CICLO 5%. [Siemens](https://mall.industry.siemens.com/mall/en/se/Catalog/Product/6SL3201-0BE21-8AA0). |
| 3557 / 6GK59921AM008AA0 | SFP sem tipo de fibra, conector e alcance. | MÓDULO SFP SCALANCE X 1 PORTA 1000Mbit/s FIBRA MONOMODO LC ALCANCE ATÉ 10km. [Siemens](https://mall.industry.siemens.com/mall/KZ/EN/Catalog/Product/?mlfb=6GK5992-1AM00-8AA0). |

Nos resistores, registrar o regime de referência de 12s em período de 240s na descrição. Faixa de potência do acionamento compatível é informação diferente da potência dissipada pelo resistor.

### Phoenix Contact

| ID / código atual | Problema | Nome proposto e fonte |
| --- | --- | --- |
| 3754 / 2966650 | “24VCC 2 SAÍDAS” não corresponde à entrada nem à quantidade de saídas. | RELÉ DE ESTADO SÓLIDO PLC-OSC-120UC/24DC/2 ENTRADA 120VCA/110VCC 1NA SAÍDA 3-33VCC ATÉ 3A CONEXÃO POR PARAFUSO. [Phoenix](https://www.phoenixcontact.com/en-us/products/solid-state-relay-module-plc-osc-120uc-24dc-2-2966650). |
| 477 / 1424657 | Conector sem gênero, codificação e conexão dos condutores. | CONECTOR M12 MACHO RETO 4 POLOS CODIFICAÇÃO A SACC-M12MS-4PL M CONEXÃO PUSH-LOCK 250VCA/CC. [Phoenix](https://www.phoenixcontact.com/en-us/products/circular-connector-cable-side-sacc-m12ms-4pl-m-1424657). |
| 2935 / 25187 | Carcaça descrita como “06 POLOS LAT”; referência 1412575 consta no próprio cadastro. | CARCAÇA PARA CONECTOR HEAVYCON HC-STA-B06-HLFS-1TTM25-EL-AL TAMANHO B6 ALUMÍNIO ENTRADA RETA M25 ALTURA 52mm. [Phoenix](https://www.phoenixcontact.com/en-pc/products/housing-hc-sta-b06-hlfs-1ttm25-el-al-1412575). |

ID 3754: saída eletrônica normalmente aberta; 3A é limite sujeito à curva de redução de corrente por temperatura, não capacidade garantida em qualquer condição. O sufixo “/2” do modelo não significa duas saídas. ID 477: especificar na descrição a corrente de 4A e a redução para 2A com condutor de 0,14mm². ID 2935: manter `25187` como código cadastrado do fornecedor; `1412575` é a referência Phoenix. B6 é tamanho da carcaça, não prova de quantidade de contatos. A carcaça não inclui prensa-cabo.

### Schneider

| ID / código atual | Problema | Nome proposto e fonte |
| --- | --- | --- |
| 2952 / XPSUAF13AP | “CONTROLADOR DE SEGURANCA” genérico e sem grupo. | RELÉ DE SEGURANÇA HARMONY 2 CANAIS DE ENTRADA 3 SAÍDAS NA 24VCA/CC CONEXÃO POR PARAFUSO. [Schneider](https://iportal.se.com/Contents/docs/SQD-XPSUAF13AP_DATASHEET.PDF). |
| 595 / XB5AD912R10K | “10K” sem unidade de resistência e sem diâmetro. | POTENCIÔMETRO COMPLETO HARMONY XB5 10kΩ Ø22mm CORPO PLÁSTICO. [Schneider](https://www.se.com/us/en/product/XB5AD912R10K/complete-potentiometer-harmony-xb5-plastic-22mm-10k/). |
| 644 / XB5AD912R4K7 | “4 7K” perde a precisão da resistência. | POTENCIÔMETRO COMPLETO HARMONY XB5 4,7kΩ Ø22mm CORPO PLÁSTICO. [Schneider](https://eshop.se.com/sg/complete-potentiometer-harmony-xb5-plastic-22mm-4k7-xb5ad912r4k7.html). |

ID 2952: grupo proposto `RELES_SEGURANCA`, já existente. Não confundir classificação de segurança do componente com validação da máquina completa. Os potenciômetros precisam de grupo adequado; não criar grupo nesta etapa de diagnóstico.

### WEG

| ID / código atual | Problema | Nome proposto e fonte |
| --- | --- | --- |
| 3612 / 18050494 | “SENSOR INDUSTRIAL”; NF identifica MV-CAM1.60E-MF. | CÂMERA PARA VISÃO INDUSTRIAL MV-CAM1.60E-MF 1,6MP 1440X1080 PIXELS MONTAGEM DE LENTE C/CS IP30. [Informativo WEG](https://static.weg.net/medias/downloadcenter/h4b/hdd/WEG_InfoTec_MV-CAM_50146195_pt.pdf). |
| 3324 / 17793861 | “DISJUNTOR CAIXA MOLDADA 440V” omite corrente, polos e ajustes. | DISJUNTOR CAIXA MOLDADA CBW3C-N400GAA3 3P AJUSTE TÉRMICO 280-400A AJUSTE MAGNÉTICO 1000-2000A. [Catálogo WEG CBW3](https://static.weg.net/medias/downloadcenter/h59/h4c/WEG-CBW3-brochure-50160449-en.pdf). |
| 1394 / 18772462 | Mesmo nome genérico do ID 1395. | CONJUNTO DE CORTINA DE LUZ LGW300H-1000 TRANSMISSOR+RECEPTOR ALTURA DE PROTEÇÃO 1000mm RESOLUÇÃO 29mm ALCANCE 0,2-7m TIPO 4 24VCC. [WEG — referência exata](https://www.weg.net/catalog/weg/LU/es/Seguridad-de-M%C3%A1quinas%2C-Sensores-Industriales-y-Fuentes-de-Alimentaci%C3%B3n/Seguridad-de-M%C3%A1quinas/Barreras-de-Seguridad/Barreras-de-Seguridad-LGW300/CORTINA-LUZ-LGW300H-1000/p/18772462). |
| 1395 / 18772436 | Mesmo nome genérico do ID 1394. | CONJUNTO DE CORTINA DE LUZ LGW300H-400 TRANSMISSOR+RECEPTOR ALTURA DE PROTEÇÃO 400mm RESOLUÇÃO 29mm ALCANCE 0,2-7m TIPO 4 24VCC. [WEG — referência exata](https://www.weg.net/catalog/weg/CI/tr/S%C3%A9curit%C3%A9/Safety/Safety-Light-Curtains/Safety-Light-Curtains-LGW300/LIGHT-CURTAIN-LGW300H-400/p/18772436). |

ID 3612: identificação associando modelo da NF à ficha oficial; não interpretar a câmera isolada como sistema de visão completo. ID 3324: proposta ainda requer completar tensão de operação e Icu/Ics correspondente; não reaproveitar “440V” como classe confirmada sem distinguir Ue e Ui. A mudança não deve apagar a descrição anterior.

Para as cortinas, o [catálogo de segurança WEG](https://static.weg.net/medias/downloadcenter/h98/hf3/WEG-catalogo-solucoes-em-seguranca-50029132-pt.pdf) informa fornecimento em par transmissor/receptor e ausência de cabos e relé no conjunto. Conferir unidade comercial já praticada antes de qualquer alteração de unidade; esta revisão não muda saldo ou conversões.

### Rittal

| ID / código atual | Problema | Nome proposto e fonte |
| --- | --- | --- |
| 2503 / CP6206300 | “EMBREAGEM 120/60” descreve incorretamente a função. | ACOPLAMENTO GIRATÓRIO PARA BRAÇO DE SUSTENTAÇÃO CP60 CONEXÃO Ø130mm GIRO 310° ZINCO FUNDIDO RAL7035. [Rittal](https://www.rittal.com/pdf-creator/variant/com-en/6206300). |
| 178 / 3110000 | Faixa “5-55ºC” diverge do fabricante; tensões sem distinção CA/CC. | TERMOSTATO PARA INTERIOR DE PAINEL SK3110.000 AJUSTE 5-60°C 1 CONTATO REVERSÍVEL 24-230VCA/24-60VCC. [Rittal](https://www.rittal.com/us-en_US/products/PG20231215SCH101/PG20231512SCH301/PRO70850?variantId=3110000). |

Termostato: registrar capacidades dos contatos conforme aquecimento/resfriamento e tipo de carga, sem atribuir uma única corrente indiscriminadamente. Todos os 48 itens Rittal ativos estão sem grupo; distinguir armários, acessórios mecânicos, distribuição elétrica e climatização, não classificar tudo como painel.

## Pendências que não devem ser corrigidas por suposição

| ID | Evidência / problema | Próxima conferência |
| --- | --- | --- |
| 688 | Fabricante WEG, fornecedor Siemens, código 5SL13507MB. | Confirmar fabricante pela referência/etiqueta antes de regularizar; não alterar fornecedor comercial automaticamente. |
| 2956 | Schneider LC1G300, nome apenas “CONTATOR”. A família tem sufixos de bobina/variante, conforme [documentação Schneider](https://download.se.com/files?p_Doc_Ref=ENVEOLI2105013&p_File_Name=EoLI_ENVEOLI2105013_V3.pdf&p_enDocType=Circularity+Profile). | Solicitar referência completa ou etiqueta; não adivinhar bobina nem especificações pela família. |
| 2493 | Código Rittal 9340300; descrição cita SV9342300 e 800A. [9340300](https://www.rittal.com/pdf-creator/variant/ca-en/9340300) é suporte OM sem sistema de contatos; [9342300](https://www.rittal.com/pdf-creator/variant/com-en/9342300) é adaptador de conexão de 800A. | Conferir etiqueta/documento de compra: o código e o objeto descrito são diferentes. Não escolher um deles automaticamente. |
| 2908 | Nome WEG “CP420”, mas código 14810513 aponta a [módulo MOD5.00-4RTD](https://www.weg.net/catalog/weg/BW/pt_PT/Drives/Acess%C3%B3rios-para-Drives/Acess%C3%B3rios-Eletroeletr%C3%B4nicos/MODULO-EXPANSAO-FUNCAO-MOD5-00-4RTD/p/14810513). | Confirmar se o código ou o nome está incorreto. |
| 547 | Código comercial 18778 e nome “CONT PHOENIX 06 POLOS MACHO”; NF não fornece referência oficial. | Solicitar referência Phoenix ou foto; código numérico do revendedor não identifica automaticamente produto Phoenix. |
| 3614 | “CABO DE REDE INDUSTRIAL”; NF informa MV-AC-U3.0-5. Pode haver erro de interface/classificação, ainda não confirmado por ficha exata. | Obter documentação; não inferir Ethernet, USB, comprimento ou conectores pelo nome abreviado. |
| 3567 | Siemens 3SE53120SG11, “CHAVE DE SEGURANÇA 24VCC”. | Conferir variante exata antes de completar contatos, bloqueio, atuador e conexão. |

Também permanecem para pesquisa os acessórios WEG MV-LS-VAR-6, MV-IO-12-3M, WCD-ED400-CVU e MV-LIGHT-PB-31.5-D. Não expandir especificações apenas decodificando seus nomes.

## Decisões incorporadas ao padrão do agente após aprovação

As premissas abaixo foram incorporadas ao catálogo D-035 (versão 1.23.0), no trecho operacional consumido pelo cadastro assistido e pelo importador. Foram ampliadas as verificações compartilhadas de completude e os testes; esta ativação no código local não equivale à publicação remota:

1. Separar potência nominal, potência de pico e potência do equipamento compatível; preservar tempo e ciclo quando a capacidade depender deles.
2. Em relés, distinguir alimentação/entrada e circuito de saída, quantidade/tipo de saídas e conexão. Não transformar dígitos do modelo em quantidades.
3. Separar código comercial do fornecedor de referência do fabricante. Para código numérico, incluir família/modelo alfanumérico confirmado na descrição, preservando os códigos de integração existentes.
4. Em contatores, exigir referência completa de variante/bobina; não pesquisar somente família e completar por semelhança.
5. Em SFPs, identificar velocidade, tipo de fibra, conector e alcance. Em câmeras, identificar modelo, resolução e interface confirmada, sem confundir câmera com sistema completo.
6. Em carcaças e armários, distinguir material, dimensões e ordem dos eixos, tipo de entrada e compatibilidade. Tamanho da carcaça não é quantidade de contatos.
7. Em cortinas de luz, distinguir altura de proteção, resolução, alcance, tipo, alimentação e composição do fornecimento, sem alterar unidade comercial por inferência.
8. Quando código e descrição apontarem a produtos diferentes, sinalizar conflito e bloquear enriquecimento automático da identidade. Guardar fonte, referência encontrada e motivo da pendência.
9. Manter os padrões já solicitados: unidade sem espaço do número, símbolos corretos (`kΩ`, `kW`, `mm`), remoção de texto comercial/pedido e pesquisa prioritária em fonte oficial.

## Condições para uma aplicação posterior

- Aprovar o lote e as decisões de padronização; pendências de identidade ficam fora de atualização automática.
- Completar atributos críticos ainda pendentes, especialmente tensão e interrupção do ID 3324.
- Reconsultar cada registro no mesmo tenant/empresa e comparar com o retrato para não sobrescrever edições posteriores.
- Gerar backup anterior à escrita e trilha de antes/depois com fonte por item; não alterar saldos, unidades ou códigos por esta revisão.
- Atualizar o padrão ativo do agente com as decisões aprovadas e criar testes dos erros identificados.
- Conferir registros gravados e comportamento na entrada de novos itens. Nesta execução, registros, testes de regressão e código foram validados conforme o resultado no início do documento; a conferência visual da tela autenticada continua não realizada.
