# Retorno de mercadoria de terceiros — NF-e pelo ERP

Construído em 16/09/2026 a pedido do Gabriel. Caso de referência: NF-e 900356/1 da WEG Tintas
(CFOP 5901, remessa para industrialização por encomenda, chave
42260660621141000404550010009003561304254706, XML em `docs/fiscal/exemplos/`). Haverá umas dez
notas iguais. Homologação do retorno: **NF-e 2/60** (chave
42260913671448000189550020000000601648220511, protocolo 342260000950332; a 2/59 saiu antes
do ajuste de natOp/infAdFisco/frete e ficou só como histórico); perfil liberado contra a 2/60,
produção da aba ligada e **nota real emitida em 16/09/2026: NF-e 2/20**, chave
42260913671448000189550020000000201907656978, protocolo 242260439667531 — remessa
RETORNADA, operação RETORNO CONCLUIDA, sem título financeiro.

**Segunda nota real, 18/09/2026, já com cEnq 109 e o modal em linguagem simples:** NF-e 908542/1 da
WEG (tintas para industrialização, 12 UN, R$ 867,72, chave 42260760621141000404550010009085421545851279,
XML em `docs/fiscal/exemplos/`), material aplicado → "Foi usado no produto" (5902). Perfil 5902
revisado pela tela às 06:40, homologação **NF-e 2/71** (protocolo 342260000953956) às 06:43,
liberação para essa solicitação (`0fc9a299-dc4d-4a27-a205-a7ca6ce7e581`) às 06:44 e **nota real NF-e
2/25** às 06:45, chave 42260913671448000189550020000000251536196350, protocolo 242260442413978. XML
conferido: CFOP 5902, cEnq 109, cBenef SC840008, ICMS 50/IPI 55/PIS-COFINS 08, IBS/CBS 410/410999,
refNFe = chave da 908542, item espelho, modFrete 0, 12 volumes 52,8 kg, tPag 90. Remessa RETORNADA,
operação RETORNO CONCLUIDA, zero títulos e zero movimentações de estoque ligados à nota. Prints de
cada passo, DANFE e XML em `docs/faturamento/retorno-terceiros-manual/`; **manual do operador**
(equipe de faturamento) em `docs/faturamento/manual-operador-retorno-terceiros.md` e
`Dropbox/Projeto_Estoque/Manual-Retorno-Remessa-Terceiros.docx` (revisado com as telas desta nota;
a versão de 16/09 fica no histórico do Dropbox).

Portão do banco: `f.fn_nfe_producao_preparar_e_claimar` compara o payload real com o da
homologação e, desde a migration 20260917120000, tolera `notas_referenciadas` (só a nota
real leva o NFref).

Referências do ERP antigo (Vertex) citadas pelo Gabriel em 16/09/2026 e ainda **não** no banco
nem no repositório: NF 3427/1 (23/09/2025, WEG, 5902, chave
42250913671448000189550010000034271000045843) e NF 3644/1 (07/05/2026, Krona, 5916, chave
42260513671448000189550010000036441000050862). Quando os XMLs entrarem em
`docs/fiscal/exemplos/`, comparar campo a campo com o montador.

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
   (0 padrão; 1/3/4/9 sem transportadora; volumes copiados da origem, senão qVol/espécie
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
| natOp | `RETORNO DE MERCADORIA UTILIZADA NA INDUSTRIALIZACAO` (o padrão pedido, "…POR ENCOMENDA", tem 65 caracteres e natOp aceita 60; a NF 3427 do Vertex usava "RETORNO DE MERCAD. UTILIZADA NA INDUST.") — conserto: `RETORNO DE MERCADORIA RECEBIDA PARA CONSERTO` |
| Destinatário | emitente da origem, do XML (CNPJ, IE, endereço), nunca do cadastro |
| NFref | `refNFe` = chave da origem (`notas_referenciadas` na Focus) — **só em produção**: a SEFAZ de homologação não conhece a chave de produção e recusou com cStat 267 (16/09/2026); em homologação a chave fica só no infCpl e a comparação produção × homologação ignora o grupo |
| Itens | espelho exato: cProd, xProd, NCM, uCom, qCom, vUnCom, vProd, mesma ordem; total = vProd, vNF = vProd |
| ICMS | CST 50, sem base/valor, orig da origem, cBenef **SC840008** (`CBENEF_RETORNO_SC`, não copia o da origem) |
| IPI | CST 55, sem valor, cEnq **109** (RIPI art. 43, VII; Anexo XIV da NT 2015.002). Até 18/09/2026 saía 108, que é o inciso VI (remessa); a NF-e 2/20 da WEG saiu com 108 e a correção por CC-e está com a contadora (rascunho abaixo) |
| PIS/COFINS | CST 08 |
| IBS/CBS | CST 410, cClassTrib 410999, sem gIBSCBS |
| Pagamento | tPag 90, vPag 0; sem cobr |
| Transporte | modFrete da tela (padrão **0**, como na NF 3427 do Vertex; 1/3/4/9), sem grupo transportadora; volumes da origem se existirem |
| infAdFisco | `ICMS SUSPENSO CONFORME ANEXO 2, ART. 27, II, DO RICMS-SC. RETORNO DA NF-E {nNF} DE {dd/mm/aaaa}. IPI SUSPENSO CONFORME ART. 43, VII, DO RIPI (DECRETO 7.212/2010).` (a frase do IPI acompanha o grupo IPI, que hoje sempre vai; conserto: "ART. 27" sem inciso até a NF 3644 do Vertex ser conferida) |
| infCpl | `RETORNO INTEGRAL DA MERCADORIA RECEBIDA PELA NF-E N. {nNF} SERIE {serie} DE {dd/mm/aaaa}, CHAVE {chave}. MERCADORIA DE TERCEIROS. SEM COBRANCA.` + observação |

Sem título financeiro (`fn_upsert_ar_from_nfe_venda` ignora tPag 90), sem estoque, fora de
receita e relatórios de venda. Na lista de NF-e (`/faturamento/nfe`) a nota aparece como
**Sem cobrança**, com "A pagar" zerado, e fica fora do faturado e do a receber: a lista lê
a forma de pagamento da solicitação pela emissão de produção (tPag 90) em vez de cair no
fallback "A pagar pelo valor da nota" (corrigido em 17/09/2026, quando a 2/20 e a 2/21
apareceram como a pagar).

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

## Decidido em 18/09/2026 (Gabriel)

- **cBenef SC840008 confirmado** (RICMS/SC, Anexo 2, art. 27, II) para o retorno 5902/5903.
- **cEnq do IPI do retorno = 109** (RIPI art. 43, VII; tabela do Anexo XIV da NT 2015.002). O 108
  é o art. 43, VI, da remessa 5901. Alterado por migration `20260918150000_retorno_terceiros_cenq_109.sql`
  em `f.fn_retorno_terceiros_config()`, na constante `RETORNO_REMESSA_TERCEIROS` (montador exige 109)
  e no perfil `SEG-RETORNO-TERCEIROS-5902-O0-CST50`, que **voltou para revisão** (produção
  desabilitada; o portão `fn_nfe_producao_pronta` só reabre com revisão, homologação posterior a ela
  e liberação). A remessa de conserto (`remessa-conserto.ts`, 5915/5916) continua com 108: pendente.
- **Importação de TESTE de homologação** (migration `20260918160000_retorno_terceiros_remessa_de_teste.sql`,
  mesmo dia): caixa "Teste de homologação" no importador da aba. Marcada, o XML de chave já
  importada entra em linha própria (`f.remessas_terceiros.is_teste`), sem tocar na remessa real: o
  índice único da chave vale só entre as reais (um teste por chave). O teste fica na seção "Testes de
  homologação" (fora de "em nosso poder", do prazo e de `v_remessas_abertas`), só gera retorno em
  homologação, a produção é recusada no banco (gatilho `aab_remessa_terceiros_teste_bloqueia_producao`
  em `f.documento_fiscal_emissao`, além da tela), o gatilho de baixa só carimba a homologação e
  "Excluir teste" (`f.fn_remessa_terceiros_teste_excluir`) cancela a solicitação e apaga a linha.
  Executado em 18/09/2026 com a NF-e 900356 da WEG: **homologação NF-e 2/69 autorizada** (cStat 100,
  protocolo 342260000953934) com CFOP 5902, cEnq **109**, cBenef SC840008, ICMS CST 50, IPI CST 55,
  infAdFisco com o art. 27, II e o art. 43, VII; a remessa real continuou RETORNADA.
- Liberação do perfil pelo fluxo normal: `fn_perfil_operacao_nfe_liberar_producao` não distingue
  teste. Como a 2/69 saiu **antes** da nova revisão do perfil (a migration 150000 zerou a revisão), a
  ordem é: revisar o perfil na tela de perfis → na seção Testes, "Gerar retorno" de novo (nova
  homologação, posterior à revisão) → "Liberar perfil" na linha do teste. A liberação vale para a
  solicitação do teste (produção bloqueada); cada remessa real seguinte tem a sua homologação e
  liberação, como sempre.

### Rascunho de CC-e da NF-e 2/20 (não enviada; decisão da contadora)

NF-e 2/20, chave 42260913671448000189550020000000201907656978, emitida em 16/09/2026 para WEG
Tintas. Texto proposto (xCorrecao):

`CORRECAO DO CODIGO DE ENQUADRAMENTO LEGAL DO IPI (cEnq) DO ITEM 1 - MATERIAIS PARA PINTURA, NCM 32099019, CFOP 5902: ONDE SE LE cEnq 108, LEIA-SE cEnq 109 (SUSPENSAO DO IPI NO RETORNO DE MERCADORIA RECEBIDA PARA INDUSTRIALIZACAO POR ENCOMENDA - RIPI, DECRETO 7.212/2010, ART. 43, VII). CST DO IPI 55, VALORES, QUANTIDADES, DATAS E DEMAIS DADOS DO ITEM E DA NOTA PERMANECEM INALTERADOS.`

A CC-e não altera valor, quantidade, data nem partes (Ajuste SINIEF 07/05, cláusula 14-A, § 1º-A);
só o campo de enquadramento. Envio, se aprovado, pelo ciclo de vida da NF-e (evento CARTA_CORRECAO).

## Modal em linguagem simples e perfil 5903 (18/09/2026, migration `20260918170000`)

Princípio (vale para o ERP): código fiscal nunca aparece sozinho — opção em linguagem simples,
exemplo curto e o código pequeno ao lado; a pessoa escolhe a situação e o sistema deriva o código.

- **Modal "Gerar retorno"**: no lugar do seletor de CFOP, a pergunta "O que aconteceu com o material do
  cliente?" com três opções: **Foi usado no produto** (Ex.: tinta aplicada, peça montada. O material
  volta dentro do produto. · CFOP 5902), **Voltou sem usar** (Ex.: lata fechada, sobra devolvida como
  veio. · CFOP 5903) e **Parte usada, parte devolvida** (desabilitada: "Ainda não disponível. Fale com o
  responsável fiscal."). Fora de SC o mesmo desenho deriva 6902/6903 e, sem perfil para o CFOP, a opção
  fica desabilitada com a mesma legenda. Conserto mantém as duas opções de sempre (5916/5903) no
  mesmo padrão de legenda. Rótulo e legenda vêm de `f.perfil_operacao.rotulo_usuario` /
  `legenda_usuario` (preenchidos no 5902 e no 5903).
- **Banco deriva o CFOP**: `fn_remessa_terceiros_retorno_criar(p_remessa_id, p_cfop, p_modalidade_frete,
  p_observacao, p_volumes, p_situacao)` — `USADO` → 5902, `NAO_USADO` → 5903, conserto `CONSERTADO` →
  5916; `PARCIAL` é recusado no banco ("Retorno parcial ... ainda nao esta disponivel"), não só na
  tela. `p_cfop` continua aceito para chamadas antigas. A situação fica em `operacao_fiscal.dados_json`
  e em `operacao_snapshot.retorno_terceiros`.
- **Perfil `SEG-RETORNO-TERCEIROS-5903-O0-CST50`**: cópia do 5902 com CFOP 5903, mesma tributação
  (ICMS 50/SC840008, IPI 55/109, PIS/COFINS 08, IBS/CBS 410/410999), evidência própria, produção
  desabilitada até revisão e liberação do Gabriel. natOp `RETORNO DE MERCADORIA P/ INDUSTRIALIZACAO NAO
  APLICADA` (o texto completo pedido tem 88 caracteres e o leiaute aceita 60); infCpl do 5903:
  `RETORNO DA MERCADORIA RECEBIDA PARA INDUSTRIALIZACAO PELA NF-E N. {nNF} SERIE {serie} DE {data}, CHAVE
  {chave}, NAO APLICADA NO REFERIDO PROCESSO: O MATERIAL VOLTA SEM TER SIDO UTILIZADO, COMO FOI RECEBIDO.
  MERCADORIA DE TERCEIROS. SEM COBRANCA.` (montador, `natOpRetornoTerceiros`/`textoRetornoTerceiros`).
- **Produção desligada**: a linha mostra "Emissão real desligada para esta aba. Peça a um
  administrador para ligar." no lugar do botão que sumia; só ADMIN vê o botão de ligar.
- **Conferência antes de liberar** (`app/faturamento/perfis/ConferenciaRetornoTerceiros.tsx`): na tela de
  liberar perfil, quando a solicitação é de retorno de terceiros, um quadro "Confira se o que está
  voltando é igual ao que o cliente mandou" compara remessa × retorno homologado (produto, NCM,
  quantidade, unidade, valor unitário, valor total, chave referenciada); igual em cinza, divergência em
  vermelho; casas decimais não contam; nada bloqueia.

## Pendências

- Retorno de **conserto** (5916): cBenef (SC840008 ou SC840007, Art. 27, I) e cEnq — com a contadora.
- Perfil 5902: revisado e liberado em 18/09/2026 para a NF-e 2/71/2/25. Cada remessa nova continua
  exigindo homologar e liberar de novo (liberação por solicitação). Perfil 5903 existe, mas sem
  revisão: revisar no primeiro caso real de "Voltou sem usar". 5916 ainda não tem perfil.
- CC-e da NF-e 2/20 (cEnq 108 → 109): rascunho acima, decisão da contadora, sem urgência.
- A remessa de TESTE da WEG 900356 foi excluída em 18/09/2026 depois da nota real (a homologação
  2/70 do 5903 ficou cancelada); para novo teste, importar de novo com a caixa marcada.
