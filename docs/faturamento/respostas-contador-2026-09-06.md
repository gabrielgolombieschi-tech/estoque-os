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

## O que ficou pendente

1. **Alíquota do 07.02 em São Francisco do Sul**: 2% (NFS-e 1646) ou 3% (NFS-e 37). Auditar na prefeitura antes de desbloquear o perfil.
2. **cBenef do Convênio 52/91** para o NCM 8460.90.90: o contador não informou o código. Sem ele a nota não sai.
3. **Abatimento de material no 07.02**: o perfil permite; o campo da DPS (`vDedRed`/documentos) entra na homologação do 07.02.
4. **PIS/COFINS das NFS-e importadas do emissor antigo** (janeiro a agosto/2026): a apuração delas ficou com 0,65/3,00. Se a empresa é Lucro Real não cumulativo, o histórico está subestimado. Decisão do contador antes de refazer.
5. **Notas de agosto do 14.01 sem CRF**: o contador avisa que só estão certas se caírem nas exceções; caso contrário a Segau recolhe o PIS/COFINS/CSLL na apuração. Conferir nota a nota.
6. **Arredondamento** (R$ 0,23 na nota 37): o ERP arredonda meio-para-cima nas retenções; a diferença é entre sistemas, sem passivo. Conciliar no contas a receber quando acontecer.
