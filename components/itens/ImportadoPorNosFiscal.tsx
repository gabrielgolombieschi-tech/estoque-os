"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

/**
 * "Importado por nós (DIR/DI no nosso CNPJ)" na aba fiscal do item.
 *
 * Quando a empresa e a importadora, ela e equiparada a industrial (RIPI, Decreto 7.212/2010,
 * art. 9o, I) e destaca o IPI da TIPI ao revender. Ate 18/09/2026 so a entrada de importacao
 * em 3101/3102 marcava isso; aqui a marcacao e feita a mao, com a DIR/DI e a nota de entrada
 * como prova, e o banco grava quem marcou e quando
 * (public.web_fiscal_item_marcar_importado_por_nos, 20260918210000).
 */

type Estado = {
  origem: number | null;
  cst_ipi: string | null;
  aliq_ipi: number | string | null;
  equiparado_industrial: boolean | null;
  importado_por_nos_dir: string | null;
  importado_por_nos_nota: string | null;
  importado_por_nos_em: string | null;
  importado_por_nos_por: string | null;
};

export type ImportadoPorNosResultado = {
  origem: number;
  cst_ipi: string;
  aliq_ipi: number | string | null;
};

function dataHora(valor: string | null) {
  if (!valor) return "";
  const data = new Date(valor);
  return Number.isNaN(data.getTime())
    ? valor
    : data.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" });
}

function textoErro(cause: unknown) {
  if (cause && typeof cause === "object" && "message" in cause) return String((cause as { message: unknown }).message);
  return String(cause);
}

export default function ImportadoPorNosFiscal({
  itemId,
  podeEditar,
  onAplicado,
}: {
  itemId: number;
  podeEditar: boolean;
  /** Chamado depois de marcar, com origem, CST e alíquota de IPI já gravados no banco. */
  onAplicado?: (resultado: ImportadoPorNosResultado) => void;
}) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [estado, setEstado] = useState<Estado | null>(null);
  const [aberto, setAberto] = useState(false);
  const [dir, setDir] = useState("");
  const [nota, setNota] = useState("");
  const [ocupado, setOcupado] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);

  const carregar = useCallback(async () => {
    const { data, error } = await supabase
      .from("fiscal_itens")
      .select("origem,cst_ipi,aliq_ipi,equiparado_industrial,importado_por_nos_dir,importado_por_nos_nota,importado_por_nos_em,importado_por_nos_por")
      .eq("item_id", itemId)
      .maybeSingle();
    if (error) {
      setErro(textoErro(error));
      return;
    }
    setEstado((data as Estado | null) ?? null);
  }, [itemId, supabase]);

  useEffect(() => { void carregar(); }, [carregar]);

  async function marcar() {
    setErro(null);
    setAviso(null);
    if (!dir.trim()) {
      setErro("Informe o número da DIR ou da DI.");
      return;
    }
    if (!nota.trim()) {
      setErro("Informe a nota de entrada da importação (ex.: 2/24 ou a chave).");
      return;
    }
    if (!window.confirm(
      "Marcar este item como importado por nós?\n\n"
      + "O cadastro fiscal passa a: origem 1 (importação direta), equiparado a industrial, "
      + "IPI CST 50 com a alíquota da TIPI do NCM. A próxima venda deste item destaca o IPI.\n\n"
      + `DIR/DI: ${dir.trim()}\nNota de entrada: ${nota.trim()}`,
    )) return;
    setOcupado(true);
    try {
      const { data, error } = await supabase.rpc("web_fiscal_item_marcar_importado_por_nos", {
        p_item_id: itemId,
        p_dir_numero: dir.trim(),
        p_nota_entrada: nota.trim(),
      });
      if (error) throw error;
      const resultado = data as { depois: ImportadoPorNosResultado & { aliq_ipi: number | string | null }; documento_fiscal: { serie: string; numero: string } | null; tipi: number | string };
      setAberto(false);
      setDir("");
      setNota("");
      setAviso(
        `Marcado: origem 1, equiparado a industrial, IPI CST ${resultado.depois.cst_ipi} a ${String(resultado.tipi).replace(".", ",")}%`
        + (resultado.documento_fiscal ? ` · nota de entrada ${resultado.documento_fiscal.serie}/${resultado.documento_fiscal.numero} encontrada no ERP.` : " · a nota de entrada informada não foi encontrada no ERP; ficou registrada como texto."),
      );
      await carregar();
      onAplicado?.({ origem: resultado.depois.origem, cst_ipi: resultado.depois.cst_ipi, aliq_ipi: resultado.depois.aliq_ipi });
    } catch (cause) {
      setErro(textoErro(cause));
    } finally {
      setOcupado(false);
    }
  }

  const marcado = Boolean(estado?.equiparado_industrial && estado?.importado_por_nos_em);

  return (
    <section data-testid="importado-por-nos" className={`space-y-2 rounded-lg border p-3 ${marcado ? "border-emerald-900/70 bg-emerald-950/15" : "border-zinc-800 bg-zinc-900/30"}`}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <div className="text-sm font-medium text-zinc-100">
            Importado por nós (DIR/DI no nosso CNPJ)
            {marcado ? <span className="ml-2 rounded-full border border-emerald-700 px-2 py-0.5 text-xs font-normal text-emerald-200">marcado</span> : null}
          </div>
          <p className="mt-1 max-w-3xl text-xs text-zinc-400">
            Quando a importação foi feita no nosso CNPJ (a DIR ou DI está em nosso nome), somos equiparados a industrial
            e a venda deste item destaca o IPI da TIPI. Ex.: CPU de CLP comprada da China pela remessa expressa. Ao marcar, o
            cadastro fica com origem 1, equiparado a industrial e IPI CST 50 com a alíquota do NCM. Comprado de distribuidor
            no Brasil: não marque (origem 2, sem IPI).
          </p>
        </div>
        {podeEditar && !aberto ? (
          <button
            type="button"
            onClick={() => { setErro(null); setAviso(null); setAberto(true); }}
            className="rounded-md border border-emerald-800 px-3 py-1.5 text-xs text-emerald-100 hover:bg-emerald-950/40"
          >
            {marcado ? "Corrigir DIR/DI ou nota" : "Marcar como importado por nós"}
          </button>
        ) : null}
      </div>

      {marcado && estado ? (
        <div className="grid gap-1 text-xs text-zinc-300 md:grid-cols-2">
          <div><span className="text-zinc-500">DIR/DI:</span> {estado.importado_por_nos_dir}</div>
          <div><span className="text-zinc-500">Nota de entrada:</span> {estado.importado_por_nos_nota}</div>
          <div className="md:col-span-2"><span className="text-zinc-500">Marcado em:</span> {dataHora(estado.importado_por_nos_em)}{estado.importado_por_nos_por ? ` · usuário ${estado.importado_por_nos_por.slice(0, 8)}…` : ""}</div>
          <div className="md:col-span-2"><span className="text-zinc-500">Cadastro fiscal:</span> origem {estado.origem} · equiparado a industrial · IPI CST {estado.cst_ipi}{estado.aliq_ipi !== null ? ` a ${String(estado.aliq_ipi).replace(".", ",")}%` : ""}</div>
        </div>
      ) : null}

      {aberto ? (
        <div className="grid gap-3 md:grid-cols-2">
          <label className="space-y-1 text-xs text-zinc-400">
            Nº da DIR (12 dígitos) ou DI (10 dígitos) <span className="text-amber-300">obrigatório</span>
            <input
              aria-label="Número da DIR ou DI"
              className="w-full px-3 py-2"
              value={dir}
              onChange={(event) => setDir(event.target.value)}
              maxLength={20}
              placeholder="Ex.: 260191366846"
            />
          </label>
          <label className="space-y-1 text-xs text-zinc-400">
            Nota de entrada da importação <span className="text-amber-300">obrigatório</span>
            <input
              aria-label="Nota de entrada da importação"
              className="w-full px-3 py-2"
              value={nota}
              onChange={(event) => setNota(event.target.value)}
              maxLength={60}
              placeholder="Ex.: 2/24 (série/número) ou a chave de 44 dígitos"
            />
          </label>
          <div className="flex flex-wrap gap-2 md:col-span-2">
            <button
              type="button"
              onClick={() => void marcar()}
              disabled={ocupado}
              className="rounded-md bg-emerald-700 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-600 disabled:opacity-40"
            >
              {ocupado ? "Marcando..." : "Confirmar: importado por nós"}
            </button>
            <button type="button" onClick={() => setAberto(false)} disabled={ocupado} className="rounded-md border border-zinc-700 px-3 py-2 text-sm hover:bg-zinc-900">
              Cancelar
            </button>
          </div>
        </div>
      ) : null}

      {erro ? <div role="alert" className="rounded border border-red-900 bg-red-950/30 p-2 text-sm text-red-200">{erro}</div> : null}
      {aviso ? <div role="status" className="text-xs text-emerald-200">{aviso}</div> : null}
    </section>
  );
}
