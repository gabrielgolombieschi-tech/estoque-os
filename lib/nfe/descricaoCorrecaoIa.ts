export type CorrecaoDescricaoAgente = {
  descricao_origem: string;
  descricao_origem_normalizada: string;
  descricao_corrigida: string;
};

export function erroTabelaCorrecaoAusente(error: { code?: unknown; message?: unknown } | null | undefined) {
  const code = String(error?.code ?? "");
  const message = String(error?.message ?? "").toLowerCase();
  return ["42P01", "PGRST205"].includes(code) || message.includes("parametro_importacao_xml_descricao_ia");
}

export function normalizarDescricaoAprendizado(value: unknown) {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ")
    .slice(0, 500);
}

export function aplicarCorrecoesExatas<T extends { descricao_nf: string }>(
  itens: T[],
  correcoes: CorrecaoDescricaoAgente[]
) {
  const porDescricao = new Map(
    correcoes.map((correcao) => [correcao.descricao_origem_normalizada, correcao.descricao_corrigida] as const)
  );

  return new Map(
    itens.flatMap((item) => {
      const descricaoCorrigida = porDescricao.get(normalizarDescricaoAprendizado(item.descricao_nf));
      return descricaoCorrigida ? [[normalizarDescricaoAprendizado(item.descricao_nf), descricaoCorrigida] as const] : [];
    })
  );
}

export function substituirDescricaoSugestao<T extends { descricao_padronizada: string }>(
  sugestao: T,
  descricaoCorrigida: string
) {
  return { ...sugestao, descricao_padronizada: descricaoCorrigida };
}
