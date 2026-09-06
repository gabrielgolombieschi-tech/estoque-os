# Respostas do contador (06/09/2026) e o que mudou no ERP

Perguntas em [perguntas-contador-nfse.md](perguntas-contador-nfse.md). Migration `20260906120000_nfse_respostas_contador.sql`. Cada item: resposta em uma linha, decisão, onde ficou.

| # | Resposta do contador | O que o ERP faz agora | Onde |
| --- | --- | --- | --- |
| 1 | ISS 14.01/14.06 sempre Joinville, sem retenção. Exceção: tomador substituto tributário (órgão público, banco, hospital, concessionária) retém. | Perfis 14.01/14.06 com `iss_retido_regra = NUNCA`. Cadastro do cliente ganhou **Substituto tributário do ISS**; com a marca, a nota sai com ISS retido (aviso), e a tela pode desligar com justificativa. Campo travado do ISS confirmado nos dois perfis. | `clientes.iss_substituto_tributario`; conferência; cadastro fiscal do cliente |
| 2 | INSS 14.06 sem retenção (empreitada com escopo fechado). Retém só em cessão de mão de obra (a Segau não faz) ou obra civil (que é 07.02). | 14.06 segue `retencao_inss_regra = NUNCA`; campo travado confirmado. Obra civil continua no perfil 07.02 (INSS 11% SEMPRE). | perfis |
| 3 | CRF 14.01 com retenção por padrão; exceções: conserto isolado, tomador do Simples, retenção ≤ R$ 10,00 (nota ≤ R$ 215,05). Notas de agosto sem retenção só valem se caírem numa exceção. | Já era assim. Agora a frase da nota muda pelo motivo (ver 8) e o motivo fica gravado (`motivo_dispensa_pcc`). | conferência |
| 4 | NBS 14.06 = 1.2003.29.00 (nota 21 estava errada). Obra elétrica é 07.02 com NBS 1.0102.41.00; material discriminado abate a base do ISS e do INSS; a OS deve chegar carimbada "Montagem 14.06" ou "Obra 07.02". | 07.02 com NBS 1.0102.41.00 e `permite_deducao_material = true`. O abatimento de material na DPS fica para a homologação do 07.02 (campo `vDedRed` do leiaute nacional; exige contrato e discriminação). O carimbo é a escolha do perfil na tela da OS. | perfil 07.02 (bloqueado) |
| 5 | 07.02: ISS na obra retido pelo tomador; INSS 11% sobre o valor integral salvo material; sem IRRF; sem CRF. Alíquota de SFS: nota 1646 (cancelada) saiu com 2%, a 37 com 3%; auditar. R$ 0,23 é arredondamento entre sistemas. | Regras confirmadas no perfil. Alíquota 3% mantida na tabela com a pendência de auditoria registrada. 07.02 continua **BLOQUEADO** até auditar SFS e homologar. | `f.nfse_aliquota_iss` (fonte), `justificativa_faixa` |
| 6 | PIS/COFINS próprios no Lucro Real: 1,65% / 7,60%. Os 0,65/3,00 das notas eram a alíquota da retenção espelhada por engano. | Perfis passam a 1,65 / 7,60 (vai na DPS como informativo). A apuração (débito de PIS/COFINS) da NFS-e emitida pelo ERP usa a alíquota da solicitação, nunca a linha de retenção nem o fallback 0,65/3,00. Notas importadas do emissor antigo seguem como estavam (ver pendências). | `fn_nfse_sync_piscofins_debito_doc` |
| 7 | IBS/CBS em todas as notas (obrigatório desde 01/08/2026); CST 000, cClassTrib 000001, 0,10/0,90, base serviço − ISS: corretos. cIndOp 050103 correto para 14.01/14.06/17.09; **07.02 é 020201** (bem imóvel), não 040101 (feiras e eventos). | 07.02 com cIndOp 020201 no perfil e na fixture. NFS-e 37 real saiu com 040101: errada. | perfil, fixture, `nfse-payload.ts` |
| 8 | IN SRF 459/2004 foi revogada: citar IN RFB 2.141/2023. 14.01 não pode levar "não incidência" por padrão. Textos sugeridos para 14.06, 14.01 (conserto isolado) e 17.09 (com Art. 714 do RIR/2018 e o valor da Lei 12.741). | Perfil ganhou `texto_sem_retencao`. 14.06: "Serviço não sujeito à retenção de PIS/COFINS/CSLL, conforme IN RFB nº 2.141/2023." 14.01: frase da regra geral com CRF; sem retenção, a frase do motivo (conserto isolado, Simples, ≤ R$ 10). 17.09: frase de laudos com `{VTOTTRIB}` preenchido pela tabela por subitem. | perfis; conferência |
| 9 | Joinville (Decreto 30.798/2018): cancelamento direto até o fechamento da competência; por protocolo + substituição até 30 dias após o vencimento; depois, processo. As 24 h eram trava do ERP. | Regra nova `MES_EMISSAO` em `c.empresa_fiscal`: cancelar direto até o último dia do mês de emissão; depois, substituição. Segau configurada assim; `HORAS` continua disponível. | `fn_nfse_cancelamento_claim`, tela da OS |
| 10 | Painéis (8537.20.90, 8538.90.90): 17% SC / 12% PR, base cheia, IPI na base do ICMS para consumidor final: tudo confirmado. NCM 8460.90.90: Convênio ICMS 52/91, CST 20, cBenef do convênio, base reduzida para carga efetiva 8,80% (interna e interestadual). | Montador da NF-e recusa 8460.90.90 fora desse formato (CST 20 + cBenef + carga 8,80%). O código do cBenef não foi informado: precisa estar no cadastro do item. | `nfe-payload.ts`, `icms-sc-destinacao.ts` |

## Frases que o ERP grava (texto exato)

- **14.06** (sempre): "Serviço não sujeito à retenção de PIS/COFINS/CSLL, conforme IN RFB nº 2.141/2023."
- **14.01 com CRF**: "Serviço sujeito à retenção de CRF (4,65%, sendo PIS 0,65%, COFINS 3,0% e CSLL 1,0%) conforme IN RFB nº 2.141/2023." (derivada da frase do 17.09 do contador, sem o IRRF)
- **14.01 conserto isolado**: "Serviço de conserto isolado não sujeito à retenção de PIS/COFINS/CSLL, conforme art. 2º, § 2º, inciso II, da IN RFB nº 2.141/2023."
- **14.01 tomador do Simples**: "Tomador optante pelo Simples Nacional: dispensada a retenção de PIS/COFINS/CSLL, conforme IN RFB nº 2.141/2023."
- **14.01 retenção ≤ R$ 10**: "Retenção de PIS/COFINS/CSLL dispensada: valor igual ou inferior a R$ 10,00, conforme IN RFB nº 2.141/2023."
- **17.09**: "Serviço sujeito à retenção de IRRF (1,5%) conforme Art. 714 do RIR/2018, e CRF (4,65%, sendo PIS 0,65%, COFINS 3,0% e CSLL 1,0%) conforme IN RFB nº 2.141/2023. Valor aproximado dos tributos conforme Lei 12.741/2012: R$ X,XX."
- **07.02**: sem frase.

## Estado dos perfis depois disto

Campos travados confirmados (ISS no 14.01 e 14.06; INSS no 14.06) com a resposta do contador como justificativa, e os quatro perfis re-revisados com os valores acima. Toda revisão zera a liberação de produção: **nenhum perfil de serviço está liberado**. Para emitir NFS-e real: homologar uma nota com o perfil revisado e liberar (auditado). 07.02 segue bloqueado.

## Segunda rodada (06/09/2026, tarde) — migration `20260906140000_nfse_deducao_material.sql`

| Pendência | Resposta do contador | O que o ERP faz agora |
| --- | --- | --- |
| Abatimento de material no 07.02 | Pode: LC 116/2003, art. 7º, § 2º, I. Na DPS é o "valor das deduções", motivo Materiais. O contador ainda orienta se o material sai do estoque por NF-e de remessa. | Campo **Material fornecido e incorporado à obra** na tela da OS, só em perfil com `permite_deducao_material` (07.02). Sai da base do ISS e do INSS; IRRF e CRF seguem sobre o valor integral. Vai na DPS como `valor_deducao_servico`, na emissão como `valor_deducoes` e na discriminação como "MATERIAL APLICADO: R$ …". Material igual ou maior que o serviço bloqueia. |
| Notas de agosto do 14.01 sem CRF | Pode auditar: tomador fora do Simples, nota acima de R$ 215,05 e não conserto isolado = saiu errada; avisar o contador para somar os 4,65% no DARF. | Auditoria feita pelo XML das notas: [auditoria-crf-1401-agosto-2026.xlsx](auditoria-crf-1401-agosto-2026.xlsx). Duas notas 14.01 em agosto, ambas sem CRF: **31** (Portobello, R$ 11.879,00 → CRF R$ 552,37) e **32** (WEG Tintas, R$ 3.500,00 → CRF R$ 162,75). Total R$ 715,12 se nenhuma for conserto isolado. A nota 24 (Portobello, R$ 6.500,00) foi codificada 14.06, mas descreve manutenção. |
| Frase do 14.01 com CRF | Confirmada. Texto exato: "SERVIÇO SUJEITO À RETENÇÃO DE CRF À ALÍQUOTA DE 4,65% (PIS 0,65%; COFINS 3,0%; CSLL 1,0%) CONFORME IN RFB N° 2.141/2023. TRIBUTOS INCIDENTES SOBRE O PREÇO CONFORME LEI 12.741/2012." | Gravada no perfil 14.01 e na fixture. |

## Terceira rodada (06/09/2026, noite) — migration `20260906150000_nfse_iss_sfs_2pct.sql`

| Pendência | Resposta do contador | O que o ERP faz agora |
| --- | --- | --- |
| Alíquota do 07.02 em São Francisco do Sul | **2%** (LC municipal, piso para 07.02; a NFS-e 1646 estava certa, a 37 saiu com 3% por erro). | Tabela corrigida para 2%. O perfil 07.02 saiu de BLOQUEADO para REVISAO: pode homologar; produção só depois da liberação. Obra em município sem alíquota cadastrada passa a bloquear a conferência, em vez de usar a do perfil. |
| cBenef do Convênio 52/91 (8460.90.90) | Código da Tabela 5.2 da SEF/SC, vinculado ao Anexo 2, art. 9º do RICMS/SC; o contador extrai o código exato. | Nada parametrizado. Pedido pronto: "Preciso do código cBenef atualizado da Tabela 5.2 referente à redução de base de máquinas industriais do Anexo 2, Art. 9º". Observação: o contador citou o prefixo SC03, mas o cBenef que já usamos para automação (SC820006, do documento dele) começa com SC82. Conferir o prefixo junto com o código. |
| Saída do material da obra | NF-e de produto, CFOP 5.949 (simples remessa para obra), sem ICMS e IPI; serve de prova do material deduzido do ISS e do INSS. | Regras abaixo. O fluxo de remessa 5.949/6.949 existe em `/faturamento/operacoes`, só em homologação: produção é backlog. |
| PIS/COFINS das notas antigas | A nota não muda; o ajuste é na escrituração (EFD-Contribuições), lançando 1,65% e 7,60% em vez do 0,65/3,00 escrito na nota. | O ERP não reescreveu o histórico. Impacto medido abaixo para decidir se a apuração interna do ERP acompanha. |
| Notas 31 e 32 sem CRF | Se foram conserto isolado, formalizar no ERP e na OS física como escudo jurídico. | Nota 31 = OS 291; nota 32 = OS 248. As duas estão sem a marca de conserto isolado. Script `scripts/os-marcar-conserto-isolado.mjs <os_id> "<justificativa>"` grava a marca e a observação. |

### Material da obra: remessa, venda ou dedução

| Situação | Documento | Tributação | Entra na dedução da NFS-e? |
| --- | --- | --- | --- |
| Insumo que a Segau leva para executar a obra e que fica incorporado (cabos, eletrodutos, calhas, disjuntores) | NF-e de simples remessa para obra, CFOP 5.949 (SC) ou 6.949 (outra UF) | Sem ICMS e IPI; o material está no valor da NFS-e | **Sim**: o valor entra em "material fornecido e incorporado à obra" e a remessa é a prova |
| Painel, máquina ou sistema vendido ao cliente, com faturamento parcial e saldo após o start-up | NF-e de venda (industrialização 5.101/6.101 ou revenda 5.102), pela OS ou OV | ICMS e IPI normais; o valor não está na NFS-e | **Não**: já foi tributado na venda; a NFS-e cobre só o serviço |
| Painel enviado por remessa e faturado depois | Remessa 5.949/6.949 na ida; NF-e de venda no faturamento | Remessa sem imposto; venda com ICMS/IPI | **Não** |
| Periféricos e material de instalação de um sistema vendido | Depende: se estão na venda, NF-e de venda; se são insumo do serviço, remessa | Conforme a linha acima | Só a parte que estiver dentro do valor da NFS-e |

Regra prática: **o que está no preço da NFS-e pode ser deduzido e vai por remessa; o que está no preço da NF-e de venda não entra na NFS-e**. O texto de ajuda do campo na tela diz isso.

### PIS/COFINS das NFS-e importadas (janeiro a agosto/2026), apuração interna do ERP

| | Hoje (0,65% / 3,00%) | Lucro Real (1,65% / 7,60%) | Diferença |
| --- | ---: | ---: | ---: |
| PIS | 23.344,19 | 59.258,15 | +35.913,96 |
| COFINS | 107.742,14 | 272.946,62 | +165.204,48 |
| **Total** | **131.086,33** | **332.204,77** | **+201.118,44** |

165 notas importadas, base de R$ 3,59 milhões. O contador diz que a correção é na escrituração; a pergunta que fica é se a apuração do ERP (tela de impostos e projeções) deve mostrar o mesmo número da contabilidade. É uma reescrita de oito meses de apuração: só com decisão explícita.

## Quem emite nota e quem libera perfil (06/09/2026)

Decisão do Gabriel: emitir nota e liberar perfil fiscal ficam com **ADMIN, FINANCEIRO e FATURAMENTO** na empresa. Hoje: Gabriel e Larissa (ADMIN), Deyvison (FINANCEIRO) e Vanessa (FATURAMENTO). Vale para o botão **Faturar** da OS, o quadro **Faturamento da OS por valor** e o menu **Comercial → OV**. DIRETOR (Diogo e Marcelo) não entra na lista.

A tela `/faturamento/perfis` passou a listar também os perfis de serviço (NFS-e), com resumo somente leitura dos campos fiscais e o mesmo bloco de liberação para produção. A **revisão** do perfil de serviço continua por script (`scripts/nfse-perfil-revisar.mjs`), de propósito: os valores ficam ao lado da justificativa do contador e versionados, como os campos de NF-e que vêm de migration.

Ressalva: papel de tenant OWNER, ADMIN ou DIRETOR mantém carta branca no portão antigo do banco. A restrição acima é de tela.

## O que ficou pendente

1. **cBenef do Convênio 52/91** para o NCM 8460.90.90: pedir ao contador o código da Tabela 5.2 (Anexo 2, art. 9º) e conferir o prefixo.
2. **Homologar e liberar os perfis**: nenhum perfil de serviço está em produção. Ordem sugerida: 14.06 (Portobello, OS 319), 14.01, 17.09, 07.02 (com dedução de material).
3. **Remessa para obra em produção**: o fluxo 5.949/6.949 de `/faturamento/operacoes` só roda em homologação.
4. **Apuração interna do ERP para as NFS-e importadas**: decidir se acompanha a escrituração (+R$ 201 mil).
5. **Notas 31 e 32**: marcar conserto isolado nas OS 291 e 248 se for o caso; senão, o contador soma R$ 552,37 e R$ 162,75 no DARF.
6. **Arredondamento** (R$ 0,23 na nota 37): diferença entre sistemas, sem passivo.
