# Comparação: DANFE do ERP (Focus) × DANFE do emissor antigo (VertexERP)

Feita em 05/09/2026 sobre a NF-e série 2 nº 1 (ERP, Focus) e a NF 3758 série 1
de 05/08/2026 (VertexERP), ambas para a Portobello. Serve para separar o que é
**dado nosso** (podemos mexer), o que é **decisão de conferência** (já existe
na tela) e o que é **do gerador de PDF da Focus** (só com DANFE próprio).

## Diferenças e onde cada uma se resolve

| Diferença observada | ERP (Focus) | Emissor antigo | Origem | Situação |
|---|---|---|---|---|
| Número da nota | `Nº 1`, `Série 2` | `Nº 000.003.758`, `Série 001` | formatação do PDF da Focus | **Focus**. Só muda com DANFE próprio (marco 01/10/2026). O XML está correto (`nNF 1`, `serie 2`). |
| Bloco DUPLICATAS | ausente | `001 · 01/10/2026 · 563,02` | o payload não enviava o grupo `cobr` | **Nosso, corrigido em 05/09.** A conferência confirma as parcelas (dias após a emissão + valor); a nota leva fatura e duplicatas e o contas a receber nasce com as mesmas parcelas. |
| Informações complementares com texto interno | `Composicao parcial da OV OV-SEG-00004-026` | só benefício e pedido | observação automática da composição indo ao infCpl | **Nosso, corrigido em 05/09.** Só observação escrita por pessoa vai para a nota. |
| Transportadora e volumes | "9 - Sem frete", sem volumes | TEDE Transportes, frete por conta do destinatário, 1 volume, 0,45 kg | escolha feita na conferência | **Conferência.** A tela já aceita modalidade 1 com transportadora, volumes e pesos; foi escolhida modalidade 9 nesta nota. |
| "Valor aproximado dos tributos: 117,58" | ausente | presente (Lei 12.741/2012) | tabela IBPT que o ERP não possui | **Pendente de definição.** Para venda a contribuinte (B2B) a informação é facultativa; para incluir corretamente é preciso a tabela IBPT por NCM. Pergunta ao contador. |
| CST do item | `200` (origem 2 + CST 00) | `220` (origem 2 + CST 20, base reduzida) | produto diferente | **Correto nos dois.** O relé 8536.50.90 tem redução de base (Anexo 2, art. 7º, VII); o PLC 8537.10.20 não tem. |
| IPI | 0 (CST 53) | 9,75% (R$ 50,02) | produto e TIPI | **Produto.** O PLC sai com IPI não tributado na revenda; o relé era tributado no antigo. Quando um item tributado entrar, o cadastro fiscal do item (CST IPI e alíquota) define. |
| Telefone do destinatário | ausente | `(48)3279-9222` | cadastro do cliente | **Cadastro.** Preencher o telefone da Portobello em Clientes; o payload já envia quando existe. |
| Bloco ISSQN, "0 - ENTRADA / 1 - SAÍDA", rodapé com nome do software | ausentes | presentes | leiaute do gerador | **Focus.** Não afeta o XML. |
| Logotipo | presente | ausente | anexado no painel da Focus | ok |
| Hora de saída | 11:45:32 | 14:58:11 | `dhSaiEnt` = hora da emissão | igual nos dois desenhos |

## O que muda na próxima nota real

1. Ao conferir, com "a prazo", aparece o bloco **Parcelas (duplicatas da NF-e)**: dias após a emissão e valor. Uma parcela com valor vazio usa o total. Várias parcelas precisam fechar com o total da nota.
2. A NF-e sai com `nFat` (código da OV), `vOrig`, `vLiq` e as duplicatas `001..n`, e o DANFE da Focus imprime o bloco de duplicatas.
3. O contas a receber nasce com uma parcela por duplicata, mesmo vencimento.
4. O XML do evento de cancelamento passa a ser arquivado no bucket (`cancelamento.xml`) quando uma nota real for cancelada.
5. O detalhe da nota mostra "Contas a Receber cancelado" quando o título foi cancelado junto com a nota.

## Verificação do ciclo financeiro e de estoque na NF-e 2/1

| Etapa | Contas a receber | Contas a pagar | Estoque |
|---|---|---|---|
| Item lançado na OV (02/09) | — | — | saída de 1 UN do item 3629 (movimento 12634) |
| NF-e autorizada (05/09 11:45) | 1 título AR de R$ 4.563,40, pendente, vencimento 20/09 | nenhum | nenhum movimento (correto: a baixa já ocorreu na OV) |
| NF-e cancelada (05/09 12:08) | título cancelado, R$ 0,00 em aberto, parcela zerada | nenhum | nenhum movimento; o item continua reservado na OV, que voltou a ter saldo para faturar |

O estoque só volta se o item for removido da OV, o que é a decisão comercial correta quando a venda não vai acontecer. A nota cancelada não devolve mercadoria por si.
