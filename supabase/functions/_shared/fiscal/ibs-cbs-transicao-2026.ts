/**
 * Regra legal permanente do exercicio de 2026 (nao pertence a fixture fiscal provisoria).
 *
 * Base legal:
 * - ADCT art. 125 (EC 132/2023): "Em 2026, o imposto previsto no art. 156-A será
 *   cobrado à alíquota estadual de 0,1%, e a contribuição prevista no art. 195, V,
 *   ambos da Constituição Federal, será cobrada à alíquota de 0,9%."
 * - ADCT art. 125, § 4º, e LC 214/2025 art. 348: o recolhimento fica
 *   dispensado em 2026 para quem cumprir as obrigações acessórias; valores
 *   recolhidos podem ser compensados com PIS/COFINS.
 *
 * As aliquotas mudam durante a transicao. A vigencia fechada abaixo e intencional:
 * uma emissao fora de 2026 deve falhar ate que esta tabela seja revisada.
 */

export type RegraIbsCbsTransicao2026 = {
  readonly naturezaOperacao: string;
  readonly cfops: readonly string[];
  readonly cst: "000";
  readonly cClassTrib: "000001";
  readonly pIBSUF: 0.1;
  readonly pIBSMun: 0;
  readonly pCBS: 0.9;
};

export const IBS_CBS_TRANSICAO_2026 = Object.freeze({
  exercicio: 2026,
  vigenciaInicio: "2026-01-01",
  vigenciaFim: "2026-12-31",
  porNatureza: Object.freeze({
    VENDA_MERCADORIA_TERCEIROS: Object.freeze({
      naturezaOperacao: "VENDA_MERCADORIA_TERCEIROS",
      cfops: Object.freeze(["5102"]),
      cst: "000",
      cClassTrib: "000001",
      pIBSUF: 0.1,
      pIBSMun: 0,
      pCBS: 0.9,
    } satisfies RegraIbsCbsTransicao2026),
    // Venda de producao propria (OS): mesma regra legal de 2026 da venda
    // tributada integralmente (ADCT art. 125). Usada em HOMOLOGACAO pela fixture
    // provisoria; producao continua bloqueada ate o perfil 5101/6101 ser
    // liberado pelo contador (perguntas 4, 2 e 8).
    VENDA_INDUSTRIALIZACAO_INTERNA: Object.freeze({
      naturezaOperacao: "VENDA_INDUSTRIALIZACAO_INTERNA",
      cfops: Object.freeze(["5101"]),
      cst: "000",
      cClassTrib: "000001",
      pIBSUF: 0.1,
      pIBSMun: 0,
      pCBS: 0.9,
    } satisfies RegraIbsCbsTransicao2026),
    VENDA_INDUSTRIALIZACAO_INTERESTADUAL: Object.freeze({
      naturezaOperacao: "VENDA_INDUSTRIALIZACAO_INTERESTADUAL",
      cfops: Object.freeze(["6101"]),
      cst: "000",
      cClassTrib: "000001",
      pIBSUF: 0.1,
      pIBSMun: 0,
      pCBS: 0.9,
    } satisfies RegraIbsCbsTransicao2026),
  }),
});

function anoEmSaoPaulo(dataEmissao: Date) {
  if (!(dataEmissao instanceof Date) || !Number.isFinite(dataEmissao.getTime())) {
    throw new Error("Emissao bloqueada: data de emissao invalida para a regra IBS/CBS.");
  }
  return Number(new Intl.DateTimeFormat("en", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
  }).format(dataEmissao));
}

export function resolverIbsCbsTransicao2026(
  naturezaOperacao: string,
  dataEmissao: Date,
): RegraIbsCbsTransicao2026 {
  const natureza = String(naturezaOperacao ?? "").trim();
  const ano = anoEmSaoPaulo(dataEmissao);
  if (ano !== IBS_CBS_TRANSICAO_2026.exercicio) {
    throw new Error(
      `Emissao bloqueada: a tabela IBS/CBS precisa ser revisada para o exercicio ${ano}; vigencia atual ${IBS_CBS_TRANSICAO_2026.vigenciaInicio} a ${IBS_CBS_TRANSICAO_2026.vigenciaFim}.`,
    );
  }
  const regra = IBS_CBS_TRANSICAO_2026.porNatureza[
    natureza as keyof typeof IBS_CBS_TRANSICAO_2026.porNatureza
  ];
  if (!regra) {
    throw new Error(
      `Emissao bloqueada: natureza da operacao ${natureza || "<vazia>"} sem cClassTrib mapeado para 2026.`,
    );
  }
  return regra;
}

export function validarCfopIbsCbsTransicao2026(
  regra: RegraIbsCbsTransicao2026,
  cfop: string,
) {
  if (!regra.cfops.includes(cfop)) {
    throw new Error(
      `Emissao bloqueada: natureza da operacao ${regra.naturezaOperacao} nao possui cClassTrib aprovado para o CFOP ${cfop}.`,
    );
  }
}

export function calcularIbsCbsTransicao2026(base: number, regra: RegraIbsCbsTransicao2026) {
  const arredondar = (valor: number) => Math.round((valor + Number.EPSILON) * 100) / 100;
  return {
    vIBSUF: arredondar(base * regra.pIBSUF / 100),
    vIBSMun: arredondar(base * regra.pIBSMun / 100),
    vCBS: arredondar(base * regra.pCBS / 100),
  };
}
