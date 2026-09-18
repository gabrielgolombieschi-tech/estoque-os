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
da nota de débito UPS 2953830 (R$ 557,25, vencimento 10/09/2026) **APROVADO**, sem baixa: a conta
e a forma de pagamento não foram informadas. DANFE e XML (real e homologação) em
`docs/importacao/1ZJ451C10441551106/`.

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
  IPI 03/999, PIS/COFINS 98, IBS/CBS 000/000001 sobre **valor aduaneiro + II** (base do II
  acrescida dos tributos do caput, sem o ICMS e sem o IPI: LC 214/2025, art. 69, caput e §§ 1º e
  2º; 0,1% / 0% / 0,9% em 2026; nesta nota 700,75, IBS 0,70 e CBS 6,31), modFrete 9, tPag 90,
  infAdFisco e infCpl com AWB, DIR, GNRE, nota de débito, remetente da DIR e exportador da invoice.
- **Trava de destino**: CFOP 3101/3102 (industrialização/revenda) é recusado, na tela e no banco
  (`f.fn_importacao_remessa_uso_proprio`), quando a observação ou o motivo de compra indicam uso
  próprio (bancada, uso e consumo, ativo imobilizado, manutenção interna, sede, motivos
  CONSUMO_*, MANUTENCAO_*, INVESTIMENTO, OPEX_*). Uso próprio é 3556 ou 3551.
- **Perfis**: `SEG-IMPORTACAO-3101-O1-CST00`, `-3102-`, `-3556-`, `-3551-` (natureza
  `IMPORTACAO_*`, âmbito INTERESTADUAL com UF **EX**, CFOP no campo externo). Nascem em revisão;
  liberação pela tela de perfis, por homologação, como nas outras operações.
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
  industrial em 3101/3102 e crédito de ICMS pendente da contadora. `..._030000` e `..._040000` —
  o claim de produção (`fn_nfe_producao_preparar_e_claimar`) passa a somar o II no vNF e o II e
  o vOutro no vItem (as duas travas que barraram a primeira emissão real).
- `supabase/functions/_shared/fiscal/importacao-remessa.ts` + ramo `importacao` em
  `nfe-payload.ts`; naturezas em `tributacao-provisoria.ts` e `fiscal/ibs-cbs-transicao-2026.ts`.
- `lib/importacao/dir-remessa.ts` (parser e conta, usados pela tela e pelos testes),
  `app/faturamento/operacoes/ImportacaoRemessaPanel.tsx`, `app/api/faturamento/importacao/anexos/route.ts`.
- Testes: `supabase/tests/importacao_remessa.sql` (fixture `supabase/tests/fixtures/dir_remessa_ups.xml`),
  `scripts/test-importacao-remessa.mjs` (`npm run test:importacao-remessa`), cenários de importação em
  `scripts/test-nfe-pipeline.mjs`. Prints do fluxo em `docs/importacao/1ZJ451C10441551106/evidencias/`
  (fora do git).

## Pendências para a contadora (primeira nota real)

1. CST do IPI na entrada: 03 (não tributada) com cEnq 999.
2. CST de PIS/COFINS 98 (outras operações de entrada), sem valores — o RTS unifica no II de 60%.
3. Remetente da DIR (Shenzhen Cool Dream Supply) ≠ exportador da invoice (Shenzhen Haoxin Xunji):
   a nota sai para o exportador da invoice e cita o remetente da DIR no infCpl.
4. Despesas do courier (serviços + armazenagem, R$ 150,94) fora da base do ICMS e fora da nota;
   entram só no custo do estoque.
5. Crédito do ICMS (CFOP 3101/3102) com a GNRE recolhida em nome da UPS e repassada na nota de
   débito: o ERP não apropria; fica pendente da aprovação da contadora.
6. tpViaTransp 4 (aérea) ou 11 (courier) para remessa expressa.
7. IBS/CBS na entrada de importação: CST 000/000001, base = valor aduaneiro + II (LC 214/2025,
   art. 69, caput e §§ 1º e 2º; o § 2º, II exclui o ICMS), alíquotas de teste de 2026.
8. cExportador = nome do exportador (não há código interno).
9. Item importado pela Segau (3101/3102): alíquota de IPI da TIPI para o NCM no cadastro fiscal,
   para a saída futura destacar o IPI (a equiparação é marcada pelo ERP; a alíquota não).

## Pagamento ao exportador (US$ 86,12 pelo PayPal, no cartão de crédito): não implementado

Decisão do Gabriel em 18/09/2026: **aguarda a contadora criar o plano de despesa financeira**;
até lá o valor da mercadoria entra no custo (vProd da DIR) sem título e sem pagamento no ERP.
Como será quando entrar:

- Forma **CARTAO via PayPal**, no padrão dos pagamentos em cartão que o ERP já registra
  (`f.titulo` AP + `f.pagamento` de forma `CARTAO` contra a conta bancária em que a fatura do
  cartão é debitada; hoje SICREDI, SANTANDER e CAIXA).
- O **valor em reais vem da fatura do cartão** (câmbio do PayPal + IOF), não da DIR.
- A **diferença** entre o valor da fatura e os **R$ 437,97 da DIR** vai para o plano de despesa
  financeira (que ainda não existe: nada com "financeira", "IOF" ou "câmbio" no plano de contas).
- Exportador como fornecedor sem CNPJ (o cadastro aceita documento nulo; há 41 assim), criado
  pela importação quando não existir; o custo de estoque continua o da DIR (vProd + II + courier).

Nota de débito da UPS 2953830 (R$ 557,25, 10/09/2026): paga via PayPal com o cartão de crédito;
baixa de forma CARTAO na conta do cartão, com a observação "Pago via PayPal; aparece na fatura
como PayPal".

## Backlog (decisão do Gabriel em 18/09/2026, não fazer agora)

- Campo estruturado "destino" na importação (uso próprio / industrialização / revenda) decidindo o
  CFOP, no lugar da trava por palavra-chave na observação e no motivo de compra.
- Equiparação a industrial por lote de entrada, não pelo cadastro do item.
