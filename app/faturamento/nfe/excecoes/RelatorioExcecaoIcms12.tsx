"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { formatMoneyBR } from "@/lib/decimal";
import { supabaseBrowser } from "@/lib/supabase/client";

/**
 * Notas emitidas no mes com a excecao "ICMS 12% por exigencia do destinatario"
 * (f.fn_nfe_excecao_aliquota_relatorio). vBC e ICMS somam so os itens que usaram a excecao;
 * a diferenca para 17% e o que o destinatario responde solidariamente (RICMS/SC-01,
 * art. 26, § 6º).
 */

type Linha = {
  documento_fiscal_id: string;
  serie: number | null;
  numero: number | null;
  autorizado_em: string;
  destinatario: string | null;
  destinatario_documento: string | null;
  numero_oc: string | null;
  itens: string | null;
  valor_base_calculo: number | string;
  valor_icms: number | string;
  valor_icms_17: number | string;
  diferenca_17: number | string;
};

const input = "rounded border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-sky-500";
const button = "rounded border border-zinc-600 bg-zinc-900 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-800 disabled:opacity-40";

const n = (valor: number | string | null | undefined) => {
  const numero = Number(valor ?? 0);
  return Number.isFinite(numero) ? numero : 0;
};

function documentoMascarado(valor: string | null) {
  const digitos = String(valor ?? "").replace(/\D/g, "");
  if (digitos.length === 14) return digitos.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5");
  if (digitos.length === 11) return digitos.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, "$1.$2.$3-$4");
  return valor ?? "";
}

function csv(linhas: Linha[]) {
  const celula = (valor: string) => `"${valor.replace(/"/g, '""')}"`;
  const moeda = (valor: number | string) => n(valor).toFixed(2).replace(".", ",");
  const cabecalho = ["Nota", "Autorizada em", "Destinatário", "CNPJ/CPF", "OC", "Itens", "vBC", "ICMS destacado", "ICMS a 17%", "Diferença para 17%"];
  const corpo = linhas.map((linha) => [
    `${linha.serie ?? ""}/${linha.numero ?? ""}`,
    new Date(linha.autorizado_em).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" }),
    linha.destinatario ?? "",
    documentoMascarado(linha.destinatario_documento),
    linha.numero_oc ?? "",
    linha.itens ?? "",
    moeda(linha.valor_base_calculo),
    moeda(linha.valor_icms),
    moeda(linha.valor_icms_17),
    moeda(linha.diferenca_17),
  ]);
  return [cabecalho, ...corpo].map((colunas) => colunas.map(celula).join(";")).join("\r\n");
}

export default function RelatorioExcecaoIcms12({ competencia }: { competencia: string }) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [ambiente, setAmbiente] = useState<"PRODUCAO" | "HOMOLOGACAO">("PRODUCAO");
  const [linhas, setLinhas] = useState<Linha[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  // Carregando e derivado: a consulta pronta guarda para qual competencia e ambiente foi.
  const [carregadoPara, setCarregadoPara] = useState("");
  const chave = `${competencia}:${ambiente}`;
  const carregando = carregadoPara !== chave;

  useEffect(() => {
    if (!/^\d{4}-\d{2}$/.test(competencia)) return;
    let ativo = true;
    void supabase.schema("f").rpc("fn_nfe_excecao_aliquota_relatorio", { p_mes: `${competencia}-01`, p_ambiente: ambiente })
      .then(({ data, error }) => {
        if (!ativo) return;
        setErro(error ? error.message : null);
        setLinhas(error ? [] : (data ?? []) as Linha[]);
        setCarregadoPara(`${competencia}:${ambiente}`);
      });
    return () => { ativo = false; };
  }, [ambiente, competencia, supabase]);

  const totais = linhas.reduce(
    (acc, linha) => ({
      base: acc.base + n(linha.valor_base_calculo),
      icms: acc.icms + n(linha.valor_icms),
      diferenca: acc.diferenca + n(linha.diferenca_17),
    }),
    { base: 0, icms: 0, diferenca: 0 },
  );

  function baixarCsv() {
    // BOM na frente para o Excel abrir os acentos certos.
    const url = URL.createObjectURL(new Blob([String.fromCharCode(0xfeff), csv(linhas)], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = url;
    link.download = `excecao-icms-12-${competencia}-${ambiente.toLowerCase()}.csv`;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 10_000);
  }

  return (
    <section className="space-y-3 rounded-xl border border-zinc-800 p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="font-semibold">ICMS 12% por exigência do destinatário</h2>
          <p className="max-w-3xl text-xs text-zinc-400">
            Notas autorizadas na competência com a exceção ativa. vBC e ICMS somam só os itens que saíram a 12% pela exceção;
            a diferença para 17% é a parcela pela qual o destinatário responde solidariamente (RICMS/SC-01, art. 26, § 6º).
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <select aria-label="Ambiente do relatório" className={input} value={ambiente} onChange={(event) => setAmbiente(event.target.value as "PRODUCAO" | "HOMOLOGACAO")}>
            <option value="PRODUCAO">Produção</option>
            <option value="HOMOLOGACAO">Homologação</option>
          </select>
          <button type="button" className={button} disabled={linhas.length === 0} onClick={baixarCsv}>Baixar CSV</button>
        </div>
      </div>
      {erro ? <div role="alert" className="rounded border border-rose-700/60 bg-rose-950/20 p-3 text-sm text-rose-200">{erro}</div> : null}
      <div className="overflow-x-auto">
        <table className="w-full min-w-[860px] text-sm">
          <thead className="bg-zinc-900/60 text-left text-xs uppercase text-zinc-500">
            <tr>
              <th className="px-3 py-2">Nota</th>
              <th className="px-3 py-2">Destinatário</th>
              <th className="px-3 py-2">OC</th>
              <th className="px-3 py-2">Itens</th>
              <th className="px-3 py-2 text-right">vBC</th>
              <th className="px-3 py-2 text-right">ICMS destacado</th>
              <th className="px-3 py-2 text-right">Diferença para 17%</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-900 tabular-nums">
            {linhas.map((linha) => (
              <tr key={linha.documento_fiscal_id}>
                <td className="px-3 py-2">
                  <Link className="text-sky-300 hover:underline" href={`/faturamento/nfe/${linha.documento_fiscal_id}`}>{linha.serie}/{linha.numero}</Link>
                  <div className="text-xs text-zinc-500">{new Date(linha.autorizado_em).toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" })}</div>
                </td>
                <td className="px-3 py-2">{linha.destinatario}<div className="text-xs text-zinc-500">{documentoMascarado(linha.destinatario_documento)}</div></td>
                <td className="px-3 py-2">{linha.numero_oc}</td>
                <td className="px-3 py-2">{linha.itens}</td>
                <td className="px-3 py-2 text-right">R$ {formatMoneyBR(n(linha.valor_base_calculo))}</td>
                <td className="px-3 py-2 text-right">R$ {formatMoneyBR(n(linha.valor_icms))}</td>
                <td className="px-3 py-2 text-right font-medium text-amber-200">R$ {formatMoneyBR(n(linha.diferenca_17))}</td>
              </tr>
            ))}
            {linhas.length === 0 ? (
              <tr><td colSpan={7} className="px-3 py-4 text-center text-sm text-zinc-500">{carregando ? "Carregando..." : "Nenhuma nota com a exceção nesta competência."}</td></tr>
            ) : null}
          </tbody>
          {linhas.length > 0 ? (
            <tfoot className="border-t border-zinc-800 text-sm font-medium tabular-nums">
              <tr>
                <td className="px-3 py-2" colSpan={4}>{linhas.length} nota(s)</td>
                <td className="px-3 py-2 text-right">R$ {formatMoneyBR(totais.base)}</td>
                <td className="px-3 py-2 text-right">R$ {formatMoneyBR(totais.icms)}</td>
                <td className="px-3 py-2 text-right text-amber-200">R$ {formatMoneyBR(totais.diferenca)}</td>
              </tr>
            </tfoot>
          ) : null}
        </table>
      </div>
    </section>
  );
}
