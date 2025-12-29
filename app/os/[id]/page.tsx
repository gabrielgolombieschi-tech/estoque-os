"use client";

import { useEffect, useMemo, useState } from "react";
import { useParams } from "next/navigation";
import { supabaseBrowser } from "../../../lib/supabase/client";
import { useRef } from "react";

type OS = {
  id: number;
  numero_os: string;
  cliente_nome: string;
  status: "aberta" | "em_andamento" | "concluida" | "cancelada";
  descricao_servico: string | null;
  valor_total: number;
  data_abertura: string;
  orcado: number | null;
  tipo_pedido?: string | null;
};

type OsItemRow = {
  id: number;
  item_id: number;
  quantidade: number;
  valor_unitario: number;
  valor_total: number;
  baixa_estoque: boolean;
  itens: { nome: string; codigo_interno: string; tipo: string } | null;
};

type ItemPick = {
  id: number;
  codigo_interno: string;
  nome: string;
  tipo: string;
  preco_unitario: number;
  aliquota_ipi?: number | null;
};

type ItemLookupRow = ItemPick & {
  fornecedor: string | null;
  ultima_entrada: string | null;
  estoque_atual?: number | null;
};

type SortKey = "id" | "codigo" | "descricao" | "fornecedor" | "ultima" | "preco" | "estoque";
type SortDir = "asc" | "desc";

const statusBadge: Record<string, string> = {
  aberta: "bg-blue-500/15 text-blue-300 border-blue-500/30",
  em_andamento: "bg-amber-500/15 text-amber-300 border-amber-500/30",
  concluida: "bg-emerald-500/15 text-emerald-300 border-emerald-500/30",
  cancelada: "bg-red-500/15 text-red-300 border-red-500/30",
};

export default function OsDetailPage() {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const params = useParams();
  const osId = Number(params.id);

  const [os, setOs] = useState<OS | null>(null);
  const [rows, setRows] = useState<OsItemRow[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // adicionar item
  const [q, setQ] = useState("");
  const [searching, setSearching] = useState(false);
  const [found, setFound] = useState<ItemPick[]>([]);
  const [pick, setPick] = useState<ItemPick | null>(null);
  const [qty, setQty] = useState<number>(1);
  const [vunit, setVunit] = useState<number>(0);
  const [baixa, setBaixa] = useState<boolean>(true);
  const qtyRef = useRef<HTMLInputElement | null>(null);
  const [showLookup, setShowLookup] = useState(false);
  const [lookupNome, setLookupNome] = useState("");
  const [lookupFornecedor, setLookupFornecedor] = useState("");
  const [lookupRows, setLookupRows] = useState<ItemLookupRow[]>([]);
  const [lookupBusy, setLookupBusy] = useState(false);
  const [lookupErr, setLookupErr] = useState<string | null>(null);
  const [sortKey, setSortKey] = useState<SortKey>("id");
  const [sortDir, setSortDir] = useState<SortDir>("asc");

  const locked = os?.status === "concluida" || os?.status === "cancelada";
  const formatMoney = (v: number) =>
    Number(v || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  const totais = (() => {
    const materiais = rows
      .filter((r) => r.itens?.tipo === "produto")
      .reduce((sum, r) => sum + Number(r.valor_total ?? 0), 0);
    const maoObra = rows
      .filter((r) => r.itens?.tipo === "servico")
      .reduce((sum, r) => sum + Number(r.valor_total ?? 0), 0);
    const imposto = Number(os?.orcado ?? 0) * 0.22;
    const total = materiais + maoObra + imposto;
    return { materiais, maoObra, imposto, total };
  })();

  const totalAlert = Number(os?.orcado ?? 0) > 0 && totais.total >= Number(os?.orcado ?? 0) * 0.9;
  const totalClass = totalAlert ? "text-red-300 border-red-500/40" : "text-emerald-300 border-emerald-500/40";

  const calculateUnitPriceWithTaxes = (item: { preco_unitario?: number | null; aliquota_ipi?: number | null }) => {
    const base = Number(item.preco_unitario ?? 0);
    const ipi = Number(item.aliquota_ipi ?? 0);
    const ipiPerc = Number.isFinite(ipi) ? ipi : 0;
    const final = base * (1 + ipiPerc / 100);
    return Math.round(final * 100) / 100;
  };

  async function load() {
    setErr(null);

    const { data: osData, error: osErr } = await supabase
      .from("ordens_servico")
      .select("id,numero_os,cliente_nome,status,descricao_servico,valor_total,data_abertura,orcado,tipo_pedido")
      .eq("id", osId)
      .single();

    if (osErr) {
      setErr(osErr.message);
      return;
    }
    setOs(osData as OS);

    const { data: itemsData, error: itemsErr } = await supabase
      .from("os_itens")
      .select("id,item_id,quantidade,valor_unitario,valor_total,baixa_estoque,itens(nome,codigo_interno,tipo)")
      .eq("os_id", osId)
      .order("id", { ascending: false });

    if (itemsErr) setErr(itemsErr.message);
    else setRows((itemsData ?? []) as unknown as OsItemRow[]);
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [osId]);

  async function removeItem(osItemId: number) {
    const ok = confirm("Remover este item da OS?\nSe baixou estoque, será devolvido.");
    if (!ok) return;

    setBusy(true);
    setErr(null);

    const { data: sess } = await supabase.auth.getSession();
    const userEmail = sess.session?.user?.email ?? null;

    const { error } = await supabase.rpc("remove_os_item_reverte_estoque", {
      p_os_item_id: osItemId,
      p_realizado_por: userEmail,
      p_motivo: "Remoção pelo app (devolução automática)",
    });

    setBusy(false);

    if (error) return setErr(error.message);

    await load();
  }

  async function setStatus(newStatus: OS["status"]) {
    if (!os) return;

    if (newStatus === "concluida") {
      const ok = confirm("Concluir esta OS? Depois disso, a edição será bloqueada.");
      if (!ok) return;
    }
    if (newStatus === "cancelada") {
      const ok = confirm("Cancelar esta OS? Depois disso, a edição será bloqueada.");
      if (!ok) return;
    }

    setBusy(true);
    setErr(null);

    const patch: any = { status: newStatus, atualizado_em: new Date().toISOString() };
    if (newStatus === "concluida") patch.data_conclusao = new Date().toISOString();

    const { error } = await supabase
      .from("ordens_servico")
      .update(patch)
      .eq("id", os.id);

    setBusy(false);
    if (error) return setErr(error.message);

    await load();
  }

  async function handleSearch(nextNome?: string, nextFornecedor?: string) {
    setLookupErr(null);
    setLookupBusy(true);

    const nomeTerm = (nextNome ?? lookupNome).trim();
    const fornecedorTerm = (nextFornecedor ?? lookupFornecedor).trim();

    const baseSelect = fornecedorTerm
      ? "id,codigo_interno,nome,tipo,preco_unitario,aliquota_ipi,fornecedores:fornecedor_id!inner(nome)"
      : "id,codigo_interno,nome,tipo,preco_unitario,aliquota_ipi,fornecedores:fornecedor_id(nome)";

    let query = supabase.from("itens").select(baseSelect).eq("ativo", true);

    if (nomeTerm) query = query.ilike("nome", `%${nomeTerm}%`);
    if (fornecedorTerm) query = query.ilike("fornecedores.nome", `%${fornecedorTerm}%`);

    const { data, error } = await query.order("nome", { ascending: true }).limit(50);

    if (error) {
      setLookupErr(error.message);
      setLookupRows([]);
      setLookupBusy(false);
      return;
    }

    const baseRows = (data ?? []) as any[];
    const ids = baseRows.map((r) => r.id);
    const ultimaMap = new Map<number, string>();

    const stockMap = new Map<number, number>();

    if (ids.length > 0) {
      const { data: movData, error: movErr } = await supabase
        .from("movimentacoes")
        .select("item_id,data_movimentacao")
        .eq("tipo", "entrada")
        .in("item_id", ids)
        .order("data_movimentacao", { ascending: false });

      if (!movErr) {
        (movData ?? []).forEach((m: any) => {
          if (!ultimaMap.has(m.item_id)) ultimaMap.set(m.item_id, m.data_movimentacao as string);
        });
      }

      const { data: estData } = await supabase
        .from("estoque")
        .select("item_id,quantidade_atual")
        .in("item_id", ids);
      (estData ?? []).forEach((e: any) => {
        stockMap.set(e.item_id, Number(e.quantidade_atual ?? 0));
      });
    }

    setLookupRows(
      baseRows.map((r: any) => ({
        id: r.id,
        codigo_interno: r.codigo_interno,
        nome: r.nome,
        tipo: r.tipo,
        preco_unitario: r.preco_unitario,
        aliquota_ipi: r.aliquota_ipi,
        fornecedor: r.fornecedores?.nome ?? null,
        ultima_entrada: ultimaMap.get(r.id) ?? null,
        estoque_atual: stockMap.has(r.id) ? stockMap.get(r.id)! : null,
      }))
    );

    setLookupBusy(false);
  }

  function sortRows(rows: ItemLookupRow[], key: SortKey, dir: SortDir): ItemLookupRow[] {
    const factor = dir === "asc" ? 1 : -1;
    return [...rows].sort((a, b) => {
      const val = (k: SortKey): any => {
        switch (k) {
          case "id":
            return a.id;
          case "codigo":
            return a.codigo_interno?.toLowerCase() ?? "";
          case "descricao":
            return a.nome?.toLowerCase() ?? "";
          case "fornecedor":
            return a.fornecedor?.toLowerCase() ?? "";
          case "ultima":
            return a.ultima_entrada ? new Date(a.ultima_entrada).getTime() : null;
          case "preco":
            return typeof a.preco_unitario === "number" ? a.preco_unitario : null;
          case "estoque":
            return typeof a.estoque_atual === "number" ? a.estoque_atual : null;
        }
      };
      const va = val(key);
      const vb = (() => {
        switch (key) {
          case "id":
            return b.id;
          case "codigo":
            return b.codigo_interno?.toLowerCase() ?? "";
          case "descricao":
            return b.nome?.toLowerCase() ?? "";
          case "fornecedor":
            return b.fornecedor?.toLowerCase() ?? "";
          case "ultima":
            return b.ultima_entrada ? new Date(b.ultima_entrada).getTime() : null;
          case "preco":
            return typeof b.preco_unitario === "number" ? b.preco_unitario : null;
          case "estoque":
            return typeof b.estoque_atual === "number" ? b.estoque_atual : null;
        }
      })();

      // Nulls sempre no final
      const aNull = va === null || va === undefined || va === "";
      const bNull = vb === null || vb === undefined || vb === "";
      if (aNull && bNull) return 0;
      if (aNull) return 1;
      if (bNull) return -1;

      if (va < vb) return -1 * factor;
      if (va > vb) return 1 * factor;
      return 0;
    });
  }

  function handleSort(key: SortKey) {
    if (sortKey === key) {
      setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    } else {
      setSortKey(key);
      setSortDir("asc");
    }
  }

  const sortedRows = useMemo(() => sortRows(lookupRows, sortKey, sortDir), [lookupRows, sortKey, sortDir]);

  function openLookupModal() {
    setShowLookup(true);
    setLookupErr(null);
    setLookupRows([]);
    setLookupNome("");
    setLookupFornecedor("");
    handleSearch("", "");
  }

  async function searchItems() {
    setErr(null);
    setFound([]);

    const term = q.trim();
    const id = Number(term);
    if (!term || !Number.isFinite(id) || id <= 0) {
      openLookupModal();
      return;
    }

    setSearching(true);

    const { data, error } = await supabase
      .from("itens")
      .select("id,codigo_interno,nome,tipo,preco_unitario,aliquota_ipi")
      .eq("id", id)
      .maybeSingle();

    setSearching(false);

    if (error || !data) {
      setErr("Item nao encontrado pelo ID informado. Use a busca por nome/fabricante.");
      openLookupModal();
      return;
    }

    pickItem(data as ItemPick);
  }

  function pickItem(it: ItemPick) {
    setPick(it);
    setFound([]);
    setQ(`${it.codigo_interno} - ${it.nome}`);
    setQty(1);
    setVunit(calculateUnitPriceWithTaxes(it));
    // default: baixa estoque apenas se for produto
    setBaixa(it.tipo === "produto");
    setTimeout(() => {
      qtyRef.current?.focus();
      qtyRef.current?.select();
    }, 0);
  }

  async function addItem() {
    if (!pick) return setErr("Selecione um item.");
    if (qty <= 0) return setErr("Quantidade inválida.");
    if (vunit < 0) return setErr("Valor unitário inválido.");

    setBusy(true);
    setErr(null);

    const { data: sess } = await supabase.auth.getSession();
    const userEmail = sess.session?.user?.email ?? null;

    // RPC FINAL: baixa imediata
    const { error } = await supabase.rpc("add_os_item_baixa_imediata", {
      p_os_id: osId,
      p_item_id: pick.id,
      p_quantidade: Math.trunc(qty),
      p_valor_unitario: Number(vunit),
      p_baixa_estoque: baixa,
      p_realizado_por: userEmail,
      p_motivo: "Adição pela tela da OS (baixa imediata)",
    });

    setBusy(false);

    if (error) return setErr(error.message);

    // limpa form
    setPick(null);
    setQ("");
    setFound([]);
    setQty(1);
    setVunit(0);
    setBaixa(true);

    await load();
  }

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div className="space-y-2">
          <a href="/os" className="text-sm text-zinc-300 hover:text-zinc-100">
            ← Voltar
          </a>

          <div className="flex items-center gap-2 flex-wrap">
            <h1 className="text-2xl font-semibold">
              {os ? `OS ${os.numero_os} — ${os.cliente_nome}` : "Carregando..."}
            </h1>

            {os?.status && (
              <span
                className={[
                  "inline-flex items-center px-2 py-1 rounded-md border text-xs",
                  statusBadge[os.status] ?? "bg-zinc-500/10 text-zinc-300 border-zinc-500/30",
                ].join(" ")}
              >
                {os.status}
              </span>
            )}
          </div>

          {os && (
            <div className="text-sm text-zinc-400 space-y-1">
              <div>Abertura: {new Date(os.data_abertura).toLocaleString("pt-BR")}</div>
              <div className="flex flex-wrap items-center gap-2 text-xs md:text-sm">
                <span>
                  Material: <span className="text-zinc-200 tabular-nums">R$ {formatMoney(totais.materiais)}</span>
                </span>
                <span>
                  - Mão de obra: <span className="text-zinc-200 tabular-nums">R$ {formatMoney(totais.maoObra)}</span>
                </span>
                <span>
                  - Imposto: <span className="text-zinc-200 tabular-nums">R$ {formatMoney(totais.imposto)}</span>
                </span>
                <span className="text-base md:text-lg font-semibold text-zinc-100">
                  - Total:{" "}
                  <span
                    className={`inline-flex items-center px-2 py-1 rounded-md border tabular-nums ${totalClass}`}
                  >
                    R$ {formatMoney(totais.total)}
                  </span>
                </span>
              </div>
            </div>
          )}
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={load}
            disabled={busy}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Atualizar
          </button>

          <button
            onClick={() => setStatus("em_andamento")}
            disabled={busy}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Em andamento
          </button>

          <button
            onClick={() => setStatus("concluida")}
            disabled={busy || locked}
            className="px-3 py-2 rounded-md bg-emerald-300 text-emerald-950 hover:bg-emerald-200 font-medium"
          >
            Concluir
          </button>

          <button
            onClick={() => setStatus("cancelada")}
            disabled={busy || locked}
            className="px-3 py-2 rounded-md bg-red-300 text-red-950 hover:bg-red-200 font-medium"
          >
            Cancelar
          </button>
        </div>
      </div>

      {locked && (
        <div className="border border-zinc-800 rounded-xl p-3 bg-zinc-950 text-sm text-zinc-300">
          Esta OS está <b>{os?.status}</b>. Edição bloqueada.
        </div>
      )}

      {err && <div className="text-sm text-red-400">{err}</div>}

      {/* Descrição */}
      {os?.descricao_servico && (
        <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
          <div className="font-medium">Descrição</div>
          <div className="text-sm text-zinc-300 mt-2 whitespace-pre-wrap">
            {os.descricao_servico}
          </div>
        </div>
      )}

      {/* Adicionar item */}
      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="flex items-center justify-between flex-wrap gap-2">
          <div>
            <div className="font-medium">Adicionar item</div>
            <div className="text-sm text-zinc-400 mt-1">
              Produto/serviço/despesa. Produto pode dar baixa no estoque.
            </div>
          </div>

          <button
            onClick={addItem}
            disabled={busy || locked}
            className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
          >
            {busy ? "Aguarde..." : "Adicionar"}
          </button>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-6 gap-3 mt-4">
          <div className="md:col-span-3 space-y-1 relative">
            <div className="text-xs text-zinc-400">Buscar item</div>
            <div className="flex gap-2">
              <input
                className="w-full px-3 py-2"
                value={q}
                onChange={(e) => setQ(e.target.value)}
                placeholder="ID do item (ex: 123). Enter abre localizacao se nao souber."
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    e.preventDefault();
                    searchItems();
                  }
                }}
                disabled={locked}
              />
              <button
                onClick={searchItems}
                disabled={searching || locked}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                {searching ? "..." : "Buscar"}
              </button>
            </div>

            {found.length > 0 && (
              <div className="absolute z-20 mt-2 w-full border border-zinc-800 rounded-lg bg-zinc-950 overflow-hidden">
                {found.map((it) => (
                  <button
                    key={it.id}
                    onClick={() => pickItem(it)}
                    className="w-full text-left px-3 py-2 hover:bg-zinc-900"
                  >
                    <div className="text-sm font-medium">
                      [{it.codigo_interno}] {it.nome}
                    </div>
                    <div className="text-xs text-zinc-400">{it.tipo}</div>
                  </button>
                ))}
              </div>
            )}
          </div>

          <div className="md:col-span-1 space-y-1">
            <div className="text-xs text-zinc-400">Qtd</div>
            <input
              type="number"
              ref={qtyRef}
              className="w-full px-3 py-2"
              value={qty}
              onChange={(e) => setQty(Number(e.target.value))}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  addItem();
                }
              }}
              disabled={locked}
            />
          </div>

          <div className="md:col-span-1 space-y-1">
            <div className="text-xs text-zinc-400">V.Unit</div>
            <input
              type="number"
              className="w-full px-3 py-2"
              value={vunit}
              onChange={(e) => setVunit(Number(e.target.value))}
              disabled={locked}
            />
            {pick && (
              <div className="text-[11px] text-zinc-400">
                Base: R$ {formatMoney(Number(pick.preco_unitario ?? 0))} | IPI: {(Number(pick.aliquota_ipi ?? 0) || 0).toFixed(2)}%
              </div>
            )}
          </div>

          <div className="md:col-span-1 space-y-1">
            <div className="text-xs text-zinc-400">Baixa estoque</div>
            <select
              className="w-full px-3 py-2"
              value={baixa ? "sim" : "nao"}
              onChange={(e) => setBaixa(e.target.value === "sim")}
              disabled={locked}
            >
              <option value="sim">Sim</option>
              <option value="nao">Não</option>
            </select>
          </div>
        </div>

        {pick && (
          <div className="text-sm text-zinc-300 mt-3">
            Selecionado: <b>[{pick.codigo_interno}] {pick.nome}</b> ({pick.tipo})
          </div>
        )}
      </div>

      {showLookup && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50">
          <div className="w-full max-w-5xl bg-zinc-950 border border-zinc-800 rounded-xl p-5 shadow-xl space-y-4">
            <div className="flex items-center justify-between gap-3">
              <div>
                <div className="text-lg font-semibold">Localizar item</div>
                <div className="text-sm text-zinc-400">Filtre por nome ou fabricante para localizar o ID.</div>
              </div>
              <button
                onClick={() => setShowLookup(false)}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Fechar
              </button>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Nome</div>
                <input
                  className="w-full px-3 py-2"
                  value={lookupNome}
                  onChange={(e) => setLookupNome(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") {
                      e.preventDefault();
                      handleSearch(e.currentTarget.value, lookupFornecedor);
                    }
                  }}
                />
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Fornecedor</div>
                <input
                  className="w-full px-3 py-2"
                  value={lookupFornecedor}
                  onChange={(e) => setLookupFornecedor(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") {
                      e.preventDefault();
                      handleSearch(lookupNome, e.currentTarget.value);
                    }
                  }}
                />
              </div>
            </div>

            <div className="flex items-center gap-2">
              <button
                onClick={() => handleSearch()}
                disabled={lookupBusy}
                className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
              >
                {lookupBusy ? "Buscando..." : "Buscar"}
              </button>
              <button
                onClick={() => {
                  setLookupNome("");
                  setLookupFornecedor("");
                  setLookupRows([]);
                  setLookupErr(null);
                  handleSearch("", "");
                }}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Limpar
              </button>
            </div>

            {lookupErr && <div className="text-sm text-red-400">{lookupErr}</div>}

            <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
              <table className="w-full text-sm">
                <thead className="bg-zinc-900/70">
                  <tr className="text-left text-zinc-200">
                    <th className="px-4 py-3 cursor-pointer" onClick={() => handleSort("id")}>
                      ID {sortKey === "id" && (sortDir === "asc" ? "▲" : "▼")}
                    </th>
                    <th className="px-4 py-3 cursor-pointer" onClick={() => handleSort("codigo")}>
                      Codigo {sortKey === "codigo" && (sortDir === "asc" ? "▲" : "▼")}
                    </th>
                    <th className="px-4 py-3 cursor-pointer" onClick={() => handleSort("descricao")}>
                      Descricao {sortKey === "descricao" && (sortDir === "asc" ? "▲" : "▼")}
                    </th>
                    <th className="px-4 py-3 cursor-pointer" onClick={() => handleSort("fornecedor")}>
                      Fornecedor {sortKey === "fornecedor" && (sortDir === "asc" ? "▲" : "▼")}
                    </th>
                    <th className="px-4 py-3 cursor-pointer" onClick={() => handleSort("ultima")}>
                      Ultima entrada {sortKey === "ultima" && (sortDir === "asc" ? "▲" : "▼")}
                    </th>
                    <th className="px-4 py-3 text-right cursor-pointer" onClick={() => handleSort("preco")}>
                      Preco {sortKey === "preco" && (sortDir === "asc" ? "▲" : "▼")}
                    </th>
                    <th className="px-4 py-3 text-right cursor-pointer" onClick={() => handleSort("estoque")}>
                      Saldo {sortKey === "estoque" && (sortDir === "asc" ? "▲" : "▼")}
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-zinc-800">
                  {sortedRows.map((it) => (
                    <tr
                      key={it.id}
                      className="hover:bg-zinc-900/40 cursor-pointer"
                      onClick={() => {
                        pickItem(it);
                        setShowLookup(false);
                      }}
                    >
                      <td className="px-4 py-3 tabular-nums">{it.id}</td>
                      <td className="px-4 py-3">{it.codigo_interno}</td>
                      <td className="px-4 py-3">{it.nome}</td>
                      <td className="px-4 py-3 text-zinc-300">{it.fornecedor ?? "—"}</td>
                      <td className="px-4 py-3 text-zinc-300">
                        {it.ultima_entrada ? new Date(it.ultima_entrada).toLocaleDateString("pt-BR") : "—"}
                      </td>
                      <td className="px-4 py-3 text-right tabular-nums">R$ {formatMoney(Number(it.preco_unitario ?? 0))}</td>
                      <td className="px-4 py-3 text-right tabular-nums">
                        {typeof it.estoque_atual === "number" ? Number(it.estoque_atual).toFixed(0) : "—"}
                      </td>
                    </tr>
                  ))}

                  {lookupRows.length === 0 && (
                    <tr>
                      <td colSpan={6} className="px-4 py-6 text-zinc-400 text-center">
                        Nenhum resultado ainda. Informe filtros e busque.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {/* Tabela itens */}
      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-900/60">
            <tr className="text-left text-zinc-200">
              <th className="px-4 py-3">ID</th>
              <th className="px-4 py-3">Item</th>
              <th className="px-4 py-3 text-right">Qtd</th>
              <th className="px-4 py-3 text-right">V.Unit</th>
              <th className="px-4 py-3 text-right">Total</th>
              <th className="px-4 py-3 text-center">Baixa</th>
              <th className="px-4 py-3 text-center">Ações</th>
            </tr>
          </thead>

          <tbody className="divide-y divide-zinc-800">
            {rows.map((r) => (
              <tr key={r.id} className="hover:bg-zinc-900/40">
                <td className="px-4 py-3 tabular-nums">{r.item_id}</td>
                <td className="px-4 py-3">
                  {r.itens ? (
                    <>
                      <div className="font-medium">
                        [{r.itens.codigo_interno}] {r.itens.nome}
                      </div>
                      <div className="text-xs text-zinc-400">{r.itens.tipo}</div>
                    </>
                  ) : (
                    <span className="text-zinc-400">Item {r.item_id}</span>
                  )}
                </td>

                <td className="px-4 py-3 text-right tabular-nums">
                  {Number(r.quantidade).toFixed(0)}
                </td>

                <td className="px-4 py-3 text-right tabular-nums">
                  R$ {formatMoney(Number(r.valor_unitario))}
                </td>

                <td className="px-4 py-3 text-right tabular-nums">
                  R$ {formatMoney(Number(r.valor_total))}
                </td>

                <td className="px-4 py-3 text-center">{r.baixa_estoque ? "✅" : "—"}</td>

                <td className="px-4 py-3 text-center">
                  <button
                    onClick={() => removeItem(r.id)}
                    disabled={busy || locked}
                    className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                  >
                    Remover
                  </button>
                </td>
              </tr>
            ))}

            {rows.length === 0 && (
              <tr>
                <td className="px-4 py-6 text-zinc-400" colSpan={6}>
                  Nenhum item ainda.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
