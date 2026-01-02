"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

type ItemRow = {
  id: string;
  codigo: string;
  descricao: string;
  quantidade: number | null;
  quantidadeText: string;
  itemId: number | null;
  tipo: string | null;
  controlaEstoque: boolean | null;
  valorUnitario: number | null;
  estoqueAtual: number | null;
  itemFound?: boolean | null;
  itemLoading?: boolean;
  itemError?: string | null;
};

type OsInfo = {
  id: number;
  descricao: string;
  status: string;
  clienteNome: string;
};

type CachedItem = {
  id: number;
  descricao: string;
  tipo: string | null;
  controlaEstoque: boolean | null;
  valorUnitario: number | null;
  estoqueAtual: number | null;
};

const createEmptyRow = (): ItemRow => ({
  id:
    typeof crypto !== "undefined" && crypto.randomUUID
      ? crypto.randomUUID()
      : Math.random().toString(36).slice(2, 8),
  codigo: "",
  descricao: "",
  quantidade: null,
  quantidadeText: "",
  itemId: null,
  tipo: null,
  controlaEstoque: null,
  valorUnitario: null,
  estoqueAtual: null,
  itemFound: null,
  itemLoading: false,
  itemError: null,
});

const isRowEmpty = (row: ItemRow) =>
  row.codigo.trim() === "" && row.descricao.trim() === "" && row.quantidadeText.trim() === "";

const isRowComplete = (row: ItemRow) => {
  const qtyValid = row.quantidade !== null && !Number.isNaN(row.quantidade);
  const hasFound = row.itemFound === true;
  const hasId = row.itemId !== null;
  return hasFound && qtyValid && hasId;
};

function ensureTrailingEmptyRow(rows: ItemRow[]) {
  let next = rows.length ? [...rows] : [createEmptyRow()];

  while (next.length > 1 && isRowEmpty(next[next.length - 1]) && isRowEmpty(next[next.length - 2])) {
    next.pop();
  }

  const last = next[next.length - 1];
  if (isRowComplete(last)) {
    next.push(createEmptyRow());
  }

  return next;
}

const statusLabels: Record<string, { label: string; className: string }> = {
  em_andamento: { label: "Em andamento", className: "bg-emerald-900/50 text-emerald-100" },
  aberta: { label: "Aberta", className: "bg-zinc-800 text-zinc-200" },
  concluida: { label: "Concluida", className: "bg-blue-900/50 text-blue-100" },
  cancelada: { label: "Cancelada", className: "bg-red-900/50 text-red-100" },
};

export default function BaixaOsPage() {
  const supabase = supabaseBrowser();

  const [os, setOs] = useState("");
  const [osDescricao, setOsDescricao] = useState("");
  const [osId, setOsId] = useState<number | null>(null);
  const [osStatus, setOsStatus] = useState<string | null>(null);
  const [osClienteNome, setOsClienteNome] = useState("");
  const [osLoading, setOsLoading] = useState(false);
  const [osError, setOsError] = useState<string | null>(null);

  const [rows, setRows] = useState<ItemRow[]>([createEmptyRow()]);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const validItems = useMemo(() => rows.filter(isRowComplete), [rows]);

  const osCacheRef = useRef<Record<string, OsInfo | null>>({});
  const itemCacheRef = useRef<Record<string, CachedItem | null>>({});
  const osDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const itemDebounceRef = useRef<Record<string, ReturnType<typeof setTimeout>>>({});

  const normalizeOsNumber = (numero: string) => {
    const trimmed = numero.trim();
    if (/^\d+$/.test(trimmed)) {
      return String(Number(trimmed));
    }
    return trimmed;
  };

  const fetchClienteNome = async (clienteId: number | null, clienteNomeInline: string | null) => {
    if (clienteNomeInline && clienteNomeInline.trim() !== "") {
      return clienteNomeInline.trim();
    }
    if (!clienteId) return "-";

    const { data, error } = await supabase
      .from("clientes")
      .select("nome,razao_social")
      .eq("id", clienteId)
      .maybeSingle();

    if (error || !data) return "-";
    const nome = (data as any).nome ?? (data as any).razao_social ?? "";
    return nome.trim() === "" ? "-" : nome;
  };

  const fetchOs = async (numero: string) => {
    const normalized = normalizeOsNumber(numero);
    if (!normalized) {
      setOsDescricao("");
      setOsId(null);
      setOsStatus(null);
      setOsClienteNome("");
      setOsError(null);
      return;
    }

    if (osCacheRef.current[normalized] !== undefined) {
      const cached = osCacheRef.current[normalized];
      if (cached) {
        setOsDescricao(cached.descricao);
        setOsId(cached.id);
        setOsStatus(cached.status);
        setOsClienteNome(cached.clienteNome);
        setOsError(null);
      } else {
        setOsDescricao("");
        setOsId(null);
        setOsStatus(null);
        setOsClienteNome("");
        setOsError("OS nao encontrada");
      }
      return;
    }

    setOsLoading(true);
    setOsError(null);

    const { data, error: queryError } = await supabase
      .from("ordens_servico")
      .select("id,descricao_servico,status,cliente_nome,cliente_id")
      .eq("numero_os", normalized)
      .maybeSingle();

    setOsLoading(false);

    if (queryError) {
      setOsDescricao("");
      setOsId(null);
      setOsStatus(null);
      setOsClienteNome("");
      setOsError("Erro ao buscar OS");
      osCacheRef.current[normalized] = null;
      return;
    }

    if (!data) {
      setOsDescricao("");
      setOsId(null);
      setOsStatus(null);
      setOsClienteNome("");
      setOsError("OS nao encontrada");
      osCacheRef.current[normalized] = null;
      return;
    }

    const osIdDb = Number((data as any).id ?? null);
    const descricaoDb = (data as any).descricao_servico ?? (data as any).descricao ?? "";
    const statusDb = (data as any).status ?? null;
    const clienteNomeInline = (data as any).cliente_nome ?? null;
    const clienteId = (data as any).cliente_id ?? null;

    const clienteNome = await fetchClienteNome(clienteId, clienteNomeInline);

    osCacheRef.current[normalized] = { id: osIdDb, descricao: descricaoDb, status: statusDb, clienteNome };
    setOsDescricao(descricaoDb);
    setOsId(osIdDb);
    setOsStatus(statusDb);
    setOsClienteNome(clienteNome);
    setOsError(null);
  };

  const fetchItem = async (rowId: string, codigo: string) => {
    const trimmed = codigo.trim();
    if (!trimmed) {
      setRows((prev) =>
        prev.map((r) =>
          r.id === rowId
            ? {
                ...r,
                descricao: "",
                itemId: null,
                tipo: null,
                controlaEstoque: null,
                valorUnitario: null,
                estoqueAtual: null,
                itemFound: null,
                itemError: null,
                itemLoading: false,
              }
            : r
        )
      );
      return;
    }

    const isNumeric = /^\d+$/.test(trimmed);
    const cacheKey = isNumeric ? String(Number(trimmed)) : trimmed;
    const queryValue = isNumeric ? Number(cacheKey) : trimmed;

    if (itemCacheRef.current[cacheKey] !== undefined) {
      const cached = itemCacheRef.current[cacheKey];
      // se cache antigo sem ID, refaz busca para recuperar dados completos
      if (cached && (cached.id === undefined || cached.id === null)) {
        delete itemCacheRef.current[cacheKey];
      } else {
        setRows((prev) =>
          prev.map((r) =>
            r.id === rowId
              ? {
                  ...r,
                  descricao: cached?.descricao ?? "",
                  itemId: cached?.id ?? null,
                  tipo: cached?.tipo ?? null,
                  controlaEstoque: cached?.controlaEstoque ?? null,
                  valorUnitario: cached?.valorUnitario ?? null,
                  estoqueAtual: cached?.estoqueAtual ?? null,
                  itemFound: cached !== null,
                  itemError: cached ? null : "Item nao encontrado",
                  itemLoading: false,
                }
              : r
          )
        );
        return;
      }
    }

    setRows((prev) =>
      prev.map((r) => (r.id === rowId ? { ...r, itemLoading: true, itemError: null } : r))
    );

    let data: any = null;
    let queryError: any = null;

    const selectFields = "id,codigo_interno,nome,descricao,tipo,controla_estoque,preco_unitario";

    if (isNumeric) {
      const byNumber = await supabase.from("itens").select(selectFields).eq("id", queryValue).maybeSingle();
      data = byNumber.data;
      queryError = byNumber.error;
      if (!data && !queryError) {
        const byString = await supabase.from("itens").select(selectFields).eq("id", cacheKey).maybeSingle();
        data = byString.data;
        queryError = byString.error;
      }
    } else {
      const byString = await supabase.from("itens").select(selectFields).eq("id", queryValue).maybeSingle();
      data = byString.data;
      queryError = byString.error;
    }

    if (queryError) {
      setRows((prev) =>
        prev.map((r) =>
          r.id === rowId
            ? {
                ...r,
                descricao: "",
                itemId: null,
                tipo: null,
                controlaEstoque: null,
                valorUnitario: null,
                itemFound: false,
                itemError: "Erro ao buscar item",
                itemLoading: false,
              }
            : r
        )
      );
      itemCacheRef.current[cacheKey] = null;
      return;
    }

    if (!data) {
      setRows((prev) =>
        prev.map((r) =>
          r.id === rowId
            ? {
                ...r,
                descricao: "",
                itemId: null,
                tipo: null,
                controlaEstoque: null,
                valorUnitario: null,
                itemFound: false,
                itemError: "Item nao encontrado",
                itemLoading: false,
              }
            : r
        )
      );
      itemCacheRef.current[cacheKey] = null;
      return;
    }

    const codigoInterno = (data as any).codigo_interno ?? "";
    const nomeDesc = (data as any).nome ?? (data as any).descricao ?? "";
    const desc = codigoInterno ? `[${codigoInterno}] ${nomeDesc}` : nomeDesc;
    const tipo = (data as any).tipo ?? null;
    const controlaEstoque = (data as any).controla_estoque ?? null;
    const valorUnitarioRaw = Number((data as any).preco_unitario ?? null);
    const valorUnitario = Number.isFinite(valorUnitarioRaw) ? valorUnitarioRaw : null;
    const itemId = Number((data as any).id);

    let estoqueAtual: number | null = null;
    const { data: estoqueData } = await supabase.from("estoque").select("quantidade_atual").eq("item_id", itemId).maybeSingle();
    if (estoqueData) estoqueAtual = Number((estoqueData as any).quantidade_atual ?? 0);

    itemCacheRef.current[cacheKey] = { id: itemId, descricao: desc, tipo, controlaEstoque, valorUnitario, estoqueAtual };

    setRows((prev) =>
      ensureTrailingEmptyRow(
        prev.map((r) =>
          r.id === rowId
            ? {
                ...r,
                descricao: desc,
                itemId,
                tipo,
                controlaEstoque,
                valorUnitario,
                estoqueAtual,
                itemFound: true,
                itemError: null,
                itemLoading: false,
              }
            : r
        )
      )
    );
  };

  useEffect(() => {
    if (osDebounceRef.current) clearTimeout(osDebounceRef.current);
    osDebounceRef.current = setTimeout(() => {
      fetchOs(os);
    }, 400);

    return () => {
      if (osDebounceRef.current) clearTimeout(osDebounceRef.current);
    };
  }, [os]);

  useEffect(() => {
    return () => {
      if (osDebounceRef.current) clearTimeout(osDebounceRef.current);
      const timeouts = Object.values(itemDebounceRef.current);
      timeouts.forEach((t) => clearTimeout(t));
    };
  }, []);

  const handleRowChange = (id: string, field: "codigo" | "descricao" | "quantidade", value: string) => {
    setRows((prev) => {
      const updated = prev.map((row) => {
        if (row.id !== id) return row;

        if (field === "quantidade") {
          const normalized = value.replace(",", ".").trim();
          const parsed = normalized === "" ? null : Number(normalized);
          return {
            ...row,
            quantidadeText: value,
            quantidade: Number.isNaN(parsed) ? null : parsed,
          };
        }

        if (field === "codigo") {
          return {
            ...row,
            codigo: value,
            itemFound: null,
            itemError: null,
            itemId: null,
            tipo: null,
            controlaEstoque: null,
            valorUnitario: null,
            estoqueAtual: null,
          };
        }

        return row;
      });

      return ensureTrailingEmptyRow(updated);
    });

    if (field === "codigo") {
      if (itemDebounceRef.current[id]) clearTimeout(itemDebounceRef.current[id]);
      itemDebounceRef.current[id] = setTimeout(() => {
        fetchItem(id, value);
      }, 300);
    }
  };

  const removeRow = (id: string) => {
    setRows((prev) => {
      const idx = prev.findIndex((r) => r.id === id);
      if (idx === -1) return prev;
      if (idx === prev.length - 1 && isRowEmpty(prev[idx])) return prev;

      const next = prev.filter((r) => r.id !== id);
      return ensureTrailingEmptyRow(next.length ? next : [createEmptyRow()]);
    });
  };

  const handleSubmit = async () => {
    const messages: string[] = [];
    setSuccess(null);

    if (os.trim() === "") messages.push("Informe a OS");
    if (osStatus !== "em_andamento") messages.push("So e possivel baixar itens em OS em andamento.");
    if (!osId) messages.push("OS nao encontrada");

    const hasInvalidQty = rows.some((r) => r.quantidade === null && r.quantidadeText.trim() !== "");
    if (hasInvalidQty) messages.push("Quantidade invalida");

    const hasMissingCode = rows.some((r, idx) => {
      const isLastEmpty = idx === rows.length - 1 && isRowEmpty(r);
      if (isLastEmpty) return false;
      const hasCode = r.codigo.trim() !== "";
      const hasQty = r.quantidadeText.trim() !== "" || r.quantidade !== null;
      return hasCode && hasQty && r.itemFound !== true;
    });
    if (hasMissingCode) messages.push("Item nao encontrado");

    const hasMissingId = rows.some((r) => r.itemFound === true && r.itemId === null);
    if (hasMissingId) messages.push("Item invalido");

    if (validItems.length === 0) messages.push("Informe pelo menos 1 item");

    if (messages.length) {
      setError(messages[0]);
      return;
    }

    setError(null);

    const itemIds = validItems.map((r) => r.itemId).filter((id): id is number => id !== null);
    const estoqueMap = new Map<number, number>();
    if (itemIds.length > 0) {
      const { data: estoqueData, error: estoqueErr } = await supabase
        .from("estoque")
        .select("item_id,quantidade_atual")
        .in("item_id", itemIds);

      if (estoqueErr) {
        setError("Erro ao consultar estoque");
        return;
      }

      (estoqueData ?? []).forEach((e: any) => {
        estoqueMap.set(Number(e.item_id), Number(e.quantidade_atual ?? 0));
      });
    }

    const insuficiente = validItems.find((r) => {
      const precisaBaixa = (r.tipo ?? "").toLowerCase() === "produto" && r.controlaEstoque !== false;
      if (!precisaBaixa || r.itemId === null) return false;
      const saldo = estoqueMap.has(r.itemId) ? estoqueMap.get(r.itemId)! : 0;
      return Number(r.quantidade ?? 0) > saldo;
    });

    if (insuficiente) {
      const saldo =
        insuficiente.itemId !== null && estoqueMap.has(insuficiente.itemId)
          ? estoqueMap.get(insuficiente.itemId)!
          : 0;
      setError(
        `Sem saldo suficiente para o item ${insuficiente.codigo || insuficiente.descricao}. Saldo atual: ${saldo.toLocaleString(
          "pt-BR"
        )}`
      );
      return;
    }

    setSubmitting(true);

    const { data: sess } = await supabase.auth.getSession();
    const userEmail = sess.session?.user?.email ?? null;

    for (const item of validItems) {
      const precisaBaixa = (item.tipo ?? "").toLowerCase() === "produto" && item.controlaEstoque !== false;
      const { error: rpcErr } = await supabase.rpc("add_os_item_baixa_imediata", {
        p_os_id: osId,
        p_item_id: item.itemId,
        p_quantidade: item.quantidade as number,
        p_valor_unitario: Number(item.valorUnitario ?? 0),
        p_baixa_estoque: precisaBaixa,
        p_realizado_por: userEmail,
        p_motivo: "Baixa manual pela tela Baixa OS",
      });

      if (rpcErr) {
        setSubmitting(false);
        setError(rpcErr.message);
        return;
      }
    }

    setSubmitting(false);
    setSuccess("Itens baixados e registrados na OS.");
    setRows([createEmptyRow()]);
  };

  const canSubmit = osStatus === "em_andamento" && !!osDescricao && osId !== null;
  const submitEnabled = canSubmit && !submitting;

  const statusDisplay = osStatus ? statusLabels[osStatus]?.label ?? "-" : "-";
  const statusClass =
    osStatus && statusLabels[osStatus]
      ? statusLabels[osStatus].className
      : "bg-zinc-800 text-zinc-200";

  return (
    <div className="min-h-screen px-4 py-6">
      <div className="mx-auto max-w-3xl space-y-4">
        <header className="space-y-1">
          <p className="text-sm uppercase tracking-[0.08em] text-blue-300/80">Baixa de itens</p>
          <h1 className="text-2xl font-semibold text-zinc-100">Baixa OS</h1>
          <p className="text-sm text-zinc-400">Preencha a OS, itens e quantidades para baixar.</p>
        </header>

        <div className="space-y-3 rounded-2xl border border-zinc-800 bg-zinc-950 p-4 shadow">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <label className="flex flex-col gap-1 text-sm font-medium text-zinc-200 sm:col-span-1">
              <span>OS</span>
              <div className="relative">
                <input
                  value={os}
                  onChange={(e) => setOs(e.target.value)}
                  enterKeyHint="next"
                  className="w-full rounded-xl border border-zinc-800 bg-zinc-900 px-3 py-3 text-lg text-white placeholder:text-zinc-500 focus:border-blue-500 focus:outline-none"
                  placeholder="Numero da OS"
                  autoComplete="off"
                />
                {osLoading && (
                  <span className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-blue-300">
                    carregando...
                  </span>
                )}
              </div>
              {osError && <span className="text-xs text-red-300">{osError}</span>}
            </label>

            <label className="flex flex-col gap-1 text-sm font-medium text-zinc-200 sm:col-span-2">
              <span>Cliente</span>
              <input
                value={osClienteNome || "-"}
                readOnly
                title="Campo preenchido automaticamente"
                className="w-full rounded-xl border border-zinc-800 bg-zinc-900 px-3 py-3 text-lg text-white placeholder:text-zinc-500 focus:border-blue-500 focus:outline-none opacity-90 cursor-not-allowed"
              />
            </label>
          </div>

          <label className="flex flex-col gap-1 text-sm font-medium text-zinc-200">
            <span>Descricao</span>
            <textarea
              value={osDescricao}
              readOnly
              title="Campo preenchido automaticamente"
              className="w-full rounded-xl border border-zinc-800 bg-zinc-900 px-3 py-3 text-lg text-white placeholder:text-zinc-500 focus:border-blue-500 focus:outline-none min-h-[96px] opacity-90 cursor-not-allowed"
              placeholder="Descricao da OS"
            />
          </label>

          <div className="flex flex-col gap-1 text-sm font-medium text-zinc-200">
            <span>Condicao</span>
            <div className={`rounded-xl border border-zinc-800 px-3 py-3 text-lg ${statusClass}`}>
              {statusDisplay}
            </div>
          </div>
        </div>

        <div className="space-y-3 rounded-2xl border border-zinc-800 bg-zinc-950 p-4 shadow">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-semibold text-zinc-100">Itens</h2>
            <span className="text-xs text-zinc-500">adicione quantidades para baixar</span>
          </div>

          <div className="space-y-2">
            <div className="grid grid-cols-12 gap-2 text-[11px] font-semibold uppercase tracking-wide text-zinc-400 px-1">
              <span className="col-span-2">Codigo</span>
              <span className="col-span-5">Descricao</span>
              <span className="col-span-2 text-right">Estoque</span>
              <span className="col-span-3 text-right pr-1">Quantidade</span>
            </div>

            <div className="space-y-2">
              {rows.map((row, idx) => {
                const showRemove = !(idx === rows.length - 1 && isRowEmpty(row));

                return (
                  <div
                    key={row.id}
                    className="grid grid-cols-12 gap-2 rounded-xl border border-zinc-800 bg-zinc-900/70 p-3 shadow-sm px-1"
                  >
                    <div className="col-span-2 flex items-center">
                      <div className="relative w-full">
                        <input
                          value={row.codigo}
                          onChange={(e) => handleRowChange(row.id, "codigo", e.target.value)}
                          className="w-full rounded-lg bg-zinc-950 px-3 py-3 text-base text-white placeholder:text-zinc-500 focus:border focus:border-blue-500 focus:outline-none"
                          placeholder="ID do item"
                          autoComplete="off"
                          enterKeyHint="next"
                          inputMode="text"
                        />
                        {row.itemLoading && (
                          <span className="absolute right-3 top-1/2 -translate-y-1/2 text-[11px] text-blue-300">
                            carregando...
                          </span>
                        )}
                      </div>
                      {row.itemError && <span className="text-[11px] text-red-300">{row.itemError}</span>}
                    </div>

                    <div className="col-span-5 flex items-center">
                      <div
                        title="Campo preenchido automaticamente"
                        className="w-full px-2 py-2 text-base text-white opacity-90 cursor-not-allowed whitespace-pre-wrap break-words leading-relaxed min-h-[52px]"
                      >
                        {row.descricao || <span className="text-zinc-500">Descricao</span>}
                      </div>
                    </div>

                    <div className="col-span-2 flex items-center justify-end text-sm text-zinc-200">
                      {row.estoqueAtual !== null
                        ? row.estoqueAtual.toLocaleString("pt-BR", { minimumFractionDigits: 0 })
                        : "—"}
                    </div>

                    <div className="col-span-3 flex items-center gap-2 pr-1">
                      <input
                        value={row.quantidadeText}
                        onChange={(e) => handleRowChange(row.id, "quantidade", e.target.value)}
                        className="w-full rounded-lg bg-zinc-950 px-4 py-3 text-base text-white placeholder:text-zinc-500 focus:border focus:border-blue-500 focus:outline-none text-right border border-zinc-800/70"
                        placeholder="0,0"
                        inputMode="decimal"
                        enterKeyHint="next"
                      />
                      {showRemove && (
                        <button
                          type="button"
                          onClick={() => removeRow(row.id)}
                          className="shrink-0 rounded-full border border-red-900 bg-red-900/40 px-3 py-2 text-[11px] font-semibold text-red-100 hover:bg-red-900/60"
                        >
                          remover
                        </button>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>

        {success && (
          <div className="rounded-xl border border-emerald-900 bg-emerald-950 px-4 py-3 text-sm text-emerald-200">
            {success}
          </div>
        )}

        {error && (
          <div className="rounded-xl border border-red-900 bg-red-950 px-4 py-3 text-sm text-red-200">
            {error}
          </div>
        )}

        <button
          type="button"
          onClick={handleSubmit}
          disabled={!submitEnabled}
          className={`w-full rounded-2xl px-4 py-4 text-lg font-semibold text-white shadow-lg shadow-blue-500/20 ${
            submitEnabled ? "bg-blue-600 hover:bg-blue-500 active:translate-y-[1px]" : "bg-zinc-700 text-zinc-300"
          }`}
        >
          {submitting ? "Baixando..." : "Baixar Itens"}
        </button>
      </div>
    </div>
  );
}
