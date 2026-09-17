# Importação por remessa expressa (NF-e de entrada, tpNF 0)

Entregue em 17/09/2026. Primeiro caso: remessa UPS 1ZJ451C10441551106 (DIR 260191366846,
registrada em 09/09/2026, UA 0817700 Viracopos/SP), uma CPU de CLP OMRON CQM1H-CPU61
(US$ 45,00 + frete US$ 41,12 a 5,0856) no regime de tributação simplificada (RTS, regime 7):
II de 60% recolhido pelo courier (R$ 262,78), ICMS por GNRE (receita 10005-6, R$ 143,53), sem
IPI, PIS e COFINS. Homologação: **NF-e 2/66 autorizada em 17/09/2026** (chave
42260913671448000189550020000000661858317736, protocolo 342260000953704).

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
  IPI 03/999, PIS/COFINS 98, IBS/CBS 000/000001 sobre valor aduaneiro + II + ICMS (LC 214/2025,
  art. 71; 0,1% / 0% / 0,9% em 2026), modFrete 9, tPag 90, infAdFisco e infCpl com AWB, DIR,
  GNRE, nota de débito, remetente da DIR e exportador da invoice.
- **Perfis**: `SEG-IMPORTACAO-3101-O1-CST00`, `-3102-`, `-3556-`, `-3551-` (natureza
  `IMPORTACAO_*`, âmbito INTERESTADUAL com UF **EX**, CFOP no campo externo). Nascem em revisão;
  liberação pela tela de perfis, por homologação, como nas outras operações.
- **Depois da nota real** (gatilho `trg_importacao_remessa_apos_emissao`): entrada no estoque por
  item do catálogo (custo = vProd + II + despesas do courier rateadas; **ICMS entra no custo só
  em 3556/3551**, sem crédito), `credito_icms` na movimentação para os perfis com crédito; sem
  item do catálogo a linha fica em `dados_json.estoque_pendencias`. **Não gera contas a pagar da
  NF-e.** A nota de débito do courier vira título AP (`origem = IMPORTACAO`, fornecedor pelo
  CNPJ do manifesto, criado se não existir, rateio 100% no plano do motivo) **sem duplicar** um
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
5. Crédito do ICMS (CFOP 3101/3102) com a GNRE recolhida em nome da UPS e repassada na nota de débito.
6. tpViaTransp 4 (aérea) ou 11 (courier) para remessa expressa.
7. IBS/CBS na entrada de importação: CST 000/000001, base valor aduaneiro + II + ICMS, alíquotas
   de teste de 2026.
8. cExportador = nome do exportador (não há código interno).
