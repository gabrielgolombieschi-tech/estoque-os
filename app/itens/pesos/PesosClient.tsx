"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { parseDecimalBR } from "@/lib/decimal";

/**
 * Preenchimento em massa do peso dos produtos (fase 1 do grupo vol da NF-e).
 *
 * A NF-e exige pesoL e pesoB no volume sempre que houver transporte, e a base tinha
 * 3.593 itens ativos sem peso em 09/09/2026 — preencher um a um pela tela de cadastro
 * seria inviavel. Aqui a lista abre filtrada pelos que faltam, edita em linha e salva
 * de uma vez. Nesta fase nada e obrigatorio no cadastro; a trava fica para a fase 2.
 */

type Linha = {
  id: number;
  codigo_interno: string;
  nome: string;
  unidade_medida: string | null;
  peso_liquido: string;
  peso_bruto: string;
  original_liquido: string;
  original_bruto: string;
};

const PAGINA = 100;
const campo = "w-full rounded-md border border-zinc-700 bg-zinc-900 px-2 py-1 text-sm text-zinc-100 outline-none focus:border-sky-600";
const botao = "rounded-md border border-zinc-700 px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-800 disabled:opacity-40";

function texto(valor: number | null): string {
  return valor === null || valor === undefined ? "" : String(valor).replace(".", ",");
}

export default function PesosClient() {
  const supabase = supabaseBrowser();
  const { tenantId, empresaId, loading } = useTenantEmpresa();
  const [linhas, setLinhas] = useState<Linha[]>([]);
  const [busca, setBusca] = useState("");
  const [soSemPeso, setSoSemPeso] = useState(true);
  const [carregando, setCarregando] = useState(false);
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [totalSemPeso, setTotalSemPeso] = useState<number | null>(null);

  const carregar = useCallback(async () => {
    if (loading || !tenantId || !empresaId) return;
    setCarregando(true);
    setErro(null);
    try {
      let query = applyTenantEmpresa(
        supabase.from("itens").select("id,codigo_interno,nome,unidade_medida,peso_liquido,peso_bruto").eq("ativo", true),
        tenantId,
        empresaId,
      ).order("codigo_interno").limit(PAGINA);
      if (soSemPeso) query = query.or("peso_bruto.is.null,peso_bruto.eq.0");
      const termo = busca.trim();
      if (termo) query = query.or(`codigo_interno.ilike.%${termo}%,nome.ilike.%${termo}%`);

      const { data, error } = await query;
      if (error) throw error;
      setLinhas(((data ?? []) as Array<Record<string, unknown>>).map((r) => ({
        id: Number(r.id),
        codigo_interno: String(r.codigo_interno ?? ""),
        nome: String(r.nome ?? ""),
        unidade_medida: (r.unidade_medida as string | null) ?? null,
        peso_liquido: texto(r.peso_liquido as number | null),
        peso_bruto: texto(r.peso_bruto as number | null),
        original_liquido: texto(r.peso_liquido as number | null),
        original_bruto: texto(r.peso_bruto as number | null),
      })));

      const { count } = await applyTenantEmpresa(
        supabase.from("itens").select("id", { count: "exact", head: true }).eq("ativo", true).or("peso_bruto.is.null,peso_bruto.eq.0"),
        tenantId,
        empresaId,
      );
      setTotalSemPeso(count ?? null);
    } catch (e: unknown) {
      setErro(e instanceof Error ? e.message : "Falha ao carregar os itens.");
    } finally {
      setCarregando(false);
    }
  }, [loading, tenantId, empresaId, supabase, soSemPeso, busca]);

  useEffect(() => { void carregar(); }, [carregar]);

  const alterar = (id: number, campoAlvo: "peso_liquido" | "peso_bruto", valor: string) => {
    setLinhas((atual) => atual.map((l) => l.id === id ? { ...l, [campoAlvo]: valor } : l));
  };

  const pendentes = linhas.filter((l) => l.peso_liquido !== l.original_liquido || l.peso_bruto !== l.original_bruto);

  async function salvar() {
    if (pendentes.length === 0 || !tenantId || !empresaId) return;
    setSalvando(true);
    setErro(null);
    setAviso(null);
    try {
      for (const linha of pendentes) {
        const liquido = linha.peso_liquido.trim() ? parseDecimalBR(linha.peso_liquido) : null;
        const bruto = linha.peso_bruto.trim() ? parseDecimalBR(linha.peso_bruto) : null;
        if (liquido !== null && (!Number.isFinite(liquido) || liquido < 0)) throw new Error(`${linha.codigo_interno}: peso líquido inválido.`);
        if (bruto !== null && (!Number.isFinite(bruto) || bruto < 0)) throw new Error(`${linha.codigo_interno}: peso bruto inválido.`);
        // O bruto nunca pode ser menor que o líquido — o builder da NF-e recusa o volume.
        if (liquido !== null && bruto !== null && bruto < liquido) throw new Error(`${linha.codigo_interno}: peso bruto menor que o líquido.`);
        const { error } = await applyTenantEmpresa(
          supabase.from("itens").update({ peso_liquido: liquido, peso_bruto: bruto }).eq("id", linha.id),
          tenantId,
          empresaId,
        );
        if (error) throw error;
      }
      setAviso(`${pendentes.length} item(ns) salvo(s).`);
      await carregar();
    } catch (e: unknown) {
      setErro(e instanceof Error ? e.message : "Falha ao salvar.");
    } finally {
      setSalvando(false);
    }
  }

  return (
    <div className="mx-auto max-w-6xl space-y-4 px-4 py-6 text-zinc-100">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="text-xs uppercase text-zinc-500">Cadastros · Itens</div>
          <h1 className="text-xl font-semibold">Peso dos produtos</h1>
          <p className="text-sm text-zinc-400">A NF-e pede peso líquido e bruto no volume sempre que houver transporte. Preencha aqui em lote.</p>
        </div>
        <Link href="/itens" className={botao}>Voltar para Itens</Link>
      </div>

      {erro ? <div role="alert" className="rounded-md border border-red-900 bg-red-950/30 p-3 text-sm text-red-200">{erro}</div> : null}
      {aviso ? <div role="status" className="rounded-md border border-emerald-900 bg-emerald-950/30 p-3 text-sm text-emerald-200">{aviso}</div> : null}

      <div className="flex flex-wrap items-center gap-3 rounded-xl border border-zinc-800 bg-zinc-950 p-3">
        <input className={`${campo} max-w-xs`} value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Código ou nome" aria-label="Buscar item" />
        <label className="flex items-center gap-2 text-sm text-zinc-300">
          <input type="checkbox" checked={soSemPeso} onChange={(e) => setSoSemPeso(e.target.checked)} />
          Só os que faltam
        </label>
        <button type="button" className={botao} disabled={carregando} onClick={() => void carregar()}>{carregando ? "Carregando..." : "Recarregar"}</button>
        <div className="ml-auto flex items-center gap-3">
          {totalSemPeso !== null ? <span className="text-xs text-zinc-400">{totalSemPeso} item(ns) ativo(s) sem peso</span> : null}
          <button type="button" className="rounded-md bg-emerald-700 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-600 disabled:opacity-40" disabled={salvando || pendentes.length === 0} onClick={() => void salvar()}>
            {salvando ? "Salvando..." : `Salvar ${pendentes.length || ""}`.trim()}
          </button>
        </div>
      </div>

      <div className="overflow-x-auto rounded-xl border border-zinc-800 bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="text-xs uppercase text-zinc-500">
            <tr>
              <th className="px-3 py-2 text-left">Código</th>
              <th className="px-3 py-2 text-left">Nome</th>
              <th className="px-3 py-2 text-left">Unidade</th>
              <th className="w-40 px-3 py-2 text-left">Peso líquido (kg)</th>
              <th className="w-40 px-3 py-2 text-left">Peso bruto (kg)</th>
            </tr>
          </thead>
          <tbody>
            {linhas.length === 0 ? (
              <tr><td colSpan={5} className="px-3 py-6 text-center text-zinc-500">{carregando ? "Carregando..." : "Nenhum item para mostrar."}</td></tr>
            ) : linhas.map((l) => (
              <tr key={l.id} className="border-t border-zinc-800">
                <td className="px-3 py-2 font-mono text-xs">{l.codigo_interno}</td>
                <td className="px-3 py-2">{l.nome}</td>
                <td className="px-3 py-2 text-zinc-400">{l.unidade_medida ?? "-"}</td>
                <td className="px-3 py-2"><input className={campo} inputMode="decimal" value={l.peso_liquido} onChange={(e) => alterar(l.id, "peso_liquido", e.target.value)} aria-label={`Peso líquido de ${l.codigo_interno}`} /></td>
                <td className="px-3 py-2"><input className={campo} inputMode="decimal" value={l.peso_bruto} onChange={(e) => alterar(l.id, "peso_bruto", e.target.value)} aria-label={`Peso bruto de ${l.codigo_interno}`} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="text-xs text-zinc-500">Mostra até {PAGINA} itens por vez; refine pela busca para chegar nos demais.</p>
    </div>
  );
}
