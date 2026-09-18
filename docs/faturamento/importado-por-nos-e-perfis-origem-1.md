# Item importado por nós, perfis 5102 de origem 1 e a OV-SEG-00004-026 (18/09/2026)

Pedido do Gabriel: preparar o faturamento da OV-SEG-00004-026 (PBG S/A "Portobello", CPU de CLP
OMRON CQM1H-CPU61, item 3629) em homologação, sem produção. A Segau importou a peça (DIR
260191366846, NF-e de entrada 2/24 em CFOP 3556) e por isso é equiparada a industrial na
revenda (RIPI, Decreto 7.212/2010, art. 9º, I): IPI da TIPI destacado. O cliente exige 12% na OC
1309011 para manutenção (exceção do destinatário), e nesse caso o IPI fica dentro da base do
ICMS (CF art. 155, § 2º, XI: manutenção não é industrialização nem revenda).

## O que mudou

| Migration / arquivo | O quê |
| --- | --- |
| `20260918200000_ov_004_preco_da_linha_e_rotulo_da_importacao.sql` | `os_itens` 6394: 1.650,00 → **4.563,40** (orçamento SEG-387-026, 4.488,00 + 1,68% da condição 45D), motivo em `observacoes` e no `audit_log`; `ordens_servico.valor_total` da OV 344 refeito. Rótulo `dados_json.motivo_compra` da importação 6f420998 corrigido (id era CONSUMO_PRODUCAO, texto dizia ESTOQUE). |
| `20260918210000_fiscal_item_importado_por_nos.sql` | Caminho manual **"Importado por nós (DIR/DI no nosso CNPJ)"**: colunas `fiscal_itens.importado_por_nos_*` (DIR, nota, documento_fiscal_id, em, por) e RPC `public.web_fiscal_item_marcar_importado_por_nos(item, dir, nota)`: origem 1, origem_entrada 1, `equiparado_industrial`, CST IPI 50 com a alíquota vigente de `f.tipi_ncm` (51 se a TIPI for 0). Exige DIR/DI de 10 a 12 dígitos e a nota de entrada (série/número ou chave); se a nota existe no ERP e está ligada a uma importação, a DIR tem de bater. Permissão `fiscal_itens.write`. Teste `supabase/tests/fiscal_item_importado_por_nos.sql`. |
| `components/itens/ImportadoPorNosFiscal.tsx` + `app/itens/ItensClient.tsx` | Bloco na aba fiscal do item, em linguagem simples, com confirmação; mostra DIR, nota, quem e quando. |
| `20260918220000_perfis_venda_sc_5102_origem_1_ipi.sql` | Perfis **SEG-VENDA-TERCEIROS-SC-5102-O1-CST00** (12%, REVENDA/INSUMO/CONSIGNADO, indFinal 0) e **-O1-CST00-17** (17%, MANUTENCAO/USO_CONSUMO/ATIVO, indFinal 1), espelho dos -O2-, em REVISÃO, IPI CST 50 cEnq 999 com alíquota em branco, evidência própria (DIR/NF-e 2/24). Resolvedor `f.fn_solicitacao_nfe_resolver_perfis`: perfil com CST 50/99 sem alíquota completa com a do cadastro do produto e, na falta, com a TIPI. |
| `20260918230000_nfe_contexto_emissao_equiparacao_do_item.sql` | `f.fn_nfe_contexto_emissao_impl` passa a levar `equiparado_industrial`, `origem_entrada` e `importado_por_nos_dir` do cadastro fiscal em cada `solicitacao_item`. Antes, nenhum contexto de emissão carregava a marca e todo item de origem 1 parava no montador ("sem a marca de equiparado a industrial") — inclusive os marcados pela importação 3101/3102. |
| `scripts/test-nfe-pipeline.mjs` | Cenários: exceção 12% + manutenção + item equiparado (IPI 9,75%) → vBC = vProd + vIPI (5.008,33), ICMS 601,00; o mesmo sem exceção → trava `conflitoIpiNaBaseComAliquota`; manutenção a 17% com IPI na base sem trava. O montador já permitia; faltava o teste. |

## Homologação da OV-SEG-00004-026 — NF-e 2/73

Feita pela tela da venda (rascunho 1 UN × 4.563,40 → destino SC → destinação manutenção →
exceção 12% com OC 1309011 e evidência = carta da Portobello → boleto, 1 parcela em 45 dias →
frete 1, TEDE → Emitir em homologação). Solicitação `b054ba1c`, perfil resolvido
SEG-VENDA-TERCEIROS-SC-5102-O1-CST00-17 com a exceção por cima.

| Campo do XML | Valor |
| --- | --- |
| nNF / série / tpAmb / cStat / protocolo | 73 / 2 / 2 / 100 / 342260000954279 |
| chave | 42260913671448000189550020000000731420468106 |
| dhEmi | 2026-09-18T09:22:52-03:00 |
| natOp / CFOP / indFinal / indPres / xPed | VENDA MERCADORIA ADQ. REC. DE TERCEIROS / 5102 / 1 / 9 / 1309011 |
| item | CQM1HCPU61, NCM 85371020, 1 UN × 4.563,40, **orig 1** |
| ICMS | CST 00, modBC 3, **vBC 5.008,33, 12%, vICMS 601,00** |
| IPI | **CST 50, cEnq 999, 9,75%, vIPI 444,93** |
| PIS / COFINS | 01, base 3.962,40: 65,38 / 301,14 |
| IBS / CBS | 000 / 000001, base 3.595,88 |
| vNF | **5.008,33** |
| dup | 001 · 02/11/2026 · 5.008,33 (tPag 15, indPag 1) |
| frete | modFrete 1, TEDE TRANSPORTES (02.484.555/0010-72), 1 volume, 1,000 kg |
| infCpl | "Item 1: ICMS à alíquota de 12% (RICMS/SC-01, art. 26, III, "n") aplicada por determinação do destinatário, conforme OC no 1309011, utilização informada: manutenção. O destinatário responde solidariamente pela diferença de alíquota, nos termos do art. 26, § 6o, do RICMS/SC-01. \| Pedido de compra do cliente: 1309011 \| Trib. aprox. R$: 1.253,57 Federal, 155,16 Estadual Fonte: IBPT/empresometro.com.br A906AF" (a Focus troca "º" por "o" e acrescenta o vTotTrib, 1.408,72) |

Produção **não** foi emitida. Antes dela: revisar o perfil -O1-CST00-17 (IBS/CBS) na tela de
perfis, homologar de novo após a revisão e liberar para a solicitação. Se a OC for valor
fechado, refazer com vProd 4.158,00 (decisão pendente do Gabriel).

## Por que a OV herdou o preço do cadastro (item 1)

`os_itens` 6394 nasceu em 02/09/2026 com 1.650,00 porque o orçamento SEG-387-026 foi fechado em
01/09 **sem** "importar itens para a OV" (`m.orcamento.os_itens_importados_at` nulo) e a linha
foi incluída a mão na tela da venda, cujo campo de valor vem preenchido com
`itens.preco_unitario` (`VendaDetalheClient.selecionarNovoItem`). Não é bug de gravação, é
fragilidade geral: (1) a tela sugere o preço do cadastro mesmo quando a OV veio de um orçamento
com o mesmo item; (2) nada alerta quando a soma das linhas difere do `orcado` da OV — só o
painel de faturar mostra "Diferença" na hora de compor a nota, e ele sugere preços rateando o
`orcado` (por isso os rascunhos antigos já saíam com 4.563,40). Corrigido em 18/09/2026 à
tarde: a tela sugere o preço do orçamento e a OV avisa quando as linhas não fecham com o
orçado; o rascunho só nasce com o motivo (ver `faturamento-os-vs-ov.md`, seção "Linhas da OV
× orçamento").

O cadastro fiscal do item 3629 também não veio da entrada: o `audit_log` mostra NCM e origem
digitados em 02/09, origem trocada para 2 em 03/09 e para 0/2 em 04–05/09, CST IPI 53 em 03/09.
A importação 3556 de 17/09 não toca o cadastro por regra.

## NF-e 2/24 (somente leitura, item 6)

- dhEmi **2026-09-17T20:26:40-03:00**, autorizada 20:26:42 (protocolo 242260441882906). O
  cancelamento normal vale até **24 h da autorização: 18/09/2026 20:26:42**. Depois só
  cancelamento extemporâneo (Ajuste SINIEF 07/05, cláusula 13ª; em SC, até 480 h com
  justificativa e sujeito a penalidade).
- **Rascunho de CC-e 3556 → 3102** (não enviada; a contadora avalia): `CORRECAO DO CFOP, DA
  NATUREZA DA OPERACAO E DO INDICADOR DE CONSUMIDOR FINAL DO ITEM 1 (CPU DE CLP OMRON
  CQM1H-CPU61, NCM 8537.10.20, DIR 260191366846): ONDE SE LE CFOP 3556, NATUREZA "COMPRA DE
  MATERIAL PARA USO OU CONSUMO - IMPORTACAO" E indFinal 1, LEIA-SE CFOP 3102, NATUREZA "COMPRA
  PARA COMERCIALIZACAO - IMPORTACAO" E indFinal 0, POR SE TRATAR DE MERCADORIA DESTINADA A
  REVENDA. VALORES, QUANTIDADES, TRIBUTOS DESTACADOS, DATAS E PARTES PERMANECEM INALTERADOS.` CFOP,
  natOp e indFinal não estão entre as vedações da cláusula 14-A, § 1º-A (valor do imposto,
  partes, datas); CST de IPI/PIS/COFINS ficam como saíram (03/999 e 98).
- O que mudaria no ERP se a entrada fosse 3102 (só descrição; a NF-e não muda): crédito de ICMS
  de **143,53** deixa de ir ao custo e vai para `dados_json.icms_credito` PENDENTE_CONTADORA
  (movimentação com `credito_icms` 143,53, GNRE em nome do courier); custo do item **995,22 →
  851,69** (437,97 + II 262,78 + courier 150,94); motivo de compra do título da UPS (hoje
  cancelado, reembolso ao sócio de 557,25 pendente) **CONSUMO_PRODUCAO → ESTOQUE** (rateio no
  plano de estoque); cadastro fiscal com origem 1 e equiparação (já feito à mão hoje);
  natureza IMPORTACAO_COMERCIALIZACAO, perfil 3102 (em revisão), indFinal 0. Uma CC-e não
  reexecuta o gatilho pós-emissão: esses ajustes seriam por migration, com o OK.
- Rótulo do JSON: corrigido (só texto) na migration 200000.

## Estoque do item 3629 — proposta (item 7, aguarda OK)

Hoje: +1 ajuste manual 02/09 (mov. 12633, sem custo), −1 saída da OV 02/09 (mov. 12634, sem
custo), +1 entrada da importação 17/09 (mov. 13351, 995,22). Saldo 1, mas a unidade vendida é a
importada.

Correção mais limpa, por migration com `audit_log`, sem tocar a NF-e:

1. Estornar o ajuste fantasma: saída de ajuste −1 datada de hoje, motivo "estorno do ajuste
   rápido de 02/09/2026 (unidade fantasma; a peça vendida é a da NF-e 2/24)". Saldo → 0.
2. Dar custo à saída da OV: `movimentacoes` 12634 com `custo_unitario_bruto` 437,97 e
   `custo_unitario_real` **995,22** (ou **851,69** se a entrada virar 3102, e então a 13351 também
   passa a 851,69 com `credito_icms` 143,53).
3. `itens.custo_medio`/`custo_ultima_compra` acompanham (995,22 hoje).

Resultado: saldo zero depois da entrega, custo da venda = custo da importação.
