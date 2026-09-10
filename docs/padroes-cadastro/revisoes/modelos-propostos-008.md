# Modelos propostos — lote 008

PROPOSTA HISTÓRICA APROVADA E APLICADA em 09/09/2026, conforme `aprovacao-008.json` e `eventos-008-cinquenta-itens.json`. Modelos ativos incorporados ao catálogo YAML na D-044, versão 1.32.0. Este arquivo preserva a redação originalmente apresentada; não concede aprovação a lotes futuros.

Fontes: 50 fichas oficiais Siemens identificadas por referência, URL, páginas conferidas e SHA-256 no manifesto `lote-008-cinquenta-itens.json`. Os modelos abaixo descrevem a proposta apresentada, sem autorizar a aplicação.

- CLP: família + geração + CPU + alimentação + DI/DO/AI/AO + tipo/corrente de saída + portas/protocolo. Memória de programa, dados e carga separadas; quando compartilhada, não duplicar. Não transportar capacidades entre S7-1200 e G2.
- Digital: módulo SM ou placa SB + família/geração + canais + tensão de sinal + sink/source/PNP conforme ficha + transistor/relé + corrente por canal. Frequência máxima só na variante exata e sob condições aplicáveis.
- Analógico: AI/AO + quantidade + tipo de sinal/faixas + resolução por modo + base/ligação compatível. Não contar a mesma entrada configurável como dois canais. Não confundir limite de destruição com faixa útil.
- Segurança: identificar F-DI/F-DQ, HF quando confirmado, PP/PM/PPM, canais físicos e corrente. Canais redundantes não equivalem ao mesmo número de funções seguras. PL/SIL do módulo não é certificação da instalação.
- Remota/comunicação: família + modelo + protocolo + papel mestre/device/coupler + interfaces e portas físicas + conexão + alimentação. Separar limite de módulos, controladores e portas. Registrar BusAdapter exigido e itens efetivamente incluídos.
- BaseUnit: referência + tipo + conexão + auxiliares + início/continuidade de grupo de potencial. Distinguir base passiva, placa de sinal, módulo eletrônico e módulo servidor.
- Trilho/conector/cartão: material, dimensão, polos/conexão e família compatível. Largura do módulo não é passo de conector. Foto ilustrativa não prevalece sobre tabela da referência.
- Pesagem: módulo versus célula de carga, número de canais, tecnologia/faixa da célula, alimentação, interfaces e operação integrada/autônoma; sem presumir célula incluída.
- Interface de operação: família/modelo, tamanho/resolução/tipo de tela, protocolo/portas e alimentação. Display de texto não é CPU ou touchscreen.

Versões de firmware e engenharia da ficha consultada não comprovam versão instalada. Conferir equipamento físico antes de assegurar compatibilidade. Nenhuma mudança de firmware, grupo, unidade, multiplicador, preço, saldo, código ou atividade faz parte deste lote.

ID 3733: proposta corrige nome para ET200SP; grupo atual 55 é preservado e fica sinalizado para avaliação separada. ID 2461 não integra os 50 por ficha indisponível.
