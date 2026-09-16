"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * "Vincular com similar": copia o cadastro fiscal de um item parecido para o item
 * que travou a conferencia da NF-e (estoque antigo sem nota de entrada).
 *
 * A busca e a copia sao RPCs (supabase/migrations/20260916130000_fiscal_item_vincular_similar.sql):
 * fiscal_item_similares ordena mesmo NCM primeiro e depois nome, fabricante e grupo;
 * fiscal_item_copiar_de_similar grava so os campos marcados e a procedencia.
 */

type ValoresFiscais = {
  origem: number | null;
  ncm: string | null;
  cest: string | null;
  unidade_tributavel: string | null;
  cfop_padrao: string | null;
  cst_icms: string | null;
  cst_pis: string | null;
  cst_cofins: string | null;
  cst_ipi: string | null;
  aliq_icms: number | string | null;
  aliq_ipi: number | string | null;
  aliq_pis: number | string | null;
  aliq_cofins: number | string | null;
};

type Atual = ValoresFiscais & {
  id: number;
  codigo: string | null;
  nome: string | null;
  fabricante: string | null;
  grupo: string | null;
  fiscal_existe: boolean;
  ncm_cadastro_antigo: string | null;
  cest_cadastro_antigo: string | null;
  fiscal_copiado_de_item_id: number | null;
};

type Candidato = ValoresFiscais & {
  id: number;
  codigo: string | null;
  nome: string | null;
  fabricante: string | null;
  grupo: string | null;
  origem_copiavel: boolean;
  mesmo_ncm: boolean;
  motivos: string[];
};

type RespostaBusca = {
  atual: Atual;
  ncm_referencia: string | null;
  candidatos: Candidato[];
};

type Campo = keyof ValoresFiscais;

const CAMPOS: { campo: Campo; rotulo: string; mora: string }[] = [
  { campo: "origem", rotulo: "Origem da mercadoria", mora: "fiscal_itens.origem" },
  { campo: "ncm", rotulo: "NCM", mora: "fiscal_itens.ncm" },
  { campo: "cest", rotulo: "CEST", mora: "fiscal_itens.cest" },
  { campo: "unidade_tributavel", rotulo: "Unidade tributável", mora: "fiscal_itens.unidade_tributavel" },
  { campo: "cfop_padrao", rotulo: "CFOP padrão", mora: "fiscal_itens.cfop_padrao" },
  { campo: "cst_icms", rotulo: "CST ICMS", mora: "fiscal_itens.cst_icms" },
  { campo: "aliq_icms", rotulo: "Alíquota ICMS (%)", mora: "fiscal_itens.aliq_icms" },
  { campo: "cst_ipi", rotulo: "CST IPI", mora: "fiscal_itens.cst_ipi" },
  { campo: "aliq_ipi", rotulo: "Alíquota IPI (%)", mora: "fiscal_itens.aliq_ipi" },
  { campo: "cst_pis", rotulo: "CST PIS", mora: "fiscal_itens.cst_pis" },
  { campo: "aliq_pis", rotulo: "Alíquota PIS (%)", mora: "fiscal_itens.aliq_pis" },
  { campo: "cst_cofins", rotulo: "CST COFINS", mora: "fiscal_itens.cst_cofins" },
  { campo: "aliq_cofins", rotulo: "Alíquota COFINS (%)", mora: "fiscal_itens.aliq_cofins" },
];

const ORIGENS: Record<number, string> = {
  0: "0 · Nacional",
  1: "1 · Estrangeira, importação direta",
  2: "2 · Estrangeira, mercado interno",
  3: "3 · Nacional, importado 40 a 70%",
  4: "4 · Nacional, processo produtivo básico",
  5: "5 · Nacional, importado até 40%",
  6: "6 · Estrangeira direta, sem similar (CAMEX)",
  7: "7 · Estrangeira mercado interno, sem similar (CAMEX)",
  8: "8 · Nacional, importado acima de 70%",
};

function vazio(valor: unknown) {
  return valor === null || valor === undefined || String(valor).trim() === "";
}

function mostrar(campo: Campo, valor: unknown) {
  if (vazio(valor)) return "—";
  if (campo === "origem") return ORIGENS[Number(valor)] ?? String(valor);
  if (campo.startsWith("aliq_")) return Number(valor).toLocaleString("pt-BR", { maximumFractionDigits: 4 });
  if (campo === "ncm") return String(valor).replace(/^(\d{4})(\d{2})(\d{2})$/, "$1.$2.$3");
  return String(valor);
}

function igual(campo: Campo, a: unknown, b: unknown) {
  if (vazio(a) || vazio(b)) return vazio(a) && vazio(b);
  if (campo.startsWith("aliq_") || campo === "origem") return Number(a) === Number(b);
  if (campo === "ncm" || campo === "cest" || campo === "cfop_padrao") {
    return String(a).replace(/\D/g, "") === String(b).replace(/\D/g, "");
  }
  return String(a).trim().toUpperCase() === String(b).trim().toUpperCase();
}

function aliquotas(c: ValoresFiscais) {
  const fmt = (v: unknown) => (vazio(v) ? "—" : Number(v).toLocaleString("pt-BR", { maximumFractionDigits: 2 }));
  return `ICMS ${fmt(c.aliq_icms)} · IPI ${fmt(c.aliq_ipi)} · PIS ${fmt(c.aliq_pis)} · COFINS ${fmt(c.aliq_cofins)}`;
}

function mensagemErro(cause: unknown) {
  if (cause instanceof Error) return cause.message;
  if (cause && typeof cause === "object" && "message" in cause) return String((cause as { message: unknown }).message);
  return "Não foi possível concluir a operação.";
}

export default function VincularSimilarModal({
  supabase,
  itemId,
  descricao,
  onClose,
  onCopiado,
}: {
  supabase: SupabaseClient;
  itemId: number;
  descricao: string;
  onClose: () => void;
  onCopiado: (mensagem: string) => void | Promise<void>;
}) {
  const [busca, setBusca] = useState("");
  const [buscando, setBuscando] = useState(true);
  const [resposta, setResposta] = useState<RespostaBusca | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [escolhido, setEscolhido] = useState<Candidato | null>(null);
  const [marcados, setMarcados] = useState<Set<Campo>>(new Set());
  const [gravando, setGravando] = useState(false);

  const buscar = useCallback(async (texto: string) => {
    setBuscando(true);
    setErro(null);
    try {
      const { data, error } = await supabase.rpc("fiscal_item_similares", {
        p_item_id: itemId,
        p_busca: texto.trim() || null,
        p_limite: 40,
      });
      if (error) throw error;
      setResposta(data as RespostaBusca);
    } catch (cause) {
      setErro(mensagemErro(cause));
    } finally {
      setBuscando(false);
    }
  }, [itemId, supabase]);

  useEffect(() => {
    void buscar("");
  }, [buscar]);

  useEffect(() => {
    function aoTeclar(event: KeyboardEvent) {
      if (event.key === "Escape" && !gravando) onClose();
    }
    window.addEventListener("keydown", aoTeclar);
    return () => window.removeEventListener("keydown", aoTeclar);
  }, [gravando, onClose]);

  const atual = resposta?.atual ?? null;

  /** O que a comparação mostra do item atual: o fiscal, e o NCM/CEST antigos quando o fiscal está vazio. */
  const valorAtual = useCallback((campo: Campo) => {
    if (!atual) return null;
    return atual[campo];
  }, [atual]);

  const podeCopiar = useCallback((campo: Campo, similar: Candidato) => {
    if (vazio(similar[campo])) return false;
    if (campo === "origem" && !similar.origem_copiavel) return false;
    return true;
  }, []);

  function escolher(candidato: Candidato) {
    const iniciais = new Set<Campo>();
    for (const { campo } of CAMPOS) {
      if (!podeCopiar(campo, candidato)) continue;
      if (!vazio(valorAtual(campo))) continue;
      // O NCM que só existe no cadastro antigo não é trocado por um diferente sem a pessoa marcar.
      if (campo === "ncm" && atual?.ncm_cadastro_antigo && !igual("ncm", atual.ncm_cadastro_antigo, candidato.ncm)) continue;
      if (campo === "cest" && atual?.cest_cadastro_antigo && !igual("cest", atual.cest_cadastro_antigo, candidato.cest)) continue;
      iniciais.add(campo);
    }
    setMarcados(iniciais);
    setEscolhido(candidato);
    setErro(null);
  }

  function alternar(campo: Campo) {
    setMarcados((atuais) => {
      const proximo = new Set(atuais);
      if (proximo.has(campo)) proximo.delete(campo);
      else proximo.add(campo);
      return proximo;
    });
  }

  async function copiar() {
    if (!escolhido || marcados.size === 0) return;
    setGravando(true);
    setErro(null);
    try {
      const campos = CAMPOS.map((c) => c.campo).filter((campo) => marcados.has(campo));
      const { error } = await supabase.rpc("fiscal_item_copiar_de_similar", {
        p_item_id: itemId,
        p_similar_id: escolhido.id,
        p_campos: campos,
      });
      if (error) throw error;
      const rotulos = CAMPOS.filter((c) => marcados.has(c.campo)).map((c) => c.rotulo);
      await onCopiado(`Item #${itemId}: ${rotulos.join(", ")} copiados do similar #${escolhido.id}.`);
    } catch (cause) {
      setErro(mensagemErro(cause));
      setGravando(false);
    }
  }

  const candidatos = resposta?.candidatos ?? [];
  const semOrigemCopiavel = escolhido ? !escolhido.origem_copiavel : false;
  const trocasDePreenchido = useMemo(() => (
    escolhido ? CAMPOS.filter(({ campo }) => marcados.has(campo) && !vazio(valorAtual(campo)) && !igual(campo, valorAtual(campo), escolhido[campo])) : []
  ), [escolhido, marcados, valorAtual]);

  return (
    <div className="fixed inset-0 z-[60] overflow-y-auto bg-black/80 p-4" role="dialog" aria-modal="true" aria-labelledby="vincular-similar-titulo">
      <div className="mx-auto my-6 w-full max-w-6xl rounded-xl border border-zinc-700 bg-zinc-950 shadow-2xl">
        <div className="flex items-start justify-between gap-3 border-b border-zinc-800 p-4">
          <div>
            <h3 id="vincular-similar-titulo" className="text-lg font-semibold">Vincular com similar</h3>
            <p className="text-sm text-zinc-400">
              Item #{itemId}{atual?.codigo ? ` · [${atual.codigo}]` : ""} · {atual?.nome ?? descricao}
              {atual?.fabricante ? <span className="text-zinc-500"> · {atual.fabricante}</span> : null}
            </p>
            <p className="mt-1 text-xs text-zinc-500">
              Copia os dados fiscais de um item parecido que já tem NCM e origem. Nada é copiado sem você conferir campo a campo.
            </p>
          </div>
          <button type="button" onClick={onClose} disabled={gravando} className="rounded-md border border-zinc-700 px-3 py-2 text-sm hover:bg-zinc-900 disabled:opacity-40">Fechar</button>
        </div>

        {!escolhido ? (
          <div className="space-y-3 p-4">
            {atual ? (
              <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 p-3 text-sm text-zinc-300">
                Hoje no item: origem <strong>{mostrar("origem", atual.origem)}</strong>
                {" · "}NCM <strong>{mostrar("ncm", atual.ncm)}</strong>
                {!atual.ncm && atual.ncm_cadastro_antigo ? <span className="text-zinc-400"> (no cadastro antigo: {mostrar("ncm", atual.ncm_cadastro_antigo)})</span> : null}
                {" · "}CST ICMS <strong>{mostrar("cst_icms", atual.cst_icms)}</strong>
                {resposta?.ncm_referencia ? <div className="mt-1 text-xs text-zinc-500">Primeiro vêm os itens com o NCM {mostrar("ncm", resposta.ncm_referencia)}; depois os parecidos pelo nome, fabricante e grupo.</div> : <div className="mt-1 text-xs text-zinc-500">O item não tem NCM: a lista vem pelos parecidos no nome, fabricante e grupo.</div>}
              </div>
            ) : null}
            <form
              className="flex gap-2"
              onSubmit={(event) => {
                event.preventDefault();
                void buscar(busca);
              }}
            >
              <input
                aria-label="Buscar similar por código ou nome"
                className="w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-sky-500"
                value={busca}
                onChange={(event) => setBusca(event.target.value)}
                placeholder="Buscar por ID, código ou nome (vazio = sugestões)"
                autoFocus
              />
              <button type="submit" disabled={buscando} className="rounded-md border border-zinc-700 px-4 py-2 text-sm hover:bg-zinc-900 disabled:opacity-40">{buscando ? "Buscando..." : "Buscar"}</button>
            </form>
            {erro ? <div role="alert" className="rounded border border-red-900 bg-red-950/30 p-3 text-sm text-red-200">{erro}</div> : null}
            {!buscando && !erro && candidatos.length === 0 ? (
              <div className="rounded border border-zinc-800 p-3 text-sm text-zinc-400">
                Nenhum item com NCM e origem cadastrados {busca.trim() ? <>para <strong className="text-zinc-200">{busca.trim()}</strong></> : "parecido com este"}. Tente buscar por outra palavra ou código.
              </div>
            ) : null}
            {candidatos.length > 0 ? (
              <div className="overflow-x-auto rounded-lg border border-zinc-800">
                <table className="w-full min-w-[900px] text-left text-sm">
                  <thead className="bg-zinc-900/60 text-xs uppercase text-zinc-500">
                    <tr>
                      <th className="px-3 py-2">ID</th>
                      <th className="px-3 py-2">Código</th>
                      <th className="px-3 py-2">Nome</th>
                      <th className="px-3 py-2">NCM</th>
                      <th className="px-3 py-2">Origem</th>
                      <th className="px-3 py-2">CST ICMS</th>
                      <th className="px-3 py-2">Alíquotas (%)</th>
                      <th className="px-3 py-2"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {candidatos.map((c) => (
                      <tr key={c.id} className="border-t border-zinc-800 align-top" data-testid="similar-linha">
                        <td className="px-3 py-2 text-zinc-400">#{c.id}</td>
                        <td className="px-3 py-2 font-mono text-xs">{c.codigo ?? "—"}</td>
                        <td className="px-3 py-2">
                          <div>{c.nome}</div>
                          <div className="text-xs text-zinc-500">{[c.fabricante, c.grupo].filter(Boolean).join(" · ")}{c.motivos.length > 0 ? `${c.fabricante || c.grupo ? " · " : ""}${c.motivos.join(" · ")}` : ""}</div>
                        </td>
                        <td className={`px-3 py-2 whitespace-nowrap ${c.mesmo_ncm ? "text-emerald-300" : ""}`}>{mostrar("ncm", c.ncm)}</td>
                        <td className="px-3 py-2">{mostrar("origem", c.origem)}{!c.origem_copiavel ? <div className="text-xs text-amber-300">importação própria, não copia</div> : null}</td>
                        <td className="px-3 py-2">{c.cst_icms ?? "—"}</td>
                        <td className="px-3 py-2 whitespace-nowrap text-xs text-zinc-300">{aliquotas(c)}</td>
                        <td className="px-3 py-2 text-right"><button type="button" onClick={() => escolher(c)} className="rounded-md bg-sky-700 px-3 py-1.5 text-xs font-medium text-white hover:bg-sky-600">Escolher</button></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : null}
          </div>
        ) : (
          <div className="space-y-3 p-4">
            <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 p-3 text-sm">
              Similar escolhido: <strong>#{escolhido.id}</strong>{escolhido.codigo ? ` · [${escolhido.codigo}]` : ""} · {escolhido.nome}
              {escolhido.fabricante ? <span className="text-zinc-400"> · {escolhido.fabricante}</span> : null}
            </div>
            <p className="text-xs text-zinc-400">Vêm marcados só os campos vazios no item #{itemId}. Um campo já preenchido só é trocado se você marcar.</p>
            <div className="overflow-x-auto rounded-lg border border-zinc-800">
              <table className="w-full min-w-[720px] text-left text-sm">
                <thead className="bg-zinc-900/60 text-xs uppercase text-zinc-500">
                  <tr>
                    <th className="w-10 px-3 py-2">Copiar</th>
                    <th className="px-3 py-2">Campo</th>
                    <th className="px-3 py-2">Item #{itemId} (atual)</th>
                    <th className="px-3 py-2"></th>
                    <th className="px-3 py-2">Similar #{escolhido.id}</th>
                  </tr>
                </thead>
                <tbody>
                  {CAMPOS.map(({ campo, rotulo, mora }) => {
                    const valor = valorAtual(campo);
                    const antigo = campo === "ncm" ? atual?.ncm_cadastro_antigo : campo === "cest" ? atual?.cest_cadastro_antigo : null;
                    const copiavel = podeCopiar(campo, escolhido);
                    const mesmo = igual(campo, valor, escolhido[campo]);
                    const marcado = marcados.has(campo);
                    return (
                      <tr key={campo} className={`border-t border-zinc-800 ${marcado ? "bg-sky-950/20" : ""}`}>
                        <td className="px-3 py-2">
                          <input
                            type="checkbox"
                            aria-label={`Copiar ${rotulo}`}
                            checked={marcado}
                            disabled={!copiavel || gravando}
                            onChange={() => alternar(campo)}
                          />
                        </td>
                        <td className="px-3 py-2">
                          <div>{rotulo}</div>
                          <div className="font-mono text-[11px] text-zinc-600">{mora}</div>
                        </td>
                        <td className="px-3 py-2">
                          <span className={vazio(valor) ? "text-amber-300" : ""}>{vazio(valor) ? "vazio" : mostrar(campo, valor)}</span>
                          {vazio(valor) && antigo ? <div className="text-xs text-zinc-500">no cadastro antigo: {mostrar(campo, antigo)}{!igual(campo, antigo, escolhido[campo]) && !vazio(escolhido[campo]) ? " (diferente do similar)" : ""}</div> : null}
                        </td>
                        <td className="px-3 py-2 text-zinc-500">→</td>
                        <td className="px-3 py-2">
                          {mostrar(campo, escolhido[campo])}
                          {!copiavel && campo === "origem" && semOrigemCopiavel ? <div className="text-xs text-amber-300">Importação própria: só vale com a equiparação declarada no próprio item. Informe a origem no cadastro do item.</div> : null}
                          {!copiavel && campo !== "origem" ? <div className="text-xs text-zinc-500">o similar não tem</div> : null}
                          {copiavel && !vazio(valor) && mesmo ? <div className="text-xs text-zinc-500">igual</div> : null}
                          {copiavel && !vazio(valor) && !mesmo ? <div className="text-xs text-amber-300">diferente: só troca se marcar</div> : null}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            <p className="text-xs text-zinc-500">
              Não são copiados: cEnq do IPI (vem do perfil de operação), FCI, equiparação a industrial e origem declarada pelo fornecedor (são do próprio produto).
            </p>
            {trocasDePreenchido.length > 0 ? (
              <div role="status" className="rounded border border-amber-800 bg-amber-950/20 p-3 text-sm text-amber-100">
                Você marcou para trocar valor já preenchido: {trocasDePreenchido.map((c) => c.rotulo).join(", ")}.
              </div>
            ) : null}
            {erro ? <div role="alert" className="rounded border border-red-900 bg-red-950/30 p-3 text-sm text-red-200">{erro}</div> : null}
            <div className="flex flex-wrap items-center justify-between gap-2">
              <button type="button" onClick={() => { setEscolhido(null); setErro(null); }} disabled={gravando} className="rounded-md border border-zinc-700 px-4 py-2 text-sm hover:bg-zinc-900 disabled:opacity-40">Voltar à lista</button>
              <button type="button" onClick={() => void copiar()} disabled={gravando || marcados.size === 0} className="rounded-md bg-sky-600 px-4 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:cursor-not-allowed disabled:opacity-50">
                {gravando ? "Copiando..." : marcados.size === 0 ? "Marque ao menos um campo" : `Copiar para o item #${itemId}`}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
