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
    // Remessa para conserto (16/09/2026): natOp da NF 3539 do emissor antigo e dos
    // perfis CSV63-017/018. A tributacao esta em ./fiscal/remessa-conserto.ts.
    REMESSA_CONSERTO_INTERNA: "REMESSA PARA CONSERTO DENTRO DO ESTADO",
    REMESSA_CONSERTO_INTERESTADUAL: "REMESSA PARA CONSERTO FORA DO ESTADO",
    RETORNO_INDUSTRIALIZACAO: "RETORNO DE MERCAD. UTILIZADA NA INDUST.",
    // Retorno de mercadoria de terceiros (16/09/2026): a nota espelha a remessa recebida
    // (5901/6901 ou 5915/6915). Tributacao em ./fiscal/retorno-remessa-terceiros.ts, que
    // guarda o mesmo texto e explica os 60 caracteres.
    RETORNO_REMESSA_TERCEIROS: "RETORNO DE MERCADORIA UTILIZADA NA INDUSTRIALIZACAO",
    RETORNO_REMESSA_TERCEIROS_CONSERTO: "RETORNO DE MERCADORIA RECEBIDA PARA CONSERTO",
    // Devolucao de compra (17/09/2026): finNFe 4, espelho proporcional da NF-e de entrada.
    // Tributacao e texto em ./fiscal/devolucao-compra.ts.
    DEVOLUCAO_COMPRA: "DEVOLUCAO DE COMPRA PARA INDUSTRIALIZACAO",
    // Importacao por remessa expressa (17/09/2026): NF-e de ENTRADA (tpNF 0) da mercadoria
    // desembaracada pela DIR. Tributacao e textos em ./fiscal/importacao-remessa.ts.
    IMPORTACAO_INDUSTRIALIZACAO: "COMPRA PARA INDUSTRIALIZACAO - IMPORTACAO",
    IMPORTACAO_COMERCIALIZACAO: "COMPRA PARA COMERCIALIZACAO - IMPORTACAO",
    IMPORTACAO_CONSUMO: "COMPRA DE MATERIAL PARA USO OU CONSUMO - IMPORTACAO",
    IMPORTACAO_ATIVO: "COMPRA DE BEM PARA O ATIVO IMOBILIZADO - IMPORTACAO",
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
