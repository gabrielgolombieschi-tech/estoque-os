// Mensagem legivel de um erro do Supabase.
//
// PostgrestError e um objeto simples ({ message, details, hint, code }), nao uma
// instancia de Error: telas que testavam `e instanceof Error` caiam no texto
// generico e escondiam a causa. Foi o que aconteceu ao vincular OS na NF-e
// 55/1/3752 (09/09/2026): a tela dizia "Erro inesperado ao salvar a OS vinculada"
// enquanto o banco respondia que a nota nao podia ser alterada diretamente.

export function mensagemErro(cause: unknown, fallback: string): string {
  if (cause instanceof Error && cause.message.trim()) return cause.message;
  if (cause && typeof cause === "object") {
    const erro = cause as { message?: unknown; details?: unknown; hint?: unknown };
    const partes = [erro.message, erro.details, erro.hint]
      .map((parte) => (typeof parte === "string" ? parte.trim() : ""))
      .filter(Boolean);
    // details e hint costumam repetir a mensagem; so entram quando acrescentam algo.
    const unicas = partes.filter((parte, i) => partes.indexOf(parte) === i);
    if (unicas.length > 0) return unicas.join(" · ");
  }
  if (typeof cause === "string" && cause.trim()) return cause;
  return fallback;
}
