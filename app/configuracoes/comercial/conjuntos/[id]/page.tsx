"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import { mapOrcamentoError, toSupabaseErrorLike, upperTrim } from "@/lib/comercial/utils";
import { formatMoneyBR, parseMoneyBR, parseDecimalBR } from "@/lib/decimal";
import type { ConjuntoItemRow, ConjuntoRow } from "@/src/services/conjunto";
import {
  createConjunto,
  getConjunto,
  insertConjuntoItem,
  listConjuntoItens,
  softDeleteConjuntoItens,
  updateConjunto,
  updateConjuntoItem,
} from "@/src/services/conjunto";

function hasAny(caps: Capabilities | null, keys: CapabilityKey[]): boolean {
  return requireAny(caps, keys);
}

type FormState = {
  codigo: string;
  nome: string;
  categoria: string;
  precificacao: string;
  preco_fixo: string;
  ativo: boolean;
  descricao: string;
  observacoes: string;
};

type ItemSuggest = { id: number; codigo_interno: string | null; nome: string | null };

type ItemFormRow = {
  localKey: string;
  id?: string;
  ordem: string;
  item_id: string;
  item_label: string;
  quantidade: string;
};

function emptyForm(): FormState {
  return {
    codigo: "",
    nome: "",
    categoria: "",
    precificacao: "PRECO_FIXO",
    preco_fixo: "0,00",
    ativo: true,
    descricao: "",
    observacoes: "",
  };
}

function rowKey(): string {
  return `${Date.now()}_${Math.random().toString(16).slice(2)}`;
}

function normalizePrecificacao(v: string): string {
  const up = String(v ?? "").trim().toUpperCase();
  if (up === "PRECO_FIXO") return "PRECO_FIXO";
  if (up === "SOMA_COMPONENTES") return "SOMA_COMPONENTES";
  if (up === "SOMA_ITENS") return "SOMA_ITENS";
  return up;
}

export default function ConjuntoEditPage({ params }: { params: { id: string } }) {
  const idParam = String(params.id ?? "");
  const isNew = idParam === "novo";
  const router = useRouter();

  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const te = useTenantEmpresa();
  const tenantId = te.tenantId;
  const empresaId = te.empresaId;

  const { loading: permissionsLoading, ready, capabilities } = usePermissions();
  const canView = hasAny(capabilities, ["financeiro.config", "financeiro.write", "os.write"]);

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const [conjunto, setConjunto] = useState<ConjuntoRow | null>(null);
  const [form, setForm] = useState<FormState>(emptyForm());
  const [itens, setItens] = useState<ItemFormRow[]>([]);
  const removedItemIdsRef = useRef<Set<string>>(new Set());

  const [suggestBusyKey, setSuggestBusyKey] = useState<string | null>(null);
  const [suggestKey, setSuggestKey] = useState<string | null>(null);
  const [suggestTerm, setSuggestTerm] = useState<string>("");
  const [suggestRows, setSuggestRows] = useState<ItemSuggest[]>([]);
  const suggestReqRef = useRef(0);

  const load = useCallback(async () => {
    setErr(null);
    setOk(null);

    if (!supabase) return;
    if (te.loading) return;

    if (!tenantId || !empresaId) {
      setLoading(false);
      setErr("Contexto (tenant/empresa) não carregado.");
      return;
    }

    if (isNew) {
      setLoading(false);
      setConjunto(null);
      setForm(emptyForm());
      setItens([]);
      removedItemIdsRef.current = new Set();
      return;
    }

    setLoading(true);
    try {
      const c = await getConjunto(supabase, { tenantId, empresaId, id: idParam });
      setConjunto(c);
      setForm({
        codigo: c?.codigo ?? "",
        nome: c?.nome ?? "",
        categoria: c?.categoria ?? "",
        precificacao: String(c?.precificacao ?? "PRECO_FIXO"),
        preco_fixo: formatMoneyBR(Number(c?.preco_fixo ?? 0)),
        ativo: Boolean(c?.ativo ?? true),
        descricao: c?.descricao ?? "",
        observacoes: c?.observacoes ?? "",
      });

      const its = await listConjuntoItens(supabase, { tenantId, empresaId, conjuntoId: idParam });
      const ids = its.map((r) => Number(r.item_id)).filter((n) => Number.isFinite(n) && n > 0);
      const labelMap = new Map<number, string>();
      if (ids.length > 0) {
        const { data: itemRows } = await supabase
          .from("itens")
          .select("id,codigo_interno,nome")
          .in("id", ids)
          .limit(5000);
        const typedRows = (itemRows ?? []) as ItemSuggest[];
        typedRows.forEach((it) => {
          const id = Number(it.id);
          if (!Number.isFinite(id) || id <= 0) return;
          const codigo = String(it.codigo_interno ?? "").trim();
          const nome = String(it.nome ?? "").trim();
          labelMap.set(id, [codigo, nome].filter(Boolean).join(" — ") || String(id));
        });
      }

      setItens(
        its.map((r) => {
          const itemIdNum = Number(r.item_id);
          return {
            localKey: rowKey(),
            id: r.id,
            ordem: r.ordem === null || r.ordem === undefined ? "" : String(r.ordem),
            item_id: String(r.item_id ?? ""),
            item_label: labelMap.get(itemIdNum) ?? "",
            quantidade: r.quantidade === null || r.quantidade === undefined ? "" : String(r.quantidade),
          } satisfies ItemFormRow;
        })
      );
      removedItemIdsRef.current = new Set();
    } catch (e: unknown) {
      setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao carregar conjunto."));
      setConjunto(null);
      setItens([]);
    } finally {
      setLoading(false);
    }
  }, [empresaId, idParam, isNew, supabase, te.loading, tenantId]);

  useEffect(() => {
    void load();
  }, [load]);

  // autocomplete suggestions for a specific row
  useEffect(() => {
    if (!supabase) return;
    const key = suggestKey;
    if (!key) return;
    const term = suggestTerm.trim();
    const reqId = ++suggestReqRef.current;

    const t = setTimeout(async () => {
      if (!term) {
        if (reqId === suggestReqRef.current) setSuggestRows([]);
        return;
      }
      setSuggestBusyKey(key);
      try {
        let q = supabase.from("itens").select("id,codigo_interno,nome").eq("ativo", true);
        q = q.or(`codigo_interno.ilike.%${term}%,nome.ilike.%${term}%`);
        const { data, error } = await q.order("nome", { ascending: true }).limit(15);
        if (reqId !== suggestReqRef.current) return;
        if (error) {
          setSuggestRows([]);
        } else {
          setSuggestRows((data ?? []) as ItemSuggest[]);
        }
      } finally {
        if (reqId === suggestReqRef.current) setSuggestBusyKey(null);
      }
    }, 250);

    return () => clearTimeout(t);
  }, [suggestKey, suggestTerm, supabase]);

  const addItemRow = useCallback(() => {
    setItens((p) => [
      ...p,
      {
        localKey: rowKey(),
        ordem: String(p.length + 1),
        item_id: "",
        item_label: "",
        quantidade: "1",
      },
    ]);
  }, []);

  const removeItemRow = useCallback((localKey: string) => {
    setItens((p) => {
      const row = p.find((x) => x.localKey === localKey);
      if (row?.id) removedItemIdsRef.current.add(row.id);
      return p.filter((x) => x.localKey !== localKey);
    });
    if (suggestKey === localKey) {
      setSuggestKey(null);
      setSuggestTerm("");
      setSuggestRows([]);
    }
  }, [suggestKey]);

  const pickSuggestion = useCallback((localKey: string, it: ItemSuggest) => {
    const id = Number(it.id);
    const codigo = String(it.codigo_interno ?? "").trim();
    const nome = String(it.nome ?? "").trim();
    const label = [codigo, nome].filter(Boolean).join(" — ") || String(id);
    setItens((p) => p.map((r) => (r.localKey === localKey ? { ...r, item_id: String(id), item_label: label } : r)));
    setSuggestKey(null);
    setSuggestTerm("");
    setSuggestRows([]);
  }, []);

  const save = useCallback(
    async (e: FormEvent) => {
      e.preventDefault();
      if (!supabase || !tenantId || !empresaId) return;

      const codigo = upperTrim(form.codigo);
      const nome = String(form.nome ?? "").trim();
      if (!codigo) {
        setErr("Informe o código.");
        return;
      }
      if (!nome) {
        setErr("Informe o nome.");
        return;
      }

      const precificacao = normalizePrecificacao(form.precificacao);
      const precoFixo = parseMoneyBR(form.preco_fixo);
      if (precificacao === "PRECO_FIXO" && (!Number.isFinite(precoFixo) || precoFixo < 0)) {
        setErr("Preço fixo inválido.");
        return;
      }

      // validate itens
      for (const r of itens) {
        const itemIdNum = Number(String(r.item_id ?? "").trim());
        if (!Number.isFinite(itemIdNum) || itemIdNum <= 0) {
          setErr("Informe um item válido em todos os componentes.");
          return;
        }
        const qtd = parseDecimalBR(String(r.quantidade ?? "").trim());
        if (!Number.isFinite(qtd) || qtd <= 0) {
          setErr("Quantidade deve ser maior que 0 em todos os componentes.");
          return;
        }
        const ordem = r.ordem.trim() ? Number(r.ordem) : null;
        if (r.ordem.trim() && (!Number.isFinite(ordem as number) || !Number.isInteger(ordem as number) || (ordem as number) < 0)) {
          setErr("Ordem deve ser um inteiro maior ou igual a 0.");
          return;
        }
      }

      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        let currentId = conjunto?.id ?? null;
        if (isNew) {
          const created = await createConjunto(supabase, {
            tenantId,
            empresaId,
            payload: {
              codigo,
              nome,
              categoria: form.categoria.trim() ? upperTrim(form.categoria) : null,
              precificacao,
              preco_fixo: precificacao === "PRECO_FIXO" ? precoFixo : null,
              ativo: Boolean(form.ativo),
              descricao: form.descricao.trim() ? String(form.descricao).trim() : null,
              observacoes: form.observacoes.trim() ? String(form.observacoes).trim() : null,
            },
          });
          currentId = created.id;
          setConjunto(created);
        } else if (conjunto?.id) {
          await updateConjunto(supabase, {
            tenantId,
            empresaId,
            id: conjunto.id,
            patch: {
              codigo,
              nome,
              categoria: form.categoria.trim() ? upperTrim(form.categoria) : null,
              precificacao,
              preco_fixo: precificacao === "PRECO_FIXO" ? precoFixo : null,
              ativo: Boolean(form.ativo),
              descricao: form.descricao.trim() ? String(form.descricao).trim() : null,
              observacoes: form.observacoes.trim() ? String(form.observacoes).trim() : null,
            },
          });
        }

        if (!currentId) throw new Error("ID do conjunto não disponível.");

        // Soft delete removed rows
        const removedIds = Array.from(removedItemIdsRef.current);
        await softDeleteConjuntoItens(supabase, { tenantId, empresaId, ids: removedIds });
        removedItemIdsRef.current = new Set();

        // Upsert remaining rows
        for (const r of itens) {
          const ordem = r.ordem.trim() ? Number(r.ordem) : null;
          const itemIdNum = Number(String(r.item_id ?? "").trim());
          const qtd = parseDecimalBR(String(r.quantidade ?? "").trim());

          const payload = {
            ordem: ordem === null ? null : (ordem as number),
            item_id: itemIdNum,
            quantidade: qtd,
          } satisfies Pick<ConjuntoItemRow, "ordem" | "item_id" | "quantidade">;

          if (r.id) {
            await updateConjuntoItem(supabase, { tenantId, empresaId, id: r.id, patch: payload });
          } else {
            await insertConjuntoItem(supabase, { tenantId, empresaId, conjuntoId: currentId, payload });
          }
        }

        setOk("Conjunto salvo.");
        if (isNew && currentId) {
          router.replace(`/configuracoes/comercial/conjuntos/${currentId}`);
        } else {
          await load();
        }
      } catch (e2: unknown) {
        setErr(mapOrcamentoError(toSupabaseErrorLike(e2), "Erro ao salvar."));
      } finally {
        setBusy(false);
      }
    },
    [conjunto?.id, empresaId, form, isNew, itens, load, router, supabase, tenantId]
  );

  if (!ready && permissionsLoading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando permissões...</div>;
  }

  if (!canView) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>;
  }

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">{isNew ? "Novo Conjunto" : "Editar Conjunto"}</h1>
          <p className="text-sm text-zinc-400 mt-1">Defina os dados e os itens componentes do kit.</p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href="/configuracoes/comercial/conjuntos"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Voltar
          </Link>
          <button
            type="button"
            onClick={() => void load()}
            disabled={busy}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
          >
            Atualizar
          </button>
        </div>
      </div>

      {err && <div className="text-sm text-red-400">{err}</div>}
      {ok && <div className="text-sm text-emerald-300">{ok}</div>}
      {loading && <div className="text-sm text-zinc-400">Carregando...</div>}

      {!loading && (
        <form onSubmit={save} className="space-y-4">
          <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              <label className="block text-xs text-zinc-400">
                Código
                <input
                  value={form.codigo}
                  onChange={(e) => setForm((p) => ({ ...p, codigo: e.target.value }))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="block text-xs text-zinc-400 md:col-span-2">
                Nome
                <input
                  value={form.nome}
                  onChange={(e) => setForm((p) => ({ ...p, nome: e.target.value }))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              <label className="block text-xs text-zinc-400">
                Categoria
                <input
                  value={form.categoria}
                  onChange={(e) => setForm((p) => ({ ...p, categoria: e.target.value }))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>

              <label className="block text-xs text-zinc-400">
                Precificação
                <select
                  value={form.precificacao}
                  onChange={(e) => setForm((p) => ({ ...p, precificacao: e.target.value }))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
                >
                  <option value="PRECO_FIXO">PRECO_FIXO</option>
                  <option value="SOMA_COMPONENTES">SOMA_COMPONENTES</option>
                </select>
              </label>

              <label className="block text-xs text-zinc-400">
                Preço fixo
                <input
                  value={form.preco_fixo}
                  onChange={(e) => setForm((p) => ({ ...p, preco_fixo: e.target.value }))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                  disabled={normalizePrecificacao(form.precificacao) !== "PRECO_FIXO"}
                />
                {normalizePrecificacao(form.precificacao) === "PRECO_FIXO" && (
                  <div className="text-[11px] text-zinc-500 mt-1">Sugestão: {formatMoneyBR(parseMoneyBR(form.preco_fixo) || 0)}</div>
                )}
              </label>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              <label className="flex items-center gap-2 text-sm text-zinc-200">
                <input
                  type="checkbox"
                  checked={form.ativo}
                  onChange={(e) => setForm((p) => ({ ...p, ativo: e.target.checked }))}
                />
                Ativo
              </label>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <label className="block text-xs text-zinc-400">
                Descrição
                <textarea
                  value={form.descricao}
                  onChange={(e) => setForm((p) => ({ ...p, descricao: e.target.value }))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm min-h-[96px]"
                />
              </label>

              <label className="block text-xs text-zinc-400">
                Observações
                <textarea
                  value={form.observacoes}
                  onChange={(e) => setForm((p) => ({ ...p, observacoes: e.target.value }))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm min-h-[96px]"
                />
              </label>
            </div>
          </div>

          <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-3">
            <div className="flex items-center justify-between gap-2 flex-wrap">
              <div>
                <div className="text-lg font-semibold">Itens do Conjunto</div>
                <div className="text-sm text-zinc-400">Ordem, item e quantidade. Remoção é soft delete.</div>
              </div>
              <button
                type="button"
                onClick={addItemRow}
                className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium"
              >
                Adicionar item
              </button>
            </div>

            <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
              <div className="overflow-auto">
                <table className="w-full text-sm">
                  <thead className="bg-zinc-900/70">
                    <tr className="text-zinc-200">
                      <th className="px-3 py-3 text-left whitespace-nowrap w-24">Ordem</th>
                      <th className="px-3 py-3 text-left whitespace-nowrap">Item</th>
                      <th className="px-3 py-3 text-left whitespace-nowrap w-36">Quantidade</th>
                      <th className="px-3 py-3 text-right whitespace-nowrap w-24">Ações</th>
                    </tr>
                  </thead>
                  <tbody>
                    {itens.length === 0 && (
                      <tr>
                        <td colSpan={4} className="px-3 py-6 text-zinc-400">
                          Nenhum componente. Clique em “Adicionar item”.
                        </td>
                      </tr>
                    )}

                    {itens.map((r) => (
                      <tr key={r.localKey} className="border-t border-zinc-900/60 align-top">
                        <td className="px-3 py-2">
                          <input
                            value={r.ordem}
                            onChange={(e) => setItens((p) => p.map((x) => (x.localKey === r.localKey ? { ...x, ordem: e.target.value } : x)))}
                            className="w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2"
                          />
                        </td>
                        <td className="px-3 py-2">
                          <div className="space-y-1 relative">
                            <div className="grid grid-cols-1 md:grid-cols-[160px_1fr] gap-2">
                              <input
                                value={r.item_id}
                                onChange={(e) =>
                                  setItens((p) =>
                                    p.map((x) =>
                                      x.localKey === r.localKey ? { ...x, item_id: e.target.value, item_label: x.item_label } : x
                                    )
                                  )
                                }
                                className="w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2"
                                placeholder="item_id"
                              />
                              <input
                                value={suggestKey === r.localKey ? suggestTerm : ""}
                                onChange={(e) => {
                                  setSuggestKey(r.localKey);
                                  setSuggestTerm(e.target.value);
                                }}
                                onFocus={() => {
                                  setSuggestKey(r.localKey);
                                  setSuggestTerm("");
                                  setSuggestRows([]);
                                }}
                                className="w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2"
                                placeholder="Buscar item por código/nome"
                              />
                            </div>

                            {r.item_label && <div className="text-xs text-zinc-400">Selecionado: {r.item_label}</div>}

                            {suggestKey === r.localKey && (
                              <div className="absolute z-20 mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 shadow-lg overflow-hidden">
                                <div className="px-3 py-2 text-xs text-zinc-400 border-b border-zinc-900/60">
                                  {suggestBusyKey === r.localKey ? "Buscando..." : "Sugestões"}
                                </div>
                                <div className="max-h-56 overflow-auto">
                                  {suggestRows.length === 0 && (
                                    <div className="px-3 py-2 text-sm text-zinc-500">Sem resultados.</div>
                                  )}
                                  {suggestRows.map((it) => (
                                    <button
                                      type="button"
                                      key={it.id}
                                      onClick={() => pickSuggestion(r.localKey, it)}
                                      className="w-full text-left px-3 py-2 hover:bg-zinc-900/40"
                                    >
                                      <div className="text-sm text-zinc-100">
                                        {it.codigo_interno ?? ""} {it.nome ? `— ${it.nome}` : ""}
                                      </div>
                                      <div className="text-xs text-zinc-500">ID: {it.id}</div>
                                    </button>
                                  ))}
                                </div>
                              </div>
                            )}
                          </div>
                        </td>
                        <td className="px-3 py-2">
                          <input
                            value={r.quantidade}
                            onChange={(e) => setItens((p) => p.map((x) => (x.localKey === r.localKey ? { ...x, quantidade: e.target.value } : x)))}
                            className="w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2"
                          />
                        </td>
                        <td className="px-3 py-2 text-right">
                          <button
                            type="button"
                            onClick={() => removeItemRow(r.localKey)}
                            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
                          >
                            Remover
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="submit"
              disabled={busy}
              className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium text-sm disabled:opacity-60"
            >
              {busy ? "Salvando..." : "Salvar"}
            </button>
            <Link
              href="/configuracoes/comercial/conjuntos"
              className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
            >
              Cancelar
            </Link>
          </div>
        </form>
      )}
    </div>
  );
}
