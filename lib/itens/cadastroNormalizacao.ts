// Compartilhado entre formulário e API; sem dependências de servidor.
export const ORIGENS_MERCADORIA = [
  { value: "0", label: "0 - Nacional" },
  { value: "1", label: "1 - Estrangeira, importação direta" },
  { value: "2", label: "2 - Estrangeira, adquirida no mercado interno" },
  { value: "3", label: "3 - Nacional, conteúdo de importação superior a 40% e até 70%" },
  { value: "4", label: "4 - Nacional, conforme processos produtivos básicos" },
  { value: "5", label: "5 - Nacional, conteúdo de importação até 40%" },
  { value: "6", label: "6 - Estrangeira, importação direta, sem similar nacional" },
  { value: "7", label: "7 - Estrangeira, mercado interno, sem similar nacional" },
  { value: "8", label: "8 - Nacional, conteúdo de importação superior a 70%" },
] as const;

export function origemFiscalConfirmada(value: unknown): number | null {
  if (value == null || value === "") return 0;
  if (typeof value !== "number" && typeof value !== "string") return null;
  const origem = Number(value);
  return Number.isInteger(origem) && origem >= 0 && origem <= 8 ? origem : null;
}

/**
 * Converte a origem que o FORNECEDOR declarou na nota dele para a origem que NOS
 * declaramos ao vender.
 *
 * A origem e sempre do ponto de vista de quem emite: o fornecedor dizendo "1 -
 * importacao direta" esta dizendo que ELE importou. Para nos, que compramos dele
 * aqui dentro, a mesma mercadoria e "2 - estrangeira, adquirida no mercado
 * interno". So esse par muda de dono (e o 6/7, que e o mesmo caso na lista CAMEX);
 * as demais origens sao caracteristica da mercadoria e atravessam iguais.
 *
 * Copiar o 1 do fornecedor fazia a nossa nota afirmar uma importacao que nao houve
 * — e como e da origem que sai a equiparacao a industrial, o erro virava IPI
 * cobrado indevidamente na revenda (NF-e 2/50, 11/09/2026).
 *
 * Nao serve para importacao propria: ali nao ha nota de fornecedor, a entrada e por
 * DI, e a origem 1 e declarada a mao junto com a equiparacao.
 */
export function origemSaidaDeOrigemEntrada(origemEntrada: unknown): number | null {
  const origem = origemFiscalConfirmada(origemEntrada);
  if (origem === null) return null;
  if (origem === 1) return 2;
  if (origem === 6) return 7;
  return origem;
}

export function normalizarConversaoCadastro(estoque: string, compra: string | null, fator: number | null) {
  const unidadeEstoque = estoque.trim().toUpperCase() || "UN";
  const unidadeCompra = compra?.trim().toUpperCase() || null;
  // Sem unidade comercial distinta, não há conversão de quantidade/preço.
  if (!unidadeCompra) return { unidade_compra: null, fator_conversao_estoque: 1, erro: null };
  if (fator === null || !Number.isFinite(fator) || fator <= 0) {
    return { unidade_compra: unidadeCompra, fator_conversao_estoque: fator, erro: "Informe um multiplicador maior que zero para converter a unidade de compra em unidade de estoque." };
  }
  if (unidadeCompra === unidadeEstoque) {
    if (fator !== 1) return { unidade_compra: unidadeCompra, fator_conversao_estoque: fator, erro: "As unidades de compra e estoque são iguais, mas o multiplicador é diferente de 1. Corrija o multiplicador para 1 ou informe a unidade de compra correta (por exemplo, CX ou RL)." };
    return { unidade_compra: null, fator_conversao_estoque: 1, erro: null };
  }
  return { unidade_compra: unidadeCompra, fator_conversao_estoque: fator, erro: null };
}
