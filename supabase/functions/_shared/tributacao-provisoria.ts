// PROVISORIO: somente HOMOLOGACAO. Espelha
// supabase/tests/fixtures/tributacao-provisoria.json e foi inferido das NF-e
// de agosto/2026. Remover quando f.perfil_operacao assumir a configuracao.
export const tributacaoProvisoria = {
  naturezasOperacao: {
    VENDA_MERCADORIA_TERCEIROS: "VENDA MERCADORIA ADQ. REC. DE TERCEIROS",
    VENDA_INDUSTRIALIZACAO_INTERNA: "VENDA INDUSTRIALIZACAO DENTRO ESTADO",
    VENDA_INDUSTRIALIZACAO_INTERESTADUAL: "VENDA INDUSTRIALIZACAO FORA DO ESTADO",
    DEVOLUCAO_COMPRA_INDUSTRIALIZACAO: "DEVOLUCAO DE COMPRA PARA INDUSTRIAL.",
    REMESSA_INDUSTRIALIZACAO_ENCOMENDA: "REMESSA PARA INDUSTRIALIZACAO POR ENCOME",
    RETORNO_INDUSTRIALIZACAO: "RETORNO DE MERCAD. UTILIZADA NA INDUST.",
    OUTRAS_SAIDAS_INTERESTADUAL: "OUTRAS SAIDAS FORA DO ESTADO",
    REMESSA_CONTA_ORDEM_TERCEIRO: "REMESSA MERCA POR CONTA E ORDEM TERCEIRO",
    ESTORNO_NFE_FORA_PRAZO: "999 - ESTORNO DE NF-E NAO CANCELADA NO PRAZO LEGAL",
  },
  // beneficioReducaoSc saiu daqui em 04/09/2026. Era inferencia por natureza e
  // por aliquota abaixo de 17%, e disparava o texto de base reduzida em NCM que
  // nao tem o beneficio. A regra real e por NCM e esta em
  // ./fiscal/icms-sc-destinacao.ts, com a base legal do documento da
  // contabilidade (docs/faturamento/regras-icms-sc-contabilidade.md).
  ipiPorCfop: {
    // PROVISORIO: pergunta 4 ao contador. Nao promover para perfil sem confirmacao fiscal.
    "5102": {
      cst: "53",
      cEnq: "999",
      provisorio: true,
      pendenciaContador:
        "Pergunta 4: confirmar CST IPI 53 e cEnq 999 para revenda CFOP 5102 antes de liberar o perfil fiscal.",
    },
  },
  padrao: {
    cfopInterno: "5102",
    cfopExterno: "6102",
    icmsSituacaoTributaria: "00",
    icmsAliquotaInterna: 17,
    icmsAliquotaExterna: 12,
    ipiSituacaoTributaria: "53",
    pisSituacaoTributaria: "01",
    pisAliquota: 1.65,
    cofinsSituacaoTributaria: "01",
    cofinsAliquota: 7.6,
  },
  ipi: { ipiSituacaoTributaria: "50", ipiAliquota: 5 },
  baseReduzida: {
    icmsSituacaoTributaria: "20",
    icmsReducaoBaseCalculo: 41.1765,
    icmsAliquotaInterna: 17,
    icmsAliquotaExterna: 12,
  },
} as const;

export type CenarioHomologacao = "simples" | "varios_itens" | "ipi" | "desconto" | "frete" | "base_reduzida";
