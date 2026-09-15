export function upper(value: unknown): string {
  return String(value ?? "").toUpperCase();
}

export function upperTrim(value: unknown): string {
  return String(value ?? "")
    .trim()
    .toUpperCase();
}

export function upperOrNull(value: unknown): string | null {
  const normalized = upperTrim(value);
  return normalized ? normalized : null;
}

/**
 * Gemea em TypeScript de public.fn_texto_busca: tira acento e sobe pra
 * maiuscula. Use nos dois lados da comparacao — o termo digitado passa por
 * aqui, e a coluna gerada `nome_busca` (itens e fornecedores) ja vem assim do
 * banco. Sem isso, "armario" nao acha ARMÁRIO.
 */
export function textoBusca(value: unknown): string {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
}
