# Homologação — NFS-e Padrão Nacional a partir da OS, pela Focus

**Data:** 05/09/2026 · **Ambiente:** somente `HOMOLOGACAO` (ambiente nacional de homologação via Focus, sem validade jurídica) · **Migrations:** `20260905190000` a `20260905230000` · **Inventário:** [nfse-inventario.md](nfse-inventario.md).

## Resultado em uma frase

Oito NFS-e Padrão Nacional foram autorizadas em homologação saindo de OS reais pelo botão Faturar (números 1 a 8, série 2 da DPS numerada pelo ERP), com cancelamento (NFS-e 5), substituição (NFS-e 7 substitui a 4), duas OS numa nota (NFS-e 2), parcial em duas notas (NFS-e 6 e 8) e retenções de ISS, INSS, IRRF e PCC (NFS-e 3 e 8). O retorno chegou pelo webhook `nfsen` em todas. Depois da bateria, as homologações foram abandonadas e o saldo de cada OS voltou.

## O que precisou ser habilitado e o que foi descoberto na Focus

1. O Gabriel ativou **Ambiente da NFSe Nacional - Homologação** no painel da Focus (série 1 / próximo 1 no painel; o ERP numera a DPS com a série 2 e envia `serie_dps/numero_dps`, aceitos).
2. Webhook `nfsen` registrado pelo ERP (`nfse-ciclo`, ação `REGISTRAR_WEBHOOK`): id `rR9LQW65`, URL `https://ptybnreejbkqwwozvhzb.supabase.co/functions/v1/nfse-callback?token=…`. O secret `FOCUS_NFE_WEBHOOK_TOKEN` (homologação) não existia e foi criado; ele também passa a aceitar o callback de homologação da NF-e.
3. O ambiente nacional valida o XML da DPS de forma iterativa. Cada recusa queimou uma DPS (log em `f.dps_numero_log`) e foi corrigida no montador de payload (`supabase/functions/_shared/nfse-payload.ts`):

| DPS | Recusa | Correção |
|---|---|---|
| 2/1 | HTTP 400 Focus: "ative a opção habilita_nfsen_homologacao" | painel da Focus |
| 2/2 | `cIntContrib` padrão `[a-zA-Z0-9]{1,20}` ("OS 327"); `indDest` exige `cIndOp` | `codigo_interno_contribuinte = OS327`; `codigo_indicador_operacao` provisório (040101 na 07.02, 050103 nos demais, lidos das NFS-e 37 e 32 de agosto) |
| 2/3 | E0120: IM do prestador não deve ser informada (Joinville sem informações complementares no CNC) | IM do prestador não vai |
| 2/4, 2/5, 2/6 | E0240: CEP do tomador não pertence ao município | cadastro fiscal da Portobello corrigido pela tela (CEP 88200122, ROD GOVERNADOR MARIO COVAS, KM 163, igual à NFS-e 35 real); a conferência antiga tinha o snapshot congelado com o CEP velho, por isso o rascunho foi descartado e refeito |
| 2/7 | E0121: nome do prestador não deve ser informado quando o emitente é o prestador | nome e endereço do prestador não vão (só CNPJ, telefone, e-mail, opSimpNac, regEspTrib) |
| 2/8 | E0617: alíquota de ISS não pode ser informada por não optante com município ativo | `percentual_aliquota_relativa_municipio` não vai (o município parametriza; a alíquota da fixture fica só na prévia) |
| 2/9 | E0713: `indTotTrib` não permitido para não optante | ERP passa a enviar os totais aproximados (Lei 12.741): federais = PIS+COFINS próprios, municipais = ISS, estaduais 0 |
| 2/10 | **autorizada** (NFS-e 1) | — |

A partir daí o claim de retry passou a aceitar payload corrigido depois de rejeição (migration `20260905230000`), porque o número rejeitado está queimado e nada foi autorizado.

## Notas autorizadas

| NFS-e | DPS | OS (id) | Tomador | Cenário | Bruto | Retenções | Líquido | Chave |
|---|---|---|---|---|---|---|---|---|
| 1 | 2/10 | 327 (326) | Portobello, Tijucas | 1 e 5 · 14.06 na planta do cliente, sem retenção, à vista | 10.177,33 | — | 10.177,33 | 42091022213671448000189000000000000126098705177635 |
| 2 | 2/11 | 288 + 289 (287, 288) | Portobello | 7 · duas OS do mesmo tomador numa nota (4.000 + 6.000) | 10.000,00 | — | 10.000,00 | 42091022213671448000189000000000000226092979593240 |
| 3 | 2/12 | 270 (269) | WEG Tintas, Guaramirim | 2 · 17.09 na sede, ISS retido + IRRF 1,5% + PCC 4,65% | 3.000,00 | ISS 150 · IRRF 45 · PCC 139,50 | 2.665,50 | 42091022213671448000189000000000000326090463111737 |
| 4 | 2/13 | 145 (164) | Portobello | 3 · 17.09 sem retenção (depois substituída) | 5.000,00 | — | 5.000,00 | 42091022213671448000189000000000000426090785591013 |
| 5 | 2/14 | 302 (301) | Portobello | 4 · 17.06 na sede; **cancelada** no cenário 12 | 2.500,00 | — | 2.500,00 | 42091022213671448000189000000000000526099752182138 |
| 6 | 2/15 | 328 (327) | WEG Tintas | 8 · parcial A (8.000 de 18.500) | 8.000,00 | — | 8.000,00 | 42091022213671448000189000000000000626099736375303 |
| 7 | 2/16 | 145 (164) | Portobello | 13 · **substituta** da 4 (`chSubstda`, `cMotivo 99`, cStat 101) | 5.000,00 | — | 5.000,00 | 42091022213671448000189000000000000726094457683225 |
| 8 | 2/17 | 328 (327) | WEG Tintas | 6 e 8 · parcial B (10.500) com ISS + INSS 11% + IRRF + PCC | 10.500,00 | ISS 525 · INSS 1.155 · IRRF 157,50 · PCC 488,25 | 8.174,25 | 42091022213671448000189000000000000826098150075743 |

Todas com `cStat 100` (a 7 com 101 = substituição), retorno via webhook (`callback_recebido_em`), XML e DANFSe no bucket privado (`<tenant>/<empresa>/NFSH-<solicitação>/nfse.xml|danfse.pdf`), `nfse_status` do documento mantido em `RASCUNHO` (homologação não fatura; decisão A). A NFS-e 4 ficou `SUBSTITUIDA`; a 5 tem evento `CANCELAMENTO/AUTORIZADA` com o XML de cancelamento arquivado.

## Cenários

| # | Cenário | Como saiu |
|---|---|---|
| 1 | 14.06 sem retenção, uma linha | NFS-e 1 |
| 2 | 17.09 com ISS retido | NFS-e 3 (ISS retido + IRRF + PCC; tomador fora de Joinville, prestação na sede pela regra `SEDE`) |
| 3 | 17.09 sem retenção | NFS-e 4 (override "não retém" com justificativa; `clientes.iss_retido` continua nulo) |
| 4 | 17.06 com prestação na sede | NFS-e 5 (`cLocPrestacao 4209102`) |
| 5 | 14.06 na planta do cliente fora de Joinville | NFS-e 1 (Tijucas 4218004) e 6/8 (Guaramirim 4206504) |
| 6 | INSS + IRRF + PCC retidos, título líquido | NFS-e 8 (`vRetCP 1155`, `vRetIRRF 157,50`, `vRetCSLL 488,25`, `vLiq 8174,25`). O título líquido com `f.titulo_retencao` está provado pelo caminho de produção no teste SQL (homologação não cria título) |
| 7 | Duas OS do mesmo tomador | NFS-e 2 (OS 288 + 289; cada linha reservou a própria OS) |
| 8 | Parcial em duas NFS-e | NFS-e 6 + 8 na OS 328 (saldo 18.500 → 10.500 → 0, botão "Nova NFS-e parcial") |
| 9 | Tomador de Joinville sem IM | Bloqueado antes da Focus na OS 183 (TOX): pendência `cliente · inscricao_municipal` com rota para o cadastro |
| 10 | `iss_retido` indefinido | Bloqueado na OS 327 (Portobello sem decisão): quatro pendências; override sem justificativa bloqueia; com justificativa passa |
| 11 | Rejeição com DPS queimada e saldo devolvido | Executado de verdade nove vezes (tabela acima): `REJEITADA`, log `REJEITADO`, saldo devolvido, retry com número novo |
| 12 | Cancelamento | NFS-e 5: `DELETE /v2/nfsen`, corpo `cancelado`, emissão/solicitação `CANCELADA`, log `CANCELADO`, saldo da OS 302 devolvido, `cancelamento.xml` arquivado |
| 13 | Substituição migrando saldo e título | NFS-e 7 substitui a 4: clone conferido e emitido com `chave_nfse_substituida`, antiga `SUBSTITUIDA`, dois eventos `SUBSTITUICAO` (código 99), reserva da OS 145 só na nova; migração do título provada no SQL |
| 14 | Retry mesma referência, webhook duplicado, reconciliação | Retry idempotente e webhook duplicado provados no SQL; webhook real recebido nas 8 notas; reconciliação por cron (`nfe-reconciliar`, bloco NFS-e) não foi exercitada com webhook desligado |

Aceite dos PDFs: DANFSe da NFS-e 1 comparado com a NFS-e 35 real (mesmo tomador, 14.06): prestador, tomador (endereço agora igual), cTribNac 14.06.01, NBS 1.2003.29.00, local Tijucas, ISS 5% não retido, "PIS/COFINS/CSLL Não Retidos", totais aproximados presentes. Diferenças: o DANFSe da Focus traz o grupo IBS/CBS (CST 000, cClassTrib 000001, cIndOp 050103) que a NFS-e 35 não tinha; a base do IBS/CBS exclui o ISS (9.668,46). NFS-e 3 vs NFS-e 39 real (17.09 INCASA): mesmas retenções (`tpRetISSQN 2`, `tpRetPisCofins 3`, `vRetIRRF`, `vRetCSLL` = soma), mesmo cTribNac/NBS.

## Efeitos no banco e limpeza

- As homologações das OS 327, 288/289, 270, 145 e 328 foram **abandonadas** pela ação "abandonar homologação" (a NFS-e continua autorizada no ambiente nacional de homologação; só o saldo volta). Saldos finais: OS 327 = 10.177,33; 288 = 9.000; 289 = 70.600; 270 = 25.000; 145 = 32.494; 328 = 18.500; 302 = 5.987,89 (cancelada).
- `c.empresa_fiscal.proximo_numero_dps` = 18 (série 2). Antes da primeira NFS-e real decidir se produção começa em 1 (pergunta 20).
- Cadastro alterado: cliente 1 (Portobello) CEP 88200122 / ROD GOVERNADOR MARIO COVAS / KM 163 (igual à NFS-e 35 real). Nenhum `clientes.iss_retido`/`retem_*` gravado.
- Rascunho `NFSH-804c3450…` (OS 327) ficou `REJEITADA`/abandonado; não reserva saldo.

## Decisões tomadas (para revisão)

- Uma única sequência de DPS (série 2) para homologação e produção.
- Prazo de cancelamento vazio: homologação mostra o botão com aviso; produção oculta até o contador confirmar.
- Retenções: regra do perfil/fixture → cadastro do cliente → override na nota com justificativa (vai para a discriminação como "RETENCAO AJUSTADA: …"). Base do INSS = valor bruto (simplificação).
- Payload: sem IM, nome e endereço do prestador; sem alíquota de ISS; com totais aproximados; `cIndOp` provisório; `codigo_verificacao` devolvido pela Focus é a própria chave.
- Discriminação (≤1000, maiúsculas): `<DESCRIÇÃO> - OS <n>. PEDIDO DE COMPRA: <n> [ITEM <n>]. VENCIMENTO: <dias> DDL (<datas>). ISS RETIDO PELO TOMADOR|RECOLHIDO PELO PRESTADOR. <texto de retenção>. <observação> [RETENCAO AJUSTADA: …]`.

## Perguntas que sobraram para o contador (renumeradas; o plano citado na tarefa não existe no repositório)

| # | Pergunta | O que trava |
|---|---|---|
| 13 | Código nacional por serviço: 14.06 → 140601, 17.09 → 170901, 14.01 → 140101, 07.02 → 070201 conferem? O 17.06 (170601) do emissor antigo é "propaganda e publicidade" na LC 116; assessoria técnica não seria 17.01? | Perfis sem valor; homologação usa a fixture |
| 14 | NBS por serviço (14.06: 120032900 × 101061900/101026900; 17.09/17.06: 114044900; 14.01 sem NBS) | `codigo_nbs` dos perfis |
| 15 | Local de incidência e alíquota: na planta do cliente (Tijucas, Guaramirim, São Francisco do Sul 3%) o ISS é do município do tomador? O ambiente nacional parametrizou 5% para Tijucas e Guaramirim nas notas de hoje | `local_prestacao_regra` |
| 16 | Retenções federais por serviço/tomador (IRRF 1,5% e PCC 4,65% nos laudos; nunca em 14.06/14.01?) e texto legal da discriminação | `retencao_*_regra`, `texto_complementar` |
| 17 | INSS 11%: em quais serviços e sobre qual base (bruto ou só mão de obra) | `retencao_inss_regra`, `permite_deducao_material` |
| 18 | Prazo de cancelamento da NFS-e Nacional em Joinville e códigos de substituição aceitáveis | `prazo_cancelamento_nfse_horas` |
| 19 | PIS/COFINS próprios (CST 01, 1,65%/7,60%) e IBS/CBS 2026 (000/000001, 0,10%/0,90%) em serviços; `cIndOp` correto por serviço (hoje 050103, e 040101 na obra) | `cst_ibs_cbs`, `cclass_trib`, `cIndOp` |
| 20 | Série da DPS (2) e se a produção começa em 1 | `serie_dps`, `proximo_numero_dps` |
| 21 | Perfil 07.02 (obra): dados da obra e retenções obrigatórios para desbloquear | `SEG-NFSE-0702` |
| 22 | Totais aproximados dos tributos (Lei 12.741): usar IBPT como o emissor antigo (13,45% federal) ou PIS+COFINS+ISS como hoje | `valor_total_tributos_*` |
| 23 | Inscrição municipal 152836: confirmada para a Elétrica Segau (a SGU fica de fora por ora) | `c.empresa_fiscal.inscricao_municipal` |

## Como reproduzir

```
node scripts/chrome-os-nfse-homologacao.mjs --os 326 --perfil 14.06 --dias 45 --so-conferir                     # bloqueio 10
node scripts/chrome-os-nfse-homologacao.mjs --os 326 --perfil 14.06 --dias 45 --iss nao --pcc nao --irrf nao --inss nao --justificativa "..." --obs "..."
node scripts/chrome-os-nfse-homologacao.mjs --os 287 --perfil 14.06 --add-os 289 --valor 4000 --valor2 6000 --iss nao --pcc nao --irrf nao --inss nao --justificativa "..."
node scripts/chrome-os-nfse-homologacao.mjs --os 269 --perfil 17.09 --valor 3000 --iss sim --pcc sim --irrf sim --inss nao --justificativa "..."
node scripts/chrome-os-nfse-homologacao.mjs --os 327 --perfil 14.06 --nova --valor 10500 --iss sim --pcc sim --irrf sim --inss sim --justificativa "..."
node scripts/chrome-os-nfse-homologacao.mjs --os 182 --perfil 17.09 --so-conferir                                # bloqueio 9 (sem IM)
node scripts/chrome-os-nfse-homologacao.mjs --os 301 --perfil 17.06 --cancelar "..."                             # cancelamento
node scripts/chrome-os-nfse-homologacao.mjs --os 164 --perfil 17.09 --substituir "..."                           # substituicao
node scripts/chrome-os-nfe-arquivos.mjs 327 <pasta>                                                              # DANFSe/XML pela tela
node scripts/chrome-os-nfe-abandonar.mjs 327                                                                     # devolve o saldo
node scripts/nfse-retencoes-por-tomador.mjs 2026-07-01 2026-08-31
node scripts/nfse-webhook-registrar.mjs
docker run --rm -i -e PGPASSWORD=postgres postgres:16-alpine psql -h host.docker.internal -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -q < supabase/tests/faturamento_os_nfse_homologacao.sql
npm run test:nfse-pipeline && npm run test:nfe-pipeline
```
