# Modelos propostos — lote 009 SICK

APROVADO E APLICADO em 10/09/2026 após “pode dar sequencia”. Incorporado ao padrão ativo 1.33.0/D-045, mantendo ressalvas dos IDs 1708/438. Este documento conserva o nome histórico; não autoriza lote 010.

Escopo: 50 IDs do manifesto `lote-009-cinquenta-itens.json`, tenant `3ced7cfa-efbb-4f0f-addc-2028f60d1ca7`, empresa `f0e74f49-a127-46b4-901b-f7b37e43c690`. Somente nome/descrição; grupos e conversões preservados.

## Regras aprovadas para aprendizado

- Código numérico exige modelo alfanumérico e família identificável no nome; consultar a referência exata, não completar por similaridade. Evidência com URL, data, PDF preservado, páginas e SHA-256.
- Indutivos: família/modelo, rosca, alcance nominal, PNP/NPN e NA/NF, alimentação, montagem faceada/não faceada, corpo curto/padrão, conector ou cabo com material/comprimento. Alcance assegurado e fatores do alvo no complemento; MTTFd não torna sensor padrão em sensor de segurança.
- Fotoelétricos: distinguir difuso energético, supressão de fundo, retrorreflexivo e barreira emissor/receptor. Distinguir faixa operacional e máxima, refletor/alvo de referência, modo claro/escuro e seleção versus saída complementar. Conector/pinos e alimentação por versão; laser classe 1 não implica proteção de pessoas.
- Sensor tipo garfo: abertura, profundidade, menor objeto e frequência separados; push-pull PNP/NPN configurável não equivale a duas saídas independentes.
- Cortinas: nome deve identificar emissor OU receptor, família/versão, altura protegida, resolução, alcance e alimentação. OSSD somente em receptor: quantidade e corrente por saída. Não presumir System Plug incluído ou pinagem fixa quando depende de SP1/SP2; distinguir Core. SIL/PL do componente não certifica a instalação.
- Cabos com conector: especificar modelo, M12 macho/fêmea, orientação, pinos, extremidade livre, vias×seção, comprimento, PUR/PVC, blindagem e tensão/corrente do conjunto. Tensão do cabo isoladamente não substitui limite do conjunto; IP somente na conexão acoplada. Não converter automaticamente unidade ou tratar conjunto como cabo a granel sem conector.
- Chaves/atuadores/habilitadores: separar dispositivo completo de acessório passivo, contatos principais/auxiliares e categorias AC-15/DC-13. Corrente do circuito de habilitação e de botões auxiliares pode diferir. Kit mecânico de cabo de tração não é cabo elétrico. IME2S desta referência: SIL2/categoria 2/PLd, não herdar SIL3 de outra família.
- Flexi: separar CPU de expansão; entradas/saídas de segurança, saídas de teste e modos configuráveis não são a mesma coisa. Confirmar protocolo e conectores exatos. Não inferir compatibilidade entre todas as gerações Flexi.
- Ultrassônicos: faixa operacional versus limite, uma saída corrente OU tensão conforme carga, alimentação condicionada ao modo (UC30: 9-30VCC em corrente, 15-30VCC em tensão) e cargas admissíveis. Não fixar dimensões que variam por número de série.
- Nível: separar contínuo e pontual, comprimento da haste versus área útil/zonas inativas, rosca, partes molhadas e corpo, saída e alimentação. Não inferir IO-Link de família. ID 438: divergência documental 67mm/38mm permanece para conferência física.
- Fluxo: meio e faixa condicionados, haste, montagem específica, saídas alternativas/pulso/IO-Link sem somar canais; pressão depende do adaptador e temperatura.
- Temperatura: elemento Pt1000 não significa saída resistiva; ID 1714 tem transmissor 4-20mA de dois fios. Informar faixa, classe, rosca, inserção×diâmetro, materiais e alimentação; pressão máxima condicionada à temperatura.
- Pressão: usar faixa e sinal da referência exata; tensão de isolação/sobretensão não é alimentação. ID 1708 permanece PARCIAL: fonte histórica SICK hospedada por terceiro, alimentação e ligação de dois fios não confirmadas. Preservar histórico explicitamente rotulado.
- Encoder: pulsos por volta, TTL/HTL configurável e padrão de fábrica separados; eixo, diâmetro, conector e orientação. IP do corpo/conector pode diferir do eixo; não presumir programação atual da peça.
- Unidades sem espaço do número, preservando convenções do normalizador. Não reduzir especificações por limite de nome: condicionantes e detalhes ficam na descrição complementar.

## Rastreabilidade

Manifesto conserva critérios históricos `FAMILIA:proposta009` e assinatura aprovada; os 50 eventos confirmados usam critérios ativos `FAMILIA:1`. Consultar antes/depois completo no relatório do lote. As lacunas não são certificadas por aprovação da redação e continuam registradas após aplicação.

Fontes lidas em texto e tabelas relevantes conferidas visualmente conforme a skill de PDF; a inspeção de tabelas permitiu separar corrente por OSSD, limites de alimentação por modo e limites de IP por região. Não foi criado PDF de entrega: o relatório é Markdown.
