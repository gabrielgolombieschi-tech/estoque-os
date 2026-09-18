/** Mesma regra de public.fn_item_busca_normalizar, usada nas consultas de itens. */
export function normalizarBuscaItem(value: unknown): string {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/(\d),(?=\d)/g, "$1.")
    .replace(/\s+/g, " ")
    .trim();
}

export function termosBuscaItem(value: unknown): string[] {
  return [...new Set(normalizarBuscaItem(value).trim().split(/\s+/).filter(Boolean))];
}

/** Todos os termos devem aparecer, em qualquer ordem e em qualquer dos campos. */
export function correspondeBuscaItem(values: unknown[], term: unknown): boolean {
  const texto = normalizarBuscaItem(values.map((value) => String(value ?? "")).join(" "));
  return termosBuscaItem(term).every((parte) => texto.includes(parte));
}

type ConsultaIlike<T> = { ilike: (column: string, pattern: string) => T };

/**
 * Filtra no banco antes de limit/range/count. A coluna deve conter o texto já
 * normalizado; busca_item inclui ID/códigos/nome/fabricante e nome_item_busca só nome.
 */
export function aplicarBuscaItem<T extends ConsultaIlike<T>>(
  query: T,
  term: unknown,
  column = "busca_item"
): T {
  for (const parte of termosBuscaItem(term)) {
    // O texto digitado é literal: %, _ e \ não viram curingas SQL.
    const literal = parte.replace(/[\\%_]/g, "\\$&");
    query = query.ilike(column, `%${literal}%`);
  }
  return query;
}
