# Perguntas ao contador — NFS-e e NF-e da Segau (06/09/2026)

> **Respondidas em 06/09/2026.** As respostas e o que mudou no ERP estão em [respostas-contador-2026-09-06.md](respostas-contador-2026-09-06.md).

Texto pronto para enviar. Cada item diz o que o ERP faz hoje e pede um sim/não. Os campos do ERP marcados com **(travado)** ficam como estão até a resposta; a produção desses perfis não abre sem essa confirmação.

---

Olá! Estamos fechando as regras fiscais do nosso emissor de NFS-e (Padrão Nacional) e da NF-e de industrialização. Baseamos tudo nas notas de agosto/2026 e no documento de vocês de 24/11/2021. Preciso de um sim/não em cada ponto (e a correção, se for não):

**1. ISS nos serviços 14.01 (manutenção) e 14.06 (instalação/montagem)** — (travado)
Hoje: a Segau recolhe o ISS (5%, Joinville), sem retenção pelo tomador, como saiu nas notas de agosto.
Está certo para tomadores de Joinville e de fora (Tijucas, São Francisco do Sul)? Existe algum tomador que deva reter?

**2. INSS 11% no 14.06 (instalação/montagem na planta do cliente)** — (travado)
Hoje: sem retenção de INSS, como nas notas de agosto.
Está certo? Em que situação a nossa instalação vira "cessão de mão de obra" ou "empreitada" (IN RFB 2110/2022, art. 111 e 112) e passa a ter os 11%?

**3. CRF 4,65% (PIS/COFINS/CSLL) no 14.01 (manutenção)**
Hoje: retemos por padrão (IN SRF 459/2004) e só dispensamos quando a OS é conserto isolado de um bem com defeito (art. 1º, §2º, II) ou o tomador é do Simples. As notas de agosto do 14.01 não retiveram.
Qual é o padrão correto: reter ou não reter?

**4. NBS do 14.06**
Todas as notas usaram 1.2003.29.00; só a nota 21 usou 1.0102.69.00. Qual é o certo? (O ERP hoje só aceita 1.2003.29.00.)

**5. Obra (07.02, nota 37, São Francisco do Sul)**
Hoje: ISS 3% no município da obra, retido pelo tomador; INSS 11% sobre o valor integral; sem IRRF e sem CRF. A nota 37 reteve R$ 0,23 a menos de INSS.
Confirma essas quatro regras? O perfil só sai do bloqueio com essa resposta.

**6. PIS e COFINS próprios na NFS-e**
As notas saem com 0,65% e 3,00%. Como somos Lucro Real, o correto é 0,65%/3,00% ou 1,65%/7,60%?

**7. IBS/CBS**
Só as notas 32 e 37 de agosto levaram o grupo IBS/CBS. O ERP já manda em todas: CST 000, cClassTrib 000001, IBS 0,10%, CBS 0,90%, base = serviço − ISS.
Pode mandar em todas desde já? E o cIndOp: 050103 para 14.01/14.06/17.09 e 040101 para 07.02 está certo?

**8. Frases nas notas**
14.01 e 14.06: "NÃO HÁ INCIDÊNCIA DAS RETENÇÕES FEDERAIS CONFORME IN SRF N° 459/2004".
17.09 (laudos): "PARA OS SERVIÇOS DE LAUDOS E PERÍCIAS, DEVERÁ SER RETIDO IRRF À ALÍQUOTA DE 1,5% E CRF À ALÍQUOTA DE 4,65% (PIS 0,65%; COFINS 3,0%; CSLL 1%). TRIBUTOS INCIDENTES SOBRE O PREÇO LEI 12.741/2012".
Os textos estão corretos? (Corrigimos "LEI 12/2012" para "LEI 12.741/2012".)

**9. Cancelamento da NFS-e Nacional**
Qual é o prazo para cancelar uma NFS-e em Joinville? Hoje o ERP deixa 24 horas; depois disso só substituição.

**10. NF-e de industrialização (painéis, NCM 8537.20.90 e 8538.90.90)**
Hoje: ICMS 17% dentro de SC e 12% para o Paraná, base cheia (sem redução, sem cBenef); IPI pela alíquota do NCM; e, para consumidor final (uso/consumo), o IPI entra na base do ICMS, como na NF-e 3766 (69.232,80 + 6.750,20 = 75.983,00 × 17%).
Confirma? E o NCM 8460.90.90 pode sair a 12% dentro de SC ou fica em 17%?

Obrigado!

---

## Depois da resposta

- Itens 1 e 2 confirmados: rodar `f.fn_perfil_operacao_nfse_confirmar_campo` nos perfis SEG-NFSE-1406 (`iss_retido_regra`, `retencao_inss_regra`) e SEG-NFSE-1401 (`iss_retido_regra`), depois homologar e liberar.
- Item 5 confirmado: tirar o SEG-NFSE-0702 de BLOQUEADO e homologar.
- Itens 3, 4, 6, 7, 8: ajustar pelo `scripts/nfse-perfil-revisar.mjs` (nova revisão auditada).
- Item 9: ajustar `c.empresa_fiscal.prazo_cancelamento_nfse_horas`.
- Item 10: mexer só no perfil de NF-e e no cadastro do item; nenhuma alíquota de IPI fixada no ERP.
