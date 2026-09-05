# Faturamento parcial por item

Resultado em 02/09/2026: a composição parcial por linha foi implementada para OS e OV. Uma solicitação em `RASCUNHO` já reserva a quantidade; somente `CANCELADA` a devolve. A tela cria o rascunho e não emite nota.

## Estrutura entregue

A migration `20260901151000_faturamento_parcial_por_item.sql` acrescenta:

- `f.fn_os_itens_saldo_a_faturar(uuid, uuid, integer)`, com total, reservado/faturado e saldo por `public.os_itens.id`;
- índice `idx_solicitacao_item_origem_tipo_item` em `f.solicitacao_item (origem_tipo, origem_item_id)`;
- `f.fn_solicitacao_faturamento_criar_parcial(...)`, que valida saldo e cria somente `f.solicitacao_faturamento` e `f.solicitacao_item` em `RASCUNHO`;
- nova assinatura de `f.fn_faturar_documento_impl` e do invólucro público, aceitando `p_itens_quantidades jsonb`;
- compatibilidade para chamadas sem quantidade: cada linha usa o saldo atual, nunca a quantidade original integral;
- recálculo da quantidade, desconto proporcional e valor total em `f.documento_fiscal_item`.

O saldo é calculado exclusivamente por `f.solicitacao_item`, sem juntar por tentativas de emissão. Contam como reserva todos os estados diferentes de `CANCELADA`, inclusive `RASCUNHO`, `PREVIA`, `APROVADA` e `EMITIDA`. O vínculo textual é comparado de forma segura por `si.origem_item_id = oi.id::text`, sem converter texto potencialmente inválido para inteiro.

Linhas com `finalidade = 'venda'` podem ser selecionadas. Linhas com finalidade nula continuam aparecendo no retorno e na tela, em um bloco separado, mas são recusadas até serem classificadas.

## Concorrência

Foi escolhido `pg_advisory_xact_lock` com uma chave formada por tenant, empresa e ID da OS/OV. O lock é adquirido dentro da mesma transação que recalcula o saldo e grava a reserva.

Essa opção serializa todas as composições da mesma origem, mesmo quando dois usuários escolhem subconjuntos diferentes de linhas. Um `FOR UPDATE` apenas nas linhas escolhidas exigiria ordem rígida de locks e não protegeria, sozinho, mudanças no conjunto de linhas. OS/OV diferentes continuam sendo processadas em paralelo.

O helper de composição é usado tanto pela tela quanto pelo pipeline completo, portanto os dois caminhos obedecem ao mesmo lock e à mesma conta de saldo.

## Rejeição e erro de emissão

O comportamento atual foi mantido nesta tarefa:

- a solicitação passa a `APROVADA` antes do envio;
- `f.fn_nfe_registrar_envio` altera a tentativa de emissão, mas não a solicitação;
- `f.fn_nfe_aplicar_retorno` passa a solicitação para `EMITIDA` somente em `AUTORIZADA`;
- em `REJEITADA` ou `ERRO`, a solicitação permanece `APROVADA` e a quantidade continua reservada.

Não houve liberação automática porque `ERRO` pode ser transitório e `REJEITADA` normalmente exige correção e reenvio da mesma composição. A correção proposta, ainda não implementada por depender de decisão operacional, é oferecer duas ações explícitas: **corrigir e reenviar**, mantendo a reserva, ou **cancelar solicitação**, permitido apenas sem autorização e liberando o saldo. A escolha precisa gerar evento append-only.

## Tela

O componente compartilhado `FaturamentoParcialPanel` foi incluído na página da OS e da OV:

- mostra total, reservado/faturado e saldo por item;
- mantém linhas com saldo zero visíveis como `Faturado`;
- mostra legado sem finalidade separadamente;
- abre a composição com o saldo pré-preenchido por linha;
- bloqueia zero, valor negativo e quantidade acima do saldo com mensagem dentro do modal;
- mostra o total monetário da solicitação;
- confirma apenas a criação do rascunho e informa expressamente que nenhuma nota foi emitida.

Na OS, a ação antiga que apenas alterava o status foi renomeada para `Marcar OS faturada`, evitando confusão com a nova composição por item.

Durante o teste autenticado, o schema `a` também foi incluído entre os schemas expostos pelo Supabase local. Sem isso, o login local era aceito, mas o ERP não conseguia consultar `a.usuario` e ficava sem empresa ativa.

## Diagnóstico de produção

Leitura realizada em 02/09/2026, sem alteração de dados:

| Verificação | Itens | OS/OV |
| --- | ---: | ---: |
| `os_itens` com finalidade nula em origem que já possui documento fiscal de saída emitido | 1.907 | 54 |
| Mesmo `os_item` presente em mais de uma solicitação | 0 | 0 |
| Soma reservada/faturada acima da quantidade do pedido | 0 | 0 |

O problema de duplicidade e excesso era possível pela modelagem anterior, mas não foi encontrado nos dados atuais. O legado sem finalidade não foi corrigido.

## Validações

- `npx supabase db reset --local`: passou do zero com todas as migrations.
- `supabase/tests/faturamento_parcial_por_item.sql`: passou com 5 de 10, limite restante de 5, recusa de 11, cancelamento devolvendo 10, fallback para o saldo e emissão de 4 de 10 com total recalculado para R$ 96,00.
- concorrência real em duas sessões: ambas pediram 6 de uma linha de 10; uma criou o rascunho e a outra recebeu `disponível: 4`. Resultado final: uma reserva ativa de 6 e saldo 4.
- `supabase/tests/faturamento_nfe_pipeline.sql`: passou, inclusive idempotência e retorno autorizado.
- `supabase/tests/faturamento_rls_authenticated.sql`: passou; 6/6 tabelas respeitaram a empresa atual e ocultaram a outra.
- teste funcional autenticado no navegador local: OV carregou 10 total, 6 reservados e 4 de saldo; o modal abriu pré-preenchido com 4 e total de R$ 40,00; 5 foi bloqueado com mensagem visível; a confirmação criou `RASCUNHO`, exibiu o sucesso e atualizou para 10 reservados e saldo zero. A página da OS também exibiu o painel, a ação e o progresso, sem erro no console.
- ESLint nos quatro arquivos TypeScript alterados: passou sem erro ou aviso.
- `npx tsc --noEmit`: passou.
- `npx supabase db lint --local`: nenhum achado novo nas funções desta tarefa; permanecem os 10 erros preexistentes do baseline, fora do escopo.
- `git diff --check`: passou; somente avisos de conversão futura LF/CRLF em arquivos já modificados.

Nenhum CFOP, CST, CSOSN, benefício ou perfil de operação foi semeado. A migration foi aplicada em produção em 02/09/2026, após backup físico e dry-run; `migration repair` não foi executado.
