# Devolução de compra ao fornecedor (NF-e finNFe 4)

Entregue em 17/09/2026. Primeiro caso: 41,55 kg do tubo 401014 (item 2 da NF-e 121481/3 da
Aços America, chave 42260808819200000182550030001214811001242895) voltam ao fornecedor.
Orientação da contadora, no papel: **CFOP 5201, saída tributada com o CST da origem (00), IPI
fora da base do ICMS como na nota de origem, transporte com 1 volume e 41,55 kg**.

## Onde

`/faturamento/operacoes?aba=DEVOLUCAO` (Faturamento › Operações fora do faturamento › aba
DEVOLUCAO). Três cartões: **1 · Nota de entrada de origem** (busca por número, fornecedor ou
chave entre as notas importadas com XML), **2 · Itens a devolver** (quantidade por item, CFOP,
frete, volumes, transportadora opcional, observação) e **3 · Devoluções** (homologação,
liberação do perfil, produção, DANFE/XML, ciclo de vida, situação do estoque).

## Passo a passo

1. **Perfil** (uma vez): revisar `SEG-DEVOLUCAO-COMPRA-5201-O0-CST00` em Faturamento › Perfis
   fiscais com IBS/CBS 000 / 000001, 0,1% / 0% / 0,9% (a revisão desabilita a produção).
2. **Nota de referência de homologação** (uma vez, e de novo só se ela for cancelada): emitir em
   homologação uma remessa para conserto (aba REMESSA PARA CONSERTO) com a **própria empresa
   como destinatária** (cliente "ELETRICA SEGAU LTDA. EPP.", id 39). Hoje é a NF-e 2/64 de
   homologação, chave 42260913671448000189550020000000641164283751. Ver "Por que" abaixo.
3. **Buscar a entrada**: número da NF, fornecedor ou chave → "Ler XML e devolver". O banco lê o
   XML (`f.fn_devolucao_compra_preparar`) e a tela mostra o emitente (destinatário da devolução,
   do XML) e os itens com CST e alíquotas.
4. **Quantidades**: por item, a quantidade a devolver (nunca acima da nota, e a soma das
   devoluções de cada linha nunca passa do XML). CFOP 5201 dentro de SC (6201 fora), 5553/6556
   para ativo imobilizado ou uso e consumo. Frete: modalidade (padrão 0), volumes com peso
   (obrigatório quando há transporte), transportadora opcional.
5. **"Gerar devolução e emitir em homologação"**: `f.fn_devolucao_compra_nfe_criar` valida contra
   o XML (`fn_devolucao_compra_criar`), monta a operação `DEVOLUCAO_COMPRA` e a solicitação, e a
   Edge `nfe-emitir` manda para a Focus. Gerar de novo abandona o rascunho anterior pelo fluxo
   auditado.
6. **Liberar perfil para produção** (link na linha) → tela de perfis com a solicitação
   preenchida → justificativa + confirmação → "Conferir e liberar para esta homologação" → volta
   para a aba.
7. **"Emitir NF-e real (produção)"** → confirmação com destinatário, origem e valor →
   `nfe-emitir-producao`. Autorizada, a operação fica CONCLUÍDA e a mercadoria sai do estoque.

## A nota

| Campo | Valor |
| --- | --- |
| finNFe / tpNF / indFinal / indPres | 4 / 1 / 0 / 9; idDest pela UF do fornecedor |
| natOp | `DEVOLUCAO DE COMPRA PARA INDUSTRIALIZACAO` |
| Destinatário | emitente da NF-e de entrada, do XML (nunca do cadastro) |
| Referência | **por item**, grupo `DFeReferenciado` (chaveAcesso + nItem de origem), NT 2025.002-RTC, obrigatório desde 01/09/2026. **Sem** `NFref` no cabeçalho: com os dois a SEFAZ recusa (rejeição 1010) |
| Itens | espelho proporcional da linha de origem: cProd, xProd, NCM, unidade, vUnCom iguais; qCom = devolvida |
| ICMS | CST e alíquota do XML (00 a 12%); base = vProd, **IPI fora da base** (destinação nula no montador) |
| IPI | CST e alíquota do XML (50, cEnq 999, 3,25%); soma no vNF |
| PIS/COFINS | CST e alíquotas do XML (01, 1,65% / 7,6%), base = vProd − ICMS |
| IBS/CBS | 000 / 000001, 0,1% / 0% / 0,9% (`ibs-cbs-transicao-2026.ts`) |
| Pagamento | tPag 90, vPag 0; sem cobr; sem título |
| Transporte | modalidade da tela (0 a 4, 9), volumes da tela, transportadora opcional |
| infAdFisco | `DEVOLUCAO DE COMPRA REFERENTE A NF-E {nNF} DE {dd/mm/aaaa}. ICMS, IPI, PIS E COFINS DESTACADOS PROPORCIONALMENTE CONFORME A NOTA DE ORIGEM.` |
| infCpl | `DEVOLUCAO PARCIAL DA MERCADORIA RECEBIDA PELA NF-E N. {nNF} SERIE {serie} DE {data}, CHAVE {chave}. ITEM {n} ({cProd}): {qtd} {un} DE {qtd original} {un}. SEM COBRANCA.` + observação |

Primeiro caso (NF-e 2/65 de homologação, 17/09/2026): vProd 303,32 · ICMS 36,40 · IPI 9,86 ·
PIS 4,40 · COFINS 20,29 · vNF 313,18.

## Por que a homologação é diferente da nota real

A SEFAZ de homologação não conhece a nota do fornecedor. Com finNFe 4 ela exige uma referência
que exista na base dela **e cujo emitente seja o destinatário da devolução** (regras VC02-14 e
VC02-50 da NT 2025.002-RTC). Foi o que os testes de 17/09/2026 mostraram:

| Tentativa em homologação | SEFAZ |
| --- | --- |
| finNFe 4, NFref com a chave real de entrada | 321 "não possui documento fiscal referenciado" |
| finNFe 4, NFref com a origem como nota modelo 1 (refNF) | 321 |
| finNFe 4, NFref com a NF-e 2/63 de homologação (venda da Segau a outro cliente) | 321 |
| finNFe 1, CFOP 5201 | 328 "CFOP de devolução para NF-e que não é de devolução" |
| finNFe 4, NFref + DFeReferenciado com a NF-e 2/64 (Segau → Segau), destinatário Segau | 1010 "referenciamento a nível de nota e a nível de item" |
| finNFe 4, só DFeReferenciado com a 2/64, destinatário Segau | **AUTORIZADA (2/65)** |

Então a nota de teste sai com a **própria empresa como destinatária** e referencia, item a item,
a **NF-e de homologação da empresa para ela mesma** (`devolucao_compra.chave_referencia_homologacao`
e `referencia_homologacao_nitem` no snapshot, escolhidas por `fn_devolucao_compra_nfe_criar`:
última NF-e AUTORIZADA em homologação cujo cliente tem o CNPJ da empresa). A nota real leva o
fornecedor e a chave de entrada com o nItem de origem de cada item.

A comparação produção × homologação (`f.fn_nfe_payload_comparavel`, usada por
`fn_nfe_producao_preparar_e_claimar`, e `validarPayloadProducaoContraHomologacao` no montador)
tira, **só nesta natureza**, os campos do destinatário, `local_destino`, `notas_referenciadas` e
o `DFeReferenciado` dos itens. Itens, impostos, totais, transporte e pagamento continuam
congelados. Limite conhecido: fornecedor de outro estado (6201) sairia em homologação com
destinatário em SC; o CFOP interestadual pode ser recusado na nota de teste.

## Estoque e financeiro

- Autorização em **produção** dá baixa no estoque: uma movimentação de saída por item ligado à
  linha da entrada (`nf_entrada_itens.item_id`), motivo `Devolucao de compra NF-e {s}/{n} ao
  fornecedor ... [DEVOLUCAO {id}]`, gravada em `operacao_fiscal.dados_json.estoque_movimentacoes`.
- Sem saldo suficiente a nota **não** é barrada (a SEFAZ já autorizou): a linha fica em
  `dados_json.estoque_pendencias` e a tela mostra "estoque pendente" na devolução. É o caso do
  tubo 401014 (saldo 0 em 17/09: tudo já baixado em OS).
- Cancelamento da nota real (ciclo de vida) estorna a saída (entrada de igual quantidade) e
  cancela a operação (gatilhos `trg_devolucao_compra_apos_emissao` e
  `trg_operacao_fiscal_apos_cancelamento`).
- Sem título financeiro (tPag 90) e fora do faturado: a lista de NF-e mostra "Sem cobrança".

## Onde está no código

- `supabase/migrations/20260917190000_devolucao_compra_nfe.sql` — `f.fn_devolucao_compra_nfe_criar`,
  gatilho de estoque, perfil `SEG-DEVOLUCAO-COMPRA-5201-O0-CST00` e evidência; `..._200000`
  (gerar de novo pelo fluxo auditado), `..._220000` e `..._230000` (referência própria,
  DFeReferenciado, `f.fn_nfe_payload_comparavel`).
- `supabase/functions/_shared/fiscal/devolucao-compra.ts` — constantes, textos, DFeReferenciado
  por item, destinatário de teste; `nfe-payload.ts` (ramo `devolucaoCompra`);
  `tributacao-provisoria.ts` e `fiscal/ibs-cbs-transicao-2026.ts` (natureza `DEVOLUCAO_COMPRA`).
- `app/faturamento/operacoes/DevolucaoCompraPanel.tsx` (aba DEVOLUCAO).
- Testes: `supabase/tests/devolucao_compra_nfe.sql` (XML de exemplo em
  `docs/fiscal/exemplos/42260808819200000182550030001214811001242895.xml`) e
  `scripts/test-nfe-pipeline.mjs`.
- Diagnóstico: `nfe-ciclo` ação `CONSULTAR` devolve a resposta da Focus para uma emissão.

## Pendências

- Contadora: confirmar CST/cEnq do IPI na devolução (a nota espelha o XML: CST 50 cEnq 999) e o
  texto do infAdFisco; se preferir CST 49, é só o snapshot (`fn_devolucao_compra_nfe_criar`).
- Fornecedor de outro estado: primeira devolução 6201 precisa de perfil `INTERESTADUAL` e de
  conferir a nota de teste (ver limite acima).
- Cadastro: manter a própria empresa como cliente (id 39) com indicador de IE 1 para a nota
  de referência de homologação.
