# Fluxo de revisão em lotes de 50

Decisão D-039, 07/09/2026. Este documento não concede aprovação a lotes futuros.

- Aplicado: lote 003, 50 IDs únicos (45 minidisjuntores + 5 contatores Siemens).
- Aplicado e verificado: lote 004, 50 outros IDs (35 WEG + 15 disjuntores-motor Siemens), após “pode seguir...” do usuário. Aprovação e assinatura em `aprovacao-004.json`.
- Aplicado e verificado: lote 005, 50 outros IDs Siemens, após “PODE SEGUIR...” de 09/09/2026. Aprovação e assinatura em `aprovacao-005.json`.
- Aguardando aprovação: lote 006, 50 novos IDs Siemens, com antes/depois e fontes no relatório correspondente. Nenhum aplicado; quatro bases NH têm revisão parcial expressamente sinalizada.
- Manifestos congelados guardam antes/depois, referência exata, fonte, páginas conferidas, hash do PDF e impressão técnica do cadastro.
- Proposta não aplicada não é evento de aprovação nem exemplo humano aprovado para o agente.
- Cada nova aprovação deve identificar lote/IDs e versão da proposta. Alterações pedidas pelo usuário voltam à conferência técnica. Não interpretar aprovação de um lote como autorização do próximo.
- Antes de gravar, reler os itens com tenant_id e empresa_id; interromper em mudança técnica concorrente. Somente nome/descrição estão autorizados nesta rodada.
- Depois de gravar, conferir retorno e releitura, preservar todos os outros campos e emitir eventos por ID. Repetição do roteiro não reaplica nomes/descrições já iguais.
- Atualizar o padrão ativo do agente somente com decisões aprovadas. D-039, D-040 e D-041 estão no YAML 1.29.0, antes do histórico, no trecho lido pelos agentes; os exemplos aplicados dos lotes 003/004/005 foram incorporados. O lote 006 não foi incorporado como exemplo aprovado. Não houve publicação/deploy nesta rodada.
- Contagem por ID: aprovado, pendente, reavaliar, histórico recuperado/informado e não revisado. Propostas são fila separada, sem somá-las a aprovados. A campanha de 104 alertas é um subconjunto; não equivale ao catálogo completo nem aos 1.193 agrupados.

## Arquivos e retomada

1. Consultar `andamento.json` atualizado e `propostas_nao_aplicadas` antes de selecionar novos IDs.
2. Apresentar `lote-006-cinquenta-itens.md` para aprovação. Nenhum dos 50 foi gravado por este lote. Consultar `pesquisa-adiada-005.json` e `pesquisa-adiada-006.json` para não repetir pesquisas sem nova evidência.
3. Após aprovação explícita, registrar a decisão e adaptar o roteiro de aplicação para o manifesto/assinatura aprovados. O roteiro atual bloqueia `--lote=006 --apply` antes de abrir conexão, mesmo com aprovação de outro lote ou flag adulterada. Converter critérios provisórios das novas famílias em critérios ativos apenas após aprovação e tratamento das ressalvas do relatório.
4. Aplicar, conferir, registrar aprendizado e apresentar mais 50 antes/depois. Manter ordem: disjuntores/contatores; CLPs/remotas/cartões; sensores; painéis.

Backup da aplicação: `backups/revisao-lotes/003-2026-09-07T20-26-06-525Z.json` e resultado por linha no arquivo `.resultado.jsonl` correspondente.

Backup do lote 004: `backups/revisao-lotes/004-2026-09-07T22-28-57-677Z.json`, com aprovação, manifesto e valores anteriores completos; resultados por linha no `.resultado.jsonl`. Conferidos 50 retornos e releitura final, preservando os demais campos.

Documentos técnicos, extrações e imagens conferidas foram preservados localmente em `backups/fontes-lotes-003-004/`. Os hashes estão nos manifestos; são documentos públicos Siemens/WEG. O catálogo Siemens é de autoria Siemens e está hospedado pela Fegime. Não inferir capacidade pela série sem confirmar variante, tabela, tensão e norma.

## Validação desta rodada

Fontes do lote 005: `backups/fontes-lote-005/`, 50 PDFs das referências exatas, textos e páginas renderizadas conferidas. Os 50 candidatos têm histórico de grupo e não repetem IDs dos lotes anteriores. Os casos de informação parcial estão explicitados no relatório; aprovação das alterações não equivale a certificação de todos os atributos possíveis.

`node scripts/test-lotes-cinquenta.mjs`: 200 IDs distintos nos lotes 003/004/005/006, bloqueio de aprovação de 006, concorrência, idempotência, campos protegidos, capacidades e frequências condicionadas.

`node scripts/aplicar-lote-cinquenta.mjs --lote=003 --verify`: 50 já aplicados; zero alteração pendente.

`node scripts/aplicar-lote-cinquenta.mjs --lote=004 --verify`: 50 já aplicados; zero alteração pendente.

`node scripts/aplicar-lote-cinquenta.mjs --lote=005 --verify`: 50 aplicados; zero alteração pendente. Backup `backups/revisao-lotes/005-2026-09-09T13-01-40-870Z.json`, resultados individuais `.resultado.jsonl` e eventos por ID.

`node scripts/aplicar-lote-cinquenta.mjs --lote=006`: somente leitura, 50 alterações propostas e zero aplicado. Fontes preservadas em `backups/fontes-lote-006/`.

Consultar `andamento.json`/`andamento.md` após `node scripts/andamento-revisoes.mjs --save` para contagem atual. As revisões históricas permanecem separadas; aprovados no critério atual não equivalem a todos os itens alterados no passado. Grupo preenchido define prioridade, não certificação técnica completa. As quatro bases NH da proposta 006 têm lacunas explícitas de tensão, polos e conexão.
