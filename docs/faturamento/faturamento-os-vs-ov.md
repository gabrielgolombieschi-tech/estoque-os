# Faturamento de OS separado do faturamento de OV

Resultado em 02/09/2026: OV continua faturando as linhas do pedido com saldo por quantidade; OS passou a compor linhas livres com saldo informativo por valor. Uma OS não consulta `public.os_itens` nem `os_itens.finalidade` para faturar.

## Decisão do modo

O discriminador real é `public.ordens_servico.tipo_documento`:

- `OS`: ordem de serviço; faturamento por linhas livres;
- `OV`: ordem de venda; faturamento por linhas de `public.os_itens`.

A coluna é `text NOT NULL DEFAULT 'OS'` e a constraint `ordens_servico_tipo_documento_check` aceita somente `OS` e `OV`. A tela não infere o modo pela descrição, pelos itens ou pelo status.

| Regra | OV | OS |
| --- | --- | --- |
| Origem | `public.os_itens` | linha digitada no faturamento |
| Descrição | cadastro do produto, fixa | livre e editável |
| Controle | quantidade por `os_item_id` | valor do orçamento/HH |
| `os_itens.finalidade` | obrigatória e igual a `venda` | não consultada |
| `solicitacao_item.origem_item_id` | ID de `os_itens`, como texto | nulo |
| Produto cadastrado | obrigatório | opcional na composição |
| Excesso | bloqueado por quantidade | avisado por valor, sem bloqueio |

## Banco

A migration `20260901152000_faturamento_os_linhas_livres.sql` entrega:

- `f.fn_solicitacao_faturamento_criar_os_livre(...)`: valida a OS e as linhas, usa lock por tenant/empresa/OS e cria somente um `RASCUNHO`;
- `f.fn_os_saldo_a_faturar(...)`: retorna `valor_pedido`, `valor_faturado`, `valor_reservado`, `saldo` e `usa_relatorio_hh`;
- `f.fn_faturar_documento(...)`: decide pelo `tipo_documento`; OV usa os itens e quantidades do pedido, OS exige `p_linhas_livres`;
- `f.fn_faturamento_buscar_itens(...)`: busca opcional, limitada ao tenant e empresa e protegida pela permissão financeira;
- `public.add_ov_item_baixa_imediata(...)`: usa a baixa de estoque existente e grava `finalidade='venda'` na mesma transação;
- contexto de emissão compatível com linha de OS sem `os_item` e sem `item_id`.

O nome público `fn_solicitacao_faturamento_criar_parcial` foi preservado para compatibilidade, mas agora aceita somente OV. A implementação por `os_itens` ficou privada. Uma chamada dessa RPC com OS falha indicando o caminho de linhas livres.

O nome histórico `fn_os_saldo_a_faturar` continua aceitando OS e OV porque já era consumido pelas telas de venda e importação. Na OS ele alimenta o controle informativo por valor; na OV serve apenas aos cartões-resumo. O bloqueio da OV permanece exclusivamente no saldo de cada `os_item_id`.

### Reserva por valor

Para OS:

```text
saldo = valor do pedido/HH - valor autorizado - valor reservado em aberto
```

`RASCUNHO`, `PREVIA` e `APROVADA` reservam. `EMITIDA` deixa de ser reserva porque o documento autorizado entra em `valor_faturado`; `CANCELADA` não reserva. A conta usa `quantidade × valor_unitario` de `f.solicitacao_item` com `origem_tipo='OS'`, sempre com tenant, empresa e ID da OS.

Valor acima do saldo gera aviso na tela, não exceção no banco. Isso é intencional para aditivo e medição a maior. Na OV, quantidade acima do saldo continua bloqueada.

Quando o pedido/HH vale zero, a função devolve a conta numérica, mas a tela mostra **Sem teto cadastrado** e não calcula excesso.

### Linhas da OV × orçamento (18/09/2026)

Pedido do Gabriel depois da OV-SEG-00004-026 nascer com o preço do cadastro (1.650,00) em vez
do preço do orçamento (4.563,40). Migration `20260918240000_ov_divergencia_orcamento_no_rascunho.sql`.

**Preço sugerido ao incluir a linha.** A tela da venda lê o orçamento de origem
(`m.orcamento.os_id = OV`, itens em `m.orcamento_item`). Ao escolher um item no localizador, o
campo "Valor unitário" (antes rotulado "Custo unitário") vem com `valor_unitario_liquido` do
orçamento, que já traz o acréscimo da condição de pagamento; a legenda diz
**Preço do orçamento SEG-xxx-026**. Item que não está no orçamento vem com o preço de tabela do
cadastro e a legenda **Preço de tabela (item fora do orçamento)**. O valor continua editável.

**Aviso na OV.** No cabeçalho da venda, quando `sum(os_itens.valor_total)` difere de
`ordens_servico.orcado`: "As linhas somam R$ X, o orçamento fechado é R$ Y. Confira antes de
faturar." A OV não trava: itens, compras e histórico seguem normais.

**Rascunho da NF-e.** `f.fn_solicitacao_faturamento_criar_parcial` ganhou o parâmetro
`p_divergencia_motivo text default null`. Com `orcado` cadastrado (> 0) e linhas que não somam o
orçado, a função recusa (`22023`) sem um motivo de 15 caracteres ou mais (máximo 500) e a
mensagem repete os dois valores. Com o motivo, o rascunho nasce e
`f.solicitacao_faturamento.divergencia_orcamento` guarda `soma_linhas`, `orcado`, `motivo`,
`confirmado_por` (auth.uid()) e `confirmado_em`. OV sem `orcado` (nulo ou zero) não é comparada,
como o "Sem teto cadastrado" da OS. O painel de faturar mostra o mesmo aviso dentro do modal, com
o campo "Motivo da diferença", e só habilita "Salvar rascunho da NF-e" com o motivo preenchido.

A assinatura antiga de 6 parâmetros foi removida (wrapper e impl) para o PostgREST não ficar
ambíguo; a chamada sem o 7º parâmetro continua válida pelo default.

OVs abertas em 18/09/2026 com essa divergência (não corrigidas): OV-SEG-00010-026 (4.585,00 ×
2.401,40), 00009 (4.821,00 × 3.272,91; o orçamento SEG-426-026 fecha 5.588,12), 00008 (2.209,98
× 1.421,28), 00006 (300,95 × 273,29), 00005 (1.665,00 × 1.214,34), 00002 (2.219,88 × 1.145,56) e
00001 (2.121,79 × 0, sem linhas). Todas vão pedir o motivo na hora do rascunho.

**Orçado que inclui IPI (só relato, 18/09/2026).** Na OV-SEG-00004-026 o orçado (4.563,40) é o
total da OC com o IPI, e a linha é a mercadoria (4.158,00): o aviso dispara e o motivo gravado foi
"Orçado inclui IPI". Para o aviso somar o IPI previsto quando o item é equiparado a industrial,
sem mudar o orçado: (1) na tela, `somaLinhas` passaria a somar, por linha, `valor_total × alíquota
de IPI do cadastro fiscal / 100` quando `fiscal_itens.equiparado_industrial` e CST IPI 50/99
(mesma leitura que o Faturar OS já faz em `ipiLinhas`, com o arredondamento por item do montador),
e o texto diria "As linhas somam R$ 4.158,00 + IPI previsto R$ 405,41 = R$ 4.563,41"; (2) no banco,
`fn_solicitacao_faturamento_criar_ov_impl` faria a mesma soma com `left join public.fiscal_itens`
antes de comparar com o orçado; (3) a diferença de meio centavo continuaria aparecendo (4.563,41 ×
4.563,40) até o ajuste de meio centavo ser ligado, então a comparação deveria tolerar R$ 0,01 por
linha equiparada, ou considerar a marca `arredondar_empate_para_baixo` quando já houver rascunho.
Não implementado.

Testes: `supabase/tests/faturamento_parcial_por_item.sql` (bloco "Linhas x orcado": sem motivo
recusa, motivo curto recusa, com motivo grava, OV que fecha não registra);
`faturamento_os_vs_ov.sql` e `nfe_excecao_icms_12_destinatario.sql` tiveram o `orcado` das
OVs de fixture igualado às linhas.

### Produto opcional e emissão fiscal

A linha livre pode ficar sem `item_id`; isso cobre composição e aprovação de descrições como mão de obra, start-up e ajuste de escopo. Nesse caso, o documento interno mantém a descrição, quantidade, unidade e valor e usa um código operacional da linha.

Uma NF-e modelo 55 ainda precisa de classificação fiscal do produto. Antes do envio à Focus, uma linha sem produto fiscal vinculado é recusada com mensagem explícita para vincular o produto. Nenhum NCM, CFOP, CST, CSOSN, benefício ou perfil foi inventado nesta tarefa.

## Tela

`FaturamentoParcialPanel` agora despacha para dois modos:

- OV mantém a grade anterior, saldo por item, descrição fixa e quantidade pré-preenchida com o saldo;
- OS mostra orçamento/HH, faturado, reservado e saldo; a primeira linha sugere `ordens_servico.descricao_servico`, mas permanece editável; novas linhas são livres;
- a busca de produto é opcional e preenche código vinculado, descrição, unidade e preço, sem bloquear posterior edição da descrição;
- confirmar cria somente a solicitação em `RASCUNHO` e informa que nenhuma nota foi emitida.

## Diagnóstico de produção

Leitura realizada em 02/09/2026, sem escrita, limitada ao tenant do ERP e às duas empresas ativas. A produção mudou desde a medição anterior: o universo citado como 1.907 passou a **1.908** linhas.

| Diagnóstico | Resultado |
| --- | ---: |
| `os_itens.finalidade IS NULL` em origem com saída emitida — OS | **1.906 linhas em 52 OS** |
| Mesmo recorte — OV | **2 linhas em 2 OV** |
| Total atual do recorte | **1.908 linhas em 54 OS/OV** |
| Linhas de OV criadas nulas nos últimos 30 dias | **2 linhas em 2 OV** |
| OS existentes | **316** |
| OS com `orcado` nulo | **0** |
| OS com `orcado` zero | **93** |
| OS efetivamente sem teto após considerar total de HH | **29** |
| Dessas, não canceladas | **22** |

Conclusão: **99,9% da dívida de finalidade desse recorte pertence a OS e deixou de bloquear faturamento**. A dívida real da OV é de duas linhas.

### Escrita de finalidade na OV

Antes desta correção, a inclusão em `app/comercial/vendas/[id]/VendaDetalheClient.tsx` chamava `public.add_os_item_baixa_imediata`. Essa função insere `public.os_itens` sem a coluna `finalidade`, portanto o valor nascia nulo. Não existe edição direta de linha nessa tela; a operação disponível é remover e incluir novamente.

Agora a tela chama `public.add_ov_item_baixa_imediata`, definida na migration desta tarefa. Ela reaproveita todas as validações e movimentações da RPC existente e, na mesma transação, atualiza somente a linha recém-criada para `finalidade='venda'`. Nenhuma linha histórica foi corrigida automaticamente.

## Validações

- `npx supabase db reset --local`: passou do zero, incluindo a migration `152000`.
- `supabase/tests/faturamento_os_vs_ov.sql`: passou; três rascunhos da mesma OS preservaram três descrições, apenas uma linha teve produto, todas ficaram com `origem_item_id` nulo, e R$ 750,00 ficaram reservados sobre R$ 1.000,00.
- o mesmo teste aceitou aditivo até R$ 1.250,00 e devolveu saldo de -R$ 250,00, sem bloqueio.
- o pipeline completo criou uma linha de `START-UP` de R$ 650,00 sem `item_id`, preservou o contexto sem `os_item` e reservou o valor.
- a RPC pública de OV foi exercitada como `authenticated` e criou a linha com `finalidade='venda'`.
- a leitura-resumo histórica da tela de OV continuou funcionando e contabilizou R$ 80,00 reservados, sem transformar esse resumo em bloqueio por valor.
- `supabase/tests/faturamento_parcial_por_item.sql`: passou sem alteração dos cenários da OV.
- `supabase/tests/faturamento_nfe_pipeline.sql`: passou, inclusive idempotência e autorização.
- teste funcional autenticado em `http://localhost:3000/os/915300`: a descrição sugerida apareceu editável; a busca encontrou `KIT-UI`; duas linhas totalizaram R$ 1.050,00; o aviso de R$ 50,00 apareceu sem bloquear; o rascunho foi criado e o cabeçalho atualizou para reservado R$ 1.050,00 e saldo -R$ 50,00.
- o banco confirmou as duas linhas funcionais: ambas `origem_tipo='OS'`, `origem_id='915300'`, `origem_item_id IS NULL`; somente a linha escolhida na busca recebeu `item_id`.
- console do navegador: nenhum erro ou aviso.
- `supabase/tests/faturamento_rls_authenticated.sql`: passou; as seis tabelas testadas mostraram apenas a empresa ativa e ocultaram a outra empresa.
- `/financeiro/gestao-cobranca`: respondeu HTTP 200 após as migrations e os testes.
- ESLint nos arquivos TypeScript alterados: passou sem erro ou aviso.
- `npx tsc --noEmit`: passou.
- `npx supabase db lint --local`: não apontou erro na migration nova; repetiu os 10 erros preexistentes do baseline, além dos avisos já conhecidos.
- `git diff --check`: passou; somente avisos de conversão LF/CRLF em arquivos preexistentes no worktree.

A migration foi aplicada em produção em 02/09/2026, após backup físico e dry-run; `migration repair` não foi executado. Nenhum perfil fiscal foi habilitado ou semeado.
