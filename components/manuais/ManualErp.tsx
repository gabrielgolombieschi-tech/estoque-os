"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

/**
 * Manual da equipe atras do login do ERP. O texto e os prints trazem cliente, OC, precos e chave
 * de NF-e, entao nada fica em public/: a pagina busca o index.html e as imagens em
 * /api/manuais/<manual>/... com o Bearer da sessao e monta tudo aqui. Sem sessao, a API responde
 * 401 e a pagina pede o login.
 */

/** Prefixa cada seletor do CSS do manual com .manual-erp para nao vazar para o resto do ERP. */
function escoparCss(css: string) {
  return css.replace(/(^|\})\s*([^@{}]+?)\s*\{/g, (_m, antes: string, seletores: string) => {
    const lista = seletores.split(",").map((s) => s.trim()).filter(Boolean).map((s) => (s === "body" ? ".manual-erp" : `.manual-erp ${s}`));
    return `${antes} ${lista.join(", ")} {`;
  });
}

export default function ManualErp({ manual, trilha, voltarHref = "/faturamento" }: { manual: string; trilha: string; voltarHref?: string }) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [estado, setEstado] = useState<"carregando" | "sem-sessao" | "erro" | "pronto">("carregando");
  const [erro, setErro] = useState<string | null>(null);
  const [css, setCss] = useState("");
  const [corpo, setCorpo] = useState("");

  useEffect(() => {
    let ativo = true;
    const urls: string[] = [];
    const api = `/api/manuais/${manual}`;
    (async () => {
      const { data } = await supabase.auth.getSession();
      const token = data.session?.access_token;
      if (!token) { if (ativo) setEstado("sem-sessao"); return; }
      const cabecalhos = { Authorization: `Bearer ${token}` };
      const resposta = await fetch(`${api}/index.html`, { headers: cabecalhos });
      if (resposta.status === 401) { if (ativo) setEstado("sem-sessao"); return; }
      if (!resposta.ok) throw new Error(`O manual não pôde ser lido (HTTP ${resposta.status}).`);
      const html = await resposta.text();
      const estilo = html.match(/<style>([\s\S]*?)<\/style>/)?.[1] ?? "";
      let miolo = html.match(/<body[^>]*>([\s\S]*?)<\/body>/)?.[1] ?? html;
      const arquivos = [...new Set([...miolo.matchAll(/src="\.\/([A-Za-z0-9._-]+)"/g)].map((m) => m[1]))];
      for (const arquivo of arquivos) {
        const imagem = await fetch(`${api}/${arquivo}`, { headers: cabecalhos });
        if (!imagem.ok) continue;
        const url = URL.createObjectURL(await imagem.blob());
        urls.push(url);
        miolo = miolo.split(`src="./${arquivo}"`).join(`src="${url}"`);
      }
      if (!ativo) return;
      setCss(escoparCss(estilo));
      setCorpo(miolo);
      setEstado("pronto");
    })().catch((cause: unknown) => {
      if (!ativo) return;
      setErro(cause instanceof Error ? cause.message : String(cause));
      setEstado("erro");
    });
    return () => { ativo = false; for (const url of urls) URL.revokeObjectURL(url); };
  }, [manual, supabase]);

  return (
    <main className="mx-auto max-w-[1000px] p-4 text-zinc-100">
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2 text-sm">
        <div className="text-zinc-400">{trilha}</div>
        <Link href={voltarHref} className="rounded border border-zinc-700 px-3 py-1.5 hover:bg-zinc-900">Voltar</Link>
      </div>
      {estado === "carregando" ? <div className="text-sm text-zinc-400">Carregando o manual…</div> : null}
      {estado === "sem-sessao" ? (
        <div role="alert" className="rounded border border-amber-800 bg-amber-950/20 p-3 text-sm text-amber-100">
          Entre no ERP para abrir o manual. <Link href="/login" className="underline">Ir para o login</Link>
        </div>
      ) : null}
      {estado === "erro" ? <div role="alert" className="rounded border border-red-900 bg-red-950/30 p-3 text-sm text-red-200">{erro}</div> : null}
      {estado === "pronto" ? (
        <>
          <style>{css}</style>
          <div className="manual-erp rounded-lg bg-white p-6 text-zinc-900" data-testid="manual-erp" dangerouslySetInnerHTML={{ __html: corpo }} />
        </>
      ) : null}
    </main>
  );
}
