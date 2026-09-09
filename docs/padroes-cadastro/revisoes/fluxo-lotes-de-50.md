# Fluxo de revisão em lotes de 50

Decisão D-039, 07/09/2026. Este documento não concede aprovação a lotes futuros.

- Aplicado: lote 003, 50 IDs únicos (45 minidisjuntores + 5 contatores Siemens).
- Aplicado e verificado: lote 004, 50 outros IDs (35 WEG + 15 disjuntores-motor Siemens), após “pode seguir...” do usuário. Aprovação e assinatura em `aprovacao-004.json`.
- Aplicado e verificado: lote 005, 50 outros IDs Siemens, após “PODE SEGUIR...” de 09/09/2026. Aprovação e assinatura em `aprovacao-005.json`.
- Aplicado e verificado: lote 006, 50 novos IDs Siemens, após “pode seguir” de 09/09/2026, conforme `aprovacao-006.json`. As quatro bases NH continuam com revisão parcial explicitamente registrada, sem certificar tensão/polos/conexão ausentes.
- Aguardando aprovação: lote 007, 50 novos IDs (49 WEG + 1 Schneider). Nenhum aplicado; antes/depois completo no relatório. Seccionadora antiga ID 1884 tem revisão parcial; demais limitações estão discriminadas por item.
- Manifestos congelados guardam antes/depois, referência exata, fonte, páginas conferidas, hash do PDF e impressão técnica do cadastro.
- Proposta não aplicada não é evento de aprovação nem exemplo humano aprovado para o agente.
- Cada nova aprovação deve identificar lote/IDs e versão da proposta. Alterações pedidas pelo usuário voltam à conferência técnica. Não interpretar aprovação de um lote como autorização do próximo.
- Antes de gravar, reler os itens com tenant_id e empresa_id; interromper em mudança técnica concorrente. Somente nome/descrição estão autorizados nesta rodada.
- Depois de gravar, conferir retorno e releitura, preservar todos os outros campos e emitir eventos por ID. Repetição do roteiro não reaplica nomes/descrições já iguais.
- Atualizar o padrão ativo do agente somente com decisões aprovadas. D-039 a D-042 estão no YAML 1.30.0, antes do histórico, no trecho lido pelos agentes; exemplos aplicados dos lotes 003/004/005/006 incorporados. O lote 007 não foi incorporado como exemplo aprovado. Não houve publicação/deploy nesta rodada.
- Contagem por ID: aprovado, pendente, reavaliar, histórico recuperado/informado e não revisado. Propostas são fila separada, sem somá-las a aprovados. A campanha de 104 alertas é um subconjunto; não equivale ao catálogo completo nem aos 1.193 agrupados.

## Arquivos e retomada

1. Consultar `andamento.json` atualizado e `propostas_nao_aplicadas` antes de selecionar novos IDs.
2. Apresentar `lote-007-cinquenta-itens.md` para aprovação. Nenhum dos 50 foi gravado por este lote. Consultar `pesquisa-adiada-005.json`, `pesquisa-adiada-006.json` e `pesquisa-adiada-007.json` para não repetir pesquisas sem nova evidência.
3. Após aprovação explícita, registrar a decisão e adaptar o roteiro de aplicação para o manifesto/assinatura aprovados. O roteiro atual bloqueia `--lote=007 --apply` antes de abrir conexão, mesmo com aprovação de outro lote ou flag adulterada. Converter critérios provisórios das novas famílias em critérios ativos apenas após aprovação e tratamento das ressalvas do relatório.
4. Aplicar, conferir, registrar aprendizado e apresentar mais 50 antes/depois. Manter ordem: disjuntores/contatores; CLPs/remotas/cartões; sensores; painéis.

Backup da aplicação: `backups/revisao-lotes/003-2026-09-07T20-26-06-525Z.json` e resultado por linha no arquivo `.resultado.jsonl` correspondente.

Backup do lote 004: `backups/revisao-lotes/004-2026-09-07T22-28-57-677Z.json`, com aprovação, manifesto e valores anteriores completos; resultados por linha no `.resultado.jsonl`. Conferidos 50 retornos e releitura final, preservando os demais campos.

Documentos técnicos, extrações e imagens conferidas foram preservados localmente em `backups/fontes-lotes-003-004/`. Os hashes estão nos manifestos; são documentos públicos Siemens/WEG. O catálogo Siemens é de autoria Siemens e está hospedado pela Fegime. Não inferir capacidade pela série sem confirmar variante, tabela, tensão e norma.

## Validação desta rodada

Fontes do lote 005: `backups/fontes-lote-005/`, 50 PDFs das referências exatas, textos e páginas renderizadas conferidas. Os 50 candidatos têm histórico de grupo e não repetem IDs dos lotes anteriores. Os casos de informação parcial estão explicitados no relatório; aprovação das alterações não equivale a certificação de todos os atributos possíveis.

`node scripts/test-lotes-cinquenta.mjs`: 200 IDs distintos nos lotes 003/004/005/006, aprovação vinculada ao conteúdo exato, concorrência, idempotência, campos protegidos, capacidades e frequências condicionadas. `node scripts/test-lote-007.mjs`: 250 IDs distintos incluindo as 50 propostas; aprovação 007 bloqueada e hashes de evidência conferidos.

`node scripts/aplicar-lote-cinquenta.mjs --lote=003 --verify`: 50 já aplicados; zero alteração pendente.

`node scripts/aplicar-lote-cinquenta.mjs --lote=004 --verify`: 50 já aplicados; zero alteração pendente.

`node scripts/aplicar-lote-cinquenta.mjs --lote=005 --verify`: 50 aplicados; zero alteração pendente. Backup `backups/revisao-lotes/005-2026-09-09T13-01-40-870Z.json`, resultados individuais `.resultado.jsonl` e eventos por ID.

`node scripts/aplicar-lote-cinquenta.mjs --lote=006 --verify`: 50 aplicados e zero alteração pendente. Backup completo `backups/revisao-lotes/006-2026-09-09T19-10-34-146Z.json`, resultados `.resultado.jsonl` e eventos por ID. Fontes em `backups/fontes-lote-006/`.

`node scripts/aplicar-lote-cinquenta.mjs --lote=007`: somente leitura, 50 propostas, zero aplicado, nenhum conflito com a base. Fontes públicas em `backups/fontes-lote-007/`: PDFs, extrações, páginas conferidas e resultados web preservados; evidências identificadas pelo tipo, sem apresentar captura web como PDF baixado.

Consulta de 09/09/2026 às 19:39 UTC: 3.650 itens; 238 aprovados no critério atual, 2 pendentes, 0 para reavaliar, 320 históricos recuperados, 677 históricos informados e 2.413 não revisados. Há 50 propostas aguardando aprovação e nenhuma desatualizada. A contagem inclui novos cadastros concorrentes; não altera a composição congelada dos lotes.

Consultar `andamento.json`/`andamento.md` após `node scripts/andamento-revisoes.mjs --save` para contagem atual. As revisões históricas permanecem separadas; aprovados no critério atual não equivalem a todos os itens alterados no passado. Grupo preenchido define prioridade, não certificação técnica completa. As quatro bases NH aprovadas no lote 006 mantêm lacunas explícitas de tensão, polos e conexão.
