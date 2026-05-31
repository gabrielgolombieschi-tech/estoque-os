# Mapa do fluxo atual de importação XML/NF-e

Documento de mapeamento do fluxo atual. Nesta etapa nao ha chamada OpenAI, nao ha integracao de IA, nao ha alteracao de cobranca, banco ou migrations.

## Arquivos principais

- `app/estoque/importar/page.tsx`: tela principal de importacao de XML de NF-e para estoque. Concentra leitura de arquivo, parse inicial, verificacao/criacao de fornecedor, verificacao/criacao de itens, escolha de finalidade/motivo/solicitante, busca de OS, busca de pedido de compra, montagem do payload e chamada da API de importacao.
- `app/estoque/importar/layout.tsx`: envolve a tela com `PermissionsProvider` e `ImportMotivosProvider`.
- `app/estoque/importar/ImportMotivosProvider.tsx`: carrega motivos/classificacoes via `/api/estoque/motivos-compra?origem=XML_PRODUTO`.
- `app/estoque/importar/MotivoCompraCombobox.tsx`: componente de selecao/favorito da classificacao/motivo.
- `lib/nfe/parseNfeXml.ts`: parser client-side da NF-e. Usa `DOMParser`, extrai cabecalho, totais, itens, impostos por item e duplicatas/parcelas.
- `src/lib/importacaoXmlParams.ts`: carrega parametros de importacao XML em `public.parametro_importacao_xml`, com fallback local para finalidades que permitem vinculo/autocadastro.
- `app/api/estoque/importar-xml/route.ts`: endpoint server-side que valida permissao/empresa, resolve fornecedor, tenta vincular pedido, valida motivo/solicitante/itens, chama `public.import_nf_entrada` e executa sincronizacoes posteriores de estoque, AP, impostos, OS e pedido.
- `app/api/estoque/usuarios-solicitantes/route.ts`: lista usuarios solicitantes ativos da empresa/tenant.
- `app/api/estoque/motivos-compra/route.ts`: lista e favorita motivos de compra aplicaveis a XML de produtos.
- `app/api/compras/pedidos/route.ts`: lookup de pedidos de compra em andamento, opcionalmente filtrado pelo fornecedor identificado no XML.
- `app/api/compras/_lib.ts`: utilitarios de autenticacao, tenant/empresa e permissoes usados pelas APIs de compras.
- `app/estoque/importar/[id]/page.tsx`: pagina de detalhe da nota importada, reutilizando `NfeDetail` com acesso de estoque.
- `app/faturamento/nfe/components/NfeDetail.tsx`: exibe documento fiscal, itens, impostos e titulos; quando nao ha itens em `f.documento_fiscal_item`, usa fallback em `public.nf_entrada_itens`.
- `app/estoque/importar/imprimir/page.tsx`: relatorio/impressao de notas importadas de materia-prima.
- `supabase/migrations/*import_nf_entrada*.sql` e `schema.sql`: definicoes historicas/atuais da RPC `public.import_nf_entrada` e funcoes auxiliares usadas pelo fluxo.

## Fluxo atual

1. Ao abrir `/estoque/importar`, a tela resolve `tenantId` e `empresaId`, carrega permissoes, parametros de importacao XML, motivos/classificacoes, usuarios solicitantes e notas recentes ja importadas.
2. O usuario escolhe um ou mais arquivos XML, ou cola XML no painel.
3. `handleFile` chama `parseXmlAndCheck`; para arquivo local, `addJobFromFile` usa `FileReader.readAsText`.
4. `addJobFromRaw` chama `parseXml`, que delega para `parseNfeXml`.
5. `parseNfeXml` usa `DOMParser` e monta `ParsedNfe` e `ParsedItem[]`.
6. A tela normaliza o codigo do item, removendo zeros a esquerda quando o codigo e numerico.
7. A tela consulta `public.nf_entrada` por `chave` dentro de `tenant_id`/`empresa_id` para marcar XML ja importado.
8. O lote exige um unico fornecedor: o CNPJ do emitente do primeiro XML vira a base; XMLs com CNPJ diferente entram como erro de lote.
9. `checkFornecedor` procura fornecedor em `public.fornecedores` por `cnpj_norm` ou `documento_norm`, sempre com escopo por tenant/empresa. Se nao existir e houver permissao, `criarFornecedor` cria o fornecedor.
10. A finalidade e o motivo podem ser preenchidos pelos defaults do fornecedor (`finalidade_padrao`, `motivo_compra_padrao_id`), ou escolhidos na tela.
11. A tela monta `itemMap` com `carregarItensPorCodigo`, consultando `public.itens.codigo_interno` no escopo tenant/empresa. Se a finalidade exige item cadastrado, itens faltantes bloqueiam importacao ate cadastro/vinculo.
12. O cadastro rapido de item (`criarItemRapido`) cria `public.itens` e tenta gravar `public.fiscal_itens`.
13. Se a finalidade for `materia_prima`, a tela habilita vinculo opcional com OS por numero ou busca em `public.ordens_servico`.
14. O usuario pode informar/buscar pedido de compra. `loadPedidoLookup` chama `/api/compras/pedidos` com tenant, empresa, status em andamento e, se houver, `fornecedorId`.
15. Ao importar, `importarNfe` valida permissao, solicitante, finalidade, motivo, OS e itens cadastrados. Depois monta `nfJson` e `itensPayload`.
16. `itensPayload` inclui `item_id`, codigo, descricao, NCM, CFOP, quantidade, valor unitario, impostos, aliquotas, creditos, custos, motivo textual e `realizado_por`.
17. A tela chama `POST /api/estoque/importar-xml` enviando `tenantId`, `empresaId`, finalidade, OS, pedido, motivo, solicitante, fornecedor, `nfJson`, `itensJson`, `xmlRaw`, flag de contas a pagar e parcelas.
18. A API valida autenticacao, `can('xml_import','execute')` e acesso a empresa.
19. A API resolve fornecedor novamente em `resolveFornecedorId`, por CNPJ/nome, com escopo tenant/empresa. Pode criar fornecedor se nao existir.
20. Se houver pedido, `bindImportItemsFromPedido` resolve `m.pedido_compra`, valida fornecedor do pedido contra fornecedor da NF e tenta correlacionar itens da NF com `m.pedido_compra_item`.
21. A correlacao de pedido usa item_id ja resolvido, codigo, descricao, valor unitario e quantidade. Itens manuais de pedido podem gerar item cadastrado via `ensureItemFromPedidoManual`.
22. A API valida motivo em `f.motivo_compra`, solicitante em `a.usuario`/empresa, itens obrigatorios e preflight de pedido/OS.
23. A API chama `public.import_nf_entrada` no contexto do usuario. A RPC grava `public.nf_entrada` e `public.nf_entrada_itens`.
24. A API atualiza/vincula OS em `public.nf_entrada` quando aplicavel, reconcilia `item_id` em `nf_entrada_itens` e garante movimentacoes de estoque.
25. O fluxo atual tambem garante titulo AP e parcelas por funcoes financeiras existentes, sincroniza classificacao/aprovacao do titulo, sincroniza impostos fiscais, baixa materiais em OS quando aplicavel e registra recebimento do pedido.
26. A resposta retorna `nf_entrada_id` e avisos nao bloqueantes, como divergencia entre total do pedido e total da NF.

## Dados usados do XML

Cabecalho NF-e:

- Chave de acesso: atributo `Id` de `infNFe`, removendo prefixo `NFe`.
- Numero: `ide > nNF`.
- Serie: `ide > serie`.
- Emitente/fornecedor: `emit > xNome`.
- CNPJ do emitente: `emit > CNPJ`.
- Data de emissao: `ide > dhEmi`.
- Totais: `total > ICMSTot > vProd`, `vFrete`, `vSeg`, `vDesc`, `vOutro`, `vNF`.

Destinatario, usado principalmente por fluxos compartilhados de NF-e:

- Nome: `dest > xNome`.
- Documento: `dest > CNPJ` ou `dest > CPF`.
- IE, email e endereco: `IE`, `email`, `enderDest/CEP`, `xLgr`, `nro`, `xCpl`, `xBairro`, `xMun`, `UF`, `xPais` ou `cPais`.

Itens:

- Codigo do produto: `det > prod > cProd`.
- Descricao: `det > prod > xProd`.
- Quantidade: `det > prod > qCom`.
- Valor unitario: `det > prod > vUnCom`.
- Valor do produto: `det > prod > vProd`.
- NCM: `det > prod > NCM`.
- CFOP: `det > prod > CFOP`.
- Frete/desconto/outros/seguro por item: `vFrete`, `vDesc`, `vOutro`, `vSeg`.
- Tributos por item: `ICMS > * > vICMS`, `IPI`, `PIS`, `COFINS`, `vICMSST` e aliquotas `pICMS`, `pIPI`, `pPIS`, `pCOFINS`.
- `uCom`/unidade comercial nao e extraida hoje pelo parser; o cadastro rapido grava `unidade_medida: "UN"`.

Pagamento:

- Duplicatas: `cobr > dup > nDup`, `dVenc`, `vDup`.
- Se nao houver duplicatas e o fornecedor estiver configurado para gerar contas a pagar, o fluxo atual pode gerar parcela unica ou usar configuracao manual do modal.

Contexto fiscal extraido no servidor:

- `CRT`, `idDest`, `UF` do emitente e `UF` do destinatario sao lidos de `xmlRaw` por helpers regex para fallback de credito em cenario Simples/SC.

## Consultas ao Supabase

Tela `app/estoque/importar/page.tsx`:

- `public.nf_entrada`: lista notas recentes; verifica duplicidade por `chave`; abre nota importada.
- RPC `f.fn_find_documento_fiscal_from_import` e `f.fn_ensure_documento_fiscal_from_nf_entrada`: localiza/cria documento fiscal a partir de `nf_entrada`.
- RPC `f.nfe_gravar_impostos_do_documento`: best-effort ao abrir detalhe.
- `/api/estoque/usuarios-solicitantes`: carrega usuarios solicitantes.
- `public.ordens_servico`: busca/resolucao de OS por `numero_os`, `cliente_nome`, `descricao_servico`, `status`.
- `/api/compras/pedidos`: busca pedidos em andamento.
- `public.fornecedores`: consulta/cria/atualiza fornecedor por `cnpj_norm` e `documento_norm`; campos usados incluem `id`, `nome`, `cnpj`, `documento`, `finalidade_padrao`, `motivo_compra_padrao_id`, `gerar_contas_pagar_auto`.
- RPC `public.set_fornecedor_import_defaults`: salva finalidade/motivo padrao do fornecedor.
- `public.itens`: busca por `codigo_interno`; cria itens com `codigo_interno`, `nome`, `tipo`, `controla_estoque`, `unidade_medida`, custos, fornecedor, finalidade, NCM e aliquotas.
- `public.fiscal_itens`: busca perfil fiscal por item e faz upsert de NCM/aliquotas/flags de credito.
- `public.parametro_importacao_xml`: le `itens_auto_cadastrar_finalidades` e `itens_vincular_finalidades`.

API `app/api/estoque/importar-xml/route.ts`:

- RPC `public.can`: valida `xml_import.execute`.
- `getAllowedEmpresas`: valida acesso a empresa.
- `a.usuario`: resolve usuario atual e valida solicitante.
- `public.fornecedores`: resolve, cria, atualiza nome e consolida duplicados.
- `m.pedido_compra`: resolve pedido por UUID ou codigo, valida status, atualiza status de recebimento.
- `m.pedido_compra_item`: busca itens do pedido, atualiza `item_id`, `quantidade_recebida` e calcula total de divergencia.
- `m.pedido_compra_item_origem`: recupera pendencias/origem de itens do pedido.
- `m.compra_pendencia`: recupera `origem_os_id` e conclui pendencias recebidas.
- `m.pedido_compra_recebimento` e `m.pedido_compra_recebimento_item`: registra recebimento do pedido vinculado ao documento da NF.
- RPC `m.fn_pedido_compra_log_evento`: loga evento de recebimento.
- `public.itens`: valida item cadastrado/ativo; cria item para item manual de pedido; reconcilia item por codigo/descricao.
- `f.motivo_compra`: valida classificacao/motivo ativo e aplicavel.
- RPC `public.import_nf_entrada`: grava a NF e itens de entrada.
- `public.nf_entrada`: atualiza OS/baixa, consulta resumo e vinculos.
- `public.nf_entrada_itens`: reconcilia `item_id`, monta fallback de pedido e monta vinculos diretos de OS.
- `public.movimentacoes`: cria/verifica entradas e saidas vinculadas a `origem_nf_entrada_id`.
- `public.estoque`: confere/aplica saldo apos movimentacao.
- RPC `public.fn_backfill_movimentacoes_nf_entrada`: fallback de sincronizacao de movimentacoes.
- RPC `public.fn_ensure_titulo_ap_from_nf_entrada`: garante titulo AP/parcelas.
- RPC `public.fn_sync_titulo_aprovacao_from_nf_entrada`: sincroniza motivo/aprovacao do AP.
- RPC `f.fn_find_documento_fiscal_from_import` e `f.nfe_sync_creditos_entrada_from_nf_itens`: localiza documento fiscal e sincroniza creditos/impostos.
- `public.os_itens` e `public.ordens_servico`: cria/atualiza itens de OS, baixa estoque, recalcula valor total da OS.

Principais tabelas/campos de destino:

- `public.nf_entrada`: `tenant_id`, `empresa_id`, `chave`, `numero`, `serie`, `emitente_nome`, `emitente_cnpj`, `data_emissao`, `valor_produtos`, `valor_frete`, `valor_seguro`, `valor_desconto`, `valor_outros`, `valor_total`, `xml_raw`, `fornecedor_id`, `finalidade_contexto`, `os_id`, `baixa_os_automatica`, `motivo_compra_id`, `solicitante_usuario_id`.
- `public.nf_entrada_itens`: `tenant_id`, `empresa_id`, `nf_entrada_id`, `item_id`, `codigo_fornecedor`, `descricao`, `ncm`, `cfop`, `qtd`, `v_unit`, `v_prod`, `v_icms`, `v_ipi`, `v_pis`, `v_cofins`, `aliq_icms`, `aliq_ipi`, `aliq_pis`, `aliq_cofins`.
- `public.fornecedores`: `tenant_id`, `empresa_id`, `nome`, `cnpj`, `documento`, `cnpj_norm`, `documento_norm`, `finalidade_padrao`, `motivo_compra_padrao_id`, `gerar_contas_pagar_auto`.
- `public.itens`: `tenant_id`, `empresa_id`, `codigo_interno`, `nome`, `unidade_medida`, `fornecedor_id`, `finalidade`, `ncm`, aliquotas e custos.
- `public.movimentacoes`: `tenant_id`, `empresa_id`, `item_id`, `tipo`, `quantidade`, `motivo`, `realizado_por`, `data_movimentacao`, custos, creditos, impostos, `origem_nf_entrada_id`, `origem_os_id`.
- `m.pedido_compra`: `id`, `codigo`, `status`, `fornecedor_id`, `solicitante_usuario_id`, `total_geral`, `tenant_id`, `empresa_id`.
- `m.pedido_compra_item`: `id`, `seq`, `item_id`, `item_codigo`, `item_nome`, `origem_os_id`, `quantidade`, `quantidade_recebida`, `valor_unitario`, `valor_total`.
- `f.motivo_compra`: `id`, `tenant_id`, `codigo`, `nome`, `requires_text`, `requires_os`, `aplica_em`, `ativo`, `deleted_at`.
- `f.documento_fiscal` e `f.documento_fiscal_xml`: documento fiscal derivado da NF importada e backup do XML.
- `f.titulo`, `f.titulo_parcela`, `f.titulo_aprovacao`: AP/parcelas/classificacao geradas pelo fluxo financeiro existente.

Mapa dos campos solicitados:

| Dado | Origem atual | Uso/destino |
| --- | --- | --- |
| fornecedor | `emit > xNome` | `fornecedores.nome`, `nf_entrada.emitente_nome`, `f.documento_fiscal.fornecedor_id` |
| CNPJ | `emit > CNPJ` | `fornecedores.cnpj/documento`, `cnpj_norm/documento_norm`, `nf_entrada.emitente_cnpj` |
| chave da NF-e | `infNFe @Id` | `nf_entrada.chave`, `f.documento_fiscal.chave_acesso`, `f.documento_fiscal_xml.chave_acesso`, `pedido_compra_recebimento.documento_ref` |
| numero/serie | `ide > nNF`, `ide > serie` | `nf_entrada.numero`, `nf_entrada.serie`, `f.documento_fiscal.numero`, `f.documento_fiscal.serie` |
| itens da nota | `det` | `ParsedItem[]`, `itensPayload`, `nf_entrada_itens` |
| codigo do produto | `prod > cProd` | lookup `itens.codigo_interno`, `nf_entrada_itens.codigo_fornecedor`, match com `pedido_compra_item.item_codigo` |
| descricao | `prod > xProd` | `nf_entrada_itens.descricao`, `itens.nome`, match com `pedido_compra_item.item_nome` |
| unidade | nao extraida hoje do XML | cadastro rapido usa `itens.unidade_medida = "UN"`; pedido usa `pedido_compra_item.unidade` |
| quantidade | `prod > qCom` | `qtd/quantidade`, `nf_entrada_itens.qtd`, `movimentacoes.quantidade`, `pedido_compra_recebimento_item.quantidade`, `os_itens.quantidade` |
| valor unitario | `prod > vUnCom`, ajustado por desconto quando aplicavel | `nf_entrada_itens.v_unit`, `movimentacoes.custo_unitario_*`, match com `pedido_compra_item.valor_unitario` |
| pedido de compra | digitado/buscado na tela | `pedidoCompraRef` enviado como `pedidoCompraId`; API resolve `m.pedido_compra.id` ou `codigo` |
| item do pedido | `m.pedido_compra_item` | correlacao com itens da NF; gera `pedidoRecebimentos` e `pedidoOsVinculos` |
| solicitante | tela ou `m.pedido_compra.solicitante_usuario_id` | `nf_entrada.solicitante_usuario_id`, aprovacao do AP |
| finalidade | tela, default do fornecedor ou inferida pelo pedido | `nf_entrada.finalidade_contexto`, `fornecedores.finalidade_padrao`, `itens.finalidade` |
| classificacao/motivo | `f.motivo_compra` via combobox/default/fallback de pedido | `nf_entrada.motivo_compra_id`, `fornecedores.motivo_compra_padrao_id`, `f.titulo.motivo_compra_id`, `f.titulo_aprovacao.motivo_compra_id` |

## Pontos onde o assistente de importação poderá entrar no futuro

- Analise automatica de fornecedor: depois de `parseNfeXml` e antes de `checkFornecedor`, usando `ParsedNfe.cnpjEmitente`, `emitente` e historico local de fornecedores. Deve ser somente sugestao, sem criar fornecedor automaticamente fora das regras atuais.
- Busca de pedidos abertos: apos fornecedor resolvido e antes de `loadPedidoLookup`/`bindImportItemsFromPedido`, sugerindo pedidos candidatos por fornecedor, status, data e total.
- Correlacao de itens: antes de montar `itensPayload`, comparando `ParsedItem[]`, catalogo `public.itens` e itens de pedido. O resultado pode preencher uma sugestao de `item_id`, mas a importacao deve continuar usando as validacoes existentes.
- Sugestao de cadastro de item: quando `loteMissing` aponta codigos faltantes, gerar um rascunho local com codigo, descricao, NCM, unidade sugerida, custos e fornecedor.
- Sugestao de vinculo com pedido: antes de `POST /api/estoque/importar-xml`, mostrar uma proposta de pedido/item/quantidade e exigir confirmacao.
- Explicacao das divergencias: a partir de `runStrictImportPreflight`, avisos de pedido vs NF e comparacao de totais, gerar mensagens estruturadas para o usuario.
- Ponto mais seguro tecnicamente: um motor local puro, sem efeitos colaterais, chamado pela tela antes da importacao e pela API em modo preflight. Ele deve produzir apenas `findings`, `suggestions` e `warnings`.

## Riscos encontrados

- `app/estoque/importar/page.tsx` e `app/api/estoque/importar-xml/route.ts` concentram muitas regras de negocio. Isso aumenta risco de regressao ao inserir assistente no meio do fluxo.
- Ha logicas duplicadas entre cliente, API e SQL: fornecedor, item cadastrado, duplicidade de NF, motivo/solicitante e vinculo de OS/pedido.
- A identificacao de item usa codigo normalizado e heuristicas por descricao/valor/quantidade. Isso e util, mas pode vincular errado se fornecedores reutilizarem codigos ou descricoes parecidas.
- A unidade comercial do XML nao e extraida pelo parser atual; novos itens sao criados com `UN`.
- O parametro enviado como `pedidoCompraId` pode ser UUID ou codigo do pedido. O nome e ambíguo para futuras integrações.
- Existem caminhos de auto-criacao/atualizacao de fornecedor no cliente e no servidor; o servidor tambem faz merge best-effort de duplicados por CNPJ.
- O fluxo possui muitos efeitos depois da RPC principal: movimentacao, estoque, AP, impostos, OS e recebimento do pedido. Se uma etapa posterior falhar, a NF pode ja estar persistida.
- Ha sinais de historico/schema drift em migrations e snapshots (`schema.sql`, migrations de backup e migrations recentes). Antes de mexer no fluxo, a versao real da RPC `public.import_nf_entrada` deve ser confirmada no banco alvo.
- O retorno de NF duplicada aparece com tratamentos diferentes em arquivos historicos/migrations (`ja_importada`, `error`, mensagem "NF ja importada"). Isso precisa ser estabilizado antes de automatizar sugestoes.
- O fallback fiscal para Simples/SC le parte do XML por regex no servidor, nao pelo parser DOM central.
- A pagina de detalhe depende de fallback em `public.nf_entrada_itens` quando `f.documento_fiscal_item` nao esta populada, indicando que o modelo fiscal e o modelo de estoque ainda nao estao totalmente unificados.

## Próxima etapa recomendada

Criar um motor local deterministico, sem IA e sem efeitos colaterais, por exemplo `lib/nfe/xmlImportAnalyzer.ts`.

Entrada sugerida:

- `ParsedNfe`
- `ParsedItem[]`
- fornecedor resolvido ou candidatos
- mapa de itens cadastrados
- pedidos candidatos e itens dos pedidos
- finalidade, motivo e solicitante selecionados

Saida sugerida:

- `findings`: problemas objetivos, como fornecedor ausente, item nao cadastrado, pedido divergente.
- `suggestions`: sugestoes de fornecedor, pedido, item, cadastro e OS.
- `warnings`: divergencias explicaveis, como total NF vs total pedido, unidade nao extraida, item sem NCM.

Menor passo tecnico: extrair somente as analises que hoje ja existem na tela (`fornecedor`, `itens faltantes`, `pedido candidato`, `totais`) para uma funcao pura e cobrir com testes unitarios. A tela continuaria chamando as mesmas APIs e a importacao continuaria bloqueada pelas validacoes atuais.

## Etapa 2 - Motor local de análise

- Arquivo criado: `lib/nfe/xmlImportAnalyzer.ts`.
- Função principal: `analyzeXmlImport(input: XmlImportAnalyzerInput): XmlImportAnalyzerResult`.
- Tipos principais: `XmlImportAnalyzerInput`, `XmlImportAnalyzerResult`, `XmlImportDiagnostic`, `XmlImportFornecedorSuggestion`, `XmlImportPedidoSuggestion`, `XmlImportItemSuggestion`, `XmlImportPedidoCandidato`, `XmlImportPedidoItem` e `XmlImportItemInterno`.
- O motor analisa fornecedor, campos obrigatórios, finalidade, motivo/classificação, solicitante, itens cadastrados por código normalizado, unidade comercial ausente, pedidos candidatos, divergências de valor/quantidade e consistência geral.
- O retorno é apenas estruturado: `status`, `score`, `findings`, `warnings`, `suggestions`, `fornecedorSuggestion`, `pedidoSuggestion` e `itemSuggestions`.
- O motor não chama OpenAI, não usa API externa, não chama Supabase, não faz `fetch`, não grava banco, não cria migration, não altera a RPC `public.import_nf_entrada` e não aplica sugestão automaticamente.
- A preparação para uma IA futura fica no contrato determinístico: a IA poderá consumir os mesmos `findings`, `warnings` e `suggestions`, ou explicar divergências, sem substituir as validações atuais e sem mudar o fluxo de importação.

## Etapa 3 - Painel local do assistente

- Integração: o painel foi adicionado em `app/estoque/importar/page.tsx`, logo abaixo do quadro de `Requisitos`, usando o componente `app/estoque/importar/XmlImportAssistantPanel.tsx`.
- Dados usados: NF-e e itens do `selectedJob`, fornecedor já resolvido na tela, `itemMap` já carregado, finalidade do lote, motivo/classificação selecionado, solicitante selecionado, pedidos candidatos mantidos a partir da busca já existente e parâmetros de importação XML já carregados.
- O painel chama somente `analyzeXmlImport` em `useMemo`; não chama IA/OpenAI, não usa API externa, não cria API key e não faz chamadas novas ao Supabase.
- O painel não altera regra de importação, bloqueio, validação, gravação, RPC ou API. O botão de importar continua usando somente as validações anteriores da tela e da API.
- O painel apenas exibe diagnóstico local: status, score, fornecedor, pedido sugerido quando houver dados suficientes, pendências, alertas, sugestões e análise por item.
- Limitação atual: a tela não carrega automaticamente todos os itens dos pedidos candidatos para o painel. Portanto, a sugestão de pedido depende dos dados já disponíveis na busca atual de pedidos ou do pedido selecionado a partir dessa busca, sem nova consulta nesta etapa.

## Etapa 4 - Pedidos candidatos com itens

- Endpoint criado: `app/api/compras/pedidos-candidatos-importacao/route.ts`.
- Finalidade do endpoint: leitura econômica de pedidos candidatos do fornecedor identificado, com itens do pedido, para melhorar somente o painel local do assistente.
- Entrada: `tenant_id`/`tenantId`, `empresa_id`/`empresaId`, `fornecedorId` e `limit` opcional.
- Dados retornados por pedido: `id`, `codigo`, `status`, `fornecedor_id`, `fornecedor_nome`, `solicitante_usuario_id`, `total_geral`, `total_pendente` e `itens`.
- Dados retornados por item: `id`, `seq`, `item_id`, `item_codigo`, `item_nome`, `descricao`, `quantidade`, `quantidade_recebida`, `valor_unitario`, `valor_total`, `origem_os_id`, `origem_os_numero` e `origem_os_label`.
- A tela busca automaticamente esses candidatos em `app/estoque/importar/page.tsx` quando há XML selecionado, tenant/empresa carregados, fornecedor resolvido e a tela não está lendo/importando.
- O `analyzeXmlImport` agora recebe primeiro os pedidos completos com itens. Se ainda não houver candidatos completos, mantém o fallback dos pedidos já disponíveis na busca manual.
- A integração não chama IA/OpenAI, não cria chave, não altera banco, não cria migration, não altera a RPC `public.import_nf_entrada`, não altera a API de importação e não muda o fluxo final de importação.
- O painel continua somente informativo: não vincula pedido, não aplica sugestão e não bloqueia o botão de importar.
- Limitações atuais: o endpoint filtra pedidos abertos nos status `ENVIADO` e `PARCIAL_RECEBIDO`, limita a quantidade de candidatos e não busca todos os históricos de recebimento ou divergências financeiras. A correlação continua sendo heurística local do analyzer.

## Etapa 5 - Ações assistidas sem IA

- O painel `app/estoque/importar/XmlImportAssistantPanel.tsx` passou a aceitar callbacks opcionais para preencher campos da tela com clique explícito do usuário.
- Botões adicionados quando há sugestão aplicável: `Usar finalidade sugerida`, `Usar motivo sugerido`, `Usar pedido sugerido` e `Usar solicitante do pedido`.
- Todos os botões apenas preenchem campos locais da tela: finalidade, motivo/classificação, pedido de compra ou solicitante.
- O painel não chama API, não importa XML, não vincula pedido automaticamente e não grava banco diretamente.
- Em `app/estoque/importar/page.tsx`, os callbacks conectados usam `setFinalidadeLote`, `setMotivoCompraId`, `setPedidoCompraRef` e `setSolicitanteUsuarioId`.
- Para finalidade e motivo, quando há fornecedor resolvido, o callback respeita o comportamento já existente da tela de salvar defaults do fornecedor; não foi criada persistência nova.
- A etapa não usa IA/OpenAI, não cria chave, não altera banco, não cria migration, não altera a RPC `public.import_nf_entrada`, não altera a API de importação e não muda o fluxo final de validação/importação.

## Etapa 6 - Refinamento operacional do assistente local

- O motor `lib/nfe/xmlImportAnalyzer.ts` teve mensagens ajustadas para linguagem mais operacional, voltada ao usuário da importação.
- As severidades foram mantidas com o seguinte critério: `error` para pendência obrigatória, `warning` para conferência antes de importar e `info` para orientação ou sugestão.
- O score geral foi ajustado para refletir fornecedor, finalidade, motivo, solicitante, itens cadastrados, pedido compatível e divergências. A leitura operacional é: `85 a 100` cenário bom, `65 a 84` atenção, abaixo de `65` revisar antes de importar.
- O score de pedido passou a exigir item compatível para virar sugestão forte; fornecedor sozinho não sugere pedido. Quando não há itens compatíveis, o painel mostra alerta de que nenhum pedido aberto teve itens claramente compatíveis com a NF.
- A mensagem de múltiplos pedidos foi refinada para indicar que a NF pode estar relacionada a mais de um pedido de compra.
- O painel `XmlImportAssistantPanel` passou a exibir um resumo curto do status: cenário consistente, pontos para conferência ou pendências obrigatórias.
- A etapa segue sem IA/OpenAI, sem chave, sem alteração de banco, sem migration, sem alteração da RPC `public.import_nf_entrada`, sem alteração da API de importação e sem mudança no fluxo final de importação.

## Etapa 7 - Diagnóstico copiável para teste

- O painel `app/estoque/importar/XmlImportAssistantPanel.tsx` recebeu o botão `Copiar diagnóstico`, exibido apenas quando a tela fornece o callback de cópia.
- A cópia é feita em `app/estoque/importar/page.tsx` e gera um JSON técnico para teste e suporte, sem chamar API e sem alterar o estado de importação.
- O JSON inclui status, score, `fornecedorSuggestion`, `pedidoSuggestion`, `findings`, `warnings`, `suggestions`, `itemSuggestions`, dados básicos do XML selecionado e um resumo dos campos atuais da tela.
- Dados básicos do XML selecionado: `fileName`, `chave`, `numero`, `serie`, `emitente`, `cnpjEmitente`, `valorTotal` e quantidade de itens.
- Campos da tela incluídos: `finalidadeLote`, `motivoCompraId`, indicador booleano de solicitante preenchido, `pedidoCompraRef`, fornecedor resolvido, quantidade de pedidos candidatos com itens, quantidade de itens em `itemMap` e `loteMissing`.
- O diagnóstico não inclui XML completo (`xmlText`/`xmlRaw`), token de sessão, dados de autenticação, API keys, conteúdo integral do XML, cartão ou dados de pagamento.
- A etapa segue sem IA/OpenAI, sem chave, sem alteração de banco, sem migration, sem alteração da RPC `public.import_nf_entrada`, sem alteração do endpoint de pedidos candidatos e sem mudança no fluxo final de importação.

## Etapa 8 - Correlação com itens manuais do pedido

- O analyzer `lib/nfe/xmlImportAnalyzer.ts` passou a reconhecer itens manuais de pedido, mesmo quando `m.pedido_compra_item` não possui `item_id` nem `item_codigo`.
- A comparação de itens manuais usa descrição aproximada normalizada, quantidade, valor unitário e presença de `origem_os_id` como sinal positivo.
- A normalização de descrição remove acentos, padroniza maiúsculas, trata abreviações como `TB` para `TUBO` e `RED.` para `RED`, normaliza medidas como `2,00MM`, `2.00MM` e `2MM`, remove pontuação irrelevante e ignora termos genéricos como `COM`, `DE`, `PVC`, `LASER` e `IMP`.
- A similaridade dá peso maior para material/liga/família/medidas, por exemplo `INOX`, `304`, `316`, `CHAPA`, `TUBO`, `BARRA`, `RED` e medidas numéricas.
- Quando um item da NF sem cadastro parece bater com item manual do pedido, o assistente sugere cadastrar o item e depois vincular/corrigir o item manual do pedido.
- Quando um item interno já existe e bate com item manual do pedido, o assistente sugere considerar o vínculo desse cadastro ao item manual do pedido.
- O painel mostra indicação de `Itens manuais no pedido` quando o pedido sugerido depende desses matches.
- A mensagem visual do requisito de itens foi ajustada para não mostrar `OK` quando ainda há itens faltantes; agora indica pendência de cadastro sem alterar a regra final.
- A etapa não cadastra item, não vincula pedido, não importa automaticamente, não altera banco, não cria migration, não altera RPC/API de importação e segue sem IA/OpenAI.

## Etapa 9 - Plano de ação recomendado

- O analyzer `lib/nfe/xmlImportAnalyzer.ts` passou a retornar `actionPlan`, uma lista ordenada de passos operacionais derivados do diagnóstico local.
- O plano pode sugerir preencher pedido, solicitante e OS, selecionar motivo/classificação, cadastrar itens faltantes, vincular/corrigir itens manuais do pedido e conferir divergências de valor ou quantidade.
- A OS sugerida é detectada pelos `origem_os_id` dos itens compatíveis do pedido; quando todos ou a maioria dos matches aponta para a mesma OS, o plano gera uma ação `APPLY_OS` com `payload.osId`.
- Correção operacional: o `payload.osId` continua usando o ID interno da OS, mas a mensagem do painel e o campo visível usam `origem_os_numero`/`origem_os_label` quando disponíveis, evitando mostrar o ID interno como se fosse o número da OS.
- O painel `app/estoque/importar/XmlImportAssistantPanel.tsx` exibe a seção `Plano de acao recomendado` acima de pendências/alertas/sugestões.
- Ações de preenchimento continuam exigindo clique explícito: `Usar pedido`, `Usar solicitante` e `Usar OS`.
- A tabela de itens analisados passou a mostrar `Acao recomendada` e, quando existir, a descrição do item manual correspondente no pedido.
- A etapa não usa IA/OpenAI, não cria chave, não cadastra item automaticamente, não vincula pedido automaticamente, não altera banco, não cria migration, não altera RPC/API de importação e não muda o fluxo final de importação.

## Etapa 10 - Vínculo de item manual do pedido

- Endpoint criado: `app/api/compras/pedido-itens/vincular-item/route.ts`, com `POST /api/compras/pedido-itens/vincular-item`.
- Payload esperado: `tenantId`, `empresaId`, `pedidoId`, `pedidoItemId` e `itemId`.
- O endpoint valida autenticação, tenant/empresa e permissão `compras.write`, busca o pedido e permite a correção somente em pedidos abertos usados no recebimento XML (`ENVIADO` e `PARCIAL_RECEBIDO`).
- A correção atualiza somente o vínculo do item manual do pedido: `item_id`, `item_codigo` e `item_nome`, usando o cadastro de `public.itens`.
- A correção não altera quantidade, quantidade recebida, valor unitário, valor total, origem OS, status do pedido, recebimentos, estoque ou NF.
- O painel `XmlImportAssistantPanel` mostra `Vincular ao pedido` quando um item da NF já cadastrado corresponde a um item manual do pedido.
- A tela `app/estoque/importar/page.tsx` abre um modal de confirmação com item da NF, cadastro interno, pedido sugerido e lista de itens manuais do pedido para escolha explícita.
- Na tabela principal de itens do XML, quando há pedido sugerido com itens manuais, a ação passa a ser `Vincular` em vez de `Cadastrar item`.
- A ação `Vincular` também aparece para item já cadastrado quando ainda existe item manual no pedido, permitindo correção manual/forçada do vínculo pelo usuário.
- Para item ainda não cadastrado, o mesmo modal permite `Cadastrar e vincular` com clique explícito: primeiro cria o item interno com os dados do XML e depois atualiza o item manual do pedido pelo endpoint de vínculo.
- Quando um item já cadastrado ainda bate com item manual do pedido sem vínculo, o analyzer gera pendência `error` e a tela bloqueia a importação até o usuário corrigir o vínculo.
- O analyzer faz uma segunda passada para itens cadastrados que ficaram sem match inicial, tentando correlacionar com itens manuais restantes do pedido por descrição, quantidade, valor e OS antes de liberar a importação.
- Ao confirmar, a tela chama o endpoint, atualiza localmente os pedidos candidatos com o item vinculado e deixa o analyzer recalcular as sugestões pelo estado atualizado.

## Etapa 11 - Bloqueio por divergência de pedido

- O analyzer passou a detalhar divergências de valor unitário com valor da NF, valor do pedido, diferença em reais e percentual.
- Quando há pedido sugerido, diferença de valor unitário maior ou igual a `15%` gera pendência `error` e bloqueia a importação até o pedido ser corrigido.
- Divergências de quantidade contra o saldo do pedido, tanto parcial quanto excesso, geram pendência `error` e bloqueiam a importação.
- As mensagens indicam o item, a quantidade da NF, o saldo do pedido, o restante ou excesso, para orientar a correção operacional do pedido.
- A tela usa essas pendências do analyzer apenas para bloquear a importação enquanto há divergência de pedido; não altera quantidade, valor, status, recebimento, estoque ou NF automaticamente.
- A etapa segue sem IA/OpenAI, sem chave, sem alteração de banco, sem migration, sem alteração da RPC `public.import_nf_entrada` e sem alteração da API final de importação.
- Ao usar pedido sugerido ou OS sugerida, a tela tenta preencher automaticamente a classificação/motivo usando os motivos já carregados, sem ID fixo e ignorando `NAO_CLASSIFICADO`.
- A etapa não usa IA/OpenAI, não cria chave, não cria migration, não altera RPC `public.import_nf_entrada`, não altera a API de importação e não muda o fluxo final de importação.

## Remodelagem da tela inicial de importação

- A tela inicial de `/estoque/importar` agora mostra apenas o título `Importar NF-e (XML)`, um bloco simples para selecionar/ler XML e o quadro `Notas importadas` no final.
- Finalidade, classificação/motivo, solicitante, pedido, OS, fornecedor, requisitos, assistente local, fila de XMLs, itens da NF e ações de importação só aparecem depois que existe XML lido/validado no estado da tela.
- A fila de XMLs só é renderizada quando há pelo menos um job. A tabela de itens só é renderizada quando há itens lidos, evitando tabelas e mensagens vazias no estado inicial.
- A NF-e já importada continua sendo detectada pela verificação de chave antes de liberar o formulário completo. Quando o job fica com status `importado`, a tela mostra o aviso de NF-e já importada, dados básicos da nota e mantém a ação de limpar/escolher outro XML.
- A mudança é somente visual e de organização do fluxo de tela. Não altera a regra final de importação, payload, endpoint de importação, endpoints de compras, banco, migrations ou a RPC `public.import_nf_entrada`.
- A remodelagem não usa IA/OpenAI, não cria API key e não depende de variável `OPENAI_API_KEY` ou `VITE_OPENAI_API_KEY`.
