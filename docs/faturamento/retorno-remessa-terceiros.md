# Retorno de mercadoria de terceiros — NF-e pelo ERP

Construído em 16/09/2026 a pedido do Gabriel. Caso de referência: NF-e 900356/1 da WEG Tintas
(CFOP 5901, remessa para industrialização por encomenda, chave
42260660621141000404550010009003561304254706, XML em `docs/fiscal/exemplos/`). Haverá umas dez
notas iguais.

## O problema

Peças de terceiros chegam para a Segau industrializar (5901/6901) ou consertar (5915/6915) e
depois voltam. Elas **não são nossas**: não entram no estoque, não são compra, não geram
financeiro nem receita. O que precisa existir é o controle de "mercadoria de terceiros em nosso
poder" e a NF-e de **retorno** (5902/5903 ou 5916), que é o espelho da nota recebida.

Não é devolução: finNFe 1, sem CFOP 5201/5202 e sem o fluxo DEVOLUCAO.

## Onde

Faturamento › Operações fora do faturamento (`/faturamento/operacoes`), aba **RETORNO DE
TERCEIROS** (`?aba=RETORNO`). A importação de compras (`/estoque/importar`) recusa XML cujos
itens sejam todos 5901/6901/5915/6915 e aponta para cá.

1. **Importar remessa recebida (XML)** — vários arquivos de uma vez. O banco valida
   (`f.fn_remessa_terceiros_importar`): nfeProc com cStat 100, destinatário = empresa ativa,
   todos os CFOPs em 5901/6901/5915/6915, chave inédita. Grava cabeçalho, remetente (CNPJ, IE,
   endereço), transporte (modFrete, volumes) e os itens como vieram (`f.remessas_terceiros`,
   `f.remessas_terceiros_itens`). Prazo de retorno = emissão + 180 dias.
2. **Mercadorias de terceiros em nosso poder** — chave, remetente, nº/série, emissão, dias,
   prazo (verde < 150 dias, amarelo 150–180, vermelho vencido), valor, CFOP, status, NF-e de
   retorno. Filtro por status (padrão ABERTA). Badge "homologada em dd/mm/aaaa".
3. **Gerar NF-e de retorno** (modal) — remetente e itens só leitura; CFOP (5902/5903 na
   industrialização, 5916/5903 no conserto; 6xxx fora da UF do remetente), modalidade do frete
   (9 padrão; 0/1/3/4 sem transportadora; volumes copiados da origem, senão qVol/espécie
   opcionais), observação. "Emitir em homologação" cria a solicitação
   (`f.fn_remessa_terceiros_retorno_criar`) e chama `nfe-emitir`. Enquanto a remessa estiver
   ABERTA pode gerar de novo: o retorno anterior sem produção é cancelado.

Depois: liberar o perfil na tela de perfis (como na remessa) e "Emitir NF-e real (produção)"
(`nfe-emitir-producao`) — só aparece com a **produção ligada**, que nasce desligada
(`f.retorno_terceiros_config`) e só o ADMIN da empresa liga, pelo botão da aba.

Autorizada em **produção**: remessa RETORNADA (`nfe_retorno_id`, `cfop_retorno`,
`retornada_em`), operação RETORNO CONCLUIDA em "Operações recentes". Cancelamento da nota de
produção: remessa volta a ABERTA. Homologação só grava `homologada_em`/`nfe_homologacao_id`.

## A nota de retorno

| Campo | Valor |
| --- | --- |
| finNFe / tpNF / indFinal / indPres | 1 / 1 / 0 / 9; idDest pela UF do destinatário |
| natOp | `RETORNO MERCADORIA RECEBIDA P/ INDUSTRIALIZACAO P/ ENCOMENDA` (60 caracteres; o texto pedido tinha 66) — conserto: `RETORNO DE MERCADORIA RECEBIDA PARA CONSERTO` |
| Destinatário | emitente da origem, do XML (CNPJ, IE, endereço), nunca do cadastro |
| NFref | `refNFe` = chave da origem (`notas_referenciadas` na Focus) |
| Itens | espelho exato: cProd, xProd, NCM, uCom, qCom, vUnCom, vProd, mesma ordem; total = vProd, vNF = vProd |
| ICMS | CST 50, sem base/valor, orig da origem, cBenef **SC840008** (`CBENEF_RETORNO_SC`, não copia o da origem) |
| IPI | CST 55, sem valor, cEnq **108** |
| PIS/COFINS | CST 08 |
| IBS/CBS | CST 410, cClassTrib 410999, sem gIBSCBS |
| Pagamento | tPag 90, vPag 0; sem cobr |
| Transporte | modFrete da tela, sem grupo transportadora; volumes da origem se existirem |
| infAdFisco | `ICMS SUSPENSO CONFORME ART. 27, II, ANEXO 2 DO RICMS/SC. IPI SUSPENSO CONFORME ART. 43, VII, DO RIPI (DECRETO 7.212/2010).` |
| infCpl | `RETORNO INTEGRAL DA MERCADORIA RECEBIDA PELA NF-E N. {nNF} SERIE {serie} DE {dd/mm/aaaa}, CHAVE {chave}. MERCADORIA DE TERCEIROS. SEM COBRANCA.` + observação |

Sem título financeiro (`fn_upsert_ar_from_nfe_venda` ignora tPag 90), sem estoque, fora de
receita e relatórios de venda.

## Onde está no código

| Camada | Arquivo |
| --- | --- |
| Constantes e textos | `supabase/functions/_shared/fiscal/retorno-remessa-terceiros.ts` |
| Naturezas / IBS-CBS 2026 | `tributacao-provisoria.ts`, `fiscal/ibs-cbs-transicao-2026.ts` |
| Montador | `supabase/functions/_shared/nfe-payload.ts` (`retornoTerceiros`) |
| Banco | `supabase/migrations/20260917100000_retorno_remessa_terceiros.sql` |
| Tela | `app/faturamento/operacoes/RetornoTerceirosPanel.tsx`, aba em `OperacoesFiscaisClient.tsx` |
| Parser (prévia) | `lib/nfe/parseNfeXml.ts` (IE/endereço do emitente, CSTs por item, transp, cStat) |
| Bloqueio na compra | `app/estoque/importar/page.tsx` (`addJobFromRaw`) |
| Testes | `supabase/tests/remessa_terceiros_retorno.sql`, `scripts/test-nfe-pipeline.mjs` |

## Pendências

- Confirmar com a contadora: cBenef SC840008 (constante em `f.fn_retorno_terceiros_config()` e
  em `RETORNO_REMESSA_TERCEIROS`) e cEnq 108 do IPI; e se o retorno de **conserto** (5916)
  usa o mesmo cBenef ou o SC840007 (Art. 27, I).
- Produção da aba nasce desligada; o perfil `SEG-RETORNO-TERCEIROS-5902-O0-CST50` precisa da
  revisão IBS/CBS e da liberação contra a homologação, como na remessa. Retorno 5903 e 5916
  ainda não têm perfil (produção vai exigir um).
