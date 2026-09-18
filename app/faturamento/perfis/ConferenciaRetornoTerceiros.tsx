"use client";

import { useEffect, useMemo, useState } from "react";
import { formatMoneyBR } from "@/lib/decimal";
import { supabaseBrowser } from "@/lib/supabase/client";

/**
 * Quadro "remessa do cliente x retorno homologado" na tela de liberar perfil, quando a solicitacao e
 * de retorno de mercadoria de terceiros. Conferencia visual antes de liberar: linhas iguais em cinza,
 * divergencia em vermelho. Numeros comparam por valor (400.00 = 400.0000); nada bloqueia.
 */

type LinhaRetorno = { ordem: number; codigo: string; descricao: string; ncm: string | null; quantidade: number | string; unidade: string | null; valor_unitario: number | string; cfop: string | null };
type LinhaRemessa = { n_item: number; c_prod: string; x_prod: string; ncm: string | null; q_com: number | string; u_com: string; v_un_com: number | string; v_prod: number | string };
type Dados = {
  natureza: string;
  chaveSnapshot: string | null;
  remessa: { chave: string; numero: string | null; serie: string | null; emitente_nome: string; is_teste: boolean } | null;
  itensRetorno: LinhaRetorno[];
  itensRemessa: LinhaRemessa[];
};

function num(v: unknown) {
  const n = Number(String(v ?? "").replace(",", "."));
  return Number.isFinite(n) ? n : NaN;
}
function iguais(a: number, b: number) {
  return Number.isFinite(a) && Number.isFinite(b) && Math.abs(a - b) < 0.005;
}
function texto(v: unknown) {
  return String(v ?? "").replace(/\s+/g, " ").trim().toUpperCase();
}

export default function ConferenciaRetornoTerceiros({ solicitacaoId }: { solicitacaoId: string }) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [dados, setDados] = useState<Dados | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    let vivo = true;
    setDados(null);
    setErro(null);
    if (!/^[0-9a-f-]{36}$/i.test(solicitacaoId)) return;
    void (async () => {
      try {
        const sol = await supabase.schema("f").from("solicitacao_faturamento").select("natureza_operacao,operacao_snapshot").eq("id", solicitacaoId).maybeSingle();
        if (sol.error) throw sol.error;
        const natureza = String((sol.data as { natureza_operacao?: string } | null)?.natureza_operacao ?? "");
        if (!natureza.startsWith("RETORNO_REMESSA_TERCEIROS")) { if (vivo) setDados({ natureza, chaveSnapshot: null, remessa: null, itensRetorno: [], itensRemessa: [] }); return; }
        const origem = ((sol.data as { operacao_snapshot?: { retorno_terceiros?: { remessa_id?: string; chave?: string } } } | null)?.operacao_snapshot?.retorno_terceiros) ?? {};
        const [itens, rem, itensRem] = await Promise.all([
          supabase.schema("f").from("solicitacao_item").select("ordem,codigo_produto,descricao,ncm,quantidade,unidade,valor_unitario,cfop").eq("solicitacao_id", solicitacaoId).order("ordem"),
          origem.remessa_id ? supabase.schema("f").from("remessas_terceiros").select("chave,numero,serie,emitente_nome,is_teste").eq("id", origem.remessa_id).maybeSingle() : Promise.resolve({ data: null, error: null }),
          origem.remessa_id ? supabase.schema("f").from("remessas_terceiros_itens").select("n_item,c_prod,x_prod,ncm,q_com,u_com,v_un_com,v_prod").eq("remessa_id", origem.remessa_id).order("n_item") : Promise.resolve({ data: [], error: null }),
        ]);
        if (itens.error) throw itens.error;
        if (rem.error) throw rem.error;
        if (itensRem.error) throw itensRem.error;
        if (!vivo) return;
        setDados({
          natureza,
          chaveSnapshot: origem.chave ? String(origem.chave).replace(/\D/g, "") : null,
          remessa: (rem.data as Dados["remessa"]) ?? null,
          itensRetorno: ((itens.data ?? []) as Array<Record<string, unknown>>).map((i) => ({
            ordem: Number(i.ordem), codigo: String(i.codigo_produto ?? ""), descricao: String(i.descricao ?? ""), ncm: (i.ncm as string | null) ?? null,
            quantidade: i.quantidade as number | string, unidade: (i.unidade as string | null) ?? null, valor_unitario: i.valor_unitario as number | string, cfop: (i.cfop as string | null) ?? null,
          })),
          itensRemessa: (itensRem.data ?? []) as LinhaRemessa[],
        });
      } catch (e) {
        if (vivo) setErro(e instanceof Error ? e.message : String(e));
      }
    })();
    return () => { vivo = false; };
  }, [solicitacaoId, supabase]);

  if (erro) return <p className="mt-3 text-xs text-amber-300">Não foi possível montar a conferência remessa × retorno: {erro}</p>;
  if (!dados || !dados.natureza.startsWith("RETORNO_REMESSA_TERCEIROS")) return null;

  const total = Math.max(dados.itensRetorno.length, dados.itensRemessa.length);
  const linhas = Array.from({ length: total }, (_, k) => {
    const r = dados.itensRetorno[k];
    const o = dados.itensRemessa[k];
    const qtdR = num(r?.quantidade), qtdO = num(o?.q_com);
    const unR = num(r?.valor_unitario), unO = num(o?.v_un_com);
    const totR = Number.isFinite(qtdR) && Number.isFinite(unR) ? qtdR * unR : NaN;
    const totO = num(o?.v_prod);
    const campos = [
      { nome: "Produto", origem: o ? `${o.c_prod} · ${o.x_prod}` : "—", retorno: r ? `${r.codigo} · ${r.descricao}` : "—", ok: Boolean(r && o) && texto(o?.c_prod) === texto(r?.codigo) && texto(o?.x_prod) === texto(r?.descricao) },
      { nome: "NCM", origem: o?.ncm ?? "—", retorno: r?.ncm ?? "—", ok: texto(o?.ncm) === texto(r?.ncm) },
      { nome: "Quantidade", origem: o ? String(o.q_com) : "—", retorno: r ? String(r.quantidade) : "—", ok: iguais(qtdO, qtdR) },
      { nome: "Unidade", origem: o?.u_com ?? "—", retorno: r?.unidade ?? "—", ok: texto(o?.u_com) === texto(r?.unidade) },
      { nome: "Valor unitário", origem: o ? `R$ ${formatMoneyBR(unO)}` : "—", retorno: r ? `R$ ${formatMoneyBR(unR)}` : "—", ok: iguais(unO, unR) },
      { nome: "Valor total", origem: o ? `R$ ${formatMoneyBR(totO)}` : "—", retorno: r ? `R$ ${formatMoneyBR(totR)}` : "—", ok: iguais(totO, totR) },
    ];
    return { k, campos, ok: campos.every((c) => c.ok) };
  });
  const chaveOk = Boolean(dados.remessa?.chave) && dados.chaveSnapshot === dados.remessa?.chave;
  const divergencias = linhas.filter((l) => !l.ok).length + (chaveOk ? 0 : 1);

  return (
    <div className="mt-4 rounded-lg border border-zinc-800 p-3">
      <p className="text-sm text-zinc-200">Confira se o que está voltando é igual ao que o cliente mandou.</p>
      <p className="mt-1 text-xs text-zinc-500">
        Remessa {dados.remessa ? `${dados.remessa.emitente_nome} · NF-e ${dados.remessa.numero}/${dados.remessa.serie}` : "(não encontrada)"}{dados.remessa?.is_teste ? " · TESTE de homologação" : ""} × retorno homologado
        {dados.itensRetorno[0]?.cfop ? ` · CFOP ${dados.itensRetorno[0].cfop}` : ""}. {divergencias === 0 ? "Tudo igual." : `${divergencias} divergência(s) em vermelho.`} Casas decimais não contam como divergência.
      </p>
      <div className="mt-2 overflow-x-auto">
        <table className="w-full min-w-[640px] text-xs">
          <thead className="text-left uppercase text-zinc-500"><tr><th className="py-1 pr-2">Item</th><th className="py-1 pr-2">Campo</th><th className="py-1 pr-2">Remessa do cliente</th><th className="py-1 pr-2">Retorno homologado</th></tr></thead>
          <tbody className="divide-y divide-zinc-800">
            {linhas.flatMap((l) => l.campos.map((c, i) => (
              <tr key={`${l.k}-${c.nome}`} className={c.ok ? "text-zinc-400" : "bg-rose-950/30 text-rose-200"}>
                <td className="py-1 pr-2">{i === 0 ? l.k + 1 : ""}</td>
                <td className="py-1 pr-2">{c.nome}</td>
                <td className="py-1 pr-2">{c.origem}</td>
                <td className="py-1 pr-2">{c.retorno}</td>
              </tr>
            )))}
            <tr className={chaveOk ? "text-zinc-400" : "bg-rose-950/30 text-rose-200"}>
              <td className="py-1 pr-2"></td>
              <td className="py-1 pr-2">Chave referenciada</td>
              <td className="py-1 pr-2 font-mono">{dados.remessa?.chave ?? "—"}</td>
              <td className="py-1 pr-2 font-mono">{dados.chaveSnapshot ?? "—"}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  );
}
