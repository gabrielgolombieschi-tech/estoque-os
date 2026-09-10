# Fluxo de revisão contínua por referência clara

Decisão vigente D-047, 10/09/2026, padrão 1.35.0. Substitui a aprovação repetida a cada 50 da D-039 nesta campanha: aplicar todas as referências tecnicamente claras, registrar por ID e apresentar somente exceções. Não altera a autonomia da entrada de novos itens por XML nem autoriza mudanças além de nome/descrição.

- Aplicado: lote 003, 50 IDs únicos (45 minidisjuntores + 5 contatores Siemens).
- Aplicado e verificado: lote 004, 50 outros IDs (35 WEG + 15 disjuntores-motor Siemens), após “pode seguir...” do usuário. Aprovação e assinatura em `aprovacao-004.json`.
- Aplicado e verificado: lote 005, 50 outros IDs Siemens, após “PODE SEGUIR...” de 09/09/2026. Aprovação e assinatura em `aprovacao-005.json`.
- Aplicado e verificado: lote 006, 50 novos IDs Siemens, após “pode seguir” de 09/09/2026, conforme `aprovacao-006.json`. As quatro bases NH continuam com revisão parcial explicitamente registrada, sem certificar tensão/polos/conexão ausentes.
- Aplicado e verificado: lote 007, 50 novos IDs (49 WEG + 1 Schneider), após “pode seguir” de 09/09/2026, conforme `aprovacao-007.json`. Seccionadora antiga ID 1884 continua com revisão parcial; demais limitações estão discriminadas por item.
- Aplicado e verificado: lote 008, 50 novos IDs Siemens de CLPs/remotas/cartões e acessórios/interfaces relacionados, após “pode seguir” de 09/09/2026. Aprovação em `aprovacao-008.json`; modelos incorporados pela D-044. Grupo 55 do ID 3733 preservado; ressalvas no relatório.
- Aplicado e verificado: lote 009, 50 novos IDs SICK de sensores/segurança e acessórios relacionados, após “pode dar sequencia” de 10/09/2026. Aprovação em `aprovacao-009.json`; modelos incorporados pela D-045. IDs 1708 e 438 mantêm ressalvas documentais explícitas.
- Aplicado e verificado: lote 010, 50 novos IDs Siemens (47 SIRIUS ACT e 3 chaves 3SE), após “pode alterar” em 10/09/2026. Aprovação em `aprovacao-010.json`; modelos incorporados pela D-046. ID 215 mantém revisão parcial; ID 1695 corrigido de 220V para 24V conforme referência exata, sem autorizar intervenção elétrica.
- Aplicação parcial verificada: lote 011, 28 claros aplicados e 22 retidos intactos. Autorização condicional e assinatura em `liberacao-011-referencias-claras.json`. Não aplicar os retidos por simples aprovação em bloco; buscar a evidência faltante. Embalagem/unidade do ID 2535 permanecem iguais.
- Manifestos congelados guardam antes/depois, referência exata, fonte, páginas conferidas, hash do PDF e impressão técnica do cadastro.
- Proposta não aplicada não é evento de aprovação nem exemplo humano aprovado para o agente.
- Cada liberação técnica deve identificar IDs e assinatura da proposta, fontes e páginas conferidas. A D-047 autoriza a continuidade sem nova aprovação humana a cada lote; não autoriza preencher lacunas por similaridade.
- Antes de gravar, reler os itens com tenant_id e empresa_id; interromper em mudança técnica concorrente. Somente nome/descrição estão autorizados nesta rodada.
- Depois de gravar, conferir retorno e releitura, preservar todos os outros campos e emitir eventos por ID. Repetição do roteiro não reaplica nomes/descrições já iguais.
- D-047 está no YAML 1.35.0, antes do histórico, no trecho lido pelos agentes. Aprendizado técnico confirmado sob delegação não deve ser rotulado como aprovação humana individual. O subconjunto claro do 011 foi incorporado; os demais 22 não. Não houve publicação/deploy nesta rodada.
- Contagem por ID: aprovado, pendente, reavaliar, histórico recuperado/informado e não revisado. Propostas são fila separada, sem somá-las a aprovados. A campanha de 104 alertas é um subconjunto; não equivale ao catálogo completo nem aos 1.193 agrupados.

## Arquivos e retomada

1. Consultar `andamento.json` atualizado e `propostas_nao_aplicadas` antes de selecionar novos IDs.
2. Consultar `excecoes-referencias-claras.md` para os casos duvidosos desta rodada; `fila-paineis-referencias-claras.json` separa esses casos dos ainda não pesquisados. Pendências antigas continuam em `pesquisa-adiada-*.json` e nas ressalvas dos lotes anteriores. Não declarar famílias ou catálogo concluídos só por terminar um recorte.
3. Usar `aplicar-referencias-claras.mjs` com manifesto e liberação assinados. O roteiro antigo de cinquenta continua bloqueando a aplicação integral do 011. O formato contínuo não exige completar cinquenta para aplicar um item claro; preserva as mesmas travas de escopo, concorrência, backup e conferência integral dos campos.
4. Aplicar claros, conferir e registrar aprendizado. Antes/depois fica na auditoria interna; apresentar ao usuário somente exceções. Pendências só voltam com nova evidência. Manter ordem da campanha: disjuntores/contatores; CLPs/remotas/cartões; sensores; painéis.

Backup da aplicação: `backups/revisao-lotes/003-2026-09-07T20-26-06-525Z.json` e resultado por linha no arquivo `.resultado.jsonl` correspondente.

Backup do lote 004: `backups/revisao-lotes/004-2026-09-07T22-28-57-677Z.json`, com aprovação, manifesto e valores anteriores completos; resultados por linha no `.resultado.jsonl`. Conferidos 50 retornos e releitura final, preservando os demais campos.

Documentos técnicos, extrações e imagens conferidas foram preservados localmente em `backups/fontes-lotes-003-004/`. Os hashes estão nos manifestos; são documentos públicos Siemens/WEG. O catálogo Siemens é de autoria Siemens e está hospedado pela Fegime. Não inferir capacidade pela série sem confirmar variante, tabela, tensão e norma.

## Validação desta rodada

Sob D-047: 29 aplicações verificadas (28 do 011 e 1 no 012), 36 exceções registradas sem alteração. Testes de autorização condicional, quantidade variável, assinatura, escopo, idempotência, concorrência e campos protegidos passaram; ESLint dos arquivos alterados sem erros. Verificações remotas dos lotes 011 e 012 confirmaram zero alteração pendente nos claros. Os parágrafos abaixo preservam a validação histórica anterior à D-047.

Backups desta rodada: `backups/revisao-lotes/011-claros-2026-09-10T17-50-13-655Z.json` e `backups/revisao-lotes/012-claros-2026-09-10T18-02-28-407Z.json`, com resultados por linha. Fila dos grupos da etapa: 167 IDs, 31 já aprovados (29 nesta rodada e 2 anteriormente), 36 exceções e 100 aguardando pesquisa. Não equivale a 100% do catálogo nem a todos os componentes Siemens.

Fontes do lote 005: `backups/fontes-lote-005/`, 50 PDFs das referências exatas, textos e páginas renderizadas conferidas. Os 50 candidatos têm histórico de grupo e não repetem IDs dos lotes anteriores. Os casos de informação parcial estão explicitados no relatório; aprovação das alterações não equivale a certificação de todos os atributos possíveis.

`node scripts/test-lotes-cinquenta.mjs`: 200 IDs distintos nos lotes 003/004/005/006, aprovação vinculada ao conteúdo exato, concorrência, idempotência, campos protegidos, capacidades e frequências condicionadas. Testes 007/008/009/010: 250/300/350/400 IDs distintos, aprovação vinculada ao conteúdo exato, hashes/modelos/páginas e ressalvas preservadas. `node scripts/test-lote-011.mjs`: 450 IDs distintos incluindo 50 propostas não aprovadas, campos protegidos e aplicação 011 bloqueada antes da conexão. Todos passaram; teste de fabricantes e 18 casos de normalização também. ESLint dos roteiros alterados sem erro.

`node scripts/aplicar-lote-cinquenta.mjs --lote=003 --verify`: 50 já aplicados; zero alteração pendente.

`node scripts/aplicar-lote-cinquenta.mjs --lote=004 --verify`: 50 já aplicados; zero alteração pendente.

`node scripts/aplicar-lote-cinquenta.mjs --lote=005 --verify`: 50 aplicados; zero alteração pendente. Backup `backups/revisao-lotes/005-2026-09-09T13-01-40-870Z.json`, resultados individuais `.resultado.jsonl` e eventos por ID.

`node scripts/aplicar-lote-cinquenta.mjs --lote=006 --verify`: 50 aplicados e zero alteração pendente. Backup completo `backups/revisao-lotes/006-2026-09-09T19-10-34-146Z.json`, resultados `.resultado.jsonl` e eventos por ID. Fontes em `backups/fontes-lote-006/`.

`node scripts/aplicar-lote-cinquenta.mjs --lote=007 --verify`: 50 aplicados e zero alteração pendente. Backup completo `backups/revisao-lotes/007-2026-09-09T20-27-48-619Z.json`, resultados `.resultado.jsonl` e eventos por ID. Fontes públicas em `backups/fontes-lote-007/`: PDFs, extrações, páginas conferidas e resultados web preservados; evidências identificadas pelo tipo, sem apresentar captura web como PDF baixado.

`node scripts/aplicar-lote-cinquenta.mjs --lote=008 --verify`: 50 aplicados, zero alteração pendente, releitura em 09/09/2026. Backup completo `backups/revisao-lotes/008-2026-09-09T21-15-58-264Z.json`, resultados individuais `.resultado.jsonl` e eventos por ID. Fontes em `backups/fontes-lote-008/`: 50 PDFs das referências exatas, textos e páginas renderizadas conferidas. Nas consultas, `node --use-system-ca` utiliza as autoridades confiáveis do Windows mantendo validação TLS ativa.

Lote 009: manifesto congelado SHA-256 `714df3a7c6a7ecd536a4e4be40768b1142f7854d5cd5f7e86f5d1db237d7d87b`. Fontes em `backups/fontes-lote-009/`, incluindo manual comum aos atuadores 426/427 e catálogo do 438. Fonte 1708: ficha histórica de autoria SICK hospedada pela PZIP, não apresentada como hospedagem oficial. Inspeção de texto e tabelas relevantes renderizadas conforme skill PDF. Sem alteração de unidades/conversões, inclusive dos quatro conjuntos com conector.

`node --use-system-ca scripts/aplicar-lote-cinquenta.mjs --lote=009 --verify`: 50 aplicados e zero alteração pendente, releitura em 10/09/2026. Backup completo `backups/revisao-lotes/009-2026-09-10T12-48-20-171Z.json`, resultados individuais `.resultado.jsonl` e eventos por ID. Somente nome/descrição alterados; demais campos preservados.

Lote 010: manifesto congelado SHA-256 `6b82344ea80f3e00a8c260b5e4866879cc3850a5aeba56c8b6b32d904d4d2276`. Fontes em `backups/fontes-lote-010/`: 50 PDFs oficiais Siemens, metadados, extrações e páginas renderizadas. Backup `backups/revisao-lotes/010-2026-09-10T13-14-09-052Z.json`; resultados `.resultado.jsonl`; 50 eventos emitidos após conferência. Releitura `--lote=010 --verify`: 50 já aplicados e zero alteração pendente. Somente nome/descrição alterados. O relatório distingue cabeçotes de conjuntos completos e alimentação de LED de tensão de isolamento, mantendo ressalvas.

Lote 011: manifesto SHA-256 `588f94f2467f6f9871276cb46677686cf52c6284dbd131e701b0432552417219`. Fontes em `backups/fontes-lote-011/`: 50 PDFs oficiais, textos, metadados e páginas renderizadas. Conferência textual das páginas utilizadas e visual das tabelas críticas conforme skill PDF. Nenhum evento aprovado emitido. Fora do lote: cinco 8WA com HTTP 404; ver `pesquisa-adiada-011.json`. Não inferir inexistência/descontinuação. Pares de possíveis duplicidades não unificados; embalagem de 50 unidades do RJ45 não convertida.

Consulta final de 10/09/2026 às 13:32 UTC: 3.650 itens; 438 aprovados no critério atual, 2 pendentes, 0 para reavaliar, 251 históricos recuperados, 546 históricos informados e 2.413 não revisados. Os 50 aplicados migraram dos históricos para aprovados, sem duplicidade. Lote 011: 50 propostas aguardando aprovação, zero desatualizadas após conferir impressão técnica e atividade contra o banco. A contagem é uma fotografia; proposta não soma aprovação e aprovação da redação não certifica atributos ausentes.

Consultar `andamento.json`/`andamento.md` após `node scripts/andamento-revisoes.mjs --save` para contagem atual. As revisões históricas permanecem separadas; aprovados no critério atual não equivalem a todos os itens alterados no passado. Grupo preenchido define prioridade, não certificação técnica completa. As quatro bases NH aprovadas no lote 006 mantêm lacunas explícitas de tensão, polos e conexão.
