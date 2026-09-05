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
