// Quem pode baixar os PDFs de relatorio.
//
// O papel avaliado e o de a.usuario_empresa (o mesmo que
// public.app_contexto_atual() devolve), nao o papel de tenant.
//
// Os dois conjuntos sao diferentes de proposito: o relatorio HH abre valor de
// hora por colaborador, entao fica acima da coordenacao; o PDF do orcamento e
// material comercial, que a coordenacao ja manda para o cliente.
//
// O aplicativo repete essas regras em src/lib/papeis.ts para decidir se mostra
// o botao. Aqui e o que vale: a tela so esconde, a rota barra.

const PAPEIS_ACIMA_DE_COORDENACAO = new Set(["ADMIN", "DIRETOR", "FINANCEIRO", "FATURAMENTO"]);

export function podeBaixarRelatorioHhPdf(papel: string | null | undefined): boolean {
  return PAPEIS_ACIMA_DE_COORDENACAO.has(String(papel ?? "").trim().toUpperCase());
}

export function podeBaixarOrcamentoPdf(papel: string | null | undefined): boolean {
  const normalizado = String(papel ?? "").trim().toUpperCase();
  return PAPEIS_ACIMA_DE_COORDENACAO.has(normalizado) || normalizado === "COORDENACAO";
}
