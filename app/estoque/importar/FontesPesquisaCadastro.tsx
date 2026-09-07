import type { PesquisaCadastroXml } from "@/lib/itens/pesquisaCadastroXml";

export function FontesPesquisaCadastro({ pesquisa }: { pesquisa?: PesquisaCadastroXml }) {
  if (!pesquisa) return null; // Compatibilidade com sugestões anteriores.
  return (
    <div className="space-y-1 border-t border-sky-500/20 pt-2 text-xs">
      <div className={pesquisa.status === "exato" ? "text-sky-200" : "text-amber-200"}>
        {pesquisa.status === "exato" ? "Pesquisa técnica: correspondência exata sugerida" : "Pesquisa técnica: identificação não confirmada"}
        {pesquisa.modelo_referencia ? ` · ${pesquisa.modelo_referencia}` : ""}
      </div>
      <div className="text-sky-100/80">{pesquisa.observacao}</div>
      {pesquisa.fontes.filter((fonte) => /^https:\/\//i.test(fonte.url)).map((fonte) => (
        <a key={fonte.url} href={fonte.url} target="_blank" rel="noopener noreferrer" className="block break-words text-sky-300 underline hover:text-sky-100">
          {fonte.titulo} · {fonte.dominio}
        </a>
      ))}
    </div>
  );
}
