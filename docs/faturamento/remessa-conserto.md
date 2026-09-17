# Remessa para conserto (garantia) — NF-e pelo ERP

Primeira emissão em 16/09/2026: duas cortinas de luz SICK enviadas para análise em garantia
(SICK SOLUCAO EM SENSORES LTDA, São Bernardo do Campo/SP). Homologação NF-e 2/58, produção
NF-e 2/19 (chave 42260913671448000189550020000000191919938263) — **cancelada em 17/09/2026**:
a SICK avisou que o item 1 estava errado (era a C4C-SA12030A10000, cód. 1211501, da NF
347.442/002 da SICK de 03/03/2026, e não a C4C-SA15010A10000). Refeita em 17/09 com
1211501 (R$ 2.196,49) + 1211502 (R$ 2.563,60) = R$ 4.760,09: homologação 2/61 e produção
**NF-e 2/21**, chave 42260913671448000189550020000000211604881603. O cancelamento da nota de
produção encerra a operação e o controle de retorno (migration 20260917150000).

## Onde

Faturamento › NF-e › "Exceções e rotinas mensais" não; é **Faturamento › Operações fora do
faturamento** (`/faturamento/operacoes`), aba **Remessa para conserto**.

## Passo a passo

1. **Cliente** (Cadastros › Clientes): o destinatário precisa existir como cliente com o
   cadastro fiscal completo (`/clientes/cadastro-fiscal`): razão social, CNPJ, indicador de
   IE, IE, endereço com código IBGE. A busca de município aceita nome sem acento.
2. **Item** (Cadastros › Itens › Novo): o assistente de cadastro cria o item pelo fornecedor e
   código; confira a descrição, o preço sugerido (o assistente sugeriu R$ 21.332,18 para a
   1211482; o valor certo, da NF da SICK, é R$ 3.393,07) e, na aba Fiscal, NCM e origem.
3. **Perfil** (Faturamento › Perfis fiscais): revisar o perfil `SEG-REMESSA-CONSERTO-6915-O2-CST50`
   com IBS/CBS CST 410, cClassTrib 410999, alíquotas 0 (uma vez; a revisão desabilita a produção).
4. **Prazo**: aba "Outras remessas", finalidade CONSERTO, 180 dias (RICMS/SC-01, Anexo 2, Art. 27, I).
5. **Remessa**: buscar o cliente, os itens (valor = última compra), transporte (modalidade,
   transportadora, volume com peso), observação opcional → "Criar remessa e preparar a NF-e".
6. **Homologação**: "Emitir em homologação". A SEFAZ responde pelo callback.
7. **Liberação**: "Liberar perfil para produção" abre a tela de perfis com a solicitação
   preenchida; justificativa + confirmação → "Conferir e liberar para esta homologação".
8. **Produção**: "Emitir NF-e real (produção)" → confirmação → autorizada. A remessa passa a
   "Remessas em aberto" com a chave, a data e os dias decorridos; "Criar retorno" quando voltar.
   Na lista de NF-e (`/faturamento/nfe`) a remessa aparece como **Sem cobrança** (tPag 90,
   sem título), fora do faturado e do a receber.

## Tributação (Status Contabilidade, docs/faturamento/regras-icms-sc-contabilidade.md)

| Tributo | Na nota | Base legal |
| --- | --- | --- |
| ICMS | CST 50, cBenef SC840007, sem base | RICMS/SC-01, Anexo 2, Art. 27, I (retorno em 180 dias) |
| IPI | CST 55, cEnq 108, sem valor | RIPI/10 (Decreto 7.212/10), art. 43, VI |
| PIS/COFINS | CST 08 | operação sem incidência |
| IBS/CBS | CST 410, cClassTrib 410999, sem gIBSCBS | não incidência (não é fornecimento oneroso) |
| Pagamento | tPag 90, vPag 0 | remessa não cobra |
| CFOP | 6915 fora de SC, 5915 dentro | natOp "REMESSA PARA CONSERTO FORA/DENTRO DO ESTADO" |

Informações complementares: "ICMS suspenso, conforme o inciso I do art. 27 do Anexo 2 do
Decreto nº 2.870/01 - RICMS-SC/01 (cBenef SC840007) | IPI suspenso, conforme o inciso VI do
art. 43 do Decreto nº 7.212/10 - RIPI/10 | Mercadoria remetida para conserto ou análise em
garantia, com retorno ao estabelecimento de origem no prazo de 180 dias".

Decisões a confirmar com o contador: IPI 55 (suspensão) em vez de 53 (a NF 3539 do emissor
antigo citava RIPI art. 5º, XI); cEnq 108; cClassTrib 410999 (é o que as remessas 5901 da WEG
e o retorno 6916 da Keyence trazem em 2026).

## O que a SEFAZ ensinou na homologação

cStat 1021 "Grupo IBS/CBS informado indevidamente": com CST 410 nenhuma alíquota pode ir no
item, nem zerada, porque a Focus monta o gIBSCBS a partir delas. O item vai só com CST e
cClassTrib, e os portões de produção deixam de comparar alíquotas quando o CST é 410
(migration 20260916180000).

## Onde está no código

| Camada | Arquivo |
| --- | --- |
| Regra e textos | `supabase/functions/_shared/fiscal/remessa-conserto.ts` |
| Naturezas / IBS-CBS 2026 | `tributacao-provisoria.ts`, `fiscal/ibs-cbs-transicao-2026.ts` |
| Montador | `supabase/functions/_shared/nfe-payload.ts` (remessaConserto) |
| Banco | migrations 20260916160000 (remessa), 20260916170000 (busca de itens), 20260916180000 (portões 410) |
| Tela | `app/faturamento/operacoes/RemessaConsertoPanel.tsx` |
| Testes | `scripts/test-nfe-pipeline.mjs`, `supabase/tests/remessa_conserto_nfe.sql` |

## Pendências

- Estoque: a remessa não movimenta estoque; as cortinas continuam no saldo até decisão.
- Retorno (5916/6916): o botão "Criar retorno" cria a operação de retorno, mas ela ainda usa o
  caminho antigo (chave digitada); emitir o retorno pelo pipeline é o próximo passo.
- Perfil de remessa só para origem 2; item de origem 0/1 precisa de perfil próprio.
