# Homologação — NFS-e Padrão Nacional a partir da OS, pela Focus

**Data:** 05/09/2026 · **Ambiente:** somente `HOMOLOGACAO` · **Migrations:** `20260905190000_nfse_nacional_fundacao`, `20260905200000_nfse_nacional_pipeline`, `20260905210000_nfse_contexto_empresa`, `20260905220000_nfse_dps_marcar` · **Inventário:** [nfse-inventario.md](nfse-inventario.md).

## Estado em uma frase

Tudo está construído e provado até a porta da Focus: a tela emite pelo mesmo botão Faturar da NF-e, a DPS é numerada pelo ERP dentro da transação do rascunho, o POST `/v2/nfsen` foi feito de verdade e **a Focus recusou porque a NFS-e Nacional em homologação ainda não está habilitada para a empresa no painel** (opção `habilita_nfsen_homologacao`, mensagem literal abaixo). A rejeição foi tratada como projetado: mensagem legível na tela, DPS 2/1 queimada, saldo da OS devolvido. Os cenários que dependem de autorização do ambiente nacional ficam prontos para rodar assim que o painel for habilitado; a mesma lógica está provada no teste SQL (rollback) e no teste local do pipeline.

## O que o Gabriel precisa fazer para destravar

1. No painel da Focus (homologação), empresa **13.671.448/0001-89**, ativar `habilita_nfsen_homologacao` (referência: https://focusnfe.com.br/e/nfse-nacional).
2. Nada mais no ERP: `FOCUS_NFSE_NACIONAL_ENABLED=true` já está nos secrets, o webhook `nfsen` já está registrado (id `rR9LQW65`, URL `https://ptybnreejbkqwwozvhzb.supabase.co/functions/v1/nfse-callback?token=…`, token em `FOCUS_NFE_WEBHOOK_TOKEN`, criado hoje) e o rascunho da OS 327 está em `REJEITADA` esperando o botão "Tentar emitir novamente (nova DPS)".
3. Rodar os cenários pelos comandos do fim deste documento e colar aqui o que voltou (número, DPS, chave).

## Cenários

| # | Cenário | Situação | Onde está provado |
|---|---|---|---|
| 1 | 14.06 sem retenção, uma linha | **Executado até a Focus** na OS 327 (Portobello, R$ 10.177,33, OC 1307761): conferência OK, prévia (ISS 5% = 508,87 recolhido pela Segau, líquido 10.177,33), discriminação montada, DPS **2/1** reservada, referência `NFSH-804c3450-0709-4795-bd5f-8f19d5ee6d0f`, POST feito, Focus HTTP 400 "O município Joinville SC adota o AMBIENTE NACIONAL para emissão de NFSe em homologação. Para utilizá-lo, ative a opção 'habilita_nfsen_homologacao' da empresa." Emissão `REJEITADA`, evento `REJEICAO`, saldo da OS de volta a 10.177,33 | tela + banco; SQL (cenário A/B) |
| 2 | 17.09 com ISS retido | Aguarda painel. Provado no SQL: 17.09 com ISS retido + IRRF 1,5% + PCC 4,65%, bruto 6.000 → ISS 300, IRRF 90, PCC 279, líquido 5.331; `tpRetISSQN 2`, `tpRetPisCofins 3`, `valor_csll` = soma | SQL (A); pipeline mjs |
| 3 | 17.09 sem retenção | Aguarda painel. Mesma função com override "não retém" + justificativa (SQL E) | SQL (E) |
| 4 | 17.06 com prestação na sede | Aguarda painel. Regra `SEDE` → município 4209102 (SQL A usa 17.09 SEDE; 17.06 tem a mesma fixture) | SQL (A) |
| 5 | 14.06 na planta do cliente fora de Joinville | **Conferido de verdade** na OS 327: município de prestação 4218004 (Tijucas) pela regra `CLIENTE`, editável | tela; SQL (B) |
| 6 | INSS + IRRF + PCC retidos, título líquido e `titulo_retencao` | Aguarda painel para a nota; o título está provado pelo caminho de produção: documento EMITIDA → AR nasce do líquido (2.221,25), parcelas 14/28 dias sobre o líquido, 5 linhas em `f.titulo_retencao` (ISS, IRRF, PIS, COFINS, CSLL = 278,75), cancelamento zera o aberto | SQL (título) |
| 7 | Duas OS do mesmo tomador numa NFS-e | Aguarda painel. Provado: linhas OS-1 (1.000) + OS-2 (1.500), reserva por OS (7.000/3.000 e 1.500/500), discriminação com as duas OS | SQL (C); tela tem "Adicionar OS do mesmo tomador" |
| 8 | Parcial em duas NFS-e | Aguarda painel. Mesma mecânica da NF-e (saldo por OS, reserva por solicitação) | SQL (A + C na OS 915400) |
| 9 | Tomador de Joinville sem IM bloqueia antes da Focus | Provado: pendência `cliente · inscricao_municipal` com rota `/clientes/cadastro-fiscal?cliente_id=…`, nenhuma emissão criada | SQL (D) |
| 10 | `iss_retido` indefinido bloqueia | **Executado na tela** (OS 327, Portobello sem decisão): quatro pendências (iss_retido, retem_pcc, retem_irrf, retem_inss) com link "corrigir"; override sem justificativa bloqueia; com justificativa passa e vai para a discriminação ("RETENCAO AJUSTADA: …"); `clientes.iss_retido` continua nulo | tela; SQL (E) |
| 11 | Rejeição: DPS queimada, saldo devolvido | **Executado de verdade** (rejeição da Focus na OS 327): emissão `REJEITADA`, saldo devolvido, log da DPS 2/1 marcado; retry renumera (SQL: DPS 1 → 4, claim exige o número novo) | tela + banco; SQL (rejeição) |
| 12 | Cancelamento | Aguarda painel. Provado: claim durável + finalizar, emissão/solicitação `CANCELADA`, log `CANCELADO`, saldo devolvido, finalização repetida idempotente, retorno tardio não reabre | SQL (cancelar) |
| 13 | Substituição com migração de saldo e título | Aguarda painel. Provado: clone da solicitação com `chave_nfse_substituida` (DPS nova), reserva da substituída conta a favor, na autorização da nova a antiga vira `SUBSTITUIDA`, solicitação antiga encerrada, log `SUBSTITUIDO`, dois eventos `SUBSTITUICAO` (chave nova/substituída/código), segunda substituição concorrente recusada | SQL (substituir) |
| 14 | Retry mesma referência, webhook duplicado, reconciliação | Provado: preparo idempotente (mesmo documento/DPS), webhook duplicado não gera segunda autorização nem sobrescreve o XML, reconciliação usa `fn_nfse_emissoes_pendentes_reconciliacao` + GET `/v2/nfsen/<ref>` no cron de 15 min (bloco próprio em `nfe-reconciliar`, atrás da flag) | SQL; código |

Aceite dos PDFs (cenários 1, 2 e 4 lado a lado com as NFS-e reais): pendente da habilitação; os DANFSe são baixados por `scripts/chrome-os-nfe-arquivos.mjs` (mesma lista de notas) assim que existirem.

## O que ficou registrado no banco nesta rodada

| Objeto | Valor |
|---|---|
| `c.empresa_fiscal` (Elétrica Segau) | `serie_dps 2`, `proximo_numero_dps 2` (a DPS 2/1 foi consumida), `codigo_opcao_simples_nacional 1`, `regime_especial_tributacao 0`, `inscricao_municipal 152836`, `prazo_cancelamento_nfse_horas` **vazio**, `focus_webhook_nfsen_id rR9LQW65` |
| Perfis de serviço | `SEG-NFSE-1406`, `-1709`, `-1706`, `-1401` (REVISAO) e `-0702` (BLOQUEADO), todos sem valor fiscal |
| Fixture `f.tributacao_provisoria_nfse_homologacao` | 14.06 / 17.09 / 17.06 / 14.01 / 07.02 com fonte (NFS-e 12–40 de ago/2026) e pendência do contador |
| Solicitação da OS 327 | `NFSH-804c3450-…`, emissão `REJEITADA` (HTTP 400 da Focus), DPS 2/1 |
| `clientes.iss_retido` etc. | Nenhum gravado (a decisão da OS 327 ficou só na nota, com justificativa) |

## Decisões tomadas nesta rodada (para revisão)

- **Uma única sequência de DPS** (`proximo_numero_dps`) para homologação e produção. Antes da primeira NFS-e real, decidir se o contador quer produção começando em 1 (basta zerar o contador ou usar outra série).
- Prazo de cancelamento vazio: em homologação o botão aparece com aviso; em produção fica oculto até o contador confirmar (`c.empresa_fiscal.prazo_cancelamento_nfse_horas`).
- Retenções: regra do perfil/fixture (`NUNCA/SEMPRE/POR_TOMADOR`) → cadastro do cliente → override na nota com justificativa. Base do INSS = valor bruto (simplificação; ver perguntas).
- Discriminação (≤1000, maiúsculas, mesma ordem das NFS-e reais): `<DESCRIÇÃO> - OS <n>. PEDIDO DE COMPRA: <n> [ITEM <n>]. VENCIMENTO: <dias> DDL (<datas>). ISS RETIDO PELO TOMADOR|RECOLHIDO PELO PRESTADOR. <texto de retenção>. <observação> [RETENCAO AJUSTADA: <justificativa>]`. As datas de vencimento são calculadas na conferência (data + dias).
- `razao_social_tomador` em homologação = "NFS-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL" (mesma disciplina da NF-e); em produção o nome real.
- `FOCUS_NFE_WEBHOOK_TOKEN` (homologação) não existia: foi criado hoje e serve também ao `nfe-callback` de homologação da NF-e, que até então recusava tudo com 401 (a reconciliação cobria).

## Perguntas que sobraram para o contador (renumeradas; o plano citado na tarefa não foi encontrado)

| # | Pergunta | O que trava |
|---|---|---|
| 13 | Código nacional de cada serviço da Segau: 14.06 → `140601`, 17.09 → `170901`, 14.01 → `140101`, 07.02 → `070201` conferem? O 17.06 (`170601`) usado pelo emissor antigo é "propaganda e publicidade" na LC 116; assessoria técnica não seria 17.01? | Perfis 17.06/17.01 sem valor; homologação usa a fixture |
| 14 | NBS por serviço: 14.06 saiu com 120032900 (14 notas), 101061900 e 101026900 (3); 17.09/17.06 com 114044900; 14.01 sem NBS observado. Qual usar? | `codigo_nbs` dos perfis |
| 15 | Alíquota de ISS e local de incidência: 5% Joinville na sede; na planta do cliente (Tijucas, Guaramirim, São Francisco do Sul 3%) o ISS é do município do tomador? Para 14.06/14.01 em planta do cliente, `cLocPrestacao` = município do tomador está certo? | `local_prestacao_regra` e `aliquota_iss` dos perfis |
| 16 | Retenções federais por serviço e por tomador: IRRF 1,5% e PCC 4,65% valem para 17.09/17.06 sempre que o tomador for PJ (acima do piso mensal)? Em 14.06/14.01 nunca? Texto legal que deve ir na discriminação em cada caso | `retencao_*_regra`, `texto_complementar` |
| 17 | INSS 11%: em quais serviços (07.02 sempre; 14.06/14.01 com cessão de mão de obra?) e sobre qual base (bruto ou só mão de obra, com dedução de material)? | `retencao_inss_regra`, `permite_deducao_material`, base do cálculo |
| 18 | Prazo de cancelamento da NFS-e Nacional para Joinville e regra de substituição (códigos 01–05/99) que a Segau pode usar sem o tomador rejeitar | `prazo_cancelamento_nfse_horas`; botão Cancelar em produção |
| 19 | PIS/COFINS próprios na NFS-e (CST 01, 1,65%/7,60% no Lucro Real) e IBS/CBS 2026 (CST 000, cClassTrib 000001, 0,10%/0,90%) para serviços: confirmar, inclusive se a NFS-e deve levar o grupo IBS/CBS já em 2026 (a NFS-e 37 de agosto levou; 35/39 não) | `cst_ibs_cbs`, `cclass_trib` dos perfis |
| 20 | Série da DPS do ERP: 2 (proposta; o emissor antigo usa 70000) e se a produção deve começar em 1 | `serie_dps`, `proximo_numero_dps` |
| 21 | Perfil 07.02 (obra): quais dados da obra (endereço, CNO/CEI, ART) e retenções são obrigatórios para desbloquear | `SEG-NFSE-0702` BLOQUEADO |
| 22 | Inscrição municipal do prestador: 152836 é da Elétrica Segau (o cadastro da SGU AUTOMAÇÃO tem o mesmo número) | `c.empresa_fiscal.inscricao_municipal` |

## Como reproduzir

```
# cenario 10 (bloqueio) e 1/5 (14.06 na planta do cliente) na OS 327 (id 326)
node scripts/chrome-os-nfse-homologacao.mjs --os 326 --perfil 14.06 --dias 45 --so-conferir
node scripts/chrome-os-nfse-homologacao.mjs --os 326 --perfil 14.06 --dias 45 --iss nao --pcc nao --irrf nao --inss nao --justificativa "..." --obs "..."
# 17.09 com ISS retido + IRRF + PCC (override com justificativa) numa OS de laudo (ex.: OS 256, INCASA, id 255 — precisa de IM do tomador)
node scripts/chrome-os-nfse-homologacao.mjs --os 255 --perfil 17.09 --iss sim --pcc sim --irrf sim --inss nao --justificativa "..." --dias 21
# duas OS do mesmo tomador (Portobello): OS 327 + OS 288
node scripts/chrome-os-nfse-homologacao.mjs --os 326 --perfil 14.06 --add-os 288 --valor 5000 --valor2 9000 --iss nao --pcc nao --irrf nao --inss nao --justificativa "..."
# cancelar / substituir a nota autorizada da OS
node scripts/chrome-os-nfse-homologacao.mjs --os 326 --cancelar "Cancelamento no cenario de homologacao 12"
node scripts/chrome-os-nfse-homologacao.mjs --os 326 --substituir "Descricao corrigida a pedido do tomador"
# leitura das retencoes por tomador (nao grava nada)
node scripts/nfse-retencoes-por-tomador.mjs 2026-07-01 2026-08-31
# registrar o webhook nfsen (ja feito hoje)
node scripts/nfse-webhook-registrar.mjs
# testes
docker run --rm -i -e PGPASSWORD=postgres postgres:16-alpine psql -h host.docker.internal -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -q < supabase/tests/faturamento_os_nfse_homologacao.sql
npm run test:nfse-pipeline
npm run test:nfe-pipeline
```
