# Perfis de serviço da NFS-e — o que mudou em 06/09/2026

Base: estudo das 29 NFS-e (12–40) e 8 NF-e (3765–3772) de agosto/2026, documento do contador de 24/11/2021 e legislação vigente em 05/09/2026. Migrations `20260906090000_nfse_perfis_servico.sql` e `20260906100000_nfse_sgu_sem_perfis.sql`, aplicadas local → dry-run → push. Commit no fim deste arquivo.

## Resultado em uma frase

Os quatro perfis (14.06, 14.01, 17.09, 07.02) têm valores gravados por revisão auditada; 14.06 e 14.01 estão com campos travados (CONFERIR_08_09) que barram a produção sem barrar a homologação; a discriminação é composta por template e recusa "MÃO DE OBRA"; IBS/CBS e vTotTrib saem de tabela e reproduzem as notas reais no centavo; o IPI passou a integrar a base do ICMS na NF-e para consumidor final.

## Critério de pronto (§11) — item a item

| Critério | Estado | Onde |
| --- | --- | --- |
| Quatro perfis com valores | Feito. 14.06, 14.01, 17.09 em REVISAO (revisados, `habilitado_producao=false` até nova homologação + liberação); 07.02 revisado e BLOQUEADO | `scripts/nfse-perfil-revisar.mjs`; eventos REVISAO em `f.perfil_operacao_revisao_evento` |
| DPS e NFS-e independentes + teste | Já eram colunas distintas (`dps_numero` / `nfse_numero`); teste passou a afirmar que a NFS-e 101 não arrasta a DPS 4 | `supabase/tests/faturamento_os_nfse_homologacao.sql` (bloco `autorizada`) |
| Discriminação recusa "MÃO DE OBRA" + teste | Feito: `f.fn_nfse_texto_proibido` (com/sem til, com hífen) na descrição, na observação e no texto composto; revisão do perfil também recusa | migration §3/§6; teste bloco `regras_perfil` |
| IBS/CBS no centavo (notas 32 e 37) | Feito: base = serviço − ISS, arredondamento meio-par (`f.fn_round_half_even`, `arredondarMeioPar`). 3.500 → 3.325 / 3,32 / 29,92; 42.298,75 → 41.029,79 / 41,03 / 369,27 | SQL (bloco `regras_perfil`) e `scripts/test-nfse-pipeline.mjs` |
| vTotTrib de tabela | Feito: `f.nfse_tributos_aproximados` (federal 13,45%; municipal 4,69 / 4,69 / 3,64 / 2,11; estadual 0) com vigência; conferência lê a tabela e só cai no perfil se não houver linha | migration §2/§6 |
| Validação NBS × subitem | Feito: `f.fn_nfse_nbs_compativel` (capítulo 20 para 14.xx, 14 para 17.xx, 01 para 07.xx); recusa na revisão e pendência na conferência (barra o caso da nota 21) | migration §3 |
| 17.06 inexistente | Perfil SEG-NFSE-1706 BLOQUEADO com justificativa; fixture 17.06 desativada; a revisão recusa 17.06 | migration §5/§7 |
| 14.01 nasce com CRF ativa | Feito: `retencao_pcc_regra = SEMPRE` (4,65%), `excecao_conserto_isolado = true`; a flag da OS (`ordens_servico.conserto_isolado`) desliga a CRF e grava a base legal na observação | conferência §6; checkbox na tela |
| Campos CONFERIR_08_09 sinalizados e bloqueando produção | Feito: `perfil_operacao.campos_conferir` (14.06: ISS retido e INSS; 14.01: ISS retido); `fn_perfil_operacao_nfse_liberar_producao` e `fn_nfse_producao_pronta` recusam; `fn_perfil_operacao_nfse_confirmar_campo` destrava com justificativa e evento | migration §5 |
| Nenhuma alíquota de IPI fixada | Mantido: o IPI continua atributo do NCM (cadastro do item); nada semeado | — |
| Nenhum perfil da SGU | Feito: a fundação de 05/09 tinha criado os cinco perfis (e a fixture) também para a SGU; a migration `20260906100000` removeu perfis, fixture e tabelas da SGU (nunca referenciados) | — |
| 84609090 não entra a 12% | Mantido: nenhuma regra nova de ICMS; o 12% desse NCM segue fora (CONFERIR_08_09 no estudo) | `nfe-payload.ts` inalterado nesse ponto |

## O que mais mudou

- **ISS por incidência × subitem** (`f.nfse_aliquota_iss`): 14.01/14.06/17.09 incidem na sede (LC 116 art. 3 caput); 07.02 no município da obra (art. 3 III; São Francisco do Sul 3%, Joinville 5%). A prévia mostra "ISS incide em <IBGE>". Base de retenção = valor integral. IM do tomador segue opcional.
- **Competência** aceita mês anterior; recusa data futura.
- **Dispensa ≤ R$ 10,00** para IRRF, CRF e INSS, com aviso; o cadastro do tomador não é tocado.
- **Tomador optante do Simples** (`clientes.optante_simples`): CRF não se aplica (aviso); nulo gera aviso pedindo o regime. Campo novo no cadastro fiscal do cliente.
- **Template de discriminação por tomador** (`clientes.nfse_discriminacao_template`), segmentos separados por `|`, segmento com campo vazio some. Padrão: `{RESULTADO}. PEDIDO DE COMPRA: {PEDIDO}{ITEM}. VENCIMENTO: {VENCIMENTO} DDL. OS {OS}. "{FRASE_LEGAL}". {OBSERVACAO}`. Várias parcelas viram `14/28 DDL`; à vista some o segmento. Sem datas por padrão (token `{DATAS}` disponível).
- **Frases legais** por perfil (`texto_complementar`): 14.01/14.06 "NAO HA INCIDENCIA DAS RETENCOES FEDERAIS CONFORME IN SRF N 459/2004"; 17.09 a frase de laudos com "LEI 12.741/2012" (a fixture tinha "LEI 12/2012", corrigido); 07.02 vazio.
- **cIndOp** sem default no perfil: perfil revisado sem cIndOp não emite (`nfse-payload.ts`) e vira pendência a partir de 01/10/2026 (aviso antes). A fixture mantém o provisório (040101 / 050103) só até 30/09/2026.
- **NF-e: IPI na base do ICMS para consumidor final** (`nfe-payload.ts`): NF-e 3766 reproduzida (69.232,80 + 6.750,20 = 75.983,00 × 17% = 12.917,11); revenda continua sem IPI na base. Teste em `scripts/test-nfe-pipeline.mjs` (77 cenários).
- **Tela da OS**: mostra perfil revisado (cTribNac, NBS, ISS e incidência, cIndOp), campos travados, checkbox "conserto isolado" (14.01), IBS/CBS e tributos aproximados na prévia, origem dos valores (perfil × fixture). Regras de retenção passam a vir do perfil revisado.
- **Descrição padrão do 14.06** trocada de "SERVICOS MAO DE OBRA ELETRICISTA" para "INSTALACAO E MONTAGEM DE EQUIPAMENTOS ELETRICOS" (a antiga seria recusada).

## Conferido no projeto (06/09/2026, 03h)

- Revisões gravadas: SEG-NFSE-1406 (2 campos travados), SEG-NFSE-1401 (1 travado, CRF SEMPRE, conserto isolado), SEG-NFSE-1709, SEG-NFSE-0702 (BLOQUEADO). Todos com `habilitado_producao=false`.
- Conferência real da OS 319 (Portobello) pelo navegador com o 14.06 revisado, sem emitir: fonte PERFIL, ISS 5% incidindo em 4209102 com prestação em 4218004, líquido 18.166,99, discriminação `MANUTENCAO DO PAINEL DE DISTRIBUICAO. PEDIDO DE COMPRA: 4500123. VENCIMENTO: 45 DDL. OS 319. "NAO HA INCIDENCIA DAS RETENCOES FEDERAIS CONFORME IN SRF N 459/2004"`, aviso dos campos travados. Rascunho descartado depois (`scripts/nfse-rascunho-descartar.mjs`), saldo devolvido. Um rascunho criado por engano na OS 320 (Cremer, id 319) foi descartado do mesmo modo; a conferência dele recusou "MAO DE OBRA DE PROGRAMAÇÃO" como esperado.
- Testes: 10 suítes SQL de faturamento OK; 77 cenários NF-e e 13 NFS-e OK; `tsc` e `eslint` limpos. Edge Functions publicadas: nfse-emitir, nfe-emitir, nfe-emitir-producao.

## Conflito com o enunciado (decidido em 06/09/2026)

A tarefa dizia "FOCUS_NFE_PRODUCAO_ENABLED permanece false" e "HOMOLOGACAO continua o único liberado". Em 05/09 a produção foi habilitada pelo Gabriel (NF-e e NFS-e reais emitidas e canceladas) e em 06/09 ele confirmou: **o secret fica `true`**. A trava efetiva de produção é o perfil: nenhum perfil de serviço está liberado (14.06 perdeu a liberação ao ser revisado e ainda tem campos travados), e a emissão em produção continua exigindo homologação AUTORIZADA da mesma solicitação + liberação auditada + `fn_nfse_producao_pronta`.

## Para 08/09 (confirmação dos campos travados)

```
f.fn_perfil_operacao_nfse_confirmar_campo(<perfil_id>, 'iss_retido_regra', '<justificativa>')
f.fn_perfil_operacao_nfse_confirmar_campo(<perfil_id>, 'retencao_inss_regra', '<justificativa>')
```

Depois: homologar a mesma solicitação (NFS-e AUTORIZADA em HOMOLOGACAO após a revisão) e `fn_perfil_operacao_nfse_liberar_producao`.

## Perguntas ao contador (acumuladas)

1. NBS do 14.06: 1.2003.29.00 (todas as notas) ou 1.0102.69.00 (nota 21)? O ERP barra a segunda.
2. 07.02: confirmar ISS 3% em São Francisco do Sul e retenção pelo tomador; INSS 11% sobre o valor integral (nota 37 reteve R$ 0,23 a menos).
3. PIS/COFINS próprios da NFS-e no Lucro Real: 0,65%/3,00% (como saem as notas) ou 1,65%/7,60%?
4. Grupo IBS/CBS antes de 01/10/2026: por que só as notas 32 e 37 o levam? O ERP envia sempre (CST 000 / 000001 / cIndOp do perfil).
5. cIndOp por perfil: 050103 para 14.xx e 17.09, 040101 para 07.02 — confirmar a tabela.
6. Prazo normativo de cancelamento da NFS-e Nacional em Joinville (o ERP usa 24h configuráveis em `c.empresa_fiscal`).
7. Templates ArcelorMittal e Regional Telhas: texto exato para cadastrar em `clientes.nfse_discriminacao_template`.
