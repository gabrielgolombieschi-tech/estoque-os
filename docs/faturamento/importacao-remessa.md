# Importação por remessa expressa (NF-e de entrada, tpNF 0)

Entregue em 17/09/2026. Primeiro caso: remessa UPS 1ZJ451C10441551106 (DIR 260191366846,
registrada em 09/09/2026, UA 0817700 Viracopos/SP), uma CPU de CLP OMRON CQM1H-CPU61
(US$ 45,00 + frete US$ 41,12 a 5,0856) no regime de tributação simplificada (RTS, regime 7):
II de 60% recolhido pelo courier (R$ 262,78), ICMS por GNRE (receita 10005-6, R$ 143,53), sem
IPI, PIS e COFINS. Destino confirmado pelo Gabriel: bancada própria, CFOP 3556. Homologação
**NF-e 2/67** (a 2/66, em 3101 e com o ICMS na base do IBS/CBS, foi cancelada). **Nota real:
NF-e 2/24, autorizada em 17/09/2026 20:26** (chave 42260913671448000189550020000000241890455952,
protocolo 242260441882906, lidos do XML autorizado). Resultado: entrada de 1 UN no item 3629 a
R$ 995,22 (movimentação 13351, crédito de ICMS zero, cadastro fiscal do item intocado) e título AP
da nota de débito UPS 2953830 (R$ 557,25, vencimento 10/09/2026) **APROVADO**, sem baixa: foi paga
pelo cartão pessoal do sócio (ver "Despesas pagas pelo sócio"). DANFE e XML (real e homologação) em
`docs/importacao/1ZJ451C10441551106/`.

**Ajuste de 18/09/2026, só para as próximas notas (a 2/24 não muda):** IPI de entrada CST **02**
(entrada isenta) com cEnq **319**, PIS/COFINS CST **71** (aquisição com isenção), tpViaTransp padrão
**11** (courier), e a importação de **teste** (homologação com a DIR já usada). Os quatro perfis
voltaram para revisão: antes da próxima nota real, revisar o perfil do CFOP, homologar e liberar.
Homologação de teste com a mesma DIR em 18/09/2026: ver "Teste de homologação de 18/09/2026".

## Onde

`/faturamento/operacoes?aba=IMPORTACAO`. Cinco passos: **1 · DIR** (upload do XML do Siscomex
Remessa, raiz `xml1702`), **2 · Dados da nota** (exportador, mercadorias com item do catálogo,
NCM e fabricante, CFOP, alíquota, GNRE, desembaraço, despesas e nota de débito do courier,
anexos), **3 · Cálculo e conferência**, **4 · Prévia da NF-e** com o botão de emitir em
homologação, **5 · Importações** (homologação, liberação do perfil, produção, DANFE/XML,
anexos, estoque e contas a pagar, cancelar).

## Regras

- **Bloqueios da DIR** (banco e tela): destinatário ≠ CNPJ da empresa; situação ≠ 25; II
  pendente; XML que não é DIR; **DIR já usada** (uma DIR gera uma nota; "gerar de novo" cancela a
  anterior pelo fluxo auditado, só sem nota real).
- **Conta**: vProd = valor aduaneiro (valor tributável da DIR: mercadoria + frete); II da DIR;
  BC ICMS = (vProd + II) ÷ (1 − alíquota); ICMS = BC × alíquota, **conferido com a GNRE
  (diferença acima de R$ 0,05 bloqueia)**; vOutro = ICMS; vNF = vProd + II + vOutro. Com mais de
  uma mercadoria o rateio é pelo valor em dólar e o ICMS é calculado item a item (o total pode
  andar centavos em relação à GNRE, dentro da tolerância).
- **Nota**: tpNF 0, idDest 3, finNFe 1, indFinal 0 (3101/3102) ou 1 (3556/3551), indPres 9;
  destinatário = exportador no exterior (sem CNPJ/IE, idEstrangeiro opcional, município 9999999
  EXTERIOR, UF EX, país BACEN); item origem 1, CST 00 modBC 3 (base por dentro), grupo II
  (vBC = vProd, vDespAdu 0, vIOF 0), grupo DI (nDI, dDI = dDesemb = registro, local/UF pela UA,
  tpViaTransp da tela, tpIntermedio 1, cExportador, uma adição por item com cFabricante),
  IPI **02/319** (entrada isenta; cEnq 319 = remessas sujeitas ao RTS), PIS/COFINS **71**
  (aquisição com isenção), IBS/CBS 000/000001 sobre **valor aduaneiro + II** (base do II
  acrescida dos tributos do caput, sem o ICMS e sem o IPI: LC 214/2025, art. 69, caput e §§ 1º e
  2º; 0,1% / 0% / 0,9% em 2026; nesta nota 700,75, IBS 0,70 e CBS 6,31), modFrete 9, tPag 90,
  infAdFisco e infCpl com AWB, DIR, GNRE, nota de débito, remetente da DIR e exportador da invoice.
  Os CSTs de IPI e PIS/COFINS dos itens vêm do **perfil do CFOP** (não são literais do código).
  tpViaTransp padrão 11 (courier), trocável na tela.
- **Teste de homologação** (caixa no passo 1): a importação nasce com `teste = true`, convive com a
  DIR já usada (fora do índice único e do "em uso"), só emite em homologação, não oferece produção
  e, se uma nota real chegasse, não geraria estoque nem contas a pagar. Serve para re-homologar um
  perfil alterado sem tocar na importação real; a homologação autorizada vale como evidência para
  liberar o perfil.
- **Trava de destino**: CFOP 3101/3102 (industrialização/revenda) é recusado, na tela e no banco
  (`f.fn_importacao_remessa_uso_proprio`), quando a observação ou o motivo de compra indicam uso
  próprio (bancada, uso e consumo, ativo imobilizado, manutenção interna, sede, motivos
  CONSUMO_*, MANUTENCAO_*, INVESTIMENTO, OPEX_*). Uso próprio é 3556 ou 3551.
- **Perfis**: `SEG-IMPORTACAO-3101-O1-CST00`, `-3102-`, `-3556-`, `-3551-` (natureza
  `IMPORTACAO_*`, âmbito INTERESTADUAL com UF **EX**, CFOP no campo externo). Nascem em revisão;
  liberação pela tela de perfis, por homologação, como nas outras operações. Em 18/09/2026 os quatro
  receberam IPI 02/319 e PIS/COFINS 71 e voltaram para revisão (migration `..._090000`).
- **Depois da nota real** (gatilho `trg_importacao_remessa_apos_emissao`): entrada no estoque por
  item do catálogo (custo = vProd + II + despesas do courier rateadas; **ICMS entra no custo só
  em 3556/3551**); sem item do catálogo a linha fica em `dados_json.estoque_pendencias`. O
  **crédito de ICMS não é apropriado automaticamente** (movimentação com `credito_icms` 0): a
  GNRE está em nome do courier e repassada na nota de débito, e a pendência fica em
  `dados_json.icms_credito` (PENDENTE_CONTADORA) para a contadora aprovar. Em **3101/3102 o item
  passa a importado pela Segau** (`fiscal_itens.origem` 1, `origem_entrada` 1,
  `equiparado_industrial`, IPI destacado na saída futura; registrado em `dados_json.fiscal_itens`
  e desfeito no cancelamento); em 3556/3551 nada muda no cadastro. **Não gera contas a pagar da
  NF-e.** A nota de débito do courier vira título AP (`origem = IMPORTACAO`, fornecedor pelo
  CNPJ do manifesto, criado se não existir, rateio 100% no plano do motivo de compra; **o motivo
  segue o destino**, `f.fn_importacao_remessa_motivo_por_cfop`: 3556 → CONSUMO_PRODUCAO ou outro
  CONSUMO_*, 3551 → INVESTIMENTO, 3101/3102 → o escolhido, padrão ESTOQUE) **sem duplicar** um
  título do mesmo fornecedor com o mesmo número; com data, conta e forma informadas o pagamento
  é registrado por `f.registrar_pagamento_ap_v2` (título PAGO). Cancelamento da nota real estorna
  a entrada e cancela a importação (a DIR fica livre).
- **Anexos** no bucket `nfe-documentos` (`{tenant}/{empresa}/IMPORTACAO-{id}/...`) pela rota
  `POST /api/faturamento/importacao/anexos` (XML, PDF, JPEG, PNG, WebP, texto e Markdown).

## Onde está no código

- `supabase/migrations/20260918000000_importacao_remessa_nfe_entrada.sql` — tabelas
  `f.importacao_remessa`, `_item`, `_anexo`; `fn_importacao_remessa_ler_dir`, `_criar`, `_cancelar`,
  `_anexo_registrar`; gatilho pós-emissão; patch das funções de preparo (ENTRADA + II no total);
  perfis. `..._010000` — tipos de anexo no bucket e `fn_importacao_remessa_nota_debito_atualizar`.
  `..._020000` — base IBS/CBS sem ICMS no snapshot, trava de uso próprio, equiparação a
  industrial em 3101/3102 e crédito de ICMS pendente da contadora. `..._050000` — o claim de
  produção (`fn_nfe_producao_preparar_e_claimar`, definição completa) soma o II no vNF e o II e o
  vOutro no vItem (as duas travas que barraram a primeira emissão real). `..._060000` — motivo de
  compra pelo CFOP (rateio do título). `..._090000` — IPI 02/319, PIS/COFINS 71, via 11, coluna
  `teste`, CSTs do perfil em `fn_importacao_remessa_criar`, perfis de volta à revisão.
- `supabase/functions/_shared/fiscal/importacao-remessa.ts` + ramo `importacao` em
  `nfe-payload.ts`; naturezas em `tributacao-provisoria.ts` e `fiscal/ibs-cbs-transicao-2026.ts`.
- `lib/importacao/dir-remessa.ts` (parser e conta, usados pela tela e pelos testes),
  `app/faturamento/operacoes/ImportacaoRemessaPanel.tsx`, `app/api/faturamento/importacao/anexos/route.ts`.
- Testes: `supabase/tests/importacao_remessa.sql` (fixture `supabase/tests/fixtures/dir_remessa_ups.xml`),
  `scripts/test-importacao-remessa.mjs` (`npm run test:importacao-remessa`), cenários de importação em
  `scripts/test-nfe-pipeline.mjs`. Prints do fluxo em `docs/importacao/1ZJ451C10441551106/evidencias/`
  (fora do git).

## Decidido, com base legal (definições do Gabriel em 18/09/2026)

1. **IPI na entrada: CST 02 (entrada isenta), cEnq 319** — o RTS isenta o IPI: Decreto-Lei
   1.804/1980, Portaria MF 156/1999, Regulamento Aduaneiro (Decreto 6.759/2009) art. 99; o cEnq 319
   é "remessas postais internacionais sujeitas ao regime de tributação simplificada" (RIPI, Decreto
   7.212/2010, art. 54, XIX; tabela do Anexo XIV da NT 2015.002, que exige cEnq 3xx para CST 02).
   Até 17/09 a nota saía com 03/999 (a 2/24 fica assim).
2. **PIS/COFINS na entrada: CST 71 (aquisição com isenção)**, sem valores — o RTS isenta
   PIS/Pasep-Importação e Cofins-Importação (Lei 10.865/2004, art. 9º, II, "c"). Até 17/09 saía 98.
3. **Remetente da DIR ≠ exportador da invoice** (Shenzhen Cool Dream Supply × Shenzhen Haoxin Xunji):
   decisão operacional, sem base legal específica — o destinatário da NF-e de entrada é quem vendeu
   (invoice); o remetente logístico da DIR fica identificado no infCpl. Os dois constam na nota.
4. **Despesas do courier (serviços + armazenagem, R$ 150,94) fora da base do ICMS e fora da nota**,
   só no custo do estoque — a base do ICMS na importação é mercadoria + II + IPI + IOF + despesas
   aduaneiras (LC 87/1996, art. 13, V); tarifa e armazenagem do courier são cobradas pelo
   transportador, não pela repartição aduaneira, e a própria GNRE recolhida pela UPS (R$ 143,53)
   confere com a base sem elas.
5. **Crédito do ICMS não apropriado automaticamente** — em 3556/3551 (uso e consumo / ativo) não há
   crédito de material de uso e consumo até 1º/01/2033 (LC 87/1996, art. 33, I); em 3101/3102 o
   crédito depende da GNRE em nome do courier, repassada na nota de débito, e fica pendente da
   aprovação da contadora (`dados_json.icms_credito`).
6. **tpViaTransp 11 (courier)** como padrão da remessa expressa, trocável na tela — tabela do campo
   tpViaTransp do grupo DI (leiaute NF-e 4.0, Manual de Orientação do Contribuinte): 11 = Courier.
7. **IBS/CBS na entrada de importação: CST 000 / cClassTrib 000001, base = valor aduaneiro + II**
   (LC 214/2025, art. 69, caput e §§ 1º e 2º; o § 2º, II exclui o ICMS), alíquotas de teste de 2026
   (0,1% / 0% / 0,9%).
8. **cExportador = nome do exportador** — o campo é "código do exportador usado nos sistemas
   internos do emitente" (grupo DI do leiaute NF-e 4.0); não há código interno, então vai o nome.
9. **Item importado pela Segau em 3101/3102 = equiparado a industrial** (RIPI, Decreto 7.212/2010,
   art. 9º, I: importador que dá saída a produto de procedência estrangeira), IPI destacado na saída
   futura com a alíquota da TIPI para o NCM (a equiparação é marcada pelo ERP; a alíquota do
   cadastro fiscal, não).

## Pendências para a contadora

1. **Conta contábil do reembolso ao sócio**: despesas de importação pagas pela pessoa física do
   sócio (nota de débito UPS 2953830, R$ 557,25, e o pagamento ao exportador via PayPal), reembolso
   com comprovantes. Hoje o ERP registra reembolsos como título AP MANUAL ao reembolsado (motivo
   REEMBOLSO, rateio no plano da despesa), pago por PIX; não há conta transitória.
2. **Plano de despesa financeira** para a diferença de câmbio do PayPal + IOF (nada com "financeira",
   "IOF" ou "câmbio" no plano de contas).
3. **Ciência da data da nota**: NF-e 2/24 emitida em 17/09/2026 para uma DIR registrada e
   desembaraçada em 09/09/2026.

## Despesas pagas pelo sócio (cartão pessoal via PayPal): reembolso, não pagamento da empresa

Correção do Gabriel em 18/09/2026: a nota de débito UPS 2953830 (R$ 557,25, 10/09/2026) e o
pagamento ao exportador (US$ 86,12) foram pagos pelo **cartão pessoal do sócio (Itaú PF) via
PayPal**. Não é pagamento da empresa: **não baixar como CARTAO e não criar conta Itaú**.

Padrão que já existe no ERP para despesa da empresa paga por sócio/funcionário: título AP
**MANUAL** ao reembolsado, cadastrado como fornecedor pessoa física (Gabriel = fornecedor 362,
CPF), motivo de compra **REEMBOLSO**, rateio no plano da despesa original, pago por **PIX** da
SICREDI-SGU. Exemplos: "REEMBOLSO IMPORTACAO" R$ 1.599,18 (10/08/2026, plano 4.99), "REEMBOLSO
CARTÃO DE CRÉDITO" R$ 20.610,19 (15/07/2026, CONSUMO_GERAL), "REEMBOLSO CORREIO" R$ 619,60
(14/08/2026, 4.02), reembolsos de km e almoço à equipe (DESP_VIAGEM / DESP_GERAL). O que não existe:
conta transitória (`f.conta_bancaria` só aceita BANCO e CAIXA) e baixa sem conta (`f.pagamento`
exige conta bancária). Nesse padrão a despesa entra só pelo título do reembolso; não há um título
ao fornecedor original baixado "por fora".

- **Nota de débito UPS 2953830**: título AP da importação segue **APROVADO** até o ok do Gabriel.
  Proposta (pendente de ok): cancelar o título da UPS com o motivo "pago pelo sócio; reembolso em
  título próprio" e criar título AP MANUAL de R$ 557,25 ao fornecedor 362 (Gabriel), motivo
  REEMBOLSO, rateio CONSUMO - MATERIAIS GERAIS (o mesmo do título da UPS), em aberto, observação
  "Pago via PayPal, cartão pessoal do sócio; reembolsar". Quando a contadora definir a conta
  contábil, o desenho pode virar conta transitória "Reembolso a sócio" + baixa do título original.
- **Pagamento ao exportador (US$ 86,12)**: continua **não implementado**. Mesmo caminho: cartão
  pessoal do sócio via PayPal; o **valor em reais vem da fatura do cartão** (câmbio do PayPal +
  IOF), não da DIR; **reembolso ao sócio** por título AP MANUAL (motivo REEMBOLSO); a **diferença**
  entre o valor da fatura e os **R$ 437,97 da DIR** vai para o plano de despesa financeira, que a
  contadora ainda vai criar. Até lá o valor da mercadoria entra no custo (vProd da DIR) sem título.
  Exportador como fornecedor sem CNPJ (o cadastro aceita documento nulo), criado pela importação
  quando não existir; o custo de estoque continua o da DIR (vProd + II + courier).

## Teste de homologação de 18/09/2026 (CSTs novos)

Feito em tela (build `next start` na 3025 contra o banco online, Playwright), como uma pessoa
faria: revisão do perfil `SEG-IMPORTACAO-3556-O1-CST00` salva pela tela de perfis; DIR
260191366846 lida de novo (a tela avisou "já em uso na importação concluída, NF-e 2/24"), caixa
**"Teste de homologação"** marcada, mesmos dados da nota real (CFOP 3556, via 11, observação da
bancada), "Gerar importação e emitir em homologação". Resultado: **NF-e 2/68 AUTORIZADA em
homologação (cStat 100)** com `<IPI><cEnq>319</cEnq><IPINT><CST>02</CST></IPINT></IPI>`,
`<PISOutr><CST>71</CST>` e `<COFINSOutr><CST>71</CST>` zerados, `<tpViaTransp>11</tpViaTransp>`:
SEFAZ e Focus aceitam 02/319 e 71 sem valores. A importação de teste ficou HOMOLOGADA com o selo
"TESTE de homologação", sem botão de produção; a importação real (CONCLUIDA, 2/24), o título da
UPS (APROVADO) e o estoque não mudaram. Prints, XML e DANFE em
`docs/importacao/1ZJ451C10441551106/evidencias/teste-rts-2026-09-18/` e
`NFe-2-68-importacao-UPS-homologacao-teste-rts.*` (fora do git). O perfil 3556 está revisado e
**não liberado**: liberar pela tela de perfis usando a 2/68 antes da próxima nota real.

## Backlog (decisão do Gabriel em 18/09/2026, não fazer agora)

- Campo estruturado "destino" na importação (uso próprio / industrialização / revenda) decidindo o
  CFOP, no lugar da trava por palavra-chave na observação e no motivo de compra.
- Equiparação a industrial por lote de entrada, não pelo cadastro do item.
